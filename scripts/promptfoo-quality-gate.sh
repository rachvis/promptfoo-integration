#!/usr/bin/env bash
set -euo pipefail

RESULTS_FILE="${1:-promptfoo-results.json}"
MIN_PASS_RATE="${2:-95}"

if [[ ! -f "$RESULTS_FILE" ]]; then
  echo "Results file not found: $RESULTS_FILE" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 2
fi

SUCCESS_COUNT=$(jq -r '.results.stats.successes // 0' "$RESULTS_FILE")
FAILURE_COUNT=$(jq -r '.results.stats.failures // 0' "$RESULTS_FILE")
ERROR_COUNT=$(jq -r '.results.stats.errors // 0' "$RESULTS_FILE")
TOTAL_COUNT=$((SUCCESS_COUNT + FAILURE_COUNT + ERROR_COUNT))

if [[ "$TOTAL_COUNT" -eq 0 ]]; then
  echo "Quality gate failed: no promptfoo assertions were found in $RESULTS_FILE" >&2
  exit 1
fi

PASS_RATE=$(jq -nr --argjson successes "$SUCCESS_COUNT" --argjson total "$TOTAL_COUNT" '($successes / $total) * 100')
echo "Promptfoo assertions: successes=$SUCCESS_COUNT failures=$FAILURE_COUNT errors=$ERROR_COUNT pass_rate=${PASS_RATE}% minimum=${MIN_PASS_RATE}%"

if ! jq -en --argjson pass_rate "$PASS_RATE" --argjson min_pass_rate "$MIN_PASS_RATE" '$pass_rate >= $min_pass_rate' >/dev/null; then
  echo "Quality gate failed: ${PASS_RATE}% < ${MIN_PASS_RATE}%" >&2
  exit 1
fi

printf 'Quality gate passed: %.2f%% >= %s%%\n' "$PASS_RATE" "$MIN_PASS_RATE"
