# AntiCheatVM 别名和函数
# 将此文件添加到你的~/.bashrc: source /path/to/aliases.sh

# GPU状态查看
alias hows-my-gpu='echo "NVIDIA Dedicated Graphics" | grep "NVIDIA" && lspci -nnk | grep "01:00.0" -A 2 | grep "Kernel driver in use" && echo "Enable and disable the dedicated NVIDIA GPU with nvidia-enable and nvidia-disable"'

# GPU切换别名
alias nvidia-enable='sudo /home/ydzat/workspace/AntiCheatVM/switch_gpu.sh nvidia'
alias nvidia-disable='sudo /home/ydzat/workspace/AntiCheatVM/switch_gpu.sh vfio'

# Looking Glass简化命令
alias looking-glass='looking-glass-client -s -m 97'
