# Release, patch, and recovery runbook

## Scope and prerequisites

Practice a successful release, a real application patch, a broken configuration rollout, and a verified Helm rollback. All exercise resources live in `lab-release` on context `kind-platform-delivery-lab`. The separate dev/staging releases are not modified.

Prerequisites: PowerShell 7, Git, Docker Linux containers, project-local tools, and the cluster from [the Kubernetes walkthrough](../kubernetes-lab.md). Run commands from the repository root.

The patch adds `Cache-Control: no-store` to `/healthz` and `/readyz`, including readiness status 503. Four new tests cover both endpoints with readiness enabled/disabled. The current suite has 17 tests.

## Build the two artifacts

```powershell
docker build --target test -t platform-delivery-lab:test .
docker run --rm --network none platform-delivery-lab:test
./scripts/build-release-images.ps1
```

Check every command's result before continuing.

| Image | Source |
| --- | --- |
| `platform-delivery-lab:release-0.1.0` | Frozen commit `bd9cec24bfc7272714f187da4864adc748327780`, before the patch. When dependency declarations match, archived requirements line endings are aligned with the current checkout to share the dependency layer. |
| `platform-delivery-lab:patch-0.1.1` | Current checkout. Revision metadata gains `-dirty` when tracked or untracked changes exist. |

These are separate builds, not two tags on the same patched image. OCI version/revision labels and Docker IDs are saved in `work/releases/images.json`. The script compares installed Python package versions and refuses the comparison if they differ; matching versions are saved in `work/releases/python-packages.txt`. This check does not replace dependency locking or signed provenance. The base-image and dependency reproducibility limits from the first milestone remain.

The baseline commit must exist locally. CI fetches full history for the Kubernetes job so `git archive` can read it. A shallow local clone must fetch that commit before building. Images remain local; this does not publish a registry artifact or a GitHub Release.

## Run the controlled failure

```powershell
./scripts/exercise-release-recovery.ps1 -RunFailureExercise
```

The explicit switch is required because the command deliberately creates a failed Helm revision. It refuses an existing `lab-release` namespace without the exercise ownership label. Rerunning resets this exercise release through baseline and patch again; revision numbers are discovered dynamically.

1. Import both images into kind and create/reuse the owned namespace with restricted Pod Security.
2. Install image `release-0.1.0`, reported version `0.1.0`, with two replicas. Verify readiness, ready Service endpoints, response bodies, and absent probe cache headers.
3. Upgrade to image `patch-0.1.1`, reported version `0.1.1`. Verify both updated replicas and the new headers. Record this successful Helm revision as the recovery target.
4. Upgrade the same patch image with only `app.ready=false`. Require a nonzero Helm timeout after a 35-second wait and Helm status `failed`. Unrelated failures are not accepted.
5. Verify one new pod is Running but unready, has zero restarts, returns health 200 and readiness 503. Confirm the two ready Service endpoints still refer to the previous patch pods and exclude the candidate. Check 36 sampled Service requests against the functional patch behavior.
6. Roll back to the recorded good revision with `--wait`. Verify two updated/ready/available replicas, image, Service responses, restored readiness configuration, Helm status `deployed`, and a new Helm revision.

The baseline, patch, failed-rollout checkpoint, and recovery each sample 36 Service requests. This is checkpoint verification, not continuous traffic monitoring or a zero-downtime guarantee.

The Deployment uses `maxUnavailable: 0` and `maxSurge: 1`; spare capacity for one additional pod is needed. Liveness uses `/healthz`, while readiness uses `/readyz`, so an unready candidate remains alive. The 35-second Helm wait timeout is distinct from the chart's 120-second Deployment progress deadline; this exercise does not claim `ProgressDeadlineExceeded`.

In CI, the normal dev/staging gate must pass before a separate exercise step runs in `lab-release`. There is no `continue-on-error`: specific failure, isolation, and recovery assertions must all pass.

## Inspect evidence and diagnose

```powershell
./work/tools/helm --kubeconfig work/kubeconfig --kube-context kind-platform-delivery-lab -n lab-release history delivery-lab
./work/tools/helm --kubeconfig work/kubeconfig --kube-context kind-platform-delivery-lab -n lab-release status delivery-lab
./work/tools/helm --kubeconfig work/kubeconfig --kube-context kind-platform-delivery-lab -n lab-release get values delivery-lab
./work/tools/kubectl --kubeconfig work/kubeconfig --context kind-platform-delivery-lab -n lab-release get pods,replicasets,endpointslices
./work/tools/kubectl --kubeconfig work/kubeconfig --context kind-platform-delivery-lab -n lab-release describe deployment delivery-lab
./work/tools/kubectl --kubeconfig work/kubeconfig --context kind-platform-delivery-lab -n lab-release get events --sort-by=.metadata.creationTimestamp
```

On Windows, explicit tool paths can also use `.exe`. Local evidence is ignored by Git:

- `work/releases/exercise-result.json`: image identities, timestamped phases, failure, Helm revisions, and conclusion.
- `work/releases/failure-events.txt`: events collected before rollback.
- `work/releases/failed-deployment.txt`: Deployment state before rollback.

The JSON summary also appears in the CI log. CI deletes the disposable cluster afterward; locally the recovered release remains available for inspection. A frozen local result is included with [the simulated incident report](../incidents/2026-10-22-readiness-rollout.md).

## Manual recovery

After fault injection starts, an unexpected assertion failure triggers an attempt to restore the known-good patch revision. Even if emergency recovery succeeds, the exercise still fails. If recovery also fails, both errors are reported. Failures before a good patch revision exists require diagnosis instead of an assumed recovery target.

Inspect history and select the actual successful revision with `app.ready=true`, image `patch-0.1.1`, and version `0.1.1`. Replace `<GOOD_REVISION>` with that number before running:

```powershell
./work/tools/helm --kubeconfig work/kubeconfig --kube-context kind-platform-delivery-lab -n lab-release rollback delivery-lab <GOOD_REVISION> --wait --timeout 120s
./work/tools/kubectl --kubeconfig work/kubeconfig --context kind-platform-delivery-lab -n lab-release rollout status deployment/delivery-lab --timeout=120s
```

Verify values, actual pod images/readiness, ready endpoints, and HTTP responses. A successful rollback command alone does not establish application recovery. A standalone `kubectl rollout undo` would not reconcile Helm values/history. If GitOps is introduced later, recovery must follow the declared Git state instead.

## Version numbers to explain at an interview

| Identifier | Meaning |
| --- | --- |
| Git commit | Source snapshot for a build. |
| Docker image ID / tag | Built-image identity / mutable reference. |
| Application version | Deployment-supplied `/version` value; not an independent attestation. |
| Chart version | Unchanged template package `0.1.0` used for both images. Chart `appVersion` is informational default metadata, not the overridden running image version. |
| Helm revision | Release history entry. Rollback creates a new revision with earlier configuration. |
| Deployment revision | Kubernetes pod-template rollout history, separate from Helm revisions. |

The bad candidate reuses the patch image and application version. Only readiness configuration changes; this is a configuration release failure.

## References

- [Helm rollback](https://helm.sh/docs/helm/helm_rollback/)
- [Helm upgrade](https://helm.sh/docs/helm/helm_upgrade/)
- [Kubernetes Deployment behavior](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
