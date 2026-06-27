#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NODES_CONFIG_LIB="$SCRIPT_DIR/lib/nodes_config.sh"
if [[ ! -f "$NODES_CONFIG_LIB" ]]; then
  echo "缺少节点配置函数库：$NODES_CONFIG_LIB" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$NODES_CONFIG_LIB"

usage() {
  cat <<'EOF'
用法：
  sudo scripts/leave_node.sh NODE_NAME [选项]

从 SSMS 安全移除登录节点：
  1. 停止并卸载节点 SMB 网关和 storage-agent。
  2. 删除节点同步 sudoers。
  3. 撤销 Storage Server 与节点的双向 SSH 公钥。
  4. 从项目和 /etc/ssms/nodes.conf 删除节点。
  5. 删除管理后台节点状态记录。

不会删除节点本地用户、用户 home 或 Storage Server 上的共享数据。

选项：
  --storage-user USER      Storage Server SSH 用户，默认 sudo 发起用户
  --config-only            仅清理节点清单和后台记录，不连接远端节点
  --keep-backend-record    保留管理后台节点状态记录
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
if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

NODE_NAME="$1"
shift
STORAGE_USER="${SUDO_USER:-}"
CONFIG_ONLY="0"
KEEP_BACKEND_RECORD="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --storage-user)
      STORAGE_USER="${2:-}"
      shift 2
      ;;
    --config-only)
      CONFIG_ONLY="1"
      shift
      ;;
    --keep-backend-record)
      KEEP_BACKEND_RECORD="1"
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

if [[ ! "$NODE_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "节点名非法：$NODE_NAME" >&2
  exit 1
fi
if [[ -z "$STORAGE_USER" || "$STORAGE_USER" == "root" ]]; then
  echo "无法确定 Storage Server SSH 用户，请使用 --storage-user 指定。" >&2
  exit 1
fi

RUNTIME_NODES="/etc/ssms/nodes.conf"
PROJECT_NODES="$PROJECT_ROOT/configs/nodes.conf"
NODE_LINE=""
for source_file in "$RUNTIME_NODES" "$PROJECT_NODES"; do
  if [[ -f "$source_file" ]]; then
    NODE_LINE="$(awk -v name="$NODE_NAME" '$1 == name { print; exit }' "$source_file")"
    if [[ -n "$NODE_LINE" ]]; then
      break
    fi
  fi
done
if [[ -z "$NODE_LINE" ]]; then
  echo "运行时和项目节点清单中均不存在：$NODE_NAME" >&2
  exit 1
fi
read -r _ NODE_HOST NODE_USER NODE_PROJECT_DIR EXTRA <<< "$NODE_LINE"
if [[ -n "${EXTRA:-}" || -z "$NODE_HOST" || -z "$NODE_USER" || -z "$NODE_PROJECT_DIR" ]]; then
  echo "节点清单格式错误：$NODE_LINE" >&2
  exit 1
fi

SSH_OPTS=(-o StrictHostKeyChecking=accept-new)
SSH_CMD=(sudo -u "$STORAGE_USER" ssh)
NODE_TARGET="$NODE_USER@$NODE_HOST"

remove_key_line() {
  local file="$1"
  local key="$2"
  local tmp
  [[ -f "$file" ]] || return 0
  tmp="$(mktemp)"
  grep -vxF "$key" "$file" > "$tmp" || true
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

remove_node_from_file() {
  local file="$1"
  local tmp
  [[ -f "$file" ]] || return 0
  tmp="$(mktemp)"
  awk -v name="$NODE_NAME" '$1 != name { print }' "$file" > "$tmp"
  install -m 0644 "$tmp" "$file"
  rm -f "$tmp"
}

write_site_nodes() {
  local site_file="$PROJECT_ROOT/configs/site.env"
  ssms_sync_site_nodes "$site_file" "$PROJECT_NODES"
}

uninstall_node_gateway_and_agent() {
  echo "卸载 $NODE_NAME 的 SMB 网关、Agent 和同步 sudoers；若出现 sudo 提示，请输入 $NODE_USER 的登录密码。"
  "${SSH_CMD[@]}" -tt "${SSH_OPTS[@]}" "$NODE_TARGET" \
    "if [ -x '$NODE_PROJECT_DIR/scripts/install_smb_gateway.sh' ]; then
       sudo '$NODE_PROJECT_DIR/scripts/install_smb_gateway.sh' --uninstall;
     else
       sudo systemctl disable --now ssms-smb-gateway.socket >/dev/null 2>&1 || true;
       sudo systemctl stop ssms-smb-gateway.service >/dev/null 2>&1 || true;
       sudo rm -f /etc/systemd/system/ssms-smb-gateway.socket /etc/systemd/system/ssms-smb-gateway.service;
       sudo systemctl daemon-reload;
     fi;
     if systemctl is-active --quiet ssms-smb-gateway.socket ||
        systemctl is-active --quiet ssms-smb-gateway.service ||
        sudo test -e /etc/systemd/system/ssms-smb-gateway.socket ||
        sudo test -e /etc/systemd/system/ssms-smb-gateway.service; then
       echo 'SMB 网关卸载检查失败。' >&2;
       exit 1;
     fi;
     sudo systemctl disable --now storage-agent >/dev/null 2>&1 || true;
     sudo rm -f /etc/systemd/system/storage-agent.service /etc/ssms/storage-agent.env /usr/local/bin/storage-agent /etc/sudoers.d/ssms-node-sync;
     sudo systemctl daemon-reload;
     sudo systemctl reset-failed storage-agent >/dev/null 2>&1 || true"
  echo "$NODE_NAME 的 SMB 网关已停止并卸载。"
}

if [[ "$CONFIG_ONLY" == "0" ]]; then
  STORAGE_HOME="$(getent passwd "$STORAGE_USER" | cut -d: -f6)"
  if [[ -z "$STORAGE_HOME" || ! -f "$STORAGE_HOME/.ssh/id_ed25519.pub" ]]; then
    echo "Storage Server SSH 公钥不存在，无法完整撤销节点：$STORAGE_USER" >&2
    exit 1
  fi
  STORAGE_PUB="$(cat "$STORAGE_HOME/.ssh/id_ed25519.pub")"
  NODE_PUB="$("${SSH_CMD[@]}" "${SSH_OPTS[@]}" "$NODE_TARGET" \
    "cat ~/.ssh/id_ed25519.pub")"

  uninstall_node_gateway_and_agent

  printf '%s\n' "$STORAGE_PUB" | "${SSH_CMD[@]}" "${SSH_OPTS[@]}" "$NODE_TARGET" '
    tmp="$(mktemp)"
    grep -vxFf /dev/stdin ~/.ssh/authorized_keys > "$tmp" || true
    cat "$tmp" > ~/.ssh/authorized_keys
    rm -f "$tmp"
  '
  remove_key_line "$STORAGE_HOME/.ssh/authorized_keys" "$NODE_PUB"
fi

remove_node_from_file "$PROJECT_NODES"
remove_node_from_file "$RUNTIME_NODES"
write_site_nodes

if [[ "$KEEP_BACKEND_RECORD" == "0" ]]; then
  if "$SCRIPT_DIR/backend_sync.sh" health >/dev/null 2>&1; then
    "$SCRIPT_DIR/backend_sync.sh" delete-server "$NODE_NAME"
  else
    echo "后台 API 不可用，已跳过后台节点记录删除。"
  fi
fi

echo "节点已移除：$NODE_NAME ($NODE_HOST)"
echo "节点本地用户和 Storage Server 共享数据均未删除。"
