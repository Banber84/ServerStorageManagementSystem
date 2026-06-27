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
  sudo scripts/join_node.sh NODE_NAME NODE_HOST NODE_USER [选项]

在 Storage Server 上一键接入新的登录节点：
  1. 更新 configs/nodes.conf。
  2. 配置 configs/sync.conf。
  3. 复制 configs、scripts、docs/deployment 到新节点。
  4. 在新节点执行 install_node_client.sh。
  5. 配置 Storage Server <-> 新节点 双向 SSH key。
  6. 配置双方 sudoers 免密同步脚本。
  7. 验证创建/删除同步脚本可远程调用。

选项：
  --node-project DIR       新节点项目目录，默认 /home/NODE_USER/ServerStorageManagementSystem
  --storage-user USER      Storage Server SSH 用户，默认 sudo 发起用户
  --storage-host HOST      Storage Server 地址，默认读取 STORAGE_SERVER
  --storage-project DIR    Storage Server 项目目录，默认当前项目目录
  --skip-copy              不复制项目文件到新节点
  --skip-install           不执行 install_node_client.sh

示例：
  sudo scripts/join_node.sh nodeC 192.168.1.130 nodec1
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

if [[ $# -lt 3 ]]; then
  usage
  exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

NODE_NAME="$1"
NODE_HOST="$2"
NODE_USER="$3"
shift 3

STORAGE_USER="${SUDO_USER:-}"
if [[ -z "$STORAGE_USER" || "$STORAGE_USER" == "root" ]]; then
  STORAGE_USER="$(logname 2>/dev/null || true)"
fi
STORAGE_HOST="${STORAGE_SERVER:-}"
STORAGE_PROJECT_DIR="$PROJECT_ROOT"
NODE_PROJECT_DIR="/home/$NODE_USER/ServerStorageManagementSystem"
SKIP_COPY="0"
SKIP_INSTALL="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --node-project)
      NODE_PROJECT_DIR="$2"
      shift 2
      ;;
    --storage-user)
      STORAGE_USER="$2"
      shift 2
      ;;
    --storage-host)
      STORAGE_HOST="$2"
      shift 2
      ;;
    --storage-project)
      STORAGE_PROJECT_DIR="$2"
      shift 2
      ;;
    --skip-copy)
      SKIP_COPY="1"
      shift
      ;;
    --skip-install)
      SKIP_INSTALL="1"
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

