SHELL := /bin/bash
.DEFAULT_GOAL := help

ROOT_DIR := $(CURDIR)
HARNESS_DIR ?= $(ROOT_DIR)/alpine_macos_build
LOCAL_BIN_DIR ?= $(HARNESS_DIR)/bin
TOOLCHAIN_BIN_DIR ?= $(HARNESS_DIR)/toolchain/bin
DROP_DIR ?= $(HARNESS_DIR)/drop
DROP_ISO_DIR ?= $(DROP_DIR)/iso
DROP_FIRMWARE_DIR ?= $(DROP_DIR)/firmware
OUT_DIR ?= $(HARNESS_DIR)/out
ISO_DIR ?= $(OUT_DIR)/iso
ISO_WORK_DIR ?= $(OUT_DIR)/work/mkimage
QEMU_STATE_DIR ?= $(OUT_DIR)/qemu
LOG_DIR ?= $(OUT_DIR)/logs
HARNESS_SETUP_WRAPPERS ?= $(HARNESS_DIR)/scripts/setup-wrappers.sh
HARNESS_BOOTSTRAP_HOST ?= $(HARNESS_DIR)/scripts/bootstrap-host.sh
HARNESS_BUILD_GRUB ?= $(HARNESS_DIR)/scripts/build-grub-host.sh

ARCH ?= aarch64
ISO_PROFILE ?= virt
ALPINE_BRANCH ?= edge
ISO_TAG ?= $(shell date +%y%m%d)
ISO_NAME ?= alpine-$(ISO_PROFILE)-$(ISO_TAG)-$(ARCH).iso

ISO_PATH ?= $(shell \
	exact="$(ISO_DIR)/$(ISO_NAME)"; \
	if [ -f "$$exact" ]; then \
		printf '%s\n' "$$exact"; \
		exit 0; \
	fi; \
	for d in "$(DROP_ISO_DIR)" "$(ISO_DIR)" "$(ROOT_DIR)"; do \
		if [ -d "$$d" ]; then \
			candidate=$$(find "$$d" -maxdepth 1 -type f -name '*.iso' 2>/dev/null | head -n 1); \
			if [ -n "$$candidate" ]; then \
				printf '%s\n' "$$candidate"; \
				exit 0; \
			fi; \
		fi; \
	done)

DISK_IMAGE ?= $(QEMU_STATE_DIR)/alpine-$(ARCH).qcow2
DISK_SIZE ?= 32G

QEMU_BIN ?= $(shell \
	if [ -x "$(LOCAL_BIN_DIR)/qemu-system-$(ARCH)" ]; then \
		printf '%s\n' "$(LOCAL_BIN_DIR)/qemu-system-$(ARCH)"; \
	elif [ -x "$(TOOLCHAIN_BIN_DIR)/qemu-system-$(ARCH)" ]; then \
		printf '%s\n' "$(TOOLCHAIN_BIN_DIR)/qemu-system-$(ARCH)"; \
	elif command -v qemu-system-$(ARCH) >/dev/null 2>&1; then \
		command -v qemu-system-$(ARCH); \
	elif [ -x "/opt/homebrew/bin/qemu-system-$(ARCH)" ]; then \
		printf '%s\n' "/opt/homebrew/bin/qemu-system-$(ARCH)"; \
	elif [ -x "/usr/local/bin/qemu-system-$(ARCH)" ]; then \
		printf '%s\n' "/usr/local/bin/qemu-system-$(ARCH)"; \
	fi)

QEMU_IMG ?= $(shell \
	if [ -x "$(LOCAL_BIN_DIR)/qemu-img" ]; then \
		printf '%s\n' "$(LOCAL_BIN_DIR)/qemu-img"; \
	elif [ -x "$(TOOLCHAIN_BIN_DIR)/qemu-img" ]; then \
		printf '%s\n' "$(TOOLCHAIN_BIN_DIR)/qemu-img"; \
	elif command -v qemu-img >/dev/null 2>&1; then \
		command -v qemu-img; \
	elif [ -x "/opt/homebrew/bin/qemu-img" ]; then \
		printf '%s\n' "/opt/homebrew/bin/qemu-img"; \
	elif [ -x "/usr/local/bin/qemu-img" ]; then \
		printf '%s\n' "/usr/local/bin/qemu-img"; \
	fi)

