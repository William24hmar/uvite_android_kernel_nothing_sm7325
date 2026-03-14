#!/bin/bash
#
#   Neutrino Kernel Builder — Nothing Phone 1 (sm7325 / lahaina)
#   Toolchain: Snapdragon Clang 19 (sdclang-19)
#
#   Usage (CI / manual):
#       ./build.sh
#       ./build.sh --clean
#       ./build.sh --log
#       ./build.sh --regen
#
#   sdclang19.tgz extracts FLAT — no wrapper subdirectory.
#   After extraction the layout under toolchains/sdclang/ is:
#
#       toolchains/sdclang/
#       ├── bin/          ← clang, clang++, arm-ar, arm-nm, arm-link …
#       ├── lib/          ← runtime shared libraries
#       ├── libexec/
#       ├── share/
#       ├── tools/bin/
#       ├── aarch64-linux-gnu/
#       ├── armv7-linux-gnueabi/
#       └── …
#

############################################################################
#                              COLORS
############################################################################

blue='\033[0;34m'
yellow='\033[0;33m'
white='\033[0m'
red='\033[0;31m'
green='\e[0;32m'
cyan='\033[0;36m'
purple='\033[0;35m'
orange_yellow='\033[38;5;214m'
greenish_yellow='\033[38;5;190m'
reset='\e[0m'
R='\033[1;31m'
G='\033[1;32m'
B='\033[1;34m'
W='\033[1;37m'

############################################################################
#                            ASCII ART LOGO
############################################################################

ascii_art_logo() {
  echo -e "
${cyan}*******************************Phone1*******************************${reset}
${cyan} ______ ______ _______ _______ _______ _______ ___ ___ ______ _______ ${reset}
${cyan}|   __ \   __ \       |_     _|       |_     _|   |   |   __ \    ___|${reset}
${cyan}|    __/      <   -   | |   | |   -   | |   |  \     /|    __/    ___|${reset}
${cyan}|___|  |___|__|_______| |___| |_______| |___|   |___| |___|  |_______|${reset}
"
}

############################################################################
#                             HELPER FUNCTIONS
############################################################################

msg()     { echo -e "\e[1;32m$*\e[0m"; }
error()   { echo -e "\n$R error: $W $*\n"; exit 1; }
success() { echo -e "\n$G success: $W $*\n"; exit 0; }

inform() {
    if [[ $SILENCE != 1 || $* =~ "--force" ]]; then
        echo -e "\n$B info: $W" "$@" "$G" | sed 's/--force//'
        echo -e ""
    fi
}

countdown() {
    for ((i = $1; i > 0; i--)); do echo "Countdown: $i"; sleep 1; done
}

muke() { make "$@" "${MAKE_ARGS[@]}"; }

usage() {
    inform " ./build.sh [options]
        (no args)    Build for Nothing Phone 1 (lahaina).
        --clean      Clean build directory before building.
        --regen      Regenerates defconfig.
        --obj=X      Builds specified object X.
        --dtbs       Builds dtbs, dtbo & dtbo.img.
        --dtb_zip    Builds flashable zip with dtbs.
        --log        Save build log to log.txt.
        --silence    Silence Kbuild output."
    exit 0
}

############################################################################
#                        HARDCODED DEVICE CONFIG
#         Nothing Phone 1 — Snapdragon 778G (sm7325 / lahaina)
############################################################################

DEVICENAME="Nothing Phone 1"
CODENAME="lahaina"
DEFCONFIG="phone1_defconfig"

############################################################################
#                          USER / HOST DETAILS
############################################################################

# Allow CI to override via env, fall back to defaults
KBUILD_USER="${KBUILD_BUILD_USER:-Willay}"
KBUILD_HOST="${KBUILD_BUILD_HOST:-GNU/Linux}"

############################################################################
#                           DIRECTORY PATHS
############################################################################

KERNEL_DIR=$(pwd)
TLDR="$KERNEL_DIR/toolchains"
AK3_DIR="$KERNEL_DIR/AnyKernel3"
AKVDR="$AK3_DIR/modules/vendor/lib/modules"
AKVRD="$AK3_DIR/vendor_ramdisk/lib/modules"
DTB_PATH="$KERNEL_DIR/work/arch/arm64/boot/dts"
DTBO_PATH="$KERNEL_DIR/work/arch/arm64/boot"

