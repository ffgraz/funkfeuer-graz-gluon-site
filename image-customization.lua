-- ported from the GLUON_FEATURES / GLUON_SITE_PACKAGES of this site's site.mk,
-- which the current gluon no longer reads

features {
	'logging',
	'autoupdater',
	'mesh-babel',
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
	'ffgraz-gluon-provisioning', 'ffgraz-config-mode-gluon-provisioning',
	'ffgraz-config-mode-theme-funkfeuer', '-gluon-config-mode-theme',
	'ffgraz-private-ap', 'ffgraz-web-private-ap',
	'ffgraz-migrations',
	'ffgraz-ddhcpd-nextnode',
	'ffgraz-ddhcpd',
	'ffgraz-monitor-and-reboot',
	'ffgraz-blink',
	'ffda-gluon-usteer',
	'ffac-weeklyreboot',
	'ffac-ssid-changer',
}

-- The small-flash devices have no room for olsr on top of babel once the rest
-- of the image is in, so they mesh with babel alone. Everything else keeps
-- both.
if not (device_class('tiny') or device_class('p2p-tiny')) then
	features {'mesh-olsrd'}

	packages {
		'ffgraz-olsr-auto-restart',
	}
end

-- p2p-tiny is a p2p device on small flash: it needs to mesh point to point,
-- but the tp-link safeloader models cap the filesystem partition well below
-- their nominal flash size, so it gets none of the p2p diagnostic extras.
if device_class('p2p') or device_class('p2p-tiny') then
	features {'p2p-support'}
end

if device_class('standard') then
	packages {
		'iwinfo', 'mtr-nojson', 'iperf3',
		'ffgraz-config-mode-at-runtime', 'ffgraz-config-mode-remote',
		'ffgraz-mesh-vpn-openvpn', 'ffgraz-web-mesh-vpn-openvpn', 'ffgraz-mesh-olsr12-openvpn',
	}
end

if device_class('p2p') then
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
