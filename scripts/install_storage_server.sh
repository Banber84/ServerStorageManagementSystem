#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$PROJECT_ROOT/configs/system.conf}"

if [[ $EUID -ne 0 ]]; then
  echo "请使用 root 权限执行：sudo $0"
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "缺少配置文件：$CONFIG_FILE"
  exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y samba quota acl

install -d -m 0755 /etc/ssms
install -m 0644 "$CONFIG_FILE" /etc/ssms/system.conf

if ! getent group "$STORAGE_GROUP" >/dev/null; then
  groupadd --system "$STORAGE_GROUP"
fi

install -d -o root -g "$STORAGE_GROUP" -m 0711 "$STORAGE_ROOT"

if [[ -f /etc/samba/smb.conf ]]; then
  cp /etc/samba/smb.conf "/etc/samba/smb.conf.bak.$(date +%Y%m%d%H%M%S)"
fi

install -m 0644 "$PROJECT_ROOT/configs/smb.conf" /etc/samba/smb.conf
sed -i \
  -e "s/^\\s*workgroup = .*/   workgroup = $SMB_WORKGROUP/" \
  -e "s/^\\s*netbios name = .*/   netbios name = $SMB_NETBIOS_NAME/" \
  /etc/samba/smb.conf

testparm -s
systemctl enable --now smbd nmbd
systemctl restart smbd nmbd

cat <<EOF
Storage Server 基础安装完成。

下一步：
1. 为 $STORAGE_ROOT 所在文件系统启用 quota 挂载参数。
2. 执行：sudo $SCRIPT_DIR/quota_manager.sh enable
3. 创建用户：sudo $SCRIPT_DIR/create_user.sh USERNAME --quota-gb $DEFAULT_QUOTA_GB
EOF
