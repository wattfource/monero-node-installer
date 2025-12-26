#!/bin/bash
#
#===============================================================================
#
#   MONERO NODE SETUP SCRIPT FOR DEBIAN 13
#   
#   A fully interactive setup script for deploying and managing Monero nodes
#   on Debian 13 (Trixie) systems, with support for both standard wallet
#   nodes and mining pool backend configurations.
#
#===============================================================================
#
#   USAGE:
#       sudo ./setup-monero.sh
#       sudo ./setup-monero.sh --skip-update-check
#
#   CAPABILITIES:
#       • Fresh Installation - Install Monero node from scratch
#       • Update - Update Monero binaries while preserving configuration
#       • Reconfigure - Change node settings without reinstalling
#       • Wallet Management - Create or import wallets (for mining pools)
#       • Self-Update - Automatically checks for and installs script updates
#
#   REQUIREMENTS:
#       - Debian 13 (Trixie) or compatible Debian-based system
#       - Root/sudo access
#       - Minimum 4GB RAM (8GB recommended)
#       - Minimum 220GB disk space for full node (65GB for pruned)
#       - Internet connection for downloading Monero binaries
#
#   NODE TYPES:
#       - Standard Node: For personal wallet use, remote wallet connections
#       - Mining Pool Node: Optimized backend for mining pool software
#
#   BLOCKCHAIN MODES:
#       - Full Node: Complete blockchain (~180GB), maximum security
#       - Pruned Node: Reduced blockchain (~65GB), still validates all blocks
#
#   CONFIGURATION FILES:
#       - /etc/monero/monerod.conf     - Main daemon configuration
#       - /etc/monero/pool-wallet.conf - Pool wallet info (pool mode only)
#       - /etc/systemd/system/monerod.service - Systemd service file
#
#   DEFAULT PATHS:
#       - Binaries:    /opt/monero/
#       - Blockchain:  /var/lib/monero/
#       - Wallets:     /var/lib/monero/wallets/
#       - Logs:        /var/log/monero/
#       - Config:      /etc/monero/
#
#   NETWORK PORTS:
#       - 18080/tcp: P2P (peer-to-peer network connections)
#       - 18081/tcp: RPC (wallet/pool software connections)
#       - 18082/tcp: ZMQ (block notifications, mining pool mode only)
#
#   REPOSITORY:
#       https://github.com/wattfource/monero-node-installer
#
#   LICENSE:
#       MIT License - See repository for details
#
#===============================================================================

# Don't use set -e - we handle errors explicitly for better user feedback
# set -e

#===============================================================================
# SCRIPT VERSION AND UPDATE SETTINGS
#===============================================================================

# Script version - increment this with each release
SCRIPT_VERSION="1.1.0"

# GitHub repository for updates
GITHUB_REPO="wattfource/monero-node-installer"
GITHUB_RAW_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/setup-monero.sh"
GITHUB_VERSION_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/VERSION"

#===============================================================================
# CONFIGURATION DEFAULTS
#===============================================================================

# Monero version and download URLs
# Note: MONERO_URL always downloads the latest release
MONERO_VERSION="0.18.4.4"
MONERO_URL="https://downloads.getmonero.org/cli/linux64"
MONERO_HASHES_URL="https://www.getmonero.org/downloads/hashes.txt"

# GPG key for binaryFate (official Monero release signer)
GPG_KEY_ID="81AC591FE9C4B65C5806AFC3F0AF4D462A0BDF92"
GPG_KEY_SERVER="hkps://keyserver.ubuntu.com"

# Default installation paths
INSTALL_DIR="/opt/monero"
DATA_DIR="/var/lib/monero"
WALLET_DIR="/var/lib/monero/wallets"
CONFIG_DIR="/etc/monero"
LOG_DIR="/var/log/monero"
MONERO_USER="monero"

# Default network configuration
RPC_BIND_IP="0.0.0.0"
RPC_PORT="18081"
P2P_PORT="18080"
ZMQ_PORT="18082"

# Default mode settings
NODE_TYPE="standard"           # standard or pool
BLOCKCHAIN_MODE="full"         # full or pruned
CONFIGURE_FIREWALL="Y"
ENABLE_RPC_LOGIN="N"
RPC_USERNAME=""
RPC_PASSWORD=""

# Pool wallet settings
POOL_WALLET_ADDRESS=""
CREATE_POOL_WALLET="N"

# Block notification settings (for mining pool)
ENABLE_ZMQ="N"                 # ZMQ block notifications (can have issues on some systems)
ENABLE_BLOCKNOTIFY="N"         # blocknotify script (alternative to ZMQ)
BLOCKNOTIFY_CMD=""             # Command to run on new block

# Installation mode
SETUP_MODE="fresh"             # fresh, update, reconfigure

#===============================================================================
# TERMINAL COLORS
#===============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

#===============================================================================
# HELPER FUNCTIONS
#===============================================================================

print_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                      ║"
    echo "║                MONERO NODE SETUP FOR DEBIAN 13                       ║"
    echo "║                                                                      ║"
    echo "║                    Interactive Setup Wizard                          ║"
    echo "║                                                                      ║"
    echo -e "║                        Version ${SCRIPT_VERSION}                              ║"
    echo "║                                                                      ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_subsection() {
    echo ""
    echo -e "${BLUE}───────────────────────────────────────────────────────────────────────${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}───────────────────────────────────────────────────────────────────────${NC}"
    echo ""
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_step() {
    echo -e "${MAGENTA}[STEP $1]${NC} $2"
}

