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
  scripts/test_mount.sh USERNAME

请在登录节点上、用户完成登录后执行。
EOF
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

USERNAME="$1"
MOUNT_PATH="/home/$USERNAME/$MOUNT_POINT_NAME"

if mountpoint -q "$MOUNT_PATH"; then
  echo "已挂载：$MOUNT_PATH"
  df -h "$MOUNT_PATH"
  touch "$MOUNT_PATH/.ssms_mount_test"
  rm -f "$MOUNT_PATH/.ssms_mount_test"
  echo "读写测试通过。"
else
  echo "未挂载：$MOUNT_PATH"
  exit 1
fi
