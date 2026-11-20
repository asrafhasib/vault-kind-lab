#!/usr/bin/env bash
set -euo pipefail

kubectl apply -f kubernetes/namespaces.yaml
kubectl apply -f kubernetes/web-serviceaccount.yaml
kubectl apply -f kubernetes/web-deployment.yaml

kubectl rollout status deployment/web -n shop --timeout=240s

echo "Demo application deployed."
echo "Check injection: kubectl describe pod -n shop -l app=web"
echo "Check Agent logs: kubectl logs -n shop deployment/web -c vault-agent"
