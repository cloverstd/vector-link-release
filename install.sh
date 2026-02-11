#!/usr/bin/env bash
set -euo pipefail

# Vector-Link 统一安装脚本
# 支持 Server/Node 模式，Docker/系统服务 两种安装方式
#
# 交互式安装:
#   curl -fsSL https://raw.githubusercontent.com/cloverstd/vector-link-release/main/install.sh | bash
#
# 非交互式安装:
#   # Docker Server
#   bash install.sh --mode server --method docker --port 8080
#
#   # 系统服务 Server
#   bash install.sh --mode server --method system --port 8080
#
#   # Docker Node
#   bash install.sh --mode node --method docker --master http://1.2.3.4:8080 --token YOUR_TOKEN
#
#   # 系统服务 Node
#   bash install.sh --mode node --method system --master http://1.2.3.4:8080 --token YOUR_TOKEN
#
#   # 卸载
#   bash install.sh --uninstall --mode server --method docker

# ── 常量 ────────────────────────────────────────────────────
REPO="cloverstd/vector-link-release"
BIN_NAME="vector-link"
DOCKER_IMAGE="ghcr.io/cloverstd/vector-link-release"

# 系统安装路径
BIN_PATH="/usr/local/bin/${BIN_NAME}"
CONFIG_DIR="/etc/vector-link"
DATA_DIR_SYSTEM="/var/lib/vector-link"

# Docker 安装路径
INSTALL_DIR_DEFAULT="/opt/vector-link"

# ── 全局变量 ─────────────────────────────────────────────────
MODE=""              # server | node
METHOD=""            # docker | system
VERSION=""           # 版本号（空则自动获取最新）
IMAGE_TAG="latest"   # Docker 镜像标签
PORT="8080"          # Server 端口
MASTER_URL=""        # Master 地址（Node 模式）
TOKEN=""             # Node Token
JWT_SECRET=""        # JWT 密钥（Server 模式）
JWT_EXPIRATION="24h" # JWT 过期时间
ADMIN_USER="admin"   # 管理员用户名
ADMIN_PASS=""        # 管理员密码（空则自动生成）
INSTALL_DIR=""       # Docker 安装目录
DATA_DIR=""          # 数据目录
TIMEZONE="Asia/Shanghai"
LOG_LEVEL="info"
REPORT_INTERVAL="30"
XRAY_VERSION="latest"
DO_UNINSTALL=false
OVERWRITE_BINARY=false
OVERWRITE_CONFIG=false
SKIP_NTP=false
AUTO_INSTALL_NTP=false

# ── 颜色输出 ─────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }

# ── 用户输入 ─────────────────────────────────────────────────
# 读取用户输入，支持管道模式 (curl | bash)
read_input() {
    local prompt="$1"
    local default="$2"
    local result=""

    printf "  ${CYAN}?${NC} %s ${BOLD}[%s]${NC}: " "$prompt" "$default" >&2

    if [ -t 0 ]; then
        read -r result
    elif [ -e /dev/tty ]; then
        read -r result < /dev/tty
    fi

    echo "${result:-$default}"
}

# 读取密码输入（不回显）
read_secret() {
    local prompt="$1"
    local default="$2"
    local result=""

    printf "  ${CYAN}?${NC} %s ${BOLD}[%s]${NC}: " "$prompt" "$default" >&2

    if [ -t 0 ]; then
        read -r -s result
        echo "" >&2
    elif [ -e /dev/tty ]; then
        read -r -s result < /dev/tty
        echo "" >&2
    fi

    echo "${result:-$default}"
}

# 选择菜单
read_choice() {
    local prompt="$1"
    shift
    local options=("$@")
    local choice=""

    echo "" >&2
    echo -e "  ${CYAN}?${NC} ${prompt}" >&2
    for i in "${!options[@]}"; do
        echo -e "    ${BOLD}$((i + 1)))${NC} ${options[$i]}" >&2
    done

    if [ -t 0 ]; then
        read -r -p "    请选择 [1]: " choice
    elif [ -e /dev/tty ]; then
        read -r -p "    请选择 [1]: " choice < /dev/tty
    fi

    choice="${choice:-1}"
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
        echo "$choice"
    else
        echo "1"
    fi
}

# ── 覆盖安装检测 ──────────────────────────────────────────
get_installed_version() {
    if [ -f "$BIN_PATH" ] && [ -x "$BIN_PATH" ]; then
        "$BIN_PATH" --version 2>/dev/null || echo "未知版本"
    else
        echo ""
    fi
}