QEMU_ACCEL ?= hvf
QEMU_CPU ?= host
QEMU_MACHINE ?= virt,highmem=off
QEMU_RAM ?= 4096
QEMU_CPUS ?= 4
SSH_FWD_PORT ?= 2222
QEMU_NETDEV ?= user,id=net0,hostfwd=tcp::$(SSH_FWD_PORT)-:22
QEMU_NET_DEVICE ?= virtio-net-device,netdev=net0
QEMU_CONSOLE_ARGS ?= -nographic
QEMU_EXTRA_ARGS ?=
QEMU_DEBUG_EXTRA_ARGS ?= -s -S

QEMU_FIRMWARE_CODE ?= $(shell \
	for f in \
		"$(DROP_FIRMWARE_DIR)/edk2-aarch64-code.fd" \
		"$(DROP_FIRMWARE_DIR)/edk2-arm-code.fd" \
		"/opt/homebrew/share/qemu/edk2-aarch64-code.fd" \
		"/opt/homebrew/share/qemu/edk2-arm-code.fd" \
		"/usr/local/share/qemu/edk2-aarch64-code.fd" \
		"/usr/local/share/qemu/edk2-arm-code.fd"; do \
		if [ -f "$$f" ]; then \
			printf '%s\n' "$$f"; \
			exit 0; \
		fi; \
	done; \
	if [ -d "$(DROP_FIRMWARE_DIR)" ]; then \
		find "$(DROP_FIRMWARE_DIR)" -maxdepth 1 -type f \( -name '*aarch64*code*.fd' -o -name '*arm*code*.fd' -o -name '*code*.fd' \) 2>/dev/null | head -n 1; \
	fi)

QEMU_FIRMWARE_VARS_TEMPLATE ?= $(shell \
	for f in \
		"$(DROP_FIRMWARE_DIR)/edk2-aarch64-vars.fd" \
		"$(DROP_FIRMWARE_DIR)/edk2-arm-vars.fd" \
		"/opt/homebrew/share/qemu/edk2-aarch64-vars.fd" \
		"/opt/homebrew/share/qemu/edk2-arm-vars.fd" \
		"/usr/local/share/qemu/edk2-aarch64-vars.fd" \
		"/usr/local/share/qemu/edk2-arm-vars.fd"; do \
		if [ -f "$$f" ]; then \
			printf '%s\n' "$$f"; \
			exit 0; \
		fi; \
	done; \
	if [ -d "$(DROP_FIRMWARE_DIR)" ]; then \
		find "$(DROP_FIRMWARE_DIR)" -maxdepth 1 -type f \( -name '*aarch64*vars*.fd' -o -name '*arm*vars*.fd' -o -name '*vars*.fd' \) 2>/dev/null | head -n 1; \
	fi)

QEMU_FIRMWARE_VARS ?= $(QEMU_STATE_DIR)/edk2-vars.fd
QEMU_FIRMWARE_ARGS :=

ifneq ($(strip $(QEMU_FIRMWARE_CODE)),)
ifneq ($(strip $(QEMU_FIRMWARE_VARS_TEMPLATE)),)
QEMU_FIRMWARE_ARGS := -drive "if=pflash,format=raw,readonly=on,file=$(QEMU_FIRMWARE_CODE)" -drive "if=pflash,format=raw,file=$(QEMU_FIRMWARE_VARS)"
else
QEMU_FIRMWARE_ARGS := -bios "$(QEMU_FIRMWARE_CODE)"
endif
endif

APK_REPOSITORIES ?= https://dl-cdn.alpinelinux.org/alpine/$(ALPINE_BRANCH)/main https://dl-cdn.alpinelinux.org/alpine/$(ALPINE_BRANCH)/community
APK_REPOSITORIES_FILE ?=
MKIMAGE_SCRIPT ?= $(ROOT_DIR)/aports/scripts/mkimage.sh
MKIMAGE_EXTRA_ARGS ?=

