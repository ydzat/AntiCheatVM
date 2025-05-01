#!/bin/bash
# Looking Glass 设置脚本
# 根据教程创建，确保正确配置共享内存和ivshmem设备

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 检查是否以root身份运行
if [ "$(id -u)" -eq 0 ]; then
    echo -e "${RED}[错误] 此脚本不应以root权限运行${NC}"
    echo "请不要使用sudo运行此脚本"
    exit 1
fi

echo "=================================================="
echo " AntiCheatVM - Looking Glass 配置工具"
echo "=================================================="

# 检查依赖安装
check_dependencies() {
    echo -e "${BLUE}[+] 检查Looking Glass依赖...${NC}"
    
    # 检测操作系统
    if [ -f /etc/fedora-release ]; then
        OS_TYPE="fedora"
    elif [ -f /etc/debian_version ]; then
        OS_TYPE="debian"
    elif [ -f /etc/arch-release ]; then
        OS_TYPE="arch"
    else
        OS_TYPE="unknown"
    fi
    
    # 设置依赖列表
    local dependencies
    case $OS_TYPE in
        fedora)
            dependencies=(
                "cmake" "gcc" "gcc-c++" "libglvnd-devel" "fontconfig-devel" 
                "spice-protocol" "make" "nettle-devel" "pkgconf-pkg-config" 
                "binutils-devel" "libXi-devel" "libXinerama-devel" 
                "libXcursor-devel" "libXpresent-devel" "libxkbcommon-x11-devel" 
                "wayland-devel" "wayland-protocols-devel" "libXScrnSaver-devel" 
                "libXrandr-devel" "dejavu-sans-mono-fonts" "pipewire-devel"
                "libsamplerate-devel" "pulseaudio-libs-devel"
            )
            ;;
        debian)
            dependencies=(
                "cmake" "gcc" "g++" "libegl-dev" "libgl-dev" "libgles-dev" 
                "libfontconfig-dev" "libgmp-dev" "libspice-protocol-dev" 
                "make" "nettle-dev" "pkg-config" "binutils-dev" "libx11-dev" 
                "libxfixes-dev" "libxi-dev" "libxinerama-dev" "libxss-dev" 
                "libxcursor-dev" "libxpresent-dev" "libxkbcommon-dev" 
                "libwayland-bin" "libwayland-dev" "wayland-protocols" 
                "libpipewire-0.3-dev" "libsamplerate0-dev" "libpulse-dev" 
                "fonts-dejavu-core"
            )
            ;;
        arch)
            dependencies=(
                "cmake" "gcc" "fontconfig" "nettle" "spice-protocol" 
                "make" "pkgconf" "binutils" "libxi" "libxinerama" 
                "libxcursor" "libxss" "libxpresent" "libxkbcommon" 
                "wayland" "wayland-protocols" "pipewire" "libsamplerate" 
                "ttf-dejavu"
            )
            ;;
        *)
            echo -e "${RED}[错误] 不支持的操作系统类型: $OS_TYPE${NC}"
            echo "请手动安装Looking Glass依赖"
            return 1
            ;;
    esac
    
    # 检查缺失的依赖
    local missing_deps=()
    for dep in "${dependencies[@]}"; do
        case $OS_TYPE in
            fedora)
                if ! rpm -q "$dep" &>/dev/null; then
                    missing_deps+=("$dep")
                fi
                ;;
            debian)
                if ! dpkg-query -W -f='${Status}' "$dep" 2>/dev/null | grep -q "ok installed"; then
                    missing_deps+=("$dep")
                fi
                ;;
            arch)
                if ! pacman -Q "$dep" &>/dev/null; then
                    missing_deps+=("$dep")
                fi
                ;;
        esac
    done
    
    # 如果有缺失的依赖，询问是否安装
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${YELLOW}[!] 缺少以下依赖: ${missing_deps[*]}${NC}"
        read -p "是否安装缺失的依赖? (y/n): " install_deps
        
        if [[ "$install_deps" == "y" || "$install_deps" == "Y" ]]; then
            echo -e "${BLUE}[+] 安装缺失的依赖...${NC}"
            
            case $OS_TYPE in
                fedora)
                    sudo dnf install -y "${missing_deps[@]}"
                    ;;
                debian)
                    sudo apt-get update
                    sudo apt-get install -y "${missing_deps[@]}"
                    ;;
                arch)
                    sudo pacman -Sy --needed "${missing_deps[@]}"
                    ;;
            esac
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}[✓] 所有依赖安装完成${NC}"
            else
                echo -e "${RED}[错误] 依赖安装失败${NC}"
                return 1
            fi
        else
            echo -e "${YELLOW}[!] 跳过依赖安装，继续执行${NC}"
        fi
    else
        echo -e "${GREEN}[✓] 所有必要的依赖已安装${NC}"
    fi
    
    return 0
}

