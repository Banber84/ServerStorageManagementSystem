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
  sudo scripts/storage_usage_report.sh [--format csv|json]

从 STORAGE_ROOT 统计每个用户的存储使用量。
可供运维查看，也可供 Go 管理后台按需导入。
EOF
}

if [[ $EUID -ne 0 ]]; then
  echo "请使用 root 权限执行：sudo $0"
  exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

FORMAT="csv"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --format)
      FORMAT="$2"
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

if [[ "$FORMAT" != "csv" && "$FORMAT" != "json" ]]; then
  echo "格式必须是 csv 或 json。"
  exit 1
fi

if [[ ! -d "$STORAGE_ROOT" ]]; then
  echo "存储根目录不存在：$STORAGE_ROOT"
  exit 1
fi

if [[ "$FORMAT" == "csv" ]]; then
  echo "username,path,used_kb"
else
  echo "["
fi

FIRST="1"
while IFS= read -r USER_DIR; do
  USERNAME="$(basename "$USER_DIR")"
  case "$USERNAME" in
    _deleted_*) continue ;;
  esac
  USED_KB="$(du -sk "$USER_DIR" | awk '{print $1}')"

  if [[ "$FORMAT" == "csv" ]]; then
    printf '%s,%s,%s\n' "$USERNAME" "$USER_DIR" "$USED_KB"
  else
    if [[ "$FIRST" == "0" ]]; then
      echo ","
    fi
    FIRST="0"
    printf '  {"username":"%s","path":"%s","used_kb":%s}' "$USERNAME" "$USER_DIR" "$USED_KB"
  fi
done < <(find "$STORAGE_ROOT" -mindepth 1 -maxdepth 1 -type d | sort)

if [[ "$FORMAT" == "json" ]]; then
  echo
  echo "]"
fi
