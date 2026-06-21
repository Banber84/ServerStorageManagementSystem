#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-/etc/ssms/sync.conf}"
if [[ ! -f "$CONFIG_FILE" ]]; then
  CONFIG_FILE="$PROJECT_ROOT/configs/sync.conf"
fi

usage() {
  cat <<'EOF'
用法：
  scripts/request_user_delete.sh USERNAME [--keep-data] [--keep-node-home] [--storage HOST] [--storage-user USER] [--storage-project DIR]

在 NodeA/NodeB 上发起用户删除同步请求。
脚本会通过 SSH 调用 Storage Server 上的 scripts/sync_delete_user.sh，再由 Storage Server 同步删除三方用户。

示例：
  scripts/request_user_delete.sh alice
  scripts/request_user_delete.sh alice --keep-data --keep-node-home
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "缺少同步配置文件：$CONFIG_FILE"
  exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

USERNAME="$1"
shift
STORAGE_HOST="${STORAGE_SYNC_HOST:-}"
STORAGE_USER="${STORAGE_SYNC_USER:-}"
STORAGE_PROJECT_DIR="${STORAGE_SYNC_PROJECT_DIR:-}"
KEEP_DATA="0"
KEEP_NODE_HOME="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-data)
      KEEP_DATA="1"
      shift
      ;;
    --keep-node-home)
      KEEP_NODE_HOME="1"
      shift
      ;;
    --storage)
      STORAGE_HOST="$2"
      shift 2
      ;;
    --storage-user)
      STORAGE_USER="$2"
      shift 2
      ;;
    --storage-project)
      STORAGE_PROJECT_DIR="$2"
      shift 2
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

if [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  echo "用户名非法：$USERNAME"
  exit 1
fi

if [[ -z "$STORAGE_HOST" || -z "$STORAGE_USER" || -z "$STORAGE_PROJECT_DIR" ]]; then
  echo "Storage Server 连接配置不完整，请检查 $CONFIG_FILE。"
  exit 1
fi

REMOTE_SCRIPT="$STORAGE_PROJECT_DIR/scripts/sync_delete_user.sh"
printf -v REMOTE_SCRIPT_Q '%q' "$REMOTE_SCRIPT"
printf -v USERNAME_Q '%q' "$USERNAME"
REMOTE_ARGS=()
if [[ "$KEEP_DATA" == "1" ]]; then
  REMOTE_ARGS+=("--keep-data")
fi
if [[ "$KEEP_NODE_HOME" == "1" ]]; then
  REMOTE_ARGS+=("--keep-node-home")
fi

echo "向 Storage Server 发起用户删除同步：$STORAGE_USER@$STORAGE_HOST"
ssh "$STORAGE_USER@$STORAGE_HOST" \
  "sudo $REMOTE_SCRIPT_Q $USERNAME_Q ${REMOTE_ARGS[*]}"

echo "节点发起的用户删除同步完成：$USERNAME"
