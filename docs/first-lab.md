# First lab: application and container

## What each component does

- `app/__init__.py`: creates the Flask application and its HTTP endpoints.
- `tests/test_app.py`: checks readiness, liveness, release configuration, and configuration errors.
- `requirements.txt`: pins the direct runtime dependencies.
- `requirements-dev.txt`: adds pytest for tests.
- `Dockerfile`: separates dependency installation, testing, and the runtime image.
- `.dockerignore`: only sends the application, tests, and dependency files to the build.
- `scripts/verify-container.ps1`: checks the running image in ready and unready modes and cleans up its temporary containers.

Flask is a small HTTP framework; Gunicorn serves the application in the Linux container. The first version has no database or external API.

## Endpoint contract

| Endpoint | Success | Purpose |
| --- | --- | --- |
| `/` | 200 | Identify the service. |
| `/healthz` | 200 | Confirm that the process can serve an HTTP request. |
| `/readyz` | 200, or 503 if disabled | Represent whether this instance should receive traffic. |
| `/version` | 200 | Report the configured version and environment. |

`APP_READY` is a startup flag for a later controlled rollout exercise, not a continuous dependency check. Changing an environment variable requires a new process/container. There is no public endpoint that changes readiness.

## Commands from PowerShell

Run these commands from the project directory. Docker Desktop must be running in Linux container mode. The first build downloads a Python image and dependencies.

```powershell
docker build --target test -t platform-delivery-lab:test .
docker run --rm --network none platform-delivery-lab:test
docker build --target runtime -t platform-delivery-lab:0.1.0 .
docker run --rm --name delivery-lab-demo -p 127.0.0.1:8080:8080 --read-only --tmpfs /tmp -e APP_ENV=dev -e APP_VERSION=0.1.0 platform-delivery-lab:0.1.0
```

The last command stays attached to the running container. In another terminal:

```powershell
Invoke-RestMethod http://127.0.0.1:8080/healthz
Invoke-RestMethod http://127.0.0.1:8080/readyz
Invoke-RestMethod http://127.0.0.1:8080/version
```

Expected: health status `ok`, readiness status `ready`, version `0.1.0`, environment `dev`. Use Ctrl+C in the first terminal to stop the container.

Alternatively, after building the runtime image, run `.\scripts\verify-container.ps1` to check both ready and unready behavior automatically. This script verifies response bodies and status codes, checks UID 10001, and stops its temporary containers. Review it before running; local PowerShell script execution must be allowed by your existing policy.

For a controlled unready instance, stop the previous container and repeat the run command with `-e APP_READY=false`. Health should remain 200 and readiness should return 503; PowerShell reports non-success HTTP responses as errors.

## What to explain at interview

1. Why should an unready instance still pass its liveness check?
2. Why are the runtime image and test image separate?
3. Which process serves HTTP, and what user does it run as?
4. How do version and environment configuration reach the container?
5. What does this exercise verify, and what remains untested until Kubernetes and CI are added?

## Reproducibility limits

The direct dependency versions are pinned. The Python image tag and transitive dependencies are not yet locked; two future builds are not guaranteed to produce identical images. Digest pinning and dependency locking belong to the delivery-hardening stage.

## References

- [Flask application factories](https://flask.palletsprojects.com/en/stable/patterns/appfactories/)
- [Flask testing](https://flask.palletsprojects.com/en/stable/testing/)
- [Gunicorn with Flask](https://flask.palletsprojects.com/en/stable/deploying/gunicorn/)
- [Flask on PyPI](https://pypi.org/project/Flask/)
- [Gunicorn on PyPI](https://pypi.org/project/gunicorn/)
- [pytest on PyPI](https://pypi.org/project/pytest/)
