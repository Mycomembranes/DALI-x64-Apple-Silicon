#!/bin/bash
#
# build_dali_arm64.sh - Build DaliLite.v5 natively for Apple Silicon (ARM64)
#
# This script downloads, patches, and compiles DaliLite.v5 for M1/M2/M3 Macs.
#
# Prerequisites:
#   - Xcode Command Line Tools: xcode-select --install
#   - GCC with gfortran: brew install gcc
#   - Perl (included with macOS)
#
# Usage:
#   ./build_dali_arm64.sh [install_directory]
#
# Example:
#   ./build_dali_arm64.sh /opt/dali
#   ./build_dali_arm64.sh ~/software/DaliLite.v5
#

set -e

# Default installation directory
INSTALL_DIR="${1:-$(pwd)/DaliLite.v5}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_DIR="$SCRIPT_DIR/../patches"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check for gfortran
    if ! command -v gfortran &> /dev/null; then
        log_error "gfortran not found. Install with: brew install gcc"
        exit 1
    fi

    # Check for gcc
    if ! command -v gcc &> /dev/null; then
        log_error "gcc not found. Install Xcode Command Line Tools: xcode-select --install"
        exit 1
    fi

    # Check architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" != "arm64" ]]; then
        log_warn "This script is optimized for ARM64 (Apple Silicon). Detected: $ARCH"
        log_warn "Continuing anyway, but binaries may not be optimal."
    fi

    log_info "Prerequisites OK"
    log_info "  gfortran: $(gfortran --version | head -1)"
    log_info "  gcc: $(gcc --version | head -1)"
}

# Download DaliLite.v5
download_dali() {
    log_info "Downloading DaliLite.v5..."

    DOWNLOAD_DIR=$(mktemp -d)
    cd "$DOWNLOAD_DIR"

    curl -L -o DaliLite.v5.tar.gz \
        "http://ekhidna2.biocenter.helsinki.fi/dali/DaliLite.v5.tar.gz"

    tar -xzf DaliLite.v5.tar.gz

    # Move to install directory
    mkdir -p "$(dirname "$INSTALL_DIR")"
    mv DaliLite.v5 "$INSTALL_DIR"

    cd "$INSTALL_DIR"
    rm -rf "$DOWNLOAD_DIR"

    log_info "Downloaded to $INSTALL_DIR"
}

# Apply ARM64 patches
apply_patches() {
    log_info "Applying ARM64 compatibility patches..."

    cd "$INSTALL_DIR/src"

    # Backup original files
    cp parsizes.for parsizes.for.orig
    cp gagasizes.for gagasizes.for.orig

    # Apply patches if patch files exist
    if [[ -f "$PATCH_DIR/parsizes.for.patch" ]]; then
        patch -p0 < "$PATCH_DIR/parsizes.for.patch"
    else
        # Apply patch inline
        log_info "Applying parsizes.for modifications inline..."
        sed -i.bak 's/parameter (maxprot=1000000)/parameter (maxprot=10000)/' parsizes.for
    fi

    if [[ -f "$PATCH_DIR/gagasizes.for.patch" ]]; then
        patch -p0 < "$PATCH_DIR/gagasizes.for.patch"
    else
        # Apply patch inline
        log_info "Applying gagasizes.for modifications inline..."
        sed -i.bak 's/parameter(maxres=5000/parameter(maxres=2000/' gagasizes.for
    fi

    log_info "Patches applied"
}

