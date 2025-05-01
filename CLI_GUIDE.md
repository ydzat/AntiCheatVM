# AntiCheatVM 命令行使用指南

本文档提供了使用AntiCheatVM在Fedora上进行GPU直通虚拟化的完整命令行指南。

## 简介

AntiCheatVM设计用于创建一个隔离的Windows虚拟机环境，通过直通NVIDIA GPU来运行需要高性能图形处理的游戏，同时避免反作弊软件的检测。

### 系统要求

- Fedora Linux (本指南基于Fedora 41)
- 支持IOMMU的CPU
- 双显卡配置(一个集成显卡，如Intel HD Graphics，和一个独立NVIDIA显卡)
- 足够的内存供主机和虚拟机使用
- 已启用UEFI中的虚拟化选项(VT-d/AMD-V及IOMMU)

## 1. 初始设置

如果您是首次设置系统，请按照以下步骤进行操作：

```bash
# 安装必要的虚拟化软件包
sudo dnf groupinstall --with-optional virtualization

# 确保系统已更新到最新
sudo dnf update

# 授予当前用户访问libvirt的权限
sudo usermod -a -G libvirt $(whoami)
sudo usermod -a -G qemu $(whoami)

# 启用并启动libvirt服务
sudo systemctl enable libvirtd
sudo systemctl start libvirtd

# 安装显卡切换脚本
./install.sh

# 让别名立即生效
source ~/.bashrc
```

## 2. GPU直通准备

### 2.1 查看系统GPU信息

```bash
# 使用别名查看GPU状态
hows-my-gpu

# 或使用脚本查看详细状态
sudo ./gpu-manager.sh status
```

### 2.2 切换GPU到VM模式

在图形界面下：

```bash
# 使用别名切换GPU
gpu-to-vm
```

切换完成后，系统将切换到命令行模式。**注意：在切换过程中显示会暂时黑屏，这是正常的。**

## 3. 启动虚拟机

在命令行模式下，执行以下命令启动虚拟机：

```bash
# 使用别名启动虚拟机
start-vm

# 或使用选项启动
./start_vm.sh --evdev  # 启用键鼠直通
```

### 3.1 使用Looking Glass

虚拟机启动后，Looking Glass客户端将自动启动。如果没有自动启动，可以手动启动：

```bash
# 使用别名启动Looking Glass
vm-display
```

#### Looking Glass快捷键

- **右Ctrl键**：在主机和虚拟机之间切换鼠标/键盘控制
- **左Ctrl + 左Alt + X**：关闭Looking Glass客户端

## 4. 停止虚拟机

当您完成虚拟机使用后，可以通过以下命令停止虚拟机：

```bash
# 使用别名停止虚拟机
stop-vm

# 或使用脚本
./stop_vm.sh
```

## 5. 切换GPU回主机模式

```bash
# 使用别名将GPU切换回主机模式
gpu-to-host

# 返回图形界面
gui  # 这是一个自动创建的别名，等同于 sudo systemctl isolate graphical.target
```

## 6. 常见问题解决

### 图形界面无法恢复

如果在返回图形界面时遇到问题：

```bash
# 确保GPU已切换回主机模式
gpu-to-host

# 然后强制返回图形界面
sudo systemctl isolate graphical.target
```

### Looking Glass共享内存问题

如果Looking Glass无法连接到共享内存：

```bash
# 重新设置共享内存文件权限
sudo touch /dev/shm/looking-glass
sudo chown $(whoami):qemu /dev/shm/looking-glass
sudo chmod 0660 /dev/shm/looking-glass

# 对于Fedora (SELinux)
sudo semanage fcontext -a -t svirt_tmpfs_t /dev/shm/looking-glass
sudo restorecon -v /dev/shm/looking-glass
```

### 键盘/鼠标直通问题

如果键盘鼠标直通不工作：

```bash
# 查看可用输入设备
ls -l /dev/input/by-id/
ls -l /dev/input/by-path/

# 使用evdev选项重启VM
./start_vm.sh --evdev
```

## 7. 有用的命令

下面是一些在使用过程中可能需要的有用命令：

```bash
# 查看虚拟机状态
virsh list --all

# 查看VM详情
virsh dominfo AntiCheatVM

# 检查GPU绑定状态
lspci -nnk | grep -A 3 NVIDIA

# 在不修改GPU模式的情况下切换至命令行界面
sudo systemctl isolate multi-user.target

# 在不修改GPU模式的情况下返回图形界面
sudo systemctl isolate graphical.target
```

## 致谢

感谢您使用AntiCheatVM。如有任何问题或建议，请提交issues或PR到项目仓库。