# 设置共享内存
setup_shared_memory() {
    echo -e "${BLUE}[+] 配置Looking Glass共享内存...${NC}"
    
    # 创建共享内存文件
    echo -e "${BLUE}[+] 创建共享内存文件...${NC}"
    if [ -e /dev/shm/looking-glass ]; then
        echo -e "${YELLOW}[!] 共享内存文件已存在，正在重新配置...${NC}"
        sudo rm -f /dev/shm/looking-glass
    fi
    
    # 创建共享内存文件
    sudo touch /dev/shm/looking-glass
    sudo chown $USER:qemu /dev/shm/looking-glass
    sudo chmod 0660 /dev/shm/looking-glass
    
    # 检查是否创建成功
    if [ -e /dev/shm/looking-glass ] && [ -w /dev/shm/looking-glass ]; then
        echo -e "${GREEN}[✓] 共享内存文件创建成功${NC}"
    else
        echo -e "${RED}[错误] 共享内存文件创建失败${NC}"
        return 1
    fi
    
    # 为SELinux设置正确的上下文
    if command -v semanage &> /dev/null; then
        echo -e "${BLUE}[+] 配置SELinux上下文...${NC}"
        sudo semanage fcontext -a -t svirt_tmpfs_t /dev/shm/looking-glass
        sudo restorecon -v /dev/shm/looking-glass
        echo -e "${GREEN}[✓] SELinux上下文已配置${NC}"
    fi
    
    # 创建tmpfiles.d配置文件以在重启后持久化
    echo -e "${BLUE}[+] 创建持久化配置...${NC}"
    echo "f /dev/shm/looking-glass 0660 $USER qemu -" | sudo tee /etc/tmpfiles.d/10-looking-glass.conf > /dev/null
    echo -e "${GREEN}[✓] 持久化配置已创建${NC}"
    
    return 0
}

# 下载并安装Looking Glass
install_looking_glass() {
    echo -e "${BLUE}[+] 下载并安装Looking Glass...${NC}"
    
    # 创建临时目录
    tmp_dir=$(mktemp -d)
    echo -e "${BLUE}[+] 使用临时目录: $tmp_dir${NC}"
    
    # 询问用户是否下载源代码
    read -p "是否下载并编译Looking Glass最新版本? (y/n): " download_source
    
    if [[ "$download_source" == "y" || "$download_source" == "Y" ]]; then
        # 下载稳定版Looking Glass
        echo -e "${BLUE}[+] 下载Looking Glass源码...${NC}"
        wget https://looking-glass.io/artifact/stable/source -O $tmp_dir/looking-glass.tar.gz
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}[错误] 下载失败${NC}"
            rm -rf $tmp_dir
            return 1
        fi
        
        # 解压源码
        echo -e "${BLUE}[+] 解压源码...${NC}"
        cd $tmp_dir
        tar -xzvf looking-glass.tar.gz
        
        # 查找解压后的目录
        lg_dir=$(find . -maxdepth 1 -type d -name "looking-glass-*" | head -1)
        if [ -z "$lg_dir" ]; then
            echo -e "${RED}[错误] 解压后无法找到Looking Glass目录${NC}"
            rm -rf $tmp_dir
            return 1
        fi
        
        # 切换到源码目录
        cd $lg_dir
        
        # 创建构建目录并编译
        echo -e "${BLUE}[+] 编译Looking Glass客户端...${NC}"
        mkdir -p client/build
        cd client/build
        cmake ../
        make -j$(nproc)
        
        # 检查编译是否成功
        if [ $? -ne 0 ]; then
            echo -e "${RED}[错误] 编译失败${NC}"
            rm -rf $tmp_dir
            return 1
        fi
        
        # 安装客户端
        echo -e "${BLUE}[+] 安装Looking Glass客户端...${NC}"
        sudo make install
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}[错误] 安装失败${NC}"
            rm -rf $tmp_dir
            return 1
        fi
        
        echo -e "${GREEN}[✓] Looking Glass客户端安装完成${NC}"
    else
        echo -e "${YELLOW}[!] 跳过Looking Glass安装${NC}"
        echo -e "${YELLOW}[!] 请确保Looking Glass客户端已安装${NC}"
    fi
    
    # 清理临时文件
    rm -rf $tmp_dir
    
    # 测试Looking Glass是否可用
    if command -v looking-glass-client &> /dev/null; then
        echo -e "${GREEN}[✓] Looking Glass客户端可用${NC}"
        looking_glass_version=$(looking-glass-client --version)
        echo -e "${GREEN}[i] 版本信息: $looking_glass_version${NC}"
    else
        echo -e "${RED}[错误] Looking Glass客户端不可用${NC}"
        echo -e "${YELLOW}[!] 您可能需要手动安装Looking Glass${NC}"
        return 1
    fi
    
    return 0
}

