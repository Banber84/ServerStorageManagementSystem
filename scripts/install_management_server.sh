#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SITE_CONFIG="${SITE_CONFIG:-$PROJECT_ROOT/configs/site.env}"
APP_DIR="${APP_DIR:-/opt/ssms}"

usage() {
  cat <<'EOF'
用法：
  sudo scripts/install_management_server.sh

说明：
  安装主节点 Web 管理后台：
    1. 创建 /opt/ssms 和 /etc/ssms
    2. 复制 server/templates、docs、configs、scripts 等运行文件
    3. 安装 bin/storage-server 到 /usr/local/bin/storage-server
    4. 根据 configs/site.env 生成 /etc/ssms/storage-server.env
    5. 安装并启动 storage-server.service
    6. 安装并启动 storage-usage-sync.timer

执行前请先在仓库根目录编译：
  go build -o bin/storage-server ./server

并填写统一部署配置：
  cp configs/site.env.example configs/site.env
  vim configs/site.env
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

if [[ ! -x "$PROJECT_ROOT/bin/storage-server" ]]; then
  echo "缺少可执行文件：$PROJECT_ROOT/bin/storage-server" >&2
  echo "请先执行：go build -o bin/storage-server ./server" >&2
  exit 1
fi

if [[ ! -f "$SITE_CONFIG" ]]; then
  echo "缺少统一部署配置：$SITE_CONFIG" >&2
  echo "请先执行：cp configs/site.env.example configs/site.env，并填写真实部署信息" >&2
  exit 1
fi

install -d -m 0755 "$APP_DIR" /etc/ssms

if [[ -z "$APP_DIR" || "$APP_DIR" == "/" ]]; then
  echo "APP_DIR 配置危险：$APP_DIR" >&2
  exit 1
fi
for managed_path in server agent docs configs scripts README.md LICENSE; do
  rm -rf "$APP_DIR/$managed_path"
done

cp -R \
  "$PROJECT_ROOT/server" \
  "$PROJECT_ROOT/agent" \
  "$PROJECT_ROOT/docs" \
  "$PROJECT_ROOT/configs" \
  "$PROJECT_ROOT/scripts" \
  "$PROJECT_ROOT/README.md" \
  "$PROJECT_ROOT/LICENSE" \
  "$APP_DIR/"

install -m 0755 "$PROJECT_ROOT/bin/storage-server" /usr/local/bin/storage-server
install -m 0755 "$PROJECT_ROOT/scripts/ssmsctl" /usr/local/bin/ssmsctl
"$PROJECT_ROOT/scripts/apply_site_config.sh" --config "$SITE_CONFIG" --output-dir /etc/ssms
install -m 0644 "$PROJECT_ROOT/configs/storage-server.service" /etc/systemd/system/storage-server.service
install -m 0644 "$PROJECT_ROOT/configs/storage-usage-sync.service" /etc/systemd/system/storage-usage-sync.service
install -m 0644 "$PROJECT_ROOT/configs/storage-usage-sync.timer" /etc/systemd/system/storage-usage-sync.timer

systemctl daemon-reload
systemctl enable storage-server
systemctl restart storage-server
systemctl enable storage-usage-sync.timer
systemctl restart storage-usage-sync.timer

cat <<EOF
管理后台安装完成。

运行目录：$APP_DIR
统一管理命令：ssmsctl --help
服务状态：sudo systemctl status storage-server
用量定时器：sudo systemctl status storage-usage-sync.timer
健康检查：curl http://127.0.0.1:8080/api/health
EOF