############################################################################
#                      SNAPDRAGON CLANG 19 SETUP
#
#   The tgz from khuza08/snapdragon-clang extracts FLAT (same layout as
#   ZyCromerZ/SDClang which is the upstream reference):
#
#       toolchains/sdclang/bin/clang
#       toolchains/sdclang/bin/arm-ar
#       toolchains/sdclang/bin/arm-nm
#       toolchains/sdclang/bin/arm-elfcopy   (OBJCOPY)
#       toolchains/sdclang/bin/llvm-objdump  (OBJDUMP)
#       toolchains/sdclang/bin/arm-readelf
#       toolchains/sdclang/bin/arm-strip
#       toolchains/sdclang/bin/arm-link      (linker / ld.qcld)
#       toolchains/sdclang/lib/              (runtime libs)
############################################################################

SDCLANG_DIR="$TLDR/sdclang"
SDCLANG_BIN="$SDCLANG_DIR/bin"
SDCLANG_LIB="$SDCLANG_DIR/lib"
SDCLANG_URL="https://github.com/khuza08/snapdragon-clang/releases/download/sdclang-19.0.0-release/sdclang19.tgz"

setup_toolchain() {
    msg "|| Setting up Snapdragon Clang 19 ||"

    mkdir -p "$TLDR"

    if [ ! -f "$SDCLANG_BIN/clang" ]; then
        echo -e "$blue << Downloading Snapdragon Clang 19... >> $white"
        mkdir -p "$SDCLANG_DIR"

        if command -v aria2c &>/dev/null; then
            aria2c -x 16 -s 16 --dir="$TLDR" --out="sdclang19.tgz" "$SDCLANG_URL" \
                || error "aria2c download failed"
        else
            wget --progress=bar:force -O "$TLDR/sdclang19.tgz" "$SDCLANG_URL" \
                || error "wget download failed"
        fi

        echo -e "$blue << Extracting... >> $white"
        # Extracts flat — bin/ lib/ etc. go directly into $SDCLANG_DIR
        tar xf "$TLDR/sdclang19.tgz" -C "$SDCLANG_DIR" \
            || error "Extraction failed"
        rm -f "$TLDR/sdclang19.tgz"
        echo -e "$green << Snapdragon Clang 19 ready! >> $white"
    else
        echo -e "$yellow << Snapdragon Clang 19 already present, skipping >> $white"
    fi

    # Export PATH and lib path
    export PATH="$SDCLANG_BIN:$PATH"
    export LD_LIBRARY_PATH="$SDCLANG_LIB:${LD_LIBRARY_PATH:-}"

    # Kernel architecture flags
    export ARCH=arm64
    export SUBARCH=ARM64
    export CROSS_COMPILE=aarch64-linux-gnu-
    export CROSS_COMPILE_ARM32=arm-linux-gnueabi-

    # Sanity check
    if ! command -v clang &>/dev/null; then
        error "clang not found in $SDCLANG_BIN\nCheck archive extraction — expected flat layout with bin/ at root."
    fi

    C_NAME=$(clang --version | head -n 1)

    # Build make arguments — pure sdclang, zero GCC
    MAKE_ARGS=(
        "O=work"
        "ARCH=arm64"
        "SUBARCH=ARM64"
        "CC=clang"
        "HOSTCC=clang"
        "HOSTCXX=clang++"
        "CROSS_COMPILE=aarch64-linux-gnu-"
        "CROSS_COMPILE_ARM32=arm-linux-gnueabi-"
        "LLVM=1"
        "LLVM_IAS=1"
        "AR=arm-ar"
        "NM=arm-nm"
        "OBJCOPY=arm-elfcopy"
        "OBJDUMP=llvm-objdump"
        "READELF=arm-readelf"
        "STRIP=arm-strip"
        "HOSTLD=arm-link"
        "LD_LIBRARY_PATH=$SDCLANG_LIB"
        "PATH=$SDCLANG_BIN:$PATH"
        "DTC_FLAGS+=-q"
        "KBUILD_BUILD_USER=$KBUILD_USER"
        "KBUILD_BUILD_HOST=$KBUILD_HOST"
    )

    # Append build.config.common if present
    if [[ -f build.config.common ]]; then
        MAKE_ARGS+=("$(head -1 build.config.common)" "$(head -2 build.config.common | tail -1)")
    fi

    echo -e "$green << Compiler  : $C_NAME >> $white"
    echo -e "$green << Toolchain : $SDCLANG_BIN >> $white"
}

############################################################################
#                          ENVIRONMENT SETUP
############################################################################