prompt_yes_no() {
    local prompt="$1"
    local default="$2"
    local result
    
    if [[ "$default" == "Y" ]]; then
        echo -ne "${YELLOW}${prompt} [Y/n]:${NC} "
    else
        echo -ne "${YELLOW}${prompt} [y/N]:${NC} "
    fi
    
    read -r result
    result="${result:-$default}"
    
    if [[ "$result" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

prompt_input() {
    local prompt="$1"
    local default="$2"
    local result
    
    echo -ne "${YELLOW}${prompt} [${default}]:${NC} "
    read -r result
    echo "${result:-$default}"
}

prompt_input_required() {
    local prompt="$1"
    local result=""
    
    while [[ -z "$result" ]]; do
        echo -ne "${YELLOW}${prompt}:${NC} "
        read -r result
        if [[ -z "$result" ]]; then
            print_warning "This field is required"
        fi
    done
    echo "$result"
}

prompt_secret() {
    local prompt="$1"
    local result
    
    echo -ne "${YELLOW}${prompt}:${NC} "
    read -rs result
    echo ""
    echo "$result"
}

prompt_choice() {
    local prompt="$1"
    shift
    local options=("$@")
    local choice
    
    echo -e "${YELLOW}${prompt}${NC}"
    echo ""
    
    for i in "${!options[@]}"; do
        echo -e "  ${CYAN}$((i+1)))${NC} ${options[$i]}"
    done
    
    echo ""
    echo -ne "${YELLOW}Enter choice [1-${#options[@]}]:${NC} "
    read -r choice
    
    # Validate choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt "${#options[@]}" ]]; then
        choice=1
    fi
    
    echo "$choice"
}

#===============================================================================
# SELF-UPDATE FUNCTIONALITY
#===============================================================================

check_for_script_update() {
    # Skip update check if flag is passed
    if [[ "$1" == "--skip-update-check" ]] || [[ "$SKIP_UPDATE_CHECK" == "true" ]]; then
        return 0
    fi
    
    echo -e "${BLUE}[INFO]${NC} Checking for script updates..."
    
    # Try to fetch the remote version
    local remote_version=""
    remote_version=$(curl -fsSL --connect-timeout 5 "$GITHUB_VERSION_URL" 2>/dev/null || echo "")
    
    # If VERSION file doesn't exist, try to extract version from the script itself
    if [[ -z "$remote_version" ]]; then
        remote_version=$(curl -fsSL --connect-timeout 10 "$GITHUB_RAW_URL" 2>/dev/null | grep '^SCRIPT_VERSION=' | head -1 | cut -d'"' -f2 || echo "")
    fi
    
    if [[ -z "$remote_version" ]]; then
        echo -e "${YELLOW}[!]${NC} Could not check for updates (no internet or repository unavailable)"
        echo ""
        return 0
    fi
    
    # Compare versions
    if [[ "$remote_version" == "$SCRIPT_VERSION" ]]; then
        echo -e "${GREEN}[✓]${NC} Script is up to date (v${SCRIPT_VERSION})"
        echo ""
        return 0
    fi
    
    # Version differs - offer update
    echo ""
    echo -e "${YELLOW}════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}                      SCRIPT UPDATE AVAILABLE                           ${NC}"
    echo -e "${YELLOW}════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Current version:  ${RED}v${SCRIPT_VERSION}${NC}"
    echo -e "  Latest version:   ${GREEN}v${remote_version}${NC}"
    echo ""
    echo "  Updating will download the latest script from GitHub and restart."
    echo "  Your Monero configuration and blockchain data are NOT affected."
    echo ""
    
    echo -ne "${YELLOW}Would you like to update now? [Y/n]:${NC} "
    read -r response
    response="${response:-Y}"
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        perform_script_update
    else
        echo ""
        echo -e "${BLUE}[INFO]${NC} Continuing with current version (v${SCRIPT_VERSION})"
        echo ""
    fi
}

perform_script_update() {
    echo ""
    echo -e "${BLUE}[INFO]${NC} Downloading latest script..."
    
    local script_path="$(readlink -f "$0")"
    local temp_script=$(mktemp)
    
    # Download new script
    if ! curl -fsSL "$GITHUB_RAW_URL" -o "$temp_script" 2>/dev/null; then
        echo -e "${RED}[✗]${NC} Failed to download update"
        rm -f "$temp_script"
        return 1
    fi
    
    # Verify the download looks like a valid script
    if ! head -1 "$temp_script" | grep -q "^#!/bin/bash"; then
        echo -e "${RED}[✗]${NC} Downloaded file doesn't appear to be a valid script"
        rm -f "$temp_script"
        return 1
    fi
    
    # Backup current script
    cp "$script_path" "${script_path}.backup"
    
    # Replace with new script
    mv "$temp_script" "$script_path"
    chmod +x "$script_path"
    
    echo -e "${GREEN}[✓]${NC} Script updated successfully!"
    echo -e "${BLUE}[INFO]${NC} Restarting with new version..."
    echo ""
    
    # Re-execute the script with skip-update flag to prevent infinite loop
    exec "$script_path" --skip-update-check "$@"
}

#===============================================================================
# SYSTEM CHECKS
#===============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        echo ""
        echo "Usage: sudo ./setup-monero.sh"
        exit 1
    fi
    print_success "Running as root"
}

check_debian() {
    if [[ ! -f /etc/debian_version ]]; then
        print_error "This script is designed for Debian-based systems"
        exit 1
    fi
    local version=$(cat /etc/debian_version)
    print_success "Detected Debian version: ${version}"
}

check_existing_installation() {
    local found=false
    
    if [[ -f "$INSTALL_DIR/monerod" ]]; then
        found=true
        local current_version=$("$INSTALL_DIR/monerod" --version 2>/dev/null | grep -oP 'v\d+\.\d+\.\d+\.\d+' | head -1 || echo "unknown")
        print_info "Existing Monero installation found: ${current_version}"
    fi
    
    if [[ -f "$CONFIG_DIR/monerod.conf" ]]; then
        found=true
        print_info "Existing configuration found"
    fi
    
    if systemctl is-active --quiet monerod 2>/dev/null; then
        print_info "Monero daemon is currently running"
    fi
    
    if [[ "$found" == true ]]; then
        return 0
    else
        return 1
    fi
}

check_disk_space() {
    local available_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    print_info "Available disk space: ${available_gb}GB"
    
    # Check storage type (SSD vs HDD)
    check_storage_type
    
    local required_gb=220
    local recommended_gb=300
    if [[ "$BLOCKCHAIN_MODE" == "pruned" ]]; then
        required_gb=80
        recommended_gb=120
    fi
    
    if [[ $available_gb -lt $required_gb ]]; then
        echo ""
        print_error "Insufficient disk space!"
        if [[ "$BLOCKCHAIN_MODE" == "full" ]]; then
            echo "         Full Monero blockchain requires ~180GB"
            echo "         Plus ~40GB overhead for database, logs, and growth"
            echo "         Minimum: ${required_gb}GB | Recommended: ${recommended_gb}GB"
            echo "         Consider using a pruned node if space is limited"
        else
            echo "         Pruned Monero blockchain requires ~65GB"
            echo "         Plus ~15GB overhead for database and growth"
            echo "         Minimum: ${required_gb}GB | Recommended: ${recommended_gb}GB"
        fi
        echo ""
        if ! prompt_yes_no "Continue anyway?" "N"; then
            print_error "Setup aborted due to insufficient disk space"
            exit 1
        fi
    elif [[ $available_gb -lt $recommended_gb ]]; then
        echo ""
        print_warning "Disk space is below recommended (${recommended_gb}GB)"
        echo "         Current: ${available_gb}GB"
        echo "         The blockchain grows ~20-30GB per year."
        echo ""
    fi
}

check_memory() {
    local total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_mem_gb=$((total_mem_kb / 1024 / 1024))
    local total_mem_mb=$((total_mem_kb / 1024))
    print_info "Available RAM: ${total_mem_gb}GB (${total_mem_mb}MB)"
    
    if [[ $total_mem_gb -lt 4 ]]; then
        print_warning "Less than 4GB RAM detected!"
        echo "         Monero initial sync requires significant memory."
        echo "         4GB minimum | 8GB recommended"
        echo ""
        echo "         To add swap space if sync is slow or crashes:"
        echo "           sudo fallocate -l 4G /swapfile"
        echo "           sudo chmod 600 /swapfile"
        echo "           sudo mkswap /swapfile"
        echo "           sudo swapon /swapfile"
        echo ""
    elif [[ $total_mem_gb -lt 8 ]]; then
        print_info "RAM: ${total_mem_gb}GB - sufficient (8GB recommended)"
    else
        print_success "RAM: ${total_mem_gb}GB (sufficient)"
    fi
}

check_cpu() {
    local cpu_cores=$(nproc)
    local cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
    
    print_info "CPU: ${cpu_model}"
    print_info "CPU cores: ${cpu_cores}"
    
    if [[ $cpu_cores -lt 2 ]]; then
        print_warning "Only ${cpu_cores} CPU core(s) detected!"
        echo "         Initial blockchain sync will be very slow."
        echo "         2 cores minimum | 4 cores recommended"
    elif [[ $cpu_cores -lt 4 ]]; then
        print_info "CPU cores: ${cpu_cores} - sufficient (4 recommended for pool)"
    else
        print_success "CPU cores: ${cpu_cores} (sufficient)"
    fi
}

check_storage_type() {
    local disk_type="unknown"
    local root_device=$(df / | awk 'NR==2 {print $1}' | sed 's/[0-9]*$//' | sed 's/p$//')
    local device_name=$(basename "$root_device")
    
    # Try to detect if storage is SSD or HDD
    if [[ -f "/sys/block/${device_name}/queue/rotational" ]]; then
        local rotational=$(cat "/sys/block/${device_name}/queue/rotational" 2>/dev/null || echo "1")
        if [[ "$rotational" == "0" ]]; then
            disk_type="SSD/NVMe"
            print_success "Storage type: ${disk_type} (recommended)"
        else
            disk_type="HDD (spinning disk)"
            print_warning "Storage type: ${disk_type}"
            echo ""
            echo -e "         ${YELLOW}⚠ WARNING: HDD detected!${NC}"
            echo "         Monero blockchain sync on HDD is EXTREMELY slow."
            echo "         Initial sync may take 1-3 WEEKS on spinning disk."
            echo "         SSD/NVMe is strongly recommended for acceptable performance."
            echo ""
            if [[ "$NODE_TYPE" == "pool" ]]; then
                echo -e "         ${RED}Mining pool nodes REQUIRE SSD for acceptable RPC latency.${NC}"
                echo ""
            fi
            if ! prompt_yes_no "Continue anyway (not recommended)?" "N"; then
                print_error "Setup aborted - SSD strongly recommended"
                exit 1
            fi
        fi
    else
        print_info "Storage type: Could not detect (assuming SSD)"
    fi
}

load_existing_config() {
    if [[ -f "$CONFIG_DIR/monerod.conf" ]]; then
        print_info "Loading existing configuration..."
        
        # Parse existing config
        if grep -q "prune-blockchain=1" "$CONFIG_DIR/monerod.conf" 2>/dev/null; then
            BLOCKCHAIN_MODE="pruned"
        else
            BLOCKCHAIN_MODE="full"
        fi
        
        if grep -q "zmq-pub=" "$CONFIG_DIR/monerod.conf" 2>/dev/null; then
            NODE_TYPE="pool"
        else
            NODE_TYPE="standard"
        fi
        
        # Get RPC bind IP
        local rpc_ip=$(grep "^rpc-bind-ip=" "$CONFIG_DIR/monerod.conf" 2>/dev/null | cut -d'=' -f2)
        if [[ -n "$rpc_ip" ]]; then
            RPC_BIND_IP="$rpc_ip"
        fi
        
        # Get data directory
        local data_dir=$(grep "^data-dir=" "$CONFIG_DIR/monerod.conf" 2>/dev/null | cut -d'=' -f2)
        if [[ -n "$data_dir" ]]; then
            DATA_DIR="$data_dir"
        fi
        
        print_success "Loaded existing configuration"
        echo "  Node Type: ${NODE_TYPE^}"
        echo "  Blockchain: ${BLOCKCHAIN_MODE^}"
        echo "  RPC Bind: ${RPC_BIND_IP}"
    fi
}

#===============================================================================
# SETUP MODE SELECTION
#===============================================================================

select_setup_mode() {
    print_section "SETUP MODE"
    
    if check_existing_installation; then
        echo "An existing Monero installation was detected."
        echo ""
        echo "What would you like to do?"
        echo ""
        echo -e "┌─────────────────────────────────────────────────────────────────────┐"
        echo -e "│  ${CYAN}[1]${NC} ${BOLD}UPDATE MONERO${NC}                                                  │"
        echo -e "│      Download latest binaries, keep config and blockchain           │"
        echo -e "├─────────────────────────────────────────────────────────────────────┤"
        echo -e "│  ${CYAN}[2]${NC} ${BOLD}RECONFIGURE${NC}                                                    │"
        echo -e "│      Change settings without reinstalling                           │"
        echo -e "├─────────────────────────────────────────────────────────────────────┤"
        echo -e "│  ${CYAN}[3]${NC} ${BOLD}FRESH INSTALL${NC}                                                  │"
        echo -e "│      Complete reinstall (keeps blockchain data)                     │"
        echo -e "├─────────────────────────────────────────────────────────────────────┤"
        echo -e "│  ${CYAN}[4]${NC} ${BOLD}MANAGE WALLET${NC}                                                  │"
        echo -e "│      Create or view pool wallet                                     │"
        echo -e "├─────────────────────────────────────────────────────────────────────┤"
        echo -e "│  ${CYAN}[5]${NC} ${BOLD}EXIT${NC}                                                           │"
        echo -e "│      Exit setup                                                     │"
        echo -e "└─────────────────────────────────────────────────────────────────────┘"
        echo ""
        echo -ne "${YELLOW}Enter your choice [1-5]:${NC} "
        read -r choice
        
        case "$choice" in
            1) SETUP_MODE="update" ;;
            2) SETUP_MODE="reconfigure" ;;
            3) SETUP_MODE="fresh" ;;
            4) SETUP_MODE="wallet" ;;
            5|*) 
                print_info "Exiting setup"
                exit 0
                ;;
        esac
    else
        echo "No existing installation detected."
        echo "This will perform a fresh installation."
        echo ""
        
        if ! prompt_yes_no "Continue with fresh installation?" "Y"; then
            print_info "Setup cancelled"
            exit 0
        fi
        
        SETUP_MODE="fresh"
    fi
    
    echo ""
    print_success "Selected mode: ${SETUP_MODE^}"
}

