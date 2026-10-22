# Review round 01: decisions and remediation

## Review scope and provenance

Claude and DeepSeek independently reviewed the same [input package](input-package.md) and [prompt](prompt.md), targeting commit `7f61c435b06cc5393ce1ccd96e96aeba27ebfc73`.

The owner supplied both responses: [Claude](claude.md), [DeepSeek](deepseek.md). Exact interface model labels, settings, and elapsed times were not supplied and are unknown. Both models explicitly said they had not executed code. The [initial verification](verification.md) records the separate reproduction work before any fixes.

This is an actual development review, not a seeded-defect benchmark. Agreement between models was not treated as proof, and no general model-quality ranking is claimed.

## Decisions

| Observation | Source | Decision |
| --- | --- | --- |
| PowerShell 5.1 can terminate on redirected native stderr | Claude | Capture Docker output under a locally scoped Continue preference, restore it with finally, and inspect the actual exit code. |
| --rm can discard startup failure logs | Claude | Create and start containers separately; retain them until diagnostics have been collected. |
| Cleanup failure can still produce a success message | DeepSeek | Attempt graceful stop/removal, fall back to forced removal after stop failure, and confirm absence with a successful empty container listing. Fail if absence cannot be confirmed. |
| APP_READY normalization lacks regression coverage | Both | Add whitespace and mixed-case cases, plus an invalid padded value. |
| Runtime-constraint PASS text exceeds its explicit checks | Claude optional improvement; DeepSeek verification gap | Check UID, GID, and Docker's ReadonlyRootfs configuration directly. |

Primary application errors and cleanup errors are both retained if they occur together. Cleanup only targets names created successfully by the verification script. The user-facing demo container is separate.

## Results after remediation

- Updated pytest suite: **13 passed in 0.46s**.
- Mutation inside a disposable test container, removing `.strip().lower()`: **4 failed, 9 passed in 0.34s**. The new tests detect the regression; host application files were not mutated.
- Normal smoke verification passed for ready and unready instances: HTTP status/body checks, UID 10001, GID 10001, read-only root configuration, runtime logs, and confirmed removal.
- Five fault-injection scenarios passed:

| Injected condition | Observed result |
| --- | --- |
| Stop fails, forced removal works | Verification succeeds after confirming removal. |
| Stop and removal fail | Script throws and does not print success. Probe teardown removes its owned container. |
| Docker container-list check fails | Script throws even if removal already succeeded; daemon failure is not accepted as proof of absence. |
| Application exits with invalid readiness configuration | Original error logs are printed, verification fails, container is removed. |
| Application startup and cleanup both fail | Original logs are printed; thrown message retains both failures. Probe teardown removes its owned container. |

The fault-injection harness is saved as [test-smoke-failures.ps1](../../../scripts/tests/test-smoke-failures.ps1). It exercises the actual verification script, delegates ordinary operations to Docker, and injects only the selected failures. Its final teardown directly removes the exact container IDs it created.

```powershell
docker build --target test -t platform-delivery-lab:test .
docker run --rm --network none platform-delivery-lab:test
.\scripts\verify-container.ps1
.\scripts\tests\test-smoke-failures.ps1
```

## Shell compatibility limits

End-to-end Docker checks ran under PowerShell **7.6.5**. The updated script parses without syntax errors under both Windows PowerShell **5.1.22621.4249** and 7.6.5. Small inline checks of the new stderr-capture pattern preserved native exit codes 0 and 7 and restored ErrorActionPreference in both shells.

Full script execution under 5.1 remains unverified because that shell's existing execution policy blocks script files. No execution policy was changed. Inline capture checks and parser checks do not constitute a full 5.1 smoke run.

The runtime application/image was unchanged by these review fixes; only tests, the verification script, and documentation changed. No CI or Kubernetes validation is claimed.
