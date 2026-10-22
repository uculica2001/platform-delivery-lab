# Local verification: 2026-10-22

## Environment

- Windows PowerShell host with Docker Desktop 4.90.0.
- Docker client and engine 29.7.2; context `desktop-linux`.
- Engine architecture: Linux amd64; kernel reports WSL2.
- Direct WSL distribution access has not been validated. It is not required by the selected container-based quickstart.
- GitHub connector identity verified as `uculica2001`; public repository `uculica2001/platform-delivery-lab` created after browser authentication. Source changes are tracked through the repository pull requests.

## Application tests

```text
docker build --target test -t platform-delivery-lab:test .
docker run --rm --network none platform-delivery-lab:test
8 passed in 0.43s
```

The cases verify health, default readiness, intentional unready behavior while health stays successful, deployment version/environment, rejection of three invalid readiness settings, and isolation between application instances.

## Runtime checks

Runtime image built successfully:

```text
platform-delivery-lab:0.1.0
sha256:c018ab96b8ee1f6fa97a35f0707e2d8f386101185fe76a6056598ee423925528
```

`scripts/verify-container.ps1` started the default Gunicorn command in two temporary containers, each with a read-only root filesystem, writable temporary memory filesystem, and a dynamically assigned loopback port. Both containers ran as UID 10001.

| Mode | `/` | `/healthz` | `/readyz` | `/version` |
| --- | --- | --- | --- | --- |
| `APP_READY=true` | 200 | 200 | 200 | 200 |
| `APP_READY=false` | 200 | 200 | 503 | 200 |

Response JSON fields were checked as well as status codes. Version/environment overrides were returned correctly. Both temporary containers were stopped by the script.

## Limits

- No Kubernetes deployment or CI run has been performed.
- No vulnerability scan or load test has been performed.
- Test dependencies are in the separate test target, not copied into the runtime target.
- Direct runtime dependencies are Flask 3.1.3 and Gunicorn 26.2.0; tests use pytest 9.1.1.
- The base image resolved during these builds to `python:3.13-slim@sha256:27b7c9d4f13ca20bb1170148f02095d50a5dfce1f7f2dabf5ca273727e43b7ea`. The Dockerfile still uses the mutable tag and transitive dependencies are not locked.
- This is a portfolio laboratory, not a production readiness or security certification.
