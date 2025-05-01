#!/bin/bash
# AntiCheatVM VFIO设置脚本
# 配置IOMMU和VFIO所需的所有组件

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

# 确保配置目录存在
mkdir -p "$CONFIG_DIR"

echo "=================================================="
echo " AntiCheatVM VFIO 设置工具"
echo "=================================================="

# 检测CPU类型并确定IOMMU参数
detect_cpu_type() {
    echo -e "${BLUE}[+] 检测CPU类型...${NC}"
    
    if grep -q "AuthenticAMD" /proc/cpuinfo; then
        echo -e "${GREEN}[✓] 检测到AMD CPU${NC}"
        echo "amd_iommu=on"
    else
        echo -e "${GREEN}[✓] 检测到Intel CPU${NC}"
        echo "intel_iommu=on"
    fi
}

# 检查IOMMU是否已启用
check_iommu() {
    echo -e "${BLUE}[+] 检查IOMMU状态...${NC}"
    
    if dmesg | grep -i -e DMAR -e IOMMU | grep -i enabled > /dev/null; then
        echo -e "${GREEN}[✓] IOMMU 已启用${NC}"
        return 0
    else
        echo -e "${YELLOW}[!] IOMMU 未启用${NC}"
        return 1
    fi
}

# 列出所有PCI设备
list_pci_devices() {
    echo -e "${BLUE}[+] 扫描PCI设备...${NC}"
    
    # 创建PCI设备文本文件
    lspci -nnv > "$CONFIG_DIR/pci_devices.txt"
    
    echo -e "${GREEN}[✓] PCI设备列表已保存至 $CONFIG_DIR/pci_devices.txt${NC}"
}

