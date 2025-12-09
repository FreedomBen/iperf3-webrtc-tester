#!/usr/bin/env bash
# Stop iperf3 servers started by iperf3_webrtc_server.sh.

set -euo pipefail

PID_FILE="${PID_FILE:-scripts/iperf3_server.pids}"

if [[ ! -f "$PID_FILE" ]]; then
  echo "No pid file found at $PID_FILE"
  exit 0
fi

while read -r pid; do
  [[ -z "$pid" ]] && continue
  if kill -0 "$pid" >/dev/null 2>&1; then
    kill "$pid" || true
  fi
done < "$PID_FILE"

rm -f "$PID_FILE"
echo "Stopped iperf3 servers listed in $PID_FILE"
