#!/bin/bash
###
 # @Author: @ydzat
 # @Date: 2025-04-29 23:30:00
 # @LastEditors: @ydzat
 # @LastEditTime: 2025-04-29 23:30:00
 # @Description: Install and setup Looking Glass for VM display
### 

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$(id -u)" -eq 0 ]; then
    echo -e "${RED}[ERROR] This script should NOT be run as root${NC}"
    echo "Please run without sudo"
    exit 1
fi

echo "======================================================"
echo " Looking Glass Setup for AntiCheatVM"
echo "======================================================"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check for required dependencies
check_dependencies() {
    echo -e "${BLUE}[+] Checking dependencies...${NC}"
    
    local deps=("git" "cmake" "make" "gcc" "g++" "pkg-config")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command_exists "$dep"; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${YELLOW}[!] Missing dependencies: ${missing_deps[*]}${NC}"
        read -p "Install missing dependencies? (y/n): " install_deps
        if [[ "$install_deps" == "y" || "$install_deps" == "Y" ]]; then
            echo -e "${BLUE}[+] Installing dependencies...${NC}"
            sudo apt-get update
            sudo apt-get install -y "${missing_deps[@]}" \
                libgl1-mesa-dev libglu1-mesa-dev libpulse-dev \
                libsdl2-dev libsdl2-ttf-dev libspice-protocol-dev \
                libfontconfig1-dev libx11-dev nettle-dev libwayland-dev \
                cmake make gcc g++ binutils-dev libxi-dev
            echo -e "${GREEN}[✓] Dependencies installed${NC}"
        else
            echo -e "${RED}[ERROR] Required dependencies missing. Cannot continue.${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}[✓] All base dependencies found${NC}"
    fi
}

# Setup shared memory file for Looking Glass
setup_shared_memory() {
    echo -e "${BLUE}[+] Setting up shared memory file...${NC}"
    
    local shmem_file="/dev/shm/looking-glass"
    
    if [ -e "$shmem_file" ]; then
        echo -e "${GREEN}[✓] Shared memory file already exists${NC}"
    else
        echo -e "${BLUE}[+] Creating shared memory file...${NC}"
        sudo touch "$shmem_file"
        sudo chown $USER:qemu "$shmem_file"
        sudo chmod 660 "$shmem_file"
        echo -e "${GREEN}[✓] Shared memory file created${NC}"
    fi
    
    # Set up systemd tmpfiles configuration for persistence across reboots
    local tmpfiles_conf="/etc/tmpfiles.d/10-looking-glass.conf"
    if [ ! -e "$tmpfiles_conf" ]; then
        echo -e "${BLUE}[+] Setting up persistent shared memory configuration...${NC}"
        echo "f /dev/shm/looking-glass 0660 $USER qemu -" | sudo tee "$tmpfiles_conf" > /dev/null
        echo -e "${GREEN}[✓] Persistence configuration created${NC}"
    fi
}

# Install Looking Glass client
install_looking_glass() {
    echo -e "${BLUE}[+] Setting up Looking Glass client...${NC}"
    
    # Create a temporary directory for building
    local build_dir=$(mktemp -d)
    echo -e "${BLUE}[+] Using temporary directory: $build_dir${NC}"
    
    # Clone the repository
    echo -e "${BLUE}[+] Cloning Looking Glass repository...${NC}"
    git clone https://github.com/gnif/LookingGlass.git "$build_dir/LookingGlass"
    cd "$build_dir/LookingGlass"
    git submodule init
    git submodule update
    
    # Build the client
    echo -e "${BLUE}[+] Building Looking Glass client...${NC}"
    mkdir -p "$build_dir/LookingGlass/client/build"
    cd "$build_dir/LookingGlass/client/build"
    cmake ..
    make -j$(nproc)
    
    # Install the client
    echo -e "${BLUE}[+] Installing Looking Glass client...${NC}"
    sudo make install
    
    # Clean up
    echo -e "${BLUE}[+] Cleaning up build files...${NC}"
    rm -rf "$build_dir"
    
    echo -e "${GREEN}[✓] Looking Glass client installed${NC}"
}

