from __future__ import annotations

from dispatch_api.app import create_app
from dispatch_api.config import get_settings


def main() -> None:
    settings = get_settings()
    app = create_app(settings)
    app.run(host=settings.api_host, port=settings.api_port, debug=settings.debug)


if __name__ == "__main__":
    main()
