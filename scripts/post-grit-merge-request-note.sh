#!/usr/bin/env bash
set -euo pipefail

: "${GRIT_API_TOKEN:?Set GRIT_API_TOKEN to a GRIT personal access token with api scope}"
: "${GRIT_PROJECT_ID:?Set GRIT_PROJECT_ID to the numeric GRIT/GitLab project ID}"
: "${GRIT_MERGE_REQUEST_IID:?Set GRIT_MERGE_REQUEST_IID to the merge request IID}"

GRIT_API_BASE_URL="${GRIT_API_BASE_URL:-https://us-south.git.cloud.ibm.com/api/v4}"
NOTE_JSON_FILE="${1:-merge-request-note.json}"

if [[ ! -f "$NOTE_JSON_FILE" ]]; then
  echo "Merge request note payload not found: $NOTE_JSON_FILE" >&2
  exit 2
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required" >&2
  exit 2
fi

curl --fail-with-body \
  --request POST \
  --header "PRIVATE-TOKEN: ${GRIT_API_TOKEN}" \
  --header "Content-Type: application/json" \
  --data @"$NOTE_JSON_FILE" \
  "${GRIT_API_BASE_URL}/projects/${GRIT_PROJECT_ID}/merge_requests/${GRIT_MERGE_REQUEST_IID}/notes"
