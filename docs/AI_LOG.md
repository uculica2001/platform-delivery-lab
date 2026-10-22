# AI contribution log

Record substantial proposals and changes, the owner's decision, and verification evidence. Do not infer results from a model's confidence.

| Date | Assistant | Contribution | Decision / verification |
| --- | --- | --- | --- |
| 2026-10-22 | Claude, user-supplied proposal | Delivery Lab design and manual AI review experiment | Used as the initial planning basis; experiment reduced to three pilot cases. No implementation verified. |
| 2026-10-22 | DeepSeek, user-supplied proposal | GitOps, observability, and incident response extension | Retain for later stages. Proposed B-series AKS system pool rejected after checking Microsoft documentation. |
| 2026-10-22 | Current OpenAI assistant | Proposal comparison, phased scope, startup documentation, and Windows environment checks | Project membership changed successfully. Environment limitations are recorded in the plan; implementation is pending. |
| 2026-10-22 | Current OpenAI assistant | Copied startup documents into the project and rechecked Docker after the owner started it | File copies verified by SHA-256. Docker engine access denied in the restricted session; verification in the owner terminal is pending. |
| 2026-10-22 | Current OpenAI assistant | Implemented the Flask application, container targets, tests, and PowerShell smoke check | Eight tests passed; ready/unready HTTP checks passed with UID 10001 and a read-only root filesystem. See the verification record. Owner selected a public repository; GitHub account verified and repository created. |
| 2026-10-22 | Current OpenAI assistant | Found and fixed a Gunicorn control-socket write error during the walkthrough | Disabled the unused control interface. Extended smoke checks to inspect logs; the original image failed and the rebuilt image passed ready/unready checks. |
| 2026-10-22 | Claude and DeepSeek, independently reviewed frozen snapshot 7f61c43 | PowerShell compatibility, lost startup logs, cleanup false-success, readiness test gaps, and stronger runtime-constraint checks | Findings were reproduced before changes. Native Docker capture and lifecycle cleanup were corrected; 13 tests pass, normalization mutation is rejected, and five failure-path probes pass. See docs/reviews/round-01/remediation.md for original responses and evidence. |
| 2026-10-22 | Current OpenAI assistant | Added pull-request CI and portable Docker discovery for the fault-injection harness | Workflow uses a standard Ubuntu runner, pinned checkout, read-only contents permission, application/container checks, and five failure scenarios. Actual execution evidence is linked from the PR and Actions. |

## Kubernetes milestone

Earlier rows preserve the state observed at the time.

- Date: 2026-10-22; current OpenAI assistant.
- Contribution: Helm chart with dev/staging values and schema, pinned project-local tooling, isolated kind setup, deployment verification, CI Kubernetes job, and walkthrough.
- Verification: both chart configurations lint/render; three invalid values rejected; local releases have one/two ready replicas and Service endpoints; Service HTTP and runtime constraint checks pass. Repeat reconciliation also passed. See `docs/verification/2026-10-22-kubernetes.md` and the actual CI run linked from the PR.
- Remaining scope: controlled failed rollout/recovery, image publishing, security scanning, and the seeded-defect AI review pilot.

## Entry template

- Date and model label shown in the interface:
- Task and supplied context:
- Proposal or change:
- Accepted, modified, or rejected; reason:
- Verification performed and evidence:
- Remaining uncertainty:



