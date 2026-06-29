#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "检查 Shell 语法。"
while IFS= read -r -d '' script; do
  bash -n "$script"
done < <(find "$PROJECT_ROOT/scripts" -type f \( -name '*.sh' -o -name 'ssmsctl' \) -print0 | sort -z)

echo "检查关键命令帮助入口。"
for script in \
  backend_sync.sh \
  bootstrap_storage_server.sh \
  create_node_user.sh \
  deploy_smb_gateways.sh \
  install_node_agent.sh \
  install_smb_gateway.sh \
  join_node.sh \
  leave_node.sh \
  ssmsctl
do
  "$PROJECT_ROOT/scripts/$script" --help >/dev/null
done
"$PROJECT_ROOT/scripts/ssmsctl" node --help >/dev/null
"$PROJECT_ROOT/scripts/ssmsctl" user --help >/dev/null
"$PROJECT_ROOT/scripts/ssmsctl" quota --help >/dev/null
"$PROJECT_ROOT/scripts/ssmsctl" gateway --help >/dev/null
"$PROJECT_ROOT/scripts/ssmsctl" usage --help >/dev/null
"$PROJECT_ROOT/scripts/ssmsctl" backend --help >/dev/null
"$PROJECT_ROOT/scripts/ssmsctl" system --help >/dev/null

echo "检查后台 API 路径。"
grep -qF '/api/users/username/$username/quota' "$PROJECT_ROOT/scripts/backend_sync.sh"
grep -qF '/api/storage/username' "$PROJECT_ROOT/scripts/backend_sync.sh"
grep -qF 'list-users)' "$PROJECT_ROOT/scripts/backend_sync.sh"
grep -qF 'user:list)' "$PROJECT_ROOT/scripts/ssmsctl"
if grep -qE '/api/users/\$username/quota|/api/storage/by-username' "$PROJECT_ROOT/scripts/backend_sync.sh"; then
  echo "发现已废弃的后台 API 路径。" >&2
  exit 1
fi
grep -qF '"${SSH_CMD[@]}" -n "$SSH_USER@$NODE_HOST"' "$PROJECT_ROOT/scripts/sync_delete_user.sh"
grep -qF 'ListenStream=445' "$PROJECT_ROOT/configs/ssms-smb-gateway.socket"
grep -qF 'systemd-socket-proxyd' "$PROJECT_ROOT/scripts/install_smb_gateway.sh"
grep -qF 'sync_node_smb_gateway_files' "$PROJECT_ROOT/scripts/join_node.sh"
grep -qF 'node_smb_gateway_ready' "$PROJECT_ROOT/scripts/join_node.sh"
grep -qF 'install_smb_gateway.sh' "$PROJECT_ROOT/scripts/leave_node.sh"
grep -qF 'SMB 网关卸载检查失败' "$PROJECT_ROOT/scripts/leave_node.sh"
grep -qF 'OnUnitActiveSec=1min' "$PROJECT_ROOT/configs/storage-usage-sync.timer"
grep -qF '<meta http-equiv="refresh" content="30">' "$PROJECT_ROOT/server/templates/storage.html"
grep -qF 'quota_manager.sh" ensure' "$PROJECT_ROOT/scripts/create_user.sh"
grep -qF 'ensure_quota_ready' "$PROJECT_ROOT/scripts/quota_manager.sh"
grep -qF 'quota_setup_hint' "$PROJECT_ROOT/scripts/quota_manager.sh"
if grep -qF '*,quota,*' "$PROJECT_ROOT/scripts/quota_manager.sh"; then
  echo "quota_manager.sh 不能只根据 mount options 中的 quota 判断用户 quota 已启用。" >&2
  exit 1