#===============================================================================
# INTERACTIVE CONFIGURATION
#===============================================================================

show_introduction() {
    print_section "WELCOME"
    
    echo "This wizard will guide you through setting up a Monero node."
    echo ""
    echo "You will be asked to make the following decisions:"
    echo ""
    echo -e "  ${BOLD}1. Node Type${NC}"
    echo "     • Standard Node - For personal use and wallet connections"
    echo "     • Mining Pool Node - Optimized backend for mining pool software"
    echo ""
    echo -e "  ${BOLD}2. Blockchain Mode${NC}"
    echo "     • Full Node (~180GB) - Complete blockchain, maximum security"
    echo "     • Pruned Node (~65GB) - Reduced storage, still validates all blocks"
    echo ""
    echo -e "  ${BOLD}3. Directory Paths${NC}"
    echo "     • Where to install binaries"
    echo "     • Where to store blockchain data"
    echo ""
    echo -e "  ${BOLD}4. Network Configuration${NC}"
    echo "     • RPC access settings"
    echo "     • Firewall rules"
    echo ""
    if [[ "$NODE_TYPE" == "pool" ]] || [[ "$SETUP_MODE" == "fresh" ]]; then
        echo -e "  ${BOLD}5. Pool Wallet (Mining Pool mode only)${NC}"
        echo "     • Create new wallet or use existing address"
        echo ""
    fi
    
    if ! prompt_yes_no "Ready to continue?" "Y"; then
        echo ""
        print_info "Setup cancelled. Run again when ready."
        exit 0
    fi
}

configure_node_type() {
    print_section "STEP 1: NODE TYPE"
    
    echo "What will this node be used for?"
    echo ""
    echo -e "┌─────────────────────────────────────────────────────────────────────┐"
    echo -e "│  ${CYAN}[1]${NC} ${BOLD}STANDARD NODE${NC}                                                  │"
    echo -e "│                                                                     │"
    echo -e "│      • For personal wallet use                                      │"
    echo -e "│      • Allows remote wallet connections (GUI/CLI wallets)           │"
    echo -e "│      • RPC runs in restricted mode for security                     │"
    echo -e "│      • Best for: Personal use, small services                       │"
    echo -e "└─────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo -e "┌─────────────────────────────────────────────────────────────────────┐"
    echo -e "│  ${CYAN}[2]${NC} ${BOLD}MINING POOL BACKEND${NC}                                            │"
    echo -e "│                                                                     │"
    echo -e "│      • Optimized for mining pool software (stratum servers)         │"
    echo -e "│      • Full RPC access on localhost only                            │"
    echo -e "│      • ZMQ enabled for instant block notifications                  │"
    echo -e "│      • Higher bandwidth and connection limits                       │"
    echo -e "│      • Best for: Mining pools, payment processors                   │"
    echo -e "└─────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo -ne "${YELLOW}Enter your choice [1 or 2]:${NC} "
    read -r choice
    
    if [[ "$choice" == "2" ]]; then
        NODE_TYPE="pool"
        RPC_BIND_IP="127.0.0.1"
        echo ""
        print_success "Selected: Mining Pool Backend"
        echo ""
        echo -e "${GREEN}Mining pool mode will:${NC}"
        echo "  • Bind RPC to localhost only (127.0.0.1)"
        echo "  • Enable unrestricted RPC access for pool software"
        echo "  • Enable ZMQ block notifications on port ${ZMQ_PORT}"
        echo "  • Increase bandwidth and peer limits"
    else
        NODE_TYPE="standard"
        echo ""
        print_success "Selected: Standard Node"
    fi
}

configure_blockchain_mode() {
    print_section "STEP 2: BLOCKCHAIN MODE"
    
    echo "How much blockchain data should be stored?"
    echo ""
    echo -e "┌─────────────────────────────────────────────────────────────────────┐"
    echo -e "│  ${CYAN}[1]${NC} ${BOLD}FULL NODE${NC}  (~180GB disk space)                                  │"
    echo -e "│                                                                     │"
    echo -e "│      • Stores complete blockchain history                           │"
    echo -e "│      • Maximum security and decentralization                        │"
    echo -e "│      • Can serve historical data to other nodes                     │"
    echo -e "│      • Best for: Block explorers, full archival needs               │"
    echo -e "└─────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo -e "┌─────────────────────────────────────────────────────────────────────┐"
    echo -e "│  ${CYAN}[2]${NC} ${BOLD}PRUNED NODE${NC}  (~65GB disk space)                                 │"
    echo -e "│                                                                     │"
    echo -e "│      • Stores only recent blockchain data                           │"
    echo -e "│      • Still validates ALL blocks (same security!)                  │"
    echo -e "│      • Uses ~65% less disk space                                    │"
    echo -e "│      • Best for: Most use cases including mining pools              │"
    echo -e "└─────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo -ne "${YELLOW}Enter your choice [1 or 2]:${NC} "
    read -r choice
    
    if [[ "$choice" == "2" ]]; then
        BLOCKCHAIN_MODE="pruned"
        echo ""
        print_success "Selected: Pruned Node (~65GB)"
    else
        BLOCKCHAIN_MODE="full"
        echo ""
        print_success "Selected: Full Node (~180GB)"
    fi
}

configure_directories() {
    print_section "STEP 3: INSTALLATION DIRECTORIES"
    
    echo "Where should Monero be installed?"
    echo ""
    echo "Default paths:"
    echo "  • Binaries:   ${INSTALL_DIR}"
    echo "  • Blockchain: ${DATA_DIR}"
    echo "  • Wallets:    ${WALLET_DIR}"
    echo "  • Config:     ${CONFIG_DIR}"
    echo "  • Logs:       ${LOG_DIR}"
    echo ""
    
    if prompt_yes_no "Use default paths?" "Y"; then
        print_success "Using default paths"
    else
        echo ""
        INSTALL_DIR=$(prompt_input "Binaries directory" "$INSTALL_DIR")
        DATA_DIR=$(prompt_input "Blockchain data directory" "$DATA_DIR")
        WALLET_DIR="${DATA_DIR}/wallets"
        print_success "Custom paths configured"
    fi
}

