#!/usr/bin/env bash

set -euo pipefail

: "${KEDIFY_TOKEN:?KEDIFY_TOKEN is required}"
: "${KEDIFY_CLUSTER_ID:?KEDIFY_CLUSTER_ID is required}"

if ! command -v kedify >/dev/null 2>&1; then
  echo "kedify binary not found on PATH" >&2
  exit 1
fi

if ! command -v helm >/dev/null 2>&1; then
  echo "helm binary not found on PATH" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq binary not found on PATH" >&2
  exit 1
fi

chart_path="${CHART_PATH:-chart}"
values_file="${VALUES_FILE:-${chart_path}/values.yaml}"
api_url="${KEDIFY_API_URL:-https://api.dev.kedify.io/v1}"
min_confidence="${KEDIFY_MIN_CONFIDENCE:-20}"
work_dir="${KEDIFY_WORK_DIR:-.kedify}"
recommendations_file="${work_dir}/recommendations.json"
results_dir="${work_dir}/results"

mkdir -p "${results_dir}"

echo "Fetching recommendations for cluster ${KEDIFY_CLUSTER_ID}" >&2
kedify --apiurl "${api_url}" --token "${KEDIFY_TOKEN}" \
  list recommendations "${KEDIFY_CLUSTER_ID}" --output json > "${recommendations_file}"

mapfile -t workloads < <(
  jq -r '
    map(select(.status == "waiting" and .kind == "Deployment"))
    | map({kind: (.kind | ascii_downcase), name, namespace})
    | unique_by(.kind, .name, .namespace)
    | .[]
    | @base64
  ' "${recommendations_file}"
)

if [ "${#workloads[@]}" -eq 0 ]; then
  echo "No waiting Deployment recommendations found." >&2
  exit 0
fi

patched_count=0
skipped_count=0
unexpected_failures=0

for encoded in "${workloads[@]}"; do
  workload_json="$(printf '%s' "${encoded}" | base64 --decode)"
  kind="$(printf '%s' "${workload_json}" | jq -r '.kind')"
  name="$(printf '%s' "${workload_json}" | jq -r '.name')"
  namespace="$(printf '%s' "${workload_json}" | jq -r '.namespace')"
  target="${kind}/${name}"
  result_file="${results_dir}/${kind}-${name}-${namespace}.json"

  echo "Applying recommendations for ${target} in namespace ${namespace}" >&2
  set +e
  kedify --apiurl "${api_url}" --token "${KEDIFY_TOKEN}" \
    apply recommendations "${target}" \
    --namespace "${namespace}" \
    --chart-path "${chart_path}" \
    --values-file "${values_file}" \
    --recommendations-file "${recommendations_file}" \
    --min-confidence "${min_confidence}" \
    --format json > "${result_file}"
  status=$?
  set -e

  cat "${result_file}"

  if [ "${status}" -eq 0 ]; then
    patched_count=$((patched_count + 1))
    continue
  fi

  if jq -e '.result == "failed"' "${result_file}" >/dev/null 2>&1; then
    if jq -e '
      [.reasons[]?.code]
      | length > 0
      and all(
        . == "not_found"
        or . == "unsupported"
        or . == "ambiguous"
        or . == "below_confidence_threshold"
      )
    ' "${result_file}" >/dev/null 2>&1; then
      skipped_count=$((skipped_count + 1))
      echo "Skipping ${target}: no safe patch could be produced for this demo chart." >&2
      continue
    fi
  fi

  unexpected_failures=$((unexpected_failures + 1))
  echo "Unexpected failure while applying ${target}." >&2
done

echo "Patched workloads: ${patched_count}" >&2
echo "Skipped workloads: ${skipped_count}" >&2

if [ "${unexpected_failures}" -gt 0 ]; then
  echo "Unexpected workload failures: ${unexpected_failures}" >&2
  exit 1
fi
