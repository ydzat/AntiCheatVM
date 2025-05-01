#!/bin/bash
# AntiCheatVM 启动脚本
# 包含必要的性能优化和GPU直通配置

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 默认虚拟机名称
VM_NAME="AntiCheatVM"

# 解析命令行参数
LOOKING_GLASS=false
BYPASS_GPU_CHECK=false

# 解析参数
for arg in "$@"
do
    case $arg in
        --lg|--looking-glass)
        LOOKING_GLASS=true
        shift
        ;;
        --bypass-gpu-check)
        BYPASS_GPU_CHECK=true
        shift
        ;;
        --vm=*)
        VM_NAME="${arg#*=}"
        shift
        ;;
        *)
        # 未知参数
        ;;
    esac
done

echo "=================================================="
echo " AntiCheatVM 启动程序 - $VM_NAME"
echo "=================================================="

# 检查虚拟机是否存在
check_vm_exists() {
    echo -e "${BLUE}[+] 检查虚拟机是否存在...${NC}"
    
    if ! virsh list --all | grep -q "$VM_NAME"; then
        echo -e "${RED}[错误] 找不到虚拟机: $VM_NAME${NC}"
        echo "请先使用 create_vm.py 创建虚拟机，或提供正确的虚拟机名称"
        exit 1
    fi
    
    echo -e "${GREEN}[✓] 虚拟机存在: $VM_NAME${NC}"
    return 0
}

# 检查GPU状态
check_gpu_status() {
    echo -e "${BLUE}[+] 检查GPU状态...${NC}"
    
    if [ "$BYPASS_GPU_CHECK" = true ]; then
        echo -e "${YELLOW}[!] 跳过GPU检查...${NC}"
        return 0
    fi
    
    # 获取配置的VFIO设备
    VFIO_CONFIG_FILE="$SCRIPT_DIR/config/vfio_devices.yaml"
    
    if [ ! -f "$VFIO_CONFIG_FILE" ]; then
        echo -e "${RED}[错误] 找不到VFIO设备配置文件${NC}"
        echo "请先运行 setup_vfio.sh 配置GPU直通"
        exit 1
    fi
    
    # 读取配置文件中的第一个设备 - 修复格式问题
    GPU_ID=$(grep -m 1 "\".*\"" "$VFIO_CONFIG_FILE" | grep -o '"[^"]*"' | head -1 | tr -d '"')
    
    if [ -z "$GPU_ID" ]; then
        echo -e "${RED}[错误] 无法从配置文件中读取GPU ID${NC}"
        # 尝试使用默认值
        GPU_ID="10de2820"
        echo -e "${YELLOW}[!] 尝试使用默认值: $GPU_ID${NC}"
    fi
    
    # 将十六进制ID转换为可搜索格式
    FORMATTED_GPU_ID=$(echo "$GPU_ID" | sed 's/\(..\)\(..\)/\1:\2/')
    
    # 直接查找对应的NVIDIA显卡
    GPU_INFO=$(lspci -nn | grep "NVIDIA" | grep "VGA")
    GPU_ADDR=$(echo "$GPU_INFO" | head -1 | awk '{print $1}')
    
    if [ -z "$GPU_ADDR" ]; then
        echo -e "${YELLOW}[!] 未找到NVIDIA显卡，尝试查找任何显卡...${NC}"
        # 尝试查找任何显卡
        GPU_INFO=$(lspci -nn | grep -i "VGA")
        GPU_ADDR=$(echo "$GPU_INFO" | grep -v "Intel" | head -1 | awk '{print $1}')
        
        if [ -z "$GPU_ADDR" ]; then
            echo -e "${RED}[错误] 无法找到任何可用的显卡${NC}"
            echo -e "${YELLOW}[!] 使用默认地址 01:00.0${NC}"
            GPU_ADDR="01:00.0"
        fi
    fi
    
    echo -e "${GREEN}[✓] 找到GPU地址: $GPU_ADDR${NC}"
    
    # 改进GPU驱动检查，增强容错性
    GPU_STATUS=$(lspci -nnk -s "$GPU_ADDR" | grep -A2 "Kernel driver")
    echo -e "${BLUE}[+] GPU当前状态:${NC}"
    echo "$GPU_STATUS"
    
    # 检查GPU驱动是否为vfio-pci
    if echo "$GPU_STATUS" | grep -q "vfio-pci"; then
        echo -e "${GREEN}[✓] GPU已绑定到vfio-pci驱动，可以直通给VM${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}[!] GPU未绑定到vfio-pci驱动${NC}"
    echo -e "${YELLOW}[!] 将尝试绑定GPU到vfio-pci...${NC}"
    
    # 调用GPU切换脚本
    sudo "$SCRIPT_DIR/switch_gpu.sh" vfio
    
    # 再次检查
    sleep 2
    GPU_STATUS=$(lspci -nnk -s "$GPU_ADDR" | grep -A2 "Kernel driver")
    
    if echo "$GPU_STATUS" | grep -q "vfio-pci"; then
        echo -e "${GREEN}[✓] GPU已成功绑定到vfio-pci驱动${NC}"
        return 0
    else
        echo -e "${RED}[错误] 无法将GPU绑定到vfio-pci驱动${NC}"
        echo "请手动运行 '$SCRIPT_DIR/gpu-manager.sh' 切换GPU到VM模式"
        exit 1
    fi
}

