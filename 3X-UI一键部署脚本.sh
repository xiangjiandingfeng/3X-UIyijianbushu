#!/bin/bash

################################################################################
# 3X-UI 中转服务器完整部署脚本
# 功能：完全复刻当前服务器的网络优化配置和3X-UI面板
# 系统要求：Ubuntu 24.04 LTS (Noble Numbat)
# 作者：基于 199.180.119.149 服务器配置生成
# 日期：2026-02-10
################################################################################

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${PLAIN} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${PLAIN} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${PLAIN} $1"
}

log_step() {
    echo -e "\n${BLUE}========================================${PLAIN}"
    echo -e "${BLUE}$1${PLAIN}"
    echo -e "${BLUE}========================================${PLAIN}\n"
}

# 检查是否为root用户
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        log_error "请使用root用户运行此脚本"
        exit 1
    fi
}

# 检查系统版本
check_system() {
    log_step "步骤1: 检查系统版本"
    
    if [ ! -f /etc/os-release ]; then
        log_error "无法检测系统版本"
        exit 1
    fi
    
    source /etc/os-release
    
    if [ "$ID" != "ubuntu" ] || [ "$VERSION_ID" != "24.04" ]; then
        log_warn "当前系统: $PRETTY_NAME"
        log_warn "推荐系统: Ubuntu 24.04 LTS"
        read -p "是否继续安装? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log_info "系统版本检查通过: $PRETTY_NAME"
    fi
    
    # 显示内核版本
    KERNEL_VERSION=$(uname -r)
    log_info "内核版本: $KERNEL_VERSION"
}

# 更新系统并安装依赖
install_dependencies() {
    log_step "步骤2: 更新系统并安装依赖"
    
    log_info "更新软件包列表..."
    export DEBIAN_FRONTEND=noninteractive
    apt update -y
    
    log_info "升级系统软件包..."
    apt upgrade -y
    
    log_info "安装必要依赖..."
    apt install -y \
        curl \
        wget \
        sqlite3 \
        systemd \
        net-tools \
        iproute2 \
        ca-certificates \
        gnupg \
        lsb-release
    
    log_info "依赖安装完成"
}

# 配置BBR加速
configure_bbr() {
    log_step "步骤3: 配置BBR加速和网络优化"
    
    # 检查内核是否支持BBR
    if ! lsmod | grep -q bbr; then
        log_info "加载BBR模块..."
        modprobe tcp_bbr
        echo "tcp_bbr" >> /etc/modules-load.d/bbr.conf
    fi
    
    # 备份sysctl.conf
    if [ ! -f /etc/sysctl.conf.bak ]; then
        cp /etc/sysctl.conf /etc/sysctl.conf.bak
        log_info "已备份 /etc/sysctl.conf"
    fi
    
    # 配置BBR和网络优化参数
    log_info "配置BBR和网络优化参数..."
    
    cat >> /etc/sysctl.conf << 'EOF'

# ============================================
# BBR加速和网络优化配置
# 由3X-UI部署脚本自动添加
# ============================================

# BBR拥塞控制算法
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# TCP Fast Open
net.ipv4.tcp_fastopen = 3

# TCP缓冲区优化（适合高延迟网络）
net.ipv4.tcp_rmem = 4096        131072  6291456
net.ipv4.tcp_wmem = 4096        16384   4194304

# 网络邻居表优化
net.ipv4.neigh.default.base_reachable_time_ms = 600000
net.ipv4.neigh.default.mcast_solicit = 20
net.ipv4.neigh.default.retrans_time_ms = 250

# 关闭反向路径过滤（用于多网卡场景）
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0

# TCP连接优化
net.ipv4.tcp_tw_reuse = 2
net.ipv4.tcp_fin_timeout = 60
net.ipv4.ip_local_port_range = 32768 60999

# 网络设备队列
net.core.netdev_max_backlog = 1000

EOF
    
    # 应用配置
    log_info "应用网络优化配置..."
    sysctl -p > /dev/null 2>&1
    
    # 验证BBR是否启用
    if sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
        log_info "✓ BBR加速已启用"
    else
        log_warn "BBR启用失败，可能需要重启系统"
    fi
    
    log_info "网络优化配置完成"
}

