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
  sudo scripts/deploy_smb_gateways.sh [--nodes-file PATH] [--node NODE_NAME]

在 nodes.conf 中的全部登录节点安装 SMB TCP 入口网关。
使用 --node 时只部署指定节点。
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
if [[ $EUID -ne 0 ]]; then
  echo "请在 Storage Server 上使用 root 权限执行：sudo $0" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

NODES_FILE="${NODES_FILE:-/etc/ssms/nodes.conf}"
TARGET_NODE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --nodes-file)
      NODES_FILE="${2:-}"
      shift 2
      ;;
    --node)
      TARGET_NODE="${2:-}"
      shift 2
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

if [[ ! -f "$NODES_FILE" ]]; then
  echo "节点清单不存在：$NODES_FILE" >&2
  exit 1
fi
if [[ ! "$STORAGE_SERVER" =~ ^[a-zA-Z0-9._:-]+$ ]]; then
  echo "Storage Server 地址非法：$STORAGE_SERVER" >&2
  exit 1
fi
if [[ -n "$TARGET_NODE" && ! "$TARGET_NODE" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "节点名非法：$TARGET_NODE" >&2
  exit 1
fi

STORAGE_USER="${SUDO_USER:-}"
if [[ -z "$STORAGE_USER" || "$STORAGE_USER" == "root" ]]; then
  STORAGE_USER="$(logname 2>/dev/null || true)"
fi
if [[ -z "$STORAGE_USER" ]]; then
  echo "无法确定 Storage Server 管理用户。" >&2
  exit 1
fi

SSH_OPTS=(-o StrictHostKeyChecking=accept-new)
SSH_CMD=(sudo -u "$STORAGE_USER" ssh)
SCP_CMD=(sudo -u "$STORAGE_USER" scp)
deployed_count=0

while read -r NODE_NAME NODE_HOST NODE_USER NODE_PROJECT_DIR EXTRA <&3; do
  if [[ -z "${NODE_NAME:-}" || "$NODE_NAME" == \#* ]]; then
    continue
  fi
  if [[ -n "$TARGET_NODE" && "$NODE_NAME" != "$TARGET_NODE" ]]; then
    continue
  fi
  if [[ -n "${EXTRA:-}" || -z "${NODE_HOST:-}" || -z "${NODE_USER:-}" || -z "${NODE_PROJECT_DIR:-}" ]]; then
    echo "节点清单格式错误：$NODE_NAME $NODE_HOST $NODE_USER ${NODE_PROJECT_DIR:-} ${EXTRA:-}" >&2
    exit 1
  fi

  NODE_TARGET="$NODE_USER@$NODE_HOST"
  echo "部署 SMB 网关：$NODE_NAME ($NODE_TARGET)"
  "${SSH_CMD[@]}" -n "${SSH_OPTS[@]}" "$NODE_TARGET" \
    "mkdir -p '$NODE_PROJECT_DIR/scripts' '$NODE_PROJECT_DIR/configs'"
  "${SCP_CMD[@]}" "${SSH_OPTS[@]}" \
    "$PROJECT_ROOT/scripts/install_smb_gateway.sh" \
    "$NODE_TARGET:$NODE_PROJECT_DIR/scripts/install_smb_gateway.sh"
  "${SCP_CMD[@]}" "${SSH_OPTS[@]}" \
    "$PROJECT_ROOT/configs/ssms-smb-gateway.socket" \
    "$NODE_TARGET:$NODE_PROJECT_DIR/configs/ssms-smb-gateway.socket"
  "${SSH_CMD[@]}" -tt "${SSH_OPTS[@]}" "$NODE_TARGET" \
    "chmod +x '$NODE_PROJECT_DIR/scripts/install_smb_gateway.sh' &&
     cd '$NODE_PROJECT_DIR' &&
     sudo scripts/install_smb_gateway.sh --storage-server '$STORAGE_SERVER'"
  deployed_count=$((deployed_count + 1))
done 3< "$NODES_FILE"

if [[ "$deployed_count" -eq 0 ]]; then
  echo "没有匹配的节点：${TARGET_NODE:-$NODES_FILE}" >&2
  exit 1
fi
echo "SMB 网关批量部署完成：$deployed_count 个节点"
