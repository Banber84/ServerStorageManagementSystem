#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SITE_CONFIG="${SITE_CONFIG:-$PROJECT_ROOT/configs/site.env}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/configs}"

usage() {
  cat <<'EOF'
用法：
  scripts/apply_site_config.sh [--config FILE] [--output-dir DIR]

说明：
  从统一部署模板 site.env 生成现有脚本和 systemd 使用的配置文件：
    system.conf
    sync.conf
    nodes.conf
    backend.conf
    storage-server.env
    storage-agent.env

示例：
  cp configs/site.env.example configs/site.env
  vim configs/site.env
  scripts/apply_site_config.sh --config configs/site.env --output-dir configs
  sudo scripts/apply_site_config.sh --config configs/site.env --output-dir /etc/ssms
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      SITE_CONFIG="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
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

if [[ -z "$SITE_CONFIG" || ! -f "$SITE_CONFIG" ]]; then
  echo "缺少统一部署配置：$SITE_CONFIG" >&2
  echo "请先执行：cp configs/site.env.example configs/site.env" >&2
  exit 1
fi

if [[ -z "$OUTPUT_DIR" ]]; then
  echo "缺少输出目录" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$SITE_CONFIG"

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

is_blank() {
  [[ -z "$(trim "${1:-}")" ]]
}

require_value() {
  local name="$1"
  local value="${2:-}"
  if is_blank "$value"; then
    echo "site.env 缺少必填项：$name" >&2
    return 1
  fi
}

SSMS_MANAGEMENT_PORT="${SSMS_MANAGEMENT_PORT:-8080}"
SSMS_MANAGEMENT_URL="${SSMS_MANAGEMENT_URL:-}"
SSMS_SERVER_ADDR="${SSMS_SERVER_ADDR:-0.0.0.0:${SSMS_MANAGEMENT_PORT}}"
SSMS_DB_PATH="${SSMS_DB_PATH:-/var/lib/ssms/server-storage.db}"
GIN_MODE="${GIN_MODE:-release}"
SSMS_AUTH_ENABLED="${SSMS_AUTH_ENABLED:-0}"
SSMS_ADMIN_USERNAME="${SSMS_ADMIN_USERNAME:-admin}"
SSMS_ADMIN_PASSWORD="${SSMS_ADMIN_PASSWORD:-}"
SSMS_ADMIN_PASSWORD_HASH="${SSMS_ADMIN_PASSWORD_HASH:-}"
SSMS_SESSION_SECRET="${SSMS_SESSION_SECRET:-}"

STORAGE_SERVER="${STORAGE_SERVER:-}"
STORAGE_ROOT="${STORAGE_ROOT:-/srv/samba/users}"
STORAGE_GROUP="${STORAGE_GROUP:-storageusers}"
DEFAULT_QUOTA_GB="${DEFAULT_QUOTA_GB:-10}"
MOUNT_POINT_NAME="${MOUNT_POINT_NAME:-storage}"
SMB_WORKGROUP="${SMB_WORKGROUP:-WORKGROUP}"
SMB_NETBIOS_NAME="${SMB_NETBIOS_NAME:-SSMS-STORAGE}"

STORAGE_SYNC_HOST="${STORAGE_SYNC_HOST:-}"
STORAGE_SYNC_USER="${STORAGE_SYNC_USER:-}"
STORAGE_SYNC_PROJECT_DIR="${STORAGE_SYNC_PROJECT_DIR:-}"
DEFAULT_SYNC_QUOTA_GB="${DEFAULT_SYNC_QUOTA_GB:-1}"

SSMS_AGENT_NAME="${SSMS_AGENT_NAME:-}"
SSMS_AGENT_ADDRESS="${SSMS_AGENT_ADDRESS:-}"
SSMS_AGENT_DISK="${SSMS_AGENT_DISK:-/}"
SSMS_AGENT_INTERVAL="${SSMS_AGENT_INTERVAL:-30s}"
SSMS_SERVER_URL="${SSMS_SERVER_URL:-}"
BACKEND_SYNC_ENABLED="${BACKEND_SYNC_ENABLED:-1}"
BACKEND_API_TIMEOUT="${BACKEND_API_TIMEOUT:-5}"

auth_enabled_lc="$(printf '%s' "$SSMS_AUTH_ENABLED" | tr '[:upper:]' '[:lower:]')"
validation_failed=0
require_value SSMS_MANAGEMENT_HOST "${SSMS_MANAGEMENT_HOST:-}" || validation_failed=1
require_value STORAGE_SERVER "$STORAGE_SERVER" || validation_failed=1
require_value STORAGE_SYNC_HOST "$STORAGE_SYNC_HOST" || validation_failed=1
require_value STORAGE_SYNC_USER "$STORAGE_SYNC_USER" || validation_failed=1
require_value STORAGE_SYNC_PROJECT_DIR "$STORAGE_SYNC_PROJECT_DIR" || validation_failed=1
require_value SSMS_AGENT_NAME "$SSMS_AGENT_NAME" || validation_failed=1
require_value SSMS_AGENT_ADDRESS "$SSMS_AGENT_ADDRESS" || validation_failed=1
case "$auth_enabled_lc" in
  1|true|yes|on)
    SSMS_AUTH_ENABLED="1"
    require_value SSMS_ADMIN_USERNAME "$SSMS_ADMIN_USERNAME" || validation_failed=1
    if is_blank "$SSMS_ADMIN_PASSWORD" && is_blank "$SSMS_ADMIN_PASSWORD_HASH"; then
      echo "site.env 启用了 SSMS_AUTH_ENABLED，但缺少 SSMS_ADMIN_PASSWORD 或 SSMS_ADMIN_PASSWORD_HASH" >&2
      validation_failed=1
    fi
    require_value SSMS_SESSION_SECRET "$SSMS_SESSION_SECRET" || validation_failed=1
    ;;
  0|false|no|off)
    SSMS_AUTH_ENABLED="0"
    ;;
  *)
    echo "site.env 中 SSMS_AUTH_ENABLED 只能为 1/0、true/false、yes/no 或 on/off" >&2
    validation_failed=1
    ;;
