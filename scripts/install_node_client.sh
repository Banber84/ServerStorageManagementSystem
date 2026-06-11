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
DEBIAN_FRONTEND=noninteractive apt-get install -y cifs-utils libpam-mount

install -d -m 0755 /etc/ssms
install -m 0644 "$CONFIG_FILE" /etc/ssms/system.conf

if [[ -f /etc/security/pam_mount.conf.xml ]]; then
  cp /etc/security/pam_mount.conf.xml "/etc/security/pam_mount.conf.xml.bak.$(date +%Y%m%d%H%M%S)"
fi

install -m 0644 "$PROJECT_ROOT/configs/pam_mount.conf.xml" /etc/security/pam_mount.conf.xml
sed -i \
  -e "s/server=\"[^\"]*\"/server=\"$STORAGE_SERVER\"/" \
  -e "s#mountpoint=\"/home/%(USER)/[^\"]*\"#mountpoint=\"/home/%(USER)/$MOUNT_POINT_NAME\"#" \
  /etc/security/pam_mount.conf.xml

pam-auth-update --enable mount

cat <<EOF
登录节点安装完成。

请在该节点创建对应的 Linux 登录用户：
  sudo adduser USERNAME

用户登录密码必须与 Storage Server 上创建的 Samba 密码一致。
登录后，//$STORAGE_SERVER/USERNAME 会自动挂载到 /home/USERNAME/$MOUNT_POINT_NAME。
EOF
