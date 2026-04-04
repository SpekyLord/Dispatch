from __future__ import annotations

from http import HTTPStatus

from flask import current_app, jsonify, request

from dispatch_api.auth import get_current_user, require_auth, require_role
from dispatch_api.errors import ApiError
from dispatch_api.modules.departments import blueprint
from dispatch_api.services.assessment_service import AssessmentService
from dispatch_api.services.department_service import DepartmentService
from dispatch_api.services.feed_service import FeedService
from dispatch_api.services.notification_service import NotificationService
from dispatch_api.services.report_service import ReportService

MAX_POST_PHOTOS = 3
MAX_POST_ATTACHMENTS = 5


def _assessment_service() -> AssessmentService:
    return AssessmentService(current_app.extensions["supabase_client"])


def _department_service() -> DepartmentService:
    return DepartmentService(current_app.extensions["supabase_client"])


def _report_service() -> ReportService:
    client = current_app.extensions["supabase_client"]
    return ReportService(client, NotificationService(client))


def _feed_service() -> FeedService:
    client = current_app.extensions["supabase_client"]
    return FeedService(client, NotificationService(client))


@blueprint.get("/profile")
@require_auth()
@require_role("department")
def get_department_profile():
    user = get_current_user()
    department = _department_service().get_department_for_user(user.id)
    return jsonify({"department": department})


@blueprint.get("/view/<user_id>")
def get_public_department_profile(user_id: str):
    department = _department_service().get_department_for_user(user_id)
    if department.get("verification_status") != "approved":
        raise ApiError(
            "Department profile is not publicly available.",
            code="not_found",
            status_code=HTTPStatus.NOT_FOUND,
        )
    return jsonify({"department": department})


@blueprint.get("/directory")
def list_public_departments():
    departments = _department_service().list_public_departments()
    return jsonify({"departments": departments})


@blueprint.put("/profile")
@require_auth()
@require_role("department")
def update_department_profile():
    user = get_current_user()
    department_service = _department_service()
    department = department_service.get_department_for_user(user.id)
    client = current_app.extensions["supabase_client"]
    has_form = request.files or request.form
    body = request.form if has_form else (request.get_json(silent=True) or {})

    allowed_fields = {
        "name",
        "type",
        "contact_number",
        "address",
        "area_of_responsibility",
        "description",
        "profile_picture",
        "profile_photo",
        "header_photo",
    }
    update_data = {key: value for key, value in body.items() if key in allowed_fields}
    if _coerce_bool(body.get("remove_profile_picture")):
        update_data["profile_picture"] = None
    if _coerce_bool(body.get("remove_profile_photo")):
        update_data["profile_photo"] = None
    if _coerce_bool(body.get("remove_header_photo")):
        update_data["header_photo"] = None

    profile_picture_file = request.files.get("profile_picture_file") if request.files else None
    profile_photo_file = request.files.get("profile_photo_file") if request.files else None
    header_photo_file = request.files.get("header_photo_file") if request.files else None
    if profile_picture_file and profile_picture_file.filename:
        update_data["profile_picture"] = _upload_department_profile_asset(
            file=profile_picture_file,
            owner_id=user.id,
            department_id=department["id"],
            domain="department-profile/profile-picture",
        )
    if profile_photo_file and profile_photo_file.filename:
        update_data["profile_photo"] = _upload_department_profile_asset(
            file=profile_photo_file,
            owner_id=user.id,
            department_id=department["id"],
            domain="department-profile/profile",
        )
    if header_photo_file and header_photo_file.filename:
        update_data["header_photo"] = _upload_department_profile_asset(
            file=header_photo_file,
            owner_id=user.id,
            department_id=department["id"],
            domain="department-profile/header",
        )

    if not update_data:
        raise ApiError("No valid fields to update.", code="validation_error")

    if department.get("verification_status") == "rejected":
        update_data["verification_status"] = "pending"
        update_data["rejection_reason"] = None
        update_data["verified_at"] = None
        update_data["verified_by"] = None

    rows = client.db_update(
        "departments",
        data=update_data,
        params={"id": f"eq.{department['id']}"},
        use_service_role=True,
    )
    if not rows:
        raise ApiError("Failed to update department.", code="update_failed")

    refreshed_department = department_service.get_department_for_user(user.id)
    return jsonify({"department": refreshed_department})


