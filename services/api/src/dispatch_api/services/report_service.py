from __future__ import annotations

import json
import re
from collections import defaultdict
from datetime import UTC, datetime, timedelta
from http import HTTPStatus
from typing import Any
from urllib.parse import unquote, urlparse

from dispatch_api.errors import ApiError
from dispatch_api.services.notification_service import NotificationService

ESCALATION_THRESHOLD_SECONDS = 120
VALID_CATEGORIES = {
    "fire",
    "flood",
    "earthquake",
    "road_accident",
    "medical",
    "structural",
    "other",
}
VALID_SEVERITIES = {"low", "medium", "high", "critical"}
DEPARTMENT_STATUS_ORDER = {"accepted": 0, "declined": 1, "pending": 2}
CATEGORY_KEYWORDS = {
    "fire": ("fire", "sunog", "blaze", "smoke", "usok", "burning"),
    "flood": ("flood", "baha", "rising water", "submerged", "tubig"),
    "earthquake": ("earthquake", "lindol", "shaking", "collapsed", "gumuho"),
    "road_accident": ("accident", "car crash", "vehicular", "banggaan", "nasagasaan"),
    "medical": ("medical", "injured", "sugatan", "unconscious", "hinimatay", "bleeding"),
    "structural": ("collapsed building", "crack", "sira", "gumiba", "landslide"),
}
CATEGORY_ROUTING = {
    "fire": {"primary": ("fire",), "escalation": ("disaster",)},
    "flood": {"primary": ("disaster",), "escalation": ()},
    "earthquake": {"primary": ("disaster",), "escalation": ()},
    "road_accident": {"primary": ("police",), "escalation": ("disaster",)},
    "medical": {"primary": ("medical", "rescue"), "escalation": ("disaster",)},
    "structural": {"primary": ("disaster",), "escalation": ()},
    "other": {"primary": ("disaster",), "escalation": ()},
}


def _parse_datetime(value: str | None) -> datetime:
    if not value:
        return datetime.min.replace(tzinfo=UTC)
    normalized = value.replace("Z", "+00:00")
    parsed = datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC)


def _utc_now() -> datetime:
    return datetime.now(tz=UTC)


