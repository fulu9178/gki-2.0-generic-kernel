#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/env.sh"
# 版本串默认 -android15-8-4k（与 gki_defconfig 一致）；可用 LOCALVERSION=... 覆盖
export LOCALVERSION="${LOCALVERSION:--android15-8-4k}"
# AutoFDO：profile 树内自带；O=out 构建时编译器/链接器 cwd 在 out/，必须用绝对路径
export CLANG_AUTOFDO_PROFILE="$GKI_ROOT/common/android/gki/aarch64/afdo/kernel.afdo"
# LTO+AutoFDO 并行峰值约 15GB RAM：默认 -j$(nproc)，仅在 OOM 时用 JOBS=N 降并行
cd "$GKI_ROOT/common"
exec make O=out ARCH=arm64 LLVM=1 LOCALVERSION="$LOCALVERSION" \
     KCFLAGS=-D__ANDROID_COMMON_KERNEL__ \
     HOSTCFLAGS="-I$GKI_ROOT/hosttools/root/usr/include" \
     -j"${JOBS:-$(nproc)}" Image
