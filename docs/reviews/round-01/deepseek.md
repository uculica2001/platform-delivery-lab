I reviewed only the attachment. I did not execute Docker/PowerShell or fetch the live branch/PR, and I did not verify package availability or Gunicorn CLI behavior from external documentation.

## Substantiated findings

### 1. Low — Smoke script downgrades cleanup failure to a warning and still reports success

**File/block:** `scripts/verify-container.ps1`, inner `finally` block after each container run.

**Trigger:** `docker stop --time 5 $containerName` returns a non-zero exit code, e.g. Docker daemon/permission problem or a stuck container. A container that already exited and was auto-removed by `--rm` can also make `docker stop` return non-zero.

**Expected:** A cleanup failure should either be retried with forced removal and/or fail the verification. The final message should not claim containers were stopped if cleanup failed.

**Actual:** The script only emits `Write-Warning "Check cleanup for container: $containerName"`, continues the loop, and later prints `Container verification passed; temporary containers stopped.` A container can therefore be left behind while the script still exits successfully.

**Evidence in source:**
```powershell
if ($containerId) {
    docker stop --time 5 $containerName | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Warning "Check cleanup for container: $containerName" }
}
```
and later:
```powershell
Write-Output 'Container verification passed; temporary containers stopped.'
```

**Assumption needing verification:** Docker `stop` can fail for reasons other than “container already gone”. The “already gone” case is benign but should be distinguished from a real cleanup failure.

**Verification procedure:** In a disposable PowerShell session, define a `docker` shim/function that delegates to real `docker.exe` except for `stop`, where it sets `$LASTEXITCODE = 1` and returns. Run the smoke script and observe that it warns but still ends with the success message. Alternatively, reason from the code path.

**Smallest reasonable fix:** On `docker stop` failure, attempt `docker rm -f $containerName`. Treat “no such container” as already cleaned; otherwise throw/fail the script. Only print the final “temporary containers stopped” message after cleanup is confirmed.

---

### 2. Low — Permission PASS line claims read-only filesystem and user=10001 but only checks UID

**File/block:** `scripts/verify-container.ps1`, after `docker exec $containerName id -u`.

**Trigger:** The runtime image’s GID changes, or the `--read-only` flag is removed/misconfigured, or the root filesystem becomes writable. The script still prints:
```powershell
PASS APP_READY=$ready, user=10001, read-only filesystem
```
because it only checked `id -u`.

**Expected:** The smoke check should verify the intended runtime constraints: UID 10001, GID 10001, and read-only root filesystem. At minimum it should not print a PASS for checks it did not perform.

**Actual:** Only UID is checked:
```powershell
$containerUid = docker exec $containerName id -u
if ($LASTEXITCODE -ne 0 -or $containerUid.Trim() -ne '10001') { throw 'Unexpected container user' }
Write-Output "PASS APP_READY=$ready, user=10001, read-only filesystem"
```
There is no `id -g` check and no `docker inspect`/write-failure check for read-only root.

**Evidence in source:** The `docker run` command includes `--read-only`, but the script never verifies that the container actually has a read-only root. The PASS text is therefore broader than the assertion.

**Verification procedure:** In a disposable copy of the script, remove `--read-only` from the `docker run` line. The container will still start and the script will still print `PASS ... read-only filesystem`, demonstrating the false assertion. Separately, change the Dockerfile’s GID to something else; the UID check still passes.

**Smallest reasonable fix:** Add checks such as:
```powershell
$containerGid = docker exec $containerName id -g
if ($LASTEXITCODE -ne 0 -or $containerGid.Trim() -ne '10001') { throw 'Unexpected container group' }
$readOnly = docker inspect --format '{{.HostConfig.ReadonlyRootfs}}' $containerName
if ($readOnly.Trim() -ne 'true') { throw 'Root filesystem is not read-only' }
```
or attempt a write under `/service` and assert it fails.

---

### 3. Low — Tests do not cover the specified `APP_READY` trim/lowercase normalization

**File/block:** `tests/test_app.py`, readiness configuration tests.

**Trigger:** A regression removes or breaks `os.getenv("APP_READY", "true").strip().lower()` in `create_app()`. For example, changing it to `os.getenv("APP_READY", "true")` still passes the current tests because they only exercise `"false"`, default, and invalid `"yes"`, `"1"`, `""`.

**Expected:** The tests should cover the specified normalization behavior: values like `" TRUE "` should be accepted as ready, and `" False "` should produce `not_ready`. Invalid values with surrounding whitespace should still fail.

**Actual:** No test uses mixed case or surrounding whitespace. The current tests would not catch loss of `.strip().lower()`.

**Evidence in source:** The invalid-value parametrization is only:
```python
@pytest.mark.parametrize("value", ["yes", "1", ""])
```
and the unready test uses only:
```python
monkeypatch.setenv("APP_READY", "false")
```

**Verification procedure:** In a disposable copy, remove `.strip().lower()` from `app/__init__.py` and run `pytest`. The current suite still passes, demonstrating the gap.

**Smallest reasonable fix:** Add parametrized cases such as:
```python
@pytest.mark.parametrize(("value", "status"), [
    (" TRUE ", 200),
    (" False ", 503),
    (" TrUe ", 200),
    (" FaLsE ", 503),
])
```
and assert `/readyz` status/body. Optionally add an invalid whitespace case like `" yes "`.

---

## Unverified concerns

- I could not verify from the attachment whether `gunicorn==26.2.0` supports the `--no-control-socket` option used in the runtime `CMD`. If that option is not recognized, the runtime container will fail at startup. This should be confirmed by building/running the image or checking `gunicorn --help` in the built image.
- I did not verify that the pinned versions `Flask==3.1.3`, `gunicorn==26.2.0`, and `pytest==9.1.1` are available for the target Python/base image; that requires a build or package-index lookup.

## Optional improvements

- Add a smoke case that starts the container with an invalid `APP_READY` value and asserts that the container exits non-zero, covering the container-level startup-failure path.
- Add a unit test for `/` and for the default `/version` metadata (`0.1.0`, `development`), since those routes are currently only covered indirectly by the smoke script or not at all.

## Recommendation

**Ready for owner review.** I found no High or Medium functional defects in the application or Dockerfile based on the attachment. The findings are low-severity verification/test gaps: the smoke script overstates what it checked and does not fail on cleanup failure, and the tests miss the explicitly specified `APP_READY` normalization. Confidence would increase after actually building the image and running the smoke script, especially to confirm the Gunicorn CLI option support.