# Kubernetes verification: 2026-10-22

## Tested environment

- Windows x64, PowerShell 7.6.5, Docker Desktop Linux engine 29.7.2.
- kind v0.33.0, Helm v4.3.1, kubectl v1.36.4, downloaded from upstream releases and checked against pinned SHA-256 values.
- One-node cluster `platform-delivery-lab`, Kubernetes v1.36.4, using the node digest in `kind/cluster.yaml`.
- Local runtime image `platform-delivery-lab:0.1.0`, Docker image ID `sha256:6d97e72211d16f1a9e0ff9dc41a151a14819c490103279649448cd876164c0bf`.

## Observed local results

| Check | Result |
| --- | --- |
| Chart lint and rendering | Passed for development and staging. |
| Invalid values | Schema rejected zero replicas, non-boolean readiness, and empty image tag. |
| Cluster creation | Completed; node became ready. A dedicated `work/kubeconfig` was written. |
| Default kubeconfig | `kubectl config get-contexts` remained empty after setup and deployment. |
| Development release | Helm installed successfully; 1/1 updated, ready, available replica and one ready Service endpoint. |
| Staging release | Helm installed successfully; 2/2 updated, ready, available replicas and two ready Service endpoints. |
| Service HTTP requests | `/`, `/healthz`, `/readyz`, `/version` returned expected 200 JSON responses in each namespace. Requests used Service DNS from an application pod. |
| Environment metadata | `dev` and `staging`, both version `0.1.0`. |
| Runtime constraints | UID/GID 10001; actual root-filesystem write failed with EROFS; `/tmp` write/delete succeeded; no mounted API token. |
| Pod security | Non-root identity, RuntimeDefault seccomp, all capabilities dropped, privilege escalation disabled, read-only root, and token automount disabled. Namespaces enforce restricted Pod Security v1.36. |
| Runtime logs | No matched Gunicorn ERROR/CRITICAL entries or Python traceback during verification. |
| Repeat reconciliation | Both releases upgraded to Helm revision 2 and all checks passed again using the pinned kubectl binary. |
| Application pods | All three were Running/Ready with zero restarts at inspection. |

Local releases were left installed for owner inspection. The existing standalone demo on port 8080 and unrelated Docker containers were not modified.

## CI evidence

The workflow includes a separate `Helm and Kubernetes checks` job that creates and removes its own cluster on the runner. Actual run results are linked in [PR #1](https://github.com/uculica2001/platform-delivery-lab/pull/1) and the repository's Actions page; the local results above do not establish the CI conclusion.

## Reproduce and limitations

Follow [the Kubernetes walkthrough](../kubernetes-lab.md). No host Python installation is needed. The application image supplies Python for in-cluster requests.

This verifies a small local deployment, not production availability, performance, image provenance, vulnerability status, namespace network isolation, or recovery from a failed release. Two staging replicas share the same node. Readiness remains a startup flag rather than an external dependency check. The image base and transitive Python dependencies retain the limits recorded in the first container milestone.
