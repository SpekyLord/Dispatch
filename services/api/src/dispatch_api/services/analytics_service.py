from __future__ import annotations

from collections import defaultdict
from datetime import UTC, datetime, timedelta
from typing import Any

# threshold (seconds) to consider a report "unattended"
UNATTENDED_THRESHOLD_SECONDS = 3600


class AnalyticsService:
    def __init__(self, client) -> None:
        self.client = client

    # -- filtered report listing for municipality dashboard --
    def get_municipality_reports(self, filters: dict[str, Any]) -> list[dict[str, Any]]:
        params: dict[str, str] = {"select": "*", "order": "created_at.desc"}

        if filters.get("status"):
            params["status"] = f"eq.{filters['status']}"
        if filters.get("category"):
            params["category"] = f"eq.{filters['category']}"
        if filters.get("date_from"):
            params["created_at"] = f"gte.{filters['date_from']}"
        if filters.get("date_to"):
            # combine with existing gte filter if present
            if "created_at" in params:
                params["and"] = (
                    f"(created_at.gte.{filters['date_from']},created_at.lte.{filters['date_to']})"
                )
                del params["created_at"]
            else:
                params["created_at"] = f"lte.{filters['date_to']}"
        if filters.get("is_escalated"):
            params["is_escalated"] = f"eq.{filters['is_escalated']}"

        return self.client.db_query("incident_reports", params=params, use_service_role=True)

    # -- compute aggregate analytics --
    def get_analytics(self) -> dict[str, Any]:
        reports = self.client.db_query(
            "incident_reports",
            params={"select": "*", "order": "created_at.desc"},
            use_service_role=True,
        )
        history = self.client.db_query(
            "report_status_history",
            params={"select": "*", "order": "created_at.asc"},
            use_service_role=True,
        )
        responses = self.client.db_query(
            "department_responses",
            params={"select": "*"},
            use_service_role=True,
        )

        total = len(reports)
        by_category = _count_by(reports, "category")
        by_status = _count_by(reports, "status")

        # time-period breakdowns
        now = datetime.now(tz=UTC)
        last_7 = sum(1 for r in reports if _within_days(r, 7, now))
        last_30 = sum(1 for r in reports if _within_days(r, 30, now))

        # response time metrics from status history
        response_times = _compute_response_times(history)

        # department activity from responses
        dept_activity = _compute_department_activity(responses)

        # unattended: pending status + no acceptance after threshold
        unattended = _count_unattended(reports, responses, now)

        return {
            "total_reports": total,
            "by_category": by_category,
            "by_status": by_status,
            "last_7_days": last_7,
            "last_30_days": last_30,
            "response_times": response_times,
            "department_activity": dept_activity,
            "unattended_reports": unattended,
        }


# -- helpers --


def _count_by(rows: list[dict], key: str) -> dict[str, int]:
    counts: dict[str, int] = defaultdict(int)
    for row in rows:
        val = row.get(key) or "unknown"
        counts[val] += 1
    return dict(counts)


def _within_days(report: dict, days: int, now: datetime) -> bool:
    created = report.get("created_at")
    if not created:
        return False
    try:
        dt = datetime.fromisoformat(created.replace("Z", "+00:00"))
        return (now - dt) <= timedelta(days=days)
    except (ValueError, AttributeError):
        return False


def _compute_response_times(history: list[dict]) -> dict[str, float | None]:
    """Avg seconds between status transitions per report."""
    # group history entries by report
    by_report: dict[str, list[dict]] = defaultdict(list)
    for entry in history:
        rid = entry.get("report_id")
        if rid:
            by_report[rid].append(entry)

    create_to_accept: list[float] = []
    accept_to_responding: list[float] = []
    responding_to_resolved: list[float] = []

    for entries in by_report.values():
        timestamps: dict[str, datetime] = {}
        for e in entries:
            status = e.get("new_status") or e.get("status")
            ts = e.get("created_at")
            if status and ts:
                try:
                    timestamps.setdefault(status, datetime.fromisoformat(ts.replace("Z", "+00:00")))
                except (ValueError, AttributeError):
                    pass

        # creation→accepted
        if "pending" in timestamps and "accepted" in timestamps:
            delta = (timestamps["accepted"] - timestamps["pending"]).total_seconds()
            if delta >= 0:
                create_to_accept.append(delta)
        # accepted→responding
        if "accepted" in timestamps and "responding" in timestamps:
            delta = (timestamps["responding"] - timestamps["accepted"]).total_seconds()
            if delta >= 0:
                accept_to_responding.append(delta)
        # responding→resolved
        if "responding" in timestamps and "resolved" in timestamps:
            delta = (timestamps["resolved"] - timestamps["responding"]).total_seconds()
            if delta >= 0:
                responding_to_resolved.append(delta)

    return {
        "avg_create_to_accept": _safe_avg(create_to_accept),
        "avg_accept_to_responding": _safe_avg(accept_to_responding),
        "avg_responding_to_resolved": _safe_avg(responding_to_resolved),
    }


def _safe_avg(values: list[float]) -> float | None:
    return round(sum(values) / len(values), 2) if values else None


def _compute_department_activity(responses: list[dict]) -> list[dict[str, Any]]:
    """Count accepts/declines per department."""
    activity: dict[str, dict[str, int]] = defaultdict(lambda: {"accepted": 0, "declined": 0})
    for r in responses:
        dept_id = r.get("department_id")
        action = r.get("action") or r.get("response_status") or r.get("status")
        if dept_id and action in ("accepted", "declined"):
            activity[dept_id][action] += 1

    return [{"department_id": did, **counts} for did, counts in activity.items()]


def _count_unattended(
    reports: list[dict],
    responses: list[dict],
    now: datetime,
) -> int:
    """Reports still pending with no acceptance past threshold."""
    # set of report ids that have at least one acceptance
    accepted_ids = {
        r["report_id"]
        for r in responses
        if r.get("action") == "accepted" or r.get("response_status") == "accepted"
    }

    count = 0
    for report in reports:
        if report.get("status") not in ("pending", "submitted"):
            continue
        if report.get("id") in accepted_ids:
            continue
        created = report.get("created_at")
        if not created:
            count += 1
            continue
        try:
            dt = datetime.fromisoformat(created.replace("Z", "+00:00"))
            if (now - dt).total_seconds() > UNATTENDED_THRESHOLD_SECONDS:
                count += 1
        except (ValueError, AttributeError):
            count += 1

    return count
