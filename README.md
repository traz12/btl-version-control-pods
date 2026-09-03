# breaker - three environments, one pipeline

A very small Python app that says hello. The app is not the point: the point is the
path a change takes from a branch, through a build, into a pod on GKE - once per
environment, with nothing shared between them by accident..

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

## Versions

Each environment counts on its own, and the count lives in git tags:

```
dev/v1.0.3      test/v1.0.1      prod/v1.0.0
```

The first release of an environment is `1.0.0`. After that, every push to that
branch releases the next number - a **patch** by default:

| Label on the pull request | 1.2.3 becomes |
|---|---|
| none, or `version:patch` | `1.2.4` |
| `version:minor` | `1.3.0` |
| `version:major` | `2.0.0` |

The label is read at merge time, off the pull request the pushed commit came from,
so you can change your mind about the size of a release right up to the moment you
merge. Two `version:` labels on one pull request fails the run before anything is
built.

### For a plain `git push` (no pull request)

`dev` takes direct pushes, so you can size the release from the commit message
instead of a label - the deploy reads a `[version:major|minor|patch]` tag
anywhere in the head commit's message:

```
git add .
git commit -m "small change [version:minor]"
git push
```

Both mechanisms work at the same time. If a push has a pull request with a
label *and* a commit message tag, and they disagree, the label wins - it is
the more visible one. Two tags in one commit message fails the run. No label
and no tag means a patch.

That one number is used everywhere the release shows up:

- the image tag in Artifact Registry - `breaker-dev:v1.0.3`
- the image the pods actually run, so every release is a real rollout
- `app.kubernetes.io/version` on the Deployment and its pods
- what the running app reports at `/version`
- the git tag `dev/v1.0.3`, written only after the pods are serving

The tags are the truth, not the `VERSION` file. `VERSION` says where an
environment starts - the first release takes that number exactly - and the tags
carry it from there. `scripts/version.sh dev current` reads it back.

Because each environment counts separately, promoting the same commit from test to
prod releases a **different number** in prod. The number tells you which release of
that environment you are looking at; the git tag tells you which commit it was.

## What runs when

**On a pull request** (`.github/workflows/ci.yml`) - nothing touches Google Cloud:

- the promotion path is checked (`dev` -> `test` -> `main`)
- `ruff` lints the code and `pytest` runs the tests
- the image is built and thrown away, to prove the Dockerfile still works
- every Kubernetes file is read and checked for valid YAML
- the version this merge would release is worked out and shown in the run summary

**On a push to `dev`, `test` or `main`** (`.github/workflows/deploy.yml`):

1. the branch is turned into an environment name by `scripts/env_for_branch.sh`
2. the pull request label decides the size of the release, and the newest git tag
   for that environment decides the number
3. the build stops if that version is already in the registry, so two builds can
   never share a number
4. the image is built with the environment and version baked in, and pushed as
   `v<version>`, `sha-<commit>` and `latest`
5. the namespace, deployment and service for that environment are applied
6. `kubectl rollout status` waits for the new pods to become ready
7. a throwaway pod calls `/version` through the service and checks it answers with
   the version just released - which catches both a broken build and a rollout that
   quietly kept the old pods
8. only then is `<env>/v<version>` tagged and pushed

The pod runs the `v<version>` tag, and every release gets a new number, so
Kubernetes always sees a new image. A moving tag like `latest` can leave it
thinking nothing changed.

**Once, by hand** (`.github/workflows/infra-setup.yml`) - creates the Artifact
Registry repository and the three namespaces. Running it again is harmless.

## Layout

```
app/main.py            the app: /, /healthz, /version
tests/                 pytest tests
Dockerfile             one image, built the same way for all three environments
VERSION                where an environment's version starts (1.0.0)
k8s/dev|test|prod/     namespace + deployment + service for that environment
scripts/               env_for_branch.sh - the branch-to-environment mapping
                       version.sh        - the next version, read from the git tags
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

One thing lives in Google Cloud rather than in GitHub: the cluster nodes pull
images as the project's default compute account, so that account needs
`roles/artifactregistry.reader` on the `breaker` repository. Without it the pods
sit in `ImagePullBackOff`. `infra-setup.yml` grants it.

There are also three GitHub environments - `dev`, `test` and `prod` - one per
deploy. Add required reviewers to `prod` in the repository settings and every
release to production will wait for someone to approve it.