# 安装3X-UI面板
install_3xui() {
    log_step "步骤4: 安装3X-UI面板"
    
    # 检查是否已安装
    if [ -f /usr/local/x-ui/x-ui ]; then
        log_warn "检测到3X-UI已安装"
        read -p "是否重新安装? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "跳过3X-UI安装"
            return
        fi
        # 停止服务
        systemctl stop x-ui 2>/dev/null || true
    fi
    
    log_info "开始安装3X-UI面板..."
    log_info "安装源: https://raw.githubusercontent.com/MHSanaei/3x-ui/main/install.sh"
    
    # 执行安装
    bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/main/install.sh)
    
    if [ $? -eq 0 ]; then
        log_info "✓ 3X-UI安装成功"
    else
        log_error "3X-UI安装失败"
        exit 1
    fi
    
    # 等待服务启动
    sleep 3
    
    # 检查服务状态
    if systemctl is-active --quiet x-ui; then
        log_info "✓ 3X-UI服务运行正常"
    else
        log_warn "3X-UI服务未运行，尝试启动..."
        systemctl start x-ui
        sleep 2
        if systemctl is-active --quiet x-ui; then
            log_info "✓ 3X-UI服务已启动"
        else
            log_error "3X-UI服务启动失败"
            systemctl status x-ui
            exit 1
        fi
    fi
}

# 配置3X-UI服务
configure_3xui_service() {
    log_step "步骤5: 配置3X-UI服务"
    
    # 检查服务文件是否存在
    if [ ! -f /etc/systemd/system/x-ui.service ]; then
        log_error "3X-UI服务文件不存在"
        exit 1
    fi
    
    # 创建环境配置文件（如果需要）
    if [ ! -f /etc/default/x-ui ]; then
        log_info "创建3X-UI环境配置文件..."
        mkdir -p /etc/default
        cat > /etc/default/x-ui << 'EOF'
# 3X-UI环境配置
XRAY_VMESS_AEAD_FORCED=false
EOF
    fi
    
    # 确保服务文件配置正确
    log_info "检查服务配置..."
    
    # 重新加载systemd
    systemctl daemon-reload
    
    # 启用开机自启
    systemctl enable x-ui
    
    log_info "✓ 3X-UI服务配置完成"
}

# 获取面板访问信息
get_panel_info() {
    log_step "步骤6: 获取面板访问信息"
    
    # 获取服务器IP
    SERVER_IP=$(curl -s ifconfig.me || curl -s ip.sb || curl -s icanhazip.com)
    
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP=$(hostname -I | awk '{print $1}')
    fi
    
    log_info "服务器IP: $SERVER_IP"
    
    # 检查面板端口（默认54321，但可能不同）
    PANEL_PORT=$(ss -tlnp | grep x-ui | grep LISTEN | awk '{print $4}' | cut -d: -f2 | head -1)
    
    if [ -z "$PANEL_PORT" ]; then
        PANEL_PORT="54321"
        log_warn "无法检测面板端口，使用默认端口: $PANEL_PORT"
    else
        log_info "检测到面板端口: $PANEL_PORT"
    fi
    
    echo ""
    echo -e "${GREEN}========================================${PLAIN}"
    echo -e "${GREEN}3X-UI面板访问信息${PLAIN}"
    echo -e "${GREEN}========================================${PLAIN}"
    echo -e "面板地址: ${BLUE}http://${SERVER_IP}:${PANEL_PORT}${PLAIN}"
    echo -e "或: ${BLUE}http://[服务器IP]:${PANEL_PORT}${PLAIN}"
    echo ""
    echo -e "${YELLOW}默认用户名和密码:${PLAIN}"
    echo -e "用户名: ${BLUE}admin${PLAIN}"
    echo -e "密码: ${BLUE}admin${PLAIN}"
    echo ""
    echo -e "${YELLOW}首次登录后请立即修改密码！${PLAIN}"
    echo -e "${GREEN}========================================${PLAIN}"
    echo ""
}