check_existing_installation() {
    local mode="$1"
    local method="$2"

    # Docker 模式检查目录
    if [ "$method" = "docker" ]; then
        local dir="${INSTALL_DIR:-${INSTALL_DIR_DEFAULT}}"
        if [ -f "${dir}/docker-compose.yml" ]; then
            echo ""
            warn "检测到已有 Docker 安装: ${dir}"
            local choice
            choice=$(read_choice "请选择操作:" "覆盖安装（更新镜像，保留配置）" "覆盖安装（更新镜像和配置，原配置自动备份）" "取消安装")
            case "$choice" in
                1)
                    OVERWRITE_BINARY=true
                    info "将更新镜像，保留现有配置"
                    ;;
                2)
                    OVERWRITE_BINARY=true
                    OVERWRITE_CONFIG=true
                    info "将更新镜像和配置，原配置将备份"
                    ;;
                3)
                    info "安装已取消"
                    exit 0
                    ;;
            esac
        fi
        return
    fi

    # 系统服务模式检查二进制和配置
    local installed_version
    installed_version=$(get_installed_version)
    local config_file
    if [ "$mode" = "server" ]; then
        config_file="${CONFIG_DIR}/server.yaml"
    else
        config_file="${CONFIG_DIR}/node.yaml"
    fi

    if [ -n "$installed_version" ] || [ -f "$config_file" ]; then
        echo ""
        warn "检测到已有安装:"
        if [ -n "$installed_version" ]; then
            warn "  二进制文件: ${BIN_PATH} (${installed_version})"
        fi
        if [ -f "$config_file" ]; then
            warn "  配置文件: ${config_file}"
        fi

        local choice
        choice=$(read_choice "请选择操作:" "覆盖安装（更新二进制，保留配置）" "覆盖安装（更新二进制和配置，原配置自动备份）" "取消安装")
        case "$choice" in
            1)
                OVERWRITE_BINARY=true
                info "将更新二进制文件，保留现有配置"
                ;;
            2)
                OVERWRITE_BINARY=true
                OVERWRITE_CONFIG=true
                info "将更新二进制文件和配置，原配置将备份"
                ;;
            3)
                info "安装已取消"
                exit 0
                ;;
        esac
    fi
}

# ── NTP 时间同步 ──────────────────────────────────────────
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            debian|ubuntu|linuxmint|pop) echo "debian" ;;
            centos|rhel|rocky|alma|ol) echo "rhel" ;;
            fedora) echo "fedora" ;;
            alpine) echo "alpine" ;;
            arch|manjaro) echo "arch" ;;
            opensuse*|sles) echo "suse" ;;
            *) echo "unknown" ;;
        esac
    elif [ -f /etc/redhat-release ]; then
        echo "rhel"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

check_ntp_status() {
    # 方法1: timedatectl
    if command -v timedatectl &>/dev/null; then
        local ntp_status
        ntp_status=$(timedatectl 2>/dev/null | grep -iE "NTP (synchronized|service|enabled)" || true)
        if echo "$ntp_status" | grep -qiE "(yes|active|enabled)"; then
            return 0
        fi
    fi

    # 方法2: chronyc
    if command -v chronyc &>/dev/null; then
        if chronyc tracking &>/dev/null; then
            return 0
        fi
    fi

    # 方法3: ntpq
    if command -v ntpq &>/dev/null; then
        if ntpq -p &>/dev/null; then
            return 0
        fi
    fi

    # 方法4: systemd-timesyncd
    if systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
        return 0
    fi

    return 1
}

install_ntp() {
    local distro
    distro=$(detect_distro)

    info "正在安装 NTP 时间同步服务..."

    case "$distro" in
        debian)
            # 先尝试 timedatectl
            if command -v timedatectl &>/dev/null; then
                timedatectl set-ntp true 2>/dev/null && { success "已通过 timedatectl 启用 NTP 同步"; return 0; }
            fi
            # 安装 chrony
            apt-get update -qq && apt-get install -y -qq chrony >/dev/null 2>&1
            systemctl enable chrony && systemctl start chrony
            ;;
        rhel|fedora)
            yum install -y chrony >/dev/null 2>&1 || dnf install -y chrony >/dev/null 2>&1
            systemctl enable chronyd && systemctl start chronyd
            ;;
        alpine)
            apk add --no-cache chrony >/dev/null 2>&1
            rc-update add chronyd default 2>/dev/null || true
            service chronyd start 2>/dev/null || rc-service chronyd start 2>/dev/null || true
            ;;
        arch)
            pacman -Sy --noconfirm ntp >/dev/null 2>&1
            systemctl enable ntpd && systemctl start ntpd
            ;;
        suse)
            zypper install -y chrony >/dev/null 2>&1
            systemctl enable chronyd && systemctl start chronyd
            ;;
        *)
            warn "无法自动安装 NTP 服务（未识别的发行版），请手动安装"
            return 1
            ;;
    esac

    success "NTP 时间同步服务已安装并启动"
}

