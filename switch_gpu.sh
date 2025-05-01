#!/bin/bash
# GPU切换脚本：在宿主机使用和VM直通之间切换

# 颜色
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

# 获取实际GPU地址
get_gpu_address() {
    # 尝试查找NVIDIA GPU
    gpu_info=$(lspci -nn | grep -i "NVIDIA" | grep -i "VGA" | head -1)
    if [ -z "$gpu_info" ]; then
        # 如果找不到NVIDIA GPU，尝试找任何显卡
        gpu_info=$(lspci -nn | grep -i "VGA" | grep -v "Intel" | head -1)
    fi
    
    if [ -n "$gpu_info" ]; then
        gpu_addr=$(echo "$gpu_info" | awk '{print $1}')
        echo "$gpu_addr"
    else
        # 默认值
        echo "01:00.0"
    fi
}

# 获取GPU地址
GPU_ADDRESS=$(get_gpu_address)

# 将PCI地址转换为libvirt格式
# 例如: 01:00.0 -> pci_0000_01_00_0
convert_to_libvirt_format() {
    local addr=$1
    # 替换冒号和点为下划线
    local formatted_addr=$(echo "$addr" | sed 's/[:.]/_/g')
    echo "pci_0000_${formatted_addr}"
}

# 显示当前状态
show_status() {
    echo -e "${BLUE}[+] 检查GPU状态...${NC}"
    
    if lspci -nnk | grep -A 2 "$GPU_ADDRESS" | grep -q "Kernel driver in use: vfio-pci"; then
        echo -e "${YELLOW}[!] GPU当前由VFIO-PCI驱动控制（适用于VM）${NC}"
        return 0  # 0 = VFIO模式
    elif lspci -nnk | grep -A 2 "$GPU_ADDRESS" | grep -q "Kernel driver in use: nvidia"; then
        echo -e "${GREEN}[✓] GPU当前由NVIDIA驱动控制（适用于宿主机）${NC}"
        return 1  # 1 = NVIDIA模式
    else
        echo -e "${RED}[错误] 无法确定当前GPU状态${NC}"
        echo -e "${YELLOW}[!] GPU地址: $GPU_ADDRESS${NC}"
        echo -e "${YELLOW}[!] 驱动信息:${NC}"
        lspci -nnk | grep -A 5 "$GPU_ADDRESS"
        exit 1
    fi
}

# 启用NVIDIA驱动（宿主机使用）
enable_nvidia() {
    echo -e "${BLUE}[+] 启用NVIDIA驱动...${NC}"
    
    # 转换PCI地址为libvirt格式
    local libvirt_dev=$(convert_to_libvirt_format "$GPU_ADDRESS")
    
    echo -e "${BLUE}[1/3] 将GPU重新附加到主机...${NC}"
    echo -e "${YELLOW}[!] 使用设备名称: $libvirt_dev${NC}"
    virsh nodedev-reattach "$libvirt_dev" || return 1
    echo -e "${GREEN}[✓] GPU已重新附加${NC}"
    
    echo -e "${BLUE}[2/3] 移除VFIO驱动...${NC}"
    rmmod vfio_pci vfio_pci_core vfio_iommu_type1 || true
    echo -e "${GREEN}[✓] VFIO驱动已移除${NC}"
    
    echo -e "${BLUE}[3/3] 加载NVIDIA驱动...${NC}"
    modprobe -i nvidia_modeset nvidia_uvm nvidia || return 1
    echo -e "${GREEN}[✓] NVIDIA驱动已加载${NC}"
    
    echo -e "${GREEN}[✓] GPU已切换到宿主机模式${NC}"
    return 0
}

# 启用VFIO驱动（VM使用）
enable_vfio() {
    echo -e "${BLUE}[+] 启用VFIO驱动...${NC}"
    
    echo -e "${BLUE}[1/3] 移除NVIDIA驱动...${NC}"
    rmmod nvidia_modeset nvidia_uvm nvidia || true
    echo -e "${GREEN}[✓] NVIDIA驱动已移除${NC}"
    
    echo -e "${BLUE}[2/3] 加载VFIO驱动...${NC}"
    modprobe -i vfio_pci vfio_pci_core vfio_iommu_type1 || return 1
    echo -e "${GREEN}[✓] VFIO驱动已加载${NC}"
    
    echo -e "${BLUE}[3/3] 将GPU分离到VFIO...${NC}"
    # 转换PCI地址为libvirt格式
    local libvirt_dev=$(convert_to_libvirt_format "$GPU_ADDRESS")
    echo -e "${YELLOW}[!] 使用设备名称: $libvirt_dev${NC}"
    virsh nodedev-detach "$libvirt_dev" || return 1
    echo -e "${GREEN}[✓] GPU已分离${NC}"
    
    echo -e "${GREEN}[✓] GPU已切换到VM直通模式${NC}"
    return 0
}

# 主逻辑
if [ "$1" == "nvidia" ] || [ "$1" == "host" ]; then
    enable_nvidia
elif [ "$1" == "vfio" ] || [ "$1" == "vm" ]; then
    enable_vfio
elif [ "$1" == "status" ]; then
    show_status
    exit $?
else
    # 自动切换模式
    show_status
    current_mode=$?
    
    if [ $current_mode -eq 0 ]; then
        # 当前为VFIO模式，切换到NVIDIA
        enable_nvidia
    else
        # 当前为NVIDIA模式，切换到VFIO
        enable_vfio
    fi
fi

# 显示最终状态
show_status
