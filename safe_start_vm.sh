#!/bin/bash
# AntiCheatVM 安全启动脚本 - 优化版本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 虚拟机名称
VM_NAME="AntiCheatVM"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 默认配置
USE_GPU_PASSTHROUGH=false
USE_HUGEPAGES=false
USE_LOOKING_GLASS=false

# 解析命令行参数
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --gpu|-g)
      USE_GPU_PASSTHROUGH=true
      shift
      ;;
    --hugepages|-h)
      USE_HUGEPAGES=true
      shift
      ;;
    --looking-glass|-l)
      USE_LOOKING_GLASS=true
      shift
      ;;
    --help)
      echo "用法: $0 [选项]"
      echo "选项:"
      echo "  --gpu, -g          启用GPU直通（需要先配置VFIO）"
      echo "  --hugepages, -h    使用大页内存以提升性能"
      echo "  --looking-glass, -l 使用Looking Glass作为显示输出"
      echo "  --help              显示此帮助信息"
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

echo "=================================================="
echo " AntiCheatVM 安全启动程序 - $VM_NAME"
echo "=================================================="

# 检查虚拟机是否存在
if ! virsh list --all | grep -q "$VM_NAME"; then
    echo -e "${RED}[错误] 找不到虚拟机: $VM_NAME${NC}"
    exit 1
fi

echo -e "${GREEN}[✓] 虚拟机存在: $VM_NAME${NC}"

# 显示当前设置
echo -e "${BLUE}[i] 当前配置:${NC}"
echo -e "  - GPU直通: $(if $USE_GPU_PASSTHROUGH; then echo "启用"; else echo "禁用"; fi)"
echo -e "  - 大页内存: $(if $USE_HUGEPAGES; then echo "启用"; else echo "禁用"; fi)"
echo -e "  - Looking Glass: $(if $USE_LOOKING_GLASS; then echo "启用"; else echo "禁用"; fi)"

# 配置GPU直通（如果启用）
if [ "$USE_GPU_PASSTHROUGH" = true ]; then
    echo -e "${BLUE}[+] 配置GPU直通...${NC}"
    
    # 检查VFIO设备配置
    if [ ! -f "$SCRIPT_DIR/config/vfio_devices.yaml" ]; then
        echo -e "${YELLOW}[!] 找不到VFIO设备配置文件${NC}"
        echo -e "${YELLOW}[!] 跳过GPU直通配置${NC}"
        USE_GPU_PASSTHROUGH=false
    else
        # 检查GPU是否已绑定到vfio-pci
        GPU_ADDR=$(lspci -nn | grep "NVIDIA" | grep "VGA" | head -1 | awk '{print $1}')
        
        if [ -z "$GPU_ADDR" ]; then
            echo -e "${YELLOW}[!] 无法找到NVIDIA显卡，尝试其他显卡...${NC}"
            GPU_ADDR=$(lspci -nn | grep -i "VGA" | grep -v "Intel" | head -1 | awk '{print $1}')
        fi
        
        if [ -z "$GPU_ADDR" ]; then
            echo -e "${YELLOW}[!] 无法找到独立显卡${NC}"
            echo -e "${YELLOW}[!] 跳过GPU直通配置${NC}"
            USE_GPU_PASSTHROUGH=false
        else
            echo -e "${GREEN}[✓] 找到GPU: $GPU_ADDR${NC}"
            
            # 检查GPU驱动状态
            GPU_DRIVER=$(lspci -nnk -s "$GPU_ADDR" | grep "Kernel driver" | awk '{print $3}')
            
            if [ "$GPU_DRIVER" != "vfio-pci" ]; then
                echo -e "${YELLOW}[!] GPU尚未绑定到vfio-pci (当前: $GPU_DRIVER)${NC}"
                echo -e "${YELLOW}[!] 尝试绑定到vfio-pci...${NC}"
                
                # 使用sudo来避免权限问题
                sudo "$SCRIPT_DIR/switch_gpu.sh" vfio
                
                # 再次检查
                sleep 2
                GPU_DRIVER=$(lspci -nnk -s "$GPU_ADDR" | grep "Kernel driver" | awk '{print $3}')
                
                if [ "$GPU_DRIVER" != "vfio-pci" ]; then
                    echo -e "${RED}[错误] 无法将GPU绑定到vfio-pci${NC}"
                    echo -e "${YELLOW}[!] 跳过GPU直通配置${NC}"
                    USE_GPU_PASSTHROUGH=false
                fi
                # 注意：这里删除了一个多余的else分支，修复了逻辑错误
            fi

            # 如果GPU已经正确绑定到vfio-pci，确保启用GPU直通
            if [ "$GPU_DRIVER" = "vfio-pci" ]; then
                echo -e "${GREEN}[✓] GPU已成功绑定到vfio-pci${NC}"
                USE_GPU_PASSTHROUGH=true
                
                # 检查是否正在使用正确的VM配置文件（包含GPU音频设备）
                if [ -f "$SCRIPT_DIR/vms/AntiCheatVM_fixed.xml" ]; then
                    # 使用包含GPU音频设备直通的修复版配置文件
                    sudo virsh define "$SCRIPT_DIR/vms/AntiCheatVM_fixed.xml" &>/dev/null
                    if [ $? -eq 0 ]; then
                        echo -e "${GREEN}[✓] 已加载包含GPU音频设备的优化配置${NC}"
                    fi
                fi
            fi
        fi
    fi
fi

