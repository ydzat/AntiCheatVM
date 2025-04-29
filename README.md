# AntiCheatVM

## 🌍 Project Overview

AntiCheatVM is a Linux-based, command-line toolkit designed to create and manage a Windows virtual machine (VM) environment optimized for running modern online games that require strict anti-cheat systems (e.g., ACE, BattlEye, EAC).

It automates the setup of QEMU/KVM virtualization, GPU passthrough (VFIO), CPU/SMBIOS spoofing, memory optimizations (HugePages), and integrates seamless display solutions like Looking Glass. The goal is to maximize compatibility and performance while minimizing the chance of anti-cheat detection.

> **Target Audience:** Linux gamers, VFIO enthusiasts, and system hackers who want to play Windows games without dual-booting.

---

## 🔧 Features

- Automated hardware passthrough (GPU, audio, USB devices)
- CPU feature masking (disable `hypervisor`, `aes`, etc.)
- Customizable SMBIOS and PCI IDs to mimic real hardware
- Pre-tuned Windows VM optimization scripts (anti-cheat service management)
- Looking Glass integration for seamless gaming without monitor input switching
- System diagnostics and compatibility checking
- No UI overhead — fully script-driven CLI workflow

---

## 🛠️ Project Structure

```plaintext
AntiCheatVM/
├── README.md
├── LICENSE
├── install.sh              # Install dependencies and basic system setup
├── setup_vfio.sh           # Configure VFIO and IOMMU settings
├── create_vm.py            # Generate optimized Windows VM configuration
├── optimize_vm.py          # Windows in-VM optimization helpers
├── looking_glass_setup.sh  # Deploy Looking Glass server/client
├── scripts/
│   ├── start_vm.sh         # Launch VM with performance optimizations
│   ├── stop_vm.sh          # Shutdown VM and clean up resources
│   └── diagnostics.sh      # System capability checker
├── config/
│   ├── vm_template.xml     # Predefined VM configuration templates
│   ├── vfio_devices.yaml   # Devices to passthrough
│   └── hugepages.conf      # HugePages configuration example
├── docs/
│   ├── HOWTO.md            # Usage guide
│   └── TROUBLESHOOTING.md  # Common issues and solutions
└── future/
    ├── web_ui/             # (Optional) Placeholder for future UI extensions
    └── plugin_system/      # Game-specific tweaks and patches
```

---

## 📚 Usage Quick Start

1. Clone this repository.
2. Run `install.sh` to set up your environment.
3. Run `setup_vfio.sh` to bind your GPU and configure GRUB/IOMMU.
4. Use `create_vm.py` to generate your Windows virtual machine.
5. Launch your gaming VM with `start_vm.sh`.
6. Play your favorite Windows games — right from Linux!

---

## 💪 Goals

- Focus on reliability, reproducibility, and compatibility.
- Play games like "Wuthering Waves", "Rainbow Six Siege", "APEX Legends", and more without switching to Windows.
- Provide a clean CLI-only framework, extendable for developers.

---

## 🌟 Future Plans (Optional)

- Web-based lightweight UI (future plugin)
- Auto-profile detection for different games (anti-cheat configuration sets)
- Better cross-distro support (Fedora, Arch, Ubuntu, etc.)

---

## ✅ Status

> **Early development phase.** Focused first on creating a reproducible, minimal, working core (MVP) before expanding features.

---

## 📢 License

Open-source. License GPLv3.

---

## 👨‍💻 Contributions

Contributions, suggestions, and bug reports are welcome! Please file issues or pull requests once the project reaches a stable alpha stage.

---

## 📖 References

- Initial implementation inspiration: [Reddit user Lamchocs' successful VFIO setup for "Wuthering Waves"](https://www.reddit.com/r/VFIO/comments/1d68hw3/wuthering_waves_works_on_windows_11/)

