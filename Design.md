# AntiCheatVM - 设计文档 (Draft)

---

## 1. 项目目标与范围 (Goals & Scope)

**目标：**

- 在 Linux 环境下，使用 QEMU/KVM 虚拟化，实现面向 Windows 游戏的高性能、低检测风险的虚拟机环境。
- 支持 GPU passthrough (VFIO) 和 CPU/SMBIOS 伪装，进一步优化运行效率，尽可能降低受到防欺诈系统 (Anti-Cheat) 检测的风险。

**范围：**

- 支持主要环境：Linux Desktop (Fedora，Arch，Ubuntu)
- 支持游戏：目前主要目标是使 "鸣潮（国服）" 能够成功运行
- 依赖于 QEMU/KVM, VFIO, Looking Glass
- 允许自定义 VM 创建、启动、关闭流程

---

## 2. 总体架构 (Architecture Overview)

**核心组件：**

- `setup_vfio.sh`：配置 VFIO/IOMMU 环境，编译并绑定 GPU 设备
- `create_vm.py`：根据用户输入，生成 Windows VM 的 libvirt XML 配置
- `optimize_vm.py`：面向虚拟机内部 Windows 系统进行最优化处理
- `looking_glass_setup.sh`：部署 Looking Glass 服务器/客户端，进行显示连接
- `scripts/`：启动、关闭、检查 VM 的主要脚本

**支持文件：**

- `config/`：主要配置文件，包括 VFIO 设备列表，HugePages 配置，VM 模板 XML
- `docs/`：使用指南，故障排查手册
- `future/`：未来接入层（网页控制面板，游戏对应插件等）

---

## 3. 主要模块设计 (Modules and Components)

### 3.1 `setup_vfio.sh`

**功能：**

- 检查 CPU 是否支持 VT-d/IOMMU
- 修改 GRUB 启动参数，启用 IOMMU 功能
- 检测设备所属 IOMMU 组，自动选择可选设备（最少用户操作）
- 生成并配置 VFIO 绑定脚本，使 GPU 和相关设备从主机系统绑定到 vfio-pci
- 设置完成后，提示用户手动重启系统（非自动重启）

**输入：**

- 自动检测硬件 PCI ID（GPU、音频、USB Controller 等）
- 可选：从 `config/vfio_devices.yaml` 读取预设设备列表

**输出：**

- 修改后的 `/etc/default/grub` 文件
- 生成自动执行的 VFIO 绑定脚本（如 `/etc/modprobe.d/vfio.conf`）
- 检测结果和提示消息
- 用户重启提示

**基本流程：**

1. 检查 CPU IOMMU 支持
2. 搜索 GPU/音频设备信息
3. 修改 GRUB 启动参数
4. 配置 VFIO 绑定脚本
5. 设置 HugePages（如有必要）
6. 提示用户重启
7. 等待用户重启，进入下一步 VM 创建

---

### 3.2 `create_vm.py`

**功能：**

- 根据用户选择或配置，生成最优化的 Windows VM libvirt XML 配置
- 自动选择相关硬件设备进行 GPU/USB/音频直通
- 将 CPU 特征和虚拟化标识隐藏（如 hypervisor bit 禁用）
- 支持自定义 SMBIOS 信息（伪装为真实硬件）
- 自动创建动态扩容的 qcow2 格式磁盘镜像，最大容量可设置
- 磁盘镜像起始占用空间极小，随着数据写入扩展，不含游戏时基本不占用额外空间

**输入：**

- 用户选择的硬件设备
- 用户指定或默认的虚拟磁盘容量（如 250GB）
- 自定义或默认的 SMBIOS 配置

**输出：**

- 生成的 libvirt XML 文件（保存在 `config/` 或 `vms/` 目录）
- 创建好的 qcow2 格式磁盘镜像

**基本流程：**

1. 搜索系统可相关硬件
2. 根据用户选择创建磁盘镜像，设置最大容量
3. 生成完整的 libvirt XML 配置
4. 保存 XML 和磁盘文件，供 VM 使用
5. 展示或提示用户可以启动 VM

---

### 3.3 `optimize_vm.py`

**功能：**

