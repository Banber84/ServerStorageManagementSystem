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
  sudo scripts/quota_manager.sh enable
  sudo scripts/quota_manager.sh set USERNAME QUOTA_GB
  sudo scripts/quota_manager.sh report

STORAGE_ROOT 所在文件系统必须使用 usrquota,grpquota 挂载参数。
EOF
}

if [[ $EUID -ne 0 ]]; then
  echo "请使用 root 权限执行：sudo $0"
  exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

COMMAND="${1:-}"
MOUNT_POINT="$(findmnt -no TARGET --target "$STORAGE_ROOT")"

case "$COMMAND" in
  enable)
    if ! findmnt -no OPTIONS --target "$STORAGE_ROOT" | grep -Eq '(^|,)usrquota(,|$)'; then
      cat <<EOF
当前 $MOUNT_POINT 未启用 quota 挂载参数。
请在 /etc/fstab 中为 $STORAGE_ROOT 所在文件系统增加 usrquota,grpquota，然后重新挂载：
  sudo mount -o remount $MOUNT_POINT
EOF
      exit 1
    fi
    quotacheck -cum "$MOUNT_POINT"
    quotaon -uv "$MOUNT_POINT"
    repquota -a
    ;;
  set)
    USERNAME="${2:-}"
    QUOTA_GB="${3:-}"
    if [[ -z "$USERNAME" || -z "$QUOTA_GB" ]]; then
      usage
      exit 1
    fi
    if ! id "$USERNAME" >/dev/null 2>&1; then
      echo "用户不存在：$USERNAME"
      exit 1
    fi
    if ! [[ "$QUOTA_GB" =~ ^[0-9]+$ ]] || [[ "$QUOTA_GB" -le 0 ]]; then
      echo "配额必须是正整数，单位为 GB。"
      exit 1
    fi
    BLOCKS=$((QUOTA_GB * 1024 * 1024))
    SOFT=$((BLOCKS * 95 / 100))
    setquota -u "$USERNAME" "$SOFT" "$BLOCKS" 0 0 "$MOUNT_POINT"
    quota -u "$USERNAME" || true
    ;;
  report)
    repquota -a
    ;;
  -h|--help|"")
    usage
    ;;
  *)
    echo "未知命令：$COMMAND"
    usage
    exit 1
    ;;
esac