check_and_setup_ntp() {
    if check_ntp_status; then
        success "NTP 时间同步已启用"
        return 0
    fi

    warn "未检测到 NTP 时间同步服务"
    warn "Xray 节点时间不同步可能导致连接失败"

    if [ "$AUTO_INSTALL_NTP" = true ]; then
        install_ntp
        return $?
    fi

    local choice
    choice=$(read_choice "是否安装 NTP 时间同步服务？" "是，自动安装（推荐）" "否，跳过")
    case "$choice" in
        1) install_ntp ;;
        2) warn "已跳过 NTP 安装，请确保系统时间同步" ;;
    esac
}

# ── 工具函数 ─────────────────────────────────────────────────
generate_random() {
    head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'
}

generate_password() {
    head -c 12 /dev/urandom | base64 | tr -d '/+=' | head -c 16
}

convert_master_url() {
    local input="$1"
    local ws_url

    ws_url="${input/http:\/\//ws:\/\/}"
    ws_url="${ws_url/https:\/\//wss:\/\/}"
    ws_url="${ws_url%/}"

    echo "${ws_url}/api/v1/ws/node"
}

# ── 前置检查 ─────────────────────────────────────────────────
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "请以 root 用户或使用 sudo 运行此脚本"
    fi
}

check_systemd() {
    if ! command -v systemctl &>/dev/null; then
        error "系统安装需要 systemd 支持，当前系统不支持"
    fi
}

check_docker() {
    if ! command -v docker &>/dev/null; then
        error "未找到 docker 命令，请先安装 Docker: https://docs.docker.com/get-docker/"
    fi

    if ! docker compose version &>/dev/null 2>&1; then
        if ! docker-compose version &>/dev/null 2>&1; then
            error "未找到 docker compose 命令，请安装 Docker Compose v2"
        fi
    fi

    if ! docker info &>/dev/null 2>&1; then
        error "Docker 守护进程未运行或当前用户没有权限"
    fi
}

detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64 | amd64) echo "amd64" ;;
        aarch64 | arm64) echo "arm64" ;;
        *) error "不支持的架构: $arch（仅支持 amd64/arm64）" ;;
    esac
}

detect_os() {
    local os
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    case "$os" in
        linux) echo "linux" ;;
        *) error "不支持的操作系统: $os（仅支持 Linux）" ;;
    esac
}

docker_compose_cmd() {
    if docker compose version &>/dev/null 2>&1; then
        echo "docker compose"
    else
        echo "docker-compose"
    fi
}

# ── 版本获取 ─────────────────────────────────────────────────
get_latest_version() {
    local version
    version=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
    if [ -z "$version" ]; then
        error "无法获取最新版本号"
    fi
    echo "$version"
}

# ── 参数解析 ─────────────────────────────────────────────────
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --mode)
                MODE="$2"
                shift 2
                ;;
            --method)
                METHOD="$2"
                shift 2
                ;;
            --version)
                VERSION="$2"
                shift 2
                ;;
            --port)
                PORT="$2"
                shift 2
                ;;
            --master)
                MASTER_URL="$2"
                shift 2
                ;;
            --token)
                TOKEN="$2"
                shift 2
                ;;
            --jwt-secret)
                JWT_SECRET="$2"
                shift 2
                ;;
            --jwt-expiration)
                JWT_EXPIRATION="$2"
                shift 2
                ;;
            --admin-user)
                ADMIN_USER="$2"
                shift 2
                ;;
            --admin-pass)
                ADMIN_PASS="$2"
                shift 2
                ;;
            --install-dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            --data-dir)
                DATA_DIR="$2"
                shift 2
                ;;
            --timezone)
                TIMEZONE="$2"
                shift 2
                ;;
            --log-level)
                LOG_LEVEL="$2"
                shift 2
                ;;
            --report-interval)
                REPORT_INTERVAL="$2"
                shift 2
                ;;
            --xray-version)
                XRAY_VERSION="$2"
                shift 2
                ;;
            --uninstall)
                DO_UNINSTALL=true
                shift
                ;;
            --skip-ntp)
                SKIP_NTP=true
                shift
                ;;
            --install-ntp)
                AUTO_INSTALL_NTP=true
                shift
                ;;
            --help | -h)
                show_help
                exit 0
                ;;
            *)
                error "未知参数: $1\n运行 --help 查看用法"
                ;;
        esac
    done
}

