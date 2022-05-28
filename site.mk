##	gluon site.mk makefile example

##	GLUON_FEATURES
#		Specify Gluon features/packages to enable;
#		Gluon will automatically enable a set of packages
#		depending on the combination of features listed

GLUON_FEATURES := \
	autoupdater \
	mesh-olsrd \
	respondd \
	status-page \
	web-advanced \
	web-wizard \
	web-admin \
	web-private-wifi \
	web-private-ap \
	web-logging \
	authorized-keys \
	config-mode-core

##	GLUON_SITE_PACKAGES
#		Specify additional Gluon/OpenWrt packages to include here;
#		A minus sign may be prepended to remove a packages from the
#		selection that would be enabled by default or due to the
#		chosen feature flags

GLUON_SITE_PACKAGES := iwinfo mtr-nojson iperf3 -batman-adv tcpdump \
  ffgraz-ddhcpd-nextnode ffgraz-mesh-olsr12-openvpn \
  ffgraz-static-ip ffgraz-web-static-ip \
  ffgraz-manman-sync ffgraz-config-mode-manman-sync \
  ffgraz-config-mode-theme-funkfeuer -gluon-config-mode-theme \
  ffgraz-config-mode-at-runtime \
  ffgraz-migrations \
	ffgraz-mesh-vpn-openvpn ffgraz-web-mesh-vpn-openvpn

##	DEFAULT_GLUON_RELEASE
#		version string to use for images
#		gluon relies on
#			opkg compare-versions "$1" '>>' "$2"
#		to decide if a version is newer or not.

DEFAULT_GLUON_RELEASE := 0.0+exp$(shell date '+%Y%m%d')

# Variables set with ?= can be overwritten from the command line

##	GLUON_RELEASE
#		call make with custom GLUON_RELEASE flag, to use your own release version scheme.
#		e.g.:
#			$ make images GLUON_RELEASE=23.42+5
#		would generate images named like this:
#			gluon-ff%site_code%-23.42+5-%router_model%.bin

GLUON_RELEASE ?= $(DEFAULT_GLUON_RELEASE)

# Default priority for updates.
GLUON_PRIORITY ?= 0

# Region code required for some images; supported values: us eu
GLUON_REGION ?= eu

# Languages to include
GLUON_LANGS ?= en de

# Do not build images for deprecated devices
GLUON_DEPRECATED ?= 0
