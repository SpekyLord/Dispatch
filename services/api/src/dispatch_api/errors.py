from __future__ import annotations

from http import HTTPStatus
from typing import Any

from flask import Flask, jsonify
from werkzeug.exceptions import HTTPException


class ApiError(Exception):
    def __init__(
        self,
        message: str,
        *,
        status_code: int = HTTPStatus.BAD_REQUEST,
        code: str = "bad_request",
        details: dict[str, Any] | None = None,
    ) -> None:
        super().__init__(message)
        self.message = message
        self.status_code = status_code
        self.code = code
        self.details = details or {}


def register_error_handlers(app: Flask) -> None:
    @app.errorhandler(ApiError)
    def handle_api_error(error: ApiError):
        response = {
            "error": {
                "code": error.code,
                "message": error.message,
                "details": error.details,
            }
        }
        return jsonify(response), error.status_code

    @app.errorhandler(HTTPException)
    def handle_http_error(error: HTTPException):
        response = {
            "error": {
                "code": error.name.lower().replace(" ", "_"),
                "message": error.description,
                "details": {},
            }
        }
        return jsonify(response), error.code

    @app.errorhandler(Exception)
    def handle_unknown_error(error: Exception):
        app.logger.exception("Unhandled exception", exc_info=error)
        response = {
            "error": {
                "code": "internal_server_error",
                "message": "An unexpected error occurred.",
                "details": {},
            }
        }
        return jsonify(response), HTTPStatus.INTERNAL_SERVER_ERROR