# 获取所有GPU和音频设备
get_gpu_devices() {
    echo -e "${BLUE}[+] 查找显卡及相关设备...${NC}"
    
    # 查找所有NVIDIA, AMD, Intel显卡
    echo -e "\n${YELLOW}=== 显卡选择指南 ===${NC}"
    echo -e "您需要选择要直通到虚拟机的显卡。理想情况下，您应该选择："
    echo -e "1. 独立显卡（NVIDIA/AMD）用于直通给虚拟机"
    echo -e "2. 保留集成显卡（Intel/AMD）给宿主Linux系统使用"
    echo -e "${YELLOW}提示: 如果您只有一块显卡，请确保您有其他方式访问系统（如SSH）${NC}\n"
    
    echo -e "${GREEN}可用的显卡设备:${NC}"
    echo -e "${BLUE}-------------------${NC}"
    
    # 使用lspci查找显卡
    gpu_list=$(lspci -nn | grep -E 'VGA|3D|Display|NVIDIA|AMD/ATI|Radeon|GeForce')
    
    # 显示GPU列表，添加更多描述信息
    gpu_count=0
    while IFS= read -r line; do
        gpu_count=$((gpu_count + 1))
        
        # 提取显卡类型信息，帮助用户辨识
        card_type=""
        if echo "$line" | grep -q "NVIDIA"; then
            if echo "$line" | grep -q "GeForce"; then
                card_type="NVIDIA 独立显卡"
            else
                card_type="NVIDIA 显卡"
            fi
        elif echo "$line" | grep -q -E "AMD|ATI|Radeon"; then
            if echo "$line" | grep -q -i "integrated"; then
                card_type="AMD 集成显卡"
            else
                card_type="AMD 独立显卡"
            fi
        elif echo "$line" | grep -q "Intel"; then
            card_type="Intel 集成显卡"
        else
            card_type="其他显卡"
        fi
        
        echo -e "[$gpu_count] ${YELLOW}$card_type${NC}: $line"
    done <<< "$gpu_list"
    
    # 如果没有发现任何GPU设备
    if [ "$gpu_count" -eq 0 ]; then
        echo -e "${RED}[错误] 未找到任何显卡设备${NC}"
        exit 1
    fi
    
    # 让用户选择要直通的GPU
    echo ""
    if [ "$gpu_count" -eq 1 ]; then
        echo -e "${YELLOW}[警告] 只检测到一个显卡设备。如果您将此显卡直通到虚拟机，宿主机将无法显示图形界面。${NC}"
        echo -e "${YELLOW}[警告] 确保您有其他方式（如SSH）访问系统，否则不建议继续。${NC}"
    elif [ "$gpu_count" -gt 1 ]; then
        echo -e "${GREEN}[提示] 检测到多个显卡设备。通常建议：${NC}"
        echo -e "   - 将独立显卡（NVIDIA/AMD）用于虚拟机"
        echo -e "   - 保留集成显卡（Intel/AMD）给宿主机使用"
    fi
    
    read -p "请输入要用于直通的显卡编号 [1-$gpu_count]: " selected_gpu
    
    if [[ ! "$selected_gpu" =~ ^[0-9]+$ ]] || [ "$selected_gpu" -lt 1 ] || [ "$selected_gpu" -gt "$gpu_count" ]; then
        echo -e "${RED}[错误] 无效的选择：$selected_gpu${NC}"
        echo -e "${RED}[错误] 请输入1到$gpu_count之间的数字${NC}"
        exit 1
    fi
    
    # 获取选择的GPU的PCI信息
    selected_gpu_line=$(sed -n "${selected_gpu}p" <<< "$gpu_list")
    gpu_pci_id=$(echo "$selected_gpu_line" | grep -o -E '[0-9a-f]{4}:[0-9a-f]{4}' | head -1)
    gpu_pci_addr=$(echo "$selected_gpu_line" | awk '{print $1}')
    
    # 提取厂商和设备名称以便更友好的显示
    vendor_id=${gpu_pci_id%%:*}
    device_id=${gpu_pci_id##*:}
    
    vendor_name=""
    case "$vendor_id" in
        10de) vendor_name="NVIDIA" ;;
        1002) vendor_name="AMD" ;;
        8086) vendor_name="Intel" ;;
        *) vendor_name="未知厂商" ;;
    esac
    
    echo -e "${GREEN}[✓] 已选择GPU: ${YELLOW}$vendor_name${NC} 设备 (PCI地址: $gpu_pci_addr)${NC}"
    echo -e "${GREEN}[✓] PCI设备ID: $gpu_pci_id${NC}"
    
    # 查找相关的音频设备
    echo -e "${BLUE}[+] 查找相关的音频设备...${NC}"
    
    gpu_domain_bus=$(echo "$gpu_pci_addr" | cut -d: -f1)
    audio_device=$(lspci -nn | grep "$gpu_domain_bus" | grep -i "Audio device")
    
    if [ -n "$audio_device" ]; then
        audio_pci_id=$(echo "$audio_device" | grep -o -E '[0-9a-f]{4}:[0-9a-f]{4}' | head -1)
        echo -e "${GREEN}[✓] 找到相关音频设备: $audio_device${NC}"
        echo -e "${GREEN}[✓] 音频设备ID: $audio_pci_id${NC}"
        echo -e "${GREEN}[i] 此音频设备将自动与GPU一起直通${NC}"
    else
        echo -e "${YELLOW}[!] 未找到相关音频设备${NC}"
        audio_pci_id=""
    fi
    
    # 将设备ID保存到配置文件
    echo -e "${BLUE}[+] 保存VFIO设备配置...${NC}"
    
    # 创建YAML格式的配置文件
    echo "devices:" > "$CONFIG_DIR/vfio_devices.yaml"
    echo "  - \"${gpu_pci_id//:}\"" >> "$CONFIG_DIR/vfio_devices.yaml"
    
    if [ -n "$audio_pci_id" ]; then
        echo "  - \"${audio_pci_id//:}\"" >> "$CONFIG_DIR/vfio_devices.yaml"
    fi
    
    echo -e "${GREEN}[✓] VFIO设备配置已保存至 $CONFIG_DIR/vfio_devices.yaml${NC}"
    
    # 返回设备ID列表，用逗号分隔
    if [ -n "$audio_pci_id" ]; then
        echo "${gpu_pci_id//:},${audio_pci_id//:}"
    else
        echo "${gpu_pci_id//:}"
    fi
}

