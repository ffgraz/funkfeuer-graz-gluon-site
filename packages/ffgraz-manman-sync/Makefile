include $(TOPDIR)/rules.mk

PKG_NAME:=ffgraz-manman-sync
PKG_VERSION:=1

include $(TOPDIR)/../package/gluon.mk

define Package/ffgraz-manman-sync
  DEPENDS:=+gluon-core +micrond +luci-lib-ip +luci-lib-httpclient +lua-ecdsa
  TITLE:=Sync configuration with data from manman
endef

define Package/ffgraz-manman-sync/install
	$(Gluon/Build/Install)

	# httpclient depends on util depends on template.parser & sys.zoneinfo which is from +luci-base
	# +luci-base is quite big and unnesesarry. stubbing the files is enough to make it work.
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/template
	touch $(1)/usr/lib/lua/luci/template/parser.lua
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/sys
	touch $(1)/usr/lib/lua/luci/sys/zoneinfo.lua
endef

$(eval $(call BuildPackageGluon,ffgraz-manman-sync))