# 配置虚拟机XML添加ivshmem设备
configure_vm() {
    echo -e "${BLUE}[+] 配置虚拟机以支持ivshmem设备...${NC}"
    
    # 检查VM是否存在
    if ! virsh list --all | grep -q "AntiCheatVM"; then
        echo -e "${YELLOW}[!] 未找到AntiCheatVM虚拟机${NC}"
        read -p "请输入要配置的虚拟机名称: " vm_name
        
        if [ -z "$vm_name" ]; then
            echo -e "${RED}[错误] 未指定虚拟机名称${NC}"
            return 1
        fi
    else
        vm_name="AntiCheatVM"
    fi
    
    # 导出虚拟机XML配置
    echo -e "${BLUE}[+] 导出虚拟机配置...${NC}"
    
    vm_xml_path="$SCRIPT_DIR/vms/${vm_name}.xml"
    virsh dumpxml $vm_name > "$vm_xml_path"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}[错误] 无法导出虚拟机配置${NC}"
        return 1
    fi
    
    # 创建备份
    cp "$vm_xml_path" "${vm_xml_path}.backup"
    
    # 检查是否已配置ivshmem
    if grep -q "<shmem name='looking-glass'" "$vm_xml_path"; then
        echo -e "${YELLOW}[!] 虚拟机已配置ivshmem设备${NC}"
        
        # 询问是否更新配置
        read -p "是否更新ivshmem配置? (y/n): " update_config
        
        if [[ "$update_config" != "y" && "$update_config" != "Y" ]]; then
            echo -e "${YELLOW}[!] 跳过ivshmem配置${NC}"
            return 0
        fi
    fi
    
    # 设置共享内存大小
    read -p "请输入共享内存大小 (MB，推荐: 32): " memory_size
    memory_size=${memory_size:-32}
    
    # 检查是否有devices部分
    if ! grep -q "</devices>" "$vm_xml_path"; then
        echo -e "${RED}[错误] 虚拟机配置中未找到devices部分${NC}"
        return 1
    fi
    
    # 移除现有的ivshmem配置（如果有）
    sed -i '/<shmem name/,/<\/shmem>/d' "$vm_xml_path"
    
    # 添加ivshmem配置
    sed -i '/<\/devices>/i \  <shmem name="looking-glass">\n    <model type="ivshmem-plain"/>\n    <size unit="M">'$memory_size'</size>\n  </shmem>' "$vm_xml_path"
    
    echo -e "${GREEN}[✓] ivshmem设备已添加到虚拟机配置${NC}"
    
    # 重新定义虚拟机
    echo -e "${BLUE}[+] 重新定义虚拟机配置...${NC}"
    virsh define "$vm_xml_path"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}[错误] 虚拟机配置更新失败${NC}"
        echo -e "${YELLOW}[!] 您可能需要手动更新虚拟机配置${NC}"
        return 1
    fi
    
    echo -e "${GREEN}[✓] 虚拟机配置已更新${NC}"
    
    return 0
}