- 生成 Windows VM 内部最优化处理脚本
- 关闭不必要的系统服务（如 Windows Update，Superfetch，远程框架服务）
- 调整系统设置（禁用休眠，关闭系统还原，启用高性能电源设置）
- 调整注册表，隐藏部分虚拟化特征
- 支持在 Linux 端生成一套可执行的 .bat/脚本包，用户在 Windows VM 中一键执行
- 记录各步操作结果，便于回滚和故障排查

**输入：**

- 预置的优化项目列表
- 用户可选指定要启用/禁用的优化策略

**输出：**

- 一套完整的 Windows 优化脚本（.bat）
- 优化处理记录（日志）

**基本流程：**

1. 根据预置生成对应脚本
2. 打包成单一执行文件，便于用户在 Windows 系统中运行
3. 提示用户在 Windows 虚拟机中发送、执行该脚本
4. 优化后，输出处理结果日志

---

### 3.4 `looking_glass_setup.sh`

**功能：**

- 默认下载安装 Looking Glass 官方预编译版本，无需手动源码编译  
- 自动配置 Linux 主机端所需组件（ivshmem 驱动，Looking Glass 客户端）  
- 指导用户配置 QEMU/KVM 虚拟机 XML，增加 IVSHMEM 设备和共享内存支持  
- 引导 Windows VM 内安装 Looking Glass Host（服务器端）  
- 提供 Linux 主机端一键启动 Looking Glass 客户端的命令或脚本  
- 优化共享内存区（如设定 32MB/64MB 大小，根据需求）  
- 记录安装与配置日志，便于排查问题

**输入：**

- 无需用户额外输入，默认使用最新稳定版 Looking Glass Release  
- 可选参数：自定义内存共享区大小、自定义客户端路径

**输出：**

- 完整安装的 Looking Glass Client 和相关依赖  
- 修改后的 VM 配置（添加 IVSHMEM 设备）  
- 安装完成提示和运行指南

**基本流程：**

1. 检查系统依赖（如 SDL2, OpenGL, ivshmem-tools）  
2. 下载并安装 Looking Glass 客户端  
3. 检查/修改 VM 配置文件，添加 ivshmem 共享内存支持  
4. 提示用户在 Windows VM 内安装 Looking Glass Host  
5. 提供本地启动脚本或命令，快速打开 Looking Glass 窗口  
6. 记录日志，完成安装配置  

---

### 3.5 `start_vm.sh`

**功能：**

- 启动配置好的 Windows 虚拟机，确保直通设备、HugePages、Looking Glass 等优化生效  
- 提供一键命令，自动加载必要参数，避免用户每次手动输入复杂命令  
- 根据 VM 配置文件自动选择最佳启动方式（如 HugePages 支持、CPU亲和性设置）

**输入：**

- 需要启动的 VM 名称或配置路径  
- （可选）自定义启动参数（如额外启用 HugePages、大页内存数量、线程亲和性）

**输出：**

- 成功启动 Windows 虚拟机  
- 输出启动日志，便于排查错误

**基本流程：**

1. 加载用户或默认的 VM 配置（XML 文件）  
2. 确认直通设备已正确绑定 VFIO  
3. 检查 HugePages 可用情况（如果启用）  
4. 启动 QEMU/KVM 实例，附加 Looking Glass 共享内存支持  
5. 监控启动日志并显示关键提示信息  

---

### 3.6 `stop_vm.sh`

**功能：**

- 优雅地关闭正在运行的 Windows 虚拟机，确保资源释放  
- 清理 HugePages 占用（如适用）  
- 恢复主机端设备绑定（如 GPU 解绑 vfio，重新绑定到主系统驱动）  
- 停止 Looking Glass 相关服务或客户端进程  

**输入：**

- 需要关闭的 VM 名称或标识  

**输出：**

- 虚拟机关闭成功提示  
- 资源回收日志信息  

**基本流程：**

1. 检测指定 VM 是否运行中  
2. 发送优雅关机指令（ACPI shutdown），如超时则强制终止  
3. 卸载 HugePages 预留（如已使用）  
4. 恢复 GPU、USB 等设备到主机系统控制  
5. 结束 Looking Glass 相关进程  
6. 输出关机完成日志  

---

# AntiCheatVM - 设计文档 (Draft)

---

## 1. 项目目标与范围 (Goals & Scope)

**目标：**

- 在 Linux 环境下，使用 QEMU/KVM 虚拟化，实现面向 Windows 游戏的高性能、低检测风险的虚拟机环境。
- 支持 GPU passthrough (VFIO) 和 CPU/SMBIOS 伪装，进一步优化运行效率，尽可能降低受到防欺诈系统 (Anti-Cheat) 检测的风险。

