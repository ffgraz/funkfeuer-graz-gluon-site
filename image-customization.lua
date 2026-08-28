-- ported from the GLUON_FEATURES / GLUON_SITE_PACKAGES of this site's site.mk,
-- which the current gluon no longer reads

features {
	'logging',
	'autoupdater',
	'mesh-babel',
	'mesh-olsrd',
	'respondd',
	'status-page',
	'web-advanced',
	'web-wizard',
	'web-admin',
	'web-private-wifi',
	'web-logging',
	'authorized-keys',
	'config-mode-core',
}

packages {
	'-batman-adv',
	'ffgraz-static-ip', 'ffgraz-web-static-ip',
	'ffgraz-manman-sync', 'ffgraz-config-mode-manman-sync',
	'ffgraz-config-mode-theme-funkfeuer', '-gluon-config-mode-theme',
	'ffgraz-private-ap', 'ffgraz-web-private-ap',
	'ffgraz-migrations',
	'ffgraz-ddhcpd-nextnode',
	'ffgraz-ddhcpd',
	'ffgraz-monitor-and-reboot',
	'ffgraz-blink',
	'ffgraz-olsr-auto-restart',
	'ffda-gluon-usteer',
	'ffac-weeklyreboot',
	'ffac-ssid-changer',
}

if device_class('standard') then
	packages {
		'iwinfo', 'mtr-nojson', 'iperf3',
		'ffgraz-config-mode-at-runtime', 'ffgraz-config-mode-remote',
		'ffgraz-mesh-vpn-openvpn', 'ffgraz-web-mesh-vpn-openvpn', 'ffgraz-mesh-olsr12-openvpn',
	}
end

if device_class('p2p') then
	features {'p2p-support'}

	packages {
		'iwinfo', 'mtr-nojson', 'iperf3',
		'ffgraz-config-mode-at-runtime', 'ffgraz-config-mode-remote',
	}
end

if device_class('big') then
	features {'wireless-encryption-wpa3-openssl', 'p2p-support'}

	packages {
		'iwinfo', 'mtr-nojson', 'tcpdump', 'iperf3', 'horst',
		'ffgraz-config-mode-at-runtime', 'ffgraz-config-mode-remote',
		'ffgraz-olsr-public-ip', 'ffgraz-web-olsr-public-ip',
		'ffgraz-mesh-vpn-openvpn', 'ffgraz-web-mesh-vpn-openvpn', 'ffgraz-mesh-olsr12-openvpn',
		'ffgraz-yggdrasil',
	}
end
