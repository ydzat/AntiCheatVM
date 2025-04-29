# Looking Glass 详细使用指南

本指南将帮助您正确配置和使用Looking Glass，实现低延迟的虚拟机图形显示。

## 正确的启动顺序

对于GPU直通和Looking Glass，按照正确的顺序启动各组件非常重要：

1. **先确保主机系统已准备好**:
   ```bash
   # 导航到AntiCheatVM目录
   cd ~/workspace/AntiCheatVM
   
   # 检查GPU状态
   sudo ./gpu-manager.sh status
   ```

2. **切换GPU到VM模式**:
   ```bash
   sudo ./gpu-manager.sh vm
   ```
   此时您的系统可能会切换到文本模式，这是预期行为。

3. **启动虚拟机**:
   ```bash
   ./start_vm.sh
   ```
   确保虚拟机完全启动并加载Windows。

4. **在Windows虚拟机中启动Looking Glass Host**:
   - 等待Windows完全加载
   - 确保您可以看到Windows桌面（通过直接连接到被直通的GPU的显示器）
   - **然后**才启动Looking Glass Host应用程序

5. **在Linux主机上运行Looking Glass客户端**:
   ```bash
   looking-glass-client
   ```
   如果没有自动启动，可以手动运行此命令。

## Windows虚拟机配置

为了确保Looking Glass Host在Windows中正确运行：

1. **确认IVSHMEM驱动程序已安装**:
   - 打开设备管理器
   - 检查是否有名为"IVSHMEM Device"的设备
   - 如果显示为未知设备，请安装驱动程序（可从Looking Glass网站下载）

2. **以管理员身份运行Looking Glass Host**:
   - 右键点击Looking Glass Host图标
   - 选择"以管理员身份运行"
   - 配置为开机自动启动，也使用管理员权限

3. **配置Looking Glass Host**:
   - 右键单击任务栏中的图标
   - 选择"Settings"
   - 设置推荐配置:
     - Capture: DXGI
     - 帧率: 60 (或与您的显示器匹配)
     - 压缩: NVENC/VGPU (如果可用)
     - 如果有崩溃，尝试降低设置

4. **故障排除**：
   - 如果Looking Glass Host启动后立即关闭，请查看Windows事件查看器中的应用程序日志
   - 临时禁用Windows防火墙和杀毒软件，看是否有所改善
   - 尝试以兼容模式运行

## 共享内存配置验证

确保共享内存设备正确配置：

1. **检查Linux主机上的共享内存文件**:
   ```bash
   ls -la /dev/shm/looking-glass
   ```
   确认权限设置正确（660，用户:qemu）

2. **检查虚拟机XML配置**:
   ```bash
   virsh dumpxml AntiCheatVM | grep -A 5 "shmem"
   ```
   应该能看到类似以下内容：
   ```xml
   <shmem name='looking-glass'>
     <model type='ivshmem-plain'/>
     <size unit='M'>32</size>
   </shmem>
   ```

3. **如果需要，更新虚拟机配置**:
   ```bash
   ./looking_glass_setup.sh
   ```
   此脚本将自动修复大部分配置问题。

## 常见问题与解决方案

1. **Looking Glass Host启动后立即关闭**:
   - 确保GPU已经成功直通到VM
   - 检查Windows设备管理器中NVIDIA GPU是否正常显示
   - 尝试更新NVIDIA驱动程序到最新版本
   - 确认IVSHMEM驱动已正确安装

2. **无法在两者间切换键盘/鼠标**:
   - 使用Pause键（有时标记为Break或Pause/Break）
   - 如果Pause键不工作，可尝试使用ScrollLock键
   - 确保Looking Glass客户端窗口处于活动状态

3. **画面卡顿或延迟高**:
   - 调整Looking Glass Host和客户端的性能设置
   - 减少分辨率或帧率
   - 禁用不必要的视觉效果
   - 确保共享内存大小足够（32MB通常足够）

4. **没有声音**:
   - Looking Glass主要处理视频，不处理音频
   - 确保虚拟机配置了声音设备(如ICH9或AC97)

## 高级配置

如果基本设置无法解决您的问题，可以尝试以下高级配置：

1. **增加共享内存大小**:
   编辑虚拟机XML，将共享内存大小从32M增加到64M或更高

2. **启用更详细的日志**:
   ```bash
   looking-glass-client -d debug
   ```

3. **使用命令行参数调优**:
   ```bash
   looking-glass-client -F input:grabKeyboardOnFocus -F win:noScreensaver
   ```

4. **如果使用多显示器**:
   ```bash
   looking-glass-client -F win:fullScreen -F win:useBufferBoost
   ```

按照这些步骤操作，您应该能够解决Looking Glass Host在Windows中启动后立即关闭的问题。