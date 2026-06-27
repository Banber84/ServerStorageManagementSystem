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
  sudo scripts/quota_manager.sh set USERNAME QUOTA_GB [--no-backend]
  sudo scripts/quota_manager.sh report

STORAGE_ROOT 所在文件系统必须使用 usrquota,grpquota 挂载参数。
set 命令默认在修改 Linux 配额后同步 Go 管理后台。
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

run_quota_cmd() {
  "$@" 2> >(grep -v 'Cannot stat() mounted device tmpfs' >&2)
}

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
    run_quota_cmd quotacheck -cum "$MOUNT_POINT"
    run_quota_cmd quotaon -uv "$MOUNT_POINT"
    run_quota_cmd repquota "$MOUNT_POINT"
    ;;
  set)
    USERNAME="${2:-}"
    QUOTA_GB="${3:-}"
    SYNC_BACKEND="1"
    if [[ -z "$USERNAME" || -z "$QUOTA_GB" ]]; then
      usage
      exit 1
    fi
    if [[ "${4:-}" == "--no-backend" ]]; then
      SYNC_BACKEND="0"
    elif [[ -n "${4:-}" ]]; then
      echo "未知参数：$4"
      usage
      exit 1
    fi
    if [[ $# -gt 4 ]]; then
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
    run_quota_cmd setquota -u "$USERNAME" "$SOFT" "$BLOCKS" 0 0 "$MOUNT_POINT"
    run_quota_cmd quota -u "$USERNAME" || true
    if [[ "$SYNC_BACKEND" == "1" ]]; then
      if "$SCRIPT_DIR/backend_sync.sh" health >/dev/null 2>&1; then
        "$SCRIPT_DIR/backend_sync.sh" upsert-user "$USERNAME" "$QUOTA_GB"
        "$SCRIPT_DIR/backend_sync.sh" sync-usage --format-summary || true
      else
        echo "后台 API 不可用，Linux 配额已修改，已跳过后台同步。"
      fi
    fi
    ;;
  report)
    run_quota_cmd repquota "$MOUNT_POINT"
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
