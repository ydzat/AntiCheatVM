# ⚠️ 警告 Warning ⚠️

**[中文]** 当前项目尚且不能完全骗过反作弊程序，因此尚不能保证能运行所有需要反作弊的游戏。使用本项目可能存在被游戏反作弊系统检测的风险，请谨慎使用。

**[English]** The current project cannot yet fully bypass anti-cheat programs, therefore it cannot guarantee running all games with anti-cheat systems. Using this project may risk detection by game anti-cheat systems, please use with caution.

---

# AntiCheatVM | 反作弊虚拟机

[English](#english) | [中文](#中文)

---

<a id="english"></a>
# 🌍 AntiCheatVM - English

## Overview

AntiCheatVM is a Linux-based solution designed to run Windows games that utilize anti-cheat systems (like ACE, BattlEye, EAC) in a virtual machine with GPU passthrough. This project focuses on providing a seamless gaming experience without compromising on performance or triggering anti-cheat protections.

### Key Features

- GPU passthrough with proper VFIO/IOMMU setup
- CPU feature masking to bypass VM detection
- Storage optimizations for anti-cheat compatibility
- Simple, script-driven workflow

---

## 📋 Requirements

- A Linux system with KVM/QEMU support
- CPU with IOMMU support (Intel VT-d or AMD-Vi)
- Two GPUs (one for Linux host, one for Windows VM) or single GPU with proper configuration
- At least 8GB RAM (16GB recommended)
- Storage space for Windows VM (min. 64GB, 128GB recommended)

---

## 🚀 Quick Start Guide

Follow these steps to set up AntiCheatVM:

### 1. Install Dependencies

Run the installation script:

```bash
sudo ./install.sh
```

This script installs all necessary packages for virtualization, GPU passthrough, and optimizes system settings.

### 2. Configure VFIO and IOMMU

Set up your GPU for passthrough:

```bash
sudo ./setup_vfio.sh
```

The script will:
- Configure IOMMU settings in GRUB
- Identify and bind your dedicated GPU to VFIO
- Create GPU management scripts

**Note:** A system reboot is required after this step.

### 3. Create and Configure the VM

After reboot, create the Windows VM:

```bash
# If you haven't already:
mkdir -p /home/$USER/workspace/AntiCheatVM/iso
# Place Windows ISO and virtio drivers ISO in the iso directory
# Then run:
sudo ./create_vm.py
```

Or manually set up the VM with virt-manager, ensuring:
- Storage type is set to `raw` instead of `qcow2`
- CPU configuration includes `topoext`, disables `hypervisor` and `aes` features
- Clock configuration uses native TSC timing

### 4. Start the VM

```bash
./start_vm.sh
```

This script:
- Checks if the GPU is properly bound to VFIO
- Allocates hugepages for better performance
- Starts the VM with optimized settings

### 5. Windows VM Configuration

After Windows installation:
1. Install virtio drivers from the virtio-win ISO
2. Install required Windows updates
3. Install your games
4. For games with ACE anti-cheat (like Wuthering Waves):
   - Find "AntiCheatExpertService" in services.msc
   - Set it to "Manual" startup type

---

## 🔧 Configuration Reference

### Important XML Settings

For games with anti-cheat (especially ACE used in Wuthering Waves), ensure your VM XML has these settings:

```xml
<disk type='file' device='disk'>
  <driver name='qemu' type='raw' discard='unmap' cache="none" io="native" iothread="1"/>
  <!-- Use raw format instead of qcow2 -->
</disk>

<cpu mode='host-passthrough' check='none' migratable='on'>
  <topology sockets="1" dies="1" clusters="1" cores="6" threads="2"/>
  <feature policy="disable" name="hypervisor"/>
  <feature policy="disable" name="aes"/>
</cpu>

<clock offset='localtime'>
  <timer name="rtc" tickpolicy="catchup" track="guest"/>
  <timer name="pit" tickpolicy="delay"/>
  <timer name="hpet" present="no"/>
  <timer name="hypervclock" present="yes"/>
  <timer name="tsc" present="yes" mode="native"/>
</clock>
```

### Converting qcow2 to raw Format

If your VM is already using qcow2 format, convert it:

```bash
qemu-img convert -f qcow2 -O raw /path/to/your/vm.qcow2 /path/to/your/vm.raw
```

Then update the XML file to point to the raw file.

---

## ❓ Troubleshooting

### Common Issues

#### Error: "cannot limit locked memory of process"

This happens when the memory lock limit is too low:

```bash
sudo mkdir -p /etc/systemd/system/user-$(id -u).slice.d/
echo -e "[Slice]\nMemoryLock=infinity" | sudo tee /etc/systemd/system/user-$(id -u).slice.d/90-memlock.conf
sudo systemctl daemon-reload
sudo systemctl restart libvirtd
```

#### Error: "per-device boot elements cannot be used together with os/boot elements"

Edit your VM XML file to remove one of the boot definitions:

```bash
sudo virsh edit YourVM
# Remove either the <boot dev='hd'/> inside <os>
# OR remove all <boot order="N"/> tags in individual devices
```

#### Error: ACE Anti-cheat Detection in Games

Ensure:
1. VM storage type is `raw` (not `qcow2`)
2. CPU features `hypervisor` and `aes` are disabled
3. "AntiCheatExpertService" in Windows is set to "Manual"

#### GPU Not Switching to VFIO Mode

Run the GPU manager:

```bash
sudo ./gpu-manager.sh
```

And select option to switch GPU to VM mode.

---

## 🧹 Cleanup

To remove all changes made by AntiCheatVM:

```bash
sudo ./cleanup.sh
```

This script provides a comprehensive cleanup process:
- Restores original system configuration (GRUB, dracut, etc.)
- Removes VFIO bindings and switches GPU back to host mode
- Creates a startup service to ensure GPU always uses host mode after reboot
- Cleans up memory settings (HugePages, memlock limits)
- Helps identify and remove downloaded libraries, source code, and build files
- Lists but does not automatically remove VM image files

The script will prompt for confirmation before deleting important files, giving you control over the cleanup process.

---

## 📚 References

- [Reddit: Wuthering Waves Works on Windows 11](https://www.reddit.com/r/VFIO/comments/1d68hw3/wuthering_waves_works_on_windows_11/)
- [Arch Wiki: PCI passthrough via OVMF](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF)
- [ACE Anti-Cheat in VMs](https://github.com/QaidVoid/Complete-Single-GPU-Passthrough)

---

<a id="中文"></a>
# 🌍 AntiCheatVM - 中文

## 概述

AntiCheatVM 是一个基于 Linux 的解决方案，旨在通过 GPU 直通在虚拟机中运行使用反作弊系统（如 ACE、BattlEye、EAC）的 Windows 游戏。该项目专注于提供无缝的游戏体验，同时不影响性能或触发反作弊保护。

### 主要特点

- 使用适当的 VFIO/IOMMU 设置实现 GPU 直通
- CPU 特性屏蔽以绕过虚拟机检测
- 针对反作弊兼容性的存储优化
- 简单、基于脚本的工作流

---

## 📋 系统要求

- 支持 KVM/QEMU 的 Linux 系统
- 支持 IOMMU 的 CPU（Intel VT-d 或 AMD-Vi）
- 两个 GPU（一个用于 Linux 宿主机，一个用于 Windows 虚拟机）或具有适当配置的单 GPU
- 至少 8GB RAM（推荐 16GB）
- Windows 虚拟机的存储空间（最小 64GB，推荐 128GB）

---

## 🚀 快速开始指南

按照以下步骤设置 AntiCheatVM：

### 1. 安装依赖项

运行安装脚本：

```bash
sudo ./install.sh
```

此脚本安装虚拟化、GPU 直通所需的所有包，并优化系统设置。

### 2. 配置 VFIO 和 IOMMU

设置 GPU 直通：

```bash
sudo ./setup_vfio.sh
```

该脚本将：
- 在 GRUB 中配置 IOMMU 设置
- 识别并将专用 GPU 绑定到 VFIO
- 创建 GPU 管理脚本

**注意：** 此步骤后需要重启系统。

### 3. 创建和配置虚拟机

重启后，创建 Windows 虚拟机：

```bash
# 如果尚未创建目录：
mkdir -p /home/$USER/workspace/AntiCheatVM/iso
# 将 Windows ISO 和 virtio 驱动 ISO 放在 iso 目录中
# 然后运行：
sudo ./create_vm.py
```

或使用 virt-manager 手动设置虚拟机，确保：
- 存储类型设置为 `raw` 而不是 `qcow2`
- CPU 配置包括 `topoext`，并禁用 `hypervisor` 和 `aes` 特性
- 时钟配置使用原生 TSC 计时

### 4. 启动虚拟机

```bash
./start_vm.sh
```

此脚本：
- 检查 GPU 是否正确绑定到 VFIO
- 分配大页内存以提高性能
- 以优化设置启动虚拟机

### 5. Windows 虚拟机配置

安装 Windows 后：
1. 从 virtio-win ISO 安装 virtio 驱动程序
2. 安装所需的 Windows 更新
3. 安装您的游戏
4. 对于使用 ACE 反作弊的游戏（如 Wuthering Waves）：
   - 在 services.msc 中找到 "AntiCheatExpertService"
   - 将其设置为 "手动" 启动类型

---

## 🔧 配置参考

### 重要的 XML 设置

对于带有反作弊的游戏（特别是 Wuthering Waves 中使用的 ACE），确保您的虚拟机 XML 具有以下设置：

```xml
<disk type='file' device='disk'>
  <driver name='qemu' type='raw' discard='unmap' cache="none" io="native" iothread="1"/>
  <!-- 使用 raw 格式而不是 qcow2 -->
</disk>

<cpu mode='host-passthrough' check='none' migratable='on'>
  <topology sockets="1" dies="1" clusters="1" cores="6" threads="2"/>
  <feature policy="disable" name="hypervisor"/>
  <feature policy="disable" name="aes"/>
</cpu>

<clock offset='localtime'>
  <timer name="rtc" tickpolicy="catchup" track="guest"/>
  <timer name="pit" tickpolicy="delay"/>
  <timer name="hpet" present="no"/>
  <timer name="hypervclock" present="yes"/>
  <timer name="tsc" present="yes" mode="native"/>
</clock>
```

### 将 qcow2 转换为 raw 格式

如果您的虚拟机已经在使用 qcow2 格式，请将其转换：

```bash
qemu-img convert -f qcow2 -O raw /path/to/your/vm.qcow2 /path/to/your/vm.raw
```

然后更新 XML 文件以指向 raw 文件。

---

## ❓ 常见问题解决

### 常见问题

#### 错误："cannot limit locked memory of process"

当内存锁定限制过低时会发生这种情况：

```bash
sudo mkdir -p /etc/systemd/system/user-$(id -u).slice.d/
echo -e "[Slice]\nMemoryLock=infinity" | sudo tee /etc/systemd/system/user-$(id -u).slice.d/90-memlock.conf
sudo systemctl daemon-reload
sudo systemctl restart libvirtd
```

#### 错误："per-device boot elements cannot be used together with os/boot elements"

编辑您的虚拟机 XML 文件以移除其中一个启动定义：

```bash
sudo virsh edit 您的虚拟机名称
# 删除 <os> 内的 <boot dev='hd'/> 
# 或移除各个设备中的所有 <boot order="N"/> 标签
```

#### 错误：游戏中的 ACE 反作弊检测

确保：
1. 虚拟机存储类型为 `raw`（而不是 `qcow2`）
2. CPU 特性 `hypervisor` 和 `aes` 已禁用
3. Windows 中的 "AntiCheatExpertService" 设置为 "手动"

#### GPU 无法切换到 VFIO 模式

运行 GPU 管理器：

```bash
sudo ./gpu-manager.sh
```

并选择将 GPU 切换到 VM 模式的选项。

---

## 🧹 清理

要删除 AntiCheatVM 所做的所有更改：

```bash
sudo ./cleanup.sh
```

此脚本提供全面的清理过程：
- 恢复原始系统配置(GRUB、dracut等)
- 移除VFIO绑定并将GPU切换回主机模式
- 创建启动服务，确保GPU在重启后始终使用主机模式
- 清理内存设置(大页内存、内存锁定限制)
- 帮助识别并移除下载的库、源代码和构建文件
- 列出但不自动删除虚拟机镜像文件

脚本在删除重要文件前会提示确认，让您可以控制清理过程。

---

## 📚 参考资料

- [Reddit：Wuthering Waves 在 Windows 11 上运行成功](https://www.reddit.com/r/VFIO/comments/1d68hw3/wuthering_waves_works_on_windows_11/)
- [Arch Wiki：通过 OVMF 进行 PCI 直通](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF)
- [Complete-Single-GPU-Passthrough Public](https://github.com/QaidVoid/Complete-Single-GPU-Passthrough)
- [[tutorial] The Ultimate Linux Laptop for PC Gamers — feat. KVM and VFIO](https://blandmanstudios.medium.com/tutorial-the-ultimate-linux-laptop-for-pc-gamers-feat-kvm-and-vfio-dee521850385)