esac

if is_blank "$SSMS_MANAGEMENT_URL"; then
  SSMS_MANAGEMENT_URL="http://${SSMS_MANAGEMENT_HOST}:${SSMS_MANAGEMENT_PORT}"
fi
if is_blank "$SSMS_SERVER_URL"; then
  SSMS_SERVER_URL="$SSMS_MANAGEMENT_URL"
fi

if ! is_blank "${SSMS_NODES:-}"; then
  while IFS= read -r line; do
    line="$(trim "$line")"
    [[ -z "$line" ]] && continue
    read -r node_name node_host node_user node_project extra <<< "$line"
    if [[ -z "${node_name:-}" || -z "${node_host:-}" || -z "${node_user:-}" || -z "${node_project:-}" || -n "${extra:-}" ]]; then
      echo "site.env 中 SSMS_NODES 格式错误：$line" >&2
      echo "正确格式：节点名 主机地址 SSH用户 项目目录" >&2
      validation_failed=1
    fi
  done <<< "$SSMS_NODES"
fi

if [[ "$validation_failed" -ne 0 ]]; then
  echo "请先复制 configs/site.env.example 为 configs/site.env，并填写真实部署信息后再生成配置。" >&2
  exit 1
fi

write_kv() {
  printf '%s=%q\n' "$1" "$2"
}

write_header() {
  local target="$1"
  {
    echo "# Generated from $SITE_CONFIG by scripts/apply_site_config.sh"
    echo "# Do not edit this file directly when using the unified deployment template."
    echo "# Edit site.env, then rerun apply_site_config.sh."
    echo
  } > "$target"
}

install -d -m 0755 "$OUTPUT_DIR"

