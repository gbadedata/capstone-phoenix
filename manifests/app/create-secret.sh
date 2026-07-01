#!/usr/bin/env bash
set -euo pipefail
# Generates random credentials and applies the Secret directly to the cluster (nothing in git).
# The app needs the password under TWO names:
#   POSTGRES_PASSWORD  -> initialises the Postgres container
#   DATABASE_PASSWORD  -> read by the backend's Alembic entrypoint (migrations/env.py)
#   DATABASE_URL       -> read by the Flask app itself
NS=taskapp
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

SECRET_KEY="$(openssl rand -hex 32)"
PG_PASSWORD="$(openssl rand -hex 16)"
DATABASE_URL="postgresql://taskuser:${PG_PASSWORD}@postgres:5432/taskmanager"

kubectl create secret generic taskapp-secret -n "$NS" \
  --from-literal=SECRET_KEY="$SECRET_KEY" \
  --from-literal=POSTGRES_PASSWORD="$PG_PASSWORD" \
  --from-literal=DATABASE_PASSWORD="$PG_PASSWORD" \
  --from-literal=DATABASE_URL="$DATABASE_URL" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secret 'taskapp-secret' created/updated in namespace '$NS'."
