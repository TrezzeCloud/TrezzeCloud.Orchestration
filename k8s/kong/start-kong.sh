#!/bin/sh
set -eu
# Restrict values to a YAML-safe alphabet; never interpolate arbitrary YAML.
: "${JWT_SECRET_KEY:?JWT_SECRET_KEY is required}"
: "${JWT_ISSUER:?JWT_ISSUER is required}"
case "$JWT_SECRET_KEY" in *[!A-Za-z0-9_+=./-]*) echo 'Invalid JWT secret alphabet' >&2; exit 1;; esac
case "$JWT_ISSUER" in ''|*[!A-Za-z0-9_.-]*) echo 'Invalid JWT issuer' >&2; exit 1;; esac
[ "${#JWT_SECRET_KEY}" -ge 32 ] || { echo 'JWT secret must have at least 32 characters' >&2; exit 1; }
umask 077
cat /kong/template/routes.yaml > /kong/runtime/kong.yml
printf '\nconsumers:\n  - username: trezzecloud-app\n    jwt_secrets:\n      - key: "%s"\n        algorithm: HS256\n        secret: "%s"\n' "$JWT_ISSUER" "$JWT_SECRET_KEY" >> /kong/runtime/kong.yml
exec /docker-entrypoint.sh kong docker-start
