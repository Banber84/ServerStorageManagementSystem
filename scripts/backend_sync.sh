#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${BACKEND_CONFIG_FILE:-/etc/ssms/backend.conf}"
if [[ ! -f "$CONFIG_FILE" ]]; then
  CONFIG_FILE="$PROJECT_ROOT/configs/backend.conf"
fi

usage() {
  cat <<'EOF'
用法：
  scripts/backend_sync.sh health
  scripts/backend_sync.sh upsert-user USERNAME QUOTA_GB
  scripts/backend_sync.sh update-quota USERNAME QUOTA_GB
  scripts/backend_sync.sh sync-usage [--format-summary]
  scripts/backend_sync.sh delete-user USERNAME

说明：
  该脚本只同步 Go 管理后台数据库，不创建或删除 Linux/Samba 系统用户。
  系统用户仍由 create_user.sh、sync_user.sh、sync_delete_user.sh 等脚本负责。
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
  echo "缺少后台配置文件：$CONFIG_FILE"
  exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

API_BASE="${BACKEND_API_BASE%/}"
API_TIMEOUT="${BACKEND_API_TIMEOUT:-5}"
SYNC_ENABLED="${BACKEND_SYNC_ENABLED:-1}"
COMMAND="$1"
shift

if [[ "$SYNC_ENABLED" != "1" ]]; then
  echo "后台同步已关闭：BACKEND_SYNC_ENABLED=$SYNC_ENABLED"
  exit 0
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "缺少命令：$1"
    exit 1
  fi
}

curl_api() {
  curl -sS --fail --max-time "$API_TIMEOUT" "$@"
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

quota_gb_to_bytes() {
  local quota_gb="$1"
  if ! [[ "$quota_gb" =~ ^[0-9]+$ ]] || [[ "$quota_gb" -le 0 ]]; then
    echo "配额必须是正整数，单位为 GB。"
    exit 1
  fi
  printf '%s\n' $((quota_gb * 1024 * 1024 * 1024))
}

username_valid() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

user_id_by_username() {
  local username="$1"
  curl_api "$API_BASE/api/users" | awk -v username="$username" '
    BEGIN {
      pattern = "\"username\":\"" username "\""
    }
    {
      text = $0
      while (match(text, /\{[^{}]*\}/)) {
        obj = substr(text, RSTART, RLENGTH)
        if (index(obj, pattern) > 0 && match(obj, /"id":[0-9]+/)) {
          print substr(obj, RSTART + 5, RLENGTH - 5)
          exit
        }
        text = substr(text, RSTART + RLENGTH)
      }
    }
  '
}

upsert_user() {
  local username="$1"
  local quota_gb="$2"
  local quota_bytes user_id safe_username

  if ! username_valid "$username"; then
    echo "用户名非法：$username"
    exit 1
  fi

  quota_bytes="$(quota_gb_to_bytes "$quota_gb")"
  user_id="$(user_id_by_username "$username")"
  safe_username="$(json_escape "$username")"

  if [[ -n "$user_id" ]]; then
    curl_api -X PUT "$API_BASE/api/users/$username/quota" \
      -H 'Content-Type: application/json' \
      -d "{\"quota_bytes\":$quota_bytes}" >/dev/null
    echo "后台用户已存在，已同步配额：$username"
  else
    curl_api -X POST "$API_BASE/api/users" \
      -H 'Content-Type: application/json' \
      -d "{\"username\":\"$safe_username\",\"full_name\":\"$safe_username\",\"email\":\"$safe_username@example.local\",\"quota_bytes\":$quota_bytes}" >/dev/null
    echo "后台用户已创建：$username"
  fi
}

update_quota() {
  local username="$1"
  local quota_gb="$2"
  local quota_bytes

  if ! username_valid "$username"; then
    echo "用户名非法：$username"
    exit 1
  fi

  quota_bytes="$(quota_gb_to_bytes "$quota_gb")"
  curl_api -X PUT "$API_BASE/api/users/$username/quota" \
    -H 'Content-Type: application/json' \
    -d "{\"quota_bytes\":$quota_bytes}" >/dev/null
  echo "后台配额已同步：$username"
}

sync_usage() {
  local summary="${1:-}"
  require_cmd awk

  if [[ $EUID -ne 0 ]]; then
    echo "同步存储用量需要读取用户目录，请使用 root 权限执行。"
    exit 1
  fi

  "$SCRIPT_DIR/storage_usage_report.sh" --format csv | tail -n +2 | while IFS=, read -r username path used_kb; do
    if [[ -z "$username" || -z "$path" || -z "$used_kb" ]]; then
      continue
    fi
    used_bytes=$((used_kb * 1024))
    safe_username="$(json_escape "$username")"
    safe_path="$(json_escape "$path")"
    curl_api -X POST "$API_BASE/api/storage/by-username" \
      -H 'Content-Type: application/json' \
      -d "{\"username\":\"$safe_username\",\"used_bytes\":$used_bytes,\"path\":\"$safe_path\"}" >/dev/null
    if [[ "$summary" == "--format-summary" ]]; then
      echo "已同步用量：$username $used_bytes bytes"
    fi
  done
}

delete_user_backend() {
  local username="$1"
  local user_id

  if ! username_valid "$username"; then
    echo "用户名非法：$username"
    exit 1
  fi

  user_id="$(user_id_by_username "$username")"
  if [[ -z "$user_id" ]]; then
    echo "后台用户不存在：$username"
    exit 0
  fi

  curl_api -X DELETE "$API_BASE/api/users/$user_id" >/dev/null
  echo "后台用户已删除：$username"
}

case "$COMMAND" in
  health)
    curl_api "$API_BASE/api/health"
    echo
    ;;
  upsert-user)
    if [[ $# -ne 2 ]]; then
      usage
      exit 1
    fi
    upsert_user "$1" "$2"
    ;;
  update-quota)
    if [[ $# -ne 2 ]]; then
      usage
      exit 1
    fi
    update_quota "$1" "$2"
    ;;
  sync-usage)
    sync_usage "${1:-}"
    ;;
  delete-user)
    if [[ $# -ne 1 ]]; then
      usage
      exit 1
    fi
    delete_user_backend "$1"
    ;;
  *)
    echo "未知命令：$COMMAND"
    usage
    exit 1
    ;;
esac
