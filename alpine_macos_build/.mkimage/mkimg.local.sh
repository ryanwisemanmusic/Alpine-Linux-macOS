#!/bin/sh
# Local mkimage plugin to adjust defaults for local builds.
# Overrides profile_base to disable modloop signing when building locally.

profile_base() {
    kernel_flavors="lts"
    initfs_cmdline="modules=loop,squashfs,sd-mod,usb-storage quiet"
    initfs_features="ata base bootchart cdrom dhcp ext4 mmc nvme raid scsi squashfs usb virtio"
    modloop_sign=no
    grub_mod="all_video disk part_gpt part_msdos linux normal configfile search search_label efi_gop fat iso9660 cat echo ls test true help gzio"
    case "$ARCH" in
    x86*) grub_mod="$grub_mod multiboot2 efi_uga";;
    esac
    case "$ARCH" in
    x86_64) initfs_features="$initfs_features nfit";;
    arm*|aarch64|riscv64) initfs_features="$initfs_features phy";;
    esac
    apks="alpine-base apk-cron busybox chrony dhcpcd doas e2fsprogs
        kbd-bkeymaps network-extras openntpd openssl openssh
        tzdata wget tiny-cloud-alpine"
    apkovl=
    hostname="alpine"
}