**范围：**

- 支持主要环境：Linux Desktop (Fedora，Arch，Ubuntu)
- 支持游戏：目前主要目标是使 "鸣潮（国服）" 能够成功运行
- 依赖于 QEMU/KVM, VFIO, Looking Glass
- 允许自定义 VM 创建、启动、关闭流程

## 2. 总体架构 (Architecture Overview)

**核心组件：**

- `setup_vfio.sh`：配置 VFIO/IOMMU 环境，编译并绑定 GPU 设备
- `create_vm.py`：根据用户输入，生成 Windows VM 的 libvirt XML 配置
- `optimize_vm.py`：面向虚拟机内部 Windows 系统进行最优化处理
- `looking_glass_setup.sh`：部署 Looking Glass 服务器/客户端，进行显示连接
- `scripts/`：启动、关闭、检查 VM 的主要脚本

**支持文件：**

- `config/`：主要配置文件，包括 VFIO 设备列表，HugePages 配置，VM 模板 XML
- `docs/`：使用指南，故障排查手册
- `future/`：未来接入层（网页控制面板，游戏对应插件等）

## 3. 主要模块设计 (Modules and Components)

### 3.1 `setup_vfio.sh`

(...原内容略...)

### 3.2 `create_vm.py`

(...原内容略...)

### 3.3 `optimize_vm.py`

(...原内容略...)

### 3.4 `looking_glass_setup.sh`

(...原内容略...)

### 3.5 `start_vm.sh`

(...原内容略...)

### 3.6 `stop_vm.sh`

(...原内容略...)

### 3.7 `diagnostics.sh`

**功能：**

- 对宿主机环境进行自动检测，评估是否满足 AntiCheatVM 的运行需求。
- 检查 CPU 是否支持虚拟化和 VT-d/IOMMU。
- 检查当前系统是否正确加载 IOMMU 支持模块。
- 检查 GPU、声卡、USB 控制器等是否处于可绑定 VFIO 的 IOMMU 组中。
- 检查 HugePages 是否启用及当前配置是否足够。
- 检查是否已安装必要依赖组件（如 QEMU、virt-manager、Looking Glass 客户端等）。
- 提供诊断报告和优化建议。

**输入：**

- 无需用户输入，默认检查当前系统状态

**输出：**

- 命令行格式的系统检测结果报告
- 可选生成结构化 JSON 或 markdown 格式的诊断报告，供调试或文档存档使用

**基本流程：**

1. 检查 CPU 支持（通过 `/proc/cpuinfo`）
2. 检查 IOMMU 支持是否启用（`dmesg`/`journalctl`）
3. 检查 GPU 是否在独立 IOMMU 组中
4. 检查 VFIO 绑定状态
5. 检查 HugePages 配置及当前分配情况
6. 检查依赖工具链安装情况（QEMU、virtio、Looking Glass 等）
7. 汇总并输出检测结果及建议

---

### 3.7 `diagnostics.sh`

**功能：**

- 对宿主机环境进行自动检测，评估是否满足 AntiCheatVM 的运行需求。
- 检查 CPU 是否支持虚拟化和 VT-d/IOMMU。
- 检查当前系统是否正确加载 IOMMU 支持模块。
- 检查 GPU、声卡、USB 控制器等是否处于可绑定 VFIO 的 IOMMU 组中。
- 检查 HugePages 是否启用及当前配置是否足够。
- 检查是否已安装必要依赖组件（如 QEMU、virt-manager、Looking Glass 客户端等）。
- 提供诊断报告和优化建议。

**输入：**

- 无需用户输入，默认检查当前系统状态

**输出：**

- 命令行格式的系统检测结果报告
- 可选生成结构化 JSON 或 markdown 格式的诊断报告，供调试或文档存档使用

**基本流程：**

1. 检查 CPU 支持（通过 `/proc/cpuinfo`）
2. 检查 IOMMU 支持是否启用（`dmesg`/`journalctl`）
3. 检查 GPU 是否在独立 IOMMU 组中
4. 检查 VFIO 绑定状态
5. 检查 HugePages 配置及当前分配情况
6. 检查依赖工具链安装情况（QEMU、virtio、Looking Glass 等）
7. 汇总并输出检测结果及建议

