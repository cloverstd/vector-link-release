#!/bin/sh
set -e

# Only ownership setup uses root. Do not follow links in an existing data
# volume, and never execute code from that writable volume as root.
if [ "$(id -u)" = 0 ]; then
    mkdir -p /app/data /usr/local/share/xray
    chown -h -R appuser:appuser /app/data
    chown -h appuser:appuser /usr/local/share/xray
    exec su-exec appuser /app/entrypoint.sh "$@"
fi

# /app and the image executable are root-owned. Keep the mutable executable
# in the data volume so self-updates need no write access to the bootstrap.
case "${1:-}" in
    ./vector-link|/app/vector-link|vector-link)
        mkdir -p /app/data/bin
        image_hash=$(sha256sum /app/vector-link | cut -d ' ' -f 1)
        old_hash=$(cat /app/data/bin/image.sha256 2>/dev/null || true)
        if [ "$image_hash" != "$old_hash" ] || [ ! -x /app/data/bin/vector-link ]; then
            cp /app/vector-link /app/data/bin/vector-link.image
            chmod 0755 /app/data/bin/vector-link.image
            mv -f /app/data/bin/vector-link.image /app/data/bin/vector-link
            printf '%s\n' "$image_hash" > /app/data/bin/image.sha256
        fi
        shift
        exec /app/data/bin/vector-link "$@"
        ;;
esac
exec "$@"
