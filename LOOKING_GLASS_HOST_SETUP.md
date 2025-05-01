# Windows Looking Glass 主机设置指南

## 1. 下载与安装

1. 从官方网站下载 Looking Glass 主机应用程序:
   https://looking-glass.io/artifact/stable/host

2. 在Windows虚拟机中运行下载的安装程序

3. 在安装过程中确保选中"Install IVSHMEM Driver"选项

## 2. 配置IVSHMEM驱动

如果在设备管理器中看到未识别的"PCI标准RAM控制器":

1. 打开设备管理器（右键点击开始菜单 -> 设备管理器）
2. 找到带有黄色感叹号的"PCI标准RAM控制器"
3. 右键点击并选择"更新驱动程序"
4. 选择"浏览计算机以查找驱动程序"
5. 浏览到 `C:\Program Files\Looking Glass (host)\ivshmem`
6. 完成驱动安装

## 3. 配置Looking Glass主机服务

1. 安装完成后，Looking Glass服务应自动启动
2. 从开始菜单打开Looking Glass主机应用程序
3. 确认"Service State"显示为"Running"
4. 确认"IVSHMEM"部分显示正确的内存大小（如32MB）

## 4. 优化设置

为获得最佳性能:

1. 对于NVIDIA显卡:
   - 确保"NvFBC"选项已启用
   
2. 对于AMD显卡:
   - 尝试不同的捕获方式（默认、GDI等）

3. 设置Windows自动登录以便无人值守启动:
   - 打开运行窗口（Win+R）
   - 输入 `netplwiz` 并运行
   - 取消选中"用户必须输入用户名和密码"
   - 输入登录凭据并确认

## 5. 故障排除

如果遇到问题:

- 重启虚拟机后再次尝试
- 确认您的GPU驱动是最新版本
- 检查Windows事件查看器中的错误
- 确认ivshmem设备显示在设备管理器中

更多帮助请访问: https://looking-glass.io/docs
