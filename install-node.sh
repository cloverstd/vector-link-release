#!/usr/bin/env bash
set -euo pipefail

# Vector-Link Node 一键部署脚本
# 用法:
#   安装:   curl -fsSL http://<Server地址>:8080/api/v1/install-node.sh | bash -s -- --master http://<Server地址>:8080 --token YOUR_TOKEN
#   指定版本: curl -fsSL ... | bash -s -- --master ... --token ... --version v1.0.0
#   卸载:   curl -fsSL ... | bash -s -- --uninstall

REPO="cloverstd/vector-link-release"
BIN_NAME="vector-link"
BIN_PATH="/usr/local/bin/${BIN_NAME}"
CONFIG_DIR="/etc/vector-link"
CONFIG_FILE="${CONFIG_DIR}/node.yaml"
SERVICE_NAME="vector-link-node"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# ── 颜色输出 ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── 前置检查 ──────────────────────────────────────────────
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "请以 root 用户或使用 sudo 运行此脚本"
    fi
}

check_systemd() {
    if ! command -v systemctl &>/dev/null; then
        error "此脚本需要 systemd，当前系统不支持"
    fi
}

detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)  echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
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

# ── 版本获取 ──────────────────────────────────────────────
get_latest_version() {
    local version
    version=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
    if [ -z "$version" ]; then
        error "无法获取最新版本号"
    fi
    echo "$version"
}

# ── URL 转换 ──────────────────────────────────────────────
convert_master_url() {
    local input="$1"
    local ws_url

    # http:// -> ws://, https:// -> wss://
    ws_url="${input/http:\/\//ws:\/\/}"
    ws_url="${ws_url/https:\/\//wss:\/\/}"

    # 移除末尾斜杠
    ws_url="${ws_url%/}"

    # 追加 WebSocket 路径
    echo "${ws_url}/api/v1/ws/node"
}

# ── 卸载 ──────────────────────────────────────────────────
uninstall() {
    info "开始卸载 Vector-Link Node..."

    if systemctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null; then
        info "停止服务..."
        systemctl stop "${SERVICE_NAME}"
    fi
    if systemctl is-enabled --quiet "${SERVICE_NAME}" 2>/dev/null; then
        info "禁用服务..."
        systemctl disable "${SERVICE_NAME}"
    fi

    [ -f "$SERVICE_FILE" ] && rm -f "$SERVICE_FILE" && info "已删除 ${SERVICE_FILE}"
    systemctl daemon-reload 2>/dev/null || true

    [ -f "$BIN_PATH" ] && rm -f "$BIN_PATH" && info "已删除 ${BIN_PATH}"

    warn "配置目录未删除（如需清理请手动操作）："
    warn "  配置: ${CONFIG_DIR}"

    info "卸载完成"
    exit 0
}

# ── 安装 ──────────────────────────────────────────────────
install() {
    local version="$1"
    local master_url="$2"
    local token="$3"
    local os arch download_url ws_url

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
    info "二进制文件已安装到 ${BIN_PATH}"

    # 创建目录
    mkdir -p "${CONFIG_DIR}"

    # 生成配置文件（不覆盖已有配置）
    if [ ! -f "${CONFIG_FILE}" ]; then
        ws_url=$(convert_master_url "$master_url")
        cat > "${CONFIG_FILE}" <<EOF
master:
  url: "${ws_url}"
  token: "${token}"

xray:
  bin_path: "/usr/local/bin/xray"
  config_path: "/etc/xray/config.json"
  version: "latest"
  asset_path: "/usr/local/share/xray"

log:
  level: "info"
  file: "/var/log/vector-link-node.log"

report_interval: 30
EOF
        chmod 600 "${CONFIG_FILE}"
        info "配置文件已生成: ${CONFIG_FILE}"
    else
        info "配置文件已存在，跳过生成: ${CONFIG_FILE}"
        warn "如需更新 master 地址或 token，请手动编辑: ${CONFIG_FILE}"
    fi

    # 创建 systemd 服务
    cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Vector-Link Node
After=network.target

[Service]
Type=simple
ExecStart=${BIN_PATH} node -c ${CONFIG_FILE}
WorkingDirectory=${CONFIG_DIR}
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
    info "systemd 服务已创建: ${SERVICE_FILE}"

    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}"
    systemctl restart "${SERVICE_NAME}"
    info "服务已启动"

    echo ""
    info "========================================="
    info " Vector-Link Node 安装完成！"
    info "========================================="
    info ""
    info "配置文件: ${CONFIG_FILE}"
    info ""
    info "常用命令:"
    info "  查看状态: systemctl status ${SERVICE_NAME}"
    info "  查看日志: journalctl -u ${SERVICE_NAME} -f"
    info "  重启服务: systemctl restart ${SERVICE_NAME}"
    info "  停止服务: systemctl stop ${SERVICE_NAME}"
}

# ── 主流程 ──────────────────────────────────────────────
main() {
    local version=""
    local master_url=""
    local token=""
    local do_uninstall=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --version|-v)
                version="$2"
                shift 2
                ;;
            --master|-m)
                master_url="$2"
                shift 2
                ;;
            --token|-t)
                token="$2"
                shift 2
                ;;
            --uninstall)
                do_uninstall=true
                shift
                ;;
            *)
                error "未知参数: $1"
                ;;
        esac
    done

    check_root
    check_systemd

    if [ "$do_uninstall" = true ]; then
        uninstall
    fi

    # 验证必要参数
    if [ -z "$master_url" ]; then
        error "缺少 --master 参数，请提供 Master 服务器地址，例如: --master http://1.2.3.4:8080"
    fi
    if [ -z "$token" ]; then
        error "缺少 --token 参数，请提供节点 Token，例如: --token YOUR_NODE_TOKEN"
    fi

    install "$version" "$master_url" "$token"
}

main "$@"
