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
  sudo scripts/sync_user.sh USERNAME [--quota-gb GB] [--nodes-file PATH] [--storage-only] [--nodes-only] [--password-stdin] [--no-backend]

在 Storage Server 上创建/更新 Samba 存储用户，并同步到 nodes.conf 中的登录节点。
同步到节点后，用户下次登录节点时由 pam_mount 自动挂载个人目录。

nodes.conf 格式：
  节点名 主机地址 SSH用户 项目目录

示例：
  sudo scripts/sync_user.sh alice --quota-gb 1
  printf 'password\n' | sudo scripts/sync_user.sh alice --quota-gb 1 --password-stdin
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
QUOTA_GB="${DEFAULT_QUOTA_GB:-10}"
NODES_FILE="${NODES_FILE:-/etc/ssms/nodes.conf}"
if [[ ! -f "$NODES_FILE" ]]; then
  NODES_FILE="$PROJECT_ROOT/configs/nodes.conf"
fi
SYNC_STORAGE="1"
SYNC_NODES="1"
PASSWORD_STDIN="0"
SYNC_BACKEND="1"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quota-gb)
      QUOTA_GB="$2"
      shift 2
      ;;
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
    --password-stdin)
      PASSWORD_STDIN="1"
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

if ! [[ "$QUOTA_GB" =~ ^[0-9]+$ ]] || [[ "$QUOTA_GB" -le 0 ]]; then
  echo "配额必须是正整数，单位为 GB。"
  exit 1
fi

if [[ "$SYNC_NODES" == "1" && ! -f "$NODES_FILE" ]]; then
  echo "节点清单不存在：$NODES_FILE"
  exit 1
fi

if [[ "$PASSWORD_STDIN" == "1" ]]; then
  IFS= read -r PASSWORD
else
  read -r -s -p "请输入 $USERNAME 的统一密码：" PASSWORD
  echo
  read -r -s -p "请再次输入密码：" PASSWORD_CONFIRM
  echo

  if [[ "$PASSWORD" != "$PASSWORD_CONFIRM" ]]; then
    echo "两次输入的密码不一致。"
    exit 1
  fi
fi

if [[ -z "$PASSWORD" ]]; then
  echo "密码不能为空。"
  exit 1
fi

if [[ "$SYNC_STORAGE" == "1" ]]; then
  printf '%s\n' "$PASSWORD" | "$SCRIPT_DIR/create_user.sh" "$USERNAME" --quota-gb "$QUOTA_GB" --password-stdin
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

    REMOTE_SCRIPT="$REMOTE_PROJECT_DIR/scripts/create_node_user.sh"
    printf -v REMOTE_SCRIPT_Q '%q' "$REMOTE_SCRIPT"
    printf -v USERNAME_Q '%q' "$USERNAME"

    echo "同步节点用户：$NODE_NAME ($SSH_USER@$NODE_HOST)"
    printf '%s\n' "$PASSWORD" | "${SSH_CMD[@]}" "$SSH_USER@$NODE_HOST" \
      "sudo $REMOTE_SCRIPT_Q $USERNAME_Q --password-stdin"
  done < "$NODES_FILE"
fi

if [[ "$SYNC_BACKEND" == "1" ]]; then
  if "$SCRIPT_DIR/backend_sync.sh" health >/dev/null 2>&1; then
    "$SCRIPT_DIR/backend_sync.sh" upsert-user "$USERNAME" "$QUOTA_GB"
    if [[ "$SYNC_STORAGE" == "1" ]]; then
      "$SCRIPT_DIR/backend_sync.sh" sync-usage --format-summary || true
    fi
  else
    echo "后台 API 不可用，已跳过后台同步。"
  fi
fi

echo "用户同步完成：$USERNAME"
echo "Storage Server 共享：//$STORAGE_SERVER/$USERNAME"
echo "节点登录后挂载点：/home/$USERNAME/$MOUNT_POINT_NAME"
