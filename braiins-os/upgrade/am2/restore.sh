#!/bin/sh

# Copyright (C) 2019  Braiins Systems s.r.o.
#
# This file is part of Braiins Open-Source Initiative (BOSI).
#
# BOSI is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# Please, keep in mind that we may also license BOSI or any part thereof
# under a proprietary license. For more information on the terms and conditions
# of such proprietary license or if you have any other questions, please
# contact us at opensource@braiins.com.

# The script expects following setting of MTD partitions:
# recovery_mtdparts=mtdparts=pl35x-nand:40m(BOOT.bin-env-dts-kernel),32m(ramfs),8m(configs),16m(reserve),32m(ramfs-bak),128m(reserve1)

set -e

# write all images to NAND
mtd -e BOOT.bin-env-dts-kernel write ./BOOT.bin BOOT.bin-env-dts-kernel
mtd -np 0x1A00000 write ./devicetree.dtb BOOT.bin-env-dts-kernel
mtd -np 0x2000000 write ./uImage BOOT.bin-env-dts-kernel

mtd -e ramfs-bak write ./uramdisk.image.gz ramfs
mtd -e ramfs-bak write ./uramdisk.image.gz ramfs-bak

mtd erase configs
mtd erase reserve
mtd erase reserve1
sync

ubiformat /dev/mtd2
ubiattach -p /dev/mtd2
ubimkvol /dev/ubi0 -N configs -m
ubiupdatevol -t /dev/ubi0_0

mount -t ubifs ubi0:configs /mnt

# restore configuration
tar xvzf ./config.tar.gz
mv ./config/* /mnt/

umount /mnt
ubidetach -p /dev/mtd2

# format partition with nvdata
ubiformat /dev/mtd5
ubiattach -p /dev/mtd5
ubimkvol /dev/ubi0 -N reserve1 -m
ubiupdatevol -t /dev/ubi0_0
ubidetach -p /dev/mtd5

sync
