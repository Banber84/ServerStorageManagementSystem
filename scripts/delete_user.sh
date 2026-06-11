#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-/etc/ssms/system.conf}"
if [[ ! -f "$CONFIG_FILE" ]]; then
  CONFIG_FILE="$SCRIPT_DIR/../configs/system.conf"
fi

usage() {
  cat <<'EOF'
用法：
  sudo scripts/delete_user.sh USERNAME [--keep-data]

禁用并删除 Samba 用户和 Linux 用户。默认会归档用户存储目录。
EOF
}

if [[ $EUID -ne 0 ]]; then
  echo "请使用 root 权限执行：sudo $0"
  exit 1
fi

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

USERNAME="$1"
shift
KEEP_DATA="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-data)
      KEEP_DATA="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数：$1"
      usage
      exit 1
      ;;
  esac
done

if pdbedit -L | cut -d: -f1 | grep -qx "$USERNAME"; then
  smbpasswd -x "$USERNAME"
fi

if id "$USERNAME" >/dev/null 2>&1; then
  setquota -u "$USERNAME" 0 0 0 0 "$(findmnt -no TARGET --target "$STORAGE_ROOT")" 2>/dev/null || true
  userdel "$USERNAME"
fi

USER_HOME="$STORAGE_ROOT/$USERNAME"
if [[ -d "$USER_HOME" && "$KEEP_DATA" == "0" ]]; then
  ARCHIVE_PATH="$STORAGE_ROOT/_deleted_${USERNAME}_$(date +%Y%m%d%H%M%S)"
  mv "$USER_HOME" "$ARCHIVE_PATH"
  chmod 0700 "$ARCHIVE_PATH"
  echo "用户数据已归档到：$ARCHIVE_PATH"
elif [[ -d "$USER_HOME" ]]; then
  echo "用户数据已保留在：$USER_HOME"
fi

echo "已删除存储用户：$USERNAME"
