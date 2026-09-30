#!/usr/bin/env bash
set -e

echo "======================================"
echo "        iVentoy Docker Server"
echo "======================================"
echo

cd /iventoy

echo "Network interfaces:"
ip -br addr || true

echo
echo "Starting iVentoy..."
/iventoy/iventoy.sh start

sleep 2

echo
/iventoy/iventoy.sh status || true

echo
echo "iVentoy startup completed."
echo "Web UI: http://192.168.0.50:26000"
echo

trap '/iventoy/iventoy.sh stop || true; exit 0' SIGTERM SIGINT SIGTERM

while true; do
    sleep 10
done