# Configure VM for Looking Glass
configure_vm() {
    echo -e "${BLUE}[+] Configuring VM for Looking Glass...${NC}"
    local vm_xml="${SCRIPT_DIR}/vms/AntiCheatVM.xml"
    
    # Check if VM XML exists
    if [ ! -f "$vm_xml" ]; then
        echo -e "${RED}[ERROR] VM XML file not found: $vm_xml${NC}"
        echo "Please create the VM first with create_vm.py"
        return 1
    fi
    
    # Check if Looking Glass is already configured
    if grep -q "org.looking-glass" "$vm_xml"; then
        echo -e "${GREEN}[✓] Looking Glass already configured in VM XML${NC}"
    else
        echo -e "${YELLOW}[!] Looking Glass configuration not found in VM XML${NC}"
        echo -e "${YELLOW}[!] Manual configuration required${NC}"
        echo ""
        echo "Please add the following to your VM XML file (inside the <devices> section):"
        echo ""
        echo "  <shmem name='looking-glass'>"
        echo "    <model type='ivshmem-plain'/>"
        echo "    <size unit='M'>32</size>"
        echo "  </shmem>"
        echo ""
        echo "Then restart your VM."
        echo ""
        read -p "Would you like to attempt automatic configuration? (y/n): " auto_config
        if [[ "$auto_config" == "y" || "$auto_config" == "Y" ]]; then
            echo -e "${BLUE}[+] Making backup of VM XML file...${NC}"
            cp "$vm_xml" "${vm_xml}.backup"
            
            # Check if VM is running
            if virsh domstate AntiCheatVM 2>/dev/null | grep -q "running"; then
                echo -e "${YELLOW}[!] VM is currently running. Changes will apply after VM restart.${NC}"
            fi
            
            # Add Looking Glass configuration
            if grep -q "</devices>" "$vm_xml"; then
                sed -i '/<\/devices>/i \  <shmem name="looking-glass">\n    <model type="ivshmem-plain"/>\n    <size unit="M">32</size>\n  <\/shmem>' "$vm_xml"
                echo -e "${GREEN}[✓] Looking Glass configuration added to VM XML${NC}"
            else
                echo -e "${RED}[ERROR] Could not find </devices> tag in VM XML${NC}"
                echo "Please configure manually."
                return 1
            fi
        fi
    fi
}

# Check Windows VM
check_vm_setup() {
    echo -e "${BLUE}[+] Checking VM configuration...${NC}"
    
    # Check if VM exists
    if ! virsh dominfo AntiCheatVM &>/dev/null; then
        echo -e "${YELLOW}[!] VM 'AntiCheatVM' not found in libvirt${NC}"
        echo "Please create the VM first with create_vm.py"
        return 1
    fi
    
    echo -e "${GREEN}[✓] VM 'AntiCheatVM' exists${NC}"
    
    # Add note about Windows guest
    echo ""
    echo -e "${YELLOW}[i] Important: Windows Guest Configuration${NC}"
    echo "To complete Looking Glass setup, you need to install the Looking Glass host application in Windows:"
    echo ""
    echo "1. Download the Windows host application from: https://looking-glass.io/downloads"
    echo "2. Install and configure it to run at startup"
    echo "3. Make sure IVSHMEM driver is installed in Windows"
    echo ""
    echo "For detailed instructions, visit: https://looking-glass.io/docs"
    echo ""
}

# Create desktop shortcut
create_shortcut() {
    echo -e "${BLUE}[+] Creating desktop shortcut...${NC}"
    
    local desktop_file="$HOME/.local/share/applications/looking-glass.desktop"
    mkdir -p "$HOME/.local/share/applications"
    
    cat > "$desktop_file" << EOF
[Desktop Entry]
Name=Looking Glass Client
Comment=Low latency VM display
Exec=looking-glass-client
Terminal=false
Type=Application
Categories=Utility;
EOF
    
    echo -e "${GREEN}[✓] Desktop shortcut created${NC}"
}

# Main function
main() {
    check_dependencies
    setup_shared_memory
    install_looking_glass
    configure_vm
    check_vm_setup
    create_shortcut
    
    echo ""
    echo -e "${GREEN}[✓] Looking Glass setup complete!${NC}"
    echo ""
    echo "Usage:"
    echo "1. Start your VM with: ./start_vm.sh"
    echo "2. Looking Glass client will auto-start"
    echo "3. Use Alt+Tab to switch between host and VM"
    echo "4. Use Pause key to grab/release mouse and keyboard"
    echo ""
}

# Execute main function
main "$@"