# 配置用户环境设置
configure_user_env() {
    echo -e "${BLUE}[+] 配置用户环境设置...${NC}"
    
    # 创建配置目录
    mkdir -p ~/.config/looking-glass
    
    # 创建默认配置文件
    cat > ~/.config/looking-glass/client.ini << EOF
[app]
shmFile=/dev/shm/looking-glass
renderer=auto

[win]
fullScreen=no
scale=100
quickSplash=yes
showFPS=no

[input]
grabKeyboard=yes
rawMouse=yes
escapeKey=97  # Right Control key
EOF
    
    # 创建别名文件或添加到现有别名文件
    if ! grep -q "alias looking-glass=" "$SCRIPT_DIR/aliases.sh" 2>/dev/null; then
        echo -e "\n# Looking Glass 别名" >> "$SCRIPT_DIR/aliases.sh"
        echo "alias looking-glass='looking-glass-client -s -m 97'" >> "$SCRIPT_DIR/aliases.sh"
        
        # 提醒用户添加到.bashrc
        echo -e "${YELLOW}[!] 请将以下行添加到您的 ~/.bashrc 文件:${NC}"
        echo -e "${YELLOW}    source $SCRIPT_DIR/aliases.sh${NC}"
    fi
    
    echo -e "${GREEN}[✓] 用户环境配置完成${NC}"
    
    return 0
}