@blueprint.get("/reports")
@require_auth()
@require_role("department")
def list_department_reports():
    user = get_current_user()
    department_service = _department_service()
    department = department_service.get_department_for_user(user.id)
    department_service.require_verified_department(department)

    reports = _report_service().list_department_reports(
        department=department,
        status=request.args.get("status"),
        category=request.args.get("category"),
    )
    return jsonify({"reports": reports})


@blueprint.post("/reports/<report_id>/accept")
@require_auth()
@require_role("department")
def accept_report(report_id: str):
    user = get_current_user()
    department_service = _department_service()
    department = department_service.get_department_for_user(user.id)
    department_service.require_verified_department(department)

    body = request.get_json(silent=True) or {}
    result = _report_service().accept_report(
        report_id=report_id,
        department=department,
        actor_user_id=user.id,
        notes=(body.get("notes") or "").strip() or None,
    )
    return jsonify(result)


@blueprint.post("/reports/<report_id>/decline")
@require_auth()
@require_role("department")
def decline_report(report_id: str):
    user = get_current_user()
    department_service = _department_service()
    department = department_service.get_department_for_user(user.id)
    department_service.require_verified_department(department)

    body = request.get_json(silent=True) or {}
    result = _report_service().decline_report(
        report_id=report_id,
        department=department,
        decline_reason=(body.get("decline_reason") or "").strip(),
        notes=(body.get("notes") or "").strip() or None,
    )
    return jsonify(result)


@blueprint.get("/reports/<report_id>/responses")
@require_auth()
@require_role("department")
def get_report_responses(report_id: str):
    user = get_current_user()
    department_service = _department_service()
    department = department_service.get_department_for_user(user.id)
    department_service.require_verified_department(department)

    result = _report_service().get_department_response_roster(
        report_id=report_id, department=department
    )
    return jsonify(result)


@blueprint.put("/reports/<report_id>/status")
@require_auth()
@require_role("department")
def update_report_status(report_id: str):
    user = get_current_user()
    department_service = _department_service()
    department = department_service.get_department_for_user(user.id)
    department_service.require_verified_department(department)

    body = request.get_json(silent=True) or {}
    report = _report_service().update_status(
        report_id=report_id,
        department=department,
        actor_user_id=user.id,
        new_status=(body.get("status") or "").strip(),
        notes=(body.get("notes") or "").strip() or None,
    )
    return jsonify({"report": report})


@blueprint.post("/posts")
@require_auth()
@require_role("department")
def create_post():
    user = get_current_user()
    department_service = _department_service()
    department = department_service.get_department_for_user(user.id)
    department_service.require_verified_department(department)

    photo_files = request.files.getlist("photos") if request.files else []
    attachment_files = request.files.getlist("attachments") if request.files else []
    _validate_feed_assets(
        files=photo_files,
        limit=MAX_POST_PHOTOS,
        validator_name="validate_upload",
    )
    _validate_feed_assets(
        files=attachment_files,
        limit=MAX_POST_ATTACHMENTS,
        validator_name="validate_attachment_upload",
    )

    has_form = request.files or request.form
    body = request.form if has_form else (request.get_json(silent=True) or {})
    post = _feed_service().create_post(
        department=department,
        author_id=user.id,
        title=(body.get("title") or "").strip(),
        content=(body.get("content") or "").strip(),
        category=(body.get("category") or "").strip(),
        location=(body.get("location") or "").strip(),
    )

    photo_urls: list[str] = []
    attachment_urls: list[str] = []
    if request.files:
        photo_urls = _upload_feed_assets(
            files=photo_files,
            owner_id=user.id,
            post_id=post["id"],
            bucket="department-feed-images",
            domain="department-feed/photos",
            limit=MAX_POST_PHOTOS,
            validator_name="validate_upload",
        )
        attachment_urls = _upload_feed_assets(
            files=attachment_files,
            owner_id=user.id,
            post_id=post["id"],
            bucket="department-feed-attachments",
            domain="department-feed/attachments",
            limit=MAX_POST_ATTACHMENTS,
            validator_name="validate_attachment_upload",
        )
        _feed_service().attach_assets(
            post_id=post["id"],
            photo_urls=photo_urls,
            attachment_urls=attachment_urls,
        )

    hydrated_post = {
        **post,
        "photos": photo_urls,
        "attachments": attachment_urls,
        "image_urls": photo_urls,
    }
    return jsonify({"post": hydrated_post}), HTTPStatus.CREATED


