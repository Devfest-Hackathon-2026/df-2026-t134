#!/usr/bin/env bash
# Run the existing Docker deployment targets using Actions' ephemeral ADC.
set -euo pipefail
: "${GOOGLE_APPLICATION_CREDENTIALS:?Authenticate with google-github-actions/auth first}"
credential_name="$(basename "$GOOGLE_APPLICATION_CREDENTIALS")"
[[ "$credential_name" == gha-creds-*.json ]] || { echo "Unexpected credential filename" >&2; exit 1; }
# Firebase CLI sees ADC through the bind mount; the credential is never printed.
exec make \
  COMPOSE="docker compose --env-file /dev/null -p ailearn-actions" \
  GCLOUD=gcloud \
  DEPLOY_PUBLIC_ACCESS= \
  FIREBASE_PROD="docker compose --env-file /dev/null -p ailearn-actions run --rm --no-deps -T -v $PWD:/workspace -e GOOGLE_APPLICATION_CREDENTIALS=/workspace/$credential_name firebase" \
  "$@"
