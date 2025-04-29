#!/bin/bash
###
 # @Author: @ydzat
 # @Date: 2025-04-29 21:15:30
 # @LastEditors: @ydzat
 # @LastEditTime: 2025-04-29 21:15:30
 # @Description: Dynamic GPU switching between host and VM
### 

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
   echo "[ERROR] This script requires root privileges, please use sudo"
   exit 1
fi

# Usage info
function show_usage {
  echo "Usage: $0 [host|vm]"
  echo "  host  - Bind GPU to nvidia drivers for host usage"
  echo "  vm    - Bind GPU to vfio-pci for VM passthrough"
  exit 1
}

# Check arguments
if [ "$#" -ne 1 ]; then
  show_usage
fi

# Load device info from config file
CONFIG_FILE="/home/ydzat/workspace/AntiCheatVM/config/vfio_devices.yaml"
if [ -f "$CONFIG_FILE" ]; then
  DEVICE_ID=$(grep -o "'.*'" "$CONFIG_FILE" | head -1 | tr -d "'")
  VENDOR_ID=$(echo $DEVICE_ID | cut -d: -f1)
  GPU_ID=$(echo $DEVICE_ID | cut -d: -f2)
else
  # Default device IDs
  VENDOR_ID="10de"
  GPU_ID="2820"
fi

# Find GPU and audio device PCI addresses
NVIDIA_INFO=$(lspci -nn | grep -i "$VENDOR_ID:$GPU_ID")
if [ -z "$NVIDIA_INFO" ]; then
  echo "[ERROR] NVIDIA GPU device not found"
  exit 1
fi

# Extract GPU PCI address
NVIDIA_GPU=$(echo "$NVIDIA_INFO" | awk '{print $1}')
echo "[INFO] Detected NVIDIA GPU: $NVIDIA_GPU"

# Find related audio device
NVIDIA_AUDIO=$(lspci | grep -A 2 "$NVIDIA_GPU" | grep "Audio" | awk '{print $1}')
if [ -n "$NVIDIA_AUDIO" ]; then
  echo "[INFO] Detected NVIDIA Audio: $NVIDIA_AUDIO"
  
  # Get the audio device's Vendor:Device ID
  AUDIO_INFO=$(lspci -nn | grep "$NVIDIA_AUDIO")
  AUDIO_ID=$(echo "$AUDIO_INFO" | grep -o "\[$VENDOR_ID:[0-9a-f]*\]" | grep -o "[0-9a-f]*" | tail -1)
else
  echo "[WARNING] No related audio device detected"
  NVIDIA_AUDIO=""
  AUDIO_ID=""
fi

