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
  sudo scripts/create_user.sh USERNAME [--quota-gb GB] [--password-stdin]

创建 Linux 用户、Samba 账号、个人存储目录和用户配额。
脚本会要求输入一次密码，并同时用于 Linux 账号和 Samba 账号。
使用 --password-stdin 时，从标准输入读取一行密码，适合同步脚本调用。
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

# shellcheck source=/dev/null
source "$CONFIG_FILE"

USERNAME="$1"
shift
QUOTA_GB="${DEFAULT_QUOTA_GB:-10}"
PASSWORD_STDIN="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quota-gb)
      QUOTA_GB="$2"
      shift 2
      ;;
    --password-stdin)
      PASSWORD_STDIN="1"
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

if ! [[ "$QUOTA_GB" =~ ^[0-9]+$ ]] || [[ "$QUOTA_GB" -le 0 ]]; then
  echo "配额必须是正整数，单位为 GB。"
  exit 1
fi

if ! getent group "$STORAGE_GROUP" >/dev/null; then
  groupadd --system "$STORAGE_GROUP"
fi

install -d -o root -g "$STORAGE_GROUP" -m 0711 "$STORAGE_ROOT"

"$SCRIPT_DIR/quota_manager.sh" ensure

USER_HOME="$STORAGE_ROOT/$USERNAME"

if ! id "$USERNAME" >/dev/null 2>&1; then
  useradd \
    --home-dir "$USER_HOME" \
    --create-home \
    --shell /usr/sbin/nologin \
    --gid "$STORAGE_GROUP" \
    "$USERNAME"
else
  usermod --home "$USER_HOME" --shell /usr/sbin/nologin "$USERNAME"
fi

if [[ "$PASSWORD_STDIN" == "1" ]]; then
  IFS= read -r PASSWORD
  if [[ -z "$PASSWORD" ]]; then
    echo "密码不能为空。"
    exit 1
  fi
else
  read -r -s -p "请输入 $USERNAME 的密码：" PASSWORD
  echo
  read -r -s -p "请再次输入密码：" PASSWORD_CONFIRM
  echo

  if [[ "$PASSWORD" != "$PASSWORD_CONFIRM" ]]; then
    echo "两次输入的密码不一致。"
    exit 1
  fi
fi

printf '%s:%s\n' "$USERNAME" "$PASSWORD" | chpasswd
printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" | smbpasswd -s -a "$USERNAME"
smbpasswd -e "$USERNAME"

install -d -o "$USERNAME" -g "$STORAGE_GROUP" -m 0700 "$USER_HOME"
chmod 0700 "$USER_HOME"
chown "$USERNAME:$STORAGE_GROUP" "$USER_HOME"

"$SCRIPT_DIR/quota_manager.sh" set "$USERNAME" "$QUOTA_GB"

echo "已创建存储用户：$USERNAME"
echo "Samba 共享：//$SMB_NETBIOS_NAME/$USERNAME"
echo "存储路径：$USER_HOME"
