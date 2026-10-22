# Independent review: platform-delivery-lab @ 7f61c43

I did not execute any code, so everything below comes from reading the attachment. Runtime claims are labelled as such and come with verification steps.

## Substantiated findings

### 1. Medium: `docker logs ... 2>&1` can abort a passing run on Windows PowerShell 5.1

- **File/block:** `scripts/verify-container.ps1`, the `$containerLogs = docker logs $containerName 2>&1 | Out-String` line inside the per-`$ready` loop.
- **Trigger:** The script runs under Windows PowerShell 5.1 (`powershell.exe`) with `$ErrorActionPreference = 'Stop'` set at the top. The container has emitted anything on stderr. Gunicorn does: `--error-logfile=-` sends its startup lines (`Starting gunicorn`, `Listening at`, `Booting worker`) to stderr.
- **Expected:** After all HTTP assertions pass, the log scan runs, and the script prints `PASS no runtime errors found in container logs`.
- **Actual (predicted):** In 5.1, merging a native command's stderr with `2>&1` wraps each stderr line in an `ErrorRecord`. Under `Stop` that becomes a terminating `NativeCommandError` before the `Out-String`/regex check runs. The script would fail on a healthy container. In PowerShell 7+ this normally does not happen.
- **Evidence:** The `2>&1` redirection and the global `Stop` preference are both in the source. The package names the environment "Windows PowerShell", which suggests 5.1, but doesn't state the version. That's the assumption to verify.
- **Verify:**
  - Minimal, no Docker: `powershell.exe -NoProfile -Command "$ErrorActionPreference='Stop'; cmd /c 'echo x 1>&2' 2>&1 | Out-String"`. Compare with the same command in `pwsh`.
  - Full: run the script with `powershell.exe -File scripts\verify-container.ps1` and with `pwsh -File ...`, and compare.
- **Smallest fix:** Relax the preference just for this call:
  ```powershell
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $containerLogs = docker logs $containerName 2>&1 | Out-String
  $logExit = $LASTEXITCODE
  $ErrorActionPreference = $old
  if ($logExit -ne 0) { throw 'Could not read container logs' }
  ```

### 2. Low: `--rm` discards the logs that the failure path tries to print

- **File/block:** `scripts/verify-container.ps1`, the `docker run --detach --rm` call and the `if (-not $started) { docker logs ...; throw }` block.
- **Trigger:** The container exits during startup, for example with a Gunicorn boot failure, a bad flag, or a bad dependency. Because of `--rm`, Docker deletes it on exit.
- **Expected:** The script prints the container's logs and then throws "Application did not become reachable".
- **Actual (predicted):** `docker logs $containerName` returns "No such container", so the diagnostic is lost. If the container dies before `docker port` runs, the script throws "Could not identify the published port" with no logs at all.
- **Evidence:** `--rm` is combined with log retrieval that happens only after readiness polling fails.
- **Verify:** Run the script with an image whose CMD exits immediately. A temporary `--env APP_READY=maybe` also works, since a Gunicorn worker fails to boot on invalid config. Observe that no application error text is printed.
- **Smallest fix:** Drop `--rm`. In `finally`, replace `docker stop` with `docker rm --force $containerName | Out-Null`. This also covers the exited-container case, where `docker stop` currently only warns. The `$containerId` guard can stay.

### 3. Low: the documented `APP_READY` normalization (trim and lowercase) has no test

- **File/block:** `tests/test_app.py`, the invalid-value parametrization and the unready test. The target is `create_app()`.
- **Trigger:** A regression that removes `.strip()` or `.lower()`, or changes the matching.
- **Expected:** The package says `APP_READY` "accepts true/false after trimming and lowercasing", so `" FALSE "` should give a 503 and `" True "` should give a 200.
- **Actual:** Only the exact lowercase `"false"` and the invalid values `yes`, `1`, `""` are tested. Nothing would fail if normalization were removed. The current implementation appears correct, so this is a test gap rather than a code defect.
- **Verify:** Mutate `app/__init__.py` to drop `.strip().lower()` and run pytest. I expect all tests to still pass.
- **Smallest fix:**
  ```python
  @pytest.mark.parametrize("value,status", [(" FALSE ", 503), ("  True", 200)])
  def test_readiness_flag_is_trimmed_and_case_insensitive(monkeypatch, value, status):
      monkeypatch.setenv("APP_READY", value)
      assert create_app().test_client().get("/readyz").status_code == status
  ```

## Unverified concerns (not claimed as defects)

- **Pinned versions and Gunicorn flag.** I can't confirm from the attachment that `gunicorn==26.2.0` supports `--no-control-socket`, or that `Flask==3.1.3` and `pytest==9.1.1` resolve. An unknown flag would make the runtime container exit at startup. Check with `docker build --target runtime .` followed by `docker run --rm platform-delivery-lab:0.1.0 gunicorn --help | grep control`. Better still, run the smoke script, which exercises the real startup path.
- **Read-only/tmpfs behavior.** The Dockerfile and flags look consistent: bytecode writing is off, the worker temp dir is `/tmp`, and the port is above 1024. I haven't observed it running. The smoke script's own `--read-only --tmpfs /tmp` run is the right check.
- **Venv portability between stages.** Copying `/opt/venv` from `dependencies` into `runtime` works because both use `python:3.13-slim`. It would break if the two stages ever resolved to different base images, for example after a digest pin applied to only one stage.

## Optional improvements (max 3)

1. Add `**/__pycache__` to `.dockerignore` so local bytecode in `app/` or `tests/` can't enter the build context.
2. Have the script's PASS line say "started with read-only filesystem" or actually verify it, for example with `docker exec ... sh -c 'touch /x'` expecting failure. As written, "read-only filesystem" is asserted only implicitly by the container starting.
3. Add a one-line `/` endpoint test to the pytest suite. It is currently covered only by the smoke script.

## Recommendation: changes needed (minor)

The application code, the Dockerfile, and the dependency and ignore files look correct against the stated intent, and I found no application-level defects. The main reason for "changes needed" is finding 1: on the stated Windows PowerShell environment, the smoke script may fail on a healthy container at its final check. Findings 2 and 3 are small. The limits are that nothing was executed, the shell version is unspecified, and the dependency versions and Gunicorn flag are unconfirmed. Re-review after one real run of the script under both `powershell.exe` and `pwsh`.