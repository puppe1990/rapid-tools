#!/bin/sh

set -eu

HOST="${HOST:-127.0.0.1}"
START_PORT="${PORT:-4000}"
MAX_PORT_TRIES="${MAX_PORT_TRIES:-50}"
MIX_ENV="${MIX_ENV:-dev}"

port="$START_PORT"
attempt=0

port_in_use() {
  lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
}

while [ "$attempt" -lt "$MAX_PORT_TRIES" ]; do
  if ! port_in_use "$port"; then
    echo "Starting RapidTools on http://$HOST:$port"
    exec env PORT="$port" MIX_ENV="$MIX_ENV" mix phx.server
  fi

  next_port=$((port + 1))
  echo "Port $port is busy, trying $next_port..."
  port="$next_port"
  attempt=$((attempt + 1))
done

end_port=$((START_PORT + MAX_PORT_TRIES - 1))
echo "No free port found between $START_PORT and $end_port." >&2
exit 1
