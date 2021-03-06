# Snippet for Linux kernel package building
# Copyright (C) 2020 Eugenio "g7" Paolantonio <me@medesimo.eu>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#    * Redistributions of source code must retain the above copyright
#      notice, this list of conditions and the following disclaimer.
#    * Redistributions in binary form must reproduce the above copyright
#      notice, this list of conditions and the following disclaimer in the
#      documentation and/or other materials provided with the distribution.
#    * Neither the name of the <organization> nor the
#      names of its contributors may be used to endorse or promote products
#      derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


include $(CURDIR)/debian/kernel-info.mk

ifneq (,$(filter parallel=%,$(DEB_BUILD_OPTIONS)))
	NUMJOBS := $(patsubst parallel=%,%,$(filter parallel=%,$(DEB_BUILD_OPTIONS)))
else
	NUMJOBS := 1
endif

export DEB_HOST_MULTIARCH = $(shell dpkg-architecture -qDEB_HOST_MULTIARCH)

KERNEL_RELEASE = $(KERNEL_BASE_VERSION)-$(DEVICE_VENDOR)-$(DEVICE_MODEL)
OUT = $(CURDIR)/out
KERNEL_OUT = $(OUT)/KERNEL_OBJ
ifeq ($(BUILD_CROSS), 1)
	CROSS_COMPILE = $(BUILD_TRIPLET)
endif
BUILD_COMMAND = PATH=$(BUILD_PATH):$(CURDIR)/debian/path-override:${PATH} LDFLAGS="" CFLAGS="" $(MAKE) KERNELRELEASE=$(KERNEL_RELEASE) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(CROSS_COMPILE) CROSS_COMPILE_ARM32=$(CROSS_COMPILE) CLANG_TRIPLE=$(BUILD_CLANG_TRIPLET) -j$(NUMJOBS) O=$(KERNEL_OUT) CC=$(BUILD_CC)

KERNEL_BOOTIMAGE_VERSION ?= 0

debian/control:
	sed -e "s|@KERNEL_BASE_VERSION@|$(KERNEL_BASE_VERSION)|g" \
		-e "s|@VARIANT@|$(VARIANT)|g" \
		-e "s|@DEVICE_VENDOR@|$(DEVICE_VENDOR)|g" \
		-e "s|@DEVICE_MODEL@|$(DEVICE_MODEL)|g" \
		-e "s|@DEVICE_FULL_NAME@|$(DEVICE_FULL_NAME)|g" \
		-e "s|@DEB_TOOLCHAIN@|$(DEB_TOOLCHAIN)|g" \
		-e "s|@DEB_BUILD_ON@|$(DEB_BUILD_ON)|g" \
		-e "s|@DEB_BUILD_FOR@|$(DEB_BUILD_FOR)|g" \
		/usr/share/linux-packaging-snippets/control.in > debian/control

path-override-prepare:
	mkdir -p debian/path-override
	ln -s /usr/bin/python2 debian/path-override/python

out/KERNEL_OBJ/.config: arch/$(KERNEL_ARCH)/configs/$(KERNEL_DEFCONFIG)
	$(BUILD_COMMAND) defconfig KBUILD_DEFCONFIG=$(KERNEL_DEFCONFIG)

out/kernel-stamp: out/KERNEL_OBJ/.config
	$(BUILD_COMMAND) $(KERNEL_BUILD_TARGET)
	touch $(OUT)/kernel-stamp

out/modules-stamp: out/kernel-stamp out/dtb-stamp
	$(BUILD_COMMAND) modules
	touch $(OUT)/modules-stamp

out/dtb-stamp: out/kernel-stamp
	$(BUILD_COMMAND) dtbs
	touch $(OUT)/dtb-stamp

out/KERNEL_OBJ/target-dtb: out/kernel-stamp out/dtb-stamp
ifeq ($(KERNEL_IMAGE_WITH_DTB),1)
ifeq ($(KERNEL_IMAGE_WITH_DTB_OVERLAY_IN_KERNEL),1)
	if [ -n "$(KERNEL_IMAGE_DTB)" ]; then \
		KERNEL_IMAGE_DTB=$(KERNEL_OUT)/$(KERNEL_IMAGE_DTB); \
	else \
		KERNEL_IMAGE_DTB=$$(find $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot -type f -iname \*.dtb | head -n 1); \
	fi; \
	if [ -n "$(KERNEL_IMAGE_DTB_OVERLAY)" ]; then \
		KERNEL_IMAGE_DTB_OVERLAY=$(KERNEL_OUT)/$(KERNEL_IMAGE_DTB_OVERLAY); \
	else \
		KERNEL_IMAGE_DTB_OVERLAY=$$(find $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot -type f -iname \*.dtbo | head -n 1); \
	fi; \
	[ -n "$${KERNEL_IMAGE_DTB}" ] && [ -n "$${KERNEL_IMAGE_DTB_OVERLAY}" ] && \
		ufdt_apply_overlay $${KERNEL_IMAGE_DTB} $${KERNEL_IMAGE_DTB_OVERLAY} $(KERNEL_OUT)/dtb-merged
