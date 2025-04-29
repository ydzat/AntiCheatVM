#!/usr/bin/env python3
"""
@Author: @ydzat
@Date: 2025-04-29 20:15:40
@LastEditors: @ydzat
@LastEditTime: 2025-04-29 20:15:40
@Description: 生成Windows虚拟机的libvirt XML配置
"""
import os
import sys
import yaml
import uuid
import random
import string
import argparse
import subprocess
from pathlib import Path
from lxml import etree

# 定义项目根目录
PROJECT_ROOT = Path(os.path.dirname(os.path.abspath(__file__)))
CONFIG_DIR = PROJECT_ROOT / "config"
VMS_DIR = PROJECT_ROOT / "vms"

# 确保必要的目录存在
CONFIG_DIR.mkdir(exist_ok=True)
VMS_DIR.mkdir(exist_ok=True)


def print_header():
    """打印脚本标题"""
    print("\n==========================================")
    print(" AntiCheatVM - Windows VM 配置生成工具")
    print("==========================================")


def load_vfio_devices():
    """加载VFIO设备配置"""
    devices_file = CONFIG_DIR / "vfio_devices.yaml"
    
    if not devices_file.exists():
        print("[错误] 未找到 VFIO 设备配置文件。请先运行 setup_vfio.sh")
        sys.exit(1)
    
    try:
        with open(devices_file, 'r') as f:
            config = yaml.safe_load(f)
            return config.get('devices', [])
    except Exception as e:
        print(f"[错误] 无法读取VFIO设备配置: {e}")
        sys.exit(1)


def get_host_cpu_info():
    """获取宿主机CPU信息"""
    cpu_info = {}
    
    # 获取CPU型号
    try:
        result = subprocess.run("lscpu", shell=True, capture_output=True, text=True)
        lscpu_output = result.stdout
        
        for line in lscpu_output.split('\n'):
            if "型号名称" in line or "Model name" in line:
                cpu_info['model'] = line.split(':')[1].strip()
            elif "CPU(s)" == line.split(':')[0].strip():
                cpu_info['cores'] = int(line.split(':')[1].strip())
    except Exception as e:
        print(f"[警告] 无法获取完整CPU信息: {e}")
        cpu_info['model'] = "Unknown CPU"
        cpu_info['cores'] = 4  # 默认值

    return cpu_info


def generate_random_serial():
    """生成随机序列号"""
    chars = string.ascii_uppercase + string.digits
    return ''.join(random.choice(chars) for _ in range(8))


def create_disk_image(disk_path, size_gb):
    """创建qcow2格式的虚拟磁盘"""
    print(f"[+] 创建虚拟磁盘镜像 ({size_gb}GB)...")
    
    try:
        result = subprocess.run(
            f"qemu-img create -f qcow2 {disk_path} {size_gb}G",
            shell=True, capture_output=True, text=True
        )
        
        if result.returncode != 0:
            print(f"[错误] 创建磁盘镜像失败: {result.stderr}")
            return False
        
        print(f"[√] 磁盘镜像已创建: {disk_path}")
        return True
    except Exception as e:
        print(f"[错误] 创建磁盘镜像时出错: {e}")
        return False


