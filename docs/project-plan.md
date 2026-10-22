# Project plan

## Agreed direction

Use the Delivery Lab proposal as the initial scope. Add GitOps and observability in later stages. Multi-model AI review is part of the project, with a small pilot before expanding the experiment.

## Initial scope

- One personal GitHub repository; proposed name: `platform-delivery-lab`.
- Small Python application using Flask, served by Gunicorn in a Linux container.
- Container image and application tests.
- Local Kubernetes environment with a Helm chart and separate development/staging values.
- GitHub Actions for validation and release checks.
- Demonstrated release, patch, controlled failure, and recovery.
- Manual reviews with ChatGPT, Claude, and DeepSeek using identical case packages.
- English README, architecture decisions, runbook, incident report, and experiment results.

## First five work items

### 1. Validate the working environment

Acceptance criteria:
- Select and document a Windows/WSL execution approach.
- Confirm the container engine is reachable and supports the chosen Linux image workflow.
- Confirm Git and the required application tooling work in that environment.
- Identify the personal GitHub account and check repository access without collecting credentials in chat.
- Record installed versions and unresolved requirements.

### 2. Build and understand the application

Acceptance criteria:
- Health, readiness, and version endpoints have documented behavior.
- Tests exercise meaningful success and failure behavior.
- The application runs locally and in its container.
- The image runs as a non-root user.
- The owner can explain the code, tests, and container configuration.

### 3. Deploy using Helm

Acceptance criteria:
- A reproducible local cluster setup is documented.
- The chart deploys the application with probes and resource configuration.
- Development and staging use justified configuration differences.
- Deployment readiness and an actual application request are verified.

### 4. Add CI and demonstrate the release lifecycle

Acceptance criteria:
- Pull request validation checks the application and chart.
- A release produces an identifiable image and validates deployment in an isolated CI cluster.
- A patch and a controlled failed rollout are demonstrated.
- Recovery is verified and documented in a runbook and simulated incident report.
- The failure exercise is explicit and isolated from the successful release gate.

### 5. Run the AI review pilot

Acceptance criteria:
- Three cases: an issue detectable by automated checks, a context-dependent issue, and a case with no intentionally introduced defect.
- Freeze the known-defect register before reviews and exclude it from model input.
- Give every model the same prompt, patch, and supporting files in a fresh conversation.
- Save raw responses and model labels shown by each interface, dates, settings, and elapsed time.
- Verify findings; keep newly discovered real issues separate from the original register.
- Compare individual reviews, their deduplicated union, and one round of peer critique.
- Report counts and limitations without generalizing to model rankings.

## Verified progress: 2026-10-22

- Git: 2.42.0.windows.2.
- Docker Desktop 4.90.0, client/engine 29.7.2, context `desktop-linux`, Linux amd64 engine.
- First execution approach: PowerShell commands and Linux containers; a host Python installation and direct WSL shell access are not required for this milestone.
- Thirteen application tests passed inside the test image after independent AI review; removing readiness normalization causes four test failures.
- Runtime image built successfully and passed the HTTP verification script in ready/unready modes, running as UID 10001 with a read-only root filesystem.
- Personal GitHub connector identity confirmed as `uculica2001`; the owner selected public visibility.
- Public repository `uculica2001/platform-delivery-lab` created. Source changes are tracked through the repository pull requests.
- kubectl client v1.36.1 is available; no Kubernetes cluster has been validated.
- Helm and kind were not found on the current Windows PATH; the Kubernetes stage still requires its own setup.
- The first independent Claude/DeepSeek development review is documented in [review round 01](reviews/round-01/remediation.md), including frozen inputs, original responses, verified findings, fixes, and five startup/cleanup failure-path checks.

See [the verification record](verification/2026-10-22-container.md) for evidence and limits.

## Open decisions

- Weekly time budget; previous proposal estimates are not a confirmed commitment.
- Actual model access and settings; do not assume subscription or API availability.

## Deferred scope

Argo CD, dashboards/alerts, Terraform, AKS, and API automation. Revisit after the core lab and review pilot work. If Argo CD is added, define recovery through the declared Git state rather than reusing the Helm-managed recovery procedure unchanged.

