FROM python:3.12-slim

# These are filled in by the deploy workflow so a running pod can tell you
# which environment, version and commit it came from.
ARG ENVIRONMENT=local
ARG APP_VERSION=0.0.0-local
ARG GIT_SHA=local
ARG BUILT_AT=unknown
ENV ENVIRONMENT=$ENVIRONMENT \
    APP_VERSION=$APP_VERSION \
    GIT_SHA=$GIT_SHA \
    BUILT_AT=$BUILT_AT \
    PYTHONUNBUFFERED=1

WORKDIR /srv
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ ./app/

EXPOSE 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