def generate_vm_xml(vm_name, disk_path, memory_gb, vcpus, vfio_devices):
    """生成libvirt XML配置"""
    print("[+] 生成虚拟机XML配置...")
    
    # 创建基础XML结构
    domain = etree.Element("domain", type="kvm")
    
    # 基本VM信息
    etree.SubElement(domain, "name").text = vm_name
    etree.SubElement(domain, "uuid").text = str(uuid.uuid4())
    etree.SubElement(domain, "metadata")
    
    # 内存配置（单位KB）
    memory_kb = memory_gb * 1024 * 1024
    etree.SubElement(domain, "memory", unit="KiB").text = str(memory_kb)
    etree.SubElement(domain, "currentMemory", unit="KiB").text = str(memory_kb)
    
    # CPU配置
    cpu = etree.SubElement(domain, "cpu", mode="host-passthrough")
    cpu.set("check", "none")
    # 隐藏虚拟化标识
    feature = etree.SubElement(cpu, "feature", policy="disable")
    feature.set("name", "hypervisor")
    # 缓存模式以避免影响性能
    cache = etree.SubElement(cpu, "cache", mode="passthrough")
    
    # VCPU配置
    vcpu_elem = etree.SubElement(domain, "vcpu", placement="static")
    vcpu_elem.text = str(vcpus)
    
    # OS启动配置
    os = etree.SubElement(domain, "os")
    etree.SubElement(os, "type", arch="x86_64", machine="q35").text = "hvm"
    # UEFI启动
    etree.SubElement(os, "loader", readonly="yes", type="pflash").text = "/usr/share/edk2/ovmf/OVMF_CODE.fd"
    etree.SubElement(os, "nvram").text = f"/var/lib/libvirt/qemu/nvram/{vm_name}_VARS.fd"
    # 启动顺序
    etree.SubElement(os, "boot", dev="hd")
    
    # 特性配置
    features = etree.SubElement(domain, "features")
    etree.SubElement(features, "acpi")
    etree.SubElement(features, "apic")
    etree.SubElement(features, "hyperv", mode="custom")
    
    # 伪装为真实硬件
    smbios = etree.SubElement(domain, "smbios", mode="host")
    
    # 设备配置
    devices = etree.SubElement(domain, "devices")
    
    # 模拟设备
    etree.SubElement(devices, "emulator").text = "/usr/bin/qemu-system-x86_64"
    
    # 磁盘配置
    disk = etree.SubElement(devices, "disk", type="file", device="disk")
    etree.SubElement(disk, "driver", name="qemu", type="qcow2", discard="unmap")
    etree.SubElement(disk, "source", file=str(disk_path))
    etree.SubElement(disk, "target", dev="vda", bus="virtio")
    
    # 添加光驱
    cdrom = etree.SubElement(devices, "disk", type="file", device="cdrom")
    etree.SubElement(cdrom, "driver", name="qemu", type="raw")
    etree.SubElement(cdrom, "target", dev="sda", bus="sata")
    etree.SubElement(cdrom, "readonly")
    
    # 网络配置（使用默认网桥）
    interface = etree.SubElement(devices, "interface", type="network")
    etree.SubElement(interface, "source", network="default")
    etree.SubElement(interface, "model", type="virtio")
    
    # 基本输入设备
    etree.SubElement(devices, "input", type="tablet", bus="usb")
    etree.SubElement(devices, "input", type="keyboard", bus="usb")
    
    # 基本显示设备 (将在主显卡直通后由它接管)
    graphics = etree.SubElement(devices, "graphics", type="spice")
    etree.SubElement(graphics, "listen", type="none")
    
    # 添加VFIO直通设备
    print("[+] 添加 VFIO 直通设备...")
    for dev_id in vfio_devices:
        vendor_id, device_id = dev_id.split(":")
        hostdev = etree.SubElement(devices, "hostdev", mode="subsystem", type="pci", managed="yes")
        source = etree.SubElement(hostdev, "source")
        etree.SubElement(source, "vendor", id="0x" + vendor_id)
        etree.SubElement(source, "product", id="0x" + device_id)
    
    # 添加Looking Glass共享内存
    print("[+] 添加 Looking Glass 共享内存支持...")
    shmem = etree.SubElement(devices, "shmem", name="looking-glass")
    etree.SubElement(shmem, "model", type="ivshmem-plain")
    etree.SubElement(shmem, "size", unit="M").text = "64"  # 64MB共享内存
    
    # 生成XML字符串
    xml_str = etree.tostring(domain, pretty_print=True, encoding="unicode")
    return xml_str


def save_vm_config(xml_str, vm_name):
    """保存VM配置到文件"""
    config_path = VMS_DIR / f"{vm_name}.xml"
    
    try:
        with open(config_path, 'w') as f:
            f.write(xml_str)
        print(f"[√] VM配置已保存到: {config_path}")
        return config_path
    except Exception as e:
        print(f"[错误] 保存VM配置失败: {e}")
        return None


