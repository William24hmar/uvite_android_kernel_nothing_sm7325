#!/bin/bash
# build.sh - Android Kernel Build Script with EVA GCC
# Author: Madara273 / William24hmar
# ----------------------------------------------------------------------------

# ---- Define colors ----
GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
YELLOW=$'\033[1;33m'
PURPLE=$'\033[0;35m'
MAGENTA=$'\033[1;35m'
LGREEN=$'\033[92m'
PINK=$'\033[38;5;206m'
CYAN=$'\033[0;36m'
BLUE=$'\033[0;34m'
GREY=$'\033[38;5;250m'
NC=$'\033[0m'

# ---- Get the absolute path of the current directory ----
CURRENT_DIR="$(pwd)"

# ---- Set timezone ----
export TZ=Europe/Kiev

# ---- random_color ----
random_color() {
	local colors=($GREEN $RED $YELLOW $PURPLE $BLUE)
	local random_index=$((RANDOM % ${#colors[@]}))
	echo -e "${colors[$random_index]}"
}

# ---- Get OS info ----
. /etc/os-release 2>/dev/null || { OS=$(uname -s); VERSION_ID=$(uname -r); }

echo -e "\n$(random_color)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "    - OS: $NAME $VERSION_ID"
echo -e "    - Kernel: $(uname -r)"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# ---- ASCII Art Logo ----
ascii_art_logo() {
	echo -e "
$(random_color)*****************************NEUTRINO*****************************${NC}
$(random_color) ______ ______ _______ _______ _______ _______ ___ ___ ______ _______ ${NC}
$(random_color)|   __ \   __ \       |_     _|       |_     _|   |   |   __ \    ___|${NC}
$(random_color)|    __/      <   -   | |   | |   -   | |   |  \     /|    __/    ___|${NC}
$(random_color)|___|  |___|__|_______| |___| |_______| |___|   |___| |___|  |_______|${NC}
"
}

# ---- User input ----
echo -e "${PURPLE}Enter KBUILD_USER:${NC}"
read -t 5 -rp "KBUILD_USER: " KBUILD_USER
KBUILD_USER="${KBUILD_USER:-William24hmar}"
echo "$KBUILD_USER"

echo -e "${PURPLE}Enter KBUILD_HOST:${NC}"
read -t 5 -rp "KBUILD_HOST: " KBUILD_HOST
KBUILD_HOST="${KBUILD_HOST:-William24hmar_GNU/Linux-2025.3}"
echo "$KBUILD_HOST"

# ─────────────────────────────────────────────────────────────────────────────
#  TOOLCHAIN CONFIGURATION - EVA GCC
# ─────────────────────────────────────────────────────────────────────────────

# Toolchain directory
TLDR="$(pwd)/toolchains"

# EVA GCC directories
GCC64_DIR="$TLDR/gcc-arm64"
GCC32_DIR="$TLDR/gcc-arm"

# Neutron Clang (optional fallback)
CLANG_DIR="$TLDR/clang"

# ---- Download and setup EVA GCC toolchains ----
setup_toolchains() {
	echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo -e "${CYAN}  Setting up EVA GCC toolchains${NC}"
	echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

	mkdir -p "$TLDR"
	cd "$TLDR" || exit 1

	# ── EVA GCC ARM64 & ARM32 ──────────────────────────────────────────
	if [ -f "$GCC64_DIR/bin/aarch64-elf-gcc" ] && [ -f "$GCC32_DIR/bin/arm-eabi-gcc" ]; then
		echo -e "${GREEN}✔ EVA GCC already present${NC}"
	else
		echo -e "${YELLOW}Downloading EVA GCC (ARM64 + ARM32)...${NC}"
		
		# Files to download
		files=("eva-gcc-arm" "eva-gcc-arm64")
		
		# Base URL
		repo_url="https://github.com/mvaisakh/gcc-build/releases/download/"
		
		# Release date (adjust if needed)
		release_date="22052025"
		
		# Download and extract
		for file in "${files[@]}"; do
			filename="${file}-${release_date}.xz"
			url="${repo_url}${release_date}/${filename}"
			
			if [ ! -d "${file/-/}" ]; then  # gcc-arm or gcc-arm64
				echo -e "${YELLOW}Downloading: $filename${NC}"
				if aria2c -x 16 -s 16 -o "$filename" "$url" 2>/dev/null || wget -q --show-progress -O "$filename" "$url"; then
					echo -e "${GREEN}Download successful: $filename${NC}"
					tar xf "$filename"
					rm -f "$filename"
					find . -name "${file}*.1.xz" -delete
				else
					echo -e "${RED}✘ Download failed: $url${NC}"
					exit 1
				fi
			fi
		done
		
		echo -e "${GREEN}✔ EVA GCC ready${NC}"
	fi

	# ── Optional: Neutron Clang ──────────────────────────────────────
	if [ ! -d "$CLANG_DIR" ]; then
		echo -e "${BLUE}Optionally downloading Neutron Clang...${NC}"
		mkdir -p clang
		bash <(curl -s "https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman") -S 2>/dev/null || true
		[ -d "bin" ] && mv bin build.info lib share clang/ 2>/dev/null || true
	fi

	cd "$CURRENT_DIR" || exit 1

	# ── Export PATH ──────────────────────────────────────────────────
	export PATH="$GCC64_DIR/bin:$GCC32_DIR/bin:$CLANG_DIR/bin:$PATH"

	# ── Get compiler version strings ─────────────────────────────────
	if [ -f "$GCC64_DIR/bin/aarch64-elf-gcc" ]; then
		COMPILER_STRING="$($GCC64_DIR/bin/aarch64-elf-gcc --version 2>&1 | head -1)"
		CC_VERSION="$COMPILER_STRING"
		echo -e "${GREEN}Compiler: $COMPILER_STRING${NC}"
	else
		echo -e "${RED}✘ EVA GCC not found!${NC}"
		exit 1
	fi
}

# Run toolchain setup
setup_toolchains

# ─────────────────────────────────────────────────────────────────────────────
#  BUILD ENVIRONMENT VARIABLES
# ─────────────────────────────────────────────────────────────────────────────

THREAD="${1:-$(nproc --all)}"

# ---- Target Variables ----
TARGET_ARCH="arm64"
TARGET_SUBARCH="arm64"
TARGET_CC="aarch64-elf-gcc"
TARGET_CROSS_COMPILE="aarch64-elf-"
TARGET_CROSS_COMPILE_COMPAT="arm-eabi-"
TARGET_BUILD_USER="$KBUILD_USER"
TARGET_BUILD_HOST="$KBUILD_HOST"
TARGET_DEVICE="phone1"
TARGET_OUT="$(pwd)/../NOTHING_PHONE1_OUT"
TARGET_DTC_FLAGS="-q"

TARGET_COMPILER_STRING="$COMPILER_STRING"
TARGET_CC_VERSION="$CC_VERSION"

# ---- Kernel files ----
TARGET_KERNEL_FILE="$TARGET_OUT/arch/arm64/boot/Image"
TARGET_KERNEL_DTB="$TARGET_OUT/arch/arm64/boot/dtb"
TARGET_KERNEL_DTB_IMG="$TARGET_OUT/arch/arm64/boot/dtb.img"
TARGET_KERNEL_DTBO_IMG="$TARGET_OUT/arch/arm64/boot/dtbo.img"

get_kernel_version(){
	TARGET_KERNEL_MOD_VERSION="$(make kernelversion O=$TARGET_OUT ARCH=arm64)"
}

# ---- Build args for EVA GCC ----
MAKE_ARGS=(
	"ARCH=$TARGET_ARCH"
	"SUBARCH=$TARGET_SUBARCH"
	"CC=$TARGET_CC"
	"HOSTCC=gcc"
	"HOSTCXX=g++"
	"HOSTLD=ld"
	"CROSS_COMPILE=$TARGET_CROSS_COMPILE"
	"CROSS_COMPILE_COMPAT=$TARGET_CROSS_COMPILE_COMPAT"
	"CC_COMPAT=$GCC32_DIR/bin/arm-eabi-gcc"
	"AR=aarch64-elf-ar"
	"NM=aarch64-elf-nm"
	"LD=aarch64-elf-ld"
	"OBJCOPY=aarch64-elf-objcopy"
	"OBJDUMP=aarch64-elf-objdump"
	"STRIP=aarch64-elf-strip"
	"READELF=aarch64-elf-readelf"
	"GCC_LTO=1"
	"GRAPHITE=1"
	"DTC_FLAGS=$TARGET_DTC_FLAGS"
	"O=$TARGET_OUT"
	"KBUILD_BUILD_USER=$TARGET_BUILD_USER"
	"KBUILD_BUILD_HOST=$TARGET_BUILD_HOST"
	"-j$THREAD"
)

# ---- Defconfig ----
DEFCONFIG_NAME="phone1_defconfig"

# ---- Time ----
START_SEC=$(date +%s)
CURRENT_TIME=$(date '+%Y%m%d-%H%M')

# ---- Keystore paths ----
HOME="${HOME:-/tmp}"
[ "$HOME" = "/" ] && HOME="/tmp"
SIGNER_DIR="$HOME/.sakura"

KEYSTORE="$SIGNER_DIR/keystore.p12"
PASSFILE="$SIGNER_DIR/.store_pass"
ALIASFILE="$SIGNER_DIR/.alias"
ROOTCA_KEY="$SIGNER_DIR/rootCA.key"
ROOTCA_CERT="$SIGNER_DIR/rootCA.pem"
TENZO_KEY="$SIGNER_DIR/tenzo.key"
TENZO_CERT="$SIGNER_DIR/tenzo.crt"
P12_FILE="$SIGNER_DIR/tenzo.p12"
CSR_FILE="$SIGNER_DIR/tenzo.csr"

# ---- Output ----
AK3_PATH="$TARGET_OUT/AnyKernel3"
LOG_FILE="$AK3_PATH/build.log"

# ---- Git info ----
remote=$(git remote -v 2>&1 | grep push | head -n1 | cut -f2 | sed "s/(push)//" | cut -f4 -d "/")
domain=$(git remote -v 2>&1 | grep push | head -n1 | cut -f2 | sed "s/(push)//" | cut -f5 -d "/" | xargs)
branch=$(git status 2>&1 | grep "On branch" | sed -e 's/On branch //g')
commit=$(git rev-parse --short=8 HEAD)

KERNEL_DIR=$(pwd)
echo -e "${GREEN}$KERNEL_DIR${NC}"

# ─────────────────────────────────────────────────────────────────────────────
#  FUNCTIONS (kept from original build.sh - no changes needed)
# ─────────────────────────────────────────────────────────────────────────────

display_build_info(){
	echo -e "${PURPLE}***************Neutrino-Kernel**************${NC}"
	echo -e "PRODUCT: $TARGET_DEVICE"
	echo -e "USER: $KBUILD_USER"
	echo -e "HOST: $KBUILD_HOST"
	echo -e "SUBLEVEL: $(grep -E '^SUBLEVEL =' Makefile | awk '{print $3}')"
	echo -e "${PURPLE}***************Device-Builder**************${NC}"
	echo -e "BUILD_DEVICE: $(lsb_release -a 2>/dev/null | grep Description | cut -f2)"
	echo -e "Compiler: $COMPILER_STRING"
	echo -e "Core count: $(nproc)"
	echo -e "Build Date: $(date +"%Y-%m-%d %H:%M")"
	echo -e "${PURPLE}*************last commit details***********${NC}"
	echo -e "Last commit (name): $(git log -1 --pretty=format:%s)"
	echo -e "Last commit (hash): $(git log -1 --pretty=format:%H)"
	echo -e "${PURPLE}*******************************************${NC}"
}

# [Rest of functions remain unchanged - install_packages, clone_anykernel3, 
#  check_tools, make_defconfig, build_kernel, link_all_dtb_files, 
#  generate_secure_keystore, sign_zip, show_fingerprint, generate_flashable,
#  save_defconfig, clean, create_changelog, display_kernel_version_info, etc.]

# ... [Copy all remaining functions from your original build.sh] ...

choose_action(){
	while true; do
		echo -e "Choose an action:"
		echo -e "${GREEN}1.👉 Install necessary packages${NC}"
		echo -e "${GREEN}2.👉 Start kernel compilation${NC}"
		echo -e "${GREEN}3.👉 Exit program${NC}"

		read -t 5 -p "Enter the action number (1/2/3): " choice
		[ -z "$choice" ] && echo -e "${YELLOW}No input detected. Automatically selecting action 1.${NC}" && install_packages && echo -e "${YELLOW}Proceeding to action 2 automatically.${NC}" && compile_kernel && break

		case $choice in
			1 ) install_packages;;
			2 ) compile_kernel;;
			3 ) exit;;
			* ) echo -e "${RED}Invalid choice. Please enter 1, 2, or 3.${NC}";;
		esac
	done
}

compile_kernel() {
	random_color
	ascii_art_logo
	clean
	check_tools
	clone_anykernel3
	make_defconfig
	display_build_info
	create_changelog
	save_defconfig
	build_kernel
	link_all_dtb_files
	generate_flashable
	display_kernel_version_info
}

choose_action

echo -e "${GREEN}Done.${NC}"