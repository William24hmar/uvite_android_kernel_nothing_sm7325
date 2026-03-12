#!/bin/bash
# build.sh - Android Kernel Build Script with EVA GCC
# Author: Madara273 / William24hmar
# Supports: GitHub Actions (auto mode) & Local builds (interactive mode)
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

# ---- User input (skip in GitHub Actions) ----
if [ -z "$GITHUB_ACTIONS" ]; then
	echo -e "${PURPLE}Enter KBUILD_USER:${NC}"
	read -t 5 -rp "KBUILD_USER: " KBUILD_USER
	KBUILD_USER="${KBUILD_USER:-William24hmar}"
	echo "$KBUILD_USER"

	echo -e "${PURPLE}Enter KBUILD_HOST:${NC}"
	read -t 5 -rp "KBUILD_HOST: " KBUILD_HOST
	KBUILD_HOST="${KBUILD_HOST:-William24hmar_GNU/Linux-2025.3}"
	echo "$KBUILD_HOST"
else
	KBUILD_USER="William24hmar"
	KBUILD_HOST="GitHub-Actions-CI"
	echo -e "${GREEN}GitHub Actions mode: KBUILD_USER=$KBUILD_USER, KBUILD_HOST=$KBUILD_HOST${NC}"
fi

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
		
		# Release date
		release_date="22052025"
		
		# Download and extract
		for file in "${files[@]}"; do
			filename="${file}-${release_date}.xz"
			url="${repo_url}${release_date}/${filename}"
			target_dir="${file/eva-/}"  # gcc-arm or gcc-arm64
			
			if [ ! -d "$target_dir" ]; then
				echo -e "${YELLOW}Downloading: $filename${NC}"
				if command -v aria2c &>/dev/null; then
					aria2c -x 16 -s 16 -o "$filename" "$url" 2>/dev/null || wget -q --show-progress -O "$filename" "$url"
				else
					wget -q --show-progress -O "$filename" "$url"
				fi
				
				if [ -f "$filename" ]; then
					echo -e "${GREEN}Download successful: $filename${NC}"
					tar xf "$filename"
					rm -f "$filename"
					find . -name "${file}*.1.xz" -delete 2>/dev/null || true
				else
					echo -e "${RED}✘ Download failed: $url${NC}"
					exit 1
				fi
			fi
		done
		
		echo -e "${GREEN}✔ EVA GCC ready${NC}"
	fi

	# ── Optional: Neutron Clang ──────────────────────────────────────
	if [ ! -d "$CLANG_DIR/bin" ]; then
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
TARGET_OUT="$(pwd)/out"
TARGET_DTC_FLAGS="-q"

TARGET_COMPILER_STRING="$COMPILER_STRING"
TARGET_CC_VERSION="$CC_VERSION"

# ---- Kernel files ----
TARGET_KERNEL_FILE="$TARGET_OUT/arch/arm64/boot/Image"
TARGET_KERNEL_DTB="$TARGET_OUT/arch/arm64/boot/dtb"
TARGET_KERNEL_DTB_IMG="$TARGET_OUT/arch/arm64/boot/dtb.img"
TARGET_KERNEL_DTBO_IMG="$TARGET_OUT/arch/arm64/boot/dtbo.img"

