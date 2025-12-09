#!/usr/bin/env bash
# Launch iperf3 servers on ports commonly used by WebRTC (TCP & UDP).
# Defaults cover typical TURN/STUN and media ports; override with PORTS and MEDIA_RANGE.

set -euo pipefail

PORTS_DEFAULT="80 443 3478 5349 19302"
#MEDIA_RANGE_DEFAULT="10000-10005" # small sample of common media UDP ports
MEDIA_RANGE_DEFAULT="30000-30005" # small sample of common media UDP ports
LOG_DIR="${LOG_DIR:-logs}"
PID_FILE="${PID_FILE:-scripts/iperf3_server.pids}"
STARTED_PORTS_FILE="${STARTED_PORTS_FILE:-scripts/iperf3_started_ports.txt}"

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
  raw_ports="$(normalize_ports "${PORTS:-$PORTS_DEFAULT}") $(normalize_ports "${MEDIA_RANGE:-$MEDIA_RANGE_DEFAULT}")"
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

can_bind_port() {
  local port="$1"
  # Ports below 1024 require root or the cap_net_bind_service capability.
  if (( port >= 1024 )); then
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

mkdir -p "$LOG_DIR"
: > "$PID_FILE"
: > "$STARTED_PORTS_FILE"

echo "Starting iperf3 servers on ports: ${PORT_LIST[*]}"

for port in "${PORT_LIST[@]}"; do
  if ! can_bind_port "$port"; then
    echo "Skipping port $port (needs root or cap_net_bind_service to bind <1024)" >&2
    continue
  fi

  # Warn if something already listens on the port.
  if lsof -iTCP:"$port" -sTCP:LISTEN -n -P >/dev/null 2>&1 || lsof -iUDP:"$port" -n -P >/dev/null 2>&1; then
    echo "Skipping port $port (already in use)" >&2
    continue
  fi

  log_file="$LOG_DIR/iperf3_${port}.log"
  nohup iperf3 -s -p "$port" > "$log_file" 2>&1 &
  pid=$!

  # Give the server a moment to fail fast (e.g., permission denied).
  sleep 0.1
  if kill -0 "$pid" >/dev/null 2>&1; then
    echo "$pid" >> "$PID_FILE"
    echo "$port" >> "$STARTED_PORTS_FILE"
  else
    err_line="$(tail -n1 "$log_file" 2>/dev/null || true)"
    echo "Failed to start iperf3 on port $port${err_line:+ ($err_line)}" >&2
    continue
  fi
done

echo "PID list saved to $PID_FILE"
echo "Started ports saved to $STARTED_PORTS_FILE"
echo "Logs under $LOG_DIR/iperf3_<port>.log"
