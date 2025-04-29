#!/bin/bash
###
 # @Author: @ydzat
 # @Date: 2025-04-29 20:01:15
 # @LastEditors: @ydzat
 # @LastEditTime: 2025-04-29 20:01:15
 # @Description: 配置 VFIO/IOMMU 环境，编译并绑定 GPU 设备
### 

set -e
echo "[AntiCheatVM] 正在配置 VFIO/IOMMU 环境..."

# 检查是否为root用户运行
if [ "$(id -u)" -ne 0 ]; then
   echo "[错误] 此脚本需要root权限执行，请使用sudo运行"
   exit 1
fi

# 检查CPU是否支持虚拟化和IOMMU
check_cpu_support() {
    echo "[+] 检查CPU虚拟化与IOMMU支持..."
    
    # 检查CPU虚拟化支持
    if ! grep -q -E 'vmx|svm' /proc/cpuinfo; then
        echo "[错误] CPU不支持硬件虚拟化 (AMD-V 或 Intel VT-x)！"
        exit 1
    fi
    
    # 检查IOMMU支持 (Intel VT-d 或 AMD-Vi)
    if grep -q GenuineIntel /proc/cpuinfo; then
        # Intel处理器 - 放宽检测条件
        if ! dmesg | grep -i "DMAR\|iommu" | grep -q .; then
            echo "[错误] Intel VT-d 未在BIOS中启用或CPU不支持"
            echo "请在BIOS中启用VT-d/IOMMU功能后重试"
            exit 1
        else
            echo "[√] Intel VT-d IOMMU支持已确认"
        fi
    else
        # AMD处理器 - 同样放宽检测条件
        if ! dmesg | grep -i "AMD-Vi\|iommu" | grep -q .; then
            echo "[错误] AMD-Vi 未在BIOS中启用或CPU不支持"
            echo "请在BIOS中启用AMD-Vi/IOMMU功能后重试"
            exit 1
        else
            echo "[√] AMD-Vi IOMMU支持已确认"
        fi
    fi
}

# 修改GRUB参数启用IOMMU
configure_grub() {
    echo "[+] 修改GRUB启动参数以启用IOMMU..."
    
    GRUB_CONFIG="/etc/default/grub"
    GRUB_CMDLINE=$(grep "GRUB_CMDLINE_LINUX=" $GRUB_CONFIG)
    
    # 根据CPU类型确定IOMMU参数
    if grep -q GenuineIntel /proc/cpuinfo; then
        IOMMU_PARAM="intel_iommu=on iommu=pt rd.driver.pre=vfio-pci"
    else
        IOMMU_PARAM="amd_iommu=on iommu=pt rd.driver.pre=vfio-pci"
    fi
    
    # 检查是否已经有IOMMU参数
    if echo $GRUB_CMDLINE | grep -q "iommu=pt"; then
        echo "[i] GRUB已包含IOMMU参数，无需修改"
        return
    fi
    
    # 备份GRUB配置
    cp $GRUB_CONFIG ${GRUB_CONFIG}.bak
    echo "[i] 已备份GRUB配置至 ${GRUB_CONFIG}.bak"
    
    # 修改GRUB_CMDLINE_LINUX参数
    if [[ $GRUB_CMDLINE == *'"'* ]]; then
        # 有引号的情况，在引号内添加参数
        sed -i "s|GRUB_CMDLINE_LINUX=\"\(.*\)\"|GRUB_CMDLINE_LINUX=\"\1 $IOMMU_PARAM\"|" $GRUB_CONFIG
    else
        # 没有引号的情况，添加引号和参数
        sed -i "s|GRUB_CMDLINE_LINUX=\(.*\)|GRUB_CMDLINE_LINUX=\"\1 $IOMMU_PARAM\"|" $GRUB_CONFIG
    fi
    
    echo "[√] GRUB配置已更新，添加了IOMMU支持"
    
    # 更新GRUB配置
    if command -v grub2-mkconfig &> /dev/null; then
        grub2-mkconfig -o /boot/grub2/grub.cfg
    else
        update-grub
    fi
    
    echo "[√] GRUB配置已重新生成"
}