setup_environment() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release; OS=$NAME; VER=$VERSION_ID
    else
        OS=$(uname -s); VER=$(uname -r)
    fi
    echo -e "$cyan OS: $OS $VER $white"

    AKHILNARANG="environment"
    if [[ ! -d "$AKHILNARANG" ]]; then
        if [[ "$OS" == *"SUSE"* ]] || [[ "$OS" == *"Regata"* ]]; then
            git clone --depth=1 https://github.com/TogoFire/scripts -b akh "$AKHILNARANG"
            cd "$AKHILNARANG" && bash setup/opensuse.sh && cd ..
        elif [[ "$OS" == *"Fedora"* ]] || [[ "$OS" == *"Nobara"* ]] || [[ "$OS" == *"Ultramarine"* ]] || [[ "$OS" == *"Rocky"* ]]; then
            git clone --depth=1 https://github.com/TogoFire/scripts -b akh "$AKHILNARANG"
            cd "$AKHILNARANG" && bash setup/fedora.sh && cd ..
        elif [[ "$OS" == *"Arch"* ]] || [[ "$OS" == *"Manjaro"* ]] || [[ "$OS" == *"Endeavour"* ]] || [[ "$OS" == *"Garuda"* ]]; then
            git clone --depth=1 https://github.com/akhilnarang/scripts "$AKHILNARANG"
            cd "$AKHILNARANG" && bash setup/arch-manjaro.sh && cd ..
        else
            # Ubuntu / Debian / CI runners — deps already handled by workflow
            echo -e "$cyan << CI/Ubuntu: skipping environment clone >> $white"
        fi
    else
        echo -e "$yellow environment already set up, skipping $white"
    fi
}

############################################################################
#                             ANYKERNEL3 CLONE
############################################################################

setup_anykernel() {
    msg "|| Cloning AnyKernel3 ||"
    if [[ ! -d "AnyKernel3" ]]; then
        echo -e "$yellow AnyKernel3 not found, downloading... $white"
        git clone --depth=1 https://github.com/William24hmar/AnyKernel3.git -b master AnyKernel3
    else
        echo -e "$yellow AnyKernel3 found, skipping $white"
    fi

    cd AnyKernel3
    CURRENT_VERSION=$(git branch -a | grep '*' | awk '{print $2}' | sed 's/^[[:alpha:]]\///')
    ANYK_VERSION="${CURRENT_VERSION:-NeutrinoKernel}"
    echo -e "$greenish_yellow AnyKernel version: $ANYK_VERSION $white"
    cd ..
}

############################################################################
#                              CLEAN-UP
############################################################################

