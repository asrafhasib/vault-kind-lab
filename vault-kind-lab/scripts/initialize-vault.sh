#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="vault"
POD="vault-0"
for bin in kubectl jq; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $bin" >&2
    exit 1
  }
done
LOCAL_DIR=".vault-local"
INIT_FILE="${LOCAL_DIR}/vault-init.json"

mkdir -p "$LOCAL_DIR"
chmod 700 "$LOCAL_DIR"

wait_for_vault() {
  for _ in $(seq 1 60); do
    # `vault status` exits 2 when Vault is sealed; that still means the API is reachable.
    if kubectl exec -n "$NAMESPACE" "$POD" -- sh -c \
      'vault status >/dev/null 2>&1; rc=$?; [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ]'; then
      return 0
    fi
    sleep 5
  done
  echo "ERROR: Vault did not become reachable." >&2
  exit 1
}

wait_for_vault

if [[ ! -f "$INIT_FILE" ]]; then
  echo "Initializing Vault. Initialization output will be stored locally in $INIT_FILE"
  kubectl exec -n "$NAMESPACE" "$POD" -- \
    vault operator init -key-shares=1 -key-threshold=1 -format=json > "$INIT_FILE"
  chmod 600 "$INIT_FILE"
else
  echo "Using existing local initialization file."
fi

UNSEAL_KEY="$(jq -r '.unseal_keys_b64[0]' "$INIT_FILE")"
ROOT_TOKEN="$(jq -r '.root_token' "$INIT_FILE")"

if [[ -z "$UNSEAL_KEY" || "$UNSEAL_KEY" == "null" || -z "$ROOT_TOKEN" || "$ROOT_TOKEN" == "null" ]]; then
  echo "ERROR: initialization file is missing expected fields." >&2
  exit 1
fi

if ! kubectl exec -n "$NAMESPACE" "$POD" -- vault status -format=json | jq -e '.sealed == false' >/dev/null; then
  kubectl exec -n "$NAMESPACE" "$POD" -- vault operator unseal "$UNSEAL_KEY" >/dev/null
fi

export VAULT_TOKEN="$ROOT_TOKEN"
export VAULT_ADDR="http://127.0.0.1:8200"

# Run Vault CLI inside the Vault pod; use the local root token only for this lab setup.
vault_exec() {
  kubectl exec -i -n "$NAMESPACE" "$POD" -- env VAULT_TOKEN="$ROOT_TOKEN" sh -c "$1"
}

if ! kubectl exec -n "$NAMESPACE" "$POD" -- env VAULT_TOKEN="$ROOT_TOKEN" vault secrets list -format=json | jq -e 'has("secret/")' >/dev/null; then
  vault_exec "vault secrets enable -path=secret kv-v2"
fi

vault_exec "vault kv put -mount=secret shop/dev/web api_key=REPLACE_WITH_TEST_VALUE db_user=webuser db_password=REPLACE_WITH_TEST_VALUE"

kubectl exec -i -n "$NAMESPACE" "$POD" -- sh -c "cat > /tmp/shop-dev-policy.hcl" < policies/shop-dev-policy.hcl
vault_exec "vault policy write shop-dev-policy /tmp/shop-dev-policy.hcl"

if ! kubectl exec -n "$NAMESPACE" "$POD" -- env VAULT_TOKEN="$ROOT_TOKEN" vault auth list -format=json | jq -e 'has("kubernetes/")' >/dev/null; then
  vault_exec "vault auth enable kubernetes"
fi

# Kubernetes service environment variables are available inside the Vault pod.
vault_exec 'vault write auth/kubernetes/config kubernetes_host="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}"'

vault_exec "vault write auth/kubernetes/role/web-dev bound_service_account_names=web bound_service_account_namespaces=shop policies=shop-dev-policy ttl=1h"

echo "Vault initialized and configured."
echo "Local root token and unseal key are in $INIT_FILE (never commit this file)."
echo "Next: ./scripts/deploy-demo-app.sh"