show_help() {
    cat <<'EOF'
Vector-Link 统一安装脚本

用法:
  install.sh [选项]

通用选项:
  --mode server|node         安装模式（Server 控制端 / Node 节点）
  --method docker|system     安装方式（Docker 容器 / 系统服务）
  --version VERSION          指定版本号（默认: 最新版）
  --timezone TIMEZONE        时区（默认: Asia/Shanghai）
  --uninstall                卸载
  --skip-ntp               跳过 NTP 时间同步检查
  --install-ntp            自动安装 NTP（非交互式）
  --help                     显示帮助

Server 选项:
  --port PORT                监听端口（默认: 8080）
  --jwt-secret SECRET        JWT 密钥（默认: 自动生成）
  --jwt-expiration DURATION  JWT 过期时间（默认: 24h）
  --admin-user USERNAME      管理员用户名（默认: admin）
  --admin-pass PASSWORD      管理员密码（默认: 自动生成）

Node 选项:
  --master URL               Master 服务器地址（必填）
  --token TOKEN              节点 Token（必填）
  --xray-version VERSION     Xray 版本（默认: latest）
  --log-level LEVEL          日志级别（默认: info）
  --report-interval SECONDS  上报间隔秒数（默认: 30）

Docker 选项:
  --install-dir DIR          安装目录（默认: /opt/vector-link）

系统服务选项:
  --data-dir DIR             数据目录（默认: /var/lib/vector-link）

示例:
  # 交互式安装
  bash install.sh

  # Docker 安装 Server
  bash install.sh --mode server --method docker --port 8080

  # 系统服务安装 Node
  bash install.sh --mode node --method system --master http://1.2.3.4:8080 --token YOUR_TOKEN

  # 卸载 Docker Server
  bash install.sh --uninstall --mode server --method docker
EOF
}

# ── 交互式配置 ───────────────────────────────────────────────
prompt_mode() {
    local choice
    choice=$(read_choice "请选择安装模式:" "Server（控制端）" "Node（节点客户端）")
    case "$choice" in
        1) MODE="server" ;;
        2) MODE="node" ;;
    esac
}

prompt_method() {
    local choice
    choice=$(read_choice "请选择安装方式:" "Docker（推荐）" "系统服务（systemd）")
    case "$choice" in
        1) METHOD="docker" ;;
        2) METHOD="system" ;;
    esac
}

prompt_server_config() {
    echo "" >&2
    echo -e "  ${BLUE}── Server 配置 ──${NC}" >&2

    PORT=$(read_input "监听端口" "$PORT")

    local default_pass
    default_pass=$(generate_password)
    ADMIN_USER=$(read_input "管理员用户名" "$ADMIN_USER")
    if [ -z "$ADMIN_PASS" ]; then
        ADMIN_PASS=$(read_secret "管理员密码" "$default_pass")
    fi

    JWT_EXPIRATION=$(read_input "JWT 过期时间" "$JWT_EXPIRATION")

    if [ -z "$JWT_SECRET" ]; then
        JWT_SECRET=$(generate_random)
    fi

    if [ "$METHOD" = "docker" ]; then
        INSTALL_DIR=$(read_input "安装目录" "${INSTALL_DIR:-${INSTALL_DIR_DEFAULT}}")
    fi
}

prompt_node_config() {
    echo "" >&2
    echo -e "  ${BLUE}── Node 配置 ──${NC}" >&2

    while [ -z "$MASTER_URL" ]; do
        MASTER_URL=$(read_input "Master 服务器地址 (如 http://1.2.3.4:8080)" "")
        if [ -z "$MASTER_URL" ]; then
            warn "Master 地址不能为空"
        fi
    done

    while [ -z "$TOKEN" ]; do
        TOKEN=$(read_input "节点 Token" "")
        if [ -z "$TOKEN" ]; then
            warn "节点 Token 不能为空"
        fi
    done

    XRAY_VERSION=$(read_input "Xray 版本" "$XRAY_VERSION")
    LOG_LEVEL=$(read_input "日志级别 (debug/info/warn/error)" "$LOG_LEVEL")
    REPORT_INTERVAL=$(read_input "状态上报间隔（秒）" "$REPORT_INTERVAL")

    if [ "$METHOD" = "docker" ]; then
        INSTALL_DIR=$(read_input "安装目录" "${INSTALL_DIR:-${INSTALL_DIR_DEFAULT}}")
    fi
}

