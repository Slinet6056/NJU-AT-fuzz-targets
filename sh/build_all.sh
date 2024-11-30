#!/bin/bash

# Exit on any error
set -e

# Colors and formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_section() {
    echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}\n"
}

# Directory Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ROOT_DIR/build"
OUTPUT_DIR="$ROOT_DIR/output"
AFLPP_DIR="$BUILD_DIR/AFLplusplus"
LOGS_DIR="$ROOT_DIR/logs"

# Get timestamp for this build session
TIMESTAMP=$(date "+%Y%m%d_%H%M%S")
SESSION_LOG_DIR="$LOGS_DIR/$TIMESTAMP"
MAIN_LOG="$SESSION_LOG_DIR/build_all.log"

# Check if running on Ubuntu 22.04
if ! grep -q "Ubuntu 22.04" /etc/os-release; then
    log_error "This script requires Ubuntu 22.04. Current OS is not compatible."
    exit 1
fi

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install dependencies if not root, use sudo
install_dependencies() {
    log_section "Installing Dependencies"
    log_info "Starting installation of system dependencies..."
    if [ "$EUID" -ne 0 ]; then
        log_info "Running as non-root user, using sudo..."
        {
            sudo apt-get update
            sudo apt-get install -y build-essential python3-dev automake cmake git flex bison libglib2.0-dev libpixman-1-dev python3-setuptools cargo libgtk-3-dev
            sudo apt-get install -y lld-14 llvm-14 llvm-14-dev clang-14 || sudo apt-get install -y lld llvm llvm-dev clang
            sudo apt-get install -y gcc-$(gcc --version | head -n1 | sed 's/\..*//' | sed 's/.* //')-plugin-dev libstdc++-$(gcc --version | head -n1 | sed 's/\..*//' | sed 's/.* //')-dev
            sudo apt-get install -y ninja-build cpio libcapstone-dev wget curl python3-pip
        } >>"$MAIN_LOG" 2>&1
    else
        log_info "Running as root user..."
        {
            apt-get update
            apt-get install -y build-essential python3-dev automake cmake git flex bison libglib2.0-dev libpixman-1-dev python3-setuptools cargo libgtk-3-dev
            apt-get install -y lld-14 llvm-14 llvm-14-dev clang-14 || apt-get install -y lld llvm llvm-dev clang
            apt-get install -y gcc-$(gcc --version | head -n1 | sed 's/\..*//' | sed 's/.* //')-plugin-dev libstdc++-$(gcc --version | head -n1 | sed 's/\..*//' | sed 's/.* //')-dev
            apt-get install -y ninja-build cpio libcapstone-dev wget curl python3-pip
        } >>"$MAIN_LOG" 2>&1
    fi
    log_success "Dependencies installed successfully"
}

# Additional dependencies for specific projects
install_project_deps() {
    log_section "Installing Project-Specific Dependencies"
    log_info "Starting installation of project-specific dependencies..."
    if [ "$EUID" -ne 0 ]; then
        log_info "Running as non-root user, using sudo..."
        {
            sudo apt-get install -y libtool-bin libpcap-dev texinfo zlib1g-dev
        } >>"$MAIN_LOG" 2>&1
    else
        log_info "Running as root user..."
        {
            apt-get install -y libtool-bin libpcap-dev texinfo zlib1g-dev
        } >>"$MAIN_LOG" 2>&1
    fi
    log_success "Project dependencies installed successfully"
}

# Clone AFL++ source code
clone_aflpp() {
    log_section "Cloning AFL++"
    cd "$BUILD_DIR"
    if [ ! -d "AFLplusplus" ]; then
        log_info "Starting to clone AFL++ from GitHub..."
        if git clone https://github.com/AFLplusplus/AFLplusplus >>"$MAIN_LOG" 2>&1; then
            log_success "AFL++ cloned successfully"
        else
            log_error "Failed to clone AFL++. Check $MAIN_LOG for details"
            return 1
        fi
    else
        log_info "AFL++ directory already exists"
    fi
    cd "$SCRIPT_DIR"
}

