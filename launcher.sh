#!/bin/bash
# RPi5 Fast Boot Launcher
# Interactive menu to select UI system and build image

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SCRIPT="$SCRIPT_DIR/build_rpi5_fastboot.sh"

# Check if build script exists
if [ ! -f "$BUILD_SCRIPT" ]; then
    echo "Error: build_rpi5_fastboot.sh not found in $SCRIPT_DIR"
    exit 1
fi

# Make build script executable
chmod +x "$BUILD_SCRIPT"

# Function to show menu
show_menu() {
    clear
    echo "=========================================="
    echo "  RPi5 Fast Boot Image Builder"
    echo "=========================================="
    echo ""
    echo "Select UI system to build:"
    echo ""
    echo "  1) realdash"
    echo "  2) epictuner (Coming soon)"
    echo "  3) ts-dash (Coming soon)"
    echo "  4) Blank/Base image (no UI)"
    echo "  5) Exit"
    echo ""
    echo -n "Enter your choice [1-5]: "
}

# Main menu loop
while true; do
    show_menu
    read -r choice
    
    case $choice in
        1)
            echo ""
            echo "Building image with realdash UI..."
            "$BUILD_SCRIPT" --ui realdash "$@"
            exit 0
            ;;
        2)
            echo ""
            echo "epictuner is coming soon. Please check back later."
            echo "Press Enter to continue..."
            read -r
            ;;
        3)
            echo ""
            echo "ts-dash is coming soon. Please check back later."
            echo "Press Enter to continue..."
            read -r
            ;;
        4)
            echo ""
            echo "Building blank/base image (no UI)..."
            "$BUILD_SCRIPT" "$@"
            exit 0
            ;;
        5)
            echo ""
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo ""
            echo "Invalid option. Please select 1-5."
            echo "Press Enter to continue..."
            read -r
            ;;
    esac
done