prompt_common_config() {
    TIMEZONE=$(read_input "时区" "$TIMEZONE")

    if [ "$METHOD" = "docker" ]; then
        IMAGE_TAG=$(read_input "镜像版本" "$IMAGE_TAG")
    else
        if [ -z "$VERSION" ]; then
            local ver
            ver=$(read_input "安装版本（留空使用最新版）" "latest")
            if [ "$ver" != "latest" ]; then
                VERSION="$ver"
            fi
        fi
    fi
}

# ── Docker 安装 ──────────────────────────────────────────────
install_docker_server() {
    check_docker

    local dir="${INSTALL_DIR:-${INSTALL_DIR_DEFAULT}}"
    local compose_cmd
    compose_cmd=$(docker_compose_cmd)

    info "安装目录: ${dir}"
    mkdir -p "${dir}/data"

    # 生成默认值
    [ -z "$JWT_SECRET" ] && JWT_SECRET=$(generate_random)
    [ -z "$ADMIN_PASS" ] && ADMIN_PASS=$(generate_password)

    # 生成 .env
    cat > "${dir}/.env" <<EOF
# Vector-Link Server 配置
# 修改后执行: ${compose_cmd} up -d

# 镜像版本
IMAGE_TAG=${IMAGE_TAG}

# 时区
TZ=${TIMEZONE}

# 数据目录（容器内挂载）
DATA_DIR=./data

# Server 端口
SERVER_PORT=${PORT}

# JWT 配置
JWT_SECRET=${JWT_SECRET}
JWT_EXPIRATION=${JWT_EXPIRATION}

# 管理员账号
ADMIN_USERNAME=${ADMIN_USER}
ADMIN_PASSWORD=${ADMIN_PASS}
EOF
    chmod 600 "${dir}/.env"
    success "配置文件已生成: ${dir}/.env"

    # 生成 docker-compose.yml
    cat > "${dir}/docker-compose.yml" <<'EOF'
services:
  server:
    image: ghcr.io/cloverstd/vector-link-release:${IMAGE_TAG:-latest}
    container_name: vector-link-server
    command: ["./vector-link", "server"]
    ports:
      - "${SERVER_PORT:-8080}:8080"
    volumes:
      - ${DATA_DIR:-./data}:/app/data
    environment:
      TZ: ${TZ:-Asia/Shanghai}
      DB_DSN: "file:/app/data/vector-link.db?cache=shared&_fk=1"
      JWT_SECRET: ${JWT_SECRET}
      JWT_EXPIRATION: ${JWT_EXPIRATION:-24h}
      ADMIN_USERNAME: ${ADMIN_USERNAME:-admin}
      ADMIN_PASSWORD: ${ADMIN_PASSWORD:-admin123}
    restart: unless-stopped
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8080/health"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 10s
EOF
    success "docker-compose.yml 已生成: ${dir}/docker-compose.yml"

    # 启动
    info "拉取镜像并启动容器..."
    cd "${dir}"
    ${compose_cmd} pull
    ${compose_cmd} up -d

    echo ""
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN} Vector-Link Server (Docker) 安装完成！${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo ""
    info "访问地址: http://<服务器IP>:${PORT}"
    info "管理账号: ${ADMIN_USER} / ${ADMIN_PASS}"
    info "安装目录: ${dir}"
    info ""
    info "常用命令:"
    info "  查看状态: cd ${dir} && ${compose_cmd} ps"
    info "  查看日志: cd ${dir} && ${compose_cmd} logs -f"
    info "  重启服务: cd ${dir} && ${compose_cmd} restart"
    info "  停止服务: cd ${dir} && ${compose_cmd} down"
    info "  更新版本: cd ${dir} && ${compose_cmd} pull && ${compose_cmd} up -d"
    echo ""
    warn "请立即修改默认密码！"
}