# 查找显卡及其相关设备
find_gpu() {
    echo "[+] 扫描可用显卡设备..."
    
    # 创建配置目录
    mkdir -p config
    
    # 收集PCI设备信息
    lspci -nnk > config/pci_devices.txt
    
    # 查找所有显卡
    echo "[i] 检测到以下显卡设备:"
    GPU_LIST=$(lspci | grep -i 'vga\|3d controller' | cut -d' ' -f1)
    
    if [ -z "$GPU_LIST" ]; then
        echo "[错误] 未检测到任何显卡设备"
        exit 1
    fi
    
    # 为每个显卡显示详细信息
    IFS=$'\n'
    GPU_COUNT=0
    declare -a GPU_ARRAY
    
    for GPU_ID in $GPU_LIST; do
        GPU_COUNT=$((GPU_COUNT + 1))
        GPU_INFO=$(lspci -nnks $GPU_ID | grep -E "VGA|3D controller|Kernel driver" | tr '\n' ' ')
        GPU_ARRAY+=("$GPU_ID: $GPU_INFO")
        echo "[$GPU_COUNT] $GPU_ID: $GPU_INFO"
    done
    
    # 选择要绑定的显卡
    if [ $GPU_COUNT -gt 1 ]; then
        echo "[i] 检测到多个显卡，请选择要用于VFIO直通的显卡编号 [1-$GPU_COUNT]:"
        read -r GPU_SELECTION
        
        if ! [[ $GPU_SELECTION =~ ^[0-9]+$ ]] || [ $GPU_SELECTION -lt 1 ] || [ $GPU_SELECTION -gt $GPU_COUNT ]; then
            echo "[错误] 无效选择"
            exit 1
        fi
        
        SELECTED_GPU_ID=$(echo "$GPU_LIST" | sed -n ${GPU_SELECTION}p)
    else
        echo "[警告] 只检测到一个显卡。如果您绑定此显卡到VFIO，主机将无法显示图形界面。"
        echo "请确保您有其他显示输出可用或可以通过SSH远程访问。"
        echo "是否继续? (y/n)"
        read -r CONTINUE
        
        if [[ $CONTINUE != "y" && $CONTINUE != "Y" ]]; then
            echo "[i] 操作已取消"
            exit 0
        fi
        
        SELECTED_GPU_ID=$(echo "$GPU_LIST" | head -n1)
    fi
    
    echo "[i] 已选择显卡: $SELECTED_GPU_ID"
    
    # 获取显卡的Vendor:Device ID
    GPU_VENDOR_ID=$(lspci -nns $SELECTED_GPU_ID | grep -oP '(?<=\[)[a-f0-9]{4}:[a-f0-9]{4}(?=\])')
    echo "[i] 显卡 Vendor:Device ID: $GPU_VENDOR_ID"
    
    # 寻找同一IOMMU组的相关设备(音频等)
    echo "[+] 检测显卡相关设备(同一IOMMU组)..."
    
    # 获取IOMMU组信息
    for d in /sys/kernel/iommu_groups/*/devices/*; do
        if [ -e "$d/vendor" ] && [ -e "$d/device" ]; then
            DEV_PATH=$(basename "$d")
            if [ "$DEV_PATH" = "$SELECTED_GPU_ID" ]; then
                IOMMU_GROUP=$(basename $(dirname $(dirname "$d")))
                echo "[i] 显卡所在的IOMMU组: $IOMMU_GROUP"
                break
            fi
        fi
    done
    
    # 查找同一IOMMU组的所有设备
    if [ -n "$IOMMU_GROUP" ]; then
        echo "[i] IOMMU组 $IOMMU_GROUP 中的所有设备:"
        GPU_RELATED_DEVICES=()
        
        for dev in /sys/kernel/iommu_groups/$IOMMU_GROUP/devices/*; do
            DEV_ID=$(basename "$dev")
            DEV_INFO=$(lspci -nns $DEV_ID)
            echo "    $DEV_INFO"
            
            # 提取vendor:device ID
            VENDOR_DEVICE=$(echo "$DEV_INFO" | grep -oP '(?<=\[)[a-f0-9]{4}:[a-f0-9]{4}(?=\])')
            GPU_RELATED_DEVICES+=("$VENDOR_DEVICE")
        done
    else
        echo "[警告] 无法确定显卡的IOMMU组，将只绑定显卡本身"
        GPU_RELATED_DEVICES=("$GPU_VENDOR_ID")
    fi
    
    # 保存设备信息到配置文件
    echo "[+] 保存设备信息到配置文件..."
    
    cat > config/vfio_devices.yaml <<EOL
# 通过VFIO直通的设备列表
devices:
EOL
    
    for dev_id in "${GPU_RELATED_DEVICES[@]}"; do
        echo "  - '$dev_id'  # $(lspci | grep -i "$(echo $dev_id | cut -d: -f1)")"  >> config/vfio_devices.yaml
    done
    
    echo "[√] 设备信息已保存到 config/vfio_devices.yaml"
}

# 配置VFIO模块和绑定脚本
configure_vfio() {
    echo "[+] 配置VFIO模块加载..."
    
    # 确保VFIO模块会被加载
    if ! grep -q vfio /etc/modules 2>/dev/null && [ -f /etc/modules ]; then
        echo "vfio" >> /etc/modules
        echo "vfio_iommu_type1" >> /etc/modules
        echo "vfio_pci" >> /etc/modules
        echo "vfio_virqfd" >> /etc/modules 2>/dev/null || true  # 某些系统可能没有这个模块
    fi
    
    # 创建VFIO配置
    echo "[+] 创建VFIO设备配置..."
    
    # 从YAML文件读取设备ID（简化版，生产环境建议使用Python和yaml库）
    DEVICE_IDS=$(grep -oP "(?<=').*?(?=')" config/vfio_devices.yaml)
    
    VFIO_CONF="/etc/modprobe.d/vfio.conf"
    OPTIONS="options vfio-pci ids="
    
    for id in $DEVICE_IDS; do
        OPTIONS+="$id,"
    done
    
    # 移除最后的逗号
    OPTIONS=${OPTIONS%,}
    
    # 写入配置文件
    echo "$OPTIONS" > $VFIO_CONF
    echo "[√] VFIO配置已写入 $VFIO_CONF"
    
    # 更新initramfs
    echo "[+] 更新initramfs以应用VFIO配置..."
    
    if command -v dracut &> /dev/null; then
        dracut --force
    elif command -v update-initramfs &> /dev/null; then
        update-initramfs -u
    else
        echo "[警告] 无法找到dracut或update-initramfs命令，请手动更新initramfs"
    fi
    
    echo "[√] initramfs已更新"
}

# 主函数
main() {
    check_cpu_support
    configure_grub
    find_gpu
    configure_vfio
    
    echo "======================================================"
    echo "[AntiCheatVM] VFIO配置已完成! 系统需要重启以应用更改。"
    echo ""
    echo "请检查以下配置文件确认无误:"
    echo "  - /etc/default/grub (IOMMU参数)"
    echo "  - /etc/modprobe.d/vfio.conf (设备直通)"
    echo "  - config/vfio_devices.yaml (设备列表)"
    echo ""
    echo "重启后，请继续运行create_vm.py创建虚拟机配置。"
    echo ""
    echo "是否立即重启? (y/n)"
    read -r REBOOT
    
    if [[ $REBOOT == "y" || $REBOOT == "Y" ]]; then
        echo "系统将在5秒后重启..."
        sleep 5
        reboot
    else
        echo "您选择了稍后重启。请在方便时手动重启系统。"
        echo "要使VFIO设置生效，重启是必要的。"
    fi
}

# 执行主函数
main