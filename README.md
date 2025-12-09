# iperf3 WebRTC Port Tester

Scripts to spin up iperf3 servers/clients across ports WebRTC commonly touches (TURN/STUN and sample media UDP range). Defaults are intentionally small and overridable so you can align with your environment.

## Default Port Set
- 80, 443 – TURN over (H)TCP
- 3478, 5349 – STUN/TURN UDP & TLS
- 19302 – Google STUN
- 10000-10005 – sample media UDP range often used by SFUs

Override with env vars:
- `PORTS="80 443 3478 5349 19302"` (space or comma separated, supports single values and ranges)
- `MEDIA_RANGE="10000-10020"` (single range; included in the overall list)

## Server
```bash
./scripts/iperf3_webrtc_server.sh
# Ports used -> ${PORTS} + ${MEDIA_RANGE}
# Logs -> logs/iperf3_<port>.log
# PIDs -> scripts/iperf3_server.pids
```
Stop the servers:
```bash
./scripts/iperf3_stop.sh
```

## Client
```bash
SERVER_HOST=10.0.0.5 ./scripts/iperf3_webrtc_client.sh
# Optional: DURATION=10 UDP_BW=20M PORTS="80,443,3478" MEDIA_RANGE="10000-10010"
```
Each port is tested twice (TCP then UDP). Make sure the server script is running on the target host first.
