#!/bin/bash
# 修复GRUB配置文件
# 此脚本将恢复GRUB配置并清理之前失败的修改

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

echo "=================================================="
echo " AntiCheatVM GRUB 配置修复工具"
echo "=================================================="

# 检查是否有GRUB备份文件
if [ -f /etc/default/grub.backup ]; then
    echo -e "${BLUE}[+] 找到GRUB配置备份文件${NC}"
    cp /etc/default/grub.backup /etc/default/grub
    echo -e "${GREEN}[✓] 已从备份恢复GRUB配置${NC}"
else
    echo -e "${YELLOW}[!] 未找到GRUB配置备份文件${NC}"
    echo -e "${BLUE}[+] 创建标准GRUB配置...${NC}"
    
    # 获取当前的cmdline参数（除去已有的VFIO和IOMMU相关参数）
    current_cmdline=$(cat /proc/cmdline | sed 's/BOOT_IMAGE=[^ ]* //g' | sed 's/intel_iommu=[^ ]* //g' | sed 's/amd_iommu=[^ ]* //g' | sed 's/iommu=[^ ]* //g' | sed 's/rd\.driver\.pre=[^ ]* //g' | sed 's/vfio-pci\.ids=[^ ]* //g' | sed 's/modprobe\.blacklist=[^ ]* //g' | sed 's/rd\.driver\.blacklist=[^ ]* //g')
    
    # 创建简化的GRUB配置
    cat > /etc/default/grub << EOF
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="$current_cmdline"
GRUB_DISABLE_RECOVERY="true"
GRUB_ENABLE_BLSCFG=true
EOF
    
    echo -e "${GREEN}[✓] 已创建新的GRUB配置${NC}"
fi

# 更新GRUB
echo -e "${BLUE}[+] 更新GRUB引导...${NC}"
if [ -f /boot/grub2/grub.cfg ]; then
    grub2-mkconfig -o /boot/grub2/grub.cfg
elif [ -f /boot/grub/grub.cfg ]; then
    grub-mkconfig -o /boot/grub/grub.cfg
else
    echo -e "${RED}[错误] 找不到GRUB配置文件${NC}"
    exit 1
fi

echo -e "${GREEN}[✓] GRUB已更新${NC}"
echo -e "${YELLOW}[i] 建议重新运行setup_vfio.sh来正确配置VFIO参数${NC}"

# 检查/etc/dracut.conf.d/目录中是否有VFIO相关文件，如果有则清理
if [ -f /etc/dracut.conf.d/local.conf ]; then
    echo -e "${BLUE}[+] 清理dracut VFIO配置...${NC}"
    rm -f /etc/dracut.conf.d/local.conf
    echo -e "${GREEN}[✓] dracut配置已清理${NC}"
fi

echo -e "${GREEN}[✓] GRUB修复完成${NC}"
echo ""
echo -e "${YELLOW}[i] 现在您可以安全地运行 setup_vfio.sh 脚本${NC}"