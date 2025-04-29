#!/bin/bash
###
 # @Author: @ydzat
 # @Date: 2025-04-29 19:36:14
 # @LastEditors: @ydzat
 # @LastEditTime: 2025-04-29 19:48:40
 # @Description: 
### 
#!/bin/bash

set -e

echo "[AntiCheatVM] 初始化安装环境..."

# 安装系统依赖（Fedora 版本）
echo "[+] 安装基础包（Fedora）..."
sudo dnf install -y \
  qemu-kvm virt-manager virt-install libvirt-daemon libvirt-daemon-driver* \
  python3 python3-pip python3-virtualenv make git || true

# 创建 Python 虚拟环境
if [ ! -d ".venv" ]; then
  echo "[+] 创建 Python 虚拟环境 .venv/"
  python3 -m venv .venv
fi

# 激活虚拟环境并安装依赖
source .venv/bin/activate
pip install --upgrade pip
pip install pyyaml lxml

echo "[AntiCheatVM] 安装完成！请执行以下命令激活环境："
echo "  source .venv/bin/activate"
echo "然后你可以运行 create_vm.py 等模块。"