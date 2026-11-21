# AegisGPU — Kubernetes Workload Security Lab

AegisGPU is a reproducible, local **Kubernetes workload-security lab** built around a small Python FastAPI service. It demonstrates container hardening, least-privilege workload identity, and **Calico-enforced ingress and egress NetworkPolicies**, with positive and negative connectivity tests.

> **Scope:** This is a security engineering learning and validation environment, **not** a production GPU service, model-inference platform, or production-grade Kubernetes deployment. The `/predict` endpoint is deliberately minimal: it multiplies an input number by two.

## Architecture

```text
   client-allowed (role=allowed-client)
                  |
                  | ingress: TCP/8000 ALLOW
                  v
          aegisgpu-service (ClusterIP)
                  |
            +-----+-----+
            |     |     |
          Pod 1 Pod 2 Pod 3  (FastAPI :8000)
            |     |     |
            +-----+-----+
                |
           egress: DENY

   client-denied (role=untrusted-client)
                  X ingress: blocked

   Kubernetes: kind | Networking: Calico | Pod CIDR: 10.245.0.0/16
```

The application uses three replicas with Kubernetes health probes, CPU/memory requests and limits, ConfigMap-provided settings, and a locally created Kubernetes Secret. The service is reachable through `kubectl port-forward` for development; **port-forward is not an ingress NetworkPolicy enforcement test**.

## Security controls

| Control | Implementation | Validation performed |
| --- | --- | --- |
| Non-root execution | Docker `USER 10001:10001`; Pod `runAsNonRoot`, `runAsUser`, `runAsGroup` | `docker ... id` and `kubectl exec ... id` showed UID 10001 |
| Filesystem protection | `readOnlyRootFilesystem: true` | Writing `/app/security-test` was denied with a read-only filesystem error |
| Process restrictions | `allowPrivilegeEscalation: false`, drop `ALL` Linux capabilities, `seccompProfile: RuntimeDefault` | Confirmed applied Pod/container securityContext configuration; no separate exploit-based test |
| Workload identity | Dedicated `aegisgpu-api-sa`, `automountServiceAccountToken: false` | Token absent from standard mounted path; service account denied `list secrets` in default namespace |
| Ingress isolation | `k8s/networkpolicy.yaml` permits same-namespace Pods labeled `role=allowed-client` to API Pods on TCP 8000 | Allowed client returned HTTP 200; untrusted client timed out |
| Egress isolation | `k8s/egress-policy.yaml` selects API Pods and declares `egress: []` | Control client reached test server with HTTP 200; API Pod TCP connection to test server timed out |

NetworkPolicies work through the chosen CNI and are **additive**. The ingress policy is based on Pod labels, not end-user authentication; a party allowed to change Pod labels or create matching Pods could bypass this trust assumption. This lab does not test restrictions on node/host traffic, all control-plane paths, or every possible egress destination.

## Threat model (lab scope)

**Assets:** application availability, Kubernetes workload runtime boundary, cluster API credentials, secrets provided to the application, and intra-cluster connectivity.

**Adversarial scenarios and mitigations:**

- **Container compromise or unsafe application behavior:** run unprivileged, use a read-only root filesystem, drop capabilities, disable privilege escalation, and apply runtime-default seccomp.
- **Stolen Kubernetes service-account credentials:** do not automatically mount the application service-account token; do not grant it additional RBAC privileges.
- **Lateral access to the API from another Pod:** isolate application ingress and allow only approved, labeled client Pods on TCP 8000.
- **Unnecessary outbound connections from a compromised API Pod:** impose default-deny egress in the lab.

**Residual risks:** No production authentication/authorization implementation, image-signature verification, admission control, secrets rotation, security monitoring/SIEM, policy-as-code CI gate, multi-node/network-failure testing, or demonstrated GPU isolation. The example Kubernetes Secret is configuration input, not a substitute for a managed secrets system. No user-facing API key authentication is claimed.

## Prerequisites

- Linux host or VM with Docker, `kind`, `kubectl`, Git and Python 3.
- A Docker-compatible environment where `kind` can create a local node.
- Sufficient resources for Kubernetes and Calico (the original lab was run in a small VM).
- Choose a Pod CIDR that **does not overlap** the host, VM, VPN, or Docker networks. The supplied Kind config uses `10.245.0.0/16`, which worked in the original test environment but may need adjustment elsewhere.

The project was validated with **Kubernetes v1.34.0 (kind v0.30.0)** and **Calico v3.33.0**.

