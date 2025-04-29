<!--
 * @Author: @ydzat
 * @Date: 2025-04-29 19:35:16
 * @LastEditors: @ydzat
 * @LastEditTime: 2025-04-29 19:35:27
 * @Description: 
-->
## MVP 阶段开发计划（修订版）

**目标：完成最小可行产品（MVP）功能链，实现“在Linux上运行鸣潮国服”的核心流程。**

### 1 MVP 模块划分与优先级

| 模块                       | 目标描述                        | 是否必须 | 优先级 |
| ------------------------ | --------------------------- | ---- | ---- |
| `setup_vfio.sh`          | 自动配置 VFIO/IOMMU，生成绑定配置，提示重启 | ✅ 是  | 高   |
| `create_vm.py`           | 创建动态磁盘镜像，生成 VM libvirt 配置   | ✅ 是  | 高   |
| `start_vm.sh`            | 启动 VM，集成 Looking Glass 客户端  | ✅ 是  | 高   |
| `stop_vm.sh`             | 正常关闭 VM，回收资源                | ✅ 是  | 中   |
| `looking_glass_setup.sh` | 下载并配置客户端 + 添加共享内存支持         | ⚪ 可选 | 中   |
| `optimize_vm.py`         | 生成 .bat 批处理优化脚本（注册表、服务）     | ⚪ 可选 | 低   |
| `diagnostics.sh`         | 检测系统是否支持运行环境，输出兼容性报告        | ⚪ 可选 | 中   |
| `plugin_system/`         | 游戏专属配置注入机制                  | ❌ 暂缓 | 最低  |

---

### 2 目录与文件初始结构（建议）

```plaintext
AntiCheatVM/
├── install.sh                # 安装依赖与初始化环境（后续可拆分）
├── setup_vfio.sh             # VFIO 初始化配置脚本
├── create_vm.py              # 生成 VM 配置与磁盘
├── start_vm.sh               # 启动 VM 实例
├── stop_vm.sh                # 停止 VM 实例
├── optimize_vm.py            # 生成 Windows 优化脚本（可选）
├── looking_glass_setup.sh    # Looking Glass 部署脚本
├── diagnostics.sh            # 系统能力检查脚本
├── config/                   # 所有配置文件模板和用户设定
│   ├── vfio_devices.yaml
│   └── vm_template.xml
├── scripts/                  # 封装常用命令（launch_wrapper 等）
├── future/
│   └── plugin_system/        # 游戏插件骨架
└── docs/
    └── HOWTO.md              # 使用说明
```

---

### 3 初步开发建议

- 每个模块先实现主流程，再迭代细节与优化。
- 启动流程（setup → create → start → shutdown）优先串通。
- 每开发完成一个模块后运行 smoke test。
- 记录已完成模块、存在的问题和 TODO。
- **使用 Python venv 虚拟环境进行开发隔离。**
  - 推荐路径为 `AntiCheatVM/venv/`
  - 建议通过 install.sh 自动创建并激活 venv，避免系统污染
  - 所需 Python 依赖包括：`pyyaml`, `lxml`（后续可按需补充）

---

### 4 install.sh 示例模板（使用 venv）

```bash
#!/bin/bash

set -e

echo "[AntiCheatVM] 初始化安装环境..."

# 安装系统依赖（以 Debian/Ubuntu 为例）
echo "[+] 安装基础包..."
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system virt-manager \
    python3 python3-venv python3-pip make git

# 创建 Python 虚拟环境
if [ ! -d "venv" ]; then
  echo "[+] 创建 Python 虚拟环境 venv/"
  python3 -m venv venv
fi

# 激活虚拟环境并安装依赖
source venv/bin/activate
pip install --upgrade pip
pip install pyyaml lxml

echo "[AntiCheatVM] 安装完成！请执行以下命令激活环境："
echo "  source venv/bin/activate"
echo "然后你可以运行 create_vm.py 等模块。"
```

---

### 5 里程碑阶段划分（建议）

| 阶段       | 关键成果                                                 |
|------------|----------------------------------------------------------|
| `MVP-Init` | 完成 install.sh 脚本，建立项目结构，初始化 Git 仓库        |
| `MVP-Core` | 实现 `setup_vfio.sh`、`create_vm.py`、`start_vm.sh` 基础流程 |
| `MVP-Test` | 跑通完整流程：VFIO + 启动 + 关闭 + 启动鸣潮安装器          |
| `MVP-Polish` | 添加日志输出、优化脚本结构、整理配置文档与 HOWTO.md       |
| `Post-MVP` | 实现可选模块，如 optimize_vm、diagnostics、plugin_system |
