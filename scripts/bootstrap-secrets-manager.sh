#!/usr/bin/env bash
set -euo pipefail

# Creates or rotates the Secrets Manager arbitrary secrets expected by the Tekton pipelines.
# Required environment variables: SECRETS_MANAGER_URL, OPENAI_API_KEY_VALUE.
# Optional environment variables: PROMPTFOO_API_KEY_VALUE, GRIT_API_TOKEN_VALUE, SECRET_GROUP_NAME.

: "${SECRETS_MANAGER_URL:?Set SECRETS_MANAGER_URL to your Secrets Manager endpoint URL}"
: "${OPENAI_API_KEY_VALUE:?Set OPENAI_API_KEY_VALUE to the provider key to store}"

SECRET_GROUP_NAME="${SECRET_GROUP_NAME:-default}"

if ! command -v ibmcloud >/dev/null 2>&1; then
  echo "IBM Cloud CLI is required" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 2
fi

create_or_rotate_arbitrary_secret() {
  local name="$1"
  local value="$2"

  if [[ -z "$value" ]]; then
    echo "Skipping empty secret $name"
    return 0
  fi

  local existing_json
  if existing_json=$(ibmcloud secrets-manager secret-by-name \
      --service-url "$SECRETS_MANAGER_URL" \
      --secret-type arbitrary \
      --name "$name" \
      --secret-group-name "$SECRET_GROUP_NAME" \
      --output json 2>/dev/null); then
    local id
    id=$(jq -r '.id' <<<"$existing_json")
    echo "Creating a new version for existing secret $name"
    ibmcloud secrets-manager secret-version-create \
      --service-url "$SECRETS_MANAGER_URL" \
      --secret-id "$id" \
      --arbitrary-payload "$value"
  else
    echo "Creating secret $name"
    ibmcloud secrets-manager secret-create \
      --service-url "$SECRETS_MANAGER_URL" \
      --secret-name "$name" \
      --secret-type arbitrary \
      --secret-group-id "$SECRET_GROUP_NAME" \
      --arbitrary-payload "$value"
  fi
}

create_or_rotate_arbitrary_secret OPENAI_API_KEY "$OPENAI_API_KEY_VALUE"
create_or_rotate_arbitrary_secret PROMPTFOO_API_KEY "${PROMPTFOO_API_KEY_VALUE:-}"
create_or_rotate_arbitrary_secret GRIT_API_TOKEN "${GRIT_API_TOKEN_VALUE:-}"