# -- Phase 3: department damage assessments --
@blueprint.post("/assessments")
@require_auth()
@require_role("department")
def create_assessment():
    user = get_current_user()
    department_service = _department_service()
    department = department_service.get_department_for_user(user.id)
    department_service.require_verified_department(department)

    body = request.get_json(silent=True) or {}
    try:
        estimated_casualties = int(body.get("estimated_casualties") or 0)
        displaced_persons = int(body.get("displaced_persons") or 0)
    except (ValueError, TypeError):
        raise ApiError(
            "estimated_casualties and displaced_persons must be integers.",
            code="validation_error",
        )
    assessment = _assessment_service().create_assessment(
        department_id=department["id"],
        report_id=(body.get("report_id") or "").strip() or None,
        affected_area=(body.get("affected_area") or "").strip(),
        damage_level=(body.get("damage_level") or "").strip(),
        estimated_casualties=estimated_casualties,
        displaced_persons=displaced_persons,
        location=(body.get("location") or "").strip(),
        description=(body.get("description") or "").strip(),
        image_urls=body.get("image_urls") or [],
    )
    return jsonify({"assessment": assessment}), HTTPStatus.CREATED


@blueprint.get("/assessments")
@require_auth()
@require_role("department")
def list_department_assessments():
    user = get_current_user()
    department_service = _department_service()
    department = department_service.get_department_for_user(user.id)
    department_service.require_verified_department(department)

    assessments = _assessment_service().list_department_assessments(department["id"])
    return jsonify({"assessments": assessments})


def _validate_feed_assets(*, files, limit: int, validator_name: str) -> None:
    valid_files = [file for file in files if file and file.filename]
    if len(valid_files) > limit:
        raise ApiError(
            f"Maximum {limit} file{'s' if limit != 1 else ''} allowed.",
            code="file_limit_exceeded",
        )

    storage = current_app.extensions["storage_service"]
    for file in valid_files:
        file_data = file.read()
        content_type = file.content_type or "application/octet-stream"
        getattr(storage, validator_name)(content_type=content_type, size_bytes=len(file_data))
        file.seek(0)


def _upload_feed_assets(
    *,
    files,
    owner_id: str,
    post_id,
    bucket: str,
    domain: str,
    limit: int,
    validator_name: str,
) -> list[str]:
    valid_files = [file for file in files if file and file.filename]
    if len(valid_files) > limit:
        raise ApiError(
            f"Maximum {limit} file{'s' if limit != 1 else ''} allowed.",
            code="file_limit_exceeded",
        )

    storage = current_app.extensions["storage_service"]
    client = current_app.extensions["supabase_client"]
    uploaded_urls: list[str] = []

    for file in valid_files:
        file_data = file.read()
        content_type = file.content_type or "application/octet-stream"
        getattr(storage, validator_name)(content_type=content_type, size_bytes=len(file_data))
        object_path = storage.build_object_path(
            owner_id=owner_id,
            domain=f"{domain}/{post_id}",
            filename=file.filename or "upload.bin",
        )
        client.storage_upload(
            bucket=bucket,
            object_path=object_path,
            file_data=file_data,
            content_type=content_type,
        )
        uploaded_urls.append(client.storage_public_url(bucket=bucket, object_path=object_path))

    return uploaded_urls


def _upload_department_profile_asset(
    *,
    file,
    owner_id: str,
    department_id: str,
    domain: str,
) -> str:
    storage = current_app.extensions["storage_service"]
    client = current_app.extensions["supabase_client"]
    file_data = file.read()
    content_type = file.content_type or "application/octet-stream"
    storage.validate_upload(content_type=content_type, size_bytes=len(file_data))
    object_path = storage.build_object_path(
        owner_id=owner_id,
        domain=f"{domain}/{department_id}",
        filename=file.filename or "upload.bin",
    )
    client.storage_upload(
        bucket="department-feed-images",
        object_path=object_path,
        file_data=file_data,
        content_type=content_type,
    )
    return client.storage_public_url(bucket="department-feed-images", object_path=object_path)


def _coerce_bool(value) -> bool:
    return str(value).lower() in {"1", "true", "yes", "on"}
