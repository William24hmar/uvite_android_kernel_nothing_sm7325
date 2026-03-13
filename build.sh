#!/usr/bin/env bash

set -e

echo "======================================="
echo " Nothing Phone 1 Kernel Build Script "
echo "======================================="

# Kernel root
KERNEL_ROOT=$(pwd)

# Output directory
OUT_DIR=$KERNEL_ROOT/out

# Toolchain directory
TOOLCHAIN_DIR=$HOME/toolchains

# Defconfig
DEFCONFIG=phone1_defconfig

# CPU threads
JOBS=$(nproc)

mkdir -p $OUT_DIR
mkdir -p $TOOLCHAIN_DIR

echo "Kernel root : $KERNEL_ROOT"
echo "Output dir  : $OUT_DIR"
echo "Threads     : $JOBS"

# -------------------------
# Install dependencies
# -------------------------

if command -v apt &> /dev/null; then

    sudo apt update

    sudo apt install -y \
        git bc bison build-essential flex \
        curl wget zip unzip cpio \
        python3 \
        device-tree-compiler \
        libssl-dev libelf-dev \
        gcc g++ \
        lz4 xz-utils zstd

fi

# -------------------------
# Snapdragon LLVM toolchain
# -------------------------

if [ ! -d "$TOOLCHAIN_DIR/llvm-arm-toolchain-ship" ]; then

    echo "Downloading Snapdragon LLVM..."

    cd $TOOLCHAIN_DIR

    curl -LO https://github.com/ravindu644/Android-Kernel-Tutorials/releases/download/toolchains/llvm-arm-toolchain-ship-10.0.9.tar.gz

    tar -xf llvm-arm-toolchain-ship-10.0.9.tar.gz

    rm llvm-arm-toolchain-ship-10.0.9.tar.gz

    cd $KERNEL_ROOT

fi

# -------------------------
# ARM GNU Toolchain
# -------------------------

if [ ! -d "$TOOLCHAIN_DIR/gcc" ]; then

    echo "Downloading ARM GNU toolchain..."

    mkdir -p $TOOLCHAIN_DIR/gcc
    cd $TOOLCHAIN_DIR/gcc

    curl -LO https://developer.arm.com/-/media/Files/downloads/gnu/14.2.rel1/binrel/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu.tar.xz

    tar -xf arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu.tar.xz

    cd $KERNEL_ROOT

fi

# -------------------------
# Toolchain paths
# -------------------------

CLANG_DIR=$TOOLCHAIN_DIR/llvm-arm-toolchain-ship/10.0.9
GCC_DIR=$TOOLCHAIN_DIR/gcc/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu

export PATH=$CLANG_DIR/bin:$PATH
export LD_LIBRARY_PATH=$CLANG_DIR/lib:$LD_LIBRARY_PATH

# -------------------------
# Kernel build environment
# -------------------------

export ARCH=arm64
export SUBARCH=arm64

export KBUILD_BUILD_USER=William
export KBUILD_BUILD_HOST=Uvite

export CROSS_COMPILE=$GCC_DIR/bin/aarch64-none-linux-gnu-
export CC=$CLANG_DIR/bin/clang
export CLANG_TRIPLE=aarch64-linux-gnu-

# -------------------------
# Clean old builds
# -------------------------

echo "Cleaning old build..."
make O=$OUT_DIR clean

# -------------------------
# Load defconfig
# -------------------------

echo "Loading defconfig..."

make \
O=$OUT_DIR \
ARCH=arm64 \
$DEFCONFIG

# -------------------------
# Build kernel
# -------------------------

echo "Building kernel..."

make -j$JOBS \
O=$OUT_DIR \
ARCH=arm64 \
CC=clang \
CLANG_TRIPLE=aarch64-linux-gnu- \
CROSS_COMPILE=$CROSS_COMPILE \
CROSS_COMPILE_ARM32=arm-linux-gnueabi-

# -------------------------
# Check result
# -------------------------

IMAGE=$OUT_DIR/arch/arm64/boot/Image

if [ -f "$IMAGE" ]; then

    echo ""
    echo "======================================="
    echo " Kernel Build Successful "
    echo "======================================="
    echo "$IMAGE"

else

    echo "Kernel build failed"
    exit 1

fi