fi
grep -qF 'systemctl restart storage-usage-sync.timer' "$PROJECT_ROOT/scripts/install_management_server.sh"
grep -qF 'systemctl restart storage-agent' "$PROJECT_ROOT/scripts/install_storage_agent.sh"
grep -qF 'system:bootstrap' "$PROJECT_ROOT/scripts/ssmsctl"
grep -qF 'configure_quota_mount' "$PROJECT_ROOT/scripts/bootstrap_storage_server.sh"
grep -qF -- '--check-only' "$PROJECT_ROOT/scripts/bootstrap_storage_server.sh"
grep -qF 'run_preflight_check' "$PROJECT_ROOT/scripts/bootstrap_storage_server.sh"
grep -qF 'ensure_bootstrap_auth_config' "$PROJECT_ROOT/scripts/bootstrap_storage_server.sh"
grep -qF '已恢复 /etc/fstab' "$PROJECT_ROOT/scripts/bootstrap_storage_server.sh"
grep -qF 'go env -w "GOPROXY=$GO_PROXY" "GOSUMDB=$GO_SUM_DB"' "$PROJECT_ROOT/scripts/bootstrap_storage_server.sh"
grep -qF 'BACKEND_CONFIG_FILE=/etc/ssms/backend.conf' "$PROJECT_ROOT/scripts/bootstrap_storage_server.sh"
grep -qF 'BOOTSTRAP_MODE=1' "$PROJECT_ROOT/scripts/bootstrap_storage_server.sh"
grep -qF 'quota_is_active' "$PROJECT_ROOT/scripts/quota_manager.sh"
grep -qF '"$CONFIG_FILE" -ef /etc/ssms/system.conf' "$PROJECT_ROOT/scripts/install_storage_server.sh"
grep -qF 'install -m 0755 "$PROJECT_ROOT/scripts/ssmsctl" /usr/local/bin/ssmsctl' "$PROJECT_ROOT/scripts/install_node_client.sh"
grep -qF 'install -m 0644 "$PROJECT_ROOT/configs/backend.conf" /etc/ssms/backend.conf' "$PROJECT_ROOT/scripts/install_node_client.sh"
grep -qF 'BACKEND_API_BASE=%q' "$PROJECT_ROOT/scripts/join_node.sh"
grep -qF '$NODE_TARGET:$NODE_PROJECT_DIR/configs/backend.conf' "$PROJECT_ROOT/scripts/join_node.sh"
grep -qF 'install -m 0755 "$PROJECT_ROOT/scripts/ssmsctl" /usr/local/bin/ssmsctl' "$PROJECT_ROOT/scripts/install_storage_server.sh"
grep -qF 'install -m 0755 "$PROJECT_ROOT/scripts/ssmsctl" /usr/local/bin/ssmsctl' "$PROJECT_ROOT/scripts/install_management_server.sh"
grep -qF 'candidates+=("$invoking_home/SSMS")' "$PROJECT_ROOT/scripts/ssmsctl"
grep -qF 'for managed_path in server agent docs configs scripts README.md LICENSE' "$PROJECT_ROOT/scripts/install_management_server.sh"
grep -qF 'SSMS_AUTH_ENABLED' "$PROJECT_ROOT/configs/site.env.example"
grep -qF 'SSMS_ADMIN_PASSWORD' "$PROJECT_ROOT/scripts/apply_site_config.sh"
grep -qF 'SSMS_SESSION_SECRET' "$PROJECT_ROOT/scripts/apply_site_config.sh"

echo "检查文档分类。"
if find "$PROJECT_ROOT/docs/deployment" -maxdepth 1 -type f -name '*test-report.md' -print -quit | grep -q .; then
  echo "测试报告必须存放在 docs/reports，不应放在 docs/deployment。" >&2
  exit 1