ifeq ($(strip $(APK_REPOSITORIES_FILE)),)
MKIMAGE_SOURCE_ARGS := $(foreach repo,$(APK_REPOSITORIES),--repository $(repo))
else
MKIMAGE_SOURCE_ARGS := --repositories-file "$(APK_REPOSITORIES_FILE)"
endif

ISO_BUILD_CMD ?= sh aports/scripts/mkimage.sh --tag "$(ISO_TAG)" --outdir "$(ISO_DIR)" --workdir "$(ISO_WORK_DIR)" --arch "$(ARCH)" --profile "$(ISO_PROFILE)" $(MKIMAGE_SOURCE_ARGS) $(MKIMAGE_EXTRA_ARGS)

.PHONY: help setup bootstrap bootstrap-host bootstrap-grub doctor layout iso disk firmware boot boot-iso boot-disk debug debug-iso debug-disk clean check-qemu check-qemu-img check-firmware check-iso check-mkimage prepare-drop-dirs prepare-out-dirs prepare-local-bin-dir

help:
	@printf '%s\n' \
		'Local Alpine macOS QEMU harness' \
		'' \
		'Simple flow:' \
		'  make setup       Create the local project folders under alpine_macos_build/' \
		'  make bootstrap   Install/stage host deps and build local grub-mkimage' \
		'  make doctor      Show what the Makefile auto-detected' \
		'  make iso         Build an ISO into alpine_macos_build/out/iso/' \
		'  make boot        Boot the discovered ISO in QEMU with HVF' \
		'  make boot-disk   Boot the qcow2 disk after installation' \
		'' \
		'Folder layout:' \
		'  alpine_macos_build/bin             Wrapper commands used by the harness' \
		'  alpine_macos_build/toolchain/bin   Optional real host binaries if not installed system-wide' \
		'  alpine_macos_build/drop/iso        Put a manually built ISO here if you want' \
		'  alpine_macos_build/drop/firmware   Put edk2 firmware files here if needed' \
		'  alpine_macos_build/out/iso         ISO output from make iso' \
		'  alpine_macos_build/out/qemu        qcow2 disk and UEFI vars' \
		'  alpine_macos_build/toolchain/grub-host  Local GRUB arm64-efi install prefix' \
		'' \
		'You should not need absolute paths for normal use once those folders are populated.'

layout:
	@printf '%s\n' \
		"$(HARNESS_DIR)" \
		"$(LOCAL_BIN_DIR)" \
		"$(TOOLCHAIN_BIN_DIR)" \
		"$(DROP_ISO_DIR)" \
		"$(DROP_FIRMWARE_DIR)" \
		"$(ISO_DIR)" \
		"$(QEMU_STATE_DIR)" \
		"$(LOG_DIR)"

