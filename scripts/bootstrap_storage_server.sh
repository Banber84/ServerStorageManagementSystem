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
CHECK_ONLY="0"
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
  --check-only         只执行环境和配置预检查，不安装依赖，不修改系统
  --go-proxy URL       Go 模块代理，默认 https://goproxy.cn,direct
  --go-sumdb HOST      Go 校验服务，默认 sum.golang.google.cn

全新虚拟机示例：
  sudo scripts/ssmsctl system bootstrap --host 192.168.1.230

部署前预检查：
  sudo scripts/ssmsctl system bootstrap --host 192.168.1.230 --check-only

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
    --check-only)
      CHECK_ONLY="1"
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

if [[ "$CHECK_ONLY" == "0" ]]; then
  install -d -m 0755 /var/log/ssms
  touch "$LOG_FILE"
  chmod 0600 "$LOG_FILE"
  exec > >(tee -a "$LOG_FILE") 2>&1

  echo "开始自动部署 Storage Server：$(date --iso-8601=seconds)"
  echo "项目目录：$PROJECT_ROOT"
  echo "部署日志：$LOG_FILE"
fi

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

random_hex() {
  local bytes="$1"
  od -An -N "$bytes" -tx1 /dev/urandom | tr -d ' \n'
}

ensure_bootstrap_auth_config() {
  local admin_username admin_password admin_password_hash session_secret generated_password

  # shellcheck source=/dev/null
  source "$SITE_CONFIG"
  admin_username="${SSMS_ADMIN_USERNAME:-admin}"
  admin_password="${SSMS_ADMIN_PASSWORD:-}"
  admin_password_hash="${SSMS_ADMIN_PASSWORD_HASH:-}"
  session_secret="${SSMS_SESSION_SECRET:-}"
  generated_password=""

  set_site_value "$SITE_CONFIG" SSMS_AUTH_ENABLED "1"
  if [[ -z "$admin_username" ]]; then
    admin_username="admin"
  fi
  set_site_value "$SITE_CONFIG" SSMS_ADMIN_USERNAME "$admin_username"

  if [[ -z "$admin_password" && -z "$admin_password_hash" ]]; then
    generated_password="$(random_hex 12)"
    set_site_value "$SITE_CONFIG" SSMS_ADMIN_PASSWORD "$generated_password"
  fi
  if [[ -z "$session_secret" ]]; then
    set_site_value "$SITE_CONFIG" SSMS_SESSION_SECRET "$(random_hex 32)"
  fi

  if [[ -n "$generated_password" ]]; then
    echo "已生成管理后台初始账号：$admin_username"
    echo "已生成管理后台初始密码：$generated_password"
    echo "请部署完成后妥善保存，并在 $SITE_CONFIG 中修改默认管理员密码。"
  fi
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

  ensure_bootstrap_auth_config
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

check_command_available() {
  local command_name="$1"
  if command -v "$command_name" >/dev/null 2>&1; then
    echo "OK  command: $command_name"
    return 0
  fi
  echo "FAIL command missing: $command_name" >&2
  return 1
}

check_listening_port() {
  local port="$1"
  if command -v ss >/dev/null 2>&1 &&
     ss -H -ltn "sport = :$port" 2>/dev/null | grep -q .; then
    echo "WARN port $port 已被监听；如果是已有 storage-server，可忽略。"
  else
    echo "OK  port: $port"
  fi
}

check_quota_target() {
  local storage_root="$1"
  local target mount_point filesystem_type mount_options
  target="$storage_root"
  while [[ ! -e "$target" && "$target" != "/" ]]; do
    target="$(dirname "$target")"
  done

  mount_point="$(findmnt -no TARGET --target "$target" 2>/dev/null || true)"
  filesystem_type="$(findmnt -no FSTYPE --target "$target" 2>/dev/null || true)"
  mount_options="$(findmnt -no OPTIONS --target "$target" 2>/dev/null || true)"
  if [[ -z "$mount_point" || -z "$filesystem_type" ]]; then
    echo "FAIL 无法识别 STORAGE_ROOT 所在挂载点：$storage_root" >&2
    return 1
  fi

  echo "OK  quota target: $storage_root -> $mount_point ($filesystem_type)"
  if [[ "$filesystem_type" != "ext4" ]]; then
    echo "WARN 自动 quota 配置仅支持 ext4；当前为 $filesystem_type，部署时需使用 --skip-quota 或手工配置。"
  elif [[ ",$mount_options," == *,usrquota,* && ",$mount_options," == *,grpquota,* ]]; then
    echo "OK  quota mount options: $mount_options"
  else
    echo "WARN ext4 挂载参数未包含 usrquota,grpquota；正式部署会备份并更新 /etc/fstab。"
  fi
}

run_preflight_check() {
  local failures=0
  local management_host management_port storage_root sync_user sync_project

  echo "开始 Storage Server 部署预检查。"
  echo "项目目录：$PROJECT_ROOT"
  echo "配置文件：$SITE_CONFIG"

  for command_name in apt-get awk findmnt getent grep id install ip mktemp mount od sed systemctl tee; do
    check_command_available "$command_name" || failures=$((failures + 1))
  done

  if [[ -n "$ADMIN_USER" ]]; then
    if id "$ADMIN_USER" >/dev/null 2>&1; then
      echo "OK  admin user: $ADMIN_USER"
    else
      echo "FAIL 管理用户不存在：$ADMIN_USER" >&2
      failures=$((failures + 1))
    fi
  else
    echo "FAIL 无法确定管理用户，请使用 --admin-user 指定。" >&2
    failures=$((failures + 1))
  fi

  if [[ ! -x "$PROJECT_ROOT/scripts/ssmsctl" ]]; then
    echo "FAIL ssmsctl 不可执行：$PROJECT_ROOT/scripts/ssmsctl" >&2
    failures=$((failures + 1))
  else
    echo "OK  ssmsctl: $PROJECT_ROOT/scripts/ssmsctl"
  fi

  if [[ -f "$SITE_CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "$SITE_CONFIG"
    management_host="${SSMS_MANAGEMENT_HOST:-}"
    management_port="${SSMS_MANAGEMENT_PORT:-8080}"
    storage_root="${STORAGE_ROOT:-/srv/samba/users}"
    sync_user="${STORAGE_SYNC_USER:-}"
    sync_project="${STORAGE_SYNC_PROJECT_DIR:-}"
    if [[ -n "$SERVER_HOST" ]]; then
      management_host="$SERVER_HOST"
      sync_user="$ADMIN_USER"
      sync_project="$PROJECT_ROOT"
      echo "WARN 本次预检查按 --host 覆盖后的配置判断，不修改现有 site.env。"
    fi
  else
    if [[ -z "$SERVER_HOST" ]]; then
      echo "FAIL 缺少 $SITE_CONFIG；首次部署预检查请使用 --host 指定当前服务器地址。" >&2
      failures=$((failures + 1))
    fi
    management_host="$SERVER_HOST"
    management_port="8080"
    storage_root="/srv/samba/users"
    sync_user="$ADMIN_USER"
    sync_project="$PROJECT_ROOT"
    echo "WARN $SITE_CONFIG 不存在；本次按默认模板和 --host 推断配置，不创建文件。"
  fi

  if [[ ! "$management_port" =~ ^[0-9]+$ ]] ||
     [[ "$management_port" -lt 1 || "$management_port" -gt 65535 ]]; then
    echo "FAIL 管理后台端口非法：$management_port" >&2
    failures=$((failures + 1))
  fi
  if [[ "$storage_root" != /* ]]; then
    echo "FAIL STORAGE_ROOT 必须是绝对路径：$storage_root" >&2
    failures=$((failures + 1))
  fi

  if [[ -n "$management_host" && "$management_host" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] &&
     ! ip -o -4 addr show | awk '{ sub(/\/.*/, "", $4); print $4 }' | grep -Fxq "$management_host"; then
    echo "FAIL 管理地址未配置在本机网卡：$management_host" >&2
    failures=$((failures + 1))
  elif [[ -n "$management_host" ]]; then
    echo "OK  management host: $management_host"
  fi

  if [[ -n "$sync_user" ]] && id "$sync_user" >/dev/null 2>&1; then
    echo "OK  storage sync user: $sync_user"
  elif [[ -n "$sync_user" ]]; then
    echo "FAIL Storage Server 管理用户不存在：$sync_user" >&2
    failures=$((failures + 1))
  fi

  if [[ -n "$sync_project" && -x "$sync_project/scripts/ssmsctl" ]]; then
    echo "OK  storage project: $sync_project"
  elif [[ -n "$sync_project" ]]; then
    echo "FAIL Storage Server 项目目录无效：$sync_project" >&2
    failures=$((failures + 1))
  fi

  if [[ "$management_port" =~ ^[0-9]+$ ]] &&
     [[ "$management_port" -ge 1 && "$management_port" -le 65535 ]]; then
    check_listening_port "$management_port"
  fi
  if [[ "$SKIP_QUOTA" == "0" && "$storage_root" == /* ]]; then
    check_quota_target "$storage_root" || failures=$((failures + 1))
  elif [[ "$SKIP_QUOTA" == "0" ]]; then
    echo "WARN 已跳过 quota 挂载点检查，因为 STORAGE_ROOT 无效。"
  else
    echo "OK  quota: skipped by --skip-quota"
  fi

  if [[ "$failures" -gt 0 ]]; then
    echo "预检查失败：$failures 项错误。未修改系统。" >&2
    exit 1
  fi
  echo "预检查通过。未修改系统。"
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
      echo "fstab 已更新，但重新挂载失败，正在恢复备份：$backup" >&2
      install -m 0644 "$backup" /etc/fstab
      mount -o remount "$mount_point" >/dev/null 2>&1 || true
      echo "已恢复 /etc/fstab。请检查挂载配置后再次运行 bootstrap。" >&2
      exit 1
    fi
  fi

  mount_options="$(findmnt -no OPTIONS --target "$STORAGE_ROOT")"
  if [[ ",$mount_options," != *,usrquota,* || ",$mount_options," != *,grpquota,* ]]; then
    echo "quota 挂载参数未生效：$mount_options" >&2
    exit 1
  fi
  "$SCRIPT_DIR/quota_manager.sh" ensure
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

if [[ "$CHECK_ONLY" == "1" ]]; then
  run_preflight_check
  exit 0
fi

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
