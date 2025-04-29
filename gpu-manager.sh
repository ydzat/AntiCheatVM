#!/bin/bash
###
 # @Author: @ydzat
 # @Date: 2025-04-29 22:30:00
 # @LastEditors: @ydzat
 # @LastEditTime: 2025-04-29 22:30:00
 # @Description: Comprehensive GPU management script for both VM passthrough and host rendering
### 

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
   echo "[ERROR] This script requires root privileges, please use sudo"
   exit 1
fi

# Help information
show_help() {
    echo "GPU Manager - Manage both VM passthrough and host rendering options"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  vm        - Bind GPU to vfio-pci for VM passthrough"
    echo "  host      - Bind GPU back to host drivers"
    echo "  nvidia    - Set new applications to use NVIDIA for rendering (PRIME)"
    echo "  intel     - Set new applications to use Intel for rendering (PRIME)"
    echo "  status    - Show current GPU status and rendering configuration"
    echo "  help      - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 vm      # Prepare GPU for VM passthrough"
    echo "  $0 host    # Return GPU to host system"
    echo "  $0 nvidia  # Use NVIDIA for application rendering"
    echo "  $0 status  # Show current GPU configuration"
    echo ""
    exit 0
}

# Load device info from config file
load_device_info() {
    CONFIG_FILE="${SCRIPT_DIR}/config/vfio_devices.yaml"
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
}

# Check GPU driver status
check_gpu_status() {
    # Must be run after load_device_info
    if [ -z "$NVIDIA_GPU" ]; then
        load_device_info
    fi

    echo "[+] Checking GPU status..."
    GPU_DRIVER=$(lspci -k | grep -A 3 "$NVIDIA_GPU" | grep "Kernel driver in use:" | awk '{print $5}')
    if [ -z "$GPU_DRIVER" ]; then
        echo "[STATUS] GPU driver: not found"
    else
        echo "[STATUS] GPU driver: $GPU_DRIVER"
    fi
    
    if [ "$GPU_DRIVER" == "nvidia" ]; then
        echo "[STATUS] GPU mode: HOST"
    elif [ "$GPU_DRIVER" == "vfio-pci" ]; then
        echo "[STATUS] GPU mode: VM"
    else
        echo "[STATUS] GPU mode: UNKNOWN"
    fi
    
    # Check rendering mode
    if [ -f "/etc/profile.d/nvidia.sh" ]; then
        OFFLOAD=$(grep "__NV_PRIME_RENDER_OFFLOAD=1" /etc/profile.d/nvidia.sh 2>/dev/null)
        if [ -n "$OFFLOAD" ]; then
            echo "[STATUS] Rendering mode: NVIDIA (PRIME Render Offload)"
        else
            echo "[STATUS] Rendering mode: Intel (Integrated Graphics)"
        fi
    else
        echo "[STATUS] Rendering mode: default"
    fi
    
    # Check current OpenGL renderer
    if command -v glxinfo > /dev/null 2>&1; then
        CURRENT_RENDERER=$(DISPLAY=:0 glxinfo 2>/dev/null | grep "OpenGL renderer" | awk -F': ' '{print $2}')
        if [ -n "$CURRENT_RENDERER" ]; then
            echo "[STATUS] Current OpenGL renderer: $CURRENT_RENDERER"
        else
            echo "[STATUS] Current OpenGL renderer: unknown (X server not running or display not set)"
        fi
    else
        echo "[STATUS] glxinfo not installed, cannot detect current renderer"
    fi
}

# Switch GPU to VM mode
switch_to_vm() {
    echo "==============================================="
    echo "[+] Switching NVIDIA GPU to VM mode..."
    echo "==============================================="
    
    # Unbind nvidia driver
    if lspci -k | grep -A 3 "$NVIDIA_GPU" | grep -q "nvidia"; then
        echo "[+] Unbinding nvidia driver..."
        
        # Try stopping X server/Wayland to release GPU
        echo "[+] Attempting to stop graphical server (may cause temporary black screen)..."
        if systemctl is-active --quiet gdm; then
            systemctl isolate multi-user.target
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
    check_gpu_status
    
    echo "[i] You can now run ./start_vm.sh to launch the VM"
    echo "[i] To return to graphical mode after VM usage:"
    echo "   1. Stop the VM"
    echo "   2. Run: sudo $0 host"
    echo "   3. Run: sudo systemctl isolate graphical.target"
}

# Switch GPU to host mode
switch_to_host() {
    echo "==============================================="
    echo "[+] Switching NVIDIA GPU to host mode..."
    echo "==============================================="
    
    # Check if VM is running and warn
    VM_NAME="AntiCheatVM"
    if virsh domstate $VM_NAME 2>/dev/null | grep -q "running"; then
        echo "[WARNING] VM '$VM_NAME' is still running!"
        read -p "Continue anyway? This may crash the VM (y/n): " answer
        if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
            echo "Operation cancelled. Please shutdown the VM first with ./stop_vm.sh"
            exit 1
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
    
    # Verify status
    check_gpu_status
    
    echo "[✓] GPU is now available for host use"
    echo "[i] To return to graphical mode, run: sudo systemctl isolate graphical.target"
}

# Set NVIDIA as rendering device (PRIME)
set_nvidia_rendering() {
    echo "[+] Setting new applications to use NVIDIA GPU for rendering..."
    echo 'export __NV_PRIME_RENDER_OFFLOAD=1' | tee /etc/profile.d/nvidia.sh >/dev/null
    echo 'export __GLX_VENDOR_LIBRARY_NAME=nvidia' | tee -a /etc/profile.d/nvidia.sh >/dev/null
    
    # Apply immediately for current terminal
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    
    echo "[✓] NVIDIA GPU set as rendering device"
    echo "[i] New terminals will use this setting automatically"
    
    # Show current renderer if X is running
    if [ -n "$DISPLAY" ] && command -v glxinfo > /dev/null 2>&1; then
        echo "Current renderer: $(glxinfo | grep "OpenGL renderer" | awk -F': ' '{print $2}')"
    fi
}

# Set Intel as rendering device (PRIME)
set_intel_rendering() {
    echo "[+] Setting new applications to use Intel integrated graphics for rendering..."
    echo 'unset __NV_PRIME_RENDER_OFFLOAD' | tee /etc/profile.d/nvidia.sh >/dev/null
    echo 'unset __GLX_VENDOR_LIBRARY_NAME' | tee -a /etc/profile.d/nvidia.sh >/dev/null
    
    # Apply immediately for current terminal
    unset __NV_PRIME_RENDER_OFFLOAD
    unset __GLX_VENDOR_LIBRARY_NAME
    
    echo "[✓] Intel integrated graphics set as rendering device"
    echo "[i] New terminals will use this setting automatically"
    
    # Show current renderer if X is running
    if [ -n "$DISPLAY" ] && command -v glxinfo > /dev/null 2>&1; then
        echo "Current renderer: $(glxinfo | grep "OpenGL renderer" | awk -F': ' '{print $2}')"
    fi
}

# Main logic
if [ $# -lt 1 ]; then
    show_help
fi

# Load device information
load_device_info

case "$1" in
    "vm")
        switch_to_vm
        ;;
    "host")
        switch_to_host
        ;;
    "nvidia")
        set_nvidia_rendering
        ;;
    "intel")
        set_intel_rendering
        ;;
    "status")
        check_gpu_status
        ;;
    "help"|"-h"|"--help")
        show_help
        ;;
    *)
        echo "[ERROR] Unknown command: $1"
        show_help
        ;;
esac