# 创建主机端帮助指南
create_host_guide() {
    echo -e "${BLUE}[+] 创建Windows主机端帮助指南...${NC}"
    
    cat > "$SCRIPT_DIR/LOOKING_GLASS_HOST_SETUP.md" << EOF
# Windows Looking Glass 主机设置指南

## 1. 下载与安装

1. 从官方网站下载 Looking Glass 主机应用程序:
   https://looking-glass.io/artifact/stable/host

2. 在Windows虚拟机中运行下载的安装程序

3. 在安装过程中确保选中"Install IVSHMEM Driver"选项

## 2. 配置IVSHMEM驱动

如果在设备管理器中看到未识别的"PCI标准RAM控制器":

1. 打开设备管理器（右键点击开始菜单 -> 设备管理器）
2. 找到带有黄色感叹号的"PCI标准RAM控制器"
3. 右键点击并选择"更新驱动程序"
4. 选择"浏览计算机以查找驱动程序"
5. 浏览到 \`C:\\Program Files\\Looking Glass (host)\\ivshmem\`
6. 完成驱动安装

## 3. 配置Looking Glass主机服务

1. 安装完成后，Looking Glass服务应自动启动
2. 从开始菜单打开Looking Glass主机应用程序
3. 确认"Service State"显示为"Running"
4. 确认"IVSHMEM"部分显示正确的内存大小（如32MB）

## 4. 优化设置

为获得最佳性能:

1. 对于NVIDIA显卡:
   - 确保"NvFBC"选项已启用
   
2. 对于AMD显卡:
   - 尝试不同的捕获方式（默认、GDI等）

3. 设置Windows自动登录以便无人值守启动:
   - 打开运行窗口（Win+R）
   - 输入 \`netplwiz\` 并运行
   - 取消选中"用户必须输入用户名和密码"
   - 输入登录凭据并确认

## 5. 故障排除

如果遇到问题:

- 重启虚拟机后再次尝试
- 确认您的GPU驱动是最新版本
- 检查Windows事件查看器中的错误
- 确认ivshmem设备显示在设备管理器中

更多帮助请访问: https://looking-glass.io/docs
EOF
    
    echo -e "${GREEN}[✓] 主机端帮助指南已创建: $SCRIPT_DIR/LOOKING_GLASS_HOST_SETUP.md${NC}"
    
    return 0
}

# 配置鼠标和键盘直通
configure_input_passthrough() {
    echo -e "${BLUE}[+] 配置鼠标和键盘直通...${NC}"
    
    # 查找输入设备
    echo -e "${BLUE}[+] 查找输入设备...${NC}"
    echo "可用的输入设备:"
    echo "-------------------"
    
    # 列出可用的输入设备
    ls -l /dev/input/by-id/ | grep -v '\-\->' | awk '{print $NF}' > /tmp/input_devices.txt
    count=1
    while read device; do
        echo "[$count] $device"
        count=$((count + 1))
    done < /tmp/input_devices.txt
    
    # 如果找不到设备
    if [ $count -eq 1 ]; then
        echo -e "${YELLOW}[!] 未找到输入设备${NC}"
        echo -e "${YELLOW}[!] 尝试使用by-path方式查找${NC}"
        
        ls -l /dev/input/by-path/ | grep -v '\-\->' | grep -i -E 'kbd|mouse' | awk '{print $NF}' > /tmp/input_devices.txt
        count=1
        while read device; do
            echo "[$count] $device"
            count=$((count + 1))
        done < /tmp/input_devices.txt
        
        if [ $count -eq 1 ]; then
            echo -e "${RED}[错误] 无法找到任何输入设备${NC}"
            return 1
        fi
        
        device_list_source="by-path"
    else
        device_list_source="by-id"
    fi
    
    # 询问用户选择键盘
    read -p "请选择键盘设备编号: " kbd_num
    
    if [[ ! "$kbd_num" =~ ^[0-9]+$ ]] || [ "$kbd_num" -lt 1 ] || [ "$kbd_num" -gt $((count-1)) ]; then
        echo -e "${RED}[错误] 无效的选择${NC}"
        return 1
    fi
    
    kbd_device=$(sed -n "${kbd_num}p" /tmp/input_devices.txt)
    echo -e "${GREEN}[✓] 已选择键盘: $kbd_device${NC}"
    
    # 询问用户选择鼠标
    read -p "请选择鼠标设备编号: " mouse_num
    
    if [[ ! "$mouse_num" =~ ^[0-9]+$ ]] || [ "$mouse_num" -lt 1 ] || [ "$mouse_num" -gt $((count-1)) ]; then
        echo -e "${RED}[错误] 无效的选择${NC}"
        return 1
    fi
    
    mouse_device=$(sed -n "${mouse_num}p" /tmp/input_devices.txt)
    echo -e "${GREEN}[✓] 已选择鼠标: $mouse_device${NC}"
    
    # 检查VM是否存在
    if ! virsh list --all | grep -q "AntiCheatVM"; then
        echo -e "${YELLOW}[!] 未找到AntiCheatVM虚拟机${NC}"
        read -p "请输入要配置的虚拟机名称: " vm_name
        
        if [ -z "$vm_name" ]; then
            echo -e "${RED}[错误] 未指定虚拟机名称${NC}"
            return 1
        fi
    else
        vm_name="AntiCheatVM"
    fi
    
    # 导出虚拟机XML配置
    echo -e "${BLUE}[+] 更新虚拟机配置...${NC}"
    
    vm_xml_path="$SCRIPT_DIR/vms/${vm_name}.xml"
    virsh dumpxml $vm_name > "$vm_xml_path"
    
    # 创建备份
    cp "$vm_xml_path" "${vm_xml_path}.backup"
    
    # 移除现有的输入设备配置
    sed -i '/<input type="evdev"/,/<\/input>/d' "$vm_xml_path"
    
    # 添加输入设备配置
    sed -i '/<\/devices>/i \  <input type="evdev">\n    <source dev="/dev/input/'"$device_list_source"'/'"$mouse_device"'"/>\n  </input>\n  <input type="evdev">\n    <source dev="/dev/input/'"$device_list_source"'/'"$kbd_device"'" grab="all" grabToggle="ctrl-ctrl" repeat="on"/>\n  </input>' "$vm_xml_path"
    
    # 移除tablet设备（避免输入冲突）
    sed -i '/<input type="tablet"/,/<\/input>/d' "$vm_xml_path"
    
    # 重新定义虚拟机
    echo -e "${BLUE}[+] 重新定义虚拟机配置...${NC}"
    virsh define "$vm_xml_path"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}[错误] 虚拟机配置更新失败${NC}"
        echo -e "${YELLOW}[!] 您可能需要手动更新虚拟机配置${NC}"
        return 1
    fi
    
    echo -e "${GREEN}[✓] 输入设备直通配置完成${NC}"
    
    return 0
}

# 主函数
main() {
    # 检查依赖
    check_dependencies || exit 1
    
    # 设置共享内存
    setup_shared_memory || exit 1
    
    # 安装Looking Glass
    install_looking_glass || exit 1
    
    # 配置虚拟机
    configure_vm || exit 1
    
    # 配置用户环境
    configure_user_env || exit 1
    
    # 创建主机端帮助指南
    create_host_guide || exit 1
    
    # 询问是否配置输入直通
    read -p "是否配置鼠标和键盘直通? (y/n): " configure_input
    
    if [[ "$configure_input" == "y" || "$configure_input" == "Y" ]]; then
        configure_input_passthrough || echo -e "${YELLOW}[!] 输入设备直通配置失败，可以稍后再试${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}[✓] Looking Glass配置完成!${NC}"
    echo ""
    echo -e "${YELLOW}[i] 接下来:${NC}"
    echo "1. 启动您的Windows虚拟机"
    echo "2. 按照 $SCRIPT_DIR/LOOKING_GLASS_HOST_SETUP.md 的指南在Windows中设置Looking Glass"
    echo "3. 启动Looking Glass客户端命令: looking-glass-client -s -m 97"
    echo "4. 或者，如果您已添加别名: looking-glass"
}

# 执行主函数
main