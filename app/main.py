"""The example app. It only says hello - the point of this repo is the pipeline."""

import os

from fastapi import FastAPI

ENVIRONMENT = os.getenv("ENVIRONMENT", "local")
APP_VERSION = os.getenv("APP_VERSION", "0.0.0-local")
GIT_SHA = os.getenv("GIT_SHA", "local")
BUILT_AT = os.getenv("BUILT_AT", "unknown")

app = FastAPI(title=f"breaker ({ENVIRONMENT})")


@app.get("/")
def hello():
    return {
        "message": "Hello World from breaker",
        "environment": ENVIRONMENT,
        "version": APP_VERSION,
    }


@app.get("/healthz")
def healthz():
    """Kubernetes asks this before it sends traffic to the pod."""
    return {"status": "ok"}


@app.get("/version")
def version():
    """Shows exactly which build is running, so you can tell the three apart."""
    return {
        "environment": ENVIRONMENT,
        "version": APP_VERSION,
        "git_sha": GIT_SHA,
        "built_at": BUILT_AT,
    }
