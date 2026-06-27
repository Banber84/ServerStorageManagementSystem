#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "检查 Shell 语法。"
while IFS= read -r -d '' script; do
  bash -n "$script"
done < <(find "$PROJECT_ROOT/scripts" -type f -name '*.sh' -print0 | sort -z)

echo "检查关键命令帮助入口。"
for script in \
  backend_sync.sh \
  create_node_user.sh \
  install_node_agent.sh \
  join_node.sh \
  leave_node.sh
do
  "$PROJECT_ROOT/scripts/$script" --help >/dev/null
done

echo "检查后台 API 路径。"
grep -qF '/api/users/username/$username/quota' "$PROJECT_ROOT/scripts/backend_sync.sh"
grep -qF '/api/storage/username' "$PROJECT_ROOT/scripts/backend_sync.sh"
if grep -qE '/api/users/\$username/quota|/api/storage/by-username' "$PROJECT_ROOT/scripts/backend_sync.sh"; then
  echo "发现已废弃的后台 API 路径。" >&2
  exit 1
fi

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