# Compile DALI
compile_dali() {
    log_info "Compiling DaliLite.v5 for ARM64..."

    cd "$INSTALL_DIR/bin"

    # Compiler flags for static linking (avoids dyld issues on macOS)
    FFLAGS="-O3 -static-libgfortran -static-libgcc"
    CFLAGS="-O -Wall -DGCC"

    # Clean any existing builds
    rm -f *.o pipe filter95fitz selfdccp pipedccp fssp puu puutos serialcompare dsspcmbi 2>/dev/null || true

    # Compile dsspcmbi (C code)
    log_info "  Compiling dsspcmbi..."
    gcc $CFLAGS -c ../src/dsspcmbi/AccSurf.c
    gcc $CFLAGS -c ../src/dsspcmbi/CalcAccSurf.c
    gcc $CFLAGS -c ../src/dsspcmbi/Contacts.c
    gcc $CFLAGS -c ../src/dsspcmbi/Date.c
    gcc $CFLAGS -c ../src/dsspcmbi/DsspCMBI.c
    gcc $CFLAGS -c ../src/dsspcmbi/p2clib.c
    gcc $CFLAGS -c ../src/dsspcmbi/Vector.c
    gcc -o dsspcmbi DsspCMBI.o p2clib.o Date.o Vector.o AccSurf.o CalcAccSurf.o Contacts.o -lm
    rm -f *.o

    # Compile Fortran binaries
    log_info "  Compiling pipe..."
    gfortran $FFLAGS ../src/pipe.f ../src/util.f -o pipe 2>/dev/null

    log_info "  Compiling filter95fitz..."
    gfortran $FFLAGS ../src/filter95fitz.f ../src/util.f ../src/u3b-8.f ../src/subfitzfast.f -o filter95fitz 2>/dev/null

    log_info "  Compiling selfdccp..."
    gfortran $FFLAGS ../src/selfdccp.f ../src/util.f -o selfdccp 2>/dev/null

    log_info "  Compiling pipedccp..."
    gfortran $FFLAGS ../src/pipedccp.f -o pipedccp 2>/dev/null

    log_info "  Compiling fssp..."
    gfortran $FFLAGS ../src/fssp.f ../src/util.f ../src/u3b-8.f -o fssp 2>/dev/null

    log_info "  Compiling puu..."
    gfortran $FFLAGS ../src/main.f ../src/puu.f ../src/util.f -o puu 2>/dev/null

    log_info "  Compiling puutos..."
    gfortran $FFLAGS ../src/puutos.f ../src/util.f -o puutos 2>/dev/null

    log_info "  Compiling serialcompare (main alignment engine)..."
    gfortran $FFLAGS \
        ../src/util.f ../src/subfitzfast.f \
        ../src/parsi-admin.f ../src/parsi-align.f ../src/parsi-score.f ../src/parsi-stack.f ../src/parsi-1.f \
        ../src/gagadccp.f ../src/gagagene.f ../src/gagahash.f ../src/gagatool.f \
        ../src/lean.f ../src/clean.f ../src/ssap.f ../src/dimple.f ../src/triplet.f ../src/testi.f ../src/soap4.f \
        ../src/wolf_original.f ../src/u3b-8.f ../src/comparemodules.f ../src/serialcompare.f \
        -o serialcompare 2>/dev/null

    log_info "Compilation complete"
}

# Verify the build
verify_build() {
    log_info "Verifying build..."

    cd "$INSTALL_DIR/bin"

    local all_ok=true

    for binary in dsspcmbi serialcompare pipe filter95fitz selfdccp pipedccp fssp puu puutos; do
        if [[ -x "$binary" ]]; then
            arch=$(file "$binary" | grep -o "arm64" || echo "unknown")
            if [[ "$arch" == "arm64" ]]; then
                log_info "  $binary: OK (ARM64)"
            else
                log_warn "  $binary: Built but not ARM64 ($arch)"
            fi
        else
            log_error "  $binary: MISSING"
            all_ok=false
        fi
    done

    if $all_ok; then
        log_info "All binaries built successfully!"
    else
        log_error "Some binaries failed to build"
        exit 1
    fi

    # Quick functional test
    log_info "Running quick functional test..."
    if ./serialcompare 2>&1 | grep -q "USAGE"; then
        log_info "  serialcompare: FUNCTIONAL"
    else
        log_error "  serialcompare: NOT WORKING (dyld issue?)"
        exit 1
    fi

    if ./dsspcmbi 2>&1 | grep -q "COPYRIGHT"; then
        log_info "  dsspcmbi: FUNCTIONAL"
    else
        log_error "  dsspcmbi: NOT WORKING"
        exit 1
    fi
}

# Print usage instructions
print_usage() {
    log_info "Installation complete!"
    echo ""
    echo "=============================================="
    echo "DaliLite.v5 ARM64 Installation Summary"
    echo "=============================================="
    echo ""
    echo "Installation directory: $INSTALL_DIR"
    echo ""
    echo "To use DALI, add to your shell profile:"
    echo ""
    echo "  export DALI_DIR=\"$INSTALL_DIR\""
    echo "  export PATH=\"\$DALI_DIR/bin:\$PATH\""
    echo ""
    echo "Quick start:"
    echo ""
    echo "  # Import a PDB file"
    echo "  import.pl --pdbfile structure.pdb --pdbid TEST --dat ./DAT --clean"
    echo ""
    echo "  # Run pairwise alignment"
    echo "  dali.pl --query query.txt --db db.txt --dat1 ./DAT --dat2 ./DAT"
    echo ""
    echo "Limitations (ARM64 build):"
    echo "  - Max 10,000 structures per list (vs 1M in original)"
    echo "  - Max 2,000 residues per structure (vs 5,000 in original)"
    echo ""
    echo "=============================================="
}

# Main
main() {
    echo "========================================"
    echo "DaliLite.v5 ARM64 Build Script"
    echo "========================================"
    echo ""

    check_prerequisites

    if [[ -d "$INSTALL_DIR" ]]; then
        log_warn "Installation directory already exists: $INSTALL_DIR"
        read -p "Overwrite? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Aborted"
            exit 0
        fi
        rm -rf "$INSTALL_DIR"
    fi

    download_dali
    apply_patches
    compile_dali
    verify_build
    print_usage
}

main "$@"
