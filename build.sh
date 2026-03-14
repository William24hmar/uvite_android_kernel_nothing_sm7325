#!/bin/bash
#
#   Build kernel with Snapdragon Clang 19 (sdclang-19)
#
#   Usage:
#       ./build.sh --device=lahaina
#       ./build.sh --device=lahaina --clean
#       ./build.sh --device=lahaina --log
#       ./build.sh --regen
#
#   Toolchain layout (after extracting sdclang19.tgz):
#       toolchains/sdclang/
#       └── linux-x86_64/
#           ├── bin/
#           │   ├── clang          <- compiler driver (also doubles as assembler)
#           │   ├── clang++
#           │   ├── arm-link       <- linker (a.k.a ld.qcld)
#           │   ├── arm-ar         <- archiver
#           │   ├── arm-nm         <- object file symbols
#           │   ├── arm-elfcopy    <- object file copier
#           │   ├── llvm-objdump   <- object file viewer
#           │   ├── arm-ranlib     <- archive indexer
#           │   ├── arm-size       <- object file size
#           │   ├── arm-strings    <- object file strings
#           │   ├── arm-strip      <- object file stripper
#           │   ├── arm-c++filt    <- C++ filter
#           │   ├── arm-addr2line  <- address converter
#           │   └── arm-readelf    <- ELF file viewer
#           └── lib/               <- runtime shared libraries
#

############################################################################
#                              COLORS
############################################################################

blue='\033[0;34m'
yellow='\033[0;33m'
white='\033[0m'
red='\033[0;31m'
green='\e[0;32m'
magenta='\033[1;35m'
lgreen='\e[92m'
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

msg() {
    echo -e "\e[1;32m$*\e[0m"
}

error() {
    echo -e ""
    echo -e "$R error: $W" "$@"
    echo -e ""
    exit 1
}

success() {
    echo -e ""
    echo -e "$G success: $W" "$@"
    echo -e ""
    exit 0
}

inform() {
    if [[ $SILENCE != 1 || $* =~ "--force" ]]; then
        echo -e ""
        echo -e "$B info: $W" "$@" "$G" | sed 's/--force//'
        echo -e ""
    fi
}

function countdown() {
    for ((i = $1; i > 0; i--)); do
        echo "Countdown: $i"
        sleep 1
    done
}

muke() {
    make "$@" "${MAKE_ARGS[@]}"
}

usage() {
    inform " ./build.sh <arg>
        --device     Sets the device for kernel build (e.g. lahaina).
        --clean      Clean build directory before building.
        --regen      Regenerates defconfig.
        --obj        Builds specified objects.
        --dtbs       Builds dtbs, dtbo & dtbo.img.
        --dtb_zip    Builds flashable zip with dtbs.
        --log        Save build log to log.txt.
        --silence    Silence shell output of Kbuild."
    exit 2
}

############################################################################
#                          USER / HOST DETAILS
############################################################################

KBUILD_USER="Willay"
KBUILD_HOST="GNU/Linux-2025.2"

############################################################################
#                           DIRECTORY PATHS
############################################################################

KERNEL_DIR=$(pwd)
TLDR="$(pwd)/toolchains"
AK3_DIR="$(pwd)/AnyKernel3"
AKVDR="$AK3_DIR/modules/vendor/lib/modules"
AKVRD="$AK3_DIR/vendor_ramdisk/lib/modules"
DTB_PATH="$KERNEL_DIR/work/arch/arm64/boot/dts"
DTBO_PATH="$KERNEL_DIR/work/arch/arm64/boot"

############################################################################
#                         SNAPDRAGON CLANG 19 SETUP
#
#   sdclang19.tgz extracts a top-level "linux-x86_64/" directory.
#   We place it under toolchains/sdclang/ so the final layout is:
#
#       toolchains/sdclang/linux-x86_64/bin/clang
#       toolchains/sdclang/linux-x86_64/bin/arm-ar
#       toolchains/sdclang/linux-x86_64/bin/arm-nm
#       toolchains/sdclang/linux-x86_64/bin/arm-strip
#       toolchains/sdclang/linux-x86_64/bin/arm-elfcopy
#       toolchains/sdclang/linux-x86_64/bin/arm-link     (ld.qcld)
#       toolchains/sdclang/linux-x86_64/bin/llvm-objdump
#       toolchains/sdclang/linux-x86_64/bin/arm-readelf
#       toolchains/sdclang/linux-x86_64/lib/             (runtime libs)
#
#   Binary names are per the Qualcomm Snapdragon LLVM ARM Utilities guide
#   (80-VB419-103 Rev. A) Table 2-1.
############################################################################

