#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/ssms}"
PURGE_DATA="0"
PURGE_CONFIG="0"

usage() {
  cat <<'EOF'
用法：
  sudo scripts/uninstall_management_server.sh [--purge-data] [--purge-config] [--purge-all]

说明：
  清理主节点 Web 管理后台，便于测试后重新部署。

默认会执行：
  1. 停止并禁用 storage-server.service
  2. 停止并禁用 storage-usage-sync.timer
  3. 删除对应 systemd 单元
  4. 删除 /usr/local/bin/storage-server
  5. 删除 /opt/ssms 发布目录

默认保留：
  - /var/lib/ssms 数据库
  - /var/log/ssms 日志
  - /etc/ssms/storage-server.env 配置

选项：
  --purge-data    同时删除 /var/lib/ssms 和 /var/log/ssms
  --purge-config  同时删除 /etc/ssms/storage-server.env
  --purge-all     等同于 --purge-data --purge-config
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge-data)
      PURGE_DATA="1"
      shift
      ;;
    --purge-config)
      PURGE_CONFIG="1"
      shift
      ;;
    --purge-all)
      PURGE_DATA="1"
      PURGE_CONFIG="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数：$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "请使用 root 权限执行：sudo $0" >&2
  exit 1
fi

guard_path() {
  local path="$1"
  case "$path" in
    ""|"/"|"/opt"|"/etc"|"/usr"|"/var"|"/home")
      echo "拒绝删除危险路径：$path" >&2
      exit 1
      ;;
  esac
}

remove_dir() {
  local path="$1"
  guard_path "$path"
  if [[ -e "$path" ]]; then
    rm -rf "$path"
    echo "已删除目录：$path"
  fi
}

systemctl disable --now storage-server >/dev/null 2>&1 || true
systemctl disable --now storage-usage-sync.timer >/dev/null 2>&1 || true

rm -f /etc/systemd/system/storage-server.service
rm -f /etc/systemd/system/storage-usage-sync.service
rm -f /etc/systemd/system/storage-usage-sync.timer
rm -f /usr/local/bin/storage-server
remove_dir "$APP_DIR"

if [[ "$PURGE_DATA" == "1" ]]; then
  remove_dir /var/lib/ssms
  remove_dir /var/log/ssms
fi

if [[ "$PURGE_CONFIG" == "1" ]]; then
  rm -f /etc/ssms/storage-server.env
  rmdir /etc/ssms >/dev/null 2>&1 || true
fi

systemctl daemon-reload
systemctl reset-failed storage-server >/dev/null 2>&1 || true
systemctl reset-failed storage-usage-sync.service >/dev/null 2>&1 || true

cat <<EOF
管理后台清理完成。

已清理：
  storage-server.service
  storage-usage-sync.service
  storage-usage-sync.timer
  /usr/local/bin/storage-server
  $APP_DIR

数据清理：$PURGE_DATA
配置清理：$PURGE_CONFIG
EOF