class ReportService:
    def __init__(self, client, notification_service: NotificationService) -> None:
        self.client = client
        self.notification_service = notification_service

    def categorize_description(self, description: str) -> str:
        normalized = " ".join(description.casefold().split())
        best_category = "other"
        best_score = 0

        for category, keywords in CATEGORY_KEYWORDS.items():
            score = sum(1 for keyword in keywords if keyword in normalized)
            if score > best_score:
                best_category = category
                best_score = score

        return best_category

    def create_report(
        self,
        *,
        reporter_id: str,
        title: str | None,
        description: str,
        category: str | None,
        severity: str,
        latitude: float | None,
        longitude: float | None,
        address: str | None,
        image_urls: list[str],
    ) -> dict[str, Any]:
        if not description:
            raise ApiError("Description is required.", code="validation_error")
        if category and category not in VALID_CATEGORIES:
            raise ApiError(
                f"Category must be one of: {', '.join(sorted(VALID_CATEGORIES))}.",
                code="validation_error",
            )
        if severity not in VALID_SEVERITIES:
            raise ApiError(
                f"Severity must be one of: {', '.join(sorted(VALID_SEVERITIES))}.",
                code="validation_error",
            )

        final_category = category or self.categorize_description(description)
        rows = self.client.db_insert(
            "incident_reports",
            data={
                "reporter_id": reporter_id,
                "title": self._build_title(title=title, description=description),
                "description": description,
                "category": final_category,
                "severity": severity,
                "status": "pending",
                "is_escalated": False,
                "image_urls": image_urls,
                "latitude": latitude,
                "longitude": longitude,
                "address": address or None,
            },
            use_service_role=True,
        )
        if not rows:
            raise ApiError("Failed to create report.", code="create_failed")

        report = self._normalize_report_record(rows[0])
        self.record_status_history(
            report_id=report["id"],
            old_status=None,
            new_status="pending",
            changed_by=reporter_id,
            notes="Report submitted.",
        )

        departments = self._primary_departments(report["category"])
        self.notification_service.notify_relevant_departments(
            report=report, departments=departments
        )
        return report

    def list_department_reports(
        self,
        *,
        department: dict[str, Any],
        status: str | None = None,
        category: str | None = None,
    ) -> list[dict[str, Any]]:
        self.scan_pending_timeouts()

        reports = self._all_reports()
        responses = self._latest_responses_by_report()
        visible_reports = [
            self._serialize_department_report(
                report=report,
                department=department,
                latest_responses=responses.get(report["id"], {}),
            )
            for report in reports
            if self.is_report_visible_to_department(report=report, department=department)
        ]

        if status:
            visible_reports = [
                report for report in visible_reports if report.get("status") == status
            ]
        if category:
            visible_reports = [
                report for report in visible_reports if report.get("category") == category
            ]

        return visible_reports

    def list_municipality_escalated_reports(self) -> list[dict[str, Any]]:
        self.scan_pending_timeouts()

        responses = self._latest_responses_by_report()
        escalated_reports: list[dict[str, Any]] = []
        for report in self._all_reports():
            if not report.get("is_escalated") or report.get("status") == "resolved":
                continue

            escalated_reports.append(
                {
                    **report,
                    "response_summary": self._build_response_summary(
                        report=report,
                        latest_responses=responses.get(report["id"], {}),
                    ),
                }
            )

        return escalated_reports

    def get_department_response_roster(
        self,
        *,
        report_id: str,
        department: dict[str, Any],
    ) -> dict[str, Any]:
        self.scan_pending_timeouts()
        report = self.get_report_for_department(report_id=report_id, department=department)
        latest_responses = self._latest_responses_for_report(report_id)
        visible_departments = self._visible_departments_for_report(report)

        roster = []
        for peer in visible_departments:
            latest_response = latest_responses.get(peer["id"])
            state = latest_response.get("action") if latest_response else "pending"
            roster.append(
                {
                    "department_id": peer["id"],
                    "department_name": peer.get("name"),
                    "department_type": peer.get("type"),
                    "state": state,
                    "decline_reason": (latest_response or {}).get("decline_reason"),
                    "notes": (latest_response or {}).get("notes"),
                    "responded_at": (latest_response or {}).get("responded_at"),
                    "is_requesting_department": peer["id"] == department["id"],
                }
            )

        roster.sort(
            key=lambda row: (
                DEPARTMENT_STATUS_ORDER.get(row["state"], 99),
                row.get("department_name") or "",
            )
        )
        return {"report": report, "responses": roster}

    def get_report_for_department(
        self, *, report_id: str, department: dict[str, Any]
    ) -> dict[str, Any]:
        report = self.get_report(report_id)
        if not self.is_report_visible_to_department(report=report, department=department):
            raise ApiError(
                "You do not have permission to view this report.",
                code="forbidden",
                status_code=HTTPStatus.FORBIDDEN,
            )
        return report

    def get_report(self, report_id: str) -> dict[str, Any]:
        rows = self.client.db_query(
            "incident_reports",
            params={"select": "*", "id": f"eq.{report_id}"},
            use_service_role=True,
        )
        if not rows:
            raise ApiError("Report not found.", code="not_found", status_code=HTTPStatus.NOT_FOUND)
        return self._normalize_report_record(rows[0])

    def accept_report(
        self,
        *,
        report_id: str,
        department: dict[str, Any],
        actor_user_id: str,
        notes: str | None = None,
    ) -> dict[str, Any]:
        report = self.get_report_for_department(report_id=report_id, department=department)
        self._ensure_report_is_open(report)

        response = self._append_department_response(
            report_id=report_id,
            department_id=department["id"],
            action="accepted",
            decline_reason=None,
            notes=notes,
        )

        if report.get("status") == "pending":
            report = self._update_report_status(
                report=report,
                old_status="pending",
                new_status="accepted",
                changed_by=actor_user_id,
                notes="First department accepted the report.",
            )
            self.notification_service.notify_reporter_status_update(
                report=report,
                message="A department accepted your report.",
            )

        return {"report": report, "response": response}

    def decline_report(
        self,
        *,
        report_id: str,
        department: dict[str, Any],
        decline_reason: str,
        notes: str | None = None,
    ) -> dict[str, Any]:
        if not decline_reason:
            raise ApiError(
                "A decline reason is required when declining a report.",
                code="validation_error",
            )

        report = self.get_report_for_department(report_id=report_id, department=department)
        self._ensure_report_is_open(report)

        response = self._append_department_response(
            report_id=report_id,
            department_id=department["id"],
            action="declined",
            decline_reason=decline_reason,
            notes=notes,
        )
        report = self._maybe_escalate(report)
        return {"report": report, "response": response}

    def update_status(
        self,
        *,
        report_id: str,
        department: dict[str, Any],
        actor_user_id: str,
        new_status: str,
        notes: str | None = None,
    ) -> dict[str, Any]:
        if new_status not in {"responding", "resolved"}:
            raise ApiError(
                "Status must be either 'responding' or 'resolved'.",
                code="validation_error",
            )

        report = self.get_report_for_department(report_id=report_id, department=department)
        current_response = self._latest_responses_for_report(report_id).get(department["id"])
        if (current_response or {}).get("action") != "accepted":
            raise ApiError(
                "Only departments with an accepted response can update report status.",
                code="validation_error",
                status_code=HTTPStatus.FORBIDDEN,
            )

        allowed_transitions = {
            "accepted": {"responding"},
            "responding": {"resolved"},
        }
        current_status = report.get("status")
        if current_status == new_status:
            return report
        if new_status not in allowed_transitions.get(current_status, set()):
            raise ApiError(
                f"Cannot move a report from {current_status!r} to {new_status!r}.",
                code="validation_error",
            )

        updated = self._update_report_status(
            report=report,
            old_status=current_status,
            new_status=new_status,
            changed_by=actor_user_id,
            notes=notes or f"Report marked as {new_status}.",
        )
        self.notification_service.notify_reporter_status_update(
            report=updated,
            message=f"Your report is now marked as {new_status}.",
        )
        return updated

    def scan_pending_timeouts(self) -> list[dict[str, Any]]:
        escalated_reports: list[dict[str, Any]] = []
        for report in self._all_reports():
            if report.get("status") != "pending" or report.get("is_escalated"):
                continue

            created_at = _parse_datetime(report.get("created_at"))
            if created_at > _utc_now() - timedelta(seconds=ESCALATION_THRESHOLD_SECONDS):
                continue

            latest_responses = self._latest_responses_for_report(report["id"])
            if any(response.get("action") == "accepted" for response in latest_responses.values()):
                continue

            escalated_reports.append(
                self._escalate_report(report, reason="No department accepted within 120 seconds.")
            )

        return escalated_reports

    def record_status_history(
        self,
        *,
        report_id: str,
        old_status: str | None,
        new_status: str,
        changed_by: str,
        notes: str | None,
    ) -> None:
        self.client.db_insert(
            "report_status_history",
            data={
                "report_id": report_id,
                "old_status": old_status,
                "new_status": new_status,
                "changed_by": changed_by,
                "notes": notes,
            },
            use_service_role=True,
            return_repr=False,
        )

    def is_report_visible_to_department(
        self, *, report: dict[str, Any], department: dict[str, Any]
    ) -> bool:
        routing = CATEGORY_ROUTING.get(report.get("category", "other"), CATEGORY_ROUTING["other"])
        department_type = department.get("type")
        if department_type in routing["primary"]:
            return True
        return bool(report.get("is_escalated") and department_type in routing["escalation"])

    def _all_reports(self) -> list[dict[str, Any]]:
        rows = self.client.db_query(
            "incident_reports",
            params={"select": "*", "order": "created_at.desc"},
            use_service_role=True,
        )
        normalized_rows = [self._normalize_report_record(row) for row in rows]
        return sorted(normalized_rows, key=lambda row: row.get("created_at") or "", reverse=True)

    def _append_department_response(
        self,
        *,
        report_id: str,
        department_id: str,
        action: str,
        decline_reason: str | None,
        notes: str | None,
    ) -> dict[str, Any]:
        rows = self.client.db_insert(
            "department_responses",
            data={
                "report_id": report_id,
                "department_id": department_id,
                "action": action,
                "decline_reason": decline_reason,
                "notes": notes,
                "responded_at": _utc_now().isoformat(),
            },
            use_service_role=True,
        )
        if not rows:
            raise ApiError("Failed to save department response.", code="create_failed")
        return rows[0]

    def _maybe_escalate(self, report: dict[str, Any]) -> dict[str, Any]:
        latest_responses = self._latest_responses_for_report(report["id"])
        primary_departments = self._primary_departments(report["category"])
        if report.get("status") != "pending" or report.get("is_escalated"):
            return report

        if not primary_departments:
            return report

        if all(
            latest_responses.get(department["id"], {}).get("action") == "declined"
            for department in primary_departments
        ):
            return self._escalate_report(
                report, reason="All primary departments declined the report."
            )
        return report

    def _escalate_report(self, report: dict[str, Any], *, reason: str) -> dict[str, Any]:
        updated_rows = self.client.db_update(
            "incident_reports",
            data={"is_escalated": True},
            params={"id": f"eq.{report['id']}"},
            use_service_role=True,
        )
        updated = (
            self._normalize_report_record(updated_rows[0])
            if updated_rows
            else self._normalize_report_record({**report, "is_escalated": True})
        )

        municipality_users = self.notification_service.list_users_by_role("municipality")
        self.notification_service.notify_report_escalated(
            report=updated, municipality_users=municipality_users
        )

        escalation_departments = self._escalation_departments(updated["category"])
        if escalation_departments:
            self.notification_service.notify_relevant_departments(
                report=updated,
                departments=escalation_departments,
                message="This incident was escalated and is now visible to your department.",
            )

        self.notification_service.notify_reporter_status_update(
            report=updated,
            message=f"Your report was escalated. {reason}",
        )
        return updated

    def _update_report_status(
        self,
        *,
        report: dict[str, Any],
        old_status: str | None,
        new_status: str,
        changed_by: str,
        notes: str | None,
    ) -> dict[str, Any]:
        update_data: dict[str, Any] = {"status": new_status}
        if new_status == "resolved":
            update_data["resolved_at"] = _utc_now().isoformat()

        rows = self.client.db_update(
            "incident_reports",
            data=update_data,
            params={"id": f"eq.{report['id']}"},
            use_service_role=True,
        )
        if not rows:
            raise ApiError("Failed to update report.", code="update_failed")

        updated = self._normalize_report_record(rows[0])
        self.record_status_history(
            report_id=report["id"],
            old_status=old_status,
            new_status=new_status,
            changed_by=changed_by,
            notes=notes,
        )
        return updated

    def _latest_responses_by_report(self) -> dict[str, dict[str, dict[str, Any]]]:
        grouped: dict[str, dict[str, dict[str, Any]]] = defaultdict(dict)
        rows = self.client.db_query(
            "department_responses",
            params={"select": "*", "order": "responded_at.desc"},
            use_service_role=True,
        )
        for row in sorted(
            rows,
            key=lambda response: (
                _parse_datetime(
                    response.get("responded_at") or response.get("created_at")
                ).timestamp(),
                response.get("id") or "",
            ),
            reverse=True,
        ):
            report_id = row.get("report_id")
            department_id = row.get("department_id")
            if report_id is None or department_id is None:
                continue
            grouped[report_id].setdefault(department_id, row)
        return grouped

    def _latest_responses_for_report(self, report_id: str) -> dict[str, dict[str, Any]]:
        return self._latest_responses_by_report().get(report_id, {})

    def _visible_departments_for_report(self, report: dict[str, Any]) -> list[dict[str, Any]]:
        department_types = set(
            CATEGORY_ROUTING.get(report["category"], CATEGORY_ROUTING["other"])["primary"]
        )
        if report.get("is_escalated"):
            department_types.update(
                CATEGORY_ROUTING.get(report["category"], CATEGORY_ROUTING["other"])["escalation"]
            )
        departments = self.client.db_query(
            "departments",
            params={"select": "*", "order": "name.asc"},
            use_service_role=True,
        )
        return [
            department
            for department in departments
            if department.get("verification_status") == "approved"
            and department.get("type") in department_types
        ]

    def _primary_departments(self, category: str) -> list[dict[str, Any]]:
        routing = CATEGORY_ROUTING.get(category, CATEGORY_ROUTING["other"])
        return [
            department
            for department in self._approved_departments()
            if department.get("type") in routing["primary"]
        ]

    def _escalation_departments(self, category: str) -> list[dict[str, Any]]:
        routing = CATEGORY_ROUTING.get(category, CATEGORY_ROUTING["other"])
        return [
            department
            for department in self._approved_departments()
            if department.get("type") in routing["escalation"]
        ]

    def _approved_departments(self) -> list[dict[str, Any]]:
        rows = self.client.db_query(
            "departments",
            params={"select": "*", "order": "name.asc"},
            use_service_role=True,
        )
        return [row for row in rows if row.get("verification_status") == "approved"]

    def _serialize_department_report(
        self,
        *,
        report: dict[str, Any],
        department: dict[str, Any],
        latest_responses: dict[str, dict[str, Any]],
    ) -> dict[str, Any]:
        routing = CATEGORY_ROUTING.get(report.get("category", "other"), CATEGORY_ROUTING["other"])
        visible_via = "primary"
        if report.get("is_escalated") and department.get("type") in routing["escalation"]:
            visible_via = "escalation"

        return {
            **report,
            "visible_via": visible_via,
            "current_response": latest_responses.get(department["id"]),
            "response_summary": self._build_response_summary(
                report=report,
                latest_responses=latest_responses,
            ),
        }

    def _build_response_summary(
        self,
        *,
        report: dict[str, Any],
        latest_responses: dict[str, dict[str, Any]],
    ) -> dict[str, int]:
        summary = {
            "accepted": 0,
            "declined": 0,
            "pending": max(
                len(self._visible_departments_for_report(report)) - len(latest_responses), 0
            ),
        }
        for response in latest_responses.values():
            action = response.get("action")
            if action in {"accepted", "declined"}:
                summary[action] += 1
        return summary

    def _ensure_report_is_open(self, report: dict[str, Any]) -> None:
        if report.get("status") == "resolved":
            raise ApiError(
                "Resolved reports can no longer be modified.",
                code="validation_error",
                status_code=HTTPStatus.CONFLICT,
            )

    def _build_title(self, *, title: str | None, description: str) -> str:
        if title:
            return title
        compact_description = " ".join(description.split())
        if len(compact_description) <= 80:
            return compact_description
        return f"{compact_description[:77].rstrip()}..."

    def _normalize_report_record(self, report: dict[str, Any]) -> dict[str, Any]:
        image_urls = [
            self._resolve_report_image_url(url)
            for url in self._normalize_image_urls(report.get("image_urls"))
        ]
        return {
            **report,
            "image_urls": [url for url in image_urls if url],
        }

    def _normalize_image_urls(self, value: Any) -> list[str]:
        if value is None:
            return []

        if isinstance(value, str):
            trimmed = value.strip()
            if not trimmed:
                return []
            if trimmed.startswith("[") and trimmed.endswith("]"):
                try:
                    parsed = json.loads(trimmed)
                except json.JSONDecodeError:
                    parsed = None
                if isinstance(parsed, list):
                    return [str(item).strip() for item in parsed if str(item).strip()]
            split_values = [item.strip() for item in re.split(r"[\r\n,]+", trimmed) if item.strip()]
            return split_values or [trimmed]

        if isinstance(value, list):
            normalized: list[str] = []
            for item in value:
                if item is None:
                    continue
                if isinstance(item, str):
                    trimmed = item.strip()
                    if not trimmed:
                        continue
                    if trimmed.startswith("[") and trimmed.endswith("]"):
                        try:
                            parsed = json.loads(trimmed)
                        except json.JSONDecodeError:
                            parsed = None
                        if isinstance(parsed, list):
                            normalized.extend(
                                str(parsed_item).strip()
                                for parsed_item in parsed
                                if str(parsed_item).strip()
                            )
                            continue
                    normalized.append(trimmed)
                    continue
                normalized.append(str(item).strip())
            return [item for item in normalized if item]

        fallback = str(value).strip()
        return [fallback] if fallback else []

    def _resolve_report_image_url(self, value: str) -> str:
        object_path = self._extract_report_image_object_path(value)
        if not object_path:
            return value

        signer = getattr(self.client, "storage_signed_url", None)
        if not callable(signer):
            return value

        try:
            return signer(bucket="report-images", object_path=object_path, expires_in=3600)
        except Exception:
            return value

    def _extract_report_image_object_path(self, value: str) -> str | None:
        trimmed = value.strip().strip("'\"")
        if not trimmed:
            return None

        if not trimmed.startswith("http://") and not trimmed.startswith("https://"):
            return trimmed.lstrip("/")

        parsed = urlparse(trimmed)
        path = unquote(parsed.path or "")
        public_prefix = "/storage/v1/object/public/report-images/"
        sign_prefix = "/storage/v1/object/sign/report-images/"

        if public_prefix in path:
            return path.split(public_prefix, 1)[1]
        if sign_prefix in path:
            return path.split(sign_prefix, 1)[1]

        return None