get_kernel_version(){
	TARGET_KERNEL_MOD_VERSION="$(make kernelversion O=$TARGET_OUT ARCH=arm64 2>/dev/null || echo 'unknown')"
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
remote=$(git remote -v 2>&1 | grep push | head -n1 | cut -f2 | sed "s/(push)//" | cut -f4 -d "/" 2>/dev/null || echo "unknown")
domain=$(git remote -v 2>&1 | grep push | head -n1 | cut -f2 | sed "s/(push)//" | cut -f5 -d "/" | xargs 2>/dev/null || echo "unknown")
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
commit=$(git rev-parse --short=8 HEAD 2>/dev/null || echo "unknown")

KERNEL_DIR=$(pwd)
echo -e "${GREEN}Kernel directory: $KERNEL_DIR${NC}"

# ─────────────────────────────────────────────────────────────────────────────
#  FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

display_build_info(){
	echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo -e "${PURPLE}        Neutrino Kernel Build Info${NC}"
	echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo -e "PRODUCT       : $TARGET_DEVICE"
	echo -e "USER          : $KBUILD_USER"
	echo -e "HOST          : $KBUILD_HOST"
	echo -e "SUBLEVEL      : $(grep -E '^SUBLEVEL =' Makefile 2>/dev/null | awk '{print $3}' || echo 'N/A')"
	echo -e "COMPILER      : $COMPILER_STRING"
	echo -e "CORES         : $(nproc)"
	echo -e "BUILD DATE    : $(date +"%Y-%m-%d %H:%M")"
	echo -e "LAST COMMIT   : $(git log -1 --pretty=format:%s 2>/dev/null || echo 'N/A')"
	echo -e "COMMIT HASH   : $(git log -1 --pretty=format:%H 2>/dev/null || echo 'N/A')"
	echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Function for "smart" installation
pkg_install() {
	if [ -f /etc/arch-release ]; then
		[ -n "$1" ] && sudo pacman -S --needed --noconfirm "$1" 2>/dev/null || true
	else
		[ -n "$2" ] && sudo apt-get install -y "$2" 2>/dev/null || true
	fi
}

# ---- Install packages ----
install_packages(){
	echo -e "${YELLOW}Starting package installation...${NC}"

	pkg_install "bc" "bc"
	pkg_install "bison" "bison"
	pkg_install "base-devel" "build-essential"
	pkg_install "zstd" "zstd"
	pkg_install "flex" "flex"
	pkg_install "gnupg" "gnupg"
	pkg_install "gperf" "gperf"
	pkg_install "ccache" "ccache"
	pkg_install "lz4" "liblz4-tool"
	pkg_install "libxml2" "libxml2"
	pkg_install "" "libxml2-utils"
	pkg_install "libpng" "pngcrush"
	pkg_install "schedtool" "schedtool"
	pkg_install "squashfs-tools" "squashfs-tools"
	pkg_install "libxslt" "xsltproc"
	pkg_install "zlib" "zlib1g-dev"
	pkg_install "ncurses" "libncurses5-dev"
	pkg_install "bzip2" "bzip2"
	pkg_install "git" "git"
	pkg_install "gcc" "gcc"
	pkg_install "gcc" "g++"
	pkg_install "openssl" "libssl-dev"
	pkg_install "python-pip" "python3-pip"
	pkg_install "cpio" "cpio"
	pkg_install "binutils" "binutils"
	pkg_install "zip" "zip"
	pkg_install "dtc" "device-tree-compiler"
	pkg_install "jdk21-openjdk" "default-jre"

	echo -e "${GREEN}Package installation completed.${NC}"
}

# ---- Clone Anykernel3 ----
clone_anykernel3(){
	if [ -d "$AK3_PATH" ]; then
		echo -e "${GREEN}✔ AnyKernel3 already exists, skipping clone${NC}"
		return 0
	fi

	if [ -n "$GITHUB_ACTIONS" ]; then
		# Auto mode for CI
		echo -e "${YELLOW}Cloning AnyKernel3 (master branch)...${NC}"
		git clone --depth=1 https://github.com/William24hmar/AnyKernel3.git -b master "$AK3_PATH" && \
			echo -e "${GREEN}✔ Clone successful${NC}" || { echo -e "${RED}✘ Clone failed${NC}"; exit 1; }
	else
		# Interactive mode for local
		while true; do
			echo -e "${YELLOW}Select branch to clone:${NC}"
			echo -e "${BLUE}1.👉 master${NC}"
			echo -e "${BLUE}2.👉 Custom git clone command${NC}"

			read -t 5 -rp "Enter your choice (1 or 2): " choice
			[ -z "$choice" ] && choice=1

			case $choice in
				1)
					git clone --depth=1 https://github.com/William24hmar/AnyKernel3.git -b master "$AK3_PATH" && \
						{ echo -e "${GREEN}✔ Clone successful${NC}"; break; } || echo -e "${RED}✘ Clone failed${NC}"
					;;
				2)
					read -rp "Enter the full git clone command: " clone_command
					eval "$clone_command $AK3_PATH" && { echo -e "${GREEN}✔ Clone successful${NC}"; break; } || echo -e "${RED}✘ Clone failed${NC}"
					;;
				*)
					echo -e "${RED}Invalid choice${NC}"
					;;
			esac
		done
	fi
}

