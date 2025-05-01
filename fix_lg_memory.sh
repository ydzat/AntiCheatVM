#!/bin/bash
# Looking Glass 共享内存修复脚本
# 此脚本设置正确的权限给 Looking Glass 共享内存文件

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 设置共享内存大小 (MB)
SIZE=${1:-32}
USERNAME=$(logname)

# 检查是否以root身份运行
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[错误] 此脚本需要以root权限运行${NC}"
    echo "请使用sudo运行此脚本"
    exit 1
fi

echo "=================================================="
echo " Looking Glass 共享内存设置 "
echo "=================================================="

# 删除旧的共享内存文件（如果存在）
if [ -e "/dev/shm/looking-glass" ]; then
    echo -e "${BLUE}[+] 移除旧的共享内存文件...${NC}"
    rm -f /dev/shm/looking-glass
fi

# 创建新的共享内存文件并设置大小
echo -e "${BLUE}[+] 创建共享内存文件 (${SIZE}MB)...${NC}"
dd if=/dev/zero of=/dev/shm/looking-glass bs=1M count=$SIZE status=progress
echo -e "${GREEN}[✓] 共享内存文件已创建并预分配${NC}"

# 设置权限
echo -e "${BLUE}[+] 设置权限...${NC}"
chown $USERNAME:qemu /dev/shm/looking-glass
chmod 0660 /dev/shm/looking-glass

# 显示结果
ls -la /dev/shm/looking-glass
echo -e "${GREEN}[✓] Looking Glass 共享内存已设置完成!${NC}"
echo ""
echo -e "${YELLOW}[i] 提示:${NC}"
echo "1. 运行VM前执行: sudo $0"
echo "2. 启动虚拟机: ./start_vm.sh --lg"