else
	if [ -n "$(KERNEL_IMAGE_DTB)" ]; then \
		KERNEL_IMAGE_DTB=$(KERNEL_OUT)/$(KERNEL_IMAGE_DTB); \
	else \
		KERNEL_IMAGE_DTB=$$(find $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot -type f -iname \*.dtb | head -n 1); \
	fi; \
	[ -n "$${KERNEL_IMAGE_DTB}" ] && \
		cp $${KERNEL_IMAGE_DTB} $(KERNEL_OUT)/dtb-merged
endif
	cat $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/$(KERNEL_BUILD_TARGET) \
		$(KERNEL_OUT)/dtb-merged \
		> $@
else
	cp $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/$(KERNEL_BUILD_TARGET) $@
endif

out/KERNEL_OBJ/dtbo.img: out/dtb-stamp
ifeq ($(KERNEL_IMAGE_WITH_DTB_OVERLAY),1)
ifdef KERNEL_IMAGE_DTB_OVERLAY_CONFIGURATION
	mkdtboimg cfg_create $@ $(KERNEL_IMAGE_DTB_OVERLAY_CONFIGURATION) --dtb-dir $(KERNEL_OUT)/$(KERNEL_IMAGE_DTB_OVERLAY_DTB_DIRECTORY)
else
	if [ -n "$(KERNEL_IMAGE_DTB_OVERLAY)" ]; then \
		KERNEL_IMAGE_DTB_OVERLAY=$(KERNEL_OUT)/$(KERNEL_IMAGE_DTB_OVERLAY); \
	else \
		KERNEL_IMAGE_DTB_OVERLAY=$$(find $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot -type f -iname \*.dtbo | head -n 1); \
	fi; \
	[ -n "$${KERNEL_IMAGE_DTB_OVERLAY}" ] && \
		mkdtboimg create $@ $${KERNEL_IMAGE_DTB_OVERLAY}
endif
else
	touch $@
endif

out/KERNEL_OBJ/vbmeta.img:
ifeq ($(DEVICE_VBMETA_REQUIRED),1)
ifeq ($(DEVICE_VBMETA_IS_SAMSUNG),0)
	avbtool make_vbmeta_image --flags 2 --padding_size 4096 --set_hashtree_disabled_flag --output $@
else
	avbtool make_vbmeta_image --flags 0 --padding_size 4096 --set_hashtree_disabled_flag --output $@
endif
else
	touch $@
endif

out/KERNEL_OBJ/boot.img: out/KERNEL_OBJ/target-dtb
	mkbootimg \
		--kernel $(KERNEL_OUT)/target-dtb \
		--ramdisk /usr/lib/$(DEB_HOST_MULTIARCH)/halium-generic-initramfs/initrd.img-halium-generic \
		--base $(KERNEL_BOOTIMAGE_BASE_OFFSET) \
		--kernel_offset $(KERNEL_BOOTIMAGE_KERNEL_OFFSET) \
		--ramdisk_offset $(KERNEL_BOOTIMAGE_INITRAMFS_OFFSET) \
		--second_offset $(KERNEL_BOOTIMAGE_SECONDIMAGE_OFFSET) \
		--tags_offset $(KERNEL_BOOTIMAGE_TAGS_OFFSET) \
		--pagesize $(KERNEL_BOOTIMAGE_PAGE_SIZE) \
		--cmdline "$(KERNEL_BOOTIMAGE_CMDLINE)" \
		--header_version "$(KERNEL_BOOTIMAGE_VERSION)" \
		-o $@

override_dh_auto_configure: debian/control out/KERNEL_OBJ/.config path-override-prepare

override_dh_auto_build: out/KERNEL_OBJ/target-dtb out/KERNEL_OBJ/boot.img out/KERNEL_OBJ/dtbo.img out/KERNEL_OBJ/vbmeta.img out/modules-stamp out/dtb-stamp