# 配置大页内存（如果启用）
if [ "$USE_HUGEPAGES" = true ]; then
    echo -e "${BLUE}[+] 配置大页内存...${NC}"
    
    # 获取虚拟机内存大小（KB）
    VM_MEMORY_KB=$(virsh dominfo "$VM_NAME" | grep "Max memory" | awk '{print $3}')
    
    if [ -z "$VM_MEMORY_KB" ]; then
        echo -e "${YELLOW}[!] 无法获取虚拟机内存大小，使用默认值${NC}"
        VM_MEMORY_KB=8388608  # 8GB 默认值
    fi
    
    # 转换为MB并增加一些余量
    VM_MEMORY_MB=$((VM_MEMORY_KB / 1024 + 256))
    
    # 计算需要的大页数量（2MB页面大小）
    HUGEPAGES_NEEDED=$((VM_MEMORY_MB / 2))
    
    echo -e "${BLUE}[+] 虚拟机内存: ${VM_MEMORY_MB}MB, 需要${HUGEPAGES_NEEDED}个大页${NC}"
    
    # 配置大页
    echo "尝试分配 $HUGEPAGES_NEEDED 个大页内存..."
    sudo sh -c "echo $HUGEPAGES_NEEDED > /proc/sys/vm/nr_hugepages"
    
    # 检查是否成功
    sleep 1
    HUGEPAGES_ALLOCATED=$(cat /proc/sys/vm/nr_hugepages)
    
    if [ "$HUGEPAGES_ALLOCATED" -lt "$HUGEPAGES_NEEDED" ]; then
        echo -e "${YELLOW}[!] 无法分配足够的大页内存 (分配: $HUGEPAGES_ALLOCATED, 需要: $HUGEPAGES_NEEDED)${NC}"
        echo -e "${YELLOW}[!] 尝试释放缓存并重新分配...${NC}"
        
        # 释放缓存
        sudo sh -c "echo 3 > /proc/sys/vm/drop_caches"
        sudo sh -c "echo $HUGEPAGES_NEEDED > /proc/sys/vm/nr_hugepages"
        
        sleep 1
        HUGEPAGES_ALLOCATED=$(cat /proc/sys/vm/nr_hugepages)
        
        if [ "$HUGEPAGES_ALLOCATED" -lt "$HUGEPAGES_NEEDED" ]; then
            echo -e "${RED}[错误] 仍然无法分配足够的大页内存${NC}"
            echo -e "${YELLOW}[!] 将使用普通内存${NC}"
            USE_HUGEPAGES=false
        else
            echo -e "${GREEN}[✓] 大页内存配置成功: $HUGEPAGES_ALLOCATED 页${NC}"
        fi
    else
        echo -e "${GREEN}[✓] 大页内存配置成功: $HUGEPAGES_ALLOCATED 页${NC}"
    fi
fi

# 配置Looking Glass（如果启用）
if [ "$USE_LOOKING_GLASS" = true ]; then
    echo -e "${BLUE}[+] 配置Looking Glass共享内存...${NC}"
    
    if [ ! -e /dev/shm/looking-glass ]; then
        echo -e "${YELLOW}[!] Looking Glass共享内存文件不存在，正在创建...${NC}"
        sudo touch /dev/shm/looking-glass
        sudo chown $USER:qemu /dev/shm/looking-glass
        sudo chmod 0660 /dev/shm/looking-glass
    elif [ ! -w /dev/shm/looking-glass ]; then
        echo -e "${YELLOW}[!] Looking Glass共享内存文件权限错误，正在修复...${NC}"
        sudo chown $USER:qemu /dev/shm/looking-glass
        sudo chmod 0660 /dev/shm/looking-glass
    fi
    
    echo -e "${GREEN}[✓] Looking Glass共享内存配置完成${NC}"
fi

# 启动前确认
echo -e "${BLUE}[+] 是否继续启动虚拟机? (y/n)${NC}"
read -r CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo -e "${YELLOW}取消启动${NC}"
    exit 0
fi

# 使用sudo启动虚拟机以避免权限问题
echo -e "${BLUE}[+] 启动虚拟机 $VM_NAME...${NC}"
sudo virsh start "$VM_NAME"

if [ $? -ne 0 ]; then
    echo -e "${RED}[错误] 虚拟机启动失败${NC}"
    exit 1
fi

echo -e "${GREEN}[✓] 虚拟机启动成功${NC}"

# 如果启用Looking Glass，启动客户端
if [ "$USE_LOOKING_GLASS" = true ]; then
    echo -e "${BLUE}[+] 等待虚拟机初始化 (10秒)...${NC}"
    sleep 10
    
    if command -v looking-glass-client &> /dev/null; then
        echo -e "${BLUE}[+] 启动Looking Glass客户端...${NC}"
        looking-glass-client -s -m 97 &
        echo -e "${GREEN}[✓] Looking Glass客户端已启动${NC}"
    else
        echo -e "${YELLOW}[!] Looking Glass客户端未安装${NC}"
        echo -e "${YELLOW}[!] 你可以运行 '$SCRIPT_DIR/looking_glass_setup.sh' 来安装${NC}"
    fi
fi

echo ""
echo -e "${GREEN}[✓] 虚拟机启动流程完成!${NC}"
echo ""
echo -e "${YELLOW}[i] 提示:${NC}"
echo "1. 使用 'sudo virsh shutdown $VM_NAME' 安全关闭虚拟机"
echo "2. 使用 'sudo virsh destroy $VM_NAME' 强制关闭虚拟机"

if [ "$USE_LOOKING_GLASS" = true ]; then
    echo "3. 右Ctrl键可切换键盘和鼠标捕获"
fi