#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'EOF'
用法：
  sudo scripts/install_smb_gateway.sh --storage-server HOST
  sudo scripts/install_smb_gateway.sh --uninstall

在登录节点监听 TCP 445，并把 SMB 流量透明转发到 Storage Server:445。
节点不保存 Samba 用户、密码或文件。
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
if [[ $EUID -ne 0 ]]; then
  echo "请使用 root 权限执行：sudo $0" >&2
  exit 1
fi

STORAGE_SERVER=""
UNINSTALL="0"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --storage-server)
      STORAGE_SERVER="${2:-}"
      shift 2
      ;;
    --uninstall)
      UNINSTALL="1"
      shift
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

SOCKET_UNIT="/etc/systemd/system/ssms-smb-gateway.socket"
SERVICE_UNIT="/etc/systemd/system/ssms-smb-gateway.service"

if [[ "$UNINSTALL" == "1" ]]; then
  systemctl disable --now ssms-smb-gateway.socket >/dev/null 2>&1 || true
  systemctl stop ssms-smb-gateway.service >/dev/null 2>&1 || true
  rm -f "$SOCKET_UNIT" "$SERVICE_UNIT"
  systemctl daemon-reload
  systemctl reset-failed ssms-smb-gateway.socket >/dev/null 2>&1 || true
  systemctl reset-failed ssms-smb-gateway.service >/dev/null 2>&1 || true
  if systemctl is-active --quiet ssms-smb-gateway.socket ||
     systemctl is-active --quiet ssms-smb-gateway.service ||
     [[ -e "$SOCKET_UNIT" || -e "$SERVICE_UNIT" ]]; then
    echo "SMB 网关卸载后仍有残留，请检查 systemd 状态。" >&2
    exit 1
  fi
  echo "SMB 网关已卸载。"
  exit 0
fi

if [[ ! "$STORAGE_SERVER" =~ ^[a-zA-Z0-9._:-]+$ ]]; then
  echo "Storage Server 地址非法：$STORAGE_SERVER" >&2
  exit 1
fi
if [[ ! -f "$PROJECT_ROOT/configs/ssms-smb-gateway.socket" ]]; then
  echo "缺少 socket 单元模板：$PROJECT_ROOT/configs/ssms-smb-gateway.socket" >&2
  exit 1
fi

PROXY_BIN=""
for candidate in \
  /usr/lib/systemd/systemd-socket-proxyd \
  /lib/systemd/systemd-socket-proxyd
do
  if [[ -x "$candidate" ]]; then
    PROXY_BIN="$candidate"
    break
  fi
done
if [[ -z "$PROXY_BIN" ]]; then
  echo "系统缺少 systemd-socket-proxyd，无法安装 SMB 网关。" >&2
  exit 1
fi

systemctl disable --now ssms-smb-gateway.socket >/dev/null 2>&1 || true
systemctl stop ssms-smb-gateway.service >/dev/null 2>&1 || true
if ss -H -ltn 'sport = :445' | grep -q .; then
  echo "本机 TCP 445 已被占用。请先停止节点上的 Samba 或其他 SMB 服务。" >&2
  ss -H -ltnp 'sport = :445' >&2 || true
  exit 1
fi

install -m 0644 \
  "$PROJECT_ROOT/configs/ssms-smb-gateway.socket" \
  "$SOCKET_UNIT"

cat > "$SERVICE_UNIT" <<EOF
[Unit]
Description=SSMS SMB gateway to $STORAGE_SERVER
Documentation=https://www.freedesktop.org/software/systemd/man/systemd-socket-proxyd.html
Requires=ssms-smb-gateway.socket
After=network-online.target ssms-smb-gateway.socket
Wants=network-online.target

[Service]
ExecStart=$PROXY_BIN --connections-max=256 $STORAGE_SERVER:445
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
NoNewPrivileges=true
EOF

systemctl daemon-reload
systemctl enable --now ssms-smb-gateway.socket
systemctl is-active --quiet ssms-smb-gateway.socket
if ! ss -H -ltn 'sport = :445' | grep -q .; then
  echo "SMB 网关 socket 已启动，但本机 TCP 445 未监听。" >&2
  exit 1
fi

echo "SMB 网关安装完成：本机:445 -> $STORAGE_SERVER:445"
echo "Windows 示例：\\\\本节点IP\\alice"
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q '^Status: active'; then
  echo "UFW 已启用；请确认局域网客户端允许访问 TCP 445。"
fi
