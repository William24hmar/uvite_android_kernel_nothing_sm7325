#!/bin/bash
# ============================================================================
#  build.sh — Neutrino Kernel Builder — Nothing Phone 1 (SM7325 / lahaina)
#  Toolchain : EVA GCC (mvaisakh/gcc-build) — aarch64-elf + arm-eabi
#  Author    : Madara273 / William24hmar
# ============================================================================

# ── Colors ───────────────────────────────────────────────────────────────────
blue='\033[0;34m'
yellow='\033[0;33m'
white='\033[0m'
red='\033[0;31m'
green='\e[0;32m'
magenta='\033[1;35m'
lgreen='\e[92m'
cyan='\033[0;36m'
purple='\033[0;35m'
pink='\033[38;5;206m'
orange_yellow='\033[38;5;214m'
greenish_yellow='\033[38;5;190m'
reset='\e[0m'
NC='\033[0m'

colors=("$blue" "$yellow" "$red" "$green" "$magenta" "$lgreen" "$cyan" "$purple" "$pink")
random_color() { echo -e "${colors[$RANDOM % ${#colors[@]}]}"; }

ascii_art_logo() {
    echo -e "
$(random_color)*****************************NEUTRINO*****************************${NC}
$(random_color) ______ ______ _______ _______ _______ _______ ___ ___ ______ _______ ${NC}
$(random_color)|   __ \   __ \       |_     _|       |_     _|   |   |   __ \    ___|${NC}
$(random_color)|    __/      <   -   | |   | |   -   | |   |  \     /|    __/    ___|${NC}
$(random_color)|___|  |___|__|_______| |___| |_______| |___|   |___| |___|  |_______|${NC}
"
}

msg()    { echo -e "\e[1;32m$*\e[0m"; }
inform() { echo -e "\n${blue}▶  $*${NC}\n"; }
error()  { echo -e "\n${red}✘  $*${NC}\n"; exit 1; }

# ── OS info ───────────────────────────────────────────────────────────────────
[ -f /etc/os-release ] && . /etc/os-release || { OS=$(uname -s); VERSION_ID=$(uname -r); }
echo -e "${cyan}OS: $NAME $VERSION_ID${NC}"
echo -e "${lgreen}<< May the force be with you! >>${reset}"
export TZ=America/Sao_Paulo

# ============================================================================
#  CONFIGURATION — edit these to suit your device
# ============================================================================
KBUILD_USER="William24hmar"
KBUILD_HOST="GitHub-Actions"

DEVICENAME="Nothing Phone 1"
CODENAME="phone1"
DEFCONFIG="phone1_defconfig"

# ============================================================================
#  PATHS
# ============================================================================
KERNEL_DIR="$(pwd)"
TLDR="$KERNEL_DIR/toolchains"

# EVA GCC output dirs match the build-gcc.sh PREFIX convention:
#   build-gcc.sh -a arm64  →  gcc-arm64/   (target: aarch64-elf)
#   build-gcc.sh -a arm    →  gcc-arm/     (target: arm-eabi)
GCC64_DIR="$TLDR/gcc-arm64"
GCC32_DIR="$TLDR/gcc-arm"

OUT_DIR="$KERNEL_DIR/work"        # O=work  (same as compile.sh)
AK3_DIR="$KERNEL_DIR/AnyKernel3"
DTB_PATH="$OUT_DIR/arch/arm64/boot/dts"
DTBO_PATH="$OUT_DIR/arch/arm64/boot"

# ============================================================================
#  EVA GCC DOWNLOAD
#  Pre-built releases from: https://github.com/mvaisakh/gcc-build/releases
#  Built with build-gcc.sh; archives extract flat (no wrapper subdir) directly
#  to gcc-arm64/ and gcc-arm/ — same pattern as the build script PREFIX output.
# ============================================================================
EVA_RELEASE="22052025"
EVA_BASE_URL="https://github.com/mvaisakh/gcc-build/releases/download/${EVA_RELEASE}"

