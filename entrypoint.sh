#!/bin/sh
set -e

# 确保数据目录存在且可写
mkdir -p /app/data
chown -R appuser:appuser /app/data

# 确保 xray 目录可写
mkdir -p /usr/local/share/xray
chown -R appuser:appuser /usr/local/share/xray

# 降权运行
exec su-exec appuser "$@"