def define_vm(xml_path):
    """向libvirt注册VM"""
    try:
        result = subprocess.run(
            f"virsh define {xml_path}",
            shell=True, capture_output=True, text=True
        )
        
        if result.returncode != 0:
            print(f"[错误] 注册VM失败: {result.stderr}")
            return False
        
        print("[√] VM已成功注册到libvirt")
        return True
    except Exception as e:
        print(f"[错误] 注册VM时出错: {e}")
        return False


def parse_args():
    """解析命令行参数"""
    parser = argparse.ArgumentParser(description="AntiCheatVM - Windows VM 配置生成工具")
    
    parser.add_argument(
        "--name", "-n", 
        default="AntiCheatVM",
        help="虚拟机名称 (默认: AntiCheatVM)"
    )
    parser.add_argument(
        "--memory", "-m", 
        type=int, default=8,
        help="分配的内存大小 (GB) (默认: 8)"
    )
    parser.add_argument(
        "--disk", "-d", 
        type=int, default=120,
        help="磁盘大小 (GB) (默认: 120)"
    )
    parser.add_argument(
        "--vcpus", "-c", 
        type=int, default=4,
        help="CPU核心数 (默认: 4)"
    )
    
    return parser.parse_args()


def main():
    """主函数"""
    print_header()
    
    args = parse_args()
    
    # 获取VFIO设备列表
    print("[+] 加载VFIO设备配置...")
    vfio_devices = load_vfio_devices()
    print(f"[i] 找到 {len(vfio_devices)} 个VFIO设备")
    
    # 获取CPU信息
    cpu_info = get_host_cpu_info()
    print(f"[i] 检测到CPU: {cpu_info['model']}, {cpu_info['cores']} 核心")
    
    # 如果用户没有明确指定VCPU数量，使用宿主机核心数的一半（至少2个）
    if args.vcpus == 4 and cpu_info['cores'] > 4:  # 4是默认值
        suggested_vcpus = max(2, cpu_info['cores'] // 2)
        print(f"[i] 建议使用 {suggested_vcpus} 个vCPU (宿主机核心数的一半)")
        response = input(f"是否使用 {suggested_vcpus} 个vCPU? (y/n): ")
        if response.lower() == 'y':
            args.vcpus = suggested_vcpus
    
    # 验证用户输入
    if args.memory < 4:
        print("[警告] 建议至少分配4GB内存给Windows VM")
    if args.disk < 64:
        print("[警告] 建议至少分配64GB磁盘空间给Windows VM")
    
    print(f"[i] VM名称: {args.name}")
    print(f"[i] 内存: {args.memory}GB")
    print(f"[i] 磁盘: {args.disk}GB")
    print(f"[i] CPU核心: {args.vcpus}")
    
    # 确认创建
    confirm = input("\n确认创建虚拟机? (y/n): ")
    if confirm.lower() != 'y':
        print("操作已取消")
        sys.exit(0)
    
    # 创建磁盘镜像
    disk_path = VMS_DIR / f"{args.name}.qcow2"
    if not create_disk_image(disk_path, args.disk):
        sys.exit(1)
    
    # 生成VM XML配置
    xml_str = generate_vm_xml(
        vm_name=args.name,
        disk_path=disk_path,
        memory_gb=args.memory,
        vcpus=args.vcpus,
        vfio_devices=vfio_devices
    )
    
    # 保存VM配置
    xml_path = save_vm_config(xml_str, args.name)
    if not xml_path:
        sys.exit(1)
    
    # 询问是否注册VM
    register = input("\n是否将VM注册到libvirt? (y/n): ")
    if register.lower() == 'y':
        if not define_vm(xml_path):
            print("[i] VM配置已保存但未注册到libvirt")
    else:
        print("[i] VM配置已保存但未注册到libvirt")
    
    print("\n====================================================")
    print("[AntiCheatVM] VM配置已完成!")
    print("")
    print("后续步骤:")
    print("1. 安装Windows系统到VM (可通过virt-manager图形界面)")
    print("2. 使用start_vm.sh启动VM")
    print("3. (可选) 使用looking_glass_setup.sh配置无桌面直通")
    print("====================================================")


if __name__ == "__main__":
    main()