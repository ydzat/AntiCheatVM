#!/bin/bash
###
 # @Author: @ydzat
 # @Date: 2025-04-29 20:35:25
 # @LastEditors: @ydzat
 # @LastEditTime: 2025-04-29 20:35:25
 # @Description: Stop Windows VM and release resources
### 

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default parameters
DEFAULT_VM_NAME="AntiCheatVM"
FORCE_SHUTDOWN=0
TIMEOUT=30  # Wait timeout for shutdown (seconds)
CLEAN_HUGEPAGES=1

# Help information
show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -n, --name NAME            Specify VM name (default: AntiCheatVM)"
    echo "  -f, --force                Force VM shutdown (skip normal shutdown)"
    echo "  -t, --timeout SECONDS      Shutdown wait timeout (default: 30 seconds)"
    echo "  --no-clean-hugepages       Do not clean HugePages"
    echo "  -h, --help                 Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --name MyWindows10VM"
    echo "  $0 --force"
    echo "  $0 --timeout 60"
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
            -f|--force)
                FORCE_SHUTDOWN=1
                shift
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --timeout=*)
                TIMEOUT="${1#*=}"
                shift
                ;;
            --no-clean-hugepages)
                CLEAN_HUGEPAGES=0
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
        exit 1
    fi
}

# Check if VM is running
check_vm_running() {
    local vm_name="$1"
    if ! virsh domstate "$vm_name" 2>/dev/null | grep -q "running"; then
        echo "[i] VM '$vm_name' is not running"
        return 1
    fi
    return 0
}

# Shutdown VM
shutdown_vm() {
    local vm_name="$1"
    local force="$2"
    local timeout="$3"
    
    # If VM is not running, no action needed
    if ! check_vm_running "$vm_name"; then
        return 0
    fi
    
    # If force shutdown, use destroy command directly
    if [ "$force" -eq 1 ]; then
        echo "[!] Forcing VM '$vm_name' shutdown..."
        virsh destroy "$vm_name"
        sleep 2
        
        if check_vm_running "$vm_name"; then
            echo "[ERROR] Cannot force shutdown VM"
            return 1
        else
            echo "[✓] VM has been forcefully shut down"
            return 0
        fi
    fi
    
    # Try normal shutdown
    echo "[+] Shutting down VM '$vm_name'..."
    virsh shutdown "$vm_name"
    
    # Wait for VM to shutdown, up to timeout seconds
    echo "[i] Waiting for VM to shutdown (max $timeout seconds)..."
    for ((i=1; i<=timeout; i++)); do
        if ! check_vm_running "$vm_name"; then
            echo "[✓] VM has shut down normally"
            return 0
        fi
        
        # Show progress every 10 seconds
        if [ $((i % 10)) -eq 0 ]; then
            echo "[i] Still waiting for VM to shutdown... ($i/$timeout seconds)"
        fi
        
        sleep 1
    done
    
    # If timeout, ask whether to force shutdown
    echo "[WARNING] VM shutdown timed out"
    read -p "Force shutdown? (y/n): " answer
    if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
        echo "[!] Forcing VM shutdown..."
        virsh destroy "$vm_name"
        sleep 2
        
        if check_vm_running "$vm_name"; then
            echo "[ERROR] Cannot force shutdown VM"
            return 1
        else
            echo "[✓] VM has been forcefully shut down"
            return 0
        fi
    else
        echo "[i] Force shutdown cancelled, VM is still running"
        return 1
    fi
}

# Clean HugePages
cleanup_hugepages() {
    if [ "$CLEAN_HUGEPAGES" -eq 1 ]; then
        echo "[+] Cleaning up HugePages..."
        
        # Check if HugePages are allocated
        local allocated_pages=$(cat /proc/sys/vm/nr_hugepages 2>/dev/null || echo "0")
        
        if [ "$allocated_pages" -gt 0 ]; then
            echo "[i] Allocated HugePages: $allocated_pages"
            echo "[+] Releasing HugePages..."
            
            # Release HugePages (set to 0)
            echo 0 | sudo tee /proc/sys/vm/nr_hugepages > /dev/null
            
            # Verify release result
            local current_pages=$(cat /proc/sys/vm/nr_hugepages 2>/dev/null || echo "0")
            if [ "$current_pages" -eq 0 ]; then
                echo "[✓] HugePages released"
            else
                echo "[WARNING] Could not fully release HugePages (remaining: $current_pages)"
                echo "[i] Other processes may be using HugePages"
            fi
        else
            echo "[i] No allocated HugePages"
        fi
    fi
}

# Stop Looking Glass client
stop_looking_glass() {
    echo "[+] Checking Looking Glass process..."
    
    # Check if Looking Glass client is running
    if pgrep -f "looking-glass-client" > /dev/null; then
        echo "[+] Closing Looking Glass client..."
        pkill -f "looking-glass-client"
        sleep 1
        
        # Check again if terminated
        if pgrep -f "looking-glass-client" > /dev/null; then
            echo "[WARNING] Could not close Looking Glass client normally, attempting force kill..."
            pkill -9 -f "looking-glass-client"
            sleep 1
            
            if pgrep -f "looking-glass-client" > /dev/null; then
                echo "[ERROR] Cannot terminate Looking Glass client"
            else
                echo "[✓] Looking Glass client terminated"
            fi
        else
            echo "[✓] Looking Glass client closed"
        fi
    else
        echo "[i] Looking Glass client is not running"
    fi
}

# Main function
main() {
    echo "======================================================"
    echo " AntiCheatVM - Virtual Machine Shutdown Tool"
    echo "======================================================"
    
    # Parse command line arguments
    parse_args "$@"
    
    # Check if VM exists
    check_vm_exists "$VM_NAME"
    
    # If VM is running, shut it down
    if check_vm_running "$VM_NAME"; then
        if ! shutdown_vm "$VM_NAME" "$FORCE_SHUTDOWN" "$TIMEOUT"; then
            echo "[ERROR] Cannot shut down VM, please check status or manual operation"
            exit 1
        fi
    fi
    
    # Stop Looking Glass client
    stop_looking_glass
    
    # Clean HugePages
    cleanup_hugepages
    
    echo "======================================================"
    echo "[AntiCheatVM] VM has been shut down, resources released"
    echo "======================================================"
}

# Execute main function
main "$@"