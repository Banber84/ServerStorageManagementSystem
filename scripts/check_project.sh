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
"$PROJECT_ROOT/scripts/ssmsctl" system --help >/dev/null

echo "检查后台 API 路径。"
grep -qF '/api/users/username/$username/quota' "$PROJECT_ROOT/scripts/backend_sync.sh"
grep -qF '/api/storage/username' "$PROJECT_ROOT/scripts/backend_sync.sh"
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
grep -qF 'systemctl restart storage-usage-sync.timer' "$PROJECT_ROOT/scripts/install_management_server.sh"
grep -qF 'install -m 0755 "$PROJECT_ROOT/scripts/ssmsctl" /usr/local/bin/ssmsctl' "$PROJECT_ROOT/scripts/install_node_client.sh"
grep -qF 'install -m 0755 "$PROJECT_ROOT/scripts/ssmsctl" /usr/local/bin/ssmsctl' "$PROJECT_ROOT/scripts/install_storage_server.sh"
grep -qF 'install -m 0755 "$PROJECT_ROOT/scripts/ssmsctl" /usr/local/bin/ssmsctl' "$PROJECT_ROOT/scripts/install_management_server.sh"

echo "检查统一节点配置更新。"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
cp "$PROJECT_ROOT/configs/site.env.example" "$tmp_dir/site.env"
cat > "$tmp_dir/nodes.conf" <<'EOF'
# test nodes
NodeA 192.168.1.122 nodea1 /home/nodea1/ServerStorageManagementSystem
nodeC 192.168.1.215 nodec1 /home/nodec1/ServerStorageManagementSystem
EOF
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/nodes_config.sh"
ssms_sync_site_nodes "$tmp_dir/site.env" "$tmp_dir/nodes.conf"
grep -qF 'NodeA 192.168.1.122 nodea1' "$tmp_dir/site.env"
grep -qF 'nodeC 192.168.1.215 nodec1' "$tmp_dir/site.env"
[[ "$(grep -c '^SSMS_NODES=' "$tmp_dir/site.env")" -eq 1 ]]
bash -n "$tmp_dir/site.env"

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