# 配置共享内存
check_shared_memory() {
    if [ "$LOOKING_GLASS" = true ]; then
        echo -e "${BLUE}[+] 检查Looking Glass共享内存...${NC}"
        
        if [ ! -e /dev/shm/looking-glass ]; then
            echo -e "${YELLOW}[!] Looking Glass共享内存文件不存在，正在创建...${NC}"
            sudo touch /dev/shm/looking-glass
            sudo chown $USER:qemu /dev/shm/looking-glass
            sudo chmod 0660 /dev/shm/looking-glass
            
            # 为SELinux设置正确的上下文
            if command -v semanage &> /dev/null; then
                sudo semanage fcontext -a -t svirt_tmpfs_t /dev/shm/looking-glass
                sudo restorecon -v /dev/shm/looking-glass
            fi
        elif [ ! -w /dev/shm/looking-glass ]; then
            echo -e "${YELLOW}[!] Looking Glass共享内存文件权限错误，正在修复...${NC}"
            sudo chown $USER:qemu /dev/shm/looking-glass
            sudo chmod 0660 /dev/shm/looking-glass
        fi
        
        echo -e "${GREEN}[✓] Looking Glass共享内存检查完成${NC}"
    fi
    
    return 0
}

# 配置大页内存以提高性能
setup_hugepages() {
    echo -e "${BLUE}[+] 配置大页内存...${NC}"
    
    # 获取虚拟机内存大小（KB）
    VM_MEMORY_KB=$(virsh dominfo "$VM_NAME" | grep "Max memory" | awk '{print $3}')
    
    if [ -z "$VM_MEMORY_KB" ]; then
        echo -e "${YELLOW}[!] 无法获取虚拟机内存大小，使用默认值${NC}"
        VM_MEMORY_KB=8388608  # 8GB 默认值
    fi
    
    # 转换为MB并增加一些余量
    VM_MEMORY_MB=$((VM_MEMORY_KB / 1024 + 512))
    
    # 计算需要的大页数量（2MB页面大小）
    HUGEPAGES_NEEDED=$((VM_MEMORY_MB / 2))
    
    echo -e "${BLUE}[+] 虚拟机内存: ${VM_MEMORY_MB}MB, 需要${HUGEPAGES_NEEDED}个大页${NC}"
    
    # 配置大页
    echo $HUGEPAGES_NEEDED | sudo tee /proc/sys/vm/nr_hugepages > /dev/null
    
    # 检查是否成功
    HUGEPAGES_ALLOCATED=$(cat /proc/sys/vm/nr_hugepages)
    
    if [ "$HUGEPAGES_ALLOCATED" -lt "$HUGEPAGES_NEEDED" ]; then
        echo -e "${YELLOW}[!] 无法分配足够的大页内存 (分配: $HUGEPAGES_ALLOCATED, 需要: $HUGEPAGES_NEEDED)${NC}"
        echo -e "${YELLOW}[!] 继续使用普通内存...${NC}"
        return 1
    fi
    
    echo -e "${GREEN}[✓] 大页内存配置完成: $HUGEPAGES_ALLOCATED 页${NC}"
    return 0
}

# 启动虚拟机
start_vm() {
    echo -e "${BLUE}[+] 启动虚拟机 $VM_NAME...${NC}"
    
    # 配置大页内存，但不添加额外参数（virsh start不支持这些参数）
    setup_hugepages
    
    # 先尝试常规启动方式
    virsh start "$VM_NAME"
    START_RESULT=$?
    
    # 如果常规启动失败，尝试使用特殊选项（绕过网络问题）
    if [ $START_RESULT -ne 0 ]; then
        echo -e "${YELLOW}[!] 使用标准方式启动失败，尝试替代方法...${NC}"
        
        # 使用 qemu:///system 连接并指定用户模式网络
        echo -e "${BLUE}[+] 尝试使用用户模式网络启动...${NC}"
        virsh --connect qemu:///system define /home/ydzat/workspace/AntiCheatVM/vms/AntiCheatVM_fixed.xml
        virsh --connect qemu:///system start "$VM_NAME"
        START_RESULT=$?
        
        if [ $START_RESULT -ne 0 ]; then
            echo -e "${RED}[错误] 无法启动虚拟机${NC}"
            exit 1
        fi
    fi
    
    echo -e "${GREEN}[✓] 虚拟机启动成功${NC}"
    
    # 启动Looking Glass（如果需要）
    if [ "$LOOKING_GLASS" = true ]; then
        echo -e "${BLUE}[+] 启动Looking Glass客户端...${NC}"
        echo -e "${YELLOW}[!] 等待10秒让VM启动...${NC}"
        sleep 10
        
        # 检查Looking Glass命令是否可用
        if command -v looking-glass-client &> /dev/null; then
            # 在后台启动Looking Glass
            looking-glass-client -s -m 97 &
            echo -e "${GREEN}[✓] Looking Glass客户端已启动${NC}"
        else
            echo -e "${RED}[错误] Looking Glass客户端未安装${NC}"
            echo "请运行 looking_glass_setup.sh 安装Looking Glass"
        fi
    fi
    
    return 0
}

# 主函数
main() {
    check_vm_exists
    check_gpu_status
    check_shared_memory
    start_vm
    
    echo ""
    echo -e "${GREEN}[✓] 虚拟机启动流程完成!${NC}"
    echo ""
    echo -e "${YELLOW}[i] 提示:${NC}"
    echo "1. 使用 '$SCRIPT_DIR/stop_vm.sh' 停止虚拟机"
    echo "2. 使用 'virsh console $VM_NAME' 连接到VM控制台（如果需要）"
    
    if [ "$LOOKING_GLASS" = true ]; then
        echo "3. 右Ctrl键可切换键盘和鼠标捕获"
    fi
}

# 执行主函数
main