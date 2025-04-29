# Command Line Interface Guide

This guide will help you manage GPU switching and virtual machine operations from a text console when you don't have access to a graphical interface.

## Basic Navigation in CLI Mode

When in text mode (no graphical interface):
- You'll see a login prompt - enter your username and password
- Navigate using keyboard only, use Tab for completion
- Press Ctrl+Alt+F1 through F6 to switch between different virtual consoles
- Use `ls`, `cd`, and standard Linux commands to navigate the filesystem

## GPU Management

The `gpu-manager.sh` script provides comprehensive GPU management functionality, combining:
- GPU driver switching for VM passthrough (host ↔ VM)
- PRIME rendering configuration (Intel ↔ NVIDIA)

### Common GPU Operations

1. **Check current GPU status**:
   ```
   sudo ./gpu-manager.sh status
   ```

2. **Switch GPU to VM mode** (bind to vfio-pci for passthrough):
   ```
   sudo ./gpu-manager.sh vm
   ```
   This will stop the graphical server if running.

3. **Return GPU to host mode** (bind to NVIDIA driver):
   ```
   sudo ./gpu-manager.sh host
   ```

4. **Return to graphical interface** after switching GPU back to host:
   ```
   sudo systemctl isolate graphical.target
   ```

5. **Switch to command-line mode** from graphical interface:
   ```
   sudo systemctl isolate multi-user.target
   ```

6. **Set application rendering** (when not doing passthrough):
   ```
   # Use NVIDIA for rendering
   sudo ./gpu-manager.sh nvidia
   
   # Use Intel for rendering
   sudo ./gpu-manager.sh intel
   ```

## Virtual Machine Management

### Starting a VM with passthrough

1. Switch to text console (if not already there):
   ```
   sudo systemctl isolate multi-user.target
   ```

2. Navigate to AntiCheatVM directory:
   ```
   cd ~/workspace/AntiCheatVM
   ```

3. Switch GPU to VM mode:
   ```
   sudo ./gpu-manager.sh vm
   ```

4. Start the virtual machine:
   ```
   ./start_vm.sh
   ```

5. After using the VM, stop it:
   ```
   ./stop_vm.sh
   ```

6. Return GPU to host mode:
   ```
   sudo ./gpu-manager.sh host
   ```

7. Restart graphical environment:
   ```
   sudo systemctl isolate graphical.target
   ```

## Troubleshooting

### Screen is blank after GPU switching

1. Switch to another virtual console using Ctrl+Alt+F2

2. Login and check GPU status:
   ```
   cd ~/workspace/AntiCheatVM
   sudo ./gpu-manager.sh status
   ```

3. If the GPU is in VM mode and you need graphical interface:
   ```
   sudo ./gpu-manager.sh host
   sudo systemctl isolate graphical.target
   ```

### GPU driver switching fails

1. Check for running processes using the GPU:
   ```
   sudo lsof /dev/nvidia*
   ```

2. Verify that no X server is running:
   ```
   ps aux | grep X
   ```

3. Try forcing all graphical services to stop:
   ```
   sudo systemctl isolate multi-user.target
   sudo systemctl stop gdm sddm lightdm
   ```

4. Then try switching the GPU again:
   ```
   sudo ./gpu-manager.sh vm  # or host
   ```

### VM fails to start with GPU passthrough

1. Check GPU passthrough status:
   ```
   lspci -nnk | grep -A 3 NVIDIA
   ```

2. Ensure the GPU is bound to vfio-pci driver:
   ```
   sudo ./gpu-manager.sh status
   ```

3. Check libvirt logs:
   ```
   sudo tail -n 100 /var/log/libvirt/qemu/AntiCheatVM.log
   ```

## Quick Reference

| Task | Command |
|------|---------|
| Check GPU status | `sudo ./gpu-manager.sh status` |
| Switch to VM mode | `sudo ./gpu-manager.sh vm` |
| Switch to host mode | `sudo ./gpu-manager.sh host` |
| Start VM | `./start_vm.sh` |
| Stop VM | `./stop_vm.sh` |
| Start graphical interface | `sudo systemctl isolate graphical.target` |
| Switch to text console | `sudo systemctl isolate multi-user.target` |

## Special Notes for NVIDIA Optimus Laptops (Your Configuration)

Your laptop uses NVIDIA Optimus technology, where:
- Intel integrated GPU manages the displays
- NVIDIA GPU handles rendering but output goes through Intel
- Both internal and external displays appear to be connected through the Intel GPU

This configuration has significant benefits for GPU passthrough:

### Optimized Workflow for Your System

1. **Display Continuity**:
   - Since both displays are likely routed through the Intel GPU, they should remain functional even when the NVIDIA GPU is passed to the VM
   - This means you may be able to keep your graphical environment running during GPU passthrough

2. **Modified VM Launch Process**:
   ```bash
   # You may not need to switch to text mode first
   # Try this workflow:
   
   # Step 1: Check current GPU status
   sudo ./gpu-manager.sh status
   
   # Step 2: Switch GPU to VM mode
   sudo ./gpu-manager.sh vm
   # If this fails with graphical environment running, then try:
   # sudo systemctl isolate multi-user.target
   # sudo ./gpu-manager.sh vm
   
   # Step 3: Start the VM
   ./start_vm.sh
   
   # Step 4: Use Looking Glass to view the VM
   # The VM won't have direct physical display output
   ```

3. **Using Looking Glass**:
   - Since your displays stay with the host, Looking Glass becomes essential
   - Install and configure Looking Glass client on your host
   - Ensure Looking Glass server is installed in your Windows VM

4. **Alternative Display Options**:
   - If you have an HDMI port directly wired to your NVIDIA GPU (uncommon in Optimus setups), you might get direct output there
   - Most likely, all your physical display ports are connected to the Intel GPU

This setup is actually ideal for GPU passthrough, as it allows you to maintain a functional host environment while passing the NVIDIA GPU to your VM.