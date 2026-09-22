# GKI_ROOT GKI 6.6.158 Image 构建记录（plain make + 系统 LLVM 19，无 root）

## 目标
构建 GKI 2.0（android15-6.6）单片（monolithic）Image，版本串形如
`6.6.<SUBLEVEL>-android15-8[-<可选后缀>]-4k`（默认 `6.6.158-android15-8-4k`）。

- 基线：AOSP ACK `android15-6.6` tip，commit `448c303366032107c46d39006c8127a5ca967a26`
- 补丁：`patches/` 共 84 个
  - 3 个通用：vermagic/CRC 绕过、`LOCALVERSION=-android15-8-4k`、`SUBLEVEL=158`
  - 1 个单片/LTO 配置：`0083-arm64-gki_defconfig-align-monolithic-image-with-Haru.patch`
  - 1 个 LTO 符号名：`0084-lto-keep-plain-symbol-names-for-statics-internalized.patch`
  - 79 条 stable 回补：`v6.6.143..v6.6.157`
- 形态：`gki_defconfig` 中 81 项 `=m` → `=y`；剩余 19 项 `=m`（18 个 KUNIT/ZRAM 测试 + `ZSMALLOC`）

## 目录
```
$GKI_ROOT/               默认 $HOME/gki-kernel
├── common/              内核树（基线 + patches/ 全部 84 个补丁）
├── tools/lld19/         lld 19 本地解包（usr/bin 提供 ld.lld）
├── kbt/                 kernel/prebuilts/build-tools（pahole/lz4/dtc/depmod + lib64）
├── hosttools/           本地解包的 Debian 包（无 root）：bison flex m4 libelf-dev zlib1g-dev pkgconf
│   ├── bin/             自包含 wrapper：pkg-config / pahole
│   └── pkgconfig/       重写过路径的 libelf.pc
└── scripts/             env.sh / build.sh / pack-boot.sh / verify.sh
```

## 复现步骤
```bash
# 0) 设定根目录（env.sh 默认 $HOME/gki-kernel）
export GKI_ROOT=${GKI_ROOT:-$HOME/gki-kernel}

# 1) 源码 + 84 个补丁
git clone https://android.googlesource.com/kernel/common "$GKI_ROOT/common"
git -C "$GKI_ROOT/common" checkout 448c303366032107c46d39006c8127a5ca967a26
git -C "$GKI_ROOT/common" am "$GKI_ROOT"/patches/*.patch

# 2) clang 19 + lld 19（宿主无需 root；lld 若发行版未装可本地解包）
sudo apt-get install clang-19 lld-19            # 已装则跳过
# 若 lld-19 来自本地解包：dpkg-deb -x lld-19_*.deb "$GKI_ROOT/tools/lld19"
# env.sh 会把 /usr/lib/llvm-19/bin 和 $GKI_ROOT/tools/lld19/usr/bin 前置到 PATH

# 3) 官方宿主工具（pahole / lz4 / dtc / depmod）
git clone --filter=blob:none --sparse -b main-kernel-build-2024 \
  https://android.googlesource.com/kernel/prebuilts/build-tools "$GKI_ROOT/kbt"
git -C "$GKI_ROOT/kbt" sparse-checkout set linux-x86/bin linux-x86/lib64

# 4) 无 root 替代 apt：本地解包 bison/flex/m4/libelf-dev/zlib1g-dev/pkgconf
mkdir -p "$GKI_ROOT/hosttools" && cd "$GKI_ROOT/hosttools"
apt-get download bison flex m4 libfl2 libelf-dev zlib1g-dev pkgconf pkgconf-bin libpkgconf3
for d in *.deb; do dpkg-deb -x "$d" root/; done
# libelf-dev 带静态 libelf.a 会被误链接，改为指向系统共享库
cd root/usr/lib/x86_64-linux-gnu
ln -sf /usr/lib/x86_64-linux-gnu/libelf.so.1 libelf.so && rm -f libelf.a

# 5) 配置
. "$GKI_ROOT/scripts/env.sh"
cd "$GKI_ROOT/common"
make O=out ARCH=arm64 LLVM=1 \
     KCFLAGS=-D__ANDROID_COMMON_KERNEL__ \
     HOSTCFLAGS="-I$GKI_ROOT/hosttools/root/usr/include" gki_defconfig

# 6) 编译（AutoFDO 必须绝对路径；LTO+AutoFDO 峰值约 15GB，默认 -j$(nproc)）
make O=out ARCH=arm64 LLVM=1 \
     KCFLAGS=-D__ANDROID_COMMON_KERNEL__ \
     HOSTCFLAGS="-I$GKI_ROOT/hosttools/root/usr/include" \
     CLANG_AUTOFDO_PROFILE="$GKI_ROOT/common/android/gki/aarch64/afdo/kernel.afdo" \
     -j$(nproc) Image
#   或："$GKI_ROOT/scripts/build.sh"   # LTO+AutoFDO 峰值约 15GB；仅 OOM 时用 JOBS=N 降并行
#
# 版本串默认取 gki_defconfig 的 CONFIG_LOCALVERSION="-android15-8-4k"；
# 需要自定义后缀时追加 LOCALVERSION=<后缀> 覆盖（如 LOCALVERSION=-android15-8-custom-4k）。

# 7) 校验
strings out/arch/arm64/boot/Image | grep -m1 '6\.6\.158'
"$GKI_ROOT/scripts/verify.sh" out/arch/arm64/boot/Image /path/to/stock_boot.img
```