## Reproduce the security lab

```bash
# From the repository root:
kind create cluster --name aegisgpu-secnet --config lab/kind-calico.yaml
kubectl config use-context kind-aegisgpu-secnet

# Install the pinned Calico manifest with the matching Pod CIDR:
bash lab/install-calico.sh
kubectl wait --for=condition=Ready node/aegisgpu-secnet-control-plane --timeout=180s
kubectl get pods -n kube-system

# Build the application and make it available in the kind node:
docker build -t aegisgpu-api:v2 .
kind load docker-image aegisgpu-api:v2 --name aegisgpu-secnet

# Local test-only secret: never commit k8s/secret.yaml.
cp k8s/secret.example.yaml k8s/secret.yaml
# Replace "replace-me" in k8s/secret.yaml with a disposable lab-only value.

# Apply dependencies before workload and policies:
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/serviceaccount.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl rollout status deployment/aegisgpu-api --timeout=120s
kubectl apply -f k8s/networkpolicy.yaml
kubectl apply -f k8s/egress-policy.yaml
kubectl get pods -o wide
kubectl get networkpolicy
```

If your local copy of `k8s/secret.yaml` already exists, **do not overwrite it** with the `cp` command. The default-deny egress policy is designed for this simple application, which does not need general outbound network access; real applications may require explicit DNS or dependency exceptions.

## Use the API

In a separate terminal:

```bash
kubectl --context kind-aegisgpu-secnet port-forward svc/aegisgpu-service 8000:8000
```

Examples:

```bash
curl http://localhost:8000/
curl -X POST http://localhost:8000/predict \
  -H 'Content-Type: application/json' \
  -d '{"value": 21}'
# Expected prediction: 42.0
```

## Security validation: recorded lab results

The following results were observed during a local test of the security-hardening branch (21 November 2026):

| Source | Destination | Result | Meaning |
| --- | --- | --- | --- |
| `client-allowed` (`role=allowed-client`) | `aegisgpu-service:8000` | HTTP 200 | Ingress allow rule worked |
| `client-denied` (`role=untrusted-client`) | `aegisgpu-service:8000` | Timeout | Ingress deny-by-default worked |
| Unrestricted control client | `egress-test-server:8080` (Pod IP) | HTTP 200 | Server and networking were functioning |
| AegisGPU application Pod | `egress-test-server:8080` (Pod IP) | TCP timeout | Egress default-deny was enforced |

The test clients and test server were created with `kubectl run` and are **temporary lab resources**, not checked-in production manifests. A timeout by itself would be ambiguous; the successful control connection to the same server is important evidence. Results describe this tested configuration, not a universal guarantee for other environments.

### Additional workload checks

```bash
kubectl exec deployment/aegisgpu-api -- id
kubectl exec deployment/aegisgpu-api -- sh -c 'touch /app/security-test'
kubectl exec deployment/aegisgpu-api -- sh -c \
  'test ! -e /var/run/secrets/kubernetes.io/serviceaccount/token && echo "No API token mounted"'
kubectl auth can-i list secrets --as=system:serviceaccount:default:aegisgpu-api-sa -n default
```

Expected: UID 10001, filesystem write denied, no mounted service-account token, and `no` for the tested RBAC permission.

## Repository layout

```text
app/                 FastAPI example workload
k8s/                 Deployment, Service, ConfigMap, example Secret,
                     ServiceAccount, ingress and egress NetworkPolicies
lab/kind-calico.yaml Kind configuration with default CNI disabled
lab/install-calico.sh Pin and configure Calico for the lab Pod CIDR
Dockerfile           Non-root Python container image
README.md            Architecture, scope, setup, and security results
```

## Design trade-offs and next steps

- The lab uses one Kind control-plane node; it does not validate high availability or cross-node network policies.
- Cluster-wide network-policy enforcement depends on Calico being correctly installed; the default Kind CNI alone does not provide this enforcement.
- Default-deny egress is appropriate for this small API but must be extended deliberately when adding DNS queries, external inference services, telemetry exporters, or real model-serving dependencies.
- Workload identity is a dedicated Kubernetes ServiceAccount, **not** a demonstrated external cloud workload identity federation flow.
- Future work could include CI validation, dependency/image scanning, admission policies, secret-management integration, metrics/alerts, and automated security regression tests.

## Status

**Security hardening v2 — implemented and manually validated in a local Kind + Calico lab.**
