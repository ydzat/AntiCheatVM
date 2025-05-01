#!/bin/bash
# AntiCheatVM 清理脚本
# 用于恢复系统到初始状态并清理由 AntiCheatVM 创建的文件和配置

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

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
VM_DIR="$SCRIPT_DIR/vms"
DOWNLOADS_DIR="$HOME/Downloads/AntiCheatVM"  # 可能的下载目录
BUILD_DIR="/tmp/AntiCheatVM_build"  # 可能的构建目录

echo "=================================================="
echo " AntiCheatVM 清理工具"
echo "=================================================="
echo -e "${YELLOW}警告: 此脚本将撤销 AntiCheatVM 所做的所有更改${NC}"
echo -e "${YELLOW}包括恢复 GRUB 配置、移除 VFIO 绑定和清理创建的文件${NC}"
echo -e "${YELLOW}还将清理下载的库、项目源码和构建文件${NC}"
echo -e "${YELLOW}但不会删除您已创建的虚拟机，需要手动处理${NC}"
echo -e "${RED}确保您的虚拟机已关闭！${NC}"
echo ""

# 确认操作
read -p "是否确定要继续? (y/n): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}[i] 操作已取消${NC}"
    exit 0
fi

# 重新绑定 GPU 到 NVIDIA 驱动
rebind_gpu_to_nvidia() {
    echo -e "${BLUE}[+] 尝试将 GPU 绑定回 NVIDIA 驱动...${NC}"
    
    # 检查 switch_gpu.sh 是否存在
    if [ -f "$SCRIPT_DIR/switch_gpu.sh" ]; then
        echo -e "${BLUE}[+] 使用现有脚本切换 GPU...${NC}"
        bash "$SCRIPT_DIR/switch_gpu.sh" nvidia
    else
        # 获取可能的 GPU 地址
        gpu_addr=""
        
        # 尝试从 lspci 获取 NVIDIA GPU 地址
        echo -e "${BLUE}[+] 查找 NVIDIA GPU...${NC}"
        gpu_info=$(lspci -nn | grep -i "NVIDIA" | grep -i "VGA" | head -1)
        
        if [ -n "$gpu_info" ]; then
            gpu_addr=$(echo "$gpu_info" | awk '{print $1}')
            echo -e "${GREEN}[✓] 找到 GPU 地址: $gpu_addr${NC}"
            
            # 手动尝试切换
            echo -e "${BLUE}[+] 尝试切换 GPU 到 NVIDIA 驱动...${NC}"
            
            # 确保 NVIDIA 模块可用
            modprobe -r vfio_pci vfio_pci_core vfio_iommu_type1 || true
            modprobe -i nvidia_modeset nvidia_uvm nvidia || true
            
            # 尝试重新附加设备
            if command -v virsh &> /dev/null; then
                # 将PCI地址转换为libvirt格式
                formatted_addr=$(echo "$gpu_addr" | sed 's/[:.]/_/g')
                libvirt_dev="pci_0000_${formatted_addr}"
                echo -e "${YELLOW}[!] 使用设备名称: $libvirt_dev${NC}"
                virsh nodedev-reattach "$libvirt_dev" || true
            fi
            
            echo -e "${GREEN}[✓] GPU 驱动切换完成${NC}"
        else
            echo -e "${YELLOW}[!] 未找到 NVIDIA GPU${NC}"
        fi
    fi
    
    return 0
}

# 恢复 GRUB 配置
restore_grub() {
    echo -e "${BLUE}[+] 恢复 GRUB 配置...${NC}"
    
    if [ -f /etc/default/grub.backup ]; then
        cp /etc/default/grub.backup /etc/default/grub
        echo -e "${GREEN}[✓] GRUB 配置已从备份恢复${NC}"
    else
        echo -e "${YELLOW}[!] 未找到 GRUB 备份文件${NC}"
        
        # 显示当前 GRUB 配置
        echo -e "${BLUE}[+] 当前 GRUB 配置:${NC}"
        cat /etc/default/grub
        echo ""
        
        # 尝试清除 VFIO 相关参数
        echo -e "${BLUE}[+] 尝试清除 GRUB 中的 VFIO 参数...${NC}"
        
        # 读取当前 GRUB 配置
        local grub_cmdline=$(grep GRUB_CMDLINE_LINUX /etc/default/grub | cut -d'"' -f2)
        
        # 清除 VFIO 相关参数（更全面的清理）
        local clean_cmdline=$(echo "$grub_cmdline" | \
            sed -e 's/intel_iommu=[^ ]*//g' \
            -e 's/amd_iommu=[^ ]*//g' \
            -e 's/iommu=[^ ]*//g' \
            -e 's/rd\.driver\.pre=[^ ]*//g' \
            -e 's/rd\.driver\.blacklist=[^ ]*//g' \
            -e 's/modprobe\.blacklist=[^ ]*//g' \
            -e 's/nvidia-drm\.modeset=[^ ]*//g' \
            -e 's/vfio-pci\.ids=[^ ]*//g' \
            -e 's/module_blacklist=[^ ]*//g' \
            -e 's/  / /g' -e 's/^ *//' -e 's/ *$//')
        
        echo -e "${BLUE}[+] 更新后的 GRUB 命令行: ${clean_cmdline}${NC}"
        
        # 更新 GRUB 配置
        sed -i "s|GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$clean_cmdline\"|" /etc/default/grub
        
        echo -e "${GREEN}[✓] GRUB 参数已清除${NC}"
    fi
    
    # 更新 GRUB
    echo -e "${BLUE}[+] 更新 GRUB 引导...${NC}"
    if [ -f /boot/grub2/grub.cfg ]; then
        grub2-mkconfig -o /boot/grub2/grub.cfg
    elif [ -f /boot/grub/grub.cfg ]; then
        grub-mkconfig -o /boot/grub/grub.cfg
    else
        echo -e "${RED}[错误] 找不到 GRUB 配置文件${NC}"
        return 1
    fi
    
    echo -e "${GREEN}[✓] GRUB 已更新${NC}"
    return 0
}

