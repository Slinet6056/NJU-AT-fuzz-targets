#!/bin/bash

# Exit on any error
set -e

# Check if running on Ubuntu 22.04
if ! grep -q "Ubuntu 22.04" /etc/os-release; then
    echo "This script requires Ubuntu 22.04. Current OS is not compatible."
    exit 1
fi

# Directory Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ROOT_DIR/build"
OUTPUT_DIR="$ROOT_DIR/output"
AFLPP_DIR="$BUILD_DIR/AFLplusplus"

# Create necessary directories
mkdir -p "$BUILD_DIR"
mkdir -p "$OUTPUT_DIR"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install dependencies if not root, use sudo
install_dependencies() {
    echo "Installing dependencies..."
    if [ "$EUID" -ne 0 ]; then
        sudo apt-get update
        sudo apt-get install -y build-essential python3-dev automake cmake git flex bison libglib2.0-dev libpixman-1-dev python3-setuptools cargo libgtk-3-dev
        sudo apt-get install -y lld-14 llvm-14 llvm-14-dev clang-14 || sudo apt-get install -y lld llvm llvm-dev clang
        sudo apt-get install -y gcc-$(gcc --version | head -n1 | sed 's/\..*//' | sed 's/.* //')-plugin-dev libstdc++-$(gcc --version | head -n1 | sed 's/\..*//' | sed 's/.* //')-dev
        sudo apt-get install -y ninja-build cpio libcapstone-dev wget curl python3-pip
    else
        apt-get update
        apt-get install -y build-essential python3-dev automake cmake git flex bison libglib2.0-dev libpixman-1-dev python3-setuptools cargo libgtk-3-dev
        apt-get install -y lld-14 llvm-14 llvm-14-dev clang-14 || apt-get install -y lld llvm llvm-dev clang
        apt-get install -y gcc-$(gcc --version | head -n1 | sed 's/\..*//' | sed 's/.* //')-plugin-dev libstdc++-$(gcc --version | head -n1 | sed 's/\..*//' | sed 's/.* //')-dev
        apt-get install -y ninja-build cpio libcapstone-dev wget curl python3-pip
    fi
}

# Additional dependencies for specific projects
install_project_deps() {
    echo "Installing project-specific dependencies..."
    if [ "$EUID" -ne 0 ]; then
        # For libxml2
        sudo apt-get install -y libtool-bin
        # For tcpdump
        sudo apt-get install -y libpcap-dev
        # For binutils
        sudo apt-get install -y texinfo
        # For general build
        sudo apt-get install -y zlib1g-dev
    else
        # For libxml2
        apt-get install -y libtool-bin
        # For tcpdump
        apt-get install -y libpcap-dev
        # For binutils
        apt-get install -y texinfo
        # For general build
        apt-get install -y zlib1g-dev
    fi
}

# Install AFL++ if not already installed
install_aflpp() {
    if ! command_exists afl-fuzz; then
        echo "Installing AFL++..."
        cd "$BUILD_DIR"
        if [ ! -d "AFLplusplus" ]; then
            git clone https://github.com/AFLplusplus/AFLplusplus
        fi
        cd AFLplusplus
        make distrib
        if [ "$EUID" -ne 0 ]; then
            sudo make install
        else
            make install
        fi
        cd "$SCRIPT_DIR"
    else
        echo "AFL++ is already installed"
    fi
}

# Extract projects
extract_projects() {
    echo "Extracting projects..."
    cd "$ROOT_DIR"

    # Array of project archives and their expected directory names
    declare -A PROJECT_DIRS=(
        ["binutils-2.28.tar.gz"]="binutils-2.28"
        ["libjpeg-turbo-3.0.4.tar.gz"]="libjpeg-turbo-3.0.4"
        ["libpng-1.6.29.tar.gz"]="libpng-1.6.29"
        ["libxml2-2.13.4.tar.gz"]="libxml2-2.13.4"
        ["lua-5.4.7.tar.gz"]="lua-5.4.7"
        ["mjs-2.20.0.tar.gz"]="mjs-2.20.0"
        ["tcpdump-tcpdump-4.99.5.tar.gz"]="tcpdump-tcpdump-4.99.5"
    )

    # Extract each project
    for project in "${!PROJECT_DIRS[@]}"; do
        if [ -f "$project" ]; then
            echo "Extracting $project..."
            tar xf "$project" -C "$BUILD_DIR"
            # Ensure directory name matches expected
            expected_dir="${PROJECT_DIRS[$project]}"
            if [ -d "$BUILD_DIR/$expected_dir" ]; then
                echo "Directory $expected_dir exists as expected"
            else
                echo "Warning: Directory $expected_dir not found after extraction!"
                # Try to find the actual directory
                actual_dir=$(find "$BUILD_DIR" -maxdepth 1 -type d -name "${expected_dir%%-*}*" | head -n1)
                if [ -n "$actual_dir" ]; then
                    echo "Found similar directory: $actual_dir"
                    mv "$actual_dir" "$BUILD_DIR/$expected_dir"
                else
                    echo "Error: Could not find extracted directory for $project"
                    exit 1
                fi
            fi
        else
            echo "Warning: $project not found!"
            exit 1
        fi
    done
}

