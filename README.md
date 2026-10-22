# Platform Delivery Lab

A personal DevOps portfolio lab for reproducible Kubernetes delivery and evidence-based review with multiple AI models.

## Status

The application and container milestone is implemented and locally verified. Seventeen application tests pass; HTTP checks cover healthy and intentionally unready instances running as a non-root user with a read-only root filesystem. The patch adds non-cacheable health/readiness responses.

The [GitHub Actions workflow](docs/ci.md) automates the application/container checks and fault-injection scenarios. Actual run results are available under Checks on the pull request.

The [local Kubernetes and Helm lab](docs/kubernetes-lab.md) deploys development and staging releases to a dedicated kind cluster. Local verification covers rollout readiness, Service requests, runtime constraints, and one/two ready replicas. The CI workflow includes a separate Kubernetes job; consult the PR checks for its actual result.

The [release and recovery exercise](docs/runbooks/release-recovery.md) uses distinct baseline/patch images and an isolated namespace to demonstrate a readiness configuration failure and verified Helm rollback. See [the simulated incident report](docs/incidents/2026-10-22-readiness-rollout.md) and actual PR checks for evidence.

The seeded-defect multi-model experiment remains a planned stage.

## Purpose

Demonstrate a complete delivery process: pull request validation, container build, Helm deployment, release, patch, diagnosis, and recovery. Compare what AI reviewers find with findings from automated checks.

## First milestone

Build a small application with health, readiness, and version endpoints; test it and run it in a container. Document commands and expected results so another person can reproduce them.

## Delivery stages

1. Application, tests, and local container execution.
2. Local Kubernetes, Helm, development/staging configuration, and GitHub Actions.
3. Release, patch, controlled failure, recovery, and a three-case AI review pilot.
4. Optional GitOps and observability extension.
5. Optional Terraform and Azure/AKS extension after configuration and budget approval.

## Working approach

- Discuss the project in Romanian; write repository artifacts in English.
- Keep the first version small and explain every component.
- Record actual verification evidence and distinguish planned work from completed work.
- Use original demo code and synthetic data.
- Start AI reviews manually using the same input for each model.
- Cloud resources and paid API use require explicit approval.

See [the project plan](docs/project-plan.md), [first lab walkthrough](docs/first-lab.md), and [AI contribution log](docs/AI_LOG.md).

## Quickstart

Prerequisite: Docker with Linux containers. No host Python installation is required for this path.

```powershell
docker build --target test -t platform-delivery-lab:test .
docker run --rm --network none platform-delivery-lab:test
docker build --target runtime -t platform-delivery-lab:0.1.0 .
docker run --rm --name delivery-lab-demo -p 127.0.0.1:8080:8080 --read-only --tmpfs /tmp -e APP_ENV=dev -e APP_VERSION=0.1.0 platform-delivery-lab:0.1.0
```

In another terminal, run `Invoke-RestMethod http://127.0.0.1:8080/version`. Expect version `0.1.0` and environment `dev`. Stop the running service with Ctrl+C in its terminal.

For an automated container smoke check from PowerShell:

```powershell
.\scripts\verify-container.ps1
```

The script creates and starts temporary containers on dynamically assigned loopback ports, verifies HTTP responses, UID/GID 10001, read-only root configuration, and runtime logs, then explicitly removes the containers and confirms their absence. Failed startup logs are collected before removal. Your PowerShell execution policy must allow local scripts; review the script before running it.

Full Docker verification has run under PowerShell 7.6.5. Windows PowerShell 5.1 syntax and the native-output capture pattern have been checked; full script execution there remains blocked by the existing execution policy and is not claimed as verified.

The [independent Claude/DeepSeek review and remediation record](docs/reviews/round-01/remediation.md) preserves the input, original responses, findings, and verification evidence. To reproduce the cleanup/startup failure-path checks, run `.\scripts\tests\test-smoke-failures.ps1` after building the runtime image.

See [the verification record](docs/verification/2026-10-22-container.md) for the actual local results and remaining limits.