# 清除 dracut 配置
cleanup_dracut() {
    echo -e "${BLUE}[+] 清除 dracut VFIO 配置...${NC}"
    
    if [ -f /etc/dracut.conf.d/local.conf ]; then
        # 检查是否包含 VFIO 配置
        if grep -q "vfio" /etc/dracut.conf.d/local.conf; then
            # 备份并删除文件
            cp /etc/dracut.conf.d/local.conf /etc/dracut.conf.d/local.conf.backup
            rm /etc/dracut.conf.d/local.conf
            echo -e "${GREEN}[✓] VFIO dracut 配置已移除${NC}"
            
            # 重建 initramfs
            echo -e "${BLUE}[+] 重建 initramfs...${NC}"
            dracut -f --kver $(uname -r)
            echo -e "${GREEN}[✓] initramfs 已更新${NC}"
        else
            echo -e "${YELLOW}[!] dracut 配置文件不包含 VFIO 设置${NC}"
        fi
    else
        echo -e "${YELLOW}[!] 未找到 dracut 配置文件${NC}"
    fi
    
    return 0
}

# 删除开机自启动的VFIO模块
remove_vfio_autoload() {
    echo -e "${BLUE}[+] 删除 VFIO 模块自动加载...${NC}"
    
    # 检查并移除可能的自动加载配置
    if [ -f /etc/modules-load.d/vfio.conf ]; then
        rm /etc/modules-load.d/vfio.conf
        echo -e "${GREEN}[✓] 已删除 VFIO 模块自动加载配置${NC}"
    fi
    
    # 检查 /etc/modprobe.d/ 目录中的 VFIO 配置
    for file in /etc/modprobe.d/*vfio*; do
        if [ -f "$file" ];then
            echo -e "${YELLOW}[!] 发现 VFIO 模块配置文件: $file${NC}"
            mv "$file" "${file}.bak"
            echo -e "${GREEN}[✓] 已备份并移除 VFIO 模块配置文件${NC}"
        fi
    done
    
    # 创建开机自动加载NVIDIA驱动的配置
    echo -e "${BLUE}[+] 创建 NVIDIA 驱动自动加载配置...${NC}"
    cat > /etc/modules-load.d/nvidia.conf << EOF
# 自动加载 NVIDIA 驱动
nvidia
nvidia_modeset
nvidia_uvm
EOF
    echo -e "${GREEN}[✓] 已创建 NVIDIA 驱动自动加载配置${NC}"
    
    return 0
}

# 创建开机启动服务，确保系统启动时使用主机模式
create_host_mode_service() {
    echo -e "${BLUE}[+] 创建开机使用主机模式的服务...${NC}"
    
    # 创建服务文件
    cat > /etc/systemd/system/gpu-host-mode.service << EOF
[Unit]
Description=Set GPU to host mode on system startup
After=display-manager.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'modprobe nvidia && modprobe nvidia_modeset && modprobe nvidia_uvm'
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

    # 启用服务
    systemctl daemon-reload
    systemctl enable gpu-host-mode.service
    
    echo -e "${GREEN}[✓] 已创建并启用开机使用主机模式的服务${NC}"
    return 0
}

# 清除系统内存设置
cleanup_memory_settings() {
    echo -e "${BLUE}[+] 清除系统内存设置...${NC}"
    
    # 重置大页内存
    echo 0 > /proc/sys/vm/nr_hugepages
    
    # 清理内存锁定限制
    if [ -f /etc/systemd/system/user-$(id -u).slice.d/90-memlock.conf ]; then
        rm /etc/systemd/system/user-$(id -u).slice.d/90-memlock.conf
        rmdir /etc/systemd/system/user-$(id -u).slice.d/ 2>/dev/null || true
        systemctl daemon-reload
        echo -e "${GREEN}[✓] 内存锁定限制已重置${NC}"
    fi
    
    # 清理 Looking Glass 共享内存
    if [ -e /dev/shm/looking-glass ]; then
        rm /dev/shm/looking-glass
        echo -e "${GREEN}[✓] Looking Glass 共享内存已清理${NC}"
    fi
    
    return 0
}

# 清理下载的库和项目
cleanup_downloaded_projects() {
    echo -e "${BLUE}[+] 清理下载的库和项目...${NC}"
    
    # 清理 Looking Glass 相关文件
    echo -e "${BLUE}[+] 查找 Looking Glass 相关文件...${NC}"
    
    # 可能的 Looking Glass 源码目录
    LG_DIRS=$(find $HOME -maxdepth 3 -type d -name "LookingGlass*" -o -name "looking-glass*" 2>/dev/null)
    
    if [ -n "$LG_DIRS" ]; then
        echo -e "${YELLOW}[!] 找到 Looking Glass 相关目录:${NC}"
        echo "$LG_DIRS"
        
        read -p "是否删除这些目录? (y/n): " remove_lg
        if [[ "$remove_lg" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}[+] 删除 Looking Glass 目录...${NC}"
            echo "$LG_DIRS" | while read dir; do
                rm -rf "$dir"
                echo -e "${GREEN}[✓] 已删除: $dir${NC}"
            done
        else
            echo -e "${BLUE}[i] 保留 Looking Glass 目录${NC}"
        fi
    else
        echo -e "${BLUE}[i] 未找到 Looking Glass 源码目录${NC}"
    fi
    
    # 清理可能的下载目录
    if [ -d "$DOWNLOADS_DIR" ]; then
        echo -e "${YELLOW}[!] 找到下载目录: $DOWNLOADS_DIR${NC}"
        read -p "是否删除此目录? (y/n): " remove_downloads
        if [[ "$remove_downloads" =~ ^[Yy]$ ]]; then
            rm -rf "$DOWNLOADS_DIR"
            echo -e "${GREEN}[✓] 已删除下载目录${NC}"
        fi
    fi
    
    # 清理临时构建目录
    if [ -d "$BUILD_DIR" ]; then
        echo -e "${YELLOW}[!] 找到构建目录: $BUILD_DIR${NC}"
        rm -rf "$BUILD_DIR"
        echo -e "${GREEN}[✓] 已删除构建目录${NC}"
    fi
    
    # 清理 Looking Glass 客户端二进制文件
    if command -v looking-glass-client &> /dev/null; then
        echo -e "${YELLOW}[!] 找到 Looking Glass 客户端安装${NC}"
        read -p "是否卸载 Looking Glass 客户端? (y/n): " remove_lgclient
        if [[ "$remove_lgclient" =~ ^[Yy]$ ]]; then
            # 尝试找到可能的安装位置
            LG_BIN=$(which looking-glass-client)
            if [ -n "$LG_BIN" ]; then
                LG_DIR=$(dirname "$LG_BIN")
                if [ "$LG_DIR" = "/usr/local/bin" ]; then
                    rm -f /usr/local/bin/looking-glass-client
                    echo -e "${GREEN}[✓] 已删除 Looking Glass 客户端${NC}"
                else
                    echo -e "${YELLOW}[!] Looking Glass 客户端位于非标准位置: $LG_BIN${NC}"
                    rm -f "$LG_BIN"
                    echo -e "${GREEN}[✓] 已删除 Looking Glass 客户端${NC}"
                fi
            fi
        fi
    fi
    
    # 清理 SPICE guest 工具
    echo -e "${BLUE}[+] 查询已安装的 SPICE/Virtio 相关包...${NC}"
    
    # 检测包管理器
    if command -v apt &> /dev/null; then
        # Debian/Ubuntu
        SPICE_PKGS=$(dpkg -l | grep -i -e spice -e virtio | awk '{print $2}')
        if [ -n "$SPICE_PKGS" ]; then
            echo -e "${YELLOW}[!] 找到 SPICE/Virtio 相关包:${NC}"
            echo "$SPICE_PKGS"
            read -p "是否卸载这些包? (y/n): " remove_spice
            if [[ "$remove_spice" =~ ^[Yy]$ ]]; then
                echo "$SPICE_PKGS" | xargs apt purge -y
                echo -e "${GREEN}[✓] 已卸载 SPICE/Virtio 相关包${NC}"
            fi
        fi
    elif command -v dnf &> /dev/null; then
        # Fedora/RHEL/CentOS
        SPICE_PKGS=$(rpm -qa | grep -i -e spice -e virtio)
        if [ -n "$SPICE_PKGS" ]; then
            echo -e "${YELLOW}[!] 找到 SPICE/Virtio 相关包:${NC}"
            echo "$SPICE_PKGS"
            read -p "是否卸载这些包? (y/n): " remove_spice
            if [[ "$remove_spice" =~ ^[Yy]$ ]]; then
                echo "$SPICE_PKGS" | xargs dnf remove -y
                echo -e "${GREEN}[✓] 已卸载 SPICE/Virtio 相关包${NC}"
            fi
        fi
    elif command -v pacman &> /dev/null; then
        # Arch Linux
        SPICE_PKGS=$(pacman -Q | grep -i -e spice -e virtio | awk '{print $1}')
        if [ -n "$SPICE_PKGS" ]; then
            echo -e "${YELLOW}[!] 找到 SPICE/Virtio 相关包:${NC}"
            echo "$SPICE_PKGS"
            read -p "是否卸载这些包? (y/n): " remove_spice
            if [[ "$remove_spice" =~ ^[Yy]$ ]]; then
                echo "$SPICE_PKGS" | xargs pacman -Rns --noconfirm
                echo -e "${GREEN}[✓] 已卸载 SPICE/Virtio 相关包${NC}"
            fi
        fi
    fi
    
    # 清理虚拟机镜像文件
    echo -e "${BLUE}[+] 查找虚拟机镜像和ISO文件...${NC}"
    
    # 查找用户目录下的qcow2和raw文件
    VM_IMAGES=$(find $HOME -type f \( -name "*.qcow2" -o -name "*.raw" \) -size +500M 2>/dev/null)
    if [ -n "$VM_IMAGES" ]; then
        echo -e "${YELLOW}[!] 找到以下虚拟机镜像文件:${NC}"
        ls -lh $(echo "$VM_IMAGES")
        echo -e "${YELLOW}[!] 警告: 这些文件可能包含重要数据，请确认哪些是您需要保留的${NC}"
        echo -e "${YELLOW}[!] 本脚本不会自动删除这些文件，如需删除请手动执行${NC}"
    fi
    
    # 查找ISO文件
    ISO_FILES=$(find $HOME -type f -name "*.iso" -size +100M 2>/dev/null | grep -v "/iso/")
    if [ -n "$ISO_FILES" ]; then
        echo -e "${YELLOW}[!] 找到以下ISO文件:${NC}"
        ls -lh $(echo "$ISO_FILES")
        echo -e "${YELLOW}[!] 这些文件可能是安装介质，如不再需要可以手动删除${NC}"
    fi
    
    return 0
}

# 列出虚拟机但不删除
list_vms() {
    echo -e "${BLUE}[+] 以下虚拟机由 AntiCheatVM 创建:${NC}"
    
    if command -v virsh &> /dev/null; then
        virsh list --all | grep -i "AntiCheatVM"
        echo ""
        echo -e "${YELLOW}[!] 如果要删除这些虚拟机，请手动执行:${NC}"
        echo -e "    virsh undefine [虚拟机名称] --remove-all-storage"
    else
        echo -e "${YELLOW}[!] virsh 命令不可用，无法列出虚拟机${NC}"
    fi
    
    return 0
}

# 主函数
main() {
    echo -e "${BLUE}[+] 开始清理 AntiCheatVM 配置...${NC}"
    
    # 重新绑定 GPU 到 NVIDIA 驱动（放在最前面以确保操作时GPU可用）
    rebind_gpu_to_nvidia
    
    # 恢复 GRUB 配置
    restore_grub
    
    # 清除 dracut 配置
    cleanup_dracut
    
    # 删除 VFIO 自动加载并配置 NVIDIA 自动加载
    remove_vfio_autoload
    
    # 创建开机使用主机模式的服务
    create_host_mode_service
    
    # 清除内存设置
    cleanup_memory_settings
    
    # 清理下载的库和项目
    cleanup_downloaded_projects
    
    # 列出虚拟机
    list_vms
    
    echo ""
    echo -e "${GREEN}[✓] AntiCheatVM 清理完成!${NC}"
    echo -e "${GREEN}[✓] 系统已配置为在启动时默认使用主机模式${NC}"
    echo -e "${YELLOW}[!] 强烈建议重启系统以应用所有更改${NC}"
    
    # 询问是否立即重启
    read -p "是否立即重启系统? (y/n): " restart
    if [[ "$restart" == "y" || "$restart" == "Y" ]]; then
        echo -e "${BLUE}[+] 系统将在5秒后重启...${NC}"
        sleep 5
        reboot
    fi
}

# 执行主函数
main