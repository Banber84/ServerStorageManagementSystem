#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
用法：
  sudo scripts/delete_node_user.sh USERNAME [--keep-home]

在 NodeA/NodeB 上删除 Linux 登录用户。
默认同时删除该用户的本地 home 目录；使用 --keep-home 可保留本地 home。
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $EUID -ne 0 ]]; then
  echo "请使用 root 权限执行：sudo $0"
  exit 1
fi

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

USERNAME="$1"
shift
KEEP_HOME="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-home)
      KEEP_HOME="1"
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

if ! id "$USERNAME" >/dev/null 2>&1; then
  echo "节点用户不存在：$USERNAME"
  exit 0
fi

if pgrep -u "$USERNAME" >/dev/null 2>&1; then
  echo "用户仍有进程在运行，请先退出该用户会话：$USERNAME"
  exit 1
fi

if [[ "$KEEP_HOME" == "1" ]]; then
  userdel "$USERNAME"
  echo "已删除节点用户并保留 home：$USERNAME"
else
  userdel -r "$USERNAME"
  echo "已删除节点用户和 home：$USERNAME"
fi