# Install AFL++ if not already installed
install_aflpp() {
    log_section "Installing AFL++"
    if ! command_exists afl-fuzz; then
        log_info "AFL++ not found, starting installation..."
        cd "$BUILD_DIR/AFLplusplus"
        log_info "Building AFL++ distribution..."
        make distrib >>"$MAIN_LOG" 2>&1
        log_info "Installing AFL++..."
        if [ "$EUID" -ne 0 ]; then
            log_info "Running as non-root user, using sudo for installation..."
            sudo make install >>"$MAIN_LOG" 2>&1
        else
            log_info "Running as root user..."
            make install >>"$MAIN_LOG" 2>&1
        fi
        cd "$SCRIPT_DIR"
        log_success "AFL++ installed successfully"
    else
        log_info "AFL++ is already installed, skipping installation"
    fi
}

# Extract projects
extract_projects() {
    log_section "Extracting Projects"
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
            log_info "Extracting $project..."
            {
                if tar xzf "$project" -C "$BUILD_DIR" >>"$MAIN_LOG" 2>&1; then
                    expected_dir="${PROJECT_DIRS[$project]}"
                    if [ -d "$BUILD_DIR/$expected_dir" ]; then
                        log_success "Successfully extracted $project"
                    else
                        actual_dir=$(find "$BUILD_DIR" -maxdepth 1 -type d -name "${expected_dir%%-*}*" | head -n1)
                        if [ -n "$actual_dir" ]; then
                            mv "$actual_dir" "$BUILD_DIR/$expected_dir" >>"$MAIN_LOG" 2>&1
                            log_success "Successfully extracted $project (fixed directory name)"
                        else
                            log_error "Failed to extract $project - directory not found"
                            exit 1
                        fi
                    fi
                else
                    log_error "Failed to extract $project"
                    exit 1
                fi
            }
        else
            log_error "$project not found!"
            exit 1
        fi
    done
}

# Make all build scripts executable
make_scripts_executable() {
    log_section "Making Build Scripts Executable"
    chmod +x "$SCRIPT_DIR"/build_*.sh
    log_success "Build scripts made executable"
}

