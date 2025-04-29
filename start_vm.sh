#!/bin/bash
###
 # @Author: @ydzat
 # @Date: 2025-04-29 20:25:30
 # @LastEditors: @ydzat
 # @LastEditTime: 2025-04-29 22:49:26
 # @Description: Start Windows VM with optimized settings
### 

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VMS_DIR="${SCRIPT_DIR}/vms"

# Default parameters
DEFAULT_VM_NAME="AntiCheatVM"
USE_HUGEPAGES=0
LOOKING_GLASS=1

# Help information
show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -n, --name NAME            Specify VM name (default: AntiCheatVM)"
    echo "  -l, --looking-glass        Enable Looking Glass (default: enabled)"
    echo "  -H, --hugepages            Enable HugePages memory (default: disabled)"
    echo "  -h, --help                 Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --name MyWindows10VM --hugepages"
    echo "  $0 --no-looking-glass"
    echo ""
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--name)
                VM_NAME="$2"
                shift 2
                ;;
            --name=*)
                VM_NAME="${1#*=}"
                shift
                ;;
            -l|--looking-glass)
                LOOKING_GLASS=1
                shift
                ;;
            --no-looking-glass)
                LOOKING_GLASS=0
                shift
                ;;
            -H|--hugepages)
                USE_HUGEPAGES=1
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Error: Unknown parameter $1"
                show_help
                exit 1
                ;;
        esac
    done

    # If VM name not specified, use default name
    VM_NAME=${VM_NAME:-$DEFAULT_VM_NAME}
}

# Check if VM exists
check_vm_exists() {
    local vm_name="$1"
    if ! virsh dominfo "$vm_name" &>/dev/null; then
        echo "[ERROR] VM '$vm_name' does not exist or is not registered with libvirt"
        echo "Please run create_vm.py to create a VM, or check the name is correct"
        exit 1
    fi
}

# Check if VM is already running
check_vm_running() {
    local vm_name="$1"
    if virsh domstate "$vm_name" 2>/dev/null | grep -q "running"; then
        echo "[WARNING] VM '$vm_name' is already running"
        read -p "Continue (will restart the VM)? (y/n): " answer
        if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
            echo "Operation cancelled"
            exit 0
        fi
        
        echo "[+] Stopping VM..."
        virsh shutdown "$vm_name"
        
        # Wait for VM to shutdown
        for i in {1..30}; do
            if ! virsh domstate "$vm_name" 2>/dev/null | grep -q "running"; then
                echo "[✓] VM has stopped"
                break
            fi
            echo -n "."
            sleep 1
        done
        
        # Force shutdown if VM is still running
        if virsh domstate "$vm_name" 2>/dev/null | grep -q "running"; then
            echo "[!] Could not shut down VM normally, forcing shutdown"
            virsh destroy "$vm_name"
            sleep 2
        fi
    fi
}

# Setup HugePages
setup_hugepages() {
    local vm_memory_kb=$(virsh dominfo "$VM_NAME" | grep "Max memory" | awk '{print $3}')
    local vm_memory_mb=$((vm_memory_kb / 1024))
    local hugepage_size=2048  # 2MB hugepages
    local hugepage_count=$(($vm_memory_mb / $hugepage_size + 1))
    
    echo "[+] Setting up HugePages for VM..."
    echo "[i] VM memory: ${vm_memory_mb}MB, Required hugepages: $hugepage_count"
    
    # Check current HugePages configuration
    local current_pages=$(cat /proc/sys/vm/nr_hugepages 2>/dev/null || echo "0")
    
    if [ "$current_pages" -lt "$hugepage_count" ]; then
        echo "[+] Setting HugePages count to $hugepage_count..."
        echo "$hugepage_count" | sudo tee /proc/sys/vm/nr_hugepages > /dev/null
        
        # Check if successfully set
        current_pages=$(cat /proc/sys/vm/nr_hugepages)
        if [ "$current_pages" -lt "$hugepage_count" ]; then
            echo "[WARNING] Could not allocate enough HugePages (requested: $hugepage_count, actual: $current_pages)"
            echo "[i] Possible reasons: Memory fragmentation or insufficient available memory"
            echo "[i] Will continue with available HugePages"
        fi
    else
        echo "[i] Current HugePages configuration is sufficient ($current_pages pages)"
    fi
    
    # Check free_hugepages
    local free_pages=$(cat /proc/sys/vm/nr_hugepages_free 2>/dev/null || echo "0")
    echo "[i] Available HugePages: $free_pages pages"
    
    # Return actual available HugePages count
    echo "$free_pages"
}