configure_network() {
    print_section "STEP 4: NETWORK CONFIGURATION"
    
    if [[ "$NODE_TYPE" == "pool" ]]; then
        echo -e "${GREEN}Mining pool mode: RPC is configured for localhost access only.${NC}"
        echo ""
        echo "Pool software should connect to:"
        echo "  • RPC:  http://127.0.0.1:${RPC_PORT}/json_rpc"
        echo ""
        echo "If your pool software runs on a different machine,"
        echo "use an SSH tunnel or reverse proxy."
        echo ""
        
        print_subsection "Block Notifications (Optional)"
        
        echo "Mining pools need to know when new blocks arrive to update miner work."
        echo "Choose a method based on your pool software requirements:"
        echo ""
        echo -e "┌─────────────────────────────────────────────────────────────────────┐"
        echo -e "│  ${CYAN}[1]${NC} ${BOLD}RPC POLLING ONLY${NC} (RECOMMENDED)                                 │"
        echo -e "│      Most compatible, works with all pool software                  │"
        echo -e "│      Pool polls get_last_block_header every 1-2 seconds             │"
        echo -e "├─────────────────────────────────────────────────────────────────────┤"
        echo -e "│  ${CYAN}[2]${NC} ${BOLD}ENABLE ZMQ${NC}                                                     │"
        echo -e "│      Instant push notifications (may have issues on some systems)   │"
        echo -e "│      ZMQ pub: tcp://127.0.0.1:${ZMQ_PORT}                                  │"
        echo -e "├─────────────────────────────────────────────────────────────────────┤"
        echo -e "│  ${CYAN}[3]${NC} ${BOLD}ENABLE BLOCKNOTIFY${NC}                                             │"
        echo -e "│      Run a custom script when new blocks arrive                     │"
        echo -e "│      Useful for custom integrations                                 │"
        echo -e "├─────────────────────────────────────────────────────────────────────┤"
        echo -e "│  ${CYAN}[4]${NC} ${BOLD}ENABLE BOTH${NC}                                                    │"
        echo -e "│      Enable both ZMQ and blocknotify                                │"
        echo -e "└─────────────────────────────────────────────────────────────────────┘"
        echo ""
        echo -ne "${YELLOW}Enter your choice [1-4]:${NC} "
        read -r notif_choice
        
        case "$notif_choice" in
            2)
                ENABLE_ZMQ="Y"
                ENABLE_BLOCKNOTIFY="N"
                echo ""
                print_success "ZMQ notifications enabled"
                echo "  ZMQ endpoint: tcp://127.0.0.1:${ZMQ_PORT}"
                echo ""
                print_warning "If you experience issues, reconfigure with RPC polling."
                ;;
            3)
                ENABLE_ZMQ="N"
                ENABLE_BLOCKNOTIFY="Y"
                echo ""
                echo "Enter the command to run when a new block is found."
                echo "The block hash will be appended as an argument."
                echo ""
                echo "Examples:"
                echo "  curl -s http://localhost:8000/newblock/"
                echo "  /opt/pool/notify.sh"
                echo ""
                echo -ne "${YELLOW}blocknotify command:${NC} "
                read -r BLOCKNOTIFY_CMD
                if [[ -z "$BLOCKNOTIFY_CMD" ]]; then
                    BLOCKNOTIFY_CMD="echo %s >> /var/log/monero/newblocks.log"
                fi
                print_success "blocknotify configured"
                ;;
            4)
                ENABLE_ZMQ="Y"
                ENABLE_BLOCKNOTIFY="Y"
                echo ""
                print_success "Both ZMQ and blocknotify enabled"
                echo "  ZMQ endpoint: tcp://127.0.0.1:${ZMQ_PORT}"
                echo ""
                echo -ne "${YELLOW}blocknotify command [default: log to file]:${NC} "
                read -r BLOCKNOTIFY_CMD
                if [[ -z "$BLOCKNOTIFY_CMD" ]]; then
                    BLOCKNOTIFY_CMD="echo %s >> /var/log/monero/newblocks.log"
                fi
                ;;
            *)
                ENABLE_ZMQ="N"
                ENABLE_BLOCKNOTIFY="N"
                echo ""
                print_success "Using RPC polling only (most compatible)"
                echo "  Pool software will poll get_last_block_header for new work."
                ;;
        esac
        echo ""
    else
        print_subsection "RPC Access"
        
        echo "RPC (Remote Procedure Call) allows wallets to connect to your node."
        echo ""
        echo -e "┌─────────────────────────────────────────────────────────────────────┐"
        echo -e "│  ${CYAN}[1]${NC} ${BOLD}ALL INTERFACES${NC}  (0.0.0.0)                                      │"
        echo -e "│                                                                     │"
        echo -e "│      • Accept connections from any IP address                       │"
        echo -e "│      • Required for remote wallet connections                       │"
        echo -e "│      • Runs in restricted mode for security                         │"
        echo -e "└─────────────────────────────────────────────────────────────────────┘"
        echo ""
        echo -e "┌─────────────────────────────────────────────────────────────────────┐"
        echo -e "│  ${CYAN}[2]${NC} ${BOLD}LOCALHOST ONLY${NC}  (127.0.0.1)                                    │"
        echo -e "│                                                                     │"
        echo -e "│      • Only accept local connections                                │"
        echo -e "│      • More secure, no remote access                                │"
        echo -e "└─────────────────────────────────────────────────────────────────────┘"
        echo ""
        echo -ne "${YELLOW}Enter your choice [1 or 2]:${NC} "
        read -r choice
        
        if [[ "$choice" == "2" ]]; then
            RPC_BIND_IP="127.0.0.1"
        else
            RPC_BIND_IP="0.0.0.0"
        fi
        
        echo ""
        print_success "RPC will bind to: ${RPC_BIND_IP}"
        
        # Optional RPC authentication
        echo ""
        print_subsection "RPC Authentication (Optional)"
        
        echo "You can require username/password for RPC connections."
        echo "This adds an extra layer of security for remote access."
        echo ""
        
        if prompt_yes_no "Enable RPC authentication?" "N"; then
            ENABLE_RPC_LOGIN="Y"
            echo ""
            RPC_USERNAME=$(prompt_input "RPC username" "monero")
            
            # Generate random password if not provided
            echo -ne "${YELLOW}RPC password [auto-generate]:${NC} "
            read -r RPC_PASSWORD
            if [[ -z "$RPC_PASSWORD" ]]; then
                RPC_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)
                echo -e "${GREEN}Generated password: ${RPC_PASSWORD}${NC}"
            fi
            print_success "RPC authentication enabled"
        fi
    fi
    
    print_subsection "Firewall Configuration"
    
    echo "UFW (Uncomplicated Firewall) can be configured automatically."
    echo ""
    echo "Ports that will be opened:"
    echo "  • 22/tcp    - SSH (always enabled for safety)"
    echo "  • ${P2P_PORT}/tcp - P2P network connections"
    if [[ "$NODE_TYPE" != "pool" ]] && [[ "$RPC_BIND_IP" == "0.0.0.0" ]]; then
        echo "  • ${RPC_PORT}/tcp - RPC wallet connections"
    fi
    echo ""
    
    if prompt_yes_no "Configure UFW firewall?" "Y"; then
        CONFIGURE_FIREWALL="Y"
        print_success "Firewall will be configured"
    else
        CONFIGURE_FIREWALL="N"
        print_warning "Skipping firewall configuration"
    fi
}