# 配置GRUB以启用IOMMU和VFIO
configure_grub() {
    local iommu_param=$1
    local device_ids=$2
    
    echo -e "${BLUE}[+] 配置GRUB启动参数...${NC}"
    
    # 备份GRUB配置
    if [ ! -f /etc/default/grub.backup ]; then
        cp /etc/default/grub /etc/default/grub.backup
        echo -e "${GREEN}[✓] GRUB配置已备份${NC}"
    fi
    
    # 读取当前GRUB配置
    local grub_cmdline=$(grep GRUB_CMDLINE_LINUX /etc/default/grub | cut -d'"' -f2)
    
    # 添加IOMMU和VFIO参数
    local new_params="$iommu_param iommu=pt rd.driver.pre=vfio-pci rd.driver.blacklist=nouveau modprobe.blacklist=nouveau nvidia-drm.modeset=1 vfio-pci.ids=$device_ids module_blacklist=nouveau"
    
    # 创建新的命令行参数，简单地清除旧的关键字并添加新参数
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
    
    # 组合新的GRUB命令行
    local new_cmdline="$clean_cmdline $new_params"
    new_cmdline=$(echo "$new_cmdline" | sed -e 's/^ *//' -e 's/ *$//')
    
    # 更新GRUB配置，使用不同的分隔符避免路径问题
    sed -i "s|GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$new_cmdline\"|" /etc/default/grub
    
    echo -e "${GREEN}[✓] GRUB配置已更新${NC}"
    
    # 更新GRUB
    echo -e "${BLUE}[+] 更新GRUB引导...${NC}"
    if [ -f /boot/grub2/grub.cfg ]; then
        grub2-mkconfig -o /boot/grub2/grub.cfg
    elif [ -f /boot/grub/grub.cfg ]; then
        grub-mkconfig -o /boot/grub/grub.cfg
    else
        echo -e "${RED}[错误] 找不到GRUB配置文件${NC}"
        return 1
    fi
    
    echo -e "${GREEN}[✓] GRUB已更新${NC}"
}

# 配置dracut以包含VFIO模块
configure_dracut() {
    echo -e "${BLUE}[+] 配置dracut以包含VFIO模块...${NC}"
    
    # 创建dracut配置 - 移除可能不存在的vfio_virqfd模块
    echo 'add_drivers+=" vfio vfio_iommu_type1 vfio_pci "' > /etc/dracut.conf.d/local.conf
    
    # 重建initramfs
    echo -e "${BLUE}[+] 重建initramfs...${NC}"
    dracut -f --kver $(uname -r)
    
    echo -e "${GREEN}[✓] dracut配置已完成${NC}"
}

