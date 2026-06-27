#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'EOF'
用法：
  sudo scripts/install_node_agent.sh \
    --binary PATH \
    --server-url URL \
    --name NODE_NAME \
    --address NODE_ADDRESS

在登录节点安装并启动 storage-agent systemd 服务。
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

AGENT_BINARY=""
SERVER_URL=""
NODE_NAME=""
NODE_ADDRESS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --binary)
      AGENT_BINARY="${2:-}"
      shift 2
      ;;
    --server-url)
      SERVER_URL="${2:-}"
      shift 2
      ;;
    --name)
      NODE_NAME="${2:-}"
      shift 2
      ;;
    --address)
      NODE_ADDRESS="${2:-}"
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

if [[ ! -f "$AGENT_BINARY" ]]; then
  echo "Agent 可执行文件不存在：$AGENT_BINARY" >&2
  exit 1
fi
if [[ ! "$SERVER_URL" =~ ^https?://[^[:space:]]+$ ]]; then
  echo "管理后台地址非法：$SERVER_URL" >&2
  exit 1
fi
if [[ ! "$NODE_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "节点名非法：$NODE_NAME" >&2
  exit 1
fi
if [[ ! "$NODE_ADDRESS" =~ ^[a-zA-Z0-9._:-]+$ ]]; then
  echo "节点地址非法：$NODE_ADDRESS" >&2
  exit 1
fi
if [[ ! -f "$PROJECT_ROOT/configs/storage-agent.service" ]]; then
  echo "缺少 systemd 服务模板：$PROJECT_ROOT/configs/storage-agent.service" >&2
  exit 1
fi

install -d -m 0755 /etc/ssms
install -m 0755 "$AGENT_BINARY" /usr/local/bin/storage-agent

{
  printf 'SSMS_SERVER_URL=%q\n' "$SERVER_URL"
  printf 'SSMS_AGENT_NAME=%q\n' "$NODE_NAME"
  printf 'SSMS_AGENT_ADDRESS=%q\n' "$NODE_ADDRESS"
  printf 'SSMS_AGENT_DISK=%q\n' "/"
  printf 'SSMS_AGENT_INTERVAL=%q\n' "30s"
} > /etc/ssms/storage-agent.env
chmod 0644 /etc/ssms/storage-agent.env

install -m 0644 \
  "$PROJECT_ROOT/configs/storage-agent.service" \
  /etc/systemd/system/storage-agent.service

systemctl daemon-reload
systemctl enable storage-agent
systemctl restart storage-agent
systemctl is-active --quiet storage-agent

echo "节点 Agent 安装完成：$NODE_NAME ($NODE_ADDRESS)"
echo "管理后台：$SERVER_URL"