case "$1" in
  "host")
    echo "==============================================="
    echo "[+] Switching NVIDIA GPU to host mode..."
    echo "==============================================="
    
    # Shutdown VM if running
    VM_NAME="AntiCheatVM"
    if virsh domstate $VM_NAME 2>/dev/null | grep -q "running"; then
      echo "[+] Shutting down VM $VM_NAME..."
      virsh shutdown $VM_NAME
      
      # Wait for VM to shutdown
      for i in {1..30}; do
        if ! virsh domstate $VM_NAME 2>/dev/null | grep -q "running"; then
          echo "[✓] VM has been shut down"
          break
        fi
        echo -n "."
        sleep 1
      done
      
      # Force shutdown if VM is still running
      if virsh domstate $VM_NAME 2>/dev/null | grep -q "running"; then
        echo "[!] VM did not shut down properly, forcing shutdown..."
        virsh destroy $VM_NAME
        sleep 2
      fi
    fi
    
    # Unbind from vfio-pci
    echo "[+] Unbinding from vfio-pci driver..."
    if [ -e "/sys/bus/pci/drivers/vfio-pci/$NVIDIA_GPU" ]; then
      echo "$NVIDIA_GPU" > /sys/bus/pci/drivers/vfio-pci/unbind
      echo "[✓] GPU unbound from vfio-pci"
    else
      echo "[i] GPU was not bound to vfio-pci"
    fi
    
    if [ -n "$NVIDIA_AUDIO" ] && [ -e "/sys/bus/pci/drivers/vfio-pci/$NVIDIA_AUDIO" ]; then
      echo "$NVIDIA_AUDIO" > /sys/bus/pci/drivers/vfio-pci/unbind
      echo "[✓] Audio device unbound from vfio-pci"
    fi
    
    # Rebind to nvidia driver
    echo "[+] Rebinding to nvidia driver..."
    
    # Unbind from any current driver
    if [ -e "/sys/bus/pci/devices/$NVIDIA_GPU/driver" ]; then
      echo "$NVIDIA_GPU" > /sys/bus/pci/devices/$NVIDIA_GPU/driver/unbind 2>/dev/null || true
    fi
    
    # Reset devices
    echo 1 > /sys/bus/pci/devices/$NVIDIA_GPU/remove
    if [ -n "$NVIDIA_AUDIO" ]; then
      echo 1 > /sys/bus/pci/devices/$NVIDIA_AUDIO/remove
    fi
    
    # Rescan PCI bus
    echo "[+] Rescanning PCI devices..."
    echo 1 > /sys/bus/pci/rescan
    sleep 2
    
    # Trigger udev to reload drivers
    echo "[+] Triggering driver reload..."
    udevadm trigger
    sleep 2
    
    echo "[✓] GPU is now available for host use"
    echo "[i] Please wait a few seconds for display system to reinitialize..."
    ;;
    
  "vm")
    echo "==============================================="
    echo "[+] Switching NVIDIA GPU to VM mode..."
    echo "==============================================="
    
    # Unbind nvidia driver
    if lspci -k | grep -A 3 "$NVIDIA_GPU" | grep -q "nvidia"; then
      echo "[+] Unbinding nvidia driver..."
      
      # Try stopping X server/Wayland to release GPU
      echo "[+] Attempting to stop graphical server (may cause temporary black screen)..."
      if systemctl is-active --quiet gdm; then
        sudo systemctl isolate multi-user.target
        sleep 3
      fi
      
      # Unload related modules
      modprobe -r nvidia_drm || true
      modprobe -r nvidia_modeset || true
      modprobe -r nvidia_uvm || true
      modprobe -r nvidia || true
      
      # If modules can't be unloaded, try unbinding device
      if lspci -k | grep -A 3 "$NVIDIA_GPU" | grep -q "nvidia"; then
        echo "[i] Directly unbinding device..."
        if [ -e "/sys/bus/pci/devices/$NVIDIA_GPU/driver" ]; then
          echo "$NVIDIA_GPU" > /sys/bus/pci/drivers/nvidia/unbind 2>/dev/null || true
        fi
      fi
      
      echo "[✓] GPU unbound from nvidia driver"
    else
      echo "[i] GPU was not bound to nvidia driver"
    fi
    
    # Unbind audio driver
    if [ -n "$NVIDIA_AUDIO" ]; then
      if lspci -k | grep -A 3 "$NVIDIA_AUDIO" | grep -q "snd_hda_intel"; then
        echo "[+] Unbinding audio driver..."
        if [ -e "/sys/bus/pci/devices/$NVIDIA_AUDIO/driver" ]; then
          echo "$NVIDIA_AUDIO" > /sys/bus/pci/drivers/snd_hda_intel/unbind 2>/dev/null || true
        fi
        echo "[✓] Audio device unbound"
      fi
    fi
    
    # Load vfio-pci driver
    echo "[+] Loading vfio-pci driver..."
    modprobe vfio || true
    modprobe vfio_pci || true
    modprobe vfio_iommu_type1 || true
    
    # Bind to vfio-pci - safer method
    echo "[+] Binding devices to vfio-pci..."
    
    # Method 1: Direct binding with device IDs
    echo "$VENDOR_ID $GPU_ID" > /sys/bus/pci/drivers/vfio-pci/new_id 2>/dev/null || true
    if [ -n "$AUDIO_ID" ]; then
      echo "$VENDOR_ID $AUDIO_ID" > /sys/bus/pci/drivers/vfio-pci/new_id 2>/dev/null || true
    fi
    
    # Method 2: Try driver_override if device exists
    if [ -e "/sys/bus/pci/devices/$NVIDIA_GPU" ]; then
      echo "vfio-pci" > /sys/bus/pci/devices/$NVIDIA_GPU/driver_override 2>/dev/null || true
      echo "$NVIDIA_GPU" > /sys/bus/pci/drivers_probe 2>/dev/null || true
    fi
    
    if [ -n "$NVIDIA_AUDIO" ] && [ -e "/sys/bus/pci/devices/$NVIDIA_AUDIO" ]; then
      echo "vfio-pci" > /sys/bus/pci/devices/$NVIDIA_AUDIO/driver_override 2>/dev/null || true
      echo "$NVIDIA_AUDIO" > /sys/bus/pci/drivers_probe 2>/dev/null || true
    fi
    
    # Wait for binding to take effect
    sleep 2
    
    # Verify results
    echo "[+] Verifying device binding status..."
    GPU_DRIVER=$(lspci -k | grep -A 3 "$NVIDIA_GPU" | grep "driver" | awk '{print $5}')
    if [ "$GPU_DRIVER" = "vfio-pci" ]; then
      echo "[✓] GPU successfully bound to vfio-pci driver"
    else
      echo "[WARNING] GPU not bound to vfio-pci (current driver: $GPU_DRIVER)"
      echo "[i] Trying alternate methods..."
      
      # Alternative: Suggest if X server is running
      if systemctl is-active --quiet gdm || pidof X > /dev/null; then
        echo "[!] Graphical server is running, may prevent GPU unbinding"
        echo "    Consider switching to text console (Ctrl+Alt+F3) and run:"
        echo "    sudo systemctl isolate multi-user.target"
        echo "    Then try this script again"
      fi
    fi
    
    if [ -n "$NVIDIA_AUDIO" ]; then
      AUDIO_DRIVER=$(lspci -k | grep -A 3 "$NVIDIA_AUDIO" | grep "driver" | awk '{print $5}')
      if [ "$AUDIO_DRIVER" = "vfio-pci" ]; then
        echo "[✓] Audio device successfully bound to vfio-pci driver"
      else
        echo "[WARNING] Audio device not bound to vfio-pci (current driver: $AUDIO_DRIVER)"
      fi
    fi
    
    echo "[✓] GPU setup complete"
    echo "[i] You can now run ./start_vm.sh to launch the VM"
    ;;
    
  *)
    show_usage
    ;;
esac