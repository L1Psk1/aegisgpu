#!/usr/bin/env bash
set -euo pipefail

# Reproducible Calico setup for the AegisGPU Kind lab.
# Run from the repository root after creating the Kind cluster.
CALICO_VERSION="v3.33.0"
POD_CIDR="10.245.0.0/16"
EXPECTED_CONTEXT="kind-aegisgpu-secnet"
MANIFEST="$(mktemp -t aegisgpu-calico.XXXXXX.yaml)"
trap 'rm -f "$MANIFEST"' EXIT

command -v curl >/dev/null || { echo 'curl is required' >&2; exit 1; }
command -v kubectl >/dev/null || { echo 'kubectl is required' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'python3 is required' >&2; exit 1; }

CONTEXT="$(kubectl config current-context)"
if [[ "$CONTEXT" != "$EXPECTED_CONTEXT" ]]; then
  echo "Wrong cluster context: $CONTEXT (expected: $EXPECTED_CONTEXT)" >&2
  exit 1
fi

# Review network ranges before using the Pod CIDR on a different machine.
curl --fail --location --silent --show-error --retry 3 \
  "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml" \
  -o "$MANIFEST"

python3 - "$MANIFEST" "$POD_CIDR" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
cidr = sys.argv[2]
source = path.read_text()
old = '''            # - name: CALICO_IPV4POOL_CIDR
            #   value: "192.168.0.0/16"'''
new = f'''            - name: CALICO_IPV4POOL_CIDR
              value: "{cidr}"'''
if source.count(old) != 1:
    raise SystemExit("Calico manifest changed: expected IP-pool stanza not found exactly once")
path.write_text(source.replace(old, new))
print(f"Prepared Calico IP pool: {cidr}")
PY

kubectl --context "$EXPECTED_CONTEXT" apply -f "$MANIFEST"
echo "Calico ${CALICO_VERSION} applied. Check progress with:"
echo "  kubectl --context ${EXPECTED_CONTEXT} get pods -n kube-system"
echo "  kubectl --context ${EXPECTED_CONTEXT} get nodes"