install_docker_node() {
    check_docker

    local dir="${INSTALL_DIR:-${INSTALL_DIR_DEFAULT}}"
    local compose_cmd
    compose_cmd=$(docker_compose_cmd)

    # 验证必要参数
    [ -z "$MASTER_URL" ] && error "缺少 --master 参数，请提供 Master 服务器地址"
    [ -z "$TOKEN" ] && error "缺少 --token 参数，请提供节点 Token"

    local ws_url
    ws_url=$(convert_master_url "$MASTER_URL")

    info "安装目录: ${dir}"
    mkdir -p "${dir}/data"

    # 生成 .env
    cat > "${dir}/.env" <<EOF
# Vector-Link Node 配置
# 修改后执行: ${compose_cmd} up -d

# 镜像版本
IMAGE_TAG=${IMAGE_TAG}

# 时区
TZ=${TIMEZONE}

# 数据目录（容器内挂载）
DATA_DIR=./data

# Master 连接
MASTER_URL=${ws_url}
MASTER_TOKEN=${TOKEN}

# Xray 配置
XRAY_VERSION=${XRAY_VERSION}

# 日志
LOG_LEVEL=${LOG_LEVEL}

# 上报间隔（秒）
REPORT_INTERVAL=${REPORT_INTERVAL}
EOF
    chmod 600 "${dir}/.env"
    success "配置文件已生成: ${dir}/.env"

    # 生成 docker-compose.yml
    cat > "${dir}/docker-compose.yml" <<'EOF'
services:
  node:
    image: ghcr.io/cloverstd/vector-link-release:${IMAGE_TAG:-latest}
    container_name: vector-link-node
    command: ["./vector-link", "node"]
    # 使用 host 网络模式，xray 需要直接监听主机端口
    network_mode: host
    volumes:
      - ${DATA_DIR:-./data}:/app/data
    environment:
      TZ: ${TZ:-Asia/Shanghai}
      MASTER_URL: ${MASTER_URL}
      MASTER_TOKEN: ${MASTER_TOKEN}
      XRAY_VERSION: ${XRAY_VERSION:-latest}
      XRAY_BIN_PATH: /app/data/xray
      XRAY_CONFIG_PATH: /app/data/xray-config.json
      XRAY_ASSET_PATH: /app/data/xray-assets
      LOG_LEVEL: ${LOG_LEVEL:-info}
      REPORT_INTERVAL: ${REPORT_INTERVAL:-30}
    restart: unless-stopped
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
    success "docker-compose.yml 已生成: ${dir}/docker-compose.yml"

    # 启动
    info "拉取镜像并启动容器..."
    cd "${dir}"
    ${compose_cmd} pull
    ${compose_cmd} up -d

    echo ""
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN} Vector-Link Node (Docker) 安装完成！${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo ""
    info "安装目录: ${dir}"
    info ""
    info "常用命令:"
    info "  查看状态: cd ${dir} && ${compose_cmd} ps"
    info "  查看日志: cd ${dir} && ${compose_cmd} logs -f"
    info "  重启服务: cd ${dir} && ${compose_cmd} restart"
    info "  停止服务: cd ${dir} && ${compose_cmd} down"
    info "  更新版本: cd ${dir} && ${compose_cmd} pull && ${compose_cmd} up -d"
}

# ── 系统服务安装 ─────────────────────────────────────────────
download_binary() {
    local version="$1"
    local os arch download_url

    os=$(detect_os)
    arch=$(detect_arch)

    if [ -z "$version" ]; then
        info "获取最新版本..."
        version=$(get_latest_version)
    fi
    info "安装版本: ${version}"

    download_url="https://github.com/${REPO}/releases/download/${version}/${BIN_NAME}-${os}-${arch}"
    info "下载 ${download_url} ..."

    if ! curl -fSL -o "${BIN_PATH}.tmp" "$download_url"; then
        rm -f "${BIN_PATH}.tmp"
        error "下载失败，请检查版本号和网络连接"
    fi
    mv "${BIN_PATH}.tmp" "${BIN_PATH}"
    chmod +x "${BIN_PATH}"
    success "二进制文件已安装到 ${BIN_PATH}"
}

