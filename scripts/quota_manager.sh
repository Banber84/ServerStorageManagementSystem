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
  sudo scripts/quota_manager.sh ensure
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
if [[ "${STORAGE_ROOT:-}" != /* ]]; then
  echo "STORAGE_ROOT 必须是绝对路径：${STORAGE_ROOT:-<empty>}" >&2
  exit 1
fi
MOUNT_POINT="$(findmnt -no TARGET --target "$STORAGE_ROOT" 2>/dev/null || true)"
if [[ -z "$MOUNT_POINT" ]]; then
  echo "无法识别 STORAGE_ROOT 所在挂载点：$STORAGE_ROOT" >&2
  exit 1
fi

run_quota_cmd() {
  "$@" 2> >(grep -v 'Cannot stat() mounted device tmpfs' >&2)
}

quota_mount_options_ready() {
  local options
  options="$(findmnt -no OPTIONS --target "$STORAGE_ROOT" 2>/dev/null || true)"
  [[ ",$options," == *,usrquota,* && ",$options," == *,grpquota,* ]]
}

quota_is_active() {
  local state
  state="$(quotaon -p "$MOUNT_POINT" 2>/dev/null || true)"
  grep -Eqi 'user quota.*(is on|enabled)' <<< "$state" && return 0
  run_quota_cmd repquota "$MOUNT_POINT" >/dev/null 2>&1
}

quota_setup_hint() {
  local filesystem_type mount_options source
  source="$(findmnt -no SOURCE --target "$STORAGE_ROOT" 2>/dev/null || true)"
  filesystem_type="$(findmnt -no FSTYPE --target "$STORAGE_ROOT" 2>/dev/null || true)"
  mount_options="$(findmnt -no OPTIONS --target "$STORAGE_ROOT" 2>/dev/null || true)"
  cat <<EOF
当前 quota 未就绪：
  STORAGE_ROOT: $STORAGE_ROOT
  挂载源: ${source:-unknown}
  挂载点: $MOUNT_POINT
  文件系统: ${filesystem_type:-unknown}
  挂载参数: ${mount_options:-unknown}

请先让 $MOUNT_POINT 启用 usrquota,grpquota 后重试：
  1. 编辑 /etc/fstab 中挂载点为 $MOUNT_POINT 的条目，给第四列追加 usrquota,grpquota。
  2. 执行：sudo mount -o remount $MOUNT_POINT
  3. 执行：sudo ssmsctl quota enable

如果该文件系统不是 ext4，请使用适合该文件系统的 quota 配置方式，或重新部署时使用 --skip-quota。
EOF
}

enable_quota() {
  if ! quota_mount_options_ready; then
    quota_setup_hint >&2
    exit 1
  fi
  if quota_is_active; then
    echo "$MOUNT_POINT 的用户 quota 已启用，跳过重复 quotacheck。"
    run_quota_cmd repquota "$MOUNT_POINT"
    return
  fi
  run_quota_cmd quotacheck -cum "$MOUNT_POINT"
  run_quota_cmd quotaon -uv "$MOUNT_POINT"
  if ! quota_is_active; then
    echo "$MOUNT_POINT 的用户 quota 初始化后仍不可用。" >&2
    quota_setup_hint >&2
    exit 1
  fi
  run_quota_cmd repquota "$MOUNT_POINT"
}

ensure_quota_ready() {
  if quota_is_active; then
    return
  fi
  if quota_mount_options_ready; then
    echo "$MOUNT_POINT 已有 quota 挂载参数，正在初始化 quota 文件。"
    enable_quota
    return
  fi
  quota_setup_hint >&2
  exit 1
}

case "$COMMAND" in
  enable)
    enable_quota
    ;;
  ensure)
    ensure_quota_ready
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
    ensure_quota_ready
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
    ensure_quota_ready
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