# Make all build scripts executable
make_scripts_executable() {
    echo "Making build scripts executable..."
    chmod +x "$SCRIPT_DIR"/build_*.sh
}

# Build all targets
build_targets() {
    echo "Building all targets..."
    export AFLPP="$(dirname $(which afl-fuzz))"

    # Array of build scripts and their corresponding source directories
    declare -A BUILD_CONFIGS=(
        ["build_cxxfilt.sh"]="binutils-2.28"
        ["build_readelf.sh"]="binutils-2.28"
        ["build_nm.sh"]="binutils-2.28"
        ["build_objdump.sh"]="binutils-2.28"
        ["build_djpeg.sh"]="libjpeg-turbo-3.0.4"
        ["build_readpng.sh"]="libpng-1.6.29"
        ["build_xmllint.sh"]="libxml2-2.13.4"
        ["build_lua.sh"]="lua-5.4.7"
        ["build_mjs.sh"]="mjs-2.20.0"
        ["build_tcpdump.sh"]="tcpdump-tcpdump-4.99.5"
    )

    # Execute each build script
    for script in "${!BUILD_CONFIGS[@]}"; do
        source_dir="$BUILD_DIR/${BUILD_CONFIGS[$script]}"
        echo "Running $script with source dir: $source_dir"
        if ! bash "$SCRIPT_DIR/$script" "$source_dir" "$OUTPUT_DIR"; then
            echo "Warning: Build script $script failed!"
            echo "Continuing with next target..."
        fi
    done
}

# Function to check build success
check_builds() {
    echo "Checking build results..."
    declare -A EXPECTED_BINARIES=(
        ["cxxfilt"]="cxxfilt"
        ["readelf"]="readelf"
        ["nm-new"]="nm-new"
        ["objdump"]="objdump"
        ["djpeg"]="djpeg"
        ["readpng"]="readpng"
        ["xmllint"]="xmllint"
        ["lua"]="lua"
        ["mjs"]="mjs"
        ["tcpdump"]="tcpdump"
    )

    FAILED=0
    for dir in "${!EXPECTED_BINARIES[@]}"; do
        binary="${EXPECTED_BINARIES[$dir]}"
        if [ ! -f "$OUTPUT_DIR/$dir/$binary" ]; then
            echo "Error: Binary $binary not found in $OUTPUT_DIR/$dir"
            FAILED=1
        else
            echo "Success: Found $binary in $OUTPUT_DIR/$dir"
            # Check AFL instrumentation
            echo "Checking AFL instrumentation for $binary..."
            if ! nm -C "$OUTPUT_DIR/$dir/$binary" | grep -q "afl"; then
                echo "Warning: No AFL instrumentation found in $binary"
                FAILED=1
            else
                echo "Success: AFL instrumentation found in $binary"
            fi
        fi
    done

    if [ $FAILED -eq 1 ]; then
        echo "Some builds failed or missing AFL instrumentation. Please check the error messages above."
    else
        echo "All builds completed successfully with AFL instrumentation!"
    fi
}

# Main execution
echo "Starting build process..."

# Make scripts executable
make_scripts_executable

# Install dependencies
install_dependencies

# Install project-specific dependencies
install_project_deps

# Install AFL++
install_aflpp

# Extract projects
extract_projects

# Build all targets
build_targets

# Check build results
check_builds

echo "Build process completed. Instrumented binaries are in $OUTPUT_DIR"