override_dh_auto_install:
	mkdir -p $(CURDIR)/debian/linux-image-$(KERNEL_RELEASE)/boot
	$(BUILD_COMMAND) modules_install INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH=$(CURDIR)/debian/linux-image-$(KERNEL_RELEASE)
	cp -v $(KERNEL_OUT)/System.map $(CURDIR)/debian/linux-image-$(KERNEL_RELEASE)/boot/System.map-$(KERNEL_RELEASE)
	cp -v $(KERNEL_OUT)/target-dtb $(CURDIR)/debian/linux-image-$(KERNEL_RELEASE)/boot/$(KERNEL_BUILD_TARGET)-$(KERNEL_RELEASE)
	cp -v $(KERNEL_OUT)/.config $(CURDIR)/debian/linux-image-$(KERNEL_RELEASE)/boot/config-$(KERNEL_RELEASE)
	rm -f $(CURDIR)/debian/linux-image-$(KERNEL_RELEASE)/lib/modules/$(KERNEL_RELEASE)/build
	rm -f $(CURDIR)/debian/linux-image-$(KERNEL_RELEASE)/lib/modules/$(KERNEL_RELEASE)/source

	mkdir -p $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE)/boot
	cp -v $(KERNEL_OUT)/boot.img $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE)/boot/boot.img-$(KERNEL_RELEASE)
ifeq ($(KERNEL_IMAGE_WITH_DTB_OVERLAY),1)
	cp -v $(KERNEL_OUT)/dtbo.img $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE)/boot/dtbo.img-$(KERNEL_RELEASE)
endif

ifeq ($(DEVICE_VBMETA_REQUIRED),1)
	cp -v $(KERNEL_OUT)/vbmeta.img $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE)/boot/vbmeta.img-$(KERNEL_RELEASE)
endif

	# Generate flash-bootimage settings
	mkdir -p $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE)/lib/flash-bootimage
ifeq ($(FLASH_ENABLED), 1)

	# Install postinst (perhaps this isn't the best place)
	sed -e "s|@KERNEL_RELEASE@|$(KERNEL_RELEASE)|g" \
		/usr/share/linux-packaging-snippets/linux-bootimage.postinst.in \
			> $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE).postinst
	chmod +x $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE).postinst

	sed -e "s|@KERNEL_BASE_VERSION@|$(KERNEL_BASE_VERSION)|g" \
		-e "s|@VARIANT@|$(VARIANT)|g" \
		-e "s|@FLASH_INFO_MANUFACTURER@|$(FLASH_INFO_MANUFACTURER)|g" \
		-e "s|@FLASH_INFO_MODEL@|$(FLASH_INFO_MODEL)|g" \
		-e "s|@FLASH_INFO_CPU@|$(FLASH_INFO_CPU)|g" \
		/usr/share/linux-packaging-snippets/flash-bootimage-template.in \
			> $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE)/lib/flash-bootimage/$(KERNEL_RELEASE).conf
else
	echo "FLASH_ENABLED=no" \
		> $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE)/lib/flash-bootimage/$(KERNEL_RELEASE).conf
endif

	# Handle legacy devices
ifeq ($(FLASH_IS_LEGACY_DEVICE), 1)
	cat /usr/share/linux-packaging-snippets/flash-bootimage-template-legacy-extend.in \
		>> $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE)/lib/flash-bootimage/$(KERNEL_RELEASE).conf
endif

	# Handle aonly devices
ifeq ($(FLASH_IS_AONLY), 1)
	cat /usr/share/linux-packaging-snippets/flash-bootimage-template-aonly-extend.in \
		>> $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE)/lib/flash-bootimage/$(KERNEL_RELEASE).conf
endif

	# Disable DTB Overlay flashing if this kernel doesn't support it
	# Use shell features to check
	if [ "$(KERNEL_IMAGE_WITH_DTB_OVERLAY)" != "1" ] || [ "$(KERNEL_IMAGE_WITH_DTB_OVERLAY_IN_KERNEL)" = "1" ]; then \
		cat /usr/share/linux-packaging-snippets/flash-bootimage-template-no-dtbo-extend.in \
			>> $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE)/lib/flash-bootimage/$(KERNEL_RELEASE).conf; \
	fi

	# Disable VBMETA flashing if we don't supply any
	# Use shell features to check
	if [ "$(DEVICE_VBMETA_REQUIRED)" != "1" ]; then \
		cat /usr/share/linux-packaging-snippets/flash-bootimage-template-no-vbmeta.in \
			>> $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE)/lib/flash-bootimage/$(KERNEL_RELEASE).conf; \
	fi

	mkdir -p $(CURDIR)/debian/linux-headers-$(KERNEL_RELEASE)/lib/modules/$(KERNEL_RELEASE)
	/usr/share/linux-packaging-snippets/extract_headers.sh $(KERNEL_RELEASE) $(CURDIR) $(KERNEL_OUT) $(CURDIR)/debian/linux-headers-$(KERNEL_RELEASE) $(KERNEL_ARCH)

override_dh_auto_clean:
	rm -rf $(OUT)
	rm -rf debian/path-override
	rm -rf include/config/
	rm -f debian/linux-*.postinst
	dh_clean

override_dh_strip:

.PHONY: path-override-prepare
