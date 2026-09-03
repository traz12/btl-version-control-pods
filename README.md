# breaker - three environments, one pipeline

A very small Python app that says hello. The app is not the point: the point is the
path a change takes from a branch, through a build, into a pod on GKE - once per
environment, with nothing shared between them by accident.

## The three environments

| Branch | Environment | Image | Namespace | Pods |
|---|---|---|---|---|
| `dev` | dev | `breaker-dev` | `breaker-dev` | 1 |
| `test` | test | `breaker-test` | `breaker-test` | 2 |
| `main` | prod | `breaker-prod` | `breaker-prod` | 3 |

All three live in the Google Cloud project `ai-btl-vaadot-testing-suite`, in the
Artifact Registry repository `breaker` (region `europe-west1`), and run on the GKE
cluster `btl-mock` in three separate namespaces.

One branch owns one environment. Pushing to a branch is what deploys it - there is no
other way in, and no way for a push to `dev` to reach the prod pods.

## How a change travels

```
your branch  ->  dev  ->  test  ->  main
                 (dev)    (test)    (prod)
```

Open a pull request into `dev`, merge it, and the dev pods get the change. To move it
on, open a pull request from `dev` into `test`, then from `test` into `main`. CI
refuses a pull request that skips a step, unless the branch is named `hotfix/...` -
so skipping is possible, but it is visible to everyone.

## What runs when

**On a pull request** (`.github/workflows/ci.yml`) - nothing touches Google Cloud:

- the promotion path is checked (`dev` -> `test` -> `main`)
- `ruff` lints the code and `pytest` runs the tests
- the image is built and thrown away, to prove the Dockerfile still works
- every Kubernetes file is read and checked for valid YAML

**On a push to `dev`, `test` or `main`** (`.github/workflows/deploy.yml`):

1. the branch is turned into an environment name by `scripts/env_for_branch.sh`
2. the image is built with that environment baked in, and pushed to Artifact Registry
   as `sha-<commit>`, `v<VERSION>` and `latest`
3. the namespace, deployment and service for that environment are applied
4. `kubectl rollout status` waits for the new pods to become ready
5. a throwaway pod calls `/version` through the service, so a broken build fails in
   the pipeline instead of in front of a user

The pod always runs the `sha-<commit>` tag. That is what makes every push a real
rollout - a moving tag like `latest` can leave Kubernetes thinking nothing changed.

**Once, by hand** (`.github/workflows/infra-setup.yml`) - creates the Artifact
Registry repository and the three namespaces. Running it again is harmless.

## Layout

```
app/main.py            the app: /, /healthz, /version
tests/                 pytest tests
Dockerfile             one image, built the same way for all three environments
VERSION                the app version, used as an image tag
k8s/dev|test|prod/     namespace + deployment + service for that environment
scripts/               env_for_branch.sh - the branch-to-environment mapping
.github/workflows/     ci.yml, deploy.yml, infra-setup.yml
```

The three `k8s/` folders are deliberately separate files rather than one file with
switches in it. You can read a folder and know exactly what runs in that environment.

## The app

| Path | What it gives you |
|---|---|
| `/` | the hello world message, plus the environment and version |
| `/healthz` | what Kubernetes asks before it sends traffic to a pod |
| `/version` | environment, version, commit and build time of the running image |

`/version` is the quick way to prove the three environments are really three builds.

## Run it on your machine

```bash
pip install -r requirements-dev.txt
pytest -q
uvicorn app.main:app --reload --port 8080
curl localhost:8080/version
```

## Look at the pods

```bash
gcloud container clusters get-credentials btl-mock --region europe-west1 \
  --project ai-btl-vaadot-testing-suite

kubectl get pods -n breaker-dev
kubectl get pods -n breaker-test
kubectl get pods -n breaker-prod

# talk to one of them
kubectl port-forward -n breaker-prod svc/breaker 8080:80
curl localhost:8080/version
```

The services are `ClusterIP`, so nothing is exposed to the internet. Use
`port-forward` to reach them.

## What the repository needs to be configured with

Secret:

- `GCP_SA_KEY` - the JSON key of a service account that may push to Artifact
  Registry and deploy to GKE

Variables:

| Name | Value |
|---|---|
| `GCP_PROJECT_ID` | `ai-btl-vaadot-testing-suite` |
| `GCP_REGION` | `europe-west1` |
| `AR_REPO` | `breaker` |
| `GKE_CLUSTER` | `btl-mock` |

There are also three GitHub environments - `dev`, `test` and `prod` - one per
deploy. Add required reviewers to `prod` in the repository settings and every
release to production will wait for someone to approve it.