cleanup() {
    echo -e "${orange_yellow} Clean-up... ${white}"
    rm -rf out/* work/* error.log changelog/* ./*.tar.gz

    if [[ -d "AnyKernel3" ]]; then
        pushd AnyKernel3 >/dev/null 2>&1
        rm -f Image dtb *.img *.zip
        popd >/dev/null 2>&1
    fi
}

############################################################################
#                            CHANGELOG
############################################################################

generate_changelog() {
    CHANGELOG_DIR="changelog"
    CHANGELOG_FILE="$CHANGELOG_DIR/kernel-changelog.txt"
    mkdir -p "$CHANGELOG_DIR"
    git log -n 350 --pretty=format:"%h - %s (%an)" > "$CHANGELOG_FILE"
    sed -i -e "s/^/- /" "$CHANGELOG_FILE"
    echo -e "${purple} Changelog saved to $CHANGELOG_FILE ${white}"
}

############################################################################
#                            CONFIG GENERATOR
############################################################################

config_generator() {
    # Nothing Phone 1 uses a simple top-level defconfig (not vendor/suffix style)
    if [[ ! -f "arch/arm64/configs/$DEFCONFIG" ]]; then
        error "Defconfig not found: arch/arm64/configs/$DEFCONFIG"
    fi

    inform "Generating .config from $DEFCONFIG"
    muke "$DEFCONFIG" savedefconfig

    if [[ $TEST == "1" ]]; then
        ./scripts/config --file work/.config -d CONFIG_LTO_CLANG
        ./scripts/config --file work/.config -d CONFIG_HEADERS_INSTALL
    fi
}

config_regenerator() {
    config_generator
    inform "Saving regenerated defconfig"
    cp work/defconfig "arch/arm64/configs/$DEFCONFIG"
    success "Defconfig regenerated"
}

############################################################################
#                             OBJ / DTB BUILDERS
############################################################################

obj_builder() {
    [[ -z $OBJ ]] && error "obj not defined"
    config_generator
    inform "Building $OBJ"
    if [[ $OBJ =~ "defconfig" ]]; then
        muke "$OBJ"
    else
        muke -j"$(nproc --all)" INSTALL_HDR_PATH="headers" "$OBJ"
    fi
    [[ $DTB_ZIP != "1" ]] && exit 0
}

dtb_zip() {
    obj_builder
    source work/.config
    [[ ! -d $AK3_DIR ]] && error "AnyKernel not present, cannot zip"
    mkdir -p "$KERNEL_DIR/out"
    mv -f "$DTBO_PATH"/*.img "$AK3_DIR"
    find "$DTB_PATH"/vendor/*/* -name '*.dtb' -exec cat {} + > "$AK3_DIR/dtb"
    cd "$AK3_DIR" || exit
    make zip VERSION="$(echo "$CONFIG_LOCALVERSION" | cut -c 8-)-dtbs-only"
    cp ./*-signed.zip "$KERNEL_DIR/out"
    make clean
    cd "$KERNEL_DIR" || exit
    success "dtbs zip built"
}

############################################################################
#                             KERNEL BUILDER
############################################################################

kernel_builder() {
    if [[ $BUILD == "clean" ]]; then
        inform "Cleaning work directory..."
        muke -s clean mrproper distclean
    fi

    config_generator

    BUILD_START=$(date +"%s")
    source work/.config
    MOD_NAME="$(muke kernelrelease -s)"
    KERNEL_VERSION=$(echo "$MOD_NAME" | cut -c -7)

    inform --force "
    *************Build Triggered*************

    CI         : $KBUILD_HOST
    Core count : $(nproc)
    Device     : $DEVICENAME
    Codename   : $CODENAME
    Defconfig  : $DEFCONFIG
    Compiler   : $C_NAME
    Kernel Name: $MOD_NAME
    Linux Ver  : $KERNEL_VERSION
    Build Date : $(date +"%Y-%m-%d %H:%M")

    *****************************************
    "

    if [[ $LOG != 1 ]]; then
        muke -j"$(nproc --all)"
    else
        muke -j"$(nproc --all)" 2>&1 | tee log.txt
    fi

    if [[ $CONFIG_MODULES == "y" ]]; then
        muke -j"$(nproc --all)" \
            modules_install \
            INSTALL_MOD_STRIP=1 \
            INSTALL_MOD_PATH="modules"
    fi

    BUILD_END=$(date +"%s")
    DIFF=$(("$BUILD_END" - "$BUILD_START"))

    zipper
}

############################################################################
#                                 ZIPPER
############################################################################

zipper() {
    TARGET="arch/arm64/boot/Image"

    [[ ! -f $KERNEL_DIR/work/$TARGET ]] && error "Kernel image not found"
    [[ ! -d $AK3_DIR ]]                 && error "AnyKernel not present, cannot zip"
    mkdir -p "$KERNEL_DIR/out"

    cd "$KERNEL_DIR" || exit
    mv -f "$KERNEL_DIR/work/$TARGET" "$DTBO_PATH"/*.img "$AK3_DIR" 2>/dev/null || true
    find "$DTB_PATH"/vendor/*/* -name '*.dtb' -exec cat {} + > "$AK3_DIR/dtb" 2>/dev/null || true

    if [[ $CONFIG_MODULES == "y" ]]; then
        MOD_PATH="work/modules/lib/modules/$MOD_NAME"
        sed -i 's/\(kernel\/[^: ]*\/\)\([^: ]*\.ko\)/\/vendor\/lib\/modules\/\2/g' "$MOD_PATH/modules.dep"
        sed -i 's/.*\///g' "$MOD_PATH/modules.order"
        if [[ $DRM_VENDOR_MODULE == "1" ]]; then
            DRM_AS_MODULE=1
            if [ ! -d "$AK3_DIR/vendor_ramdisk/lib/modules/" ]; then
                VENDOR_RAMDISK_CREATE=1
                mkdir -p "$AK3_DIR/vendor_ramdisk/lib/modules/"
            fi
            mv "$(find "$MOD_PATH" -name 'msm_drm.ko')" "$AKVRD"
            grep drm "$MOD_PATH/modules.alias"  > "$AKVRD/modules.alias"
            grep drm "$MOD_PATH/modules.dep" | sed 's/^........//' > "$AKVRD/modules.dep"
            grep drm "$MOD_PATH/modules.softdep" > "$AKVRD/modules.softdep"
            grep drm "$MOD_PATH/modules.order"  > "$AKVRD/modules.load"
            sed -i s/split_boot/dump_boot/g "$AK3_DIR/anykernel.sh"
        fi
        cp $(find "$MOD_PATH" -name '*.ko') "$AKVDR/"
        cp "$MOD_PATH/modules."{alias,dep,softdep} "$AKVDR/"
        cp "$MOD_PATH/modules.order" "$AKVDR/modules.load"
    fi

    LAST_COMMIT=$(git show -s --format=%s)
    LAST_HASH=$(git rev-parse --short HEAD)

    cd "$AK3_DIR" || exit

    BUILD_TIME=$(date +"%d%m%Y-%H%M")
    ZIPSIGNER_JAR=zipsigner-3.0.jar

    zip -r9 "${ANYK_VERSION}-${BUILD_TIME}.zip" ./* \
        --exclude="*.zip"

    if [[ -f $ZIPSIGNER_JAR ]]; then
        java -jar "$ZIPSIGNER_JAR" \
            "${ANYK_VERSION}-${BUILD_TIME}.zip" \
            "${ANYK_VERSION}-${BUILD_TIME}-signed.zip"
        FINAL_ZIP="${ANYK_VERSION}-${BUILD_TIME}-signed.zip"
    else
        # No zipsigner present (common in CI) — use unsigned zip
        mv "${ANYK_VERSION}-${BUILD_TIME}.zip" "${ANYK_VERSION}-${BUILD_TIME}-signed.zip"
        FINAL_ZIP="${ANYK_VERSION}-${BUILD_TIME}-signed.zip"
        echo -e "$yellow << zipsigner.jar not found — skipping signing >> $white"
    fi

    echo -e "  ${green}Zip built: $FINAL_ZIP ${white}"

    # Copy to kernel/out for CI artifact collection
    cp "$FINAL_ZIP" "$KERNEL_DIR/out/"

    if [ "$DRM_AS_MODULE" = "1" ]; then
        [[ "$VENDOR_RAMDISK_CREATE" = "1" ]] && rm -rf "$AK3_DIR/vendor_ramdisk/"
        sed -i s/'dump_boot; # skip unpack'/'split_boot; # skip unpack'/g "$AK3_DIR/anykernel.sh"
    fi

    SHA=$(shasum "$FINAL_ZIP" | cut -f1 -d' ')
    MD5=$(md5sum  "$FINAL_ZIP" | cut -f1 -d' ')
    echo -e "  MD5  : $MD5"
    echo -e "  SHA1 : $SHA"

    inform --force "
    ***************Phone1-Kernel**************

    CI         : $KBUILD_HOST
    Core count : $(nproc)
    Device     : $DEVICENAME
    Codename   : $CODENAME
    Compiler   : $C_NAME
    Kernel Name: $MOD_NAME
    Linux Ver  : $KERNEL_VERSION
    Build Date : $(date +"%Y-%m-%d %H:%M")

    ***********Last Commit Details***********

    Last commit (name): $LAST_COMMIT
    Last commit (hash): $LAST_HASH

    *****************************************
    "

    cd "$KERNEL_DIR" || exit
    success "Build completed in $((DIFF / 60))m $((DIFF % 60))s"
}

############################################################################
#                            MAIN
############################################################################

export TZ=America/Sao_Paulo

# Parse flags
[[ $* =~ "--log" ]]     && LOG=1
[[ $* =~ "--silence" ]] && MAKE_ARGS+=("-s") && SILENCE=1
[[ $* =~ "--help" ]]    && usage

# Run setup (always)
setup_environment
setup_toolchain
cleanup
setup_anykernel
generate_changelog
ascii_art_logo

# Parse arguments — default to building if no special arg given
for arg in "$@"; do
    case "${arg}" in
        "--clean")      BUILD='clean' ;;
        "--test")       TEST='1' ;;
        "--dtb_zip")    DTB_ZIP=1; OBJ=dtbs; dtb_zip ;;
        "--dtbs")       OBJ=dtbs; dtb_zip ;;
        "--obj="*)      OBJ=${arg#*=}; obj_builder ;;
        "--regen")      config_regenerator ;;
        "--log"|"--silence"|"--help") ;;
        *)              echo -e "$yellow Unknown arg: $arg — ignoring $white" ;;
    esac
done

# Always fall through to building the kernel
kernel_builder
############################################################################