SDCLANG_DIR="$TLDR/sdclang"
SDCLANG_BIN="$SDCLANG_DIR/linux-x86_64/bin"
SDCLANG_LIB="$SDCLANG_DIR/linux-x86_64/lib"
SDCLANG_URL="https://github.com/khuza08/snapdragon-clang/releases/download/sdclang-19.0.0-release/sdclang19.tgz"

setup_toolchain() {
    msg "|| Setting up Snapdragon Clang 19 Toolchain ||"

    # Create toolchains dir if needed
    if [ ! -d "$TLDR" ]; then
        mkdir -p "$TLDR"
        echo -e "$green Directory '$TLDR' created. $white"
    fi

    # Download & extract sdclang if not already present
    if [ ! -d "$SDCLANG_BIN" ] || [ ! -f "$SDCLANG_BIN/clang" ]; then
        echo -e "$blue << Snapdragon Clang 19 not found, downloading... >> $white"
        mkdir -p "$SDCLANG_DIR"

        # Prefer aria2c for fast multi-connection download, fallback to wget
        if command -v aria2c &>/dev/null; then
            aria2c -x 16 -s 16 --dir="$TLDR" --out="sdclang19.tgz" "$SDCLANG_URL" \
                || error "Download failed with aria2c"
        else
            wget --progress=bar:force -O "$TLDR/sdclang19.tgz" "$SDCLANG_URL" \
                || error "Download failed with wget"
        fi

        echo -e "$blue << Extracting Snapdragon Clang 19... >> $white"
        # tgz extracts to linux-x86_64/ — extract directly into $SDCLANG_DIR
        tar xf "$TLDR/sdclang19.tgz" -C "$SDCLANG_DIR" \
            || error "Extraction failed. Check the archive."
        rm -f "$TLDR/sdclang19.tgz"

        echo -e "$green << Snapdragon Clang 19 ready! >> $white"
    else
        echo -e "$yellow << Snapdragon Clang 19 found, skipping download >> $white"
    fi

    # Export PATH to sdclang bin directory (as per sdclang README instructions)
    export PATH="$SDCLANG_BIN:$PATH"

    # Export runtime library path so sdclang binaries can find their shared libs
    export LD_LIBRARY_PATH="$SDCLANG_LIB:$LD_LIBRARY_PATH"

    # Required kernel build flags
    export ARCH=arm64
    export SUBARCH=ARM64
    export CROSS_COMPILE=aarch64-linux-gnu-
    export CROSS_COMPILE_ARM32=arm-linux-gnueabi-

    # Verify clang is accessible
    if ! command -v clang &>/dev/null; then
        error "clang not found at $SDCLANG_BIN\n  Expected layout: $SDCLANG_DIR/linux-x86_64/bin/clang\n  Check the extracted archive structure."
    fi

    # Get compiler version string for build info display
    C_NAME=$(clang --version | head -n 1)
    C_NAME_32="$C_NAME"

    # ------------------------------------------------------------------
    # MAKE_ARGS — all sdclang-specific tool mappings
    #
    # Per Qualcomm LLVM ARM Utilities guide (Table 2-1), sdclang provides
    # its own arm-prefixed binutils replacing the GNU equivalents:
    #
    #   CC=clang           → Snapdragon clang compiler driver
    #   LLVM=1             → Tell the kernel build system to use LLVM tools
    #   LLVM_IAS=1         → Use clang's integrated assembler (not GNU as)
    #   AR=arm-ar          → Snapdragon archiver (instead of GNU ar)
    #   NM=arm-nm          → Snapdragon symbol lister (instead of GNU nm)
    #   OBJCOPY=arm-elfcopy → Snapdragon object copier (instead of objcopy)
    #   OBJDUMP=llvm-objdump → Snapdragon object viewer (instead of objdump)
    #   READELF=arm-readelf → Snapdragon ELF viewer (instead of readelf)
    #   STRIP=arm-strip     → Snapdragon symbol stripper (instead of strip)
    #   HOSTLD=arm-link     → Snapdragon QC linker / ld.qcld for host
    #   HOSTCC=clang        → sdclang for host C compilation
    #   HOSTCXX=clang++     → sdclang for host C++ compilation
    # ------------------------------------------------------------------
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
        "DTC_FLAGS+=-q"
        "PATH=$SDCLANG_BIN:$PATH"
        "KBUILD_BUILD_USER=$KBUILD_USER"
        "KBUILD_BUILD_HOST=$KBUILD_HOST"
    )

    # Append build.config.common entries if file exists
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
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        OS=$(uname -s)
        VER=$(uname -r)
    fi
    echo -e "$cyan OS: $OS $VER $white"

    AKHILNARANG="environment"
    if [[ "$OS" == *"SUSE"* ]] || [[ "$OS" == *"Regata"* ]]; then
        if [[ ! -d "$AKHILNARANG" ]]; then
            git clone --depth=1 https://github.com/TogoFire/scripts -b akh ${AKHILNARANG}
            cd "${AKHILNARANG}" && bash setup/opensuse.sh && cd ..
        fi
    elif [[ "$OS" == *"Fedora"* ]] || [[ "$OS" == *"Nobara"* ]] || [[ "$OS" == *"Ultramarine"* ]] || [[ "$OS" == *"Rocky"* ]]; then
        if [[ ! -d "$AKHILNARANG" ]]; then
            git clone --depth=1 https://github.com/TogoFire/scripts -b akh ${AKHILNARANG}
            cd "${AKHILNARANG}" && bash setup/fedora.sh && cd ..
        fi
    elif [[ "$OS" == *"Arch"* ]] || [[ "$OS" == *"Manjaro"* ]] || [[ "$OS" == *"Endeavour"* ]] || [[ "$OS" == *"Garuda"* ]]; then
        if [[ ! -d "$AKHILNARANG" ]]; then
            git clone --depth=1 https://github.com/akhilnarang/scripts ${AKHILNARANG}
            cd "${AKHILNARANG}" && bash setup/arch-manjaro.sh && cd ..
        fi
    else
        if [[ ! -d "$AKHILNARANG" ]]; then
            git clone --depth=1 https://github.com/TogoFire/scripts -b akh ${AKHILNARANG}
            cd "${AKHILNARANG}" && bash setup/android_build_env.sh && cd ..
        fi
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
    if [[ -n "$CURRENT_VERSION" ]]; then
        ANYK_VERSION="$CURRENT_VERSION"
        echo -e "$greenish_yellow AnyKernel version: $ANYK_VERSION $white"
    else
        echo -e "$red Could not detect AnyKernel version! $white"
        exit 1
    fi
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
    [ ! -d "$CHANGELOG_DIR" ] && mkdir "$CHANGELOG_DIR"
    git log -n 350 --pretty=format:"%h - %s (%an)" > "$CHANGELOG_FILE"
    sed -i -e "s/^/- /" "$CHANGELOG_FILE"
    echo -e "${purple} Changelog saved to $CHANGELOG_FILE ${white}"
}