fi
for report in "$PROJECT_ROOT"/docs/reports/*-test-report.md; do
  grep -qF '本文仅记录历史实测过程与结论' "$report"
done

echo "检查统一节点配置更新。"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
cp "$PROJECT_ROOT/configs/site.env.example" "$tmp_dir/site.env"
cat > "$tmp_dir/nodes.conf" <<'EOF'
# test nodes
NodeA 192.168.1.122 nodea1 /home/nodea1/SSMS
nodeC 192.168.1.215 nodec1 /home/nodec1/SSMS
EOF
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/nodes_config.sh"
ssms_sync_site_nodes "$tmp_dir/site.env" "$tmp_dir/nodes.conf"
grep -qF 'NodeA 192.168.1.122 nodea1' "$tmp_dir/site.env"
grep -qF 'nodeC 192.168.1.215 nodec1' "$tmp_dir/site.env"
[[ "$(grep -c '^SSMS_NODES=' "$tmp_dir/site.env")" -eq 1 ]]
bash -n "$tmp_dir/site.env"

cat > "$tmp_dir/site-valid.env" <<'EOF'
SSMS_MANAGEMENT_HOST="192.168.1.187"
SSMS_MANAGEMENT_PORT="8080"
SSMS_MANAGEMENT_URL=""
BACKEND_SYNC_ENABLED="1"
BACKEND_API_TIMEOUT="5"
SSMS_SERVER_ADDR="0.0.0.0:${SSMS_MANAGEMENT_PORT}"
SSMS_DB_PATH="/var/lib/ssms/server-storage.db"
GIN_MODE="release"
SSMS_AUTH_ENABLED="1"
SSMS_ADMIN_USERNAME="admin"
SSMS_ADMIN_PASSWORD="test-password"
SSMS_ADMIN_PASSWORD_HASH=""
SSMS_SESSION_SECRET="test-session-secret"
STORAGE_SERVER="192.168.1.187"
STORAGE_ROOT="/srv/samba/users"
STORAGE_GROUP="storageusers"
DEFAULT_QUOTA_GB="10"
MOUNT_POINT_NAME="storage"
SMB_WORKGROUP="WORKGROUP"
SMB_NETBIOS_NAME="SSMS-STORAGE"
STORAGE_SYNC_HOST="192.168.1.187"
STORAGE_SYNC_USER="a2"
STORAGE_SYNC_PROJECT_DIR="/home/a2/SSMS"
DEFAULT_SYNC_QUOTA_GB="1"
SSMS_AGENT_NAME="NodeA"
SSMS_AGENT_ADDRESS="192.168.1.188"
SSMS_AGENT_DISK="/"
SSMS_AGENT_INTERVAL="30s"
SSMS_NODES="
NodeA 192.168.1.188 nodea1 /home/nodea1/SSMS
"
EOF
"$PROJECT_ROOT/scripts/apply_site_config.sh" --config "$tmp_dir/site-valid.env" --output-dir "$tmp_dir/generated" >/dev/null
grep -qF 'BACKEND_API_BASE=http://192.168.1.187:8080' "$tmp_dir/generated/backend.conf"
grep -qF 'BACKEND_SYNC_ENABLED=1' "$tmp_dir/generated/backend.conf"
grep -qF 'BACKEND_API_TIMEOUT=5' "$tmp_dir/generated/backend.conf"
grep -qF 'SSMS_AUTH_ENABLED=1' "$tmp_dir/generated/storage-server.env"
grep -qF 'SSMS_ADMIN_USERNAME=admin' "$tmp_dir/generated/storage-server.env"
grep -qF 'SSMS_SESSION_SECRET=test-session-secret' "$tmp_dir/generated/storage-server.env"

sed '/^NodeA 192\.168\.1\.188 /d' "$tmp_dir/site-valid.env" > "$tmp_dir/site-empty.env"
"$PROJECT_ROOT/scripts/apply_site_config.sh" --config "$tmp_dir/site-empty.env" --output-dir "$tmp_dir/generated-empty" >/dev/null
grep -qF '# 未配置 SSMS_NODES。' "$tmp_dir/generated-empty/nodes.conf"

if command -v go >/dev/null 2>&1; then
  echo "运行 Go 测试。"
  (
    cd "$PROJECT_ROOT"
    go test ./...
  )
else
  echo "未安装 Go，已跳过 Go 测试。"
fi

echo "项目检查通过。"
