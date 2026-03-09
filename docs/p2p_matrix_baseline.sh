#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash docs/p2p_matrix_baseline.sh <log_file> <scenario_id> [output_jsonl]

Example:
  bash docs/p2p_matrix_baseline.sh ./logs/s1_p1.log S1-P1 ./logs/p2p_baseline.jsonl
EOF
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage
  exit 1
fi

log_file="$1"
scenario_id="$2"
output_jsonl="${3:-}"

if [[ ! -f "$log_file" ]]; then
  echo "log file not found: $log_file" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required but not found in PATH" >&2
  exit 1
fi

tmp_events="$(mktemp)"
tmp_elapsed="$(mktemp)"
trap 'rm -f "$tmp_events" "$tmp_elapsed"' EXIT

grep -F "event.p2p." "$log_file" >"$tmp_events" || true

count_event() {
  local event_name="$1"
  grep -F -c "event.p2p.${event_name}" "$tmp_events" || true
}

extract_payload_lines() {
  local event_name="$1"
  grep -F "event.p2p.${event_name} " "$tmp_events" \
    | sed -E 's/^.*event\.p2p\.[a-z_]+[[:space:]]+//'
}

calc_rate() {
  local numerator="$1"
  local denominator="$2"
  awk -v n="$numerator" -v d="$denominator" 'BEGIN {
    if (d <= 0) {
      printf "%.6f", 0;
    } else {
      printf "%.6f", n / d;
    }
  }'
}

calc_p95() {
  local file="$1"
  if [[ ! -s "$file" ]]; then
    echo 0
    return
  fi
  sort -n "$file" | awk '
    {vals[++count] = $1}
    END {
      if (count == 0) {
        print 0;
        exit;
      }
      idx = int((count * 95 + 99) / 100);
      if (idx < 1) idx = 1;
      if (idx > count) idx = count;
      print vals[idx];
    }'
}

total_attempts="$(count_event "direct_attempt_started")"
direct_established="$(count_event "direct_established")"
relay_committed="$(count_event "relay_committed")"
connect_failed="$(count_event "connect_failed")"
path_memory_hit="$(count_event "path_memory_hit")"
circuit_breaker_armed="$(count_event "circuit_breaker_armed")"

{
  extract_payload_lines "direct_established"
  extract_payload_lines "relay_committed"
} | jq -r '.elapsed_ms // empty' 2>/dev/null | awk 'NF > 0 {print int($1)}' >"$tmp_elapsed" || true

direct_success_rate="$(calc_rate "$direct_established" "$total_attempts")"
relay_commit_rate="$(calc_rate "$relay_committed" "$total_attempts")"
connect_fail_rate="$(calc_rate "$connect_failed" "$total_attempts")"
path_memory_hit_rate="$(calc_rate "$path_memory_hit" "$total_attempts")"
circuit_breaker_arm_rate="$(calc_rate "$circuit_breaker_armed" "$total_attempts")"
first_connect_p95_ms="$(calc_p95 "$tmp_elapsed")"

relay_reason_distribution="$(
  extract_payload_lines "relay_committed" \
    | jq -r '.reason // "unknown"' 2>/dev/null \
    | jq -R -s '
        split("\n")
        | map(select(length > 0))
        | group_by(.)
        | map({(.[0]): length})
        | add // {}
      '
)"

result_json="$(
  jq -n \
    --arg scenario "$scenario_id" \
    --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson total_attempts "$total_attempts" \
    --argjson direct_established "$direct_established" \
    --argjson relay_committed "$relay_committed" \
    --argjson connect_failed "$connect_failed" \
    --argjson path_memory_hit "$path_memory_hit" \
    --argjson circuit_breaker_armed "$circuit_breaker_armed" \
    --arg direct_success_rate "$direct_success_rate" \
    --arg relay_commit_rate "$relay_commit_rate" \
    --arg connect_fail_rate "$connect_fail_rate" \
    --arg path_memory_hit_rate "$path_memory_hit_rate" \
    --arg circuit_breaker_arm_rate "$circuit_breaker_arm_rate" \
    --argjson first_connect_p95_ms "$first_connect_p95_ms" \
    --argjson relay_reason_distribution "$relay_reason_distribution" \
    '{
      scenario: $scenario,
      generated_at: $generated_at,
      total_attempts: $total_attempts,
      direct_established: $direct_established,
      relay_committed: $relay_committed,
      connect_failed: $connect_failed,
      direct_success_rate: ($direct_success_rate | tonumber),
      relay_commit_rate: ($relay_commit_rate | tonumber),
      connect_fail_rate: ($connect_fail_rate | tonumber),
      first_connect_p95_ms: $first_connect_p95_ms,
      path_memory_hit: $path_memory_hit,
      path_memory_hit_rate: ($path_memory_hit_rate | tonumber),
      circuit_breaker_armed: $circuit_breaker_armed,
      circuit_breaker_arm_rate: ($circuit_breaker_arm_rate | tonumber),
      relay_reason_distribution: $relay_reason_distribution
    }'
)"

echo "$result_json"

if [[ -n "$output_jsonl" ]]; then
  mkdir -p "$(dirname "$output_jsonl")"
  echo "$result_json" >>"$output_jsonl"
fi