# 创建GPU启用/禁用脚本
create_gpu_toggle_scripts() {
    local gpu_addr=$1
    
    echo -e "${BLUE}[+] 创建GPU切换脚本...${NC}"
    
    # 创建GPU管理脚本
    cat > "$SCRIPT_DIR/switch_gpu.sh" << EOF
#!/bin/bash
# GPU切换脚本：在宿主机使用和VM直通之间切换

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 检查是否以root身份运行
if [ "\$(id -u)" -ne 0 ]; then
    echo -e "\${RED}[错误] 此脚本需要以root权限运行\${NC}"
    echo "请使用sudo运行此脚本"
    exit 1
fi

# 显示当前状态
show_status() {
    echo -e "\${BLUE}[+] 检查GPU状态...\${NC}"
    
    if lspci -nnk | grep -A 2 "$gpu_addr" | grep -q "Kernel driver in use: vfio-pci"; then
        echo -e "\${YELLOW}[!] GPU当前由VFIO-PCI驱动控制（适用于VM）\${NC}"
        return 0  # 0 = VFIO模式
    elif lspci -nnk | grep -A 2 "$gpu_addr" | grep -q "Kernel driver in use: nvidia"; then
        echo -e "\${GREEN}[✓] GPU当前由NVIDIA驱动控制（适用于宿主机）\${NC}"
        return 1  # 1 = NVIDIA模式
    else
        echo -e "\${RED}[错误] 无法确定当前GPU状态\${NC}"
        exit 1
    fi
}

# 启用NVIDIA驱动（宿主机使用）
enable_nvidia() {
    echo -e "\${BLUE}[+] 启用NVIDIA驱动...\${NC}"
    
    echo -e "\${BLUE}[1/3] 将GPU重新附加到主机...\${NC}"
    virsh nodedev-reattach pci_0000_${gpu_addr//:/_} || return 1
    echo -e "\${GREEN}[✓] GPU已重新附加\${NC}"
    
    echo -e "\${BLUE}[2/3] 移除VFIO驱动...\${NC}"
    rmmod vfio_pci vfio_pci_core vfio_iommu_type1 || true
    echo -e "\${GREEN}[✓] VFIO驱动已移除\${NC}"
    
    echo -e "\${BLUE}[3/3] 加载NVIDIA驱动...\${NC}"
    modprobe -i nvidia_modeset nvidia_uvm nvidia || return 1
    echo -e "\${GREEN}[✓] NVIDIA驱动已加载\${NC}"
    
    echo -e "\${GREEN}[✓] GPU已切换到宿主机模式\${NC}"
    return 0
}

# 启用VFIO驱动（VM使用）
enable_vfio() {
    echo -e "\${BLUE}[+] 启用VFIO驱动...\${NC}"
    
    echo -e "\${BLUE}[1/3] 移除NVIDIA驱动...\${NC}"
    rmmod nvidia_modeset nvidia_uvm nvidia || true
    echo -e "\${GREEN}[✓] NVIDIA驱动已移除\${NC}"
    
    echo -e "\${BLUE}[2/3] 加载VFIO驱动...\${NC}"
    modprobe -i vfio_pci vfio_pci_core vfio_iommu_type1 || return 1
    echo -e "\${GREEN}[✓] VFIO驱动已加载\${NC}"
    
    echo -e "\${BLUE}[3/3] 将GPU分离到VFIO...\${NC}"
    virsh nodedev-detach pci_0000_${gpu_addr//:/_} || return 1
    echo -e "\${GREEN}[✓] GPU已分离\${NC}"
    
    echo -e "\${GREEN}[✓] GPU已切换到VM直通模式\${NC}"
    return 0
}

# 主逻辑
if [ "\$1" == "nvidia" ] || [ "\$1" == "host" ]; then
    enable_nvidia
elif [ "\$1" == "vfio" ] || [ "\$1" == "vm" ]; then
    enable_vfio
elif [ "\$1" == "status" ]; then
    show_status
    exit \$?
else
    # 自动切换模式
    show_status
    current_mode=\$?
    
    if [ \$current_mode -eq 0 ]; then
        # 当前为VFIO模式，切换到NVIDIA
        enable_nvidia
    else
        # 当前为NVIDIA模式，切换到VFIO
        enable_vfio
    fi
fi

# 显示最终状态
show_status
EOF

    # 设置执行权限
    chmod +x "$SCRIPT_DIR/switch_gpu.sh"
    
    # 创建GPU管理脚本
    cat > "$SCRIPT_DIR/gpu-manager.sh" << EOF
#!/bin/bash
# GPU管理器 - 为使用AntiCheatVM的用户提供友好的GPU管理界面

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"

# 显示GPU状态
show_status() {
    echo -e "\${BLUE}[i] 当前状态:\${NC}"
    sudo "\$SCRIPT_DIR/switch_gpu.sh" status
    echo ""
}

# 主菜单
show_menu() {
    clear
    echo "=================================================="
    echo "          AntiCheatVM - GPU管理器"
    echo "=================================================="
    show_status
    echo "请选择操作:"
    echo "1) 切换GPU到宿主机模式 (使用NVIDIA驱动)"
    echo "2) 切换GPU到VM直通模式 (使用VFIO驱动)"
    echo "3) 退出"
    echo ""
    read -p "请输入选项 [1-3]: " choice
    
    case \$choice in
        1)
            echo -e "\${BLUE}[+] 切换GPU到宿主机模式...\${NC}"
            sudo "\$SCRIPT_DIR/switch_gpu.sh" nvidia
            read -p "按回车键继续..." dummy
            show_menu
            ;;
        2)
            echo -e "\${BLUE}[+] 切换GPU到VM直通模式...\${NC}"
            sudo "\$SCRIPT_DIR/switch_gpu.sh" vfio
            read -p "按回车键继续..." dummy
            show_menu
            ;;
        3)
            echo -e "\${GREEN}[i] 退出程序\${NC}"
            exit 0
            ;;
        *)
            echo -e "\${RED}[错误] 无效的选项\${NC}"
            read -p "按回车键继续..." dummy
            show_menu
            ;;
    esac
}

# 启动主菜单
show_menu
EOF

    # 设置执行权限
    chmod +x "$SCRIPT_DIR/gpu-manager.sh"
    
    # 创建别名文件
    cat > "$SCRIPT_DIR/aliases.sh" << EOF
# AntiCheatVM 别名和函数
# 将此文件添加到你的~/.bashrc: source /path/to/aliases.sh

# GPU状态查看
alias hows-my-gpu='echo "NVIDIA Dedicated Graphics" | grep "NVIDIA" && lspci -nnk | grep "$gpu_addr" -A 2 | grep "Kernel driver in use" && echo "Enable and disable the dedicated NVIDIA GPU with nvidia-enable and nvidia-disable"'

