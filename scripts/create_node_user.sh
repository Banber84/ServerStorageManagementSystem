#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
用法：
  sudo scripts/create_node_user.sh USERNAME

在 Node01/Node02 上创建 Linux 登录用户。
请使用与 Storage Server 上 Samba 用户一致的密码。
EOF
}

if [[ $EUID -ne 0 ]]; then
  echo "请使用 root 权限执行：sudo $0"
  exit 1
fi

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

USERNAME="$1"
if [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  echo "用户名非法：$USERNAME"
  exit 1
fi

if id "$USERNAME" >/dev/null 2>&1; then
  echo "用户已存在：$USERNAME"
  exit 0
fi

adduser "$USERNAME"
echo "已创建节点登录用户：$USERNAME"
