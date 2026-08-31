include $(TOPDIR)/rules.mk

PKG_NAME:=ffgraz-gluon-provisioning
PKG_VERSION:=1

include $(TOPDIR)/../package/gluon.mk

define Package/ffgraz-gluon-provisioning
  DEPENDS:=+gluon-core +gluon-node-info +micrond +luci-lib-ip +luci-lib-jsonc +uclient-fetch
  TITLE:=Provision node addresses from a gluon-provisioning server
endef

$(eval $(call BuildPackageGluon,ffgraz-gluon-provisioning))
