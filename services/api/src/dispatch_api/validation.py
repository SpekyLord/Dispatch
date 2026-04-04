from __future__ import annotations

import re

from flask import Request
from pydantic import BaseModel, ValidationError

from dispatch_api.errors import ApiError

# Characters safe for a single PostgREST filter value (alphanumeric, dash,
# underscore, colon, plus — covers UUIDs, ISO dates, enum slugs).
_SAFE_FILTER_RE = re.compile(r"^[\w\-:+.]+$")


def sanitize_postgrest_value(value: str | None) -> str | None:
    """Return *value* unchanged if it looks safe for PostgREST, else ``None``.

    Rejects strings that contain characters which could manipulate PostgREST
    operators (parentheses, commas, semicolons, spaces, etc.).
    """
    if value is None:
        return None
    value = value.strip()
    if not value or not _SAFE_FILTER_RE.match(value):
        return None
    return value


def validate_json[SchemaT: BaseModel](request: Request, schema: type[SchemaT]) -> SchemaT:
    try:
        payload = request.get_json(silent=False)
    except Exception as error:
        raise ApiError("Request body must be valid JSON.", code="invalid_json") from error

    try:
        return schema.model_validate(payload)
    except ValidationError as error:
        raise ApiError(
            "Request payload validation failed.",
            code="validation_error",
            details={"issues": error.errors()},
        ) from error
