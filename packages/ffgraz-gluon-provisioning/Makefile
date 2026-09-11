include $(TOPDIR)/rules.mk

PKG_NAME:=ffgraz-gluon-provisioning
PKG_VERSION:=1

include $(TOPDIR)/../package/gluon.mk

define Package/ffgraz-gluon-provisioning
  DEPENDS:=+gluon-core +gluon-node-info +ffgraz-extra-networks +micrond +luci-lib-ip +luci-lib-jsonc +uclient-fetch
  TITLE:=Provision node addresses from a gluon-provisioning server
endef

# The token a node provisions itself with lives here, and there is one per
# device - so losing it means an operator has to rotate it and put the new one
# on the node by hand. Package files are only kept over a sysupgrade when they
# are conffiles, and this one is shipped by this package.
define Package/ffgraz-gluon-provisioning/conffiles
/etc/config/gluon-provisioning
endef

$(eval $(call BuildPackageGluon,ffgraz-gluon-provisioning))
