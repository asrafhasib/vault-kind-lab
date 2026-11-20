#!/usr/bin/env bash
set -euo pipefail

echo "== Vault resources =="
kubectl get pods,pvc,svc -n vault

echo
echo "== Application resources =="
kubectl get pods,serviceaccounts -n shop

POD="$(kubectl get pod -n shop -l app=web -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -z "$POD" ]]; then
  echo "ERROR: web pod not found. Run ./scripts/deploy-demo-app.sh" >&2
  exit 1
fi

echo
echo "== Injected secret file check (does not print secret values) =="
kubectl exec -n shop "$POD" -c web -- \
  sh -c 'test -s /vault/secrets/db.properties && echo "PASS: injected secret file exists"'

echo
echo "== Vault Agent container status =="
kubectl get pod -n shop "$POD" -o jsonpath='{range .status.containerStatuses[*]}{.name}{" => "}{.ready}{"\n"}{end}'

echo
echo "== Recent Vault Agent logs =="
kubectl logs -n shop "$POD" -c vault-agent --tail=30
