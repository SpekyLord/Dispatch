from __future__ import annotations

from flask import Request
from pydantic import BaseModel, ValidationError

from dispatch_api.errors import ApiError


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