if [[ ! "$NODE_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "节点名非法：$NODE_NAME"
  exit 1
fi

if [[ ! "$NODE_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  echo "节点 SSH 用户非法：$NODE_USER"
  exit 1
fi

if [[ -z "$STORAGE_USER" || -z "$STORAGE_HOST" || -z "$STORAGE_PROJECT_DIR" ]]; then
  echo "Storage Server 连接信息不完整，请使用 --storage-user、--storage-host、--storage-project 指定。"
  exit 1
fi

SSH_OPTS=(-o StrictHostKeyChecking=accept-new)
NODE_TARGET="$NODE_USER@$NODE_HOST"
STORAGE_TARGET="$STORAGE_USER@$STORAGE_HOST"

user_home() {
  local user="$1"
  getent passwd "$user" | cut -d: -f6
}

append_authorized_key() {
  local user="$1"
  local key="$2"
  local home
  home="$(user_home "$user")"
  if [[ -z "$home" ]]; then
    echo "用户不存在，无法写入 authorized_keys：$user"
    exit 1
  fi

  install -d -m 0700 "$home/.ssh"
  chown "$user:" "$home/.ssh"
  touch "$home/.ssh/authorized_keys"
  chown "$user:" "$home/.ssh/authorized_keys"
  chmod 0600 "$home/.ssh/authorized_keys"
  if ! grep -qxF "$key" "$home/.ssh/authorized_keys"; then
    printf '%s\n' "$key" >> "$home/.ssh/authorized_keys"
  fi
}

ensure_local_ssh_key() {
  local user="$1"
  local home
  home="$(user_home "$user")"
  if [[ -z "$home" ]]; then
    echo "用户不存在，无法生成 SSH key：$user"
    exit 1
  fi
  sudo -u "$user" mkdir -p "$home/.ssh"
  sudo -u "$user" chmod 700 "$home/.ssh"
  if [[ ! -f "$home/.ssh/id_ed25519.pub" ]]; then
    sudo -u "$user" ssh-keygen -q -t ed25519 -N "" -f "$home/.ssh/id_ed25519"
  fi
  cat "$home/.ssh/id_ed25519.pub"
}

write_nodes_conf() {
  local tmp
  tmp="$(mktemp)"
  if [[ -f "$PROJECT_ROOT/configs/nodes.conf" ]]; then
    awk -v name="$NODE_NAME" -v host="$NODE_HOST" '
      /^#/ || NF == 0 { print; next }
      $1 == name || $2 == host { next }
      { print }
    ' "$PROJECT_ROOT/configs/nodes.conf" > "$tmp"
  fi
  printf '%s %s %s %s\n' "$NODE_NAME" "$NODE_HOST" "$NODE_USER" "$NODE_PROJECT_DIR" >> "$tmp"
  install -m 0644 "$tmp" "$PROJECT_ROOT/configs/nodes.conf"
  rm -f "$tmp"
}

write_sync_conf() {
  cat > "$PROJECT_ROOT/configs/sync.conf" <<EOF
# 节点作为同步发起端时使用的 Storage Server 连接配置

STORAGE_SYNC_HOST="$STORAGE_HOST"
STORAGE_SYNC_USER="$STORAGE_USER"
STORAGE_SYNC_PROJECT_DIR="$STORAGE_PROJECT_DIR"
DEFAULT_SYNC_QUOTA_GB="${DEFAULT_QUOTA_GB:-1}"
EOF
}

write_storage_sudoers() {
  local sudoers_file="/etc/sudoers.d/ssms-storage-sync"
  cat > "$sudoers_file" <<EOF
$STORAGE_USER ALL=(ALL) NOPASSWD: $STORAGE_PROJECT_DIR/scripts/sync_user.sh
$STORAGE_USER ALL=(ALL) NOPASSWD: $STORAGE_PROJECT_DIR/scripts/sync_delete_user.sh
EOF
  chmod 0440 "$sudoers_file"
  visudo -cf "$sudoers_file"
}

write_node_sudoers() {
  local content
  content="$(cat <<EOF
$NODE_USER ALL=(ALL) NOPASSWD: $NODE_PROJECT_DIR/scripts/create_node_user.sh
$NODE_USER ALL=(ALL) NOPASSWD: $NODE_PROJECT_DIR/scripts/delete_node_user.sh
EOF
)"
  printf '%s\n' "$content" | ssh -tt "${SSH_OPTS[@]}" "$NODE_TARGET" \
    "sudo tee /etc/sudoers.d/ssms-node-sync >/dev/null && sudo chmod 0440 /etc/sudoers.d/ssms-node-sync && sudo visudo -cf /etc/sudoers.d/ssms-node-sync"
}

copy_project_files() {
  ssh "${SSH_OPTS[@]}" "$NODE_TARGET" "mkdir -p '$NODE_PROJECT_DIR'"
  scp -r "${SSH_OPTS[@]}" "$PROJECT_ROOT/configs" "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/docs/deployment" "$NODE_TARGET:$NODE_PROJECT_DIR/"
}

install_node_client() {
  ssh -tt "${SSH_OPTS[@]}" "$NODE_TARGET" "cd '$NODE_PROJECT_DIR' && sudo scripts/install_node_client.sh"
}

configure_ssh_keys() {
  local storage_pub node_pub
  storage_pub="$(ensure_local_ssh_key "$STORAGE_USER")"

  printf '%s\n' "$storage_pub" | ssh "${SSH_OPTS[@]}" "$NODE_TARGET" '
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    touch ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    tmp="$(mktemp)"
    cat > "$tmp"
    grep -qxFf "$tmp" ~/.ssh/authorized_keys 2>/dev/null || cat "$tmp" >> ~/.ssh/authorized_keys
    rm -f "$tmp"
  '

  node_pub="$(ssh "${SSH_OPTS[@]}" "$NODE_TARGET" '
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    if [ ! -f ~/.ssh/id_ed25519.pub ]; then
      ssh-keygen -q -t ed25519 -N "" -f ~/.ssh/id_ed25519
    fi
    cat ~/.ssh/id_ed25519.pub
  ')"
  append_authorized_key "$STORAGE_USER" "$node_pub"
}

verify_join() {
  sudo -u "$STORAGE_USER" ssh "${SSH_OPTS[@]}" "$NODE_TARGET" \
    "sudo -n '$NODE_PROJECT_DIR/scripts/create_node_user.sh' --help >/dev/null && sudo -n '$NODE_PROJECT_DIR/scripts/delete_node_user.sh' --help >/dev/null"

  ssh "${SSH_OPTS[@]}" "$NODE_TARGET" \
    "ssh ${SSH_OPTS[*]} '$STORAGE_TARGET' \"sudo -n '$STORAGE_PROJECT_DIR/scripts/sync_user.sh' --help >/dev/null && sudo -n '$STORAGE_PROJECT_DIR/scripts/sync_delete_user.sh' --help >/dev/null\""
}

echo "接入新节点：$NODE_NAME ($NODE_TARGET)"
write_nodes_conf
write_sync_conf
write_storage_sudoers

if [[ "$SKIP_COPY" == "0" ]]; then
  copy_project_files
fi

if [[ "$SKIP_INSTALL" == "0" ]]; then
  install_node_client
fi

configure_ssh_keys
write_node_sudoers
verify_join

echo "新节点接入完成：$NODE_NAME"
echo "节点清单：$PROJECT_ROOT/configs/nodes.conf"
echo "节点可发起同步：$NODE_PROJECT_DIR/scripts/request_user_sync.sh USERNAME --quota-gb 1"
