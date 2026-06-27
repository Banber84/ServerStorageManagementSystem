#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-/etc/ssms/system.conf}"
if [[ ! -f "$CONFIG_FILE" ]]; then
  CONFIG_FILE="$PROJECT_ROOT/configs/system.conf"
fi

usage() {
  cat <<'EOF'
用法：
  sudo scripts/sync_delete_user.sh USERNAME [--nodes-file PATH] [--storage-only] [--nodes-only] [--keep-data] [--keep-node-home] [--no-backend]

在 Storage Server 上删除 Samba/Linux 存储用户，并同步删除 nodes.conf 中登录节点上的同名本地用户。
默认行为：
  1. Storage Server 上归档用户数据目录。
  2. NodeA/NodeB 上删除本地用户和本地 home 目录。

示例：
  sudo scripts/sync_delete_user.sh alice
  sudo scripts/sync_delete_user.sh alice --keep-data --keep-node-home
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $EUID -ne 0 ]]; then
  echo "请在 Storage Server 上使用 root 权限执行：sudo $0"
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
NODES_FILE="${NODES_FILE:-/etc/ssms/nodes.conf}"
if [[ ! -f "$NODES_FILE" ]]; then
  NODES_FILE="$PROJECT_ROOT/configs/nodes.conf"
fi
SYNC_STORAGE="1"
SYNC_NODES="1"
KEEP_DATA="0"
KEEP_NODE_HOME="0"
SYNC_BACKEND="1"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --nodes-file)
      NODES_FILE="$2"
      shift 2
      ;;
    --storage-only)
      SYNC_NODES="0"
      shift
      ;;
    --nodes-only)
      SYNC_STORAGE="0"
      shift
      ;;
    --keep-data)
      KEEP_DATA="1"
      shift
      ;;
    --keep-node-home)
      KEEP_NODE_HOME="1"
      shift
      ;;
    --no-backend)
      SYNC_BACKEND="0"
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

if [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  echo "用户名非法：$USERNAME"
  exit 1
fi

if [[ "$SYNC_NODES" == "1" && ! -f "$NODES_FILE" ]]; then
  echo "节点清单不存在：$NODES_FILE"
  exit 1
fi

if [[ "$SYNC_STORAGE" == "1" ]]; then
  STORAGE_ARGS=("$USERNAME")
  if [[ "$KEEP_DATA" == "1" ]]; then
    STORAGE_ARGS+=("--keep-data")
  fi
  "$SCRIPT_DIR/delete_user.sh" "${STORAGE_ARGS[@]}"
fi

if [[ "$SYNC_NODES" == "1" ]]; then
  SSH_CMD=(ssh)
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
    SSH_CMD=(sudo -u "$SUDO_USER" ssh)
  fi

  while read -r NODE_NAME NODE_HOST SSH_USER REMOTE_PROJECT_DIR EXTRA; do
    if [[ -z "${NODE_NAME:-}" || "$NODE_NAME" == \#* ]]; then
      continue
    fi
    if [[ -n "${EXTRA:-}" || -z "${NODE_HOST:-}" || -z "${SSH_USER:-}" || -z "${REMOTE_PROJECT_DIR:-}" ]]; then
      echo "节点清单格式错误：$NODE_NAME $NODE_HOST $SSH_USER ${REMOTE_PROJECT_DIR:-} ${EXTRA:-}"
      exit 1
    fi

    REMOTE_SCRIPT="$REMOTE_PROJECT_DIR/scripts/delete_node_user.sh"
    printf -v REMOTE_SCRIPT_Q '%q' "$REMOTE_SCRIPT"
    printf -v USERNAME_Q '%q' "$USERNAME"
    NODE_ARGS=()
    if [[ "$KEEP_NODE_HOME" == "1" ]]; then
      NODE_ARGS+=("--keep-home")
    fi

    echo "同步删除节点用户：$NODE_NAME ($SSH_USER@$NODE_HOST)"
    "${SSH_CMD[@]}" "$SSH_USER@$NODE_HOST" \
      "sudo $REMOTE_SCRIPT_Q $USERNAME_Q ${NODE_ARGS[*]}"
  done < "$NODES_FILE"
fi

if [[ "$SYNC_BACKEND" == "1" ]]; then
  if "$SCRIPT_DIR/backend_sync.sh" health >/dev/null 2>&1; then
    "$SCRIPT_DIR/backend_sync.sh" delete-user "$USERNAME"
  else
    echo "后台 API 不可用，已跳过后台同步。"
  fi
fi

echo "用户删除同步完成：$USERNAME"