setup_toolchains() {
    inform "Setting up EVA GCC toolchains"
    mkdir -p "$TLDR"

    # ── aarch64-elf (arm64) ───────────────────────────────────────────────────
    if [ -f "$GCC64_DIR/bin/aarch64-elf-gcc" ]; then
        echo -e "${green}✔ EVA GCC arm64 already present${NC}"
    else
        local f64="eva-gcc-arm64-${EVA_RELEASE}.xz"
        echo -e "${yellow}Downloading EVA GCC arm64…${NC}"
        aria2c -x 16 -s 16 --console-log-level=warn \
            -d "$TLDR" -o "$f64" "${EVA_BASE_URL}/${f64}" \
            || error "EVA GCC arm64 download failed"

        echo -e "${yellow}Extracting EVA GCC arm64…${NC}"
        # Archive extracts flat — gcc-arm64/ appears directly in $TLDR
        tar xf "$TLDR/$f64" -C "$TLDR"
        rm -f "$TLDR/$f64"

        [ -f "$GCC64_DIR/bin/aarch64-elf-gcc" ] \
            || error "aarch64-elf-gcc not found in $GCC64_DIR/bin/ after extraction"
        echo -e "${green}✔ EVA GCC arm64 ready${NC}"
    fi

    # ── arm-eabi (arm32) ──────────────────────────────────────────────────────
    if [ -f "$GCC32_DIR/bin/arm-eabi-gcc" ]; then
        echo -e "${green}✔ EVA GCC arm32 already present${NC}"
    else
        local f32="eva-gcc-arm-${EVA_RELEASE}.xz"
        echo -e "${yellow}Downloading EVA GCC arm32…${NC}"
        aria2c -x 16 -s 16 --console-log-level=warn \
            -d "$TLDR" -o "$f32" "${EVA_BASE_URL}/${f32}" \
            || error "EVA GCC arm32 download failed"

        echo -e "${yellow}Extracting EVA GCC arm32…${NC}"
        tar xf "$TLDR/$f32" -C "$TLDR"
        rm -f "$TLDR/$f32"

        [ -f "$GCC32_DIR/bin/arm-eabi-gcc" ] \
            || error "arm-eabi-gcc not found in $GCC32_DIR/bin/ after extraction"
        echo -e "${green}✔ EVA GCC arm32 ready${NC}"
    fi

    # ── PATH + version strings ────────────────────────────────────────────────
    export PATH="$GCC64_DIR/bin:$GCC32_DIR/bin:$PATH"

    C_NAME=$("$GCC64_DIR/bin/aarch64-elf-gcc"  --version | head -n1)
    C_NAME_32=$("$GCC32_DIR/bin/arm-eabi-gcc"  --version | head -n1)

    echo -e "${green}Compiler    : $C_NAME${NC}"
    echo -e "${green}Compiler 32 : $C_NAME_32${NC}"
}