# Start Looking Glass client
start_looking_glass() {
    echo "[+] Checking Looking Glass shared memory..."
    
    # Create shared memory file
    local shmem_file="/dev/shm/looking-glass"
    if [ ! -e "$shmem_file" ]; then
        echo "[+] Creating shared memory file..."
        sudo touch "$shmem_file"
        sudo chown $USER:qemu "$shmem_file"
        sudo chmod 660 "$shmem_file"
    fi
    
    # Check if Looking Glass client is installed
    if command -v looking-glass-client &> /dev/null; then
        echo "[i] Looking Glass client is installed, will auto-start after VM launch"
        return 0
    else
        echo "[WARNING] Looking Glass client not found"
        echo "[i] Consider running looking_glass_setup.sh to install the client"
        return 1
    fi
}

# Start VM
start_vm() {
    local vm_name="$1"
    local use_hugepages="$2"
    local cmd_args=""
    
    echo "[+] Preparing to start VM '$vm_name'..."
    
    # If HugePages enabled, add related parameters
    if [ "$use_hugepages" -eq 1 ]; then
        local available_hugepages=$(setup_hugepages)
        if [ "$available_hugepages" -gt 0 ]; then
            echo "[i] Starting VM with HugePages"
            cmd_args="--memorybacking hugepages=on"
        else
            echo "[WARNING] No HugePages available, using standard memory"
        fi
    fi
    
    # Start VM
    echo "[+] Starting VM..."
    virsh -c qemu:///system start "$vm_name" $cmd_args
    
    # Check if VM started successfully - improved detection logic
    echo "[i] Verifying VM startup..."
    # First quick check
    sleep 5
    if ! virsh list --name | grep -q "^$vm_name$"; then
        echo "[WARNING] VM not detected in initial check, waiting longer..."
        # Give more time for VM with GPU passthrough to initialize
        for i in {1..15}; do
            echo -n "."
            sleep 2
            if virsh list --name | grep -q "^$vm_name$"; then
                echo -e "\n[✓] VM detected after extended wait"
                break
            fi
        done
    fi
    
    # Final check if VM is running
    if virsh list --name | grep -q "^$vm_name$"; then
        echo "[✓] VM started successfully"
        # Show VM information
        echo "[i] VM details:"
        virsh dominfo "$vm_name" | grep -E "State|CPU|Memory"
    else
        echo "[ERROR] VM failed to start"
        echo "[i] Checking for potential issues..."
        # Check if vfio-pci driver is used for the GPU
        if lspci -k | grep -A 3 NVIDIA | grep -q "vfio-pci"; then
            echo "[i] GPU seems properly bound to vfio-pci"
        else
            echo "[WARNING] GPU might not be properly bound to vfio-pci"
            echo "[i] Try running: sudo ./gpu-manager.sh status"
        fi
        # Check for common errors in logs
        echo "[i] Last few lines from libvirt log:"
        sudo tail -n 5 /var/log/libvirt/qemu/"$vm_name".log 2>/dev/null || echo "No log file found"
        exit 1
    fi
    
    # If Looking Glass is enabled, start client
    if [ "$LOOKING_GLASS" -eq 1 ] && command -v looking-glass-client &> /dev/null; then
        # Wait for VM to fully initialize
        echo "[i] Waiting for VM initialization..."
        sleep 5
        
        # Start Looking Glass client
        echo "[+] Starting Looking Glass client..."
        looking-glass-client -a -F input:grabKeyboardOnFocus &
        echo "[i] Looking Glass client started"
    fi
}

# Main function
main() {
    echo "======================================================"
    echo " AntiCheatVM - Virtual Machine Launcher"
    echo "======================================================"
    
    # Parse command line arguments
    parse_args "$@"
    
    # Check if VM exists
    check_vm_exists "$VM_NAME"
    
    # Check if VM is already running
    check_vm_running "$VM_NAME"
    
    # If Looking Glass enabled, check and setup
    if [ "$LOOKING_GLASS" -eq 1 ]; then
        start_looking_glass
    fi
    
    # Start VM
    start_vm "$VM_NAME" "$USE_HUGEPAGES"
    
    echo "======================================================"
    echo "[AntiCheatVM] VM startup complete"
    echo ""
    echo "If using Looking Glass: "
    echo "- Alt+Tab can switch between host and VM"
    echo "- Pause key can grab/release mouse and keyboard"
    echo ""
    echo "To stop the VM, use the stop_vm.sh script"
    echo "======================================================"
}

# Execute main function
main "$@"