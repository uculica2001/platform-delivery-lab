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

## Follow-up: startup log inspection

During the interactive walkthrough, HTTP endpoints responded successfully but the initial Gunicorn configuration logged `Control server error: [Errno 30] Read-only file system: '/home/service'`. The first smoke check inspected HTTP behavior but did not inspect successful-startup logs.

The optional Gunicorn control interface is not used by this lab. Adding `--no-control-socket` to the runtime command avoids its attempt to create a control socket under the service user's home directory. The non-root user and read-only filesystem remain enabled. Reference: [Gunicorn control settings](https://gunicorn.org/reference/settings/#control).

The smoke script now rejects ERROR/CRITICAL log entries and Python tracebacks observed during the checks. It failed against the original image despite successful HTTP responses, reproducing the issue. After rebuilding, both ready and unready scenarios passed all HTTP, UID, and log checks. Temporary test containers were stopped.

The updated runtime image is `sha256:6d97e72211d16f1a9e0ff9dc41a151a14819c490103279649448cd876164c0bf`. During this rebuild the mutable Python tag resolved to `sha256:57b29a7c050c4e679e4bea572e14b3965cf4b5839de2da49d55e49ffc4024f39`; digest pinning remains a future hardening task. This does not change the historical results above.

The application code and pytest cases were unchanged; the relevant runtime checks were repeated for the configuration fix.

## Follow-up: independent AI review remediation

After Claude and DeepSeek reviewed source snapshot `7f61c43`, the application tests and smoke script were strengthened. The current suite has **13 passing tests**; removing readiness normalization in a disposable test container now produces **4 failures and 9 passes**.

The revised smoke script passed ready/unready HTTP checks, UID/GID and ReadonlyRootfs checks, log checks, and explicit removal confirmation. Five injected startup/cleanup failure scenarios passed their expected outcomes, including preserving startup diagnostics and reporting combined application/cleanup failures.

Full Docker verification ran under PowerShell 7.6.5. Windows PowerShell 5.1 parsing and inline native-capture checks passed, but full script execution remains blocked by its existing execution policy. No policy was changed.

See the [complete remediation record](../reviews/round-01/remediation.md) for original reviews, decisions, detailed results, limits, and reproduction commands. Historical results earlier in this document refer to the prior snapshots.

## Limits

- No Kubernetes deployment or CI run has been performed.
- No vulnerability scan or load test has been performed.
- Test dependencies are in the separate test target, not copied into the runtime target.
- Direct runtime dependencies are Flask 3.1.3 and Gunicorn 26.2.0; tests use pytest 9.1.1.
- The base image resolved during these builds to `python:3.13-slim@sha256:27b7c9d4f13ca20bb1170148f02095d50a5dfce1f7f2dabf5ca273727e43b7ea`. The Dockerfile still uses the mutable tag and transitive dependencies are not locked.
- This is a portfolio laboratory, not a production readiness or security certification.
