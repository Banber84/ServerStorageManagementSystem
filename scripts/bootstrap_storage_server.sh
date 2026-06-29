#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SITE_CONFIG="$PROJECT_ROOT/configs/site.env"
SERVER_HOST=""
ADMIN_USER="${SUDO_USER:-}"
AGENT_NAME="StorageServer"
SKIP_QUOTA="0"
SKIP_AGENT="0"
GO_PROXY="${GOPROXY:-https://goproxy.cn,direct}"
GO_SUM_DB="${GOSUMDB:-sum.golang.google.cn}"
LOG_FILE="/var/log/ssms/bootstrap-storage-server.log"

usage() {
  cat <<'EOF'
用法：
  sudo scripts/ssmsctl system bootstrap --host HOST [选项]
  sudo scripts/bootstrap_storage_server.sh --config FILE [选项]

在全新的 Ubuntu Storage Server 上自动完成：
  1. 安装编译、Samba、quota 和管理后台依赖。
  2. 生成 /etc/ssms 统一运行配置。
  3. 安装并启动 Samba。
  4. 为 STORAGE_ROOT 所在 ext4 文件系统启用用户/组 quota。
  5. 编译并安装管理后台和 Storage Agent。
  6. 启动用量同步定时器并执行健康检查。

选项：
  --host HOST          当前 Storage Server 的固定 IP 或域名；site.env 不存在时必填
  --config FILE        site.env 路径，默认 configs/site.env
  --admin-user USER    管理用户，默认 sudo 发起用户
  --agent-name NAME    后台显示的节点名，默认 StorageServer
  --skip-quota         跳过 fstab 修改和 quota 启用
  --skip-agent         跳过 Storage Agent 编译与安装
  --go-proxy URL       Go 模块代理，默认 https://goproxy.cn,direct
  --go-sumdb HOST      Go 校验服务，默认 sum.golang.google.cn

全新虚拟机示例：
  sudo scripts/ssmsctl system bootstrap --host 192.168.1.230

如果已经填写 configs/site.env：
  sudo scripts/ssmsctl system bootstrap --config configs/site.env
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      SERVER_HOST="${2:-}"
      shift 2
      ;;
    --config)
      SITE_CONFIG="${2:-}"
      shift 2
      ;;
    --admin-user)
      ADMIN_USER="${2:-}"
      shift 2
      ;;
    --agent-name)
      AGENT_NAME="${2:-}"
      shift 2
      ;;
    --skip-quota)
      SKIP_QUOTA="1"
      shift
      ;;
    --skip-agent)
      SKIP_AGENT="1"
      shift
      ;;
    --go-proxy)
      GO_PROXY="${2:-}"
      shift 2
      ;;
    --go-sumdb)
      GO_SUM_DB="${2:-}"
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

if [[ $EUID -ne 0 ]]; then
  echo "请使用 root 权限执行：sudo $0" >&2
  exit 1
fi
if [[ ! -f /etc/os-release ]]; then
  echo "无法识别当前操作系统。" >&2
  exit 1
fi
# shellcheck source=/dev/null
source /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "当前自动部署仅支持 Ubuntu，检测到：${ID:-unknown}" >&2
  exit 1
fi
if [[ -n "$SERVER_HOST" && ! "$SERVER_HOST" =~ ^[a-zA-Z0-9._:-]+$ ]]; then
  echo "Storage Server 地址非法：$SERVER_HOST" >&2
  exit 1
