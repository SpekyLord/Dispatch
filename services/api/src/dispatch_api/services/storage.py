from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import PurePosixPath
from typing import Any
from uuid import uuid4

from dispatch_api.config import Settings
from dispatch_api.errors import ApiError

ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/png"}
MAX_IMAGE_SIZE_BYTES = 5 * 1024 * 1024
ALLOWED_ATTACHMENT_TYPES = {
    "application/pdf",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/vnd.ms-excel",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "application/vnd.ms-powerpoint",
    "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    "text/plain",
    "text/csv",
}
MAX_ATTACHMENT_SIZE_BYTES = 10 * 1024 * 1024


@dataclass(slots=True)
class SignedRequest:
    method: str
    url: str
    headers: dict[str, str]
    json: dict[str, Any]


class StorageService:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    def validate_upload(self, *, content_type: str, size_bytes: int) -> None:
        if content_type not in ALLOWED_IMAGE_TYPES:
            raise ApiError(
                "Unsupported file type. Only JPEG and PNG images are allowed.",
                code="unsupported_media_type",
                details={"allowed_types": sorted(ALLOWED_IMAGE_TYPES)},
            )
        if size_bytes > MAX_IMAGE_SIZE_BYTES:
            raise ApiError(
                "File exceeds the maximum allowed size.",
                code="file_too_large",
                details={"max_size_bytes": MAX_IMAGE_SIZE_BYTES},
            )

    def validate_attachment_upload(self, *, content_type: str, size_bytes: int) -> None:
        if content_type not in ALLOWED_ATTACHMENT_TYPES:
            raise ApiError(
                "Unsupported attachment type.",
                code="unsupported_media_type",
                details={"allowed_types": sorted(ALLOWED_ATTACHMENT_TYPES)},
            )
        if size_bytes > MAX_ATTACHMENT_SIZE_BYTES:
            raise ApiError(
                "Attachment exceeds the maximum allowed size.",
                code="file_too_large",
                details={"max_size_bytes": MAX_ATTACHMENT_SIZE_BYTES},
            )

    def build_object_path(self, *, owner_id: str, domain: str, filename: str) -> str:
        path = PurePosixPath(filename)
        extension = path.suffix.lower() or ".bin"
        stem = re.sub(r"[^a-zA-Z0-9_-]+", "-", path.stem).strip("-").lower()[:40] or "file"
        safe_domain = domain.replace("\\", "-").replace("/", "-")
        return f"{owner_id}/{safe_domain}/{stem}-{uuid4().hex}{extension}"

    def create_signed_upload_request(
        self, *, bucket: str, object_path: str, expires_in: int = 600
    ) -> SignedRequest:
        return SignedRequest(
            method="POST",
            url=f"{self.settings.supabase_url}/storage/v1/object/upload/sign/{bucket}/{object_path}",
            headers=self._service_headers(),
            json={"expiresIn": expires_in},
        )

    def create_signed_download_request(
        self, *, bucket: str, object_path: str, expires_in: int = 600
    ) -> SignedRequest:
        return SignedRequest(
            method="POST",
            url=f"{self.settings.supabase_url}/storage/v1/object/sign/{bucket}/{object_path}",
            headers=self._service_headers(),
            json={"expiresIn": expires_in},
        )

    def _service_headers(self) -> dict[str, str]:
        return {
            "apikey": self.settings.supabase_service_role_key or "",
            "Authorization": f"Bearer {self.settings.supabase_service_role_key or ''}",
            "Content-Type": "application/json",
        }