doctor: setup
	@printf 'Project root:        %s\n' "$(ROOT_DIR)"
	@printf 'Harness dir:         %s\n' "$(HARNESS_DIR)"
	@printf 'Wrapper bin dir:     %s\n' "$(LOCAL_BIN_DIR)"
	@printf 'Toolchain bin dir:   %s\n' "$(TOOLCHAIN_BIN_DIR)"
	@printf 'Drop ISO dir:        %s\n' "$(DROP_ISO_DIR)"
	@printf 'Drop firmware dir:   %s\n' "$(DROP_FIRMWARE_DIR)"
	@printf 'Resolved ISO:        %s\n' "$(if $(ISO_PATH),$(ISO_PATH),not found)"
	@printf 'Disk image path:     %s\n' "$(DISK_IMAGE)"
	@if [ "$(QEMU_BIN)" = "$(LOCAL_BIN_DIR)/qemu-system-$(ARCH)" ]; then \
		if resolved=$$("$(QEMU_BIN)" --doctor 2>/dev/null); then \
			printf 'QEMU binary:         %s\n' "$$resolved"; \
			printf 'QEMU binary status:  ok\n'; \
		else \
			printf 'QEMU binary:         %s\n' "$(QEMU_BIN)"; \
			printf 'QEMU binary status:  missing\n'; \
		fi; \
	else \
		printf 'QEMU binary:         %s\n' "$(if $(QEMU_BIN),$(QEMU_BIN),not found)"; \
		if [ -n "$(QEMU_BIN)" ] && [ -x "$(QEMU_BIN)" ]; then printf 'QEMU binary status:  ok\n'; else printf 'QEMU binary status:  missing\n'; fi; \
	fi
	@if [ "$(QEMU_IMG)" = "$(LOCAL_BIN_DIR)/qemu-img" ]; then \
		if resolved=$$("$(QEMU_IMG)" --doctor 2>/dev/null); then \
			printf 'QEMU img:            %s\n' "$$resolved"; \
			printf 'QEMU img status:     ok\n'; \
		else \
			printf 'QEMU img:            %s\n' "$(QEMU_IMG)"; \
			printf 'QEMU img status:     missing\n'; \
		fi; \
	else \
		printf 'QEMU img:            %s\n' "$(if $(QEMU_IMG),$(QEMU_IMG),not found)"; \
		if [ -n "$(QEMU_IMG)" ] && [ -x "$(QEMU_IMG)" ]; then printf 'QEMU img status:     ok\n'; else printf 'QEMU img status:     missing\n'; fi; \
	fi
	@printf 'UEFI code:           %s\n' "$(if $(QEMU_FIRMWARE_CODE),$(QEMU_FIRMWARE_CODE),not found)"
	@printf 'UEFI vars template:  %s\n' "$(if $(QEMU_FIRMWARE_VARS_TEMPLATE),$(QEMU_FIRMWARE_VARS_TEMPLATE),not found)"
	@printf 'mkimage script:      %s\n' "$(MKIMAGE_SCRIPT)"
	@printf 'ISO profile/tag:     %s / %s\n' "$(ISO_PROFILE)" "$(ISO_TAG)"
	@printf '%s\n' ''
	@for cmd in apk abuild-sign update-kernel mkinitfs xorrisofs mksquashfs fakeroot mformat mcopy grub-mkimage; do \
		if [ -x "$(LOCAL_BIN_DIR)/$$cmd" ]; then \
			if resolved=$$("$(LOCAL_BIN_DIR)/$$cmd" --doctor 2>/dev/null); then \
				printf 'mkimage tool %-12s ok (%s)\n' "$$cmd" "$$resolved"; \
			else \
				printf 'mkimage tool %-12s missing\n' "$$cmd"; \
			fi; \
		elif command -v $$cmd >/dev/null 2>&1; then \
			printf 'mkimage tool %-12s ok (%s)\n' "$$cmd" "$$(command -v $$cmd)"; \
		else \
			printf 'mkimage tool %-12s missing\n' "$$cmd"; \
		fi; \
	done
	@printf '%s\n' ''
	@printf '%s\n' 'Note: HVF on QEMU is a useful Apple Silicon-adjacent test bed, but it is not a true 1:1 Apple SoC environment.'
	@printf '%s\n' 'Hint: run make bootstrap if you want the harness to install/stage the host-side tools it knows how to provision.'

prepare-drop-dirs:
	@mkdir -p "$(DROP_ISO_DIR)" "$(DROP_FIRMWARE_DIR)"

prepare-local-bin-dir:
	@mkdir -p "$(LOCAL_BIN_DIR)" "$(TOOLCHAIN_BIN_DIR)"

prepare-out-dirs:
	@mkdir -p "$(ISO_DIR)" "$(ISO_WORK_DIR)" "$(QEMU_STATE_DIR)" "$(LOG_DIR)"

setup: prepare-drop-dirs prepare-local-bin-dir prepare-out-dirs
	@"$(HARNESS_SETUP_WRAPPERS)"
	@printf 'Prepared local harness under %s\n' "$(HARNESS_DIR)"

bootstrap-host: setup
	@"$(HARNESS_BOOTSTRAP_HOST)"

bootstrap-grub: bootstrap-host
	@"$(HARNESS_BUILD_GRUB)"