SYSTEM_CONF="$OUTPUT_DIR/system.conf"
write_header "$SYSTEM_CONF"
{
  write_kv STORAGE_ROOT "$STORAGE_ROOT"
  write_kv STORAGE_GROUP "$STORAGE_GROUP"
  write_kv DEFAULT_QUOTA_GB "$DEFAULT_QUOTA_GB"
  echo
  write_kv STORAGE_SERVER "$STORAGE_SERVER"
  write_kv MOUNT_POINT_NAME "$MOUNT_POINT_NAME"
  echo
  write_kv SMB_WORKGROUP "$SMB_WORKGROUP"
  write_kv SMB_NETBIOS_NAME "$SMB_NETBIOS_NAME"
} >> "$SYSTEM_CONF"

SYNC_CONF="$OUTPUT_DIR/sync.conf"
write_header "$SYNC_CONF"
{
  write_kv STORAGE_SYNC_HOST "$STORAGE_SYNC_HOST"
  write_kv STORAGE_SYNC_USER "$STORAGE_SYNC_USER"
  write_kv STORAGE_SYNC_PROJECT_DIR "$STORAGE_SYNC_PROJECT_DIR"
  write_kv DEFAULT_SYNC_QUOTA_GB "$DEFAULT_SYNC_QUOTA_GB"
} >> "$SYNC_CONF"

BACKEND_CONF="$OUTPUT_DIR/backend.conf"
write_header "$BACKEND_CONF"
{
  write_kv BACKEND_API_BASE "$SSMS_MANAGEMENT_URL"
  write_kv BACKEND_SYNC_ENABLED "$BACKEND_SYNC_ENABLED"
  write_kv BACKEND_API_TIMEOUT "$BACKEND_API_TIMEOUT"
} >> "$BACKEND_CONF"

SERVER_ENV="$OUTPUT_DIR/storage-server.env"
write_header "$SERVER_ENV"
{
  write_kv SSMS_SERVER_ADDR "$SSMS_SERVER_ADDR"
  write_kv SSMS_DB_PATH "$SSMS_DB_PATH"
  write_kv GIN_MODE "$GIN_MODE"
  echo
  write_kv SSMS_AUTH_ENABLED "$SSMS_AUTH_ENABLED"
  write_kv SSMS_ADMIN_USERNAME "$SSMS_ADMIN_USERNAME"
  write_kv SSMS_ADMIN_PASSWORD "$SSMS_ADMIN_PASSWORD"
  write_kv SSMS_ADMIN_PASSWORD_HASH "$SSMS_ADMIN_PASSWORD_HASH"
  write_kv SSMS_SESSION_SECRET "$SSMS_SESSION_SECRET"
} >> "$SERVER_ENV"

AGENT_ENV="$OUTPUT_DIR/storage-agent.env"
write_header "$AGENT_ENV"
{
  write_kv SSMS_SERVER_URL "$SSMS_SERVER_URL"
  write_kv SSMS_AGENT_NAME "$SSMS_AGENT_NAME"
  write_kv SSMS_AGENT_ADDRESS "$SSMS_AGENT_ADDRESS"
  write_kv SSMS_AGENT_DISK "$SSMS_AGENT_DISK"
  write_kv SSMS_AGENT_INTERVAL "$SSMS_AGENT_INTERVAL"
} >> "$AGENT_ENV"

NODES_CONF="$OUTPUT_DIR/nodes.conf"
write_header "$NODES_CONF"
{
  echo "# 格式：节点名 主机地址 SSH用户 项目目录"
  echo
  if ! is_blank "${SSMS_NODES:-}"; then
    while IFS= read -r line; do
      [[ -z "${line//[[:space:]]/}" ]] && continue
      printf '%s\n' "$line"
    done <<< "$SSMS_NODES"
  else
    echo "# 未配置 SSMS_NODES。需要批量同步登录节点时，请在 site.env 中填写。"
  fi
} >> "$NODES_CONF"

cat <<EOF
已生成统一部署配置：
  $SYSTEM_CONF
  $SYNC_CONF
  $NODES_CONF
  $BACKEND_CONF
  $SERVER_ENV
  $AGENT_ENV
EOF
