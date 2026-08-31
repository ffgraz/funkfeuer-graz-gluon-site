include $(TOPDIR)/rules.mk

PKG_NAME:=ffgraz-config-mode-gluon-provisioning
PKG_VERSION:=1

include $(TOPDIR)/../package/gluon.mk

define Package/ffgraz-config-mode-gluon-provisioning
  TITLE:=Provision node addresses from a gluon-provisioning server
  DEPENDS:=+gluon-config-mode-core +ffgraz-gluon-provisioning
endef

$(eval $(call BuildPackageGluon,ffgraz-config-mode-gluon-provisioning))
