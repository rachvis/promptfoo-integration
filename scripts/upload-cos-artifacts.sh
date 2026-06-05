#!/usr/bin/env bash
set -euo pipefail

: "${COS_BUCKET:?Set COS_BUCKET to the IBM Cloud Object Storage bucket name}"

ARTIFACT_PREFIX="${ARTIFACT_PREFIX:-promptfoo/${PIPELINE_RUN_NAME:-manual}}"
RESULTS_FILE="${1:-promptfoo-results.json}"
REPORT_FILE="${2:-promptfoo-report.html}"

if ! command -v ibmcloud >/dev/null 2>&1; then
  echo "IBM Cloud CLI is required" >&2
  exit 2
fi

for file in "$RESULTS_FILE" "$REPORT_FILE"; do
  if [[ ! -f "$file" ]]; then
    echo "Artifact not found: $file" >&2
    exit 2
  fi

  ibmcloud cos object-put \
    --bucket "$COS_BUCKET" \
    --key "${ARTIFACT_PREFIX}/$(basename "$file")" \
    --body "$file"
done
