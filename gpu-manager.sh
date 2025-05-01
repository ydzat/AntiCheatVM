#!/bin/bash
# GPU管理器 - 为使用AntiCheatVM的用户提供友好的GPU管理界面

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 显示GPU状态
show_status() {
    echo -e "${BLUE}[i] 当前状态:${NC}"
    sudo "$SCRIPT_DIR/switch_gpu.sh" status
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
    
    case $choice in
        1)
            echo -e "${BLUE}[+] 切换GPU到宿主机模式...${NC}"
            sudo "$SCRIPT_DIR/switch_gpu.sh" nvidia
            read -p "按回车键继续..." dummy
            show_menu
            ;;
        2)
            echo -e "${BLUE}[+] 切换GPU到VM直通模式...${NC}"
            sudo "$SCRIPT_DIR/switch_gpu.sh" vfio
            read -p "按回车键继续..." dummy
            show_menu
            ;;
        3)
            echo -e "${GREEN}[i] 退出程序${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}[错误] 无效的选项${NC}"
            read -p "按回车键继续..." dummy
            show_menu
            ;;
    esac
}

# 启动主菜单
show_menu