bootstrap: bootstrap-grub
	@printf 'Bootstrapped host toolchain under %s\n' "$(HARNESS_DIR)"

check-qemu:
	@if [ -z "$(QEMU_BIN)" ] || [ ! -x "$(QEMU_BIN)" ]; then \
		printf 'Missing qemu-system-%s.\n' "$(ARCH)" >&2; \
		printf 'Put it in %s, or install it so it is on PATH.\n' "$(TOOLCHAIN_BIN_DIR)" >&2; \
		exit 1; \
	fi
	@if [ "$(QEMU_BIN)" = "$(LOCAL_BIN_DIR)/qemu-system-$(ARCH)" ] && ! "$(QEMU_BIN)" --doctor >/dev/null 2>&1; then \
		printf 'qemu-system-%s wrapper is present, but no real backend was found.\n' "$(ARCH)" >&2; \
		printf 'Put it in %s, or install it so it is on PATH.\n' "$(TOOLCHAIN_BIN_DIR)" >&2; \
		exit 1; \
	fi

check-qemu-img:
	@if [ -z "$(QEMU_IMG)" ] || [ ! -x "$(QEMU_IMG)" ]; then \
		printf '%s\n' 'Missing qemu-img.' >&2; \
		printf 'Put it in %s, or install it so it is on PATH.\n' "$(TOOLCHAIN_BIN_DIR)" >&2; \
		exit 1; \
	fi
	@if [ "$(QEMU_IMG)" = "$(LOCAL_BIN_DIR)/qemu-img" ] && ! "$(QEMU_IMG)" --doctor >/dev/null 2>&1; then \
		printf '%s\n' 'qemu-img wrapper is present, but no real backend was found.' >&2; \
		printf 'Put it in %s, or install it so it is on PATH.\n' "$(TOOLCHAIN_BIN_DIR)" >&2; \
		exit 1; \
	fi

check-firmware:
	@if [ -z "$(QEMU_FIRMWARE_CODE)" ]; then \
		printf '%s\n' 'Missing aarch64 UEFI firmware.' >&2; \
		printf 'Drop edk2 firmware files into %s, or install QEMU firmware system-wide.\n' "$(DROP_FIRMWARE_DIR)" >&2; \
		exit 1; \
	fi

check-iso:
	@if [ -z "$(ISO_PATH)" ] || [ ! -f "$(ISO_PATH)" ]; then \
		printf '%s\n' 'No ISO was found.' >&2; \
		printf 'Run make iso, or place an ISO into %s.\n' "$(DROP_ISO_DIR)" >&2; \
		exit 1; \
	fi

check-mkimage:
	@if [ ! -f "$(MKIMAGE_SCRIPT)" ]; then \
		printf 'mkimage script not found at %s\n' "$(MKIMAGE_SCRIPT)" >&2; \
		exit 1; \
	fi

iso: setup check-mkimage prepare-out-dirs
	@cd "$(ROOT_DIR)" && \
		PATH="$(LOCAL_BIN_DIR):$(TOOLCHAIN_BIN_DIR):$$PATH" \
		JOBS="$$(sysctl -n hw.ncpu 2>/dev/null || echo 4)" \
		ABUILD_SHAREDIR="$(ROOT_DIR)/abuild" \
		ABUILD_CONF="$(ROOT_DIR)/abuild/abuild.conf" \
		ABUILD_DEFCONF="$(ROOT_DIR)/abuild/default.conf" \
		APORTSDIR="$(ROOT_DIR)/aports" \
		# try to fetch alpine signing keys into the mkimage workdir so apk trusts repos
		"$(HARNESS_DIR)/scripts/fetch-apk-keys.sh" "$(ARCH)" "$(ISO_WORK_DIR)" $(APK_REPOSITORIES) || true; \
		$(ISO_BUILD_CMD)

disk: check-qemu-img prepare-out-dirs
	@if [ -f "$(DISK_IMAGE)" ]; then \
		printf 'Disk already exists: %s\n' "$(DISK_IMAGE)"; \
	else \
		"$(QEMU_IMG)" create -f qcow2 "$(DISK_IMAGE)" "$(DISK_SIZE)"; \
	fi