# ---- Check tools ----
check_tools(){
	echo -e "${YELLOW}Checking for necessary tools...${NC}"
	command -v make > /dev/null 2>&1 || { echo -e "${RED}✘ make is not installed${NC}"; exit 1; }
	command -v dtc > /dev/null 2>&1 || { echo -e "${RED}✘ dtc is not installed${NC}"; exit 1; }
	echo -e "${GREEN}✔ All necessary tools are installed${NC}"
}

# ---- Make defconfig ----
make_defconfig(){
	echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo -e "${YELLOW} Generating kernel configuration...${NC}"
	echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	
	mkdir -p "$TARGET_OUT"
	make "${MAKE_ARGS[@]}" "$DEFCONFIG_NAME" || { echo -e "${RED}✘ Failed to create defconfig${NC}"; exit 1; }
	
	echo -e "${GREEN}✔ Kernel configuration created successfully${NC}"
}

# ---- Build kernel ----
build_kernel() {
	echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo -e "${YELLOW} Building the kernel...${NC}"
	echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

	BUILD_START=$(date +%s)
	mkdir -p "$(dirname "$LOG_FILE")"

	echo -e "${YELLOW}Starting make with ${THREAD} threads...${NC}"
	make "${MAKE_ARGS[@]}" 2>&1 | tee "$LOG_FILE"
	
	if [ "${PIPESTATUS[0]}" -ne 0 ]; then
		echo -e "${RED}✘ Kernel build failed!${NC}"
		echo -e "${RED}Check log: $LOG_FILE${NC}"
		exit 1
	fi
	
	echo -e "${GREEN}✔ Kernel compiled successfully${NC}"

	# Install modules if enabled
	MODULES_DIR="$TARGET_OUT/modules_inst"
	mkdir -p "$MODULES_DIR"

	if grep -q '^CONFIG_MODULES=y$' "$TARGET_OUT/.config" 2>/dev/null; then
		echo -e "${YELLOW}Installing kernel modules...${NC}"
		make "${MAKE_ARGS[@]}" INSTALL_MOD_PATH=modules_inst INSTALL_MOD_STRIP=1 modules_install
		echo -e "${GREEN}✔ Kernel modules installed${NC}"
	else
		echo -e "${PURPLE}ℹ CONFIG_MODULES not set - no external modules${NC}"
	fi

	BUILD_END=$(date +%s)
	TOTAL_SEC=$(( BUILD_END - BUILD_START ))
	echo -e "${GREEN}✔ Build completed in $(( TOTAL_SEC / 60 ))m $(( TOTAL_SEC % 60 ))s${NC}"
}

# ---- Link DTB ----
link_all_dtb_files(){
	echo -e "${YELLOW}Linking DTB files...${NC}"
	
	mkdir -p "$TARGET_OUT/arch/arm64/boot"
	
	if find "$TARGET_OUT/arch/arm64/boot/dts/" -name '*.dtb' 2>/dev/null | grep -q .; then
		find "$TARGET_OUT/arch/arm64/boot/dts/" -name '*.dtb' -exec cat {} + > "$TARGET_OUT/arch/arm64/boot/dtb"
		echo -e "${GREEN}✔ DTB files linked: $(ls -lh "$TARGET_OUT/arch/arm64/boot/dtb" | awk '{print $5}')${NC}"
	else
		echo -e "${YELLOW}⚠ No DTB files found, skipping...${NC}"
	fi
}

# ---- Clean ----
clean() {
	echo -e "${YELLOW}Cleaning build directory...${NC}"
	make mrproper -j$THREAD > /dev/null 2>&1 || true
	make clean -j$THREAD > /dev/null 2>&1 || true
	rm -rf "$TARGET_OUT" .config output
	echo -e "${GREEN}✔ Clean completed${NC}"
}

# ---- Create changelog ----
create_changelog() {
	mkdir -p "$AK3_PATH"
	local changelog_file="$AK3_PATH/changelog.txt"
	
	echo -e "${YELLOW}Creating changelog...${NC}"
	git log -n 400 --pretty=format:"%h - %s (%an)" > "$changelog_file" 2>/dev/null || echo "No git history" > "$changelog_file"
	sed -i -e "s/^/- /" "$changelog_file" 2>/dev/null || true
	
	echo -e "${PURPLE}ℹ Changelog saved to $changelog_file${NC}"
}

