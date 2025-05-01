#!/bin/bash
# AntiCheatVM 安装脚本
# 基于教程重新设计，包含必要的虚拟化和显卡直通组件

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 检查是否以root身份运行
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[错误] 此脚本需要以root权限运行${NC}"
    echo "请使用sudo运行此脚本"
    exit 1
fi

# 检测操作系统
detect_os() {
    if [ -f /etc/fedora-release ]; then
        echo "fedora"
    elif [ -f /etc/debian_version ]; then
        if [ -f /etc/lsb-release ]; then
            echo "ubuntu"
        else
            echo "debian"
        fi
    elif [ -f /etc/arch-release ]; then
        echo "arch"
    else
        echo "unknown"
    fi
}

OS_TYPE=$(detect_os)

echo "=================================================="
echo " AntiCheatVM 安装程序 - ${OS_TYPE^} 版本"
echo "=================================================="

# 安装基础依赖
install_dependencies() {
    echo -e "${BLUE}[+] 安装基础依赖...${NC}"
    
    case $OS_TYPE in
        fedora)
            # 安装基础虚拟化包
            dnf groupinstall -y --with-optional virtualization
            
            # 安装图形界面工具
            dnf install -y virt-manager libvirt-daemon-config-network
            
            # 安装NVIDIA驱动所需组件
            dnf install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm 
            dnf install -y https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
            dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda
            
            # 安装Looking Glass所需依赖
            dnf install -y cmake gcc gcc-c++ libglvnd-devel fontconfig-devel spice-protocol make nettle-devel \
                pkgconf-pkg-config binutils-devel libXi-devel libXinerama-devel libXcursor-devel \
                libXpresent-devel libxkbcommon-x11-devel wayland-devel wayland-protocols-devel \
                libXScrnSaver-devel libXrandr-devel dejavu-sans-mono-fonts \
                pipewire-devel libsamplerate-devel pulseaudio-libs-devel
            ;;
            
        ubuntu|debian)
            # 更新软件源
            apt update
            
            # 安装基础虚拟化包
            apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager
            
            # 安装Looking Glass所需依赖
            apt install -y cmake gcc g++ libegl-dev libgl-dev libgles-dev libfontconfig-dev \
                libgmp-dev libspice-protocol-dev make nettle-dev pkg-config binutils-dev \
                libxi-dev libxinerama-dev libxss-dev libxcursor-dev libxpresent-dev \
                libxkbcommon-x11-dev wayland-protocols libpipewire-0.3-dev \
                libsamplerate0-dev libpulse-dev fonts-dejavu-core
            ;;
            
        arch)
            # 安装基础虚拟化包
            pacman -Sy --needed qemu libvirt virt-manager edk2-ovmf dnsmasq
            
            # 安装Looking Glass所需依赖
            pacman -Sy --needed cmake gcc fontconfig nettle spice-protocol make pkgconf \
                libxi libxinerama libxcursor libxss libxpresent libxkbcommon wayland \
                wayland-protocols pipewire libsamplerate ttf-dejavu
            ;;
            
        *)
            echo -e "${RED}[错误] 不支持的操作系统。请手动安装必要的依赖。${NC}"
            exit 1
            ;;
    esac
    
    echo -e "${GREEN}[✓] 基础依赖安装完成${NC}"
}

# 设置用户权限
setup_permissions() {
    echo -e "${BLUE}[+] 设置用户权限...${NC}"
    
    # 添加用户到libvirt和kvm组
    usermod -aG libvirt,kvm $SUDO_USER
    
    # 添加用户到qemu组（如果存在）
    if getent group qemu > /dev/null 2>&1; then
        usermod -aG qemu $SUDO_USER
    fi
    
    echo -e "${GREEN}[✓] 用户权限设置完成${NC}"
}

# 启用并启动libvirt服务
setup_services() {
    echo -e "${BLUE}[+] 设置系统服务...${NC}"
    
    # 启用并启动libvirtd
    systemctl enable libvirtd
    systemctl start libvirtd
    
    echo -e "${GREEN}[✓] 系统服务设置完成${NC}"
}

# 创建目录结构
create_directories() {
    echo -e "${BLUE}[+] 创建项目目录结构...${NC}"
    
    # 创建配置目录
    mkdir -p /home/$SUDO_USER/workspace/AntiCheatVM/{config,vms,iso}
    chown -R $SUDO_USER:$SUDO_USER /home/$SUDO_USER/workspace/AntiCheatVM
    
    echo -e "${GREEN}[✓] 目录结构创建完成${NC}"
}

# 主函数
main() {
    echo -e "${BLUE}[+] 开始安装 AntiCheatVM 环境...${NC}"
    
    install_dependencies
    setup_permissions
    setup_services
    create_directories
    
    echo ""
    echo -e "${GREEN}[✓] AntiCheatVM 安装完成!${NC}"
    echo ""
    echo -e "${YELLOW}[i] 下一步:${NC}"
    echo "1. 运行 setup_vfio.sh 配置VFIO和IOMMU"
    echo "2. 运行 create_vm.py 创建Windows虚拟机"
    echo "3. 运行 looking_glass_setup.sh 配置Looking Glass"
    echo ""
    echo "注意: 你需要重新登录以使组权限生效"
    
    # 提示重启
    read -p "是否立即重启系统以应用所有更改? (y/n): " restart
    if [[ "$restart" == "y" || "$restart" == "Y" ]]; then
        echo -e "${BLUE}[+] 系统将在5秒后重启...${NC}"
        sleep 5
        reboot
    fi
}

# 执行主函数
main