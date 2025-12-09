#!/usr/bin/env bash
# Run iperf3 tests against the WebRTC port set (TCP then UDP).

set -euo pipefail

SERVER_HOST="${SERVER_HOST:-127.0.0.1}"
DURATION="${DURATION:-5}"
UDP_BW="${UDP_BW:-10M}"
PORTS_DEFAULT="80 443 3478 5349 19302"
MEDIA_RANGE_DEFAULT="30000-30005"
STARTED_PORTS_FILE="${STARTED_PORTS_FILE:-scripts/iperf3_started_ports.txt}"
ALLOW_PRIV_PORTS="${ALLOW_PRIV_PORTS:-0}"
SLEEP_BETWEEN="${SLEEP_BETWEEN:-0}" # seconds to pause between ports
MAX_RETRIES="${MAX_RETRIES:-5}"

command -v iperf3 >/dev/null 2>&1 || { echo "iperf3 is required" >&2; exit 1; }

normalize_ports() {
  local raw="$1"
  raw="${raw//,/ }"
  echo "$raw"
}

expand_range() {
  local range="$1"
  if [[ "$range" =~ ^([0-9]+)-([0-9]+)$ ]]; then
    local start="${BASH_REMATCH[1]}"
    local end="${BASH_REMATCH[2]}"
    if (( start > end )); then
      echo "Invalid range: $range" >&2
      exit 1
    fi
    seq "$start" "$end"
  else
    echo "$range"
  fi
}

collect_ports() {
  local raw_ports
  if [[ -f "$STARTED_PORTS_FILE" && "$SERVER_HOST" =~ ^(127\.0\.0\.1|localhost|::1)$ ]]; then
    # Prefer the exact ports the local server actually started.
    raw_ports="$(cat "$STARTED_PORTS_FILE")"
  else
    raw_ports="$(normalize_ports "${PORTS:-$PORTS_DEFAULT}") $(normalize_ports "${MEDIA_RANGE:-$MEDIA_RANGE_DEFAULT}")"
  fi
  declare -A seen=()
  local p
  for token in $raw_ports; do
    for p in $(expand_range "$token"); do
      [[ -n "$p" ]] || continue
      if [[ -z "${seen[$p]:-}" ]]; then
        echo "$p"
        seen["$p"]=1
      fi
    done
  done
}

can_bind_port_locally() {
  local port="$1"
  if (( port >= 1024 )); then
    return 0
  fi
  if [[ "$ALLOW_PRIV_PORTS" == "1" ]]; then
    return 0
  fi
  if [[ $EUID -eq 0 ]]; then
    return 0
  fi
  if command -v getcap >/dev/null 2>&1; then
    local iperf_path
    iperf_path="$(command -v iperf3)"
    if getcap "$iperf_path" 2>/dev/null | grep -q 'cap_net_bind_service'; then
      return 0
    fi
  fi
  return 1
}

PORT_LIST=($(collect_ports))

echo "Testing against $SERVER_HOST for duration ${DURATION}s (UDP bw $UDP_BW) on ports: ${PORT_LIST[*]}"

run_tcp() {
  local port="$1"
  local attempt rc
  echo ""
  echo "TCP port $port"
  for attempt in $(seq 1 "$MAX_RETRIES"); do
    if iperf3 -c "$SERVER_HOST" -p "$port" -t "$DURATION"; then
      return 0
    fi
    rc=$?
    echo "TCP port $port attempt $attempt FAILED (exit $rc)" >&2
    if (( attempt < MAX_RETRIES )); then
      echo "Retrying TCP port $port..." >&2
    fi
  done
  echo "TCP port $port FAILED after $MAX_RETRIES attempts" >&2
}

run_udp() {
  local port="$1"
  local attempt rc
  echo ""
  echo "UDP port $port"
  for attempt in $(seq 1 "$MAX_RETRIES"); do
    if iperf3 -c "$SERVER_HOST" -p "$port" -u -b "$UDP_BW" -t "$DURATION"; then
      return 0
    fi
    rc=$?
    echo "UDP port $port attempt $attempt FAILED (exit $rc)" >&2
    if (( attempt < MAX_RETRIES )); then
      echo "Retrying UDP port $port..." >&2
    fi
  done
  echo "UDP port $port FAILED after $MAX_RETRIES attempts" >&2
}

for port in "${PORT_LIST[@]}"; do
  if [[ "$SERVER_HOST" =~ ^(127\.0\.0\.1|localhost|::1)$ ]] && (( port < 1024 )) && ! can_bind_port_locally "$port"; then
    echo ""
    echo "Skipping port $port (privileged port not available locally; set ALLOW_PRIV_PORTS=1 to force)"
    continue
  fi
  run_tcp "$port"
  run_udp "$port"
  if [[ "$SLEEP_BETWEEN" != "0" ]]; then
    sleep "$SLEEP_BETWEEN"
  fi
done
