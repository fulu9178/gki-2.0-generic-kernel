# GKI 2.0 通用内核 — 6.6.158

面向 GKI 2.0（android15-6.6，内核 6.6）设备的通用内核。

- **基线**：AOSP ACK `android15-6.6` 分支 tip（commit `448c303366032107c46d39006c8127a5ca967a26`）
- **形态**：单片内核（monolithic）。`arch/arm64/configs/gki_defconfig` 中 81 项 `=m` 改为 `=y`；
  剩余 19 项 `=m`（18 个 KUNIT/ZRAM 测试 + `ZSMALLOC`）
- **补丁**：共 **84 个**（`patches/`）
  - **3 个通用补丁**
    1. `kernel/module/version.c` — vermagic / 符号 CRC 校验绕过（`same_magic()`、`check_version()` 恒返回 1）
    2. `arch/arm64/configs/gki_defconfig` — `CONFIG_LOCALVERSION="-android15-8-4k"`，关闭 `LOCALVERSION_AUTO`
    3. `Makefile` — `SUBLEVEL = 158`
  - **1 个单片/LTO 配置补丁**：`0083-arm64-gki_defconfig-align-monolithic-image-with-Haru.patch`
  - **1 个 LTO 符号名补丁**：`0084-lto-keep-plain-symbol-names-for-statics-internalized.patch`
    — 给被 ThinLTO 内部化改名的 9 处文件级 `static` 加 `__used`，恢复 vmlinux 中的普通符号名
  - **79 条 stable 回补**：从上游 stable `v6.6.143..v6.6.157` 中挑选的修复
    （f2fs 16 · clk/qcom 15 · fuse 13 · GIC-v3-ITS 4 · erofs 3 · arm64 3 · selinux 2 · overlayfs 2 · 其余各 1）
- **版本串**：形如 `6.6.<SUBLEVEL>-android15-8[-<可选后缀>]-4k`（`uname -r`）。`-android15-8`
  对应 KMI（`BRANCH=android15-6.6` 的 `KMI_GENERATION=8`），`-4k` 是页大小；可选后缀默认为空，
  即默认版本串为 `6.6.158-android15-8-4k`
- **状态**：已在 GKI 2.0（android15-6.6）真机开机验证

## 通用补丁 1：vermagic / CRC 绕过做什么

`kernel/module/version.c` 中 `same_magic()` 与 `check_version()` 恒返回 1。GKI 设备的 vendor 模块
（`/vendor_dlkm`、`/system_dlkm`）在厂商的内核二进制上编译，其 vermagic（形如
`6.6.<x>-android15-8-g<commit>-ab<salt>-4k`）与本内核不一致；`CONFIG_MODVERSIONS=y` 还会比对符号 CRC。
不改内核就无法加载它们。该补丁显式放弃这两项校验。

## 构建选项

开启：`LTO`、`LTO_CLANG`、`LTO_CLANG_THIN`、`AUTOFDO_CLANG`、`CFI_PERMISSIVE`、`IDLE_PAGE_TRACKING`、
`TRANSPARENT_HUGEPAGE_ALWAYS`、`TMPFS_POSIX_ACL`、`TMPFS_XATTR`、`RCU_NOCB_CPU_DEFAULT_ALL`、
`TASKS_TRACE_RCU_READ_MB`、`PCIEASPM_POWER_SUPERSAVE`、`WQ_POWER_EFFICIENT_DEFAULT`。

关闭：`LTO_NONE`、`TRANSPARENT_HUGEPAGE_MADVISE`、`PCIEASPM_DEFAULT`。

## 构建

工具链：系统 clang 19 + lld 19（`/usr/lib/llvm-19/bin` 与 `$GKI_ROOT/tools/lld19/usr/bin` 前置到 `PATH`）；`ARCH=arm64 LLVM=1`。

```bash
. env.sh
make O=out ARCH=arm64 LLVM=1 \
     KCFLAGS=-D__ANDROID_COMMON_KERNEL__ \
     HOSTCFLAGS="-I$GKI_ROOT/hosttools/root/usr/include" gki_defconfig
make O=out ARCH=arm64 LLVM=1 \
     KCFLAGS=-D__ANDROID_COMMON_KERNEL__ \
     HOSTCFLAGS="-I$GKI_ROOT/hosttools/root/usr/include" \
     CLANG_AUTOFDO_PROFILE=$GKI_ROOT/common/android/gki/aarch64/afdo/kernel.afdo \
     -j$(nproc) Image
```

默认版本串取 `gki_defconfig` 的 `CONFIG_LOCALVERSION="-android15-8-4k"`；需要自定义后缀时，可在
`gki_defconfig` 改 `CONFIG_LOCALVERSION`，或在上面两条 `make` 命令后追加 `LOCALVERSION=<后缀>`
（例如 `LOCALVERSION=-android15-8-custom-4k`）覆盖。

- AutoFDO profile 必须用**绝对路径**：`O=out` 下编译器 cwd 是 `out/`，相对路径会报
  `clang: error: no such file or directory`。profile 位于树内
  `common/android/gki/aarch64/afdo/kernel.afdo`（4.16MB）。
- LTO+AutoFDO 并行峰值内存约 15GB，默认 `-j$(nproc)`；仅在 OOM 时用 `JOBS=N` 降并行。

完整步骤见 `scripts/README-build.md`；`scripts/build.sh` 封装了 `Image` 编译。

## 打包

```bash
pack-boot.sh <stock boot.img> <Image> <out.img>
```

## 从零复现

```bash
git clone https://android.googlesource.com/kernel/common common
cd common
git checkout 448c303366032107c46d39006c8127a5ca967a26    # 基线 tip
git am /path/to/patches/*.patch                          # 84 个补丁
```

## 说明与边界

- 不含 KSU/SUSFS —— 纯 GKI，无 root
- 不含任何编译产物（无 Image / boot.img / .o / .ko）
- 部分 OEM-GKI 设备的 stock 内核带厂商私有补丁（例如某些机型的 f2fs hybrid-UFS / IOSTAT 等）。
  本内核不含这些特性；实测不影响启动（vendor 模块经通用补丁 1 正常加载）。
- 内核源码为 **GPL-2.0**，见 [LICENSE](LICENSE)
