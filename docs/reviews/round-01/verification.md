# Independent development review 01: verified comparison

Reviewed snapshot: `7f61c435b06cc5393ce1ccd96e96aeba27ebfc73`.

Both original responses have been preserved alongside this report. The user identified the providers as Claude and DeepSeek; exact interface model labels, settings, and elapsed review times were not provided. Both reviewers explicitly stated that they had not executed code.

This is a development review, not the later seeded-defect benchmark. There is no predetermined defect register, and these results do not support a general ranking of models.

## Deduplicated observations

| Observation | Claude | DeepSeek | Verification and disposition |
| --- | --- | --- | --- |
| Redirected native stderr can terminate execution with ErrorActionPreference=Stop in Windows PowerShell 5.1 | Medium finding | Not reported | Mechanism reproduced on 5.1.22621.4249; the same inline probe succeeds on 7.6.5. Conditional compatibility defect: full smoke execution on 5.1 was blocked by the existing script execution policy. |
| Auto-removal discards startup failure logs | Low finding | Related cleanup discussion | Reproduced using APP_READY=invalid: with --rm the container exits 3 and docker logs fails; without --rm the same application error is retained. Diagnostics defect confirmed. |
| Cleanup failure is only warned about and final output still reports successful cleanup | Not reported as a standalone finding | Low finding | Reproduced by injecting failure only for docker stop. The original smoke script printed its success message while both verification containers were still running. Probe cleanup then removed both exact container IDs. |
| Readiness normalization has no regression coverage | Low test gap | Low test gap | Removed .strip().lower() only inside a disposable test container. All eight existing tests still passed, demonstrating the gap. Current application behavior is correct. |
| Runtime-constraint PASS text could use stronger direct checks | Optional improvement | Low verification gap | Source inspection confirms UID is explicitly checked and --read-only is supplied to docker run. GID and ReadonlyRootfs are not separately queried. Treat as verification hardening; no currently writable-root or wrong-GID defect was demonstrated. |

## Evidence

### Shell compatibility

A small inline command redirects native stderr under ErrorActionPreference=Stop without running a script file or changing policy:

```text
PowerShell 5.1.22621.4249: Terminated=true, ErrorId=NativeCommandError
PowerShell 7.6.5: Terminated=false, NativeExit=0, Captured=stderr-probe
```

An attempt to run the complete existing smoke script under powershell.exe was blocked before execution because script execution is disabled for that shell. This is an environment limitation, not a reproduction of the reported log-capture failure. No execution policy was changed.

Microsoft documents the redirected-stderr behavior change beginning with PowerShell 7.2, so "PowerShell 7+" is not a precise compatibility boundary: [about_Preference_Variables](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_preference_variables?view=powershell-7.5).

### Lost startup logs

```text
AutoRemove=true:  ContainerExit=3, LogsCommandExit=1, AppErrorRetained=false, ContainerMissing=true
AutoRemove=false: ContainerExit=3, LogsCommandExit=0, AppErrorRetained=true,  ContainerMissing=false
```

The failure was intentionally caused by invalid readiness configuration in disposable containers, with no host source mounted. Retained containers were explicitly removed after inspection.

### False cleanup success

```text
StopFailuresInjected=2
SuccessMessagePrinted=true
ContainersStillRunningBeforeProbeCleanup=2
```

Only the stop operation was simulated. The existing script otherwise ran its real HTTP and log checks against real containers. Both container IDs created by the probe were explicitly removed in the probe's final cleanup. The user-facing demo container was not targeted.

### Missing normalization regression test

```text
Mutation applied only inside a disposable container: removed readiness normalization
8 passed in 0.37s
```

The mutation was applied before importing the application, inside the existing test image with networking disabled. Project source and tests on the host were not changed.

## Concerns already resolved by previous execution evidence

Both models correctly marked package availability and Gunicorn flag support as unverified rather than claiming defects. Earlier builds resolved the pinned dependencies, and the actual runtime command with --no-control-socket passed HTTP/log checks. These concerns do not currently require code changes and should not be counted as false findings.

## Proposed correction scope

1. Make native log capture safe for the supported shell versions and document the actual shell requirement. Restore any temporarily changed error preference with try/finally. Do not alter the user's execution policy.
2. Retain verification containers until diagnostics are collected. Explicitly remove only containers created by the script and fail clearly when cleanup cannot be confirmed.
3. Add readiness tests for mixed case and surrounding whitespace; verify that those tests catch removal of normalization.
4. Clarify or directly verify the runtime constraints reported by the smoke script. A failed write by a non-root user alone is not proof of a read-only root filesystem; checking Docker's ReadonlyRootfs configuration distinguishes filesystem policy from directory permissions.
5. Repeat only the relevant application and smoke/failure-path checks after the corrections, then update the existing draft PR.

No application or tracked implementation file was modified during this validation round.