# ============================================================================
#  MAKE ARGUMENTS
#  Reference: compile.sh → compiler_setup() gcc branch (lines 491-516)
#
#  Key points from compile.sh:
#    CC='aarch64-elf-gcc'
#    CROSS_COMPILE="aarch64-elf-"
#    CC_COMPAT=$TLDR/gcc-arm/bin/arm-eabi-gcc
#    CROSS_COMPILE_COMPAT=$TLDR/gcc-arm/bin/arm-eabi-
#    GCC_LTO=1  GRAPHITE=1
#    HOSTLD=ld.lld           ← EVA GCC ships aarch64-elf-ld.lld symlink
#    PATH=$C_PATH/bin:$PATH  ← passed as make variable so sub-makes see it
# ============================================================================
build_make_args() {
    MAKE_ARGS=(
        "ARCH=arm64"
        "SUBARCH=arm64"

        # ── Cross-compiler: EVA GCC aarch64-elf ──────────────────────────────
        "CC=aarch64-elf-gcc"
        "CROSS_COMPILE=aarch64-elf-"

        # ── 32-bit compat: EVA GCC arm-eabi ──────────────────────────────────
        "CC_COMPAT=$GCC32_DIR/bin/arm-eabi-gcc"
        "CROSS_COMPILE_COMPAT=$GCC32_DIR/bin/arm-eabi-"

        # ── GCC optimisation flags ────────────────────────────────────────────
        "GCC_LTO=1"
        "GRAPHITE=1"

        # ── PATH override — EVA GCC bin dirs visible to all sub-makes ─────────
        # mirrors compile.sh line 514: "PATH=$C_PATH/bin:$PATH"
        "PATH=$GCC64_DIR/bin:$GCC32_DIR/bin:$PATH"

        # ── Host tools: native system gcc (builds fixdep, kconfig, scripts/) ──
        # MUST be system gcc — the cross-compiler has no host sysroot headers.
        "HOSTCC=gcc"
        "HOSTCXX=g++"
        "HOSTLD=ld"

        # ── HOSTCFLAGS: force C11 for host tool compilation ───────────────────
        # Ubuntu GCC 14 defaults to -std=gnu23; in C23 bool/false/true are
        # reserved keywords. Linux 5.4 headers define them as typedef/enum
        # values (legal in C11/C17), causing:
        #   stddef.h: error: cannot use keyword 'false' as enumeration constant
        #   types.h:  error: 'bool' cannot be defined via 'typedef'
        "HOSTCFLAGS=-std=gnu11"
        "HOSTCXXFLAGS=-std=gnu++11"

        # ── Output directory ──────────────────────────────────────────────────
        "O=$OUT_DIR"

        # ── DTC ───────────────────────────────────────────────────────────────
        "DTC_FLAGS=-q"

        # ── Suppress pre-existing vendor driver -Werror failures ─────────────
        # cnss2/bus.c:31   — enum* passed as u32* (incompatible-pointer-types)
        # nfc_i2c_drv.c:76 — size_t printed with %d (format=)
        # bus.c:112        — implicit fallthrough in switch
        # These are Qualcomm vendor driver bugs present in the kernel source.
        "KBUILD_CFLAGS+=-Wno-error=incompatible-pointer-types -Wno-error=format= -Wno-error=implicit-fallthrough"

        # ── Build identity ────────────────────────────────────────────────────
        "KBUILD_BUILD_USER=$KBUILD_USER"
        "KBUILD_BUILD_HOST=$KBUILD_HOST"

        # ── Threads ───────────────────────────────────────────────────────────
        "-j$(nproc --all)"
    )
}

# make wrapper — always injects MAKE_ARGS (mirrors muke() in compile.sh)
muke() { make "${MAKE_ARGS[@]}" "$@"; }

# ============================================================================
#  RESUKISU
# ============================================================================
setup_resukisu() {
    inform "Integrating ReSukiSU"
    echo -e "${cyan}────────────────────────────────────────${NC}"
    cd "$KERNEL_DIR"
    echo -e "${yellow}Running ReSukiSU setup script…${NC}"
    curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash \
        || error "ReSukiSU setup script failed"

    local defconfig_file="$KERNEL_DIR/arch/arm64/configs/$DEFCONFIG"

    _ensure_config() {
        local cfg="$1"
        if grep -q "^${cfg}$" "$defconfig_file" 2>/dev/null; then
            echo -e "${green}  ✔ $cfg already set${NC}"
        else
            echo "$cfg" >> "$defconfig_file"
            echo -e "${yellow}  + added $cfg${NC}"
        fi
    }

    echo -e "${cyan}Checking ReSukiSU configs in arch/arm64/configs/$DEFCONFIG…${NC}"
    _ensure_config "CONFIG_KSU=y"
    _ensure_config "CONFIG_KSU_SUSFS=y"
    _ensure_config "CONFIG_KSU_SUSFS_SUS_PATH=y"
    _ensure_config "CONFIG_KSU_SUSFS_SUS_MOUNT=y"
    _ensure_config "CONFIG_KSU_SUSFS_SUS_KSTAT=y"
    _ensure_config "CONFIG_KSU_SUSFS_SPOOF_UNAME=y"
    _ensure_config "CONFIG_KSU_SUSFS_ENABLE_LOG=y"
    _ensure_config "CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y"
    _ensure_config "CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y"
    _ensure_config "CONFIG_KSU_SUSFS_OPEN_REDIRECT=y"
    _ensure_config "CONFIG_KSU_SUSFS_SUS_SU=y"
    echo -e "${green}✔ All ReSukiSU defconfig checks complete${NC}"
}

