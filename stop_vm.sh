#!/bin/bash
# AntiCheatVM 停止脚本
# 安全关闭虚拟机并清理资源

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
FORCE=false
REATTACH_GPU=false

# 解析参数
for arg in "$@"
do
    case $arg in
        --force)
        FORCE=true
        shift
        ;;
        --reattach-gpu)
        REATTACH_GPU=true
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
echo " AntiCheatVM 停止程序 - $VM_NAME"
echo "=================================================="

# 检查虚拟机是否存在并运行
check_vm_running() {
    echo -e "${BLUE}[+] 检查虚拟机状态...${NC}"
    
    if ! virsh list | grep -q "$VM_NAME"; then
        echo -e "${YELLOW}[!] 虚拟机 $VM_NAME 未运行${NC}"
        
        # 检查虚拟机是否存在
        if ! virsh list --all | grep -q "$VM_NAME"; then
            echo -e "${RED}[错误] 虚拟机 $VM_NAME 不存在${NC}"
            exit 1
        fi
        
        return 1
    fi
    
    echo -e "${GREEN}[✓] 虚拟机 $VM_NAME 正在运行${NC}"
    return 0
}

# 停止虚拟机
stop_vm() {
    echo -e "${BLUE}[+] 停止虚拟机 $VM_NAME...${NC}"
    
    if [ "$FORCE" = true ]; then
        echo -e "${YELLOW}[!] 强制关闭虚拟机...${NC}"
        virsh destroy "$VM_NAME"
    else
        echo -e "${BLUE}[+] 正常关闭虚拟机（等待操作系统关闭）...${NC}"
        virsh shutdown "$VM_NAME"
        
        # 等待虚拟机关闭，最多等待60秒
        echo -e "${BLUE}[+] 等待虚拟机关闭...${NC}"
        
        for i in {1..60}; do
            if ! virsh list | grep -q "$VM_NAME"; then
                echo -e "${GREEN}[✓] 虚拟机已关闭${NC}"
                break
            fi
            
            # 每10秒显示一次提示
            if [ $((i % 10)) -eq 0 ]; then
                echo -e "${YELLOW}[!] 仍在等待虚拟机关闭... (${i}s)${NC}"
                echo -e "${YELLOW}[!] 使用 --force 参数可强制关闭${NC}"
            fi
            
            sleep 1
        done
        
        # 如果虚拟机仍在运行，询问是否强制关闭
        if virsh list | grep -q "$VM_NAME"; then
            echo -e "${YELLOW}[!] 虚拟机未能在60秒内关闭${NC}"
            read -p "是否强制关闭虚拟机? (y/n): " force_shutdown
            
            if [[ "$force_shutdown" == "y" || "$force_shutdown" == "Y" ]]; then
                echo -e "${YELLOW}[!] 强制关闭虚拟机...${NC}"
                virsh destroy "$VM_NAME"
            else
                echo -e "${YELLOW}[!] 保持虚拟机运行${NC}"
                return 1
            fi
        fi
    fi
    
    # 最终检查
    if virsh list | grep -q "$VM_NAME"; then
        echo -e "${RED}[错误] 无法关闭虚拟机${NC}"
        return 1
    fi
    
    echo -e "${GREEN}[✓] 虚拟机已成功关闭${NC}"
    return 0
}

# 清理大页内存
cleanup_hugepages() {
    echo -e "${BLUE}[+] 释放大页内存...${NC}"
    echo 0 | sudo tee /proc/sys/vm/nr_hugepages > /dev/null
    echo -e "${GREEN}[✓] 大页内存已释放${NC}"
    return 0
}

# 重新附加GPU到宿主机
reattach_gpu() {
    if [ "$REATTACH_GPU" = true ]; then
        echo -e "${BLUE}[+] 重新附加GPU到宿主机...${NC}"
        
        # 调用GPU切换脚本
        sudo "$SCRIPT_DIR/switch_gpu.sh" nvidia
        
        if [ $? -ne 0 ]; then
            echo -e "${YELLOW}[!] GPU重新附加遇到问题${NC}"
            echo "您可以稍后手动运行 '$SCRIPT_DIR/gpu-manager.sh' 管理GPU驱动"
        else
            echo -e "${GREEN}[✓] GPU已重新附加到宿主机${NC}"
        fi
    fi
    
    return 0
}

# 杀死可能正在运行的Looking Glass实例
kill_looking_glass() {
    echo -e "${BLUE}[+] 检查Looking Glass进程...${NC}"
    
    if pgrep -x "looking-glass-client" > /dev/null; then
        echo -e "${YELLOW}[!] 发现正在运行的Looking Glass实例，正在关闭...${NC}"
        pkill -x "looking-glass-client"
        echo -e "${GREEN}[✓] Looking Glass进程已终止${NC}"
    fi
    
    return 0
}

# 主函数
main() {
    # 杀死正在运行的Looking Glass进程
    kill_looking_glass
    
    # 检查虚拟机是否正在运行
    if check_vm_running; then
        # 尝试停止虚拟机
        if ! stop_vm; then
            echo -e "${YELLOW}[!] 虚拟机关闭操作未完成${NC}"
            exit 1
        fi
    fi
    
    # 清理大页内存
    cleanup_hugepages
    
    # 重新附加GPU（如果请求）
    reattach_gpu
    
    echo ""
    echo -e "${GREEN}[✓] 虚拟机停止流程完成!${NC}"
    echo ""
    echo -e "${YELLOW}[i] 提示:${NC}"
    echo "1. 使用 '$SCRIPT_DIR/start_vm.sh' 启动虚拟机"
    echo "2. 使用 '$SCRIPT_DIR/gpu-manager.sh' 管理GPU驱动状态"
}

# 执行主函数
main