fi
if [[ -n "$ADMIN_USER" && ! "$ADMIN_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  echo "管理用户非法：$ADMIN_USER" >&2
  exit 1
fi
if [[ ! "$AGENT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "Agent 名称非法：$AGENT_NAME" >&2
  exit 1
fi
if [[ -z "$GO_PROXY" || -z "$GO_SUM_DB" ]]; then
  echo "Go 模块代理和校验服务不能为空。" >&2
  exit 1
fi

install -d -m 0755 /var/log/ssms
touch "$LOG_FILE"
chmod 0600 "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "开始自动部署 Storage Server：$(date --iso-8601=seconds)"
echo "项目目录：$PROJECT_ROOT"
echo "部署日志：$LOG_FILE"

set_site_value() {
  local file="$1"
  local key="$2"
  local value="$3"
  local quoted tmp
  printf -v quoted '%q' "$value"
  tmp="$(mktemp)"
  awk -v key="$key" -v replacement="$key=$quoted" '
    index($0, key "=") == 1 {
      print replacement
      updated = 1
      next
    }
    { print }
    END {
      if (!updated) {
        print replacement
      }
    }
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

prepare_site_config() {
  local config_owner
  if [[ ! -f "$SITE_CONFIG" ]]; then
    if [[ -z "$SERVER_HOST" ]]; then
      echo "缺少 $SITE_CONFIG；首次部署请使用 --host 指定当前服务器地址。" >&2
      exit 1
    fi
    if [[ -z "$ADMIN_USER" ]]; then
      echo "无法确定管理用户，请使用 --admin-user 指定。" >&2
      exit 1
    fi
    if ! id "$ADMIN_USER" >/dev/null 2>&1; then
      echo "管理用户不存在：$ADMIN_USER" >&2
      exit 1
    fi
    cp "$PROJECT_ROOT/configs/site.env.example" "$SITE_CONFIG"
    echo "已从模板创建：$SITE_CONFIG"
  fi

  if [[ -n "$SERVER_HOST" ]]; then
    if [[ -z "$ADMIN_USER" ]]; then
      echo "使用 --host 时必须能确定管理用户，请使用 --admin-user 指定。" >&2
      exit 1
    fi
    if ! id "$ADMIN_USER" >/dev/null 2>&1; then
      echo "管理用户不存在：$ADMIN_USER" >&2
      exit 1
    fi
    set_site_value "$SITE_CONFIG" SSMS_MANAGEMENT_HOST "$SERVER_HOST"
    set_site_value "$SITE_CONFIG" STORAGE_SERVER "$SERVER_HOST"
    set_site_value "$SITE_CONFIG" STORAGE_SYNC_HOST "$SERVER_HOST"
    set_site_value "$SITE_CONFIG" STORAGE_SYNC_USER "$ADMIN_USER"
    set_site_value "$SITE_CONFIG" STORAGE_SYNC_PROJECT_DIR "$PROJECT_ROOT"
    set_site_value "$SITE_CONFIG" SSMS_AGENT_NAME "$AGENT_NAME"
    set_site_value "$SITE_CONFIG" SSMS_AGENT_ADDRESS "$SERVER_HOST"
  fi

  chmod 0600 "$SITE_CONFIG"
  config_owner="${ADMIN_USER:-root}"
  if id "$config_owner" >/dev/null 2>&1; then
    chown "$config_owner:" "$SITE_CONFIG"
  fi
}

validate_site_config_for_host() {
  local management_host management_port
  # shellcheck source=/dev/null
  source "$SITE_CONFIG"
  management_host="${SSMS_MANAGEMENT_HOST:-}"
  management_port="${SSMS_MANAGEMENT_PORT:-8080}"

  if [[ ! "$management_port" =~ ^[0-9]+$ ]] ||
     [[ "$management_port" -lt 1 || "$management_port" -gt 65535 ]]; then
    echo "管理后台端口非法：$management_port" >&2
    exit 1
  fi
  if [[ "${STORAGE_ROOT:-}" != /* ]]; then
    echo "STORAGE_ROOT 必须是绝对路径：${STORAGE_ROOT:-<empty>}" >&2
    exit 1
  fi
  if ! id "${STORAGE_SYNC_USER:-}" >/dev/null 2>&1; then
    echo "Storage Server 管理用户不存在：${STORAGE_SYNC_USER:-<empty>}" >&2
    exit 1
  fi
  if [[ ! -x "${STORAGE_SYNC_PROJECT_DIR:-}/scripts/ssmsctl" ]]; then
    echo "Storage Server 项目目录无效：${STORAGE_SYNC_PROJECT_DIR:-<empty>}" >&2
    exit 1
  fi
  if [[ "$management_host" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] &&
     ! ip -o -4 addr show | awk '{ sub(/\/.*/, "", $4); print $4 }' | grep -Fxq "$management_host"; then
    echo "site.env 中的管理地址未配置在本机网卡：$management_host" >&2
    echo "请先设置固定 IP，或使用正确的 --host 后重试。" >&2
    exit 1
  fi
}

install_build_dependencies() {
  echo "安装基础依赖。"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential \
    ca-certificates \
    curl \
    golang-go \
    python3
  command -v go >/dev/null 2>&1
  command -v gcc >/dev/null 2>&1
}

configure_go_environment() {
  local build_user build_home
  build_user="${ADMIN_USER:-$STORAGE_SYNC_USER}"
  build_home="$(getent passwd "$build_user" | cut -d: -f6)"
  sudo -u "$build_user" env HOME="$build_home" \
    go env -w "GOPROXY=$GO_PROXY" "GOSUMDB=$GO_SUM_DB"
  echo "Go 镜像配置已写入 $build_user："
  sudo -u "$build_user" env HOME="$build_home" go env GOPROXY GOSUMDB
}

configure_quota_mount() {
  local mount_point filesystem_type mount_options backup tmp
  mount_point="$(findmnt -no TARGET --target "$STORAGE_ROOT")"
  filesystem_type="$(findmnt -no FSTYPE --target "$STORAGE_ROOT")"
  mount_options="$(findmnt -no OPTIONS --target "$STORAGE_ROOT")"

  echo "quota 文件系统：$mount_point ($filesystem_type)"
  if [[ "$filesystem_type" != "ext4" ]]; then
    echo "自动 quota 配置仅支持 ext4，当前为 $filesystem_type。" >&2
    echo "可使用 --skip-quota 跳过，并按实际文件系统手工配置。" >&2
    exit 1
  fi

  if [[ ",$mount_options," != *,usrquota,* || ",$mount_options," != *,grpquota,* ]]; then
    backup="/etc/fstab.ssms.$(date +%Y%m%d%H%M%S).bak"
    cp /etc/fstab "$backup"
    tmp="$(mktemp)"
    if ! awk -v target="$mount_point" '
      /^[[:space:]]*#/ || NF == 0 {
        print
        next
      }
      $2 == target {
        options = $4
        if ("," options "," !~ /,usrquota,/) {
          options = options ",usrquota"
        }
        if ("," options "," !~ /,grpquota,/) {
          options = options ",grpquota"
        }
        printf "%s\t%s\t%s\t%s\t%s\t%s\n", $1, $2, $3, options, ($5 == "" ? 0 : $5), ($6 == "" ? 0 : $6)
        updated = 1
        next
      }
      { print }
      END {
        if (!updated) {
          exit 42
        }
      }
    ' /etc/fstab > "$tmp"; then
      rm -f "$tmp"
      echo "未在 /etc/fstab 找到挂载点：$mount_point" >&2
      echo "原文件未修改，备份位于：$backup" >&2
      exit 1
    fi
    install -m 0644 "$tmp" /etc/fstab
    rm -f "$tmp"
    echo "已更新 /etc/fstab，备份：$backup"
    if ! mount -o remount "$mount_point"; then
      echo "fstab 已更新，但重新挂载失败。请重启后再次运行 bootstrap。" >&2
      exit 1
    fi
  fi

  mount_options="$(findmnt -no OPTIONS --target "$STORAGE_ROOT")"
  if [[ ",$mount_options," != *,usrquota,* || ",$mount_options," != *,grpquota,* ]]; then
    echo "quota 挂载参数未生效：$mount_options" >&2
    exit 1
  fi
  if [[ ",$mount_options," == *,quota,* ]] ||
     quotaon -p "$mount_point" 2>/dev/null | grep -Eqi 'user quota.*(is on|enabled)'; then
    echo "用户 quota 已启用，跳过重复 quotacheck。"
  else
    "$SCRIPT_DIR/quota_manager.sh" enable
  fi
}

build_binaries() {
  local build_user build_home build_group
  build_user="${ADMIN_USER:-$STORAGE_SYNC_USER}"
  build_home="$(getent passwd "$build_user" | cut -d: -f6)"
  build_group="$(id -gn "$build_user")"
  echo "编译管理后台和 Storage Agent。"
  install -d -o "$build_user" -g "$build_group" -m 0755 "$PROJECT_ROOT/bin"
  chown "$build_user:$build_group" "$PROJECT_ROOT/bin"
  sudo -u "$build_user" env \
      HOME="$build_home" \
      CGO_ENABLED=1 \
      GOPROXY="$GO_PROXY" \
      GOSUMDB="$GO_SUM_DB" \
      go -C "$PROJECT_ROOT" build -o bin/storage-server ./server
  if [[ "$SKIP_AGENT" == "0" ]]; then
    sudo -u "$build_user" env \
        HOME="$build_home" \
        CGO_ENABLED=1 \
        GOPROXY="$GO_PROXY" \
        GOSUMDB="$GO_SUM_DB" \
        go -C "$PROJECT_ROOT" build -o bin/storage-agent ./agent
  fi
}

configure_firewall() {
  local management_port
  if ! command -v ufw >/dev/null 2>&1 || ! ufw status | grep -q '^Status: active'; then
    return
  fi
  # shellcheck source=/dev/null
  source "$SITE_CONFIG"
  management_port="${SSMS_MANAGEMENT_PORT:-8080}"
  echo "检测到 UFW 已启用，添加 SSH、Samba 和管理后台规则。"
  ufw allow OpenSSH
  if ufw app info Samba >/dev/null 2>&1; then
    ufw allow Samba
  else
    ufw allow 445/tcp
  fi
  ufw allow "$management_port/tcp"
}

verify_deployment() {
  local backend_url ready
  # shellcheck source=/dev/null
  source /etc/ssms/backend.conf
  backend_url="${BACKEND_API_BASE%/}"

  systemctl is-active --quiet smbd
  systemctl is-active --quiet nmbd
  systemctl is-active --quiet storage-server
  systemctl is-active --quiet storage-usage-sync.timer
  if [[ "$SKIP_AGENT" == "0" ]]; then
    systemctl is-active --quiet storage-agent
  fi
  testparm -s >/dev/null

  ready="0"
  for _ in {1..15}; do
    if curl -sS --fail --max-time 3 "$backend_url/api/health" >/dev/null; then
      ready="1"
      break
    fi
    sleep 1
  done
  if [[ "$ready" != "1" ]]; then
    echo "管理后台健康检查失败：$backend_url/api/health" >&2
    journalctl -u storage-server -n 30 --no-pager >&2 || true
    exit 1
  fi

  systemctl start storage-usage-sync.service
  systemctl is-failed --quiet storage-usage-sync.service && {
    journalctl -u storage-usage-sync.service -n 30 --no-pager >&2
    exit 1
  }

  echo
  echo "Storage Server 自动部署完成。"
  echo "管理后台：$backend_url"
  echo "Samba 地址：//$STORAGE_SERVER/USERNAME"
  echo "统一命令：ssmsctl --help"
  echo "部署日志：$LOG_FILE"
}

prepare_site_config
validate_site_config_for_host
install_build_dependencies
configure_go_environment
"$SCRIPT_DIR/apply_site_config.sh" --config "$SITE_CONFIG" --output-dir /etc/ssms

echo "安装 Samba Storage Server。"
CONFIG_FILE=/etc/ssms/system.conf \
BACKEND_CONFIG_FILE=/etc/ssms/backend.conf \
BOOTSTRAP_MODE=1 \
  "$SCRIPT_DIR/install_storage_server.sh"
# shellcheck source=/dev/null
source /etc/ssms/system.conf

if [[ "$SKIP_QUOTA" == "0" ]]; then
  configure_quota_mount
else
  echo "已跳过 quota 自动配置。"
fi

build_binaries
SITE_CONFIG="$SITE_CONFIG" "$SCRIPT_DIR/install_management_server.sh"
if [[ "$SKIP_AGENT" == "0" ]]; then
  SITE_CONFIG="$SITE_CONFIG" "$SCRIPT_DIR/install_storage_agent.sh"
fi
configure_firewall
verify_deployment
