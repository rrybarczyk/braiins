# Copyright (C) 2020  Braiins Systems s.r.o.
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

include $(TOPDIR)/rules.mk

PKG_NAME:=bos_autoupgrade
PKG_RELEASE:=1

PKG_MAINTAINER:=Braiins <braiins@braiins.com>

include $(INCLUDE_DIR)/package.mk

define Package/bos_autoupgrade
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Automatic checking and installation of latest upgrades
  DEPENDS:=+bos_config +at +@BUSYBOX_CONFIG_ASH_RANDOM_SUPPORT
endef

define Package/bos_autoupgrade/description
 Periodically calls opkg update to get latest packages.
endef

define Build/Compile
endef

define Package/bos_autoupgrade/install
	$(INSTALL_DIR) $(1)/etc/crontabs

	$(INSTALL_DIR) $(1)/usr/sbin/
	$(INSTALL_BIN) ./files/bos_upgrade_at.sh $(1)/usr/sbin/bos_upgrade_at

	$(INSTALL_DIR) $(1)/usr/sbin/
	$(INSTALL_BIN) ./files/bos_autoupgrade.sh $(1)/usr/sbin/bos_autoupgrade

	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) ./files/bos_autoupgrade.init $(1)/etc/init.d/bos_autoupgrade

	$(INSTALL_DIR) $(1)/etc/profile.d/
	$(INSTALL_BIN) ./files/bos_autoupgrade.profile $(1)/etc/profile.d/bos_autoupgrade.sh
endef

define Package/bos_autoupgrade/preinst
#!/bin/sh

echo "0 0 * * * /usr/sbin/bos_upgrade_at 2>&1 | logger -t upgrade" >> $${IPKG_INSTROOT}/etc/crontabs/root
endef

define Package/bos_autoupgrade/postrm
#!/bin/sh

sed -i '/usr/sbin/bos_upgrade_at/d' /etc/crontabs/root
/etc/init.d/cron restart
endef

$(eval $(call BuildPackage,bos_autoupgrade))