## AutoFDO
- profile：`common/android/gki/aarch64/afdo/kernel.afdo`（4.16MB，树内自带）
- `CLANG_AUTOFDO_PROFILE` 必须用**绝对路径**：`O=out` 下编译器/链接器 cwd 在 `out/`，
  相对路径会报 `clang: error: no such file or directory`
- LTO+AutoFDO 并行峰值内存约 15GB：默认 `-j$(nproc)`，仅在 OOM 时用 `JOBS=N` 降并行

## 生效配置
```
CONFIG_LTO=y
CONFIG_LTO_CLANG=y
CONFIG_LTO_CLANG_THIN=y
CONFIG_AUTOFDO_CLANG=y
CONFIG_CFI_PERMISSIVE=y
CONFIG_IDLE_PAGE_TRACKING=y
CONFIG_TRANSPARENT_HUGEPAGE=y
CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS=y
CONFIG_TMPFS_POSIX_ACL=y
CONFIG_TMPFS_XATTR=y
CONFIG_RCU_NOCB_CPU_DEFAULT_ALL=y
CONFIG_TASKS_TRACE_RCU_READ_MB=y
CONFIG_PCIEASPM_POWER_SUPERSAVE=y
CONFIG_WQ_POWER_EFFICIENT_DEFAULT=y
# CONFIG_LTO_NONE is not set
# CONFIG_TRANSPARENT_HUGEPAGE_MADVISE is not set
# CONFIG_PCIEASPM_DEFAULT is not set
CONFIG_LOCALVERSION="-android15-8-4k"
# CONFIG_LOCALVERSION_AUTO is not set
```

## 版本串
`KERNELVERSION`（`Makefile`：`VERSION=6 PATCHLEVEL=6 SUBLEVEL=158`）= `6.6.158`；
`CONFIG_LOCALVERSION="-android15-8-4k"` + `LOCALVERSION_AUTO` 关闭 → `uname -r` 输出
`6.6.158-android15-8-4k`。其中 `-android15-8` 对应 KMI（`KMI_GENERATION=8`）、`-4k` 为页大小；
需要自定义后缀可在 `gki_defconfig` 改 `CONFIG_LOCALVERSION` 或构建时传 `LOCALVERSION=<后缀>`。

## 打包
```bash
"$GKI_ROOT/scripts/pack-boot.sh" <stock boot.img> <Image> <out.img>
```
用 stock boot.img 的布局重打包：只替换内核区、更新 `kernel_size`、清掉失效的 AVB（vbmeta + footer），
保留分区尺寸，并自检内核区 sha256 与头部改动字节。

## 工具链与依赖
- clang/lld：系统 LLVM 19（Debian clang 19.1.x + LLD 19.1.x）；lld 亦可用本地解包置于 `$GKI_ROOT/tools/lld19/usr/bin`
- 宿主工具：`kernel/prebuilts/build-tools`（pahole v1.25 / lz4 / dtc / depmod）
- bison / flex / m4 / libelf-dev / zlib1g-dev / pkgconf：本地解包 Debian 包（`hosttools/`，无 root）
- 不使用 GCC：`CONFIG_CFI_CLANG=y` 仅 clang 支持，且 CFI type hash 与 clang 版本绑定，必须用 clang 19
- 构建过程无需 root
