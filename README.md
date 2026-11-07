# ufi003-debian
适用于 `UFI003_MB_V02`（如 `UFI_YKM_HW01CTDE_V040` / `msm8916_32_512`）的 Debian 构建脚本与全套救砖/刷机工具。

## 针对出厂 32 位固件版 UFI003 的修复说明
部分批次 `UFI003_MB_V02`（512MB RAM + 4GB eMMC）出厂搭载 32 位 Android 4.4.4，存在以下三个导致常规直刷后“无 USB / 卡死”的问题，本仓库已内置完整修正：
1. **出厂 `tz` / `hyp` 为 32 位 (`ELF32`)**：不支持切换 `AArch64` 引导 64 位 Linux 内核，且原厂 `tz` 分区仅 512KB（容不下 591.5KB 的 64 位 `tz.mbn`）。通过 `firmware/patch_gpt_tz.py` 将原厂 GPT 中相邻的 `tz` + `tzbak` 无损合并为 1MB `tz` 分区（其余分区扇区号与 `PARTUUID` 100% 不变），刷入 `firmware/tz.mbn` 与 `firmware/hyp.mbn` 即可开启 64 位支持。
2. **保留原厂 `sbl1` + 原厂 `aboot` + 二级引导 `lk2nd`**：无需替换原厂 `aboot`（避免触发 `sbl1` 签名校验失败），直接将 `firmware/lk2nd.img` 刷入硬件 `boot` 分区首部，再通过 `lk2nd` Fastboot 将 Linux `boot.img` 刷入逻辑子 `boot` 分区（偏移 `+512KB`）。
3. **修正 `userdata` `PARTUUID` 与 USB Gadget 自启**：将内核 `cmdline` 与 `/etc/fstab` 统一为 `PARTUUID=598664a9-7976-e692-1cdd-010c5d49b568`，并优化 `/usr/sbin/openstick-gc-manager.sh` 开机直接拉起 `rndis,ffs`（USB RNDIS `192.168.68.1/24` + ADB）。

## 刷入流程（9008 EDL + Fastboot）

```bash
# 1. 备份并合并原厂 GPT 中的 tz + tzbak 为 1MB tz 分区
python3 firmware/patch_gpt_tz.py gpt-head.bin gpt-tail.bin gpt-head-tz1m.bin gpt-tail-tz1m.bin

# 2. 在 9008 (EDL) 模式下刷入 1MB-tz 分区表、64 位 tz/hyp 以及 lk2nd（至 boot 分区）
edl ws 0 gpt-head-tz1m.bin --loader=loader-8916.mbn
edl w tz firmware/tz.mbn --loader=loader-8916.mbn
edl w hyp firmware/hyp.mbn --loader=loader-8916.mbn
edl w boot firmware/lk2nd.img --loader=loader-8916.mbn
edl reset --loader=loader-8916.mbn

# 3. 重启自动进入 lk2nd Fastboot (18d1:d00d) 后，刷入 Debian 根文件系统与内核
fastboot erase system
fastboot erase cache
fastboot -S 100M flash userdata rootfs.img
fastboot flash boot boot.img
fastboot reboot
```

## 特性
- NFS client v2/v3/v4, NFS server v3/v4
- KSMBD
- 默认 300% zram
- `boot-no-modem-oc.img` 内核超频至 1.2GHz

## 本地构建
1. 克隆本仓库
2. 安装软件包 `debootstrap rsync qemu-user-static binfmt-support android-sdk-libsparse-utils`
3. 进入 `rootfs` 目录，以 root 权限运行 `build.sh`
4. 构建完成后会在 `rootfs` 目录得到 `rootfs.img`，`kernel` 目录得到 `boot.img`
