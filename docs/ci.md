# Continuous integration

The [CI workflow](../.github/workflows/ci.yml) runs on pull requests targeting `main` and pushes to `main`. Each run uses a fresh GitHub-hosted `ubuntu-24.04` runner. Updates to the same pull request cancel older in-progress runs.

## Checks

1. Record Docker and PowerShell versions in the run log.
2. Build the Docker `test` target.
3. Run pytest in a disposable test container with networking disabled.
4. Build the Docker `runtime` target as `platform-delivery-lab:ci`.
5. Run the existing ready/unready HTTP, identity, filesystem, runtime-log, and cleanup verification.
6. Run the five startup/cleanup fault-injection scenarios against that same runtime image.

The scripts receive the CI image explicitly through `-Image`. Docker executable discovery in the fault-injection harness uses the native application path rather than a Windows-specific filename.

## Execution and access

- The job has a 15-minute timeout.
- Its GitHub token has `contents: read` permission.
- The checkout action is pinned to the full commit SHA for v7.0.1 and does not persist credentials in the checkout.
- Pull request code runs under the ordinary `pull_request` event.
- Images are built and exercised inside the runner; this stage does not publish images or deploy infrastructure.
- Standard GitHub-hosted runners are free for public repositories according to [GitHub's runner documentation](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job).

## Inspect a result

Open the pull request's **Checks** tab and select **Application and container checks**, or open the repository's [CI runs](https://github.com/uculica2001/platform-delivery-lab/actions/workflows/ci.yml). Expand individual steps to inspect actual test output and fault-injection results.

A workflow definition alone does not establish that a run passed; use the run's commit, conclusion, and logs as evidence. Branch protection has not yet been configured to require the check before merging.

## Reproduce locally

```powershell
docker build --target test -t platform-delivery-lab:test .
docker run --rm --network none platform-delivery-lab:test
docker build --target runtime -t platform-delivery-lab:ci .
.\scripts\verify-container.ps1 -Image platform-delivery-lab:ci
.\scripts\tests\test-smoke-failures.ps1 -Image platform-delivery-lab:ci
```

Local script execution must be permitted by the existing shell policy. The first GitHub run also validates the PowerShell scripts on Linux; the prior local evidence was collected on Windows.