# GPU切换别名
alias nvidia-enable='sudo $SCRIPT_DIR/switch_gpu.sh nvidia'
alias nvidia-disable='sudo $SCRIPT_DIR/switch_gpu.sh vfio'

# Looking Glass简化命令
alias looking-glass='looking-glass-client -s -m 97'
EOF

    echo -e "${GREEN}[✓] GPU切换脚本已创建${NC}"
    echo -e "${YELLOW}[i] 请将aliases.sh添加到您的~/.bashrc文件以启用便捷命令${NC}"
    echo "    echo 'source $SCRIPT_DIR/aliases.sh' >> ~/.bashrc"
}

# 主函数
main() {
    # 列出所有PCI设备
    list_pci_devices
    
    # 检测CPU类型并确定IOMMU参数
    iommu_param=$(detect_cpu_type)
    
    # 检查IOMMU状态
    check_iommu
    
    # 获取GPU设备ID
    device_ids=$(get_gpu_devices)
    
    # 配置GRUB
    configure_grub "$iommu_param" "$device_ids"
    
    # 配置dracut
    configure_dracut
    
    # 获取GPU地址 - 使用更简单的方法
    echo -e "${BLUE}[+] 获取GPU地址...${NC}"
    
    # 直接从 lspci 输出中获取
    gpu_id_part=$(echo $device_ids | cut -d',' -f1)
    gpu_id_formatted=$(echo $gpu_id_part | sed 's/\(..\)\(..\)/\1:\2/')
    gpu_addr=""
    
    # 使用 lspci 安全地查找
    while read -r line; do
        if echo "$line" | grep -q "$gpu_id_formatted"; then
            gpu_addr=$(echo "$line" | awk '{print $1}')
            break
        fi
    done < <(lspci -nn)
    
    # 如果找不到，使用默认值
    if [ -z "$gpu_addr" ]; then
        echo -e "${YELLOW}[!] 无法获取GPU地址，尝试其他方法...${NC}"
        
        # 尝试从配置文件读取
        selected_gpu=$(cat $CONFIG_DIR/vfio_devices.yaml | grep -m 1 "\"" | tr -d ' "' | tr -d '-')
        
        while read -r line; do
            if echo "$line" | grep -q "$gpu_id_formatted"; then
                gpu_addr=$(echo "$line" | awk '{print $1}')
                break
            fi
        done < <(lspci -nn)
        
        if [ -z "$gpu_addr" ]; then
            echo -e "${YELLOW}[!] 尝试从选择编号直接获取...${NC}"
            
            # 假设用户选择了正确的GPU（通常为独立显卡）
            gpu_info=$(lspci -nn | grep -i "NVIDIA" | grep -i "VGA" | head -1)
            
            if [ -n "$gpu_info" ]; then
                gpu_addr=$(echo "$gpu_info" | awk '{print $1}')
            else
                echo -e "${RED}[错误] 无法自动获取GPU地址${NC}"
                echo -e "${YELLOW}[!] 请手动输入GPU地址（例如：01:00.0）${NC}"
                read -p "GPU地址: " gpu_addr
                
                if [ -z "$gpu_addr" ]; then
                    gpu_addr="01:00.0"  # 默认值
                fi
            fi
        fi
    fi
    
    echo -e "${GREEN}[✓] 使用GPU地址: $gpu_addr${NC}"
    
    # 创建GPU切换脚本
    create_gpu_toggle_scripts "$gpu_addr"
    
    echo ""
    echo -e "${GREEN}[✓] VFIO配置已完成!${NC}"
    echo ""
    echo -e "${YELLOW}[i] 下一步:${NC}"
    echo "1. 重启系统使IOMMU和VFIO设置生效"
    echo "2. 重启后，运行 '$SCRIPT_DIR/gpu-manager.sh' 管理GPU驱动"
    echo "3. 然后使用 create_vm.py 创建Windows虚拟机"
    
    # 询问是否立即重启
    read -p "是否立即重启系统 (推荐)? (y/n): " restart
    if [[ "$restart" == "y" || "$restart" == "Y" ]]; then
        echo -e "${BLUE}[+] 系统将在5秒后重启...${NC}"
        sleep 5
        reboot
    fi
}

# 执行主函数
main