"""A small service for learning container delivery and Kubernetes operations."""

import os

from flask import Flask, jsonify, request


def create_app():
    """Read deployment configuration once when the application starts."""
    app = Flask(__name__)
    ready = os.getenv("APP_READY", "true").strip().lower()
    if ready not in {"true", "false"}:
        raise ValueError("APP_READY must be true or false")

    app.config.update(
        APP_VERSION=os.getenv("APP_VERSION", "0.1.0"),
        APP_ENV=os.getenv("APP_ENV", "development"),
        APP_READY=ready == "true",
    )

    @app.after_request
    def prevent_cached_probe_responses(response):
        if request.path in {"/healthz", "/readyz"}:
            response.cache_control.no_store = True
        return response

    @app.get("/")
    def index():
        return jsonify(service="platform-delivery-lab")

    @app.get("/healthz")
    def health():
        return jsonify(status="ok")

    @app.get("/readyz")
    def readiness():
        # This startup flag supports a controlled rollout-failure exercise.
        # There are no external dependencies to check in the first version.
        if not app.config["APP_READY"]:
            return jsonify(status="not_ready"), 503
        return jsonify(status="ready")

    @app.get("/version")
    def version():
        return jsonify(
            version=app.config["APP_VERSION"],
            environment=app.config["APP_ENV"],
        )

    return app
