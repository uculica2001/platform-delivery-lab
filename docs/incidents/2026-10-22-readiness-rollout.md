# Simulated incident: readiness configuration blocks a rollout

This is an intentional portfolio exercise in a local kind cluster, not a production incident or a claim about employer infrastructure.

## Outcome and scope

The baseline release and actual cache-header patch deployed successfully. A subsequent configuration release set `APP_READY=false`, causing Helm's readiness wait to time out. Two functional patch pods remained ready Service endpoints; the candidate was excluded. Helm rollback restored the good configuration and application checks passed.

Scope: namespace `lab-release`, release `delivery-lab`, context `kind-platform-delivery-lab`, one Kubernetes v1.36.4 node. Existing `lab-dev`, `lab-staging`, the standalone demo, and unrelated containers were not changed by this exercise. There was no production traffic.

## Observed timeline

Times below are UTC on 2026-10-22, from the [frozen local result](../verification/2026-10-22-release-result.json).

| Time | Evidence |
| --- | --- |
| 12:48:58.403 | Exercise started. |
| 12:49:05.348 | Baseline `0.1.0` verified: two replicas/endpoints, expected JSON, probe cache header absent. Helm revision 1. |
| 12:49:14.877 | Patch `0.1.1` verified: two updated replicas and `Cache-Control: no-store`. Good Helm revision 2 recorded. |
| 12:49:52.693 | Expected failure verified: Helm exit 1 after 35.60 seconds, revision 3 marked failed; one Running/unready candidate, zero restarts, health 200/readiness 503. Two ready endpoints still pointed to the previous patch pods. |
| 12:49:54.742 | Rollback to revision 2 verified, creating revision 4 with status deployed and readiness restored. |
| 12:49:54.889 | Successful result saved. |

Recovery verification completed about 2.05 seconds after the failed-rollout checkpoint. This is one local observation, not a recovery-time objective or production performance estimate. The healthy checkpoints and the failed-rollout checkpoint each sampled 36 successful Service requests; no continuous availability test was performed.

## Artifact identity

- Baseline Docker ID: `sha256:3c4eca0af3f3ef2496a664b70b9a1b4c04e1366f0ffda7ac95a5c0029624d6d4`.
- Patch Docker ID: `sha256:d23be7a935771f05abdcfa889e5491a40b43542ec2e98dbf2c3b56cf2e59dc31`.
- Baseline source: frozen Git commit `bd9cec24bfc7272714f187da4864adc748327780`.
- Local patch source: that checkout plus uncommitted patch changes, honestly labeled with `-dirty`. CI builds the committed checkout separately and records its own image identities.
- Installed Python package versions matched between the two images. The application suite passed 17 tests before the exercise.

Image IDs may differ on another build because base images and transitive dependencies are not fully locked. Tags and deployment-supplied version strings alone are not proof of artifact identity.

## Cause and detection

The deliberately injected cause was `app.ready=false`, rendered as `APP_READY=false`. This startup flag makes `/readyz` return 503 while `/healthz` returns 200. The cache-header patch was functional and was not the cause of the rollout failure.

The candidate's failed readiness kept it out of the ready Service endpoints. With `maxUnavailable: 0` and capacity for the extra surge pod, Kubernetes retained the two previous functional pods. Helm's `--wait --timeout 35s` reported `Updated: 1/2` and `context deadline exceeded`. This was a Helm wait timeout, not a demonstrated Deployment `ProgressDeadlineExceeded` condition.

Diagnostics checked the actual pod state, probe HTTP behavior, Service target references, and sampled responses. Merely treating any nonzero Helm exit as an expected failure would have hidden unrelated errors, so the script also requires the specific timeout and failed-release state.

## Recovery and verification

The recovery target was the successful patch revision 2. Helm rollback created revision 4, restoring `app.ready=true` while keeping patch image `0.1.1`. Recovery did not revert the application binary to `0.1.0`.

Verification required two updated/ready/available replicas, correct image references, two ready Service endpoints, expected application version/environment JSON, the new cache headers, Helm status `deployed`, and restored Helm values. The recovered release remains installed locally for inspection.

## Follow-up and limits

- The repeatable scenario is now an explicit CI step after normal dev/staging checks, isolated in its own namespace. CI evidence is linked from [PR #1](https://github.com/uculica2001/platform-delivery-lab/pull/1); this local report does not establish a CI conclusion.
- An unexpected exercise assertion triggers an attempted recovery after fault injection begins, but still fails the exercise. That emergency path is not claimed as separately fault-injected here.
- Readiness is a startup simulation flag, not a real dependency check. The cluster has one node, no continuous load, no ingress/TLS, and no production availability measurement.
- The [runbook](../runbooks/release-recovery.md) explains reproduction, diagnostics, manual recovery, and the differences between image, application, chart, Helm, and Deployment versions.