configure_pool_wallet() {
    if [[ "$NODE_TYPE" != "pool" ]]; then
        return
    fi
    
    print_section "STEP 5: POOL WALLET CONFIGURATION"
    
    echo "Mining pools require a wallet address for receiving block rewards."
    echo "This address is used by pool software when calling getblocktemplate."
    echo ""
    echo -e "┌─────────────────────────────────────────────────────────────────────┐"
    echo -e "│  ${CYAN}[1]${NC} ${BOLD}CREATE NEW WALLET${NC}                                               │"
    echo -e "│                                                                     │"
    echo -e "│      • Generate a new wallet on this server                         │"
    echo -e "│      • Wallet files stored securely in ${WALLET_DIR}        │"
    echo -e "│      • You'll receive the seed phrase (SAVE IT!)                    │"
    echo -e "└─────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo -e "┌─────────────────────────────────────────────────────────────────────┐"
    echo -e "│  ${CYAN}[2]${NC} ${BOLD}USE EXISTING ADDRESS${NC}                                            │"
    echo -e "│                                                                     │"
    echo -e "│      • Enter a wallet address you already own                       │"
    echo -e "│      • No wallet files stored on server                             │"
    echo -e "│      • You manage the wallet elsewhere                              │"
    echo -e "└─────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo -e "┌─────────────────────────────────────────────────────────────────────┐"
    echo -e "│  ${CYAN}[3]${NC} ${BOLD}SKIP FOR NOW${NC}                                                    │"
    echo -e "│                                                                     │"
    echo -e "│      • Configure wallet later                                       │"
    echo -e "│      • You'll need to set it up before starting the pool            │"
    echo -e "└─────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo -ne "${YELLOW}Enter your choice [1, 2, or 3]:${NC} "
    read -r choice
    
    case "$choice" in
        1)
            CREATE_POOL_WALLET="Y"
            echo ""
            print_success "Will create new wallet during setup"
            ;;
        2)
            CREATE_POOL_WALLET="N"
            echo ""
            echo "Enter your Monero wallet address."
            echo "It should start with '4' and be 95 characters long."
            echo ""
            while true; do
                POOL_WALLET_ADDRESS=$(prompt_input_required "Wallet address")
                if [[ ${#POOL_WALLET_ADDRESS} -eq 95 ]] && [[ "$POOL_WALLET_ADDRESS" == 4* ]]; then
                    break
                else
                    print_warning "Invalid address format. Please enter a valid Monero address."
                fi
            done
            print_success "Wallet address saved"
            ;;
        *)
            CREATE_POOL_WALLET="N"
            echo ""
            print_warning "Skipping wallet configuration"
            echo "Remember to configure your pool wallet before starting the pool software."
            ;;
    esac
}

show_configuration_summary() {
    print_section "CONFIGURATION SUMMARY"
    
    echo -e "Please review your configuration:"
    echo ""
    echo -e "  ${BOLD}Setup Mode:${NC}         ${GREEN}${SETUP_MODE^}${NC}"
    echo -e "  ${BOLD}Node Type:${NC}          ${GREEN}${NODE_TYPE^} Node${NC}"
    echo -e "  ${BOLD}Blockchain Mode:${NC}    ${GREEN}${BLOCKCHAIN_MODE^}${NC}"
    echo ""
    echo -e "  ${BOLD}Directories:${NC}"
    echo -e "    Binaries:         ${GREEN}${INSTALL_DIR}${NC}"
    echo -e "    Blockchain:       ${GREEN}${DATA_DIR}${NC}"
    echo -e "    Wallets:          ${GREEN}${WALLET_DIR}${NC}"
    echo -e "    Config:           ${GREEN}${CONFIG_DIR}${NC}"
    echo -e "    Logs:             ${GREEN}${LOG_DIR}${NC}"
    echo ""
    echo -e "  ${BOLD}Network:${NC}"
    echo -e "    P2P Port:         ${GREEN}${P2P_PORT}${NC}"
    echo -e "    RPC Bind:         ${GREEN}${RPC_BIND_IP}:${RPC_PORT}${NC}"
    if [[ "$NODE_TYPE" == "pool" ]]; then
        if [[ "$ENABLE_ZMQ" == "Y" ]]; then
            echo -e "    ZMQ Port:         ${GREEN}${ZMQ_PORT} (enabled)${NC}"
        else
            echo -e "    ZMQ:              ${YELLOW}Disabled (RPC polling)${NC}"
        fi
        if [[ "$ENABLE_BLOCKNOTIFY" == "Y" ]]; then
            echo -e "    blocknotify:      ${GREEN}Enabled${NC}"
        fi
    fi
    if [[ "$ENABLE_RPC_LOGIN" == "Y" ]]; then
        echo -e "    RPC Auth:         ${GREEN}Enabled (${RPC_USERNAME})${NC}"
    fi
    echo -e "    Firewall:         ${GREEN}${CONFIGURE_FIREWALL}${NC}"
    
    if [[ "$NODE_TYPE" == "pool" ]]; then
        echo ""
        echo -e "  ${BOLD}Pool Wallet:${NC}"
        if [[ "$CREATE_POOL_WALLET" == "Y" ]]; then
            echo -e "    Action:           ${GREEN}Create new wallet${NC}"
        elif [[ -n "$POOL_WALLET_ADDRESS" ]]; then
            echo -e "    Address:          ${GREEN}${POOL_WALLET_ADDRESS:0:20}...${NC}"
        else
            echo -e "    Action:           ${YELLOW}Configure later${NC}"
        fi
    fi
    
    echo ""
    echo -e "  ${BOLD}Monero Version:${NC}     ${GREEN}${MONERO_VERSION}${NC}"
    echo ""
    
    if [[ "$BLOCKCHAIN_MODE" == "full" ]]; then
        echo -e "  ${YELLOW}Disk space required: ~180GB${NC}"
    else
        echo -e "  ${YELLOW}Disk space required: ~65GB${NC}"
    fi
    echo ""
    
    if ! prompt_yes_no "Proceed with setup?" "Y"; then
        print_error "Setup aborted by user"
        exit 0
    fi
}

#===============================================================================
# INSTALLATION FUNCTIONS
#===============================================================================

install_dependencies() {
    print_step "1/9" "Installing system dependencies..."
    
    # Update package lists
    apt-get update -qq
    
    # Upgrade existing packages to latest versions
    print_info "Upgrading system packages..."
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq > /dev/null 2>&1 || true
    
    # Install required dependencies
    apt-get install -y -qq \
        wget \
        curl \
        bzip2 \
        tar \
        gnupg \
        ca-certificates \
        ufw \
        jq \
        htop \
        iotop \
        openssl \
        libzmq5 \
        > /dev/null
    
    print_success "Dependencies installed"
}

create_monero_user() {
    print_step "2/9" "Creating monero system user..."
    
    if id "$MONERO_USER" &>/dev/null; then
        print_info "User '$MONERO_USER' already exists"
    else
        useradd --system --shell /usr/sbin/nologin --home-dir "$DATA_DIR" "$MONERO_USER"
        print_success "User '$MONERO_USER' created"
    fi
}

create_directories() {
    print_step "3/9" "Creating directories..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$DATA_DIR"
    mkdir -p "$WALLET_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"
    
    chown -R "$MONERO_USER:$MONERO_USER" "$DATA_DIR"
    chown -R "$MONERO_USER:$MONERO_USER" "$LOG_DIR"
    chmod 700 "$WALLET_DIR"
    
    print_success "Directories created"
}

download_and_verify_monero() {
    print_step "4/9" "Downloading and verifying Monero..."
    
    local tmp_dir=$(mktemp -d)
    cd "$tmp_dir"
    
    print_info "Downloading Monero CLI v${MONERO_VERSION}..."
    wget -q --show-progress "$MONERO_URL" -O monero-linux-x64.tar.bz2
    
    print_info "Downloading hash file for verification..."
    wget -q "$MONERO_HASHES_URL" -O hashes.txt
    
    print_info "Importing GPG key..."
    gpg --keyserver "$GPG_KEY_SERVER" --recv-keys "$GPG_KEY_ID" 2>/dev/null || {
        print_warning "Could not fetch GPG key from keyserver, trying alternative..."
        wget -q "https://raw.githubusercontent.com/monero-project/monero/master/utils/gpg_keys/binaryfate.asc" -O binaryfate.asc
        gpg --import binaryfate.asc 2>/dev/null
    }
    
    print_info "Verifying download..."
    local expected_hash=$(grep "monero-linux-x64" hashes.txt | grep -oE "^[a-f0-9]{64}" | head -1)
    local actual_hash=$(sha256sum monero-linux-x64.tar.bz2 | cut -d' ' -f1)
    
    if [[ -n "$expected_hash" ]] && [[ "$expected_hash" != "$actual_hash" ]]; then
        print_error "Hash verification failed!"
        rm -rf "$tmp_dir"
        exit 1
    fi
    
    print_success "Download verified"
    
    print_info "Extracting binaries..."
    tar -xjf monero-linux-x64.tar.bz2
    
    local monero_dir=$(find . -maxdepth 1 -type d -name "monero-x86_64-linux-gnu-*" | head -1)
    if [[ -z "$monero_dir" ]]; then
        monero_dir=$(find . -maxdepth 1 -type d -name "monero-*" | head -1)
    fi
    
    if [[ -z "$monero_dir" ]]; then
        print_error "Could not find extracted Monero directory"
        rm -rf "$tmp_dir"
        exit 1
    fi
    
    cp -r "$monero_dir"/* "$INSTALL_DIR/"
    
    cd /
    rm -rf "$tmp_dir"
    
    print_success "Monero binaries installed"
}

create_symlinks() {
    print_step "5/9" "Creating symlinks..."
    
    local binaries=("monerod" "monero-wallet-cli" "monero-wallet-rpc" "monero-gen-trusted-multisig" "monero-blockchain-import" "monero-blockchain-export")
    
    for binary in "${binaries[@]}"; do
        if [[ -f "$INSTALL_DIR/$binary" ]]; then
            ln -sf "$INSTALL_DIR/$binary" "/usr/local/bin/$binary"
        fi
    done
    
    print_success "Symlinks created in /usr/local/bin/"
}

create_config_file() {
    print_step "6/9" "Creating configuration file..."
    
    # Build configuration based on selections
    cat > "$CONFIG_DIR/monerod.conf" << EOF
#===============================================================================
# MONERO NODE CONFIGURATION
# Generated by setup-monero.sh
# 
# Node Type: ${NODE_TYPE^}
# Blockchain: ${BLOCKCHAIN_MODE^}
# Generated: $(date)
#===============================================================================

#-------------------------------------------------------------------------------
# DATA DIRECTORY
#-------------------------------------------------------------------------------
data-dir=$DATA_DIR

#-------------------------------------------------------------------------------
# LOG SETTINGS
#-------------------------------------------------------------------------------
log-file=$LOG_DIR/monerod.log
log-level=0
max-log-file-size=10485760
max-log-files=5

#-------------------------------------------------------------------------------
# NETWORK SETTINGS
#-------------------------------------------------------------------------------
# P2P (peer-to-peer) connections
p2p-bind-ip=0.0.0.0
p2p-bind-port=$P2P_PORT
p2p-use-ipv6=0

#-------------------------------------------------------------------------------
# RPC SETTINGS
#-------------------------------------------------------------------------------
rpc-bind-ip=$RPC_BIND_IP
rpc-bind-port=$RPC_PORT
EOF

    # Add RPC authentication if enabled
    if [[ "$ENABLE_RPC_LOGIN" == "Y" ]]; then
        cat >> "$CONFIG_DIR/monerod.conf" << EOF
rpc-login=${RPC_USERNAME}:${RPC_PASSWORD}
EOF
    fi

    # Mode-specific settings
    if [[ "$NODE_TYPE" == "pool" ]]; then
        cat >> "$CONFIG_DIR/monerod.conf" << EOF

# MINING POOL MODE - Unrestricted RPC for pool software
# RPC binds to localhost only for security
no-igd=1
EOF

        # Only add ZMQ if enabled
        if [[ "$ENABLE_ZMQ" == "Y" ]]; then
            cat >> "$CONFIG_DIR/monerod.conf" << EOF

#-------------------------------------------------------------------------------
# ZMQ BLOCK NOTIFICATIONS (ENABLED)
# Pool software can subscribe for instant new block notifications
#-------------------------------------------------------------------------------
zmq-pub=tcp://127.0.0.1:${ZMQ_PORT}
EOF
        else
            cat >> "$CONFIG_DIR/monerod.conf" << EOF

#-------------------------------------------------------------------------------
# ZMQ BLOCK NOTIFICATIONS (DISABLED)
# Uncomment to enable - pool software will use RPC polling instead
#-------------------------------------------------------------------------------
# zmq-pub=tcp://127.0.0.1:${ZMQ_PORT}
EOF
        fi

        # Add blocknotify if enabled
        if [[ "$ENABLE_BLOCKNOTIFY" == "Y" ]] && [[ -n "$BLOCKNOTIFY_CMD" ]]; then
            cat >> "$CONFIG_DIR/monerod.conf" << EOF

#-------------------------------------------------------------------------------
# BLOCK NOTIFY SCRIPT
# Runs this command when a new block is found (%s = block hash)
#-------------------------------------------------------------------------------
block-notify=${BLOCKNOTIFY_CMD}
EOF
        fi

        cat >> "$CONFIG_DIR/monerod.conf" << EOF

#-------------------------------------------------------------------------------
# PERFORMANCE TUNING (optimized for pool)
#-------------------------------------------------------------------------------
block-sync-size=20
prep-blocks-threads=4

# Higher bandwidth limits for pool reliability
limit-rate-up=4096
limit-rate-down=16384

# More peer connections for faster block propagation
out-peers=96
in-peers=128
EOF
    else
        cat >> "$CONFIG_DIR/monerod.conf" << EOF

# STANDARD MODE - Restricted RPC for wallet connections
EOF
        if [[ "$RPC_BIND_IP" == "0.0.0.0" ]]; then
            cat >> "$CONFIG_DIR/monerod.conf" << EOF
confirm-external-bind=1
restricted-rpc=1
EOF
        fi
        cat >> "$CONFIG_DIR/monerod.conf" << EOF
no-igd=1

#-------------------------------------------------------------------------------
# PERFORMANCE TUNING
#-------------------------------------------------------------------------------
block-sync-size=10
prep-blocks-threads=4

# Bandwidth limits (kB/s, 0 = unlimited)
limit-rate-up=2048
limit-rate-down=8192

# Connection limits
out-peers=64
in-peers=128
EOF
    fi

    # Blockchain mode
    cat >> "$CONFIG_DIR/monerod.conf" << EOF

#-------------------------------------------------------------------------------
# BLOCKCHAIN MODE
#-------------------------------------------------------------------------------
EOF
    if [[ "$BLOCKCHAIN_MODE" == "pruned" ]]; then
        cat >> "$CONFIG_DIR/monerod.conf" << EOF
# Pruned node - stores only recent blockchain data (~65GB)
prune-blockchain=1
EOF
    else
        cat >> "$CONFIG_DIR/monerod.conf" << EOF
# Full node - stores complete blockchain (~180GB)
prune-blockchain=0
EOF
    fi

    # Common settings
    cat >> "$CONFIG_DIR/monerod.conf" << EOF

#-------------------------------------------------------------------------------
# SECURITY & RELIABILITY
#-------------------------------------------------------------------------------
db-sync-mode=safe
enforce-dns-checkpointing=1
enable-dns-blocklist=1
EOF

    chown "$MONERO_USER:$MONERO_USER" "$CONFIG_DIR/monerod.conf"
    chmod 640 "$CONFIG_DIR/monerod.conf"
    
    print_success "Configuration file created"
}

create_pool_wallet() {
    if [[ "$NODE_TYPE" != "pool" ]]; then
        return
    fi
    
    print_step "7/9" "Setting up pool wallet..."
    
    if [[ "$CREATE_POOL_WALLET" == "Y" ]]; then
        print_info "Creating new wallet..."
        
        local wallet_name="pool-wallet"
        local wallet_path="${WALLET_DIR}/${wallet_name}"
        local wallet_password=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
        local wallet_output=""
        local wallet_address=""
        local wallet_seed=""
        
        # Create wallet using monero-wallet-cli and capture output
        # The wallet outputs address and seed during creation
        wallet_output=$(echo -e "0\nexit\n" | "$INSTALL_DIR/monero-wallet-cli" \
            --generate-new-wallet "$wallet_path" \
            --password "$wallet_password" \
            --mnemonic-language English 2>&1) || true
        
        if [[ -f "${wallet_path}.keys" ]]; then
            # Extract wallet address from output (starts with 4, 95 chars)
            wallet_address=$(echo "$wallet_output" | grep -oP '4[0-9A-Za-z]{94}' | head -1)
            
            # Extract seed phrase (25 words after "following 25 words")
            wallet_seed=$(echo "$wallet_output" | grep -A 4 "following 25 words" | tail -n 3 | tr '\n' ' ' | sed 's/  */ /g' | xargs)
            
            # If we couldn't extract from output, try alternative method
            if [[ -z "$wallet_address" ]]; then
                wallet_address=$(echo "$wallet_output" | grep "Generated new wallet:" | grep -oP '4[0-9A-Za-z]{94}')
            fi
            
            POOL_WALLET_ADDRESS="$wallet_address"
            
            # Save wallet info
            cat > "$CONFIG_DIR/pool-wallet.conf" << EOF
# Pool Wallet Configuration
# Generated: $(date)
# 
# IMPORTANT: Keep this file secure and backed up!

WALLET_PATH=${wallet_path}
WALLET_ADDRESS=${wallet_address}
WALLET_PASSWORD=${wallet_password}

# SEED PHRASE - WRITE THIS DOWN AND STORE SECURELY!
# This is the only way to recover your wallet if files are lost.
#
# ${wallet_seed}
#
EOF
            
            chmod 600 "$CONFIG_DIR/pool-wallet.conf"
            chown "$MONERO_USER:$MONERO_USER" "$CONFIG_DIR/pool-wallet.conf"
            chown -R "$MONERO_USER:$MONERO_USER" "$WALLET_DIR"
            
            print_success "Pool wallet created"
            echo ""
            echo -e "${RED}╔══════════════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${RED}║${NC}               ${BOLD}CRITICAL: SAVE YOUR SEED PHRASE!${NC}                       ${RED}║${NC}"
            echo -e "${RED}╠══════════════════════════════════════════════════════════════════════╣${NC}"
            echo -e "${RED}║${NC}                                                                      ${RED}║${NC}"
            echo -e "${RED}║${NC}  Your seed phrase is the ONLY way to recover your wallet.            ${RED}║${NC}"
            echo -e "${RED}║${NC}  If you lose it, your funds are GONE FOREVER.                        ${RED}║${NC}"
            echo -e "${RED}║${NC}                                                                      ${RED}║${NC}"
            echo -e "${RED}╚══════════════════════════════════════════════════════════════════════╝${NC}"
            echo ""
            echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${CYAN}                         WALLET INFORMATION                            ${NC}"
            echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            echo -e "${YELLOW}Wallet Address:${NC}"
            echo "$wallet_address"
            echo ""
            echo -e "${YELLOW}Wallet Password (for local wallet file):${NC}"
            echo "$wallet_password"
            echo ""
            echo -e "${YELLOW}Seed Phrase (25 words):${NC}"
            echo "$wallet_seed"
            echo ""
            echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${CYAN}                         SECURITY WARNINGS                             ${NC}"
            echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            echo -e "  ${RED}⚠${NC}  NEVER share your seed phrase with anyone"
            echo -e "  ${RED}⚠${NC}  NEVER enter your seed phrase on any website"
            echo -e "  ${RED}⚠${NC}  NEVER store seed phrase in digital form (email, cloud, etc.)"
            echo ""
            echo -e "  ${GREEN}✓${NC}  Write the seed phrase on paper and store securely"
            echo -e "  ${GREEN}✓${NC}  Consider using a fireproof safe or safety deposit box"
            echo -e "  ${GREEN}✓${NC}  Make multiple copies stored in different locations"
            echo ""
            echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${CYAN}                         WALLET RECOVERY                               ${NC}"
            echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            echo "  To recover this wallet, use the official Monero GUI/CLI wallet:"
            echo "    monero-wallet-cli --restore-deterministic-wallet"
            echo "  Then enter your 25-word seed phrase when prompted."
            echo ""
            echo -e "${YELLOW}  Wallet info also saved in: ${CONFIG_DIR}/pool-wallet.conf${NC}"
            echo -e "${YELLOW}  (readable only by root and monero user)${NC}"
            echo ""
            echo -e "${GREEN}Press Enter when you have safely recorded your seed phrase...${NC}"
            read -r
        else
            print_warning "Could not create wallet. You can create it manually later."
        fi
        
    elif [[ -n "$POOL_WALLET_ADDRESS" ]]; then
        # Save existing wallet address
        cat > "$CONFIG_DIR/pool-wallet.conf" << EOF
# Pool Wallet Configuration
# Generated: $(date)

WALLET_ADDRESS=${POOL_WALLET_ADDRESS}

# Note: This is an external wallet address.
# The wallet is managed elsewhere.
EOF
        
        chmod 600 "$CONFIG_DIR/pool-wallet.conf"
        chown "$MONERO_USER:$MONERO_USER" "$CONFIG_DIR/pool-wallet.conf"
        
        print_success "Pool wallet address saved"
    else
        print_info "Skipping wallet configuration"
    fi
}

create_systemd_service() {
    print_step "8/9" "Creating systemd service..."
    
    cat > /etc/systemd/system/monerod.service << EOF
[Unit]
Description=Monero Full Node Daemon
Documentation=https://www.getmonero.org/resources/developer-guides/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$MONERO_USER
Group=$MONERO_USER

ExecStart=$INSTALL_DIR/monerod --config-file=$CONFIG_DIR/monerod.conf --non-interactive
ExecStop=/bin/kill -SIGTERM \$MAINPID

Restart=on-failure
RestartSec=30

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$DATA_DIR $LOG_DIR

# Resource limits
LimitNOFILE=65535
Nice=10
IOSchedulingClass=2
IOSchedulingPriority=7

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    
    print_success "Systemd service created"
}

configure_firewall() {
    print_step "9/9" "Configuring firewall..."
    
    if [[ "$CONFIGURE_FIREWALL" != "Y" ]]; then
        print_info "Skipping firewall configuration"
        return
    fi
    
    # Enable UFW if not already enabled
    if ! ufw status | grep -q "Status: active"; then
        ufw --force enable
    fi
    
    # Always allow SSH
    ufw allow ssh
    
    # Allow P2P port
    ufw allow "$P2P_PORT/tcp" comment 'Monero P2P'
    
    # RPC port depends on configuration
    if [[ "$NODE_TYPE" != "pool" ]] && [[ "$RPC_BIND_IP" == "0.0.0.0" ]]; then
        ufw allow "$RPC_PORT/tcp" comment 'Monero RPC'
        print_info "RPC port ${RPC_PORT} opened"
    else
        print_info "RPC port NOT exposed (localhost only)"
    fi
    
    ufw reload > /dev/null 2>&1
    
    print_success "Firewall configured"
}

start_service() {
    print_info "Enabling and starting monerod service..."
    
    systemctl enable monerod > /dev/null 2>&1
    systemctl start monerod
    
    sleep 3
    
    if systemctl is-active --quiet monerod; then
        print_success "Monero daemon is running!"
    else
        print_warning "Monero daemon may have failed to start"
        print_info "Check logs: sudo journalctl -u monerod -n 50"
    fi
}

stop_service() {
    if systemctl is-active --quiet monerod 2>/dev/null; then
        print_info "Stopping monerod service..."
        systemctl stop monerod
        sleep 2
        print_success "Service stopped"
    fi
}

#===============================================================================
# UPDATE MODE
#===============================================================================

perform_update() {
    print_section "UPDATING MONERO"
    
    echo "This will:"
    echo "  • Stop the monerod service"
    echo "  • Download latest Monero binaries"
    echo "  • Verify and install new binaries"
    echo "  • Restart the service"
    echo ""
    echo "Your configuration and blockchain data will be preserved."
    echo ""
    
    if ! prompt_yes_no "Continue with update?" "Y"; then
        print_info "Update cancelled"
        exit 0
    fi
    
    stop_service
    
    print_step "1/3" "Downloading latest Monero..."
    download_and_verify_monero
    
    print_step "2/3" "Updating symlinks..."
    create_symlinks
    
    print_step "3/3" "Starting service..."
    start_service
    
    print_section "UPDATE COMPLETE"
    
    local new_version=$("$INSTALL_DIR/monerod" --version 2>/dev/null | grep -oP 'v\d+\.\d+\.\d+\.\d+' | head -1 || echo "unknown")
    echo -e "${GREEN}Monero updated to: ${new_version}${NC}"
    echo ""
    echo "Check status: sudo systemctl status monerod"
    echo "View logs:    sudo journalctl -u monerod -f"
}

#===============================================================================
# RECONFIGURE MODE
#===============================================================================

perform_reconfigure() {
    print_section "RECONFIGURE MONERO NODE"
    
    load_existing_config
    
    echo "Current configuration:"
    echo "  • Node Type: ${NODE_TYPE^}"
    echo "  • Blockchain: ${BLOCKCHAIN_MODE^}"
    echo "  • RPC Bind: ${RPC_BIND_IP}"
    echo ""
    
    if ! prompt_yes_no "Change configuration?" "Y"; then
        print_info "Reconfiguration cancelled"
        exit 0
    fi
    
    # Run configuration steps
    configure_node_type
    configure_blockchain_mode
    configure_network
    
    if [[ "$NODE_TYPE" == "pool" ]]; then
        configure_pool_wallet
    fi
    
    show_configuration_summary
    
    stop_service
    
    print_info "Updating configuration..."
    create_config_file
    
    if [[ "$NODE_TYPE" == "pool" ]]; then
        create_pool_wallet
    fi
    
    configure_firewall
    start_service
    
    print_section "RECONFIGURATION COMPLETE"
    echo "Your node has been reconfigured and restarted."
}

#===============================================================================
# WALLET MANAGEMENT MODE
#===============================================================================

manage_wallet() {
    print_section "WALLET MANAGEMENT"
    
    if [[ -f "$CONFIG_DIR/pool-wallet.conf" ]]; then
        echo "Current pool wallet configuration:"
        echo ""
        source "$CONFIG_DIR/pool-wallet.conf" 2>/dev/null
        if [[ -n "$WALLET_ADDRESS" ]]; then
            echo "  Address: ${WALLET_ADDRESS:0:20}...${WALLET_ADDRESS: -10}"
        fi
        if [[ -n "$WALLET_PATH" ]]; then
            echo "  Path: $WALLET_PATH"
        fi
        echo ""
    else
        echo "No pool wallet is currently configured."
        echo ""
    fi
    
    echo "What would you like to do?"
    echo ""
    echo -e "┌─────────────────────────────────────────────────────────────────────┐"
    echo -e "│  ${CYAN}[1]${NC} ${BOLD}CREATE NEW WALLET${NC}                                               │"
    echo -e "│      Generate a new wallet on this server                           │"
    echo -e "├─────────────────────────────────────────────────────────────────────┤"
    echo -e "│  ${CYAN}[2]${NC} ${BOLD}SET EXISTING WALLET ADDRESS${NC}                                     │"
    echo -e "│      Enter a wallet address you already own                         │"
    echo -e "├─────────────────────────────────────────────────────────────────────┤"
    echo -e "│  ${CYAN}[3]${NC} ${BOLD}VIEW FULL WALLET DETAILS${NC}                                        │"
    echo -e "│      Show complete wallet configuration                             │"
    echo -e "├─────────────────────────────────────────────────────────────────────┤"
    echo -e "│  ${CYAN}[4]${NC} ${BOLD}BACK TO MAIN MENU${NC}                                               │"
    echo -e "│      Return to setup mode selection                                 │"
    echo -e "└─────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo -ne "${YELLOW}Enter your choice [1-4]:${NC} "
    read -r choice
    
    case "$choice" in
        1)
            NODE_TYPE="pool"
            CREATE_POOL_WALLET="Y"
            create_directories
            create_pool_wallet
            ;;
        2)
            NODE_TYPE="pool"
            CREATE_POOL_WALLET="N"
            echo ""
            while true; do
                POOL_WALLET_ADDRESS=$(prompt_input_required "Wallet address")
                if [[ ${#POOL_WALLET_ADDRESS} -eq 95 ]] && [[ "$POOL_WALLET_ADDRESS" == 4* ]]; then
                    break
                else
                    print_warning "Invalid address format. Please enter a valid Monero address."
                fi
            done
            
            cat > "$CONFIG_DIR/pool-wallet.conf" << EOF
# Pool Wallet Configuration
# Generated: $(date)

WALLET_ADDRESS=${POOL_WALLET_ADDRESS}
EOF
            chmod 600 "$CONFIG_DIR/pool-wallet.conf"
            print_success "Wallet address saved"
            ;;
        3)
            if [[ -f "$CONFIG_DIR/pool-wallet.conf" ]]; then
                echo ""
                cat "$CONFIG_DIR/pool-wallet.conf"
                echo ""
                echo "Press Enter to continue..."
                read -r
            else
                print_warning "No wallet configuration found"
            fi
            ;;
        4)
            return
            ;;
    esac
}