# Build all targets
build_targets() {
    log_section "Building Targets"
    log_info "Setting up AFL++ environment variables..."
    export AFLPP="$(dirname $(which afl-fuzz))"
    export AFLPP_DIR="$AFLPP_DIR"
    log_info "AFLPP path: $AFLPP"
    log_info "AFLPP_DIR: $AFLPP_DIR"

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

    BUILD_FAILED=0
    # Array to store background process PIDs and script names
    declare -a PIDS=()
    declare -A PID_TO_SCRIPT=()

    # Create logs directory
    log_info "Creating build logs directory at $SESSION_LOG_DIR/builds"
    mkdir -p "$SESSION_LOG_DIR/builds"

    # Group scripts by source directory
    log_info "Grouping build scripts by source directory..."
    declare -A DIR_TO_SCRIPTS=()
    for script in "${!BUILD_CONFIGS[@]}"; do
        source_dir="${BUILD_CONFIGS[$script]}"
        DIR_TO_SCRIPTS[$source_dir]+=" $script"
    done
    log_info "Found ${#DIR_TO_SCRIPTS[@]} unique source directories"

    # Execute scripts, running those from the same source directory sequentially
    log_info "Starting build process..."
    for source_dir in "${!DIR_TO_SCRIPTS[@]}"; do
        read -ra scripts <<<"${DIR_TO_SCRIPTS[$source_dir]}"
        if [ ${#scripts[@]} -gt 1 ]; then
            # Multiple scripts for same source - run sequentially in background
            log_info "Processing ${#scripts[@]} scripts for source directory $source_dir sequentially..."
            (
                for script in "${scripts[@]}"; do
                    script_name="${script%.sh}"
                    log_info "Starting build for $script_name from $source_dir..."
                    if ! bash "$SCRIPT_DIR/$script" "$BUILD_DIR/$source_dir" "$OUTPUT_DIR" >"$SESSION_LOG_DIR/builds/${script%.sh}.log" 2>&1; then
                        log_error "Build failed for $script_name (check $SESSION_LOG_DIR/builds/${script%.sh}.log for details)"
                        exit 1
                    fi
                done
            ) &
            pid=$!
            PIDS+=($pid)
            # Store each script name separately for better logging
            for script in "${scripts[@]}"; do
                PID_TO_SCRIPT[$pid]+="${script%.sh} "
            done
        else
            # Single script for source - run in parallel
            script="${scripts[0]}"
            script_name="${script%.sh}"
            log_info "Starting build for $script_name from $source_dir (parallel)..."
            bash "$SCRIPT_DIR/$script" "$BUILD_DIR/$source_dir" "$OUTPUT_DIR" >"$SESSION_LOG_DIR/builds/${script%.sh}.log" 2>&1 &
            pid=$!
            PIDS+=($pid)
            PID_TO_SCRIPT[$pid]=$script_name
        fi
    done

    # Wait for all processes
    log_info "Waiting for all build processes to complete..."
    for pid in "${PIDS[@]}"; do
        script_names=${PID_TO_SCRIPT[$pid]}
        log_info "Checking status for process $pid (${script_names})..."
        if ! wait $pid; then
            script_names=${PID_TO_SCRIPT[$pid]}
            for script_name in $script_names; do
                log_error "Build failed for $script_name (check $SESSION_LOG_DIR/builds/$script_name.log for details)"
            done
            BUILD_FAILED=1
        else
            script_names=${PID_TO_SCRIPT[$pid]}
            for script_name in $script_names; do
                log_success "Built $script_name successfully"
            done
        fi
    done

    if [ $BUILD_FAILED -eq 0 ]; then
        log_success "All builds completed successfully"
    else
        log_error "Some builds failed. Check the logs for details"
    fi
}

# Check build success
check_builds() {
    log_section "Checking Build Results"
    declare -A EXPECTED_BINARIES=(
        ["cxxfilt"]="cxxfilt.orig"
        ["readelf"]="readelf"
        ["nm-new"]="nm-new"
        ["objdump"]="objdump"
        ["djpeg"]="djpeg"
        ["readpng"]="readpng.orig"
        ["xmllint"]="xmllint"
        ["lua"]="lua"
        ["mjs"]="mjs"
        ["tcpdump"]="tcpdump"
    )

    FAILED=0
    for dir in "${!EXPECTED_BINARIES[@]}"; do
        binary="${EXPECTED_BINARIES[$dir]}"
        if [ ! -f "$OUTPUT_DIR/$dir/$binary" ]; then
            log_error "Binary not found: $binary"
            FAILED=1
        else
            if ! nm -C "$OUTPUT_DIR/$dir/$binary" | grep -q "__afl_"; then
                log_error "No AFL instrumentation found in $binary"
                FAILED=1
            else
                log_success "$binary built with AFL instrumentation"
            fi
        fi
    done

    if [ $BUILD_FAILED -eq 1 ] || [ $FAILED -eq 1 ]; then
        log_error "Build process failed:"
        [ $BUILD_FAILED -eq 1 ] && log_error "Some build scripts failed during execution"
        [ $FAILED -eq 1 ] && log_error "Some binaries are missing or lack AFL instrumentation"
        exit 1
    else
        log_success "All builds completed successfully with AFL instrumentation!"
    fi
}

# Cleanup function
cleanup() {
    log_section "Cleaning up previous build artifacts"

    # Check if directories exist before removing
    if [ -d "$BUILD_DIR" ]; then
        log_info "Removing previous build directory..."
        rm -rf "$BUILD_DIR"
    fi

    if [ -d "$OUTPUT_DIR" ]; then
        log_info "Removing previous output directory..."
        rm -rf "$OUTPUT_DIR"
    fi

    # Create new session log directory
    if [ ! -d "$LOGS_DIR" ]; then
        mkdir -p "$LOGS_DIR"
    fi
    mkdir -p "$SESSION_LOG_DIR/builds"

    log_success "Cleanup completed"
}

# Main execution
log_section "Starting Build Process"

# Cleanup previous builds
cleanup

# Create necessary directories after cleanup
mkdir -p "$BUILD_DIR"
mkdir -p "$OUTPUT_DIR"

# Make scripts executable
make_scripts_executable

# Clone AFL++ source code (always needed)
clone_aflpp

# Install AFL++ if not installed
if ! command_exists afl-fuzz; then
    install_dependencies
    install_aflpp
fi

# Install project dependencies
install_project_deps

# Extract projects
extract_projects

# Build all targets
build_targets

# Check build results
check_builds

log_success "Build process completed. Instrumented binaries are in $OUTPUT_DIR"