### 3.8 `plugin_system/`

**功能目标（架构骨架）：**

- 为特定游戏设计可插拔的优化模块或反检测配置，便于自动适配不同游戏的特殊要求。
- 通过插件机制扩展虚拟机配置、反作弊绕过参数、启动策略和 VM 优化手段。
- 插件文件可通过统一结构描述游戏名称、适配条件、注入方式和配置覆盖内容。

**插件格式（建议）：**

- 每个插件为一个文件夹或 `.plugin.yaml` 文件，内容包括：
  - `name`：插件名称（如 WutheringWaves_CN）
  - `target_game`：适配游戏标识符（如鸣潮_CN）
  - `description`：用途说明
  - `vm_overrides`: libvirt XML 中需要 patch 的字段（如 CPU mask、SMBIOS）
  - `startup_hooks`: 启动时插入的额外参数（如 CPU 拓扑、QEMU flags）
  - `windows_optimize`: Windows VM 内需注入的注册表脚本、服务禁用项等

**输入：**

- 指定游戏标识（或由用户选择）
- 插件定义文件夹路径（默认从 `future/plugin_system/` 自动加载）

**输出：**

- 修改后的 VM 配置副本（应用插件后的 XML）
- 插件执行记录与状态日志

**基本流程：**

1. 用户通过命令或环境变量指定目标游戏
2. 脚本从 `plugin_system/` 中加载与目标匹配的插件
3. 自动解析 plugin.yaml 并应用相关配置到 VM XML 临时副本
4. 在 `start_vm.sh` 中使用该副本启动虚拟机
5. 提示用户插件是否应用成功及推荐操作

**注意：**
- 插件系统为可选模块，非必要路径下不加载插件。
- 未来可与 `optimize_vm.py` 和 `create_vm.py` 整合成“面向游戏模板系统”。

---

### 3.8 `plugin_system/`

**功能目标（架构骨架）：**

- 为特定游戏设计可插拔的优化模块或反检测配置，便于自动适配不同游戏的特殊要求。
- 通过插件机制扩展虚拟机配置、反作弊绕过参数、启动策略和 VM 优化手段。
- 插件文件可通过统一结构描述游戏名称、适配条件、注入方式和配置覆盖内容。

**插件格式（建议）：**

- 每个插件为一个文件夹或 `.plugin.yaml` 文件，内容包括：
  - `name`：插件名称（如 WutheringWaves\_CN）
  - `target_game`：适配游戏标识符（如鸣潮\_CN）
  - `description`：用途说明
  - `vm_overrides`: libvirt XML 中需要 patch 的字段（如 CPU mask、SMBIOS）
  - `startup_hooks`: 启动时插入的额外参数（如 CPU 拓扑、QEMU flags）
  - `windows_optimize`: Windows VM 内需注入的注册表脚本、服务禁用项等

**输入：**

- 指定游戏标识（或由用户选择）
- 插件定义文件夹路径（默认从 `future/plugin_system/` 自动加载）

**输出：**

- 修改后的 VM 配置副本（应用插件后的 XML）
- 插件执行记录与状态日志

**基本流程：**

1. 用户通过命令或环境变量指定目标游戏
2. 脚本从 `plugin_system/` 中加载与目标匹配的插件
3. 自动解析 plugin.yaml 并应用相关配置到 VM XML 临时副本
4. 在 `start_vm.sh` 中使用该副本启动虚拟机
5. 提示用户插件是否应用成功及推荐操作

**注意：**

- 插件系统为可选模块，非必要路径下不加载插件。
- 未来可与 `optimize_vm.py` 和 `create_vm.py` 整合成“面向游戏模板系统”。

---

### 附录：模块实现优先级与必要性说明

**`future/game_profiles/`**

- 作用：提供游戏兼容性预设配置模板（如默认 QEMU 参数、注册表建议）。
- 状态：**非必须**，建议在已有 plugin_system 基础上融合。
- 替代方案：直接在 `config/games/` 中维护模板配置 YAML 或 XML。

**`docs/` 模块策略**

- 作用：定义如何生成、维护项目文档（如 MkDocs、Sphinx 自动化）。
- 状态：**非必须**，早期开发阶段推荐保留 `README.md` 和 `HOWTO.md` 即可。
- 建议策略：待项目趋于稳定、或计划开源时，再系统规划文档结构与构建方式。

