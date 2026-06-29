#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NODES_CONFIG_LIB="$SCRIPT_DIR/lib/nodes_config.sh"
CONFIG_FILE="${CONFIG_FILE:-/etc/ssms/system.conf}"
if [[ ! -f "$CONFIG_FILE" ]]; then
  CONFIG_FILE="$PROJECT_ROOT/configs/system.conf"
fi
if [[ ! -f "$NODES_CONFIG_LIB" ]]; then
  echo "缺少节点配置函数库：$NODES_CONFIG_LIB" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$NODES_CONFIG_LIB"

usage() {
  cat <<'EOF'
用法：
  sudo scripts/join_node.sh NODE_NAME NODE_HOST NODE_USER [选项]

在 Storage Server 上一键接入新的登录节点：
  1. 更新 configs/nodes.conf。
  2. 配置 configs/sync.conf。
  3. 配置 Storage Server <-> 新节点 双向 SSH key。
  4. 复制 configs、scripts、docs 到新节点。
  5. 写入新节点的 Storage Server 运行配置并安装客户端。
  6. 安装 SMB 入口网关和节点监控 Agent。
  7. 配置双方 sudoers 免密同步脚本。
  8. 验证创建/删除同步脚本可远程调用。

选项：
  --node-project DIR       新节点项目目录，默认 /home/NODE_USER/SSMS
  --storage-user USER      Storage Server SSH 用户，默认 sudo 发起用户
  --storage-host HOST      Storage Server 地址，默认读取 STORAGE_SERVER
  --storage-project DIR    Storage Server 项目目录，默认当前项目目录
  --management-url URL     管理后台地址，默认读取 backend.conf
  --agent-binary PATH      storage-agent 二进制路径
  --skip-copy              不复制项目文件到新节点
  --skip-install           不执行 install_node_client.sh
  --skip-smb-gateway       不安装或更新 SMB 入口网关
  --skip-agent             不安装或更新 storage-agent
  --skip-existing-users    不把 Storage Server 的现有用户补建到新节点

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
NODE_PROJECT_DIR="/home/$NODE_USER/SSMS"
MANAGEMENT_URL=""
AGENT_BINARY=""
SKIP_COPY="0"
SKIP_INSTALL="0"
SKIP_SMB_GATEWAY="0"
SKIP_AGENT="0"
SYNC_EXISTING_USERS="1"

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
    --management-url)
      MANAGEMENT_URL="$2"
      shift 2
      ;;
    --agent-binary)
      AGENT_BINARY="$2"
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
    --skip-smb-gateway)
      SKIP_SMB_GATEWAY="1"
      shift
      ;;
    --skip-agent)
      SKIP_AGENT="1"
      shift
      ;;
    --skip-existing-users)
      SYNC_EXISTING_USERS="0"
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

