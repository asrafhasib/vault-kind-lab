#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="vault"
RELEASE="vault"
CHART_VERSION="${VAULT_CHART_VERSION:-}"

for bin in kubectl helm kind; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $bin" >&2
    exit 1
  }
done

kubectl cluster-info >/dev/null

if ! kubectl get storageclass local-path >/dev/null 2>&1; then
  echo "Installing local-path storage provisioner..."
  kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
  kubectl rollout status deployment/local-path-provisioner -n local-path-storage --timeout=180s
fi

kubectl apply -f kubernetes/namespaces.yaml

helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

args=()
if [[ -n "$CHART_VERSION" ]]; then
  args+=(--version "$CHART_VERSION")
fi

helm upgrade --install "$RELEASE" hashicorp/vault \
  --namespace "$NAMESPACE" \
  --values vault/values.yaml \
  "${args[@]}"

kubectl rollout status statefulset/vault -n "$NAMESPACE" --timeout=300s
echo "Vault installed. Next: ./scripts/initialize-vault.sh"