############################################################################
#                            CONFIG GENERATOR
############################################################################

config_generator() {
    if [[ -z $CODENAME ]]; then
        error "Codename not set, cannot proceed"
    fi

    DFCF="vendor/${CODENAME}-${SUFFIX}_defconfig"

    if [[ ! -f arch/arm64/configs/$DFCF ]]; then
        inform "Generating defconfig"
        export "${MAKE_ARGS[@]}" "TARGET_BUILD_VARIANT=user"
        bash scripts/gki/generate_defconfig.sh phone1_defconfig vendor/lahaina_QGKI.config
        muke "$DFCF" vendor/lahaina_QGKI.config savedefconfig
        cat work/defconfig > arch/arm64/configs/"$DFCF"
    else
        inform "Generating .config"
        muke "$DFCF" savedefconfig
    fi

    if [[ $TEST == "1" ]]; then
        ./scripts/config --file work/.config -d CONFIG_LTO_CLANG
        ./scripts/config --file work/.config -d CONFIG_HEADERS_INSTALL
    fi
}

config_regenerator() {
    config_generator
    inform "Regenerating defconfig"
    cat work/defconfig > arch/arm64/configs/"$DFCF"
    success "Regeneration completed"
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
    [[ $TEST == "1" ]] && rm -rf arch/arm64/configs/phone1-${SUFFIX}_defconfig
    [[ $DTB_ZIP != "1" ]] && exit 0
}

