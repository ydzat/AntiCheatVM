#!/bin/bash
###
 # @Author: @ydzat
 # @Date: 2025-04-29 23:00:00
 # @LastEditors: @ydzat
 # @LastEditTime: 2025-04-29 23:00:00
 # @Description: Activate Python virtual environment for AntiCheatVM
### 

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default venv paths - prioritize .venv in project directory
VENV_PATH="${SCRIPT_DIR}/.venv"
ALTERNATE_VENV_PATH="${SCRIPT_DIR}/venv"
THIRD_VENV_PATH="${HOME}/.virtualenvs/anticheatvm"

# Check if venv directory exists, try common locations
if [ -d "${VENV_PATH}" ]; then
    echo "[i] Found venv at: ${VENV_PATH}"
elif [ -d "${ALTERNATE_VENV_PATH}" ]; then
    echo "[i] Found venv at: ${ALTERNATE_VENV_PATH}"
    VENV_PATH="${ALTERNATE_VENV_PATH}"
elif [ -d "${THIRD_VENV_PATH}" ]; then
    echo "[i] Found venv at: ${THIRD_VENV_PATH}"
    VENV_PATH="${THIRD_VENV_PATH}"
else
    # Try to find venv in parent directories
    PARENT_DIR=$(dirname "${SCRIPT_DIR}")
    if [ -d "${PARENT_DIR}/.venv" ]; then
        echo "[i] Found venv at: ${PARENT_DIR}/.venv"
        VENV_PATH="${PARENT_DIR}/.venv"
    elif [ -d "${PARENT_DIR}/venv" ]; then
        echo "[i] Found venv at: ${PARENT_DIR}/venv"
        VENV_PATH="${PARENT_DIR}/venv"
    else
        echo "[WARNING] Virtual environment not found at expected locations."
        echo "If you have a virtual environment, please specify its path:"
        read -p "venv path (leave empty to create a new one): " USER_VENV_PATH
        
        if [ -n "${USER_VENV_PATH}" ]; then
            if [ -d "${USER_VENV_PATH}" ]; then
                VENV_PATH="${USER_VENV_PATH}"
            else
                echo "[ERROR] Directory does not exist: ${USER_VENV_PATH}"
                exit 1
            fi
        else
            # Use .venv as default for new environments
            VENV_PATH="${SCRIPT_DIR}/.venv"
            echo "[i] Creating new virtual environment at ${VENV_PATH}..."
            python3 -m venv "${VENV_PATH}"
            if [ $? -ne 0 ]; then
                echo "[ERROR] Failed to create virtual environment"
                exit 1
            fi
            echo "[✓] Virtual environment created successfully"
        fi
    fi
fi

# Activate virtual environment
echo "[+] Activating virtual environment..."
source "${VENV_PATH}/bin/activate"

if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to activate virtual environment"
    exit 1
fi

echo "[✓] Virtual environment activated"
echo "[i] Python version: $(python --version)"
echo "[i] Virtual environment: $VIRTUAL_ENV"

# Check if requirements.txt exists and offer to install packages
if [ -f "${SCRIPT_DIR}/requirements.txt" ]; then
    echo "[i] Found requirements.txt file"
    read -p "Install required packages? (y/n): " INSTALL_PACKAGES
    if [[ "$INSTALL_PACKAGES" == "y" || "$INSTALL_PACKAGES" == "Y" ]]; then
        echo "[+] Installing required packages..."
        pip install -r "${SCRIPT_DIR}/requirements.txt"
    fi
fi

# If arguments are provided, execute them with the venv activated
if [ "$#" -gt 0 ]; then
    echo "[i] Executing command: $@"
    "$@"
    EXIT_CODE=$?
    echo "[i] Command completed with exit code: $EXIT_CODE"
fi

# Keep the environment activated for interactive use
echo ""
echo "Virtual environment is now active. You can now run Python scripts."
echo "Examples:"
echo "  python create_vm.py"
echo ""
echo "To deactivate the virtual environment, run 'deactivate'"
echo ""

# Create a new shell with the environment activated
if [ -z "$@" ]; then
    exec $SHELL
fi