# ---- Save defconfig ----
save_defconfig() {
	if [ -f "$TARGET_OUT/.config" ]; then
		mkdir -p "$AK3_PATH"
		cp "$TARGET_OUT/.config" "$AK3_PATH/defconfig"
		echo -e "${GREEN}✔ Kernel config saved to AnyKernel3${NC}"
	fi
}

# ---- Keystore functions ----
generate_secure_keystore() {
	[[ -f "$KEYSTORE" ]] && { echo -e "${GREEN}✔ Keystore exists${NC}"; return 0; }
	
	echo -e "${YELLOW}Creating secure keystore...${NC}"
	mkdir -p "$SIGNER_DIR" && chmod 700 "$SIGNER_DIR"
	
	PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 18 2>/dev/null || echo "defaultpass123")
	UNIQUE_ID=$(date +%Y%m%d_%H%M%S)
	KEYALIAS="tenzoKey_${UNIQUE_ID}"
	
	echo "$PASS" > "$PASSFILE"
	echo "$KEYALIAS" > "$ALIASFILE"
	chmod 600 "$PASSFILE" "$ALIASFILE"
	
	# Generate root CA
	openssl genrsa -out "$ROOTCA_KEY" 4096 2>/dev/null && \
	openssl req -x509 -new -nodes -key "$ROOTCA_KEY" -sha256 -days 9125 \
		-out "$ROOTCA_CERT" -subj "/CN=Tenzo Root CA/O=William24hmar/C=UA" 2>/dev/null || \
		{ echo -e "${RED}✘ Root CA generation failed${NC}"; return 1; }
	
	# Generate signing key
	openssl genrsa -out "$TENZO_KEY" 4096 2>/dev/null && \
	openssl req -new -key "$TENZO_KEY" -out "$CSR_FILE" \
		-subj "/CN=Tenzo/OU=Root/O=William24hmar/L=UA/ST=Ukraine/C=UA" 2>/dev/null && \
	openssl x509 -req -in "$CSR_FILE" -CA "$ROOTCA_CERT" -CAkey "$ROOTCA_KEY" \
		-CAcreateserial -out "$TENZO_CERT" -sha256 -days 365 2>/dev/null && \
	openssl pkcs12 -export -inkey "$TENZO_KEY" -in "$TENZO_CERT" \
		-certfile "$ROOTCA_CERT" -out "$P12_FILE" \
		-password pass:"$PASS" -name "$KEYALIAS" 2>/dev/null && \
	keytool -importkeystore \
		-srckeystore "$P12_FILE" -srcstoretype PKCS12 -srcstorepass "$PASS" \
		-destkeystore "$KEYSTORE" -deststoretype PKCS12 -deststorepass "$PASS" \
		-alias "$KEYALIAS" -noprompt 2>/dev/null || \
		{ echo -e "${RED}✘ Keystore generation failed${NC}"; return 1; }
	
	echo -e "${GREEN}✔ Keystore created successfully${NC}"
}

sign_zip() {
	local ZIP="$1"
	local OUT="$2"
	
	[[ ! -f "$ZIP" ]] && { echo -e "${RED}✘ ZIP not found: $ZIP${NC}"; return 1; }
	
	generate_secure_keystore || return 1
	
	PASS=$(cat "$PASSFILE" 2>/dev/null || echo "defaultpass123")
	KEYALIAS=$(cat "$ALIASFILE" 2>/dev/null || echo "defaultkey")
	
	cp "$ZIP" "$OUT"
	
	echo -e "${CYAN}Signing ZIP...${NC}"
	jarsigner -keystore "$KEYSTORE" -storepass "$PASS" -keypass "$PASS" \
		-sigalg SHA256withRSA -digestalg SHA-256 \
		"$OUT" "$KEYALIAS" 2>&1 | grep -q "jar signed" && \
		echo -e "${GREEN}✔ ZIP signed successfully${NC}" || \
		{ echo -e "${RED}✘ Signing failed${NC}"; return 1; }
}