dtb_zip() {
    obj_builder
    source work/.config
    [[ ! -d $AK3_DIR ]] && error "AnyKernel not present, cannot zip"
    [[ ! -d "$KERNEL_DIR/out" ]] && mkdir "$KERNEL_DIR/out"
    mv -f "$DTBO_PATH"/*.img "$AK3_DIR"
    find "$DTB_PATH"/vendor/*/* -name '*.dtb' -exec cat {} + > "$AK3_DIR"/dtb
    cd "$AK3_DIR" || exit
    make zip VERSION="$(echo "$CONFIG_LOCALVERSION" | cut -c 8-)-dtbs-only"
    cp ./*-signed.zip "$KERNEL_DIR"/out
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
            'modules_install' \
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
    [[ ! -d $AK3_DIR ]] && error "AnyKernel not present, cannot zip"
    [[ ! -d "$KERNEL_DIR/out" ]] && mkdir "$KERNEL_DIR/out"

    cd "$AK3_DIR" || exit
    cd "$KERNEL_DIR" || exit

    mv -f "$KERNEL_DIR/work/$TARGET" "$DTBO_PATH"/*.img "$AK3_DIR"
    find "$DTB_PATH"/vendor/*/* -name '*.dtb' -exec cat {} + > "$AK3_DIR/dtb"

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
            grep drm "$MOD_PATH/modules.alias" > "$AKVRD/modules.alias"
            grep drm "$MOD_PATH/modules.dep" | sed 's/^........//' > "$AKVRD/modules.dep"
            grep drm "$MOD_PATH/modules.softdep" > "$AKVRD/modules.softdep"
            grep drm "$MOD_PATH/modules.order" > "$AKVRD/modules.load"
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

    zip -r9 "${ANYK_VERSION}-${BUILD_TIME}.zip" ./*
    java -jar $ZIPSIGNER_JAR "${ANYK_VERSION}-${BUILD_TIME}.zip" "${ANYK_VERSION}-${BUILD_TIME}-signed.zip"

    echo -e "  ${green}Success! Zip built and signed${white}"

    make zip VERSION="$(echo "$CONFIG_LOCALVERSION" | cut -c 8-)" CUSTOM="$LAST_HASH"
    if [ "$DRM_AS_MODULE" = "1" ]; then
        [ "$VENDOR_RAMDISK_CREATE" = "1" ] && rm -rf "$AK3_DIR/vendor_ramdisk/"
        sed -i s/'dump_boot; # skip unpack'/'split_boot; # skip unpack'/g "$AK3_DIR/anykernel.sh"
    fi

    echo -e "Kernel zip: $(pwd)/${greenish_yellow}${ANYK_VERSION}-${BUILD_TIME}-signed.zip${white}"

    SHA=$(shasum "$(pwd)/${ANYK_VERSION}-${BUILD_TIME}-signed.zip" | cut -f 1 -d '/')
    MD5=$(md5sum "$(pwd)/${ANYK_VERSION}-${BUILD_TIME}-signed.zip" | cut -f 1 -d '/')
    echo -e "  MD5  : $MD5"
    echo -e "  SHA1 : $SHA"

    # Optional MEGA upload
    echo -e "$yellow \n👉 Upload to MEGA? (y/n) [auto-no in 5s] $white"
    read -t 5 -p "$(tput setaf 171) Enter your answer: " answer || { answer=n; }
    if [[ $answer == "y" ]]; then
        read -p "$(tput setaf 171) Email: " email
        read -s -p "$(tput setaf 171) Password: " password
        megaput "$(pwd)/${ANYK_VERSION}-${BUILD_TIME}-signed.zip" -u "$email" -p "$password"
        countdown 3
    fi

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
    success "Build completed in $((DIFF / 60)).$((DIFF % 60)) mins"
}

############################################################################
#                            MAIN / ARGUMENT PARSING
############################################################################

export TZ=America/Sao_Paulo

if [[ -z $* ]]; then
    usage
fi

# Parse flags
[[ $* =~ "--log" ]]     && LOG=1
[[ $* =~ "--silence" ]] && MAKE_ARGS+=("-s") && SILENCE=1

# Run setup steps (order matters)
setup_environment
setup_toolchain       # ← downloads sdclang19, sets PATH, LD_LIBRARY_PATH, MAKE_ARGS
cleanup
setup_anykernel
generate_changelog
ascii_art_logo

# Parse main arguments
for arg in "$@"; do
    case "${arg}" in
        "--device="*)
            CODE_NAME=${arg#*=}
            case $CODE_NAME in
                lahaina)
                    DEVICENAME='lahaina common qgki kernel'
                    CODENAME='lahaina'
                    SUFFIX='qgki'
                    ;;
                *)
                    inform "Device not supported: falling back to manual config"
                    read -rp 'DEVICENAME: ' DEVICENAME
                    read -rp 'CODENAME: '   CODENAME
                    read -rp 'SUFFIX: '     SUFFIX
                    ;;
            esac
            ;;
        "--clean")
            BUILD='clean'
            ;;
        "--test")
            TEST='1'
            CODENAME=lahaina
            ;;
        "--dtb_zip")
            DTB_ZIP=1
            OBJ=dtbs
            dtb_zip
            ;;
        "--dtbs")
            OBJ=dtbs
            dtb_zip
            ;;
        "--obj="*)
            OBJ=${arg#*=}
            obj_builder
            ;;
        "--regen")
            config_regenerator
            ;;
        "--log" | "--silence")
            ;;
        *)
            usage
            ;;
    esac
done

kernel_builder
############################################################################
