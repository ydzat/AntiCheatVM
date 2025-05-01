# Looking Glass 配置与使用指南

本文档提供了在AntiCheatVM环境下安装、配置和使用Looking Glass的详细指南。

## 什么是Looking Glass?

Looking Glass是一个开源的项目，允许您通过共享内存实现近乎零延迟地查看和控制虚拟机的图形输出。它非常适合GPU直通场景，无需连接额外的物理显示器到直通的GPU上。

## 1. 安装Looking Glass

### 1.1 使用自动安装脚本

最简单的方式是使用项目提供的自动安装脚本：

```bash
# 运行Looking Glass设置脚本
sudo chmod +x ./looking_glass_setup.sh
./looking_glass_setup.sh
```

### 1.2 手动安装

如果自动安装脚本不适合您，可以按照以下步骤手动安装：

#### 1.2.1 安装依赖

在Fedora上：

```bash
sudo dnf install cmake gcc gcc-c++ libglvnd-devel fontconfig-devel spice-protocol make nettle-devel \
                 pkgconf-pkg-config binutils-devel libXi-devel libXinerama-devel libXcursor-devel \
                 libXpresent-devel libxkbcommon-x11-devel wayland-devel wayland-protocols-devel \
                 libXScrnSaver-devel libXrandr-devel dejavu-sans-mono-fonts \
                 pipewire-devel libsamplerate-devel pulseaudio-libs-devel
```

#### 1.2.2 下载并编译Looking Glass

```bash
# 下载Looking Glass源代码
wget https://looking-glass.io/artifact/stable/source -O looking-glass.tar.gz
tar -xzf looking-glass.tar.gz
cd looking-glass-B6

# 编译客户端
mkdir -p client/build
cd client/build
cmake ../
make -j$(nproc)

# 安装客户端
sudo make install
```

## 2. 配置Looking Glass

### 2.1 设置共享内存

```bash
# 创建共享内存文件
sudo touch /dev/shm/looking-glass
sudo chown $USER:qemu /dev/shm/looking-glass
sudo chmod 0660 /dev/shm/looking-glass

# 设置SELinux上下文（仅适用于启用了SELinux的系统）
sudo semanage fcontext -a -t svirt_tmpfs_t /dev/shm/looking-glass
sudo restorecon -v /dev/shm/looking-glass

# 创建持久化配置
echo "f /dev/shm/looking-glass 0660 $USER qemu -" | sudo tee /etc/tmpfiles.d/10-looking-glass.conf
```

### 2.2 配置虚拟机

确保您的虚拟机XML配置文件包含以下配置（通常位于`<devices>`部分）：

```xml
<shmem name='looking-glass'>
  <model type='ivshmem-plain'/>
  <size unit='M'>64</size>
</shmem>
```

您可以使用以下命令检查：

```bash
virsh dumpxml AntiCheatVM | grep -A 4 shmem
```

如果需要添加该配置，可以使用以下命令：

```bash
virsh edit AntiCheatVM
```

## 3. Windows虚拟机中的设置

### 3.1 下载Looking Glass Host

在Windows虚拟机中，需要安装Looking Glass Host应用程序：

1. 下载最新的主机应用：https://looking-glass.io/artifact/stable/host
2. 在Windows虚拟机中安装下载的应用程序
3. 安装时，确保已选择"安装IVSHMEM驱动"选项

### 3.2 配置Looking Glass Host

1. 安装完成后，从开始菜单打开Looking Glass Host
2. 确认服务状态为"Running"
3. 确认IVSHMEM显示有效的内存大小（例如32MB或64MB）
4. 如使用NVIDIA显卡，确保启用了NvFBC选项

### 3.3 Windows优化建议

为了获得最佳体验，建议在Windows虚拟机中进行以下设置：

1. 安装最新的显卡驱动
2. 在任务管理器中将"Looking Glass (host)"服务设置为高优先级
3. 禁用Windows的视觉效果以减少资源占用
4. 启用Windows自动登录以实现无人值守启动

## 4. 使用Looking Glass

### 4.1 启动客户端

在主机系统中，可以使用以下命令启动Looking Glass客户端：

```bash
# 使用默认设置
looking-glass-client

# 使用项目预设别名（推荐，配置右Ctrl为切换键）
looking-glass

# 全屏模式
looking-glass-client -f

# 指定位置和大小
looking-glass-client -p 30 -s
```

### 4.2 快捷键

Looking Glass提供了多种快捷键，以下是最常用的：

- **右Ctrl**：切换鼠标和键盘捕获（通过别名设置）
- **Scroll Lock**：切换鼠标和键盘捕获（默认）
- **Left Ctrl+Left Alt+F**：切换全屏模式
- **Left Ctrl+Left Alt+X**：退出Looking Glass
- **Left Ctrl+Left Alt+R**：重新连接到主机

### 4.3 性能优化

1. 检查共享内存设置是否正确：

```bash
ls -la /dev/shm/looking-glass
```

2. 如果您使用Wayland，请使用特殊选项：

```bash
looking-glass-client -W wl -F input:rawMouse=yes
```

3. 启用性能统计查看运行情况：

```bash
looking-glass-client -K stats:show=yes
```

## 5. 故障排除

### 5.1 无法连接到共享内存

如果出现"Failed to map the shared memory file"错误：

```bash
# 重新设置共享内存文件权限
sudo chmod 0660 /dev/shm/looking-glass
sudo chown $USER:qemu /dev/shm/looking-glass

# 检查组权限
groups | grep qemu
# 如果没有qemu组，添加用户到qemu组
sudo usermod -a -G qemu $USER
# 然后重新登录使权限生效
```

### 5.2 Windows中驱动问题

如果在Windows设备管理器中看到未识别的"PCI标准RAM控制器"：

1. 打开设备管理器
2. 右键点击"PCI标准RAM控制器"，选择"更新驱动程序"
3. 选择"浏览计算机以查找驱动程序"
4. 浏览到`C:\Program Files\Looking Glass (host)\ivshmem`
5. 点击"下一步"完成安装

### 5.3 性能问题

如果遇到性能问题：

1. 确保Windows虚拟机中的Looking Glass Host使用了NvFBC（适用于NVIDIA卡）
2. 检查CPU使用率，如果较高可能需要增加虚拟机的CPU资源
3. 尝试使用不同的视频格式选项：

```bash
looking-glass-client -F egl:vsync=no
```

## 6. 常见命令

```bash
# 检查Looking Glass版本
looking-glass-client --version

# 显示所有配置选项
looking-glass-client --help

# 使用特定配置文件
looking-glass-client -C ~/my-config.conf

# 指定共享内存文件
looking-glass-client -f /dev/shm/looking-glass

# 设置窗口位置和大小
looking-glass-client -p 30 -y 10 -X 1920 -Y 1080
```