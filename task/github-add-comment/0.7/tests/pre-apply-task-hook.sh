#!/usr/bin/env bash
set -e

# Create GitHub token secret if not already present
kubectl -n "${tns}" create secret generic github --from-literal token="secret" \
  || echo "Secret 'github' already exists in namespace ${tns}, continuing"