install_system_server() {
    check_root
    check_systemd

    local data_dir="${DATA_DIR:-${DATA_DIR_SYSTEM}}"
    local config_file="${CONFIG_DIR}/server.yaml"
    local service_name="vector-link-server"
    local service_file="/etc/systemd/system/${service_name}.service"

    download_binary "$VERSION"

    mkdir -p "${CONFIG_DIR}" "${data_dir}"

    # 生成默认值
    [ -z "$JWT_SECRET" ] && JWT_SECRET=$(generate_random)
    [ -z "$ADMIN_PASS" ] && ADMIN_PASS=$(generate_password)

    # 生成配置文件（不覆盖已有配置）
    if [ ! -f "${config_file}" ] || [ "$OVERWRITE_CONFIG" = true ]; then
        if [ -f "${config_file}" ] && [ "$OVERWRITE_CONFIG" = true ]; then
            local backup="${config_file}.bak.$(date +%Y%m%d%H%M%S)"
            cp "${config_file}" "${backup}"
            info "原配置已备份到: ${backup}"
        fi
        cat > "${config_file}" <<EOF
server:
  host: 0.0.0.0
  port: ${PORT}

database:
  driver: sqlite3
  dsn: "file:${data_dir}/vector-link.db?cache=shared&_fk=1"

jwt:
  secret: "${JWT_SECRET}"
  expiration: ${JWT_EXPIRATION}

admin:
  username: ${ADMIN_USER}
  password: "${ADMIN_PASS}"
EOF
        chmod 600 "${config_file}"
        success "配置文件已生成: ${config_file}"
    else
        info "配置文件已存在，跳过生成: ${config_file}"
    fi

    # 创建 systemd 服务
    cat > "${service_file}" <<EOF
[Unit]
Description=Vector-Link Server
After=network.target

[Service]
Type=simple
ExecStart=${BIN_PATH} server -c ${config_file}
WorkingDirectory=${data_dir}
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
    success "systemd 服务已创建: ${service_file}"

    systemctl daemon-reload
    systemctl enable "${service_name}"
    systemctl restart "${service_name}"
    success "服务已启动"

    echo ""
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN} Vector-Link Server (系统服务) 安装完成！${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo ""
    info "访问地址: http://<服务器IP>:${PORT}"
    info "管理账号: ${ADMIN_USER} / ${ADMIN_PASS}"
    info "配置文件: ${config_file}"
    info "数据目录: ${data_dir}"
    info ""
    info "常用命令:"
    info "  查看状态: systemctl status ${service_name}"
    info "  查看日志: journalctl -u ${service_name} -f"
    info "  重启服务: systemctl restart ${service_name}"
    info "  停止服务: systemctl stop ${service_name}"
    echo ""
    warn "请立即修改默认密码！"
}

install_system_node() {
    check_root
    check_systemd

    local config_file="${CONFIG_DIR}/node.yaml"
    local service_name="vector-link-node"
    local service_file="/etc/systemd/system/${service_name}.service"

    # 验证必要参数
    [ -z "$MASTER_URL" ] && error "缺少 --master 参数，请提供 Master 服务器地址"
    [ -z "$TOKEN" ] && error "缺少 --token 参数，请提供节点 Token"

    local ws_url
    ws_url=$(convert_master_url "$MASTER_URL")

    download_binary "$VERSION"

    mkdir -p "${CONFIG_DIR}"

    # 生成配置文件（不覆盖已有配置）
    if [ ! -f "${config_file}" ] || [ "$OVERWRITE_CONFIG" = true ]; then
        if [ -f "${config_file}" ] && [ "$OVERWRITE_CONFIG" = true ]; then
            local backup="${config_file}.bak.$(date +%Y%m%d%H%M%S)"
            cp "${config_file}" "${backup}"
            info "原配置已备份到: ${backup}"
        fi
        cat > "${config_file}" <<EOF
master:
  url: "${ws_url}"
  token: "${TOKEN}"

xray:
  bin_path: "/usr/local/bin/xray"
  config_path: "/etc/xray/config.json"
  version: "${XRAY_VERSION}"
  asset_path: "/usr/local/share/xray"

log:
  level: "${LOG_LEVEL}"
  file: "/var/log/vector-link-node.log"

report_interval: ${REPORT_INTERVAL}
EOF
        chmod 600 "${config_file}"
        success "配置文件已生成: ${config_file}"
    else
        info "配置文件已存在，跳过生成: ${config_file}"
        warn "如需更新 master 地址或 token，请手动编辑: ${config_file}"
    fi

    # 创建 systemd 服务
    cat > "${service_file}" <<EOF
[Unit]
Description=Vector-Link Node
After=network.target

[Service]
Type=simple
ExecStart=${BIN_PATH} node -c ${config_file}
WorkingDirectory=${CONFIG_DIR}
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
    success "systemd 服务已创建: ${service_file}"

    systemctl daemon-reload
    systemctl enable "${service_name}"
    systemctl restart "${service_name}"
    success "服务已启动"

    echo ""
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN} Vector-Link Node (系统服务) 安装完成！${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo ""
    info "配置文件: ${config_file}"
    info ""
    info "常用命令:"
    info "  查看状态: systemctl status ${service_name}"
    info "  查看日志: journalctl -u ${service_name} -f"
    info "  重启服务: systemctl restart ${service_name}"
    info "  停止服务: systemctl stop ${service_name}"
}

