#!/bin/bash
# Looking Glass 测试脚本
# 用于测试Looking Glass配置是否正确

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================================="
echo " AntiCheatVM - Looking Glass 测试工具"
echo "=================================================="

# 检查共享内存文件
check_shared_memory() {
    echo -e "${BLUE}[+] 检查共享内存文件...${NC}"
    
    if [ ! -e /dev/shm/looking-glass ]; then
        echo -e "${RED}[错误] 共享内存文件不存在${NC}"
        return 1
    fi
    
    # 检查权限
    permissions=$(stat -c "%a" /dev/shm/looking-glass)
    owner=$(stat -c "%U:%G" /dev/shm/looking-glass)
    
    echo -e "  文件: /dev/shm/looking-glass"
    echo -e "  权限: $permissions"
    echo -e "  所有者: $owner"
    
    # 检查是否可写
    if [ -w /dev/shm/looking-glass ]; then
        echo -e "${GREEN}[✓] 共享内存文件权限正确${NC}"
    else
        echo -e "${RED}[错误] 共享内存文件权限错误 - 当前用户无法写入${NC}"
        return 1
    fi
    
    # 检查SELinux上下文(如果适用)
    if command -v sestatus &>/dev/null && sestatus | grep -q "enabled"; then
        echo -e "${BLUE}[+] 检查SELinux上下文...${NC}"
        context=$(ls -Z /dev/shm/looking-glass | awk '{print $1}')
        echo -e "  SELinux上下文: $context"
        
        if echo "$context" | grep -q "svirt_tmpfs_t"; then
            echo -e "${GREEN}[✓] SELinux上下文正确${NC}"
        else
            echo -e "${YELLOW}[!] SELinux上下文可能不正确${NC}"
            echo -e "${YELLOW}[!] 建议设置为svirt_tmpfs_t${NC}"
        fi
    fi
    
    return 0
}

# 检查虚拟机配置中的ivshmem设备
check_vm_config() {
    echo -e "${BLUE}[+] 检查虚拟机ivshmem配置...${NC}"
    
    # 默认虚拟机名称
    vm_name="AntiCheatVM"
    
    # 检查虚拟机是否存在
    if ! virsh list --all | grep -q "$vm_name"; then
        echo -e "${YELLOW}[!] 未找到默认虚拟机: $vm_name${NC}"
        read -p "请输入要检查的虚拟机名称: " user_vm
        
        if [ -z "$user_vm" ]; then
            echo -e "${RED}[错误] 未指定虚拟机名称${NC}"
            return 1
        fi
        
        vm_name="$user_vm"
    fi
    
    # 导出XML配置
    virsh dumpxml "$vm_name" > /tmp/vm_config.xml
    
    # 检查是否有ivshmem设备
    if grep -q "<shmem name='looking-glass'" /tmp/vm_config.xml; then
        echo -e "${GREEN}[✓] 虚拟机已配置ivshmem设备${NC}"
        
        # 提取内存大小
        mem_size=$(grep -A 2 "<shmem name='looking-glass'" /tmp/vm_config.xml | grep "size unit" | grep -o '[0-9]\+')
        echo -e "${GREEN}[i] 共享内存大小: ${mem_size}MB${NC}"
        
        # 检查模型类型
        if grep -A 1 "<shmem name='looking-glass'" /tmp/vm_config.xml | grep -q "ivshmem-plain"; then
            echo -e "${GREEN}[✓] ivshmem模型类型正确 (ivshmem-plain)${NC}"
        else
            echo -e "${YELLOW}[!] ivshmem模型类型可能不正确${NC}"
            echo -e "${YELLOW}[!] 建议使用 ivshmem-plain 类型${NC}"
        fi
    else
        echo -e "${RED}[错误] 虚拟机未配置ivshmem设备${NC}"
        echo -e "${YELLOW}[!] 请运行 looking_glass_setup.sh 脚本配置虚拟机${NC}"
        return 1
    fi
    
    # 清理临时文件
    rm /tmp/vm_config.xml
    
    return 0
}

# 检查Looking Glass客户端
check_looking_glass_client() {
    echo -e "${BLUE}[+] 检查Looking Glass客户端...${NC}"
    
    if ! command -v looking-glass-client &>/dev/null; then
        echo -e "${RED}[错误] Looking Glass客户端未安装${NC}"
        echo -e "${YELLOW}[!] 请运行 looking_glass_setup.sh 脚本安装Looking Glass${NC}"
        return 1
    fi
    
    # 获取版本信息
    version=$(looking-glass-client --version 2>&1)
    echo -e "${GREEN}[✓] Looking Glass客户端已安装${NC}"
    echo -e "${GREEN}[i] 版本信息: $version${NC}"
    
    return 0
}

# 检查虚拟机运行状态
check_vm_running() {
    echo -e "${BLUE}[+] 检查虚拟机运行状态...${NC}"
    
    # 默认虚拟机名称
    vm_name="AntiCheatVM"
    
    # 检查虚拟机是否存在
    if ! virsh list --all | grep -q "$vm_name"; then
        echo -e "${YELLOW}[!] 未找到默认虚拟机: $vm_name${NC}"
        read -p "请输入要检查的虚拟机名称: " user_vm
        
        if [ -z "$user_vm" ]; then
            echo -e "${RED}[错误] 未指定虚拟机名称${NC}"
            return 1
        fi
        
        vm_name="$user_vm"
    fi
    
    # 检查虚拟机是否运行
    if virsh list | grep -q "$vm_name"; then
        echo -e "${GREEN}[✓] 虚拟机 $vm_name 正在运行${NC}"
        return 0
    else
        echo -e "${YELLOW}[!] 虚拟机 $vm_name 未运行${NC}"
        echo -e "${YELLOW}[!] 请先启动虚拟机以测试Looking Glass${NC}"
        return 1
    fi
}

# 尝试启动Looking Glass
test_looking_glass() {
    echo -e "${BLUE}[+] 尝试启动Looking Glass客户端...${NC}"
    
    # 检查前置条件
    if ! check_shared_memory || ! check_vm_config || ! check_looking_glass_client || ! check_vm_running; then
        echo -e "${RED}[错误] 前置条件检查失败，无法测试Looking Glass${NC}"
        return 1
    fi
    
    echo -e "${GREEN}[✓] 所有检查通过，正在启动Looking Glass...${NC}"
    echo -e "${YELLOW}[!] 如果虚拟机中的Looking Glass主机应用程序未运行，将会失败${NC}"
    echo -e "${YELLOW}[!] 按Ctrl+C关闭Looking Glass${NC}"
    
    # 等待用户确认
    read -p "按回车键启动Looking Glass..." dummy
    
    # 启动Looking Glass
    looking-glass-client -s -m 97
    
    return 0
}

# 主函数
main() {
    # 显示菜单
    echo "请选择一个操作:"
    echo "1) 检查Looking Glass配置"
    echo "2) 测试Looking Glass连接"
    echo "3) 退出"
    read -p "请选择 [1-3]: " choice
    
    case $choice in
        1)
            check_shared_memory
            check_vm_config
            check_looking_glass_client
            ;;
        2)
            test_looking_glass
            ;;
        3)
            echo -e "${GREEN}[i] 退出程序${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}[错误] 无效的选择${NC}"
            ;;
    esac
}

# 执行主函数
main