# 验证安装
verify_installation() {
    log_step "步骤7: 验证安装"
    
    # 检查BBR
    log_info "检查BBR状态..."
    if sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
        log_info "✓ BBR: $(sysctl -n net.ipv4.tcp_congestion_control)"
    else
        log_warn "✗ BBR未启用"
    fi
    
    # 检查3X-UI服务
    log_info "检查3X-UI服务状态..."
    if systemctl is-active --quiet x-ui; then
        log_info "✓ 3X-UI服务: 运行中"
    else
        log_error "✗ 3X-UI服务: 未运行"
    fi
    
    # 检查端口监听
    log_info "检查端口监听状态..."
    if ss -tlnp | grep -q x-ui; then
        log_info "✓ 3X-UI端口: 监听中"
        ss -tlnp | grep x-ui | head -3
    else
        log_warn "✗ 未检测到3X-UI端口监听"
    fi
    
    # 检查网络优化参数
    log_info "检查网络优化参数..."
    log_info "TCP Fast Open: $(sysctl -n net.ipv4.tcp_fastopen)"
    log_info "TCP接收缓冲区: $(sysctl -n net.ipv4.tcp_rmem)"
    log_info "TCP发送缓冲区: $(sysctl -n net.ipv4.tcp_wmem)"
}

# 显示后续步骤
show_next_steps() {
    log_step "安装完成！后续步骤"
    
    echo -e "${GREEN}1. 访问3X-UI面板${PLAIN}"
    echo -e "   地址: http://[服务器IP]:[面板端口]"
    echo -e "   默认账号: admin / admin"
    echo ""
    
    echo -e "${GREEN}2. 修改面板密码${PLAIN}"
    echo -e "   登录后立即修改默认密码"
    echo ""
    
    echo -e "${GREEN}3. 配置入站节点${PLAIN}"
    echo -e "   在面板中添加VMESS或其他协议的入站节点"
    echo ""
    
    echo -e "${GREEN}4. 配置出站规则（如需要）${PLAIN}"
    echo -e "   在 Xray 设置 > 出站规则 中添加Socks5等出站"
    echo ""
    
    echo -e "${GREEN}5. 配置路由规则${PLAIN}"
    echo -e "   在 Xray 设置 > 路由规则 中配置流量路由"
    echo ""
    
    echo -e "${GREEN}6. 测试连接${PLAIN}"
    echo -e "   使用客户端连接节点，测试速度和延迟"
    echo ""
    
    echo -e "${YELLOW}重要提示:${PLAIN}"
    echo -e "1. 如果BBR未生效，请重启服务器: ${BLUE}reboot${PLAIN}"
    echo -e "2. 防火墙需要开放面板端口和节点端口"
    echo -e "3. 建议定期更新系统和3X-UI面板"
    echo ""
}

# 主函数
main() {
    clear
    echo -e "${BLUE}"
    echo "=========================================="
    echo "  3X-UI 中转服务器完整部署脚本"
    echo "  基于 199.180.119.149 服务器配置"
    echo "=========================================="
    echo -e "${PLAIN}"
    
    # 执行检查
    check_root
    check_system
    
    # 确认安装
    echo ""
    read -p "是否开始安装? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "安装已取消"
        exit 0
    fi
    
    # 执行安装步骤
    install_dependencies
    configure_bbr
    install_3xui
    configure_3xui_service
    get_panel_info
    verify_installation
    show_next_steps
    
    log_info "部署完成！"
}

# 运行主函数
main "$@"