# ============================================================================
#  ANYKERNEL3
# ============================================================================
clone_anykernel3() {
    inform "Setting up AnyKernel3"
    if [ ! -d "$AK3_DIR" ]; then
        echo -e "${yellow}Select branch to clone:${NC}"
        echo "  1.👉 master (osm0sis)"
        echo "  2.👉 Custom URL"
        local choice
        read -t 10 -rp "Choice [1]: " choice || true
        choice="${choice:-1}"
        case "$choice" in
            2)
                read -rp "Paste git clone URL: " custom_url
                git clone --depth=1 "$custom_url" "$AK3_DIR"
                ;;
            *)
                echo -e "${cyan}No input — selecting master.${NC}"
                git clone --depth=1 https://github.com/osm0sis/AnyKernel3 "$AK3_DIR"
                ;;
        esac
    else
        echo -e "${green}✔ AnyKernel3 already present${NC}"
        rm -f "$AK3_DIR"/Image "$AK3_DIR"/dtb "$AK3_DIR"/*.img "$AK3_DIR"/*.zip 2>/dev/null || true
    fi
}

# ============================================================================
#  CLEAN
# ============================================================================
clean_build() {
    inform "Cleaning source tree and build files"
    cd "$KERNEL_DIR"
    if [ -d "$OUT_DIR" ]; then
        muke -s clean mrproper 2>/dev/null || true
        rm -rf "$OUT_DIR"
    fi
    rm -rf error.log changelog/*.txt ./*.tar.gz 2>/dev/null || true
    echo -e "${green}Clean completed.${NC}"
}

# ============================================================================
#  DEFCONFIG
# ============================================================================
make_defconfig() {
    inform "Generating kernel configuration"
    mkdir -p "$OUT_DIR"
    muke "$DEFCONFIG" \
        || error "Failed to generate config from $DEFCONFIG"
}

# ============================================================================
#  BUILD INFO
# ============================================================================
display_build_info() {
    local kver
    kver=$(muke kernelrelease -s 2>/dev/null || echo "unknown")
    echo -e "
${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Build Triggered
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
  Device      : ${green}$DEVICENAME${NC}
  Defconfig   : ${green}$DEFCONFIG${NC}
  Kernel      : ${green}$kver${NC}
  Compiler    : ${green}$C_NAME${NC}
  Compiler 32 : ${green}$C_NAME_32${NC}
  Threads     : ${green}$(nproc --all)${NC}
  CI User     : ${green}$KBUILD_USER${NC}
  CI Host     : ${green}$KBUILD_HOST${NC}
  Build Date  : ${green}$(date '+%Y-%m-%d %H:%M')${NC}
${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
"
}

# ============================================================================
#  CHANGELOG
# ============================================================================
create_changelog() {
    mkdir -p "$KERNEL_DIR/changelog"
    git -C "$KERNEL_DIR" log -n 350 --pretty=format:"- %h %s (%an)" \
        > "$KERNEL_DIR/changelog/kernel-changelog.txt" 2>/dev/null || true
    echo -e "${purple}Changelog → changelog/kernel-changelog.txt${NC}"
}

# ============================================================================
#  COMPILE
# ============================================================================
build_kernel() {
    inform "Compiling kernel"

    # Color-coded real-time log output (from build__1_.sh build_kernel())
    declare -A LOG_COLORS
    LOG_COLORS["warning"]=$yellow
    LOG_COLORS["error"]=$red

    BUILD_START=$(date +"%s")

    muke 2>&1 | while IFS= read -r line; do
        local color=$green
        [[ $line == *"warning"* ]] && color=$yellow
        [[ $line == *"error"*   ]] && color=$red
        echo -e "${color}${line}${NC}"
    done

    local pipe_status="${PIPESTATUS[0]}"
    BUILD_END=$(date +"%s")
    DIFF=$(( BUILD_END - BUILD_START ))

    [ "$pipe_status" -eq 0 ] \
        || error "Compilation failed after $((DIFF/60))m $((DIFF%60))s — check output above"

    echo -e "${green}✔ Finished in $((DIFF/60))m $((DIFF%60))s${NC}"
}

# ============================================================================
#  DTB
# ============================================================================
link_all_dtb_files() {
    inform "Linking DTB files"
    if find "$DTB_PATH" -name '*.dtb' -print -quit 2>/dev/null | grep -q .; then
        find "$DTB_PATH" -name '*.dtb' -exec cat {} + > "$AK3_DIR/dtb"
        echo -e "${green}✔ DTB written to $AK3_DIR/dtb${NC}"
    else
        echo -e "${yellow}No DTB files found — skipping${NC}"
    fi
}

# ============================================================================
#  FLASHABLE ZIP
# ============================================================================
generate_flashable() {
    inform "Generating flashable ZIP"

    local image="$OUT_DIR/arch/arm64/boot/Image"
    [ -f "$image" ] || error "Kernel image not found at $image"
    [ -d "$AK3_DIR" ]  || error "AnyKernel3 not found at $AK3_DIR"

    cp -f "$image" "$AK3_DIR/Image"

    # Copy DTBO images if present
    for img in "$DTBO_PATH"/*.img; do
        [ -f "$img" ] && cp -f "$img" "$AK3_DIR/"
    done

    local last_hash last_commit build_time zip_name
    last_hash=$(git -C "$KERNEL_DIR"   rev-parse --short HEAD 2>/dev/null || echo "unknown")
    last_commit=$(git -C "$KERNEL_DIR" show -s --format="%s"  2>/dev/null || echo "unknown")
    build_time=$(date +"%d%m%Y-%H%M")
    zip_name="Neutrino-${CODENAME}-${build_time}.zip"

    cd "$AK3_DIR"
    zip -r9 "$zip_name" ./* -x '*.git*' \
        || error "Failed to create flashable zip"
    cd "$KERNEL_DIR"

    mkdir -p "$KERNEL_DIR/out"
    cp "$AK3_DIR/$zip_name" "$KERNEL_DIR/out/"

    local sha md5
    sha=$(sha1sum "$AK3_DIR/$zip_name" | cut -d' ' -f1)
    md5=$(md5sum  "$AK3_DIR/$zip_name" | cut -d' ' -f1)

    echo -e "
${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Build Completed 🎉
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
  ZIP          : ${greenish_yellow}$zip_name${NC}
  Location     : ${green}$KERNEL_DIR/out/${NC}
  Duration     : ${green}$((DIFF/60))m $((DIFF%60))s${NC}
  MD5          : ${green}$md5${NC}
  SHA1         : ${green}$sha${NC}
  Last commit  : ${green}$last_commit${NC}
  Hash         : ${green}$last_hash${NC}
${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
"
}

# ============================================================================
#  DISPLAY KERNEL VERSION INFO  (from build__1_.sh display_kernel_version_info)
# ============================================================================
display_kernel_version_info() {
    echo -e "${green}════════════════ END BUILD ════════════════${NC}"
    echo -e "VERSION    : $(grep -E '^VERSION ='    "$KERNEL_DIR/Makefile" | awk '{print $3}')"
    echo -e "PATCHLEVEL : $(grep -E '^PATCHLEVEL =' "$KERNEL_DIR/Makefile" | awk '{print $3}')"
    echo -e "SUBLEVEL   : $(grep -E '^SUBLEVEL ='   "$KERNEL_DIR/Makefile" | awk '{print $3}')"
    echo -e "Last commit: $(git -C "$KERNEL_DIR" log -1 --pretty=format:%s 2>/dev/null)"
    echo -e "Hash       : $(git -C "$KERNEL_DIR" log -1 --pretty=format:%H 2>/dev/null)"
    echo -e "${green}═══════════════════════════════════════════${NC}"
}

# ============================================================================
#  MAIN
# ============================================================================
main() {
    ascii_art_logo
    setup_toolchains    # download EVA GCC, export PATH
    build_make_args     # assemble MAKE_ARGS array
    setup_resukisu      # ReSukiSU + SUSFS defconfig injection
    clone_anykernel3    # AnyKernel3
    clean_build         # mrproper + wipe work/
    make_defconfig      # phone1_defconfig → work/.config
    create_changelog
    display_build_info
    build_kernel        # main compile
    link_all_dtb_files
    generate_flashable  # zip → out/
    display_kernel_version_info
}

main "$@"