if [[ -z "$MANAGEMENT_URL" ]]; then
  BACKEND_CONFIG_FILE="/etc/ssms/backend.conf"
  if [[ ! -f "$BACKEND_CONFIG_FILE" ]]; then
    BACKEND_CONFIG_FILE="$PROJECT_ROOT/configs/backend.conf"
  fi
  if [[ -f "$BACKEND_CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$BACKEND_CONFIG_FILE"
    MANAGEMENT_URL="${BACKEND_API_BASE:-}"
  fi
fi
MANAGEMENT_URL="${MANAGEMENT_URL:-http://$STORAGE_HOST:8080}"
if [[ ! "$MANAGEMENT_URL" =~ ^https?://[^[:space:]]+$ ]]; then
  echo "管理后台地址非法：$MANAGEMENT_URL"
  exit 1
fi

SSH_OPTS=(-o StrictHostKeyChecking=accept-new)
NODE_TARGET="$NODE_USER@$NODE_HOST"
STORAGE_TARGET="$STORAGE_USER@$STORAGE_HOST"
SSH_CMD=(sudo -u "$STORAGE_USER" ssh)
SCP_CMD=(sudo -u "$STORAGE_USER" scp)

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
  local tmp source_file runtime_file
  runtime_file="/etc/ssms/nodes.conf"
  source_file="$PROJECT_ROOT/configs/nodes.conf"
  if [[ -f "$runtime_file" ]]; then
    source_file="$runtime_file"
  fi

  tmp="$(mktemp)"
  if [[ -f "$source_file" ]]; then
    awk -v name="$NODE_NAME" -v host="$NODE_HOST" '
      /^#/ || NF == 0 { print; next }
      $1 == name || $2 == host { next }
      { print }
    ' "$source_file" > "$tmp"
  fi
  printf '%s %s %s %s\n' "$NODE_NAME" "$NODE_HOST" "$NODE_USER" "$NODE_PROJECT_DIR" >> "$tmp"

  install -d -m 0755 /etc/ssms
  install -m 0644 "$tmp" "$PROJECT_ROOT/configs/nodes.conf"
  install -m 0644 "$tmp" "$runtime_file"
  rm -f "$tmp"
}

write_site_nodes() {
  local site_file="$PROJECT_ROOT/configs/site.env"
  ssms_sync_site_nodes "$site_file" "$PROJECT_ROOT/configs/nodes.conf"
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
  local content encoded
  content="$(cat <<EOF
$NODE_USER ALL=(ALL) NOPASSWD: $NODE_PROJECT_DIR/scripts/create_node_user.sh
$NODE_USER ALL=(ALL) NOPASSWD: $NODE_PROJECT_DIR/scripts/delete_node_user.sh
EOF
)"
  encoded="$(printf '%s\n' "$content" | base64 | tr -d '\n')"
  echo "配置 $NODE_NAME 的 sudoers；若出现 sudo 提示，请输入 $NODE_USER 的登录密码。"
  "${SSH_CMD[@]}" -tt "${SSH_OPTS[@]}" "$NODE_TARGET" \
    "printf '%s' '$encoded' | base64 -d | sudo tee /etc/sudoers.d/ssms-node-sync >/dev/null && sudo chmod 0440 /etc/sudoers.d/ssms-node-sync && sudo visudo -cf /etc/sudoers.d/ssms-node-sync"
}

copy_project_files() {
  "${SSH_CMD[@]}" "${SSH_OPTS[@]}" "$NODE_TARGET" "mkdir -p '$NODE_PROJECT_DIR'"
  "${SCP_CMD[@]}" -r "${SSH_OPTS[@]}" \
    "$PROJECT_ROOT/configs" "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/docs" \
    "$NODE_TARGET:$NODE_PROJECT_DIR/"
}

sync_node_runtime_configs() {
  local system_tmp backend_tmp status
  system_tmp="$(mktemp)"
  backend_tmp="$(mktemp)"
  awk -v storage_host="$STORAGE_HOST" '
    BEGIN { updated = 0 }
    /^STORAGE_SERVER=/ {
      printf "STORAGE_SERVER=\"%s\"\n", storage_host
      updated = 1
      next
    }
    { print }
    END {
      if (!updated) {
        printf "STORAGE_SERVER=\"%s\"\n", storage_host
      }
    }
  ' "$PROJECT_ROOT/configs/system.conf" > "$system_tmp"
  {
    echo "# Generated by scripts/join_node.sh"
    printf 'BACKEND_API_BASE=%q\n' "$MANAGEMENT_URL"
    printf 'BACKEND_SYNC_ENABLED=%q\n' "${BACKEND_SYNC_ENABLED:-1}"
    printf 'BACKEND_API_TIMEOUT=%q\n' "${BACKEND_API_TIMEOUT:-5}"
  } > "$backend_tmp"
  chmod 0644 "$system_tmp" "$backend_tmp"

  status=0
  "${SSH_CMD[@]}" "${SSH_OPTS[@]}" "$NODE_TARGET" \
    "mkdir -p '$NODE_PROJECT_DIR/configs'" || status=$?
  if [[ "$status" -eq 0 ]]; then
    "${SCP_CMD[@]}" "${SSH_OPTS[@]}" "$system_tmp" \
      "$NODE_TARGET:$NODE_PROJECT_DIR/configs/system.conf" || status=$?
  fi
  if [[ "$status" -eq 0 ]]; then
    "${SCP_CMD[@]}" "${SSH_OPTS[@]}" "$PROJECT_ROOT/configs/sync.conf" \
      "$NODE_TARGET:$NODE_PROJECT_DIR/configs/sync.conf" || status=$?
  fi
  if [[ "$status" -eq 0 ]]; then
    "${SCP_CMD[@]}" "${SSH_OPTS[@]}" "$backend_tmp" \
      "$NODE_TARGET:$NODE_PROJECT_DIR/configs/backend.conf" || status=$?
  fi
  rm -f "$system_tmp" "$backend_tmp"
  return "$status"
}

install_node_client() {
  echo "安装 $NODE_NAME 客户端；若出现 sudo 提示，请输入 $NODE_USER 的登录密码。"
  "${SSH_CMD[@]}" -tt "${SSH_OPTS[@]}" "$NODE_TARGET" \
    "cd '$NODE_PROJECT_DIR' && sudo scripts/install_node_client.sh"
}

node_smb_gateway_ready() {
  "${SSH_CMD[@]}" -n "${SSH_OPTS[@]}" "$NODE_TARGET" \
    "systemctl is-active --quiet ssms-smb-gateway.socket &&
     grep -qF -- '$STORAGE_HOST:445' /etc/systemd/system/ssms-smb-gateway.service &&
     ss -H -ltn 'sport = :445' | grep -q ."
}

sync_node_smb_gateway_files() {
  "${SSH_CMD[@]}" -n "${SSH_OPTS[@]}" "$NODE_TARGET" \
    "mkdir -p '$NODE_PROJECT_DIR/scripts' '$NODE_PROJECT_DIR/configs'"
  "${SCP_CMD[@]}" "${SSH_OPTS[@]}" \
    "$PROJECT_ROOT/scripts/install_smb_gateway.sh" \
    "$NODE_TARGET:$NODE_PROJECT_DIR/scripts/install_smb_gateway.sh"
  "${SCP_CMD[@]}" "${SSH_OPTS[@]}" \
    "$PROJECT_ROOT/configs/ssms-smb-gateway.socket" \
    "$NODE_TARGET:$NODE_PROJECT_DIR/configs/ssms-smb-gateway.socket"
  "${SSH_CMD[@]}" -n "${SSH_OPTS[@]}" "$NODE_TARGET" \
    "chmod +x '$NODE_PROJECT_DIR/scripts/install_smb_gateway.sh'"
}

install_node_smb_gateway() {
  echo "安装 $NODE_NAME SMB 入口网关；若出现 sudo 提示，请输入 $NODE_USER 的登录密码。"
  "${SSH_CMD[@]}" -tt "${SSH_OPTS[@]}" "$NODE_TARGET" \
    "cd '$NODE_PROJECT_DIR' &&
     sudo scripts/install_smb_gateway.sh --storage-server '$STORAGE_HOST'"
}

prepare_agent_binary() {
  if [[ -n "$AGENT_BINARY" ]]; then
    if [[ ! -x "$AGENT_BINARY" ]]; then
      echo "指定的 Agent 可执行文件不存在或不可执行：$AGENT_BINARY"
      return 1
    fi
    return
  fi

  if [[ -x "$PROJECT_ROOT/bin/storage-agent" ]]; then
    AGENT_BINARY="$PROJECT_ROOT/bin/storage-agent"
    return
  fi
  if [[ -x /usr/local/bin/storage-agent ]]; then
    AGENT_BINARY="/usr/local/bin/storage-agent"
    return
  fi
  if ! command -v go >/dev/null 2>&1; then
    echo "缺少 storage-agent 二进制且未安装 Go；可使用 --agent-binary 指定或 --skip-agent 跳过。"
    return 1
  fi

  echo "编译 storage-agent。"
  install -d -o "$STORAGE_USER" -g "$(id -gn "$STORAGE_USER")" -m 0755 "$PROJECT_ROOT/bin"
  (
    cd "$PROJECT_ROOT"
    sudo -u "$STORAGE_USER" go build -o "$PROJECT_ROOT/bin/storage-agent" ./agent
  )
  AGENT_BINARY="$PROJECT_ROOT/bin/storage-agent"
}

node_agent_ready() {
  "${SSH_CMD[@]}" -n "${SSH_OPTS[@]}" "$NODE_TARGET" \
    "systemctl is-active --quiet storage-agent &&
     grep -qxF 'SSMS_SERVER_URL=$MANAGEMENT_URL' /etc/ssms/storage-agent.env &&
     grep -qxF 'SSMS_AGENT_NAME=$NODE_NAME' /etc/ssms/storage-agent.env &&
     grep -qxF 'SSMS_AGENT_ADDRESS=$NODE_HOST' /etc/ssms/storage-agent.env"
}

install_node_agent() {
  local remote_binary="/tmp/ssms-storage-agent"

  prepare_agent_binary
  "${SCP_CMD[@]}" "${SSH_OPTS[@]}" "$AGENT_BINARY" "$NODE_TARGET:$remote_binary"
  echo "安装 $NODE_NAME 监控 Agent；若出现 sudo 提示，请输入 $NODE_USER 的登录密码。"
  "${SSH_CMD[@]}" -tt "${SSH_OPTS[@]}" "$NODE_TARGET" \
    "cd '$NODE_PROJECT_DIR' &&
     sudo scripts/install_node_agent.sh \
       --binary '$remote_binary' \
       --server-url '$MANAGEMENT_URL' \
       --name '$NODE_NAME' \
       --address '$NODE_HOST';
     status=\$?;
     rm -f '$remote_binary';
     exit \$status"
}

configure_ssh_keys() {
  local storage_pub node_pub
  storage_pub="$(ensure_local_ssh_key "$STORAGE_USER")"

  printf '%s\n' "$storage_pub" | "${SSH_CMD[@]}" "${SSH_OPTS[@]}" "$NODE_TARGET" '
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    touch ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    tmp="$(mktemp)"
    cat > "$tmp"
    grep -qxFf "$tmp" ~/.ssh/authorized_keys 2>/dev/null || cat "$tmp" >> ~/.ssh/authorized_keys
    rm -f "$tmp"
  '

  node_pub="$("${SSH_CMD[@]}" "${SSH_OPTS[@]}" "$NODE_TARGET" '
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    if [ ! -f ~/.ssh/id_ed25519.pub ]; then
      ssh-keygen -q -t ed25519 -N "" -f ~/.ssh/id_ed25519
    fi
    cat ~/.ssh/id_ed25519.pub
  ')"
  append_authorized_key "$STORAGE_USER" "$node_pub"
}

node_sudoers_ready() {
  "${SSH_CMD[@]}" -n "${SSH_OPTS[@]}" "$NODE_TARGET" \
    "sudo -n '$NODE_PROJECT_DIR/scripts/create_node_user.sh' --help >/dev/null && sudo -n '$NODE_PROJECT_DIR/scripts/delete_node_user.sh' --help >/dev/null"
}

verify_join() {
  node_sudoers_ready
  "${SSH_CMD[@]}" "${SSH_OPTS[@]}" "$NODE_TARGET" \
    "ssh ${SSH_OPTS[*]} '$STORAGE_TARGET' \"sudo -n '$STORAGE_PROJECT_DIR/scripts/sync_user.sh' --help >/dev/null && sudo -n '$STORAGE_PROJECT_DIR/scripts/sync_delete_user.sh' --help >/dev/null\""
}

sync_existing_users() {
  local user_dir username password_hash
  local synced_count=0
  local skipped_count=0

  if [[ ! -d "$STORAGE_ROOT" ]]; then
    echo "存储根目录不存在，无法同步现有用户：$STORAGE_ROOT"
    return 1
  fi

  echo "检查 Storage Server 现有用户并补建到 $NODE_NAME。"
  while IFS= read -r user_dir; do
    username="$(basename "$user_dir")"
    case "$username" in
      _deleted_*) continue ;;
    esac
    if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
      echo "跳过非法用户名目录：$user_dir"
      skipped_count=$((skipped_count + 1))
      continue
    fi

    password_hash="$(getent shadow "$username" | cut -d: -f2)"
    if [[ ! "$password_hash" =~ ^\$[^:]+$ ]]; then
      echo "跳过无法读取有效密码哈希的用户：$username"
      skipped_count=$((skipped_count + 1))
      continue
    fi

    printf '%s\n' "$password_hash" | "${SSH_CMD[@]}" "${SSH_OPTS[@]}" "$NODE_TARGET" \
      "sudo -n '$NODE_PROJECT_DIR/scripts/create_node_user.sh' '$username' --password-hash-stdin"
    unset password_hash
    synced_count=$((synced_count + 1))
  done < <(find "$STORAGE_ROOT" -mindepth 1 -maxdepth 1 -type d | sort)

  echo "现有用户同步完成：同步 $synced_count，跳过 $skipped_count"
}

echo "接入新节点：$NODE_NAME ($NODE_TARGET)"
write_nodes_conf
write_site_nodes
write_sync_conf
write_storage_sudoers
configure_ssh_keys

if [[ "$SKIP_COPY" == "0" ]]; then
  copy_project_files
fi

sync_node_runtime_configs

if [[ "$SKIP_INSTALL" == "0" ]]; then
  install_node_client
fi

if [[ "$SKIP_SMB_GATEWAY" == "0" ]]; then
  sync_node_smb_gateway_files
  if node_smb_gateway_ready; then
    echo "$NODE_NAME 的 SMB 入口网关已正确运行，跳过重复安装。"
  else
    install_node_smb_gateway
  fi
  if ! node_smb_gateway_ready; then
    echo "$NODE_NAME 的 SMB 入口网关安装后检查失败。" >&2
    exit 1
  fi
  echo "$NODE_NAME 的 SMB 入口网关可用：$NODE_HOST:445 -> $STORAGE_HOST:445"
fi

if [[ "$SKIP_AGENT" == "0" ]]; then
  if node_agent_ready; then
    echo "$NODE_NAME 的 storage-agent 已正确运行，跳过重复安装。"
  else
    install_node_agent
  fi
fi

if node_sudoers_ready; then
  echo "$NODE_NAME 的同步 sudoers 已配置，跳过重复写入。"
else
  write_node_sudoers
fi
verify_join
if [[ "$SYNC_EXISTING_USERS" == "1" ]]; then
  sync_existing_users
fi

echo "新节点接入完成：$NODE_NAME"
echo "节点清单：$PROJECT_ROOT/configs/nodes.conf"
echo "运行时节点清单：/etc/ssms/nodes.conf"
echo "节点可发起同步：$NODE_PROJECT_DIR/scripts/request_user_sync.sh USERNAME --quota-gb 1"
