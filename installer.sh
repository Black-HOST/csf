#!/bin/bash

set -euo pipefail

# Config
CSF_URL="https://github.com/Black-HOST/csf/releases/latest/download/csf.tgz"
INSTALL_DIR="/usr/src"
CSF_DIR="${INSTALL_DIR}/csf"

# Color Output Helpers
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m" # No Color

info()    { echo -e "${BLUE}[+]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[-]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }

# Root Check
info "Checking root permissions..."
if [[ $EUID -ne 0 ]]; then
    error "This installer must be run as root."
    exit 1
fi

# Detect Package Manager
detect_package_manager() {
    if command -v apt-get &> /dev/null; then echo "apt"
    elif command -v dnf &> /dev/null; then echo "dnf"
    elif command -v yum &> /dev/null; then echo "yum"
    else echo ""; fi
}

# Install a package quietly
install_package() {
    local pkg="$1"
    local PM
    PM=$(detect_package_manager)

    case "$PM" in
        apt)
            DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null || true
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $pkg >/dev/null 
            info "Debian"
            ;;
        dnf|yum)
            "$PM" install -y -q $pkg >/dev/null
            info "DNF"
            ;;
        *)
            warn "Unsupported package manager. Please ensure '$pkg' is installed manually."
            ;;
    esac
}

# Download file using curl or wget
fetch() {
    local url="$1"
    local dest="$2"
    if command -v curl &> /dev/null; then
        curl -fsSL "$url" -o "$dest"
    elif command -v wget &> /dev/null; then
        wget -q "$url" -O "$dest"
    fi
}

# Install Dependencies
install_dependencies() {
    local PM
    PM=$(detect_package_manager)
    info "Installing dependencies..."

    if [[ "$PM" == "apt" ]]; then
        install_package "wget curl tar perl libwww-perl liblwp-protocol-https-perl libgd-graph-perl iptables host unzip sendmail"
    elif [[ "$PM" == "yum" || "$PM" == "dnf" ]]; then
        install_package "wget tar curl perl perl-libwww-perl.noarch perl-LWP-Protocol-https.noarch perl-GDGraph perl-Math-BigInt.noarch iptables host unzip sendmail iptables host unzip sendmail"
    else
        warn "Could not detect package manager. Skipping dependency installation."
    fi
}

# Main Installation
install_csf() {
    info "Preparing installation directory..."
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    if [[ -f "csf.tgz" ]]; then
        info "Removing old csf.tgz..."
        rm -f csf.tgz
    fi

    info "Downloading CSF..."
    fetch "$CSF_URL" "csf.tgz"

    info "Extracting CSF..."
    tar -xzf csf.tgz

    if [[ ! -d "$CSF_DIR" ]]; then
        error "Extraction failed. Directory $CSF_DIR not found."
        exit 1
    fi

    info "Running CSF install script..."
    cd "$CSF_DIR"
    sh install.sh
}

# Verify Installation
verify_install() {
    info "Verifying installation..."
    if [[ -f "/usr/local/csf/bin/csftest.pl" ]]; then
        perl /usr/local/csf/bin/csftest.pl
        success "Installation script completed."
    else
        error "Verification failed. /usr/local/csf/bin/csftest.pl not found."
        exit 1
    fi
}

# Execution Flow
install_dependencies
install_csf
verify_install
