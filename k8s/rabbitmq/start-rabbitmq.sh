#!/bin/sh
set -eu
rm -f /tmp/trezzecloud-rabbitmq-ready
/usr/local/bin/docker-entrypoint.sh rabbitmq-server &
server_pid=$!
trap 'kill -TERM "$server_pid" 2>/dev/null || true; wait "$server_pid" || true' EXIT
trap 'exit 0' TERM INT
# Import after first-boot default user/vhost creation; native early import skips it.
until rabbitmq-diagnostics -q check_running >/dev/null 2>&1; do
    kill -0 "$server_pid" 2>/dev/null || exit 1
    sleep 2
done
rabbitmqctl import_definitions /etc/rabbitmq/definitions.json
touch /tmp/trezzecloud-rabbitmq-ready
wait "$server_pid"