firmware: prepare-out-dirs
ifneq ($(strip $(QEMU_FIRMWARE_VARS_TEMPLATE)),)
	@if [ ! -f "$(QEMU_FIRMWARE_VARS)" ]; then \
		cp "$(QEMU_FIRMWARE_VARS_TEMPLATE)" "$(QEMU_FIRMWARE_VARS)"; \
		printf 'Seeded UEFI vars: %s\n' "$(QEMU_FIRMWARE_VARS)"; \
	fi
else
	@:
endif

boot: boot-iso

boot-iso: check-qemu check-firmware check-iso disk firmware
	@"$(QEMU_BIN)" \
		-accel "$(QEMU_ACCEL)" \
		-cpu "$(QEMU_CPU)" \
		-machine "$(QEMU_MACHINE)" \
		-smp "$(QEMU_CPUS)" \
		-m "$(QEMU_RAM)" \
		-boot order=d \
		$(QEMU_FIRMWARE_ARGS) \
		-drive "file=$(DISK_IMAGE),format=qcow2,if=virtio" \
		-cdrom "$(ISO_PATH)" \
		-netdev "$(QEMU_NETDEV)" \
		-device "$(QEMU_NET_DEVICE)" \
		-device virtio-rng-device \
		$(QEMU_CONSOLE_ARGS) \
		$(QEMU_EXTRA_ARGS)

boot-disk: check-qemu check-firmware disk firmware
	@"$(QEMU_BIN)" \
		-accel "$(QEMU_ACCEL)" \
		-cpu "$(QEMU_CPU)" \
		-machine "$(QEMU_MACHINE)" \
		-smp "$(QEMU_CPUS)" \
		-m "$(QEMU_RAM)" \
		-boot order=c \
		$(QEMU_FIRMWARE_ARGS) \
		-drive "file=$(DISK_IMAGE),format=qcow2,if=virtio" \
		-netdev "$(QEMU_NETDEV)" \
		-device "$(QEMU_NET_DEVICE)" \
		-device virtio-rng-device \
		$(QEMU_CONSOLE_ARGS) \
		$(QEMU_EXTRA_ARGS)

debug: debug-iso

debug-iso: check-qemu check-firmware check-iso disk firmware
	@"$(QEMU_BIN)" \
		-accel "$(QEMU_ACCEL)" \
		-cpu "$(QEMU_CPU)" \
		-machine "$(QEMU_MACHINE)" \
		-smp "$(QEMU_CPUS)" \
		-m "$(QEMU_RAM)" \
		-boot order=d \
		$(QEMU_FIRMWARE_ARGS) \
		-drive "file=$(DISK_IMAGE),format=qcow2,if=virtio" \
		-cdrom "$(ISO_PATH)" \
		-netdev "$(QEMU_NETDEV)" \
		-device "$(QEMU_NET_DEVICE)" \
		-device virtio-rng-device \
		$(QEMU_CONSOLE_ARGS) \
		$(QEMU_DEBUG_EXTRA_ARGS) \
		$(QEMU_EXTRA_ARGS)

debug-disk: check-qemu check-firmware disk firmware
	@"$(QEMU_BIN)" \
		-accel "$(QEMU_ACCEL)" \
		-cpu "$(QEMU_CPU)" \
		-machine "$(QEMU_MACHINE)" \
		-smp "$(QEMU_CPUS)" \
		-m "$(QEMU_RAM)" \
		-boot order=c \
		$(QEMU_FIRMWARE_ARGS) \
		-drive "file=$(DISK_IMAGE),format=qcow2,if=virtio" \
		-netdev "$(QEMU_NETDEV)" \
		-device "$(QEMU_NET_DEVICE)" \
		-device virtio-rng-device \
		$(QEMU_CONSOLE_ARGS) \
		$(QEMU_DEBUG_EXTRA_ARGS) \
		$(QEMU_EXTRA_ARGS)

clean:
	@rm -rf "$(OUT_DIR)"