# ---- Generate flashable ----
generate_flashable() {
	echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo -e "${YELLOW} Generating flashable ZIP...${NC}"
	echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	
	# Find kernel Image
	KERNEL_IMAGE=""
	for img in "arch/arm64/boot/Image" "arch/arm64/boot/Image.gz" "arch/arm64/boot/Image.gz-dtb"; do
		if [ -f "$TARGET_OUT/$img" ]; then
			KERNEL_IMAGE="$TARGET_OUT/$img"
			echo -e "${GREEN}✔ Found kernel: $img${NC}"
			break
		fi
	done
	
	[ -z "$KERNEL_IMAGE" ] && { echo -e "${RED}✘ No kernel Image found in $TARGET_OUT/arch/arm64/boot/${NC}"; exit 1; }
	
	# Copy to AnyKernel3
	mkdir -p "$AK3_PATH"
	cp -f "$KERNEL_IMAGE" "$AK3_PATH/Image" && echo -e "${GREEN}✔ Kernel Image copied${NC}"
	
	# Copy DTB if exists
	[ -f "$TARGET_KERNEL_DTB" ] && cp -f "$TARGET_KERNEL_DTB" "$AK3_PATH/" && echo -e "${GREEN}✔ DTB copied${NC}"
	
	# Create ZIP
	cd "$AK3_PATH" || return 1
	
	FLASHABLE_ZIP="Neutrino-${branch}-${commit}-${CURRENT_TIME}.zip"
	SIGNED_ZIP="Neutrino-${branch}-${commit}-${CURRENT_TIME}-signed.zip"
	
	echo -e "${YELLOW}Creating ZIP: $FLASHABLE_ZIP${NC}"
	zip -q -r "$FLASHABLE_ZIP" * -x README.md changelog.txt defconfig build.log .git\* || \
		{ echo -e "${RED}✘ ZIP creation failed${NC}"; exit 1; }
	
	echo -e "${GREEN}✔ ZIP created: $(ls -lh "$FLASHABLE_ZIP" | awk '{print $5}')${NC}"
	
	# Sign ZIP
	sign_zip "$FLASHABLE_ZIP" "$SIGNED_ZIP" || echo -e "${YELLOW}⚠ Signing failed, using unsigned ZIP${NC}"
	
	# Final output location
	FINAL_ZIP="${SIGNED_ZIP:-$FLASHABLE_ZIP}"
	echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo -e "${GREEN}✔ Flashable kernel ready:${NC}"
	echo -e "${CYAN}   $AK3_PATH/$FINAL_ZIP${NC}"
	echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	
	cd "$KERNEL_DIR" || return 1
}

# ---- Display final info ----
display_kernel_version_info() {
	echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo -e "${GREEN}       BUILD COMPLETED SUCCESSFULLY${NC}"
	echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo -e "${PURPLE}USER          : $KBUILD_USER${NC}"
	echo -e "${PURPLE}HOST          : $KBUILD_HOST${NC}"
	echo -e "${PURPLE}BRANCH        : $branch${NC}"
	echo -e "${PURPLE}COMMIT        : $commit${NC}"
	echo -e "${PURPLE}LAST COMMIT   : $(git log -1 --pretty=format:%s 2>/dev/null || echo 'N/A')${NC}"
	echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ---- Main compilation function ----
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

# ---- Interactive menu (local builds only) ----
choose_action(){
	while true; do
		echo -e "\n${CYAN}Choose an action:${NC}"
		echo -e "${GREEN}1.👉 Install necessary packages${NC}"
		echo -e "${GREEN}2.👉 Start kernel compilation${NC}"
		echo -e "${GREEN}3.👉 Exit program${NC}"

		read -t 10 -p "$(echo -e ${YELLOW})Enter the action number (1/2/3): $(echo -e ${NC})" choice
		
		# Default to build if no input
		[ -z "$choice" ] && { 
			echo -e "${YELLOW}No input detected, starting build...${NC}"
			choice=2
		}

		case $choice in
			1)
				install_packages
				;;
			2)
				compile_kernel
				break
				;;
			3)
				echo -e "${YELLOW}Exiting...${NC}"
				exit 0
				;;
			*)
				echo -e "${RED}Invalid choice. Please enter 1, 2, or 3.${NC}"
				;;
		esac
	done
}

# ─────────────────────────────────────────────────────────────────────────────
#  MAIN EXECUTION
# ─────────────────────────────────────────────────────────────────────────────

if [ -n "$GITHUB_ACTIONS" ]; then
	# GitHub Actions: Non-interactive auto-build
	echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo -e "${GREEN}  Running in GitHub Actions (CI/CD)${NC}"
	echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	
	compile_kernel
else
	# Local build: Interactive menu
	choose_action
fi

echo -e "${GREEN}✔ All done!${NC}"