#===============================================================================
# COMPLETION SCREEN
#===============================================================================

print_completion() {
    print_section "SETUP COMPLETE!"
    
    echo -e "${GREEN}Your Monero node has been successfully set up.${NC}"
    echo ""
    
    # Node-specific information
    if [[ "$NODE_TYPE" == "pool" ]]; then
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}                      MINING POOL BACKEND MODE                         ${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "${BOLD}Pool Software Connection Details:${NC}"
        echo ""
        echo "  RPC Endpoint:    http://127.0.0.1:${RPC_PORT}/json_rpc"
        if [[ "$ENABLE_ZMQ" == "Y" ]]; then
            echo "  ZMQ Endpoint:    tcp://127.0.0.1:${ZMQ_PORT}"
        else
            echo "  ZMQ:             Disabled (pool will use RPC polling)"
        fi
        
        if [[ "$ENABLE_BLOCKNOTIFY" == "Y" ]]; then
            echo ""
            echo -e "  ${GREEN}blocknotify:${NC} Enabled"
            echo "  Command: ${BLOCKNOTIFY_CMD}"
        fi
        
        if [[ -n "$POOL_WALLET_ADDRESS" ]]; then
            echo ""
            echo -e "${BOLD}Pool Wallet Address:${NC}"
            echo "  $POOL_WALLET_ADDRESS"
        fi
        
        echo ""
        echo -e "${BOLD}Test Commands:${NC}"
        echo ""
        echo "  # Check node info"
        echo "  curl -s http://127.0.0.1:${RPC_PORT}/json_rpc \\"
        echo "    -d '{\"jsonrpc\":\"2.0\",\"id\":\"0\",\"method\":\"get_info\"}' \\"
        echo "    -H 'Content-Type: application/json' | jq"
        echo ""
    fi
    
    if [[ "$ENABLE_RPC_LOGIN" == "Y" ]]; then
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}                       RPC AUTHENTICATION                              ${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "${BOLD}RPC Credentials (SAVE THESE!):${NC}"
        echo ""
        echo "  Username: ${RPC_USERNAME}"
        echo "  Password: ${RPC_PASSWORD}"
        echo ""
    fi
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}                         USEFUL COMMANDS                                ${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  # Check service status"
    echo "  sudo systemctl status monerod"
    echo ""
    echo "  # View live logs"
    echo "  sudo journalctl -u monerod -f"
    echo ""
    echo "  # Check sync progress"
    echo "  curl -s http://127.0.0.1:${RPC_PORT}/json_rpc \\"
    echo "    -d '{\"jsonrpc\":\"2.0\",\"id\":\"0\",\"method\":\"get_info\"}' \\"
    echo "    -H 'Content-Type: application/json' | jq '.result | {height, target_height, sync_pct: ((.height / .target_height) * 100 | floor)}'"
    echo ""
    echo "  # Re-run setup (update/reconfigure)"
    echo "  sudo ./setup-monero.sh"
    echo ""
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}                         FILE LOCATIONS                                 ${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  Binaries:       $INSTALL_DIR/"
    echo "  Blockchain:     $DATA_DIR/"
    echo "  Wallets:        $WALLET_DIR/"
    echo "  Config:         $CONFIG_DIR/monerod.conf"
    echo "  Logs:           $LOG_DIR/monerod.log"
    echo ""
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}                         NETWORK PORTS                                  ${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  P2P:   ${P2P_PORT}/tcp (peer-to-peer connections)"
    echo "  RPC:   ${RPC_PORT}/tcp (${RPC_BIND_IP})"
    if [[ "$NODE_TYPE" == "pool" ]] && [[ "$ENABLE_ZMQ" == "Y" ]]; then
        echo "  ZMQ:   ${ZMQ_PORT}/tcp (block notifications, localhost only)"
    fi
    echo ""
    
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}                        SYNC TIME ESTIMATES                            ${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    if [[ "$BLOCKCHAIN_MODE" == "pruned" ]]; then
        echo "  Pruned Node (~65GB):"
        echo "    • SSD + 1Gbps:   6-12 hours"
        echo "    • SSD + 100Mbps: 12-24 hours"
        echo "    • HDD:           3-7 days (not recommended)"
    else
        echo "  Full Node (~180GB):"
        echo "    • SSD + 1Gbps:   12-24 hours"
        echo "    • SSD + 100Mbps: 24-72 hours"
        echo "    • HDD:           1-3 weeks (not recommended)"
    fi
    echo ""
    echo "  Sync is I/O bound - SSD makes a MASSIVE difference!"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}                         PRIVACY OPTIONS                                ${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  For enhanced privacy, consider running monerod over Tor."
    echo "  See: https://www.getmonero.org/resources/user-guides/"
    echo ""
    echo "  Add to /etc/monero/monerod.conf:"
    echo "    proxy=127.0.0.1:9050"
    echo "    anonymous-inbound=YOUR_ONION_ADDRESS:18083,127.0.0.1:18083"
    echo ""
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================

main() {
    # Parse command line arguments
    local skip_update="false"
    for arg in "$@"; do
        case "$arg" in
            --skip-update-check)
                skip_update="true"
                ;;
        esac
    done
    
    print_banner
    
    # Check for script updates first (before root check so we can update even if not root yet)
    if [[ "$skip_update" == "false" ]]; then
        check_for_script_update
    fi
    
    # System checks
    print_section "SYSTEM CHECKS"
    check_root
    check_debian
    check_cpu
    check_memory
    
    # Check for existing installation and select mode
    select_setup_mode
    
    case "$SETUP_MODE" in
        "update")
            perform_update
            ;;
        "reconfigure")
            perform_reconfigure
            ;;
        "wallet")
            manage_wallet
            ;;
        "fresh")
            # Fresh installation
            show_introduction
            configure_node_type
            configure_blockchain_mode
            check_disk_space
            configure_directories
            configure_network
            
            if [[ "$NODE_TYPE" == "pool" ]]; then
                configure_pool_wallet
            fi
            
            show_configuration_summary
            
            # Run installation
            print_section "INSTALLING"
            
            install_dependencies
            create_monero_user
            create_directories
            download_and_verify_monero
            create_symlinks
            create_config_file
            
            if [[ "$NODE_TYPE" == "pool" ]]; then
                create_pool_wallet
            fi
            
            create_systemd_service
            configure_firewall
            start_service
            
            print_completion
            ;;
    esac
}

main "$@"