# ── 卸载 ─────────────────────────────────────────────────────
uninstall_docker() {
    local dir="${INSTALL_DIR:-${INSTALL_DIR_DEFAULT}}"
    local compose_cmd

    if [ ! -f "${dir}/docker-compose.yml" ]; then
        error "未找到 Docker 安装: ${dir}/docker-compose.yml"
    fi

    compose_cmd=$(docker_compose_cmd)

    info "停止并删除容器..."
    cd "${dir}"
    ${compose_cmd} down

    warn "安装目录未删除（如需清理请手动操作）："
    warn "  目录: ${dir}"

    success "Docker 卸载完成"
}

uninstall_system() {
    check_root

    local service_name="vector-link-${MODE}"
    local service_file="/etc/systemd/system/${service_name}.service"

    info "开始卸载 Vector-Link ${MODE}..."

    if systemctl is-active --quiet "${service_name}" 2>/dev/null; then
        info "停止服务..."
        systemctl stop "${service_name}"
    fi
    if systemctl is-enabled --quiet "${service_name}" 2>/dev/null; then
        info "禁用服务..."
        systemctl disable "${service_name}"
    fi

    [ -f "$service_file" ] && rm -f "$service_file" && info "已删除 ${service_file}"
    systemctl daemon-reload 2>/dev/null || true

    [ -f "$BIN_PATH" ] && rm -f "$BIN_PATH" && info "已删除 ${BIN_PATH}"

    warn "配置和数据目录未删除（如需清理请手动操作）："
    warn "  配置: ${CONFIG_DIR}"
    [ "$MODE" = "server" ] && warn "  数据: ${DATA_DIR_SYSTEM}"

    success "系统服务卸载完成"
}

do_uninstall() {
    [ -z "$MODE" ] && prompt_mode
    [ -z "$METHOD" ] && prompt_method

    case "$METHOD" in
        docker) uninstall_docker ;;
        system) uninstall_system ;;
        *) error "无效的安装方式: $METHOD" ;;
    esac
}

# ── 主流程 ───────────────────────────────────────────────────
main() {
    parse_args "$@"

    echo ""
    echo -e "${BOLD}${BLUE}Vector-Link 安装向导${NC}"
    echo -e "${BLUE}════════════════════${NC}"

    # 卸载模式
    if [ "$DO_UNINSTALL" = true ]; then
        do_uninstall
        exit 0
    fi

    # 交互式选择
    [ -z "$MODE" ] && prompt_mode
    [ -z "$METHOD" ] && prompt_method

    # 收集配置
    case "$MODE" in
        server) prompt_server_config ;;
        node) prompt_node_config ;;
        *) error "无效的模式: $MODE（仅支持 server/node）" ;;
    esac
    prompt_common_config

    check_existing_installation "$MODE" "$METHOD"

    if [ "$SKIP_NTP" != true ]; then
        check_and_setup_ntp
    fi

    # 确认信息
    echo ""
    echo -e "  ${BLUE}── 安装概要 ──${NC}"
    echo -e "  模式:     ${BOLD}${MODE}${NC}"
    echo -e "  安装方式: ${BOLD}${METHOD}${NC}"
    if [ "$MODE" = "server" ]; then
        echo -e "  端口:     ${BOLD}${PORT}${NC}"
        echo -e "  管理员:   ${BOLD}${ADMIN_USER}${NC}"
    else
        echo -e "  Master:   ${BOLD}${MASTER_URL}${NC}"
    fi
    echo ""

    # 执行安装
    case "${MODE}-${METHOD}" in
        server-docker) install_docker_server ;;
        server-system) install_system_server ;;
        node-docker) install_docker_node ;;
        node-system) install_system_node ;;
        *) error "无效的组合: mode=${MODE}, method=${METHOD}" ;;
    esac
}

main "$@"
