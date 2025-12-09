#!/usr/bin/env bash
# Launch iperf3 servers on ports commonly used by WebRTC (TCP & UDP).
# Defaults cover typical TURN/STUN and media ports; override with PORTS and MEDIA_RANGE.

set -euo pipefail

PORTS_DEFAULT="80 443 3478 5349 19302"
#MEDIA_RANGE_DEFAULT="10000-10005" # small sample of common media UDP ports
MEDIA_RANGE_DEFAULT="30000-30005" # small sample of common media UDP ports
LOG_DIR="${LOG_DIR:-logs}"
PID_FILE="${PID_FILE:-scripts/iperf3_server.pids}"

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

PORT_LIST=($(collect_ports))

mkdir -p "$LOG_DIR"
: > "$PID_FILE"

echo "Starting iperf3 servers on ports: ${PORT_LIST[*]}"

for port in "${PORT_LIST[@]}"; do
  # Warn if something already listens on the port.
  if lsof -iTCP:"$port" -sTCP:LISTEN -n -P >/dev/null 2>&1 || lsof -iUDP:"$port" -n -P >/dev/null 2>&1; then
    echo "Skipping port $port (already in use)" >&2
    continue
  fi

  nohup iperf3 -s -p "$port" > "$LOG_DIR/iperf3_${port}.log" 2>&1 &
  echo $! >> "$PID_FILE"
done

echo "PID list saved to $PID_FILE"
echo "Logs under $LOG_DIR/iperf3_<port>.log"
