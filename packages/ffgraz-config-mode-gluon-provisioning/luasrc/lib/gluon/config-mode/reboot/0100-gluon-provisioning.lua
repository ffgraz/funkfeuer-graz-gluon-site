local site_i18n = i18n 'gluon-site'

local uci = require('simple-uci').cursor()

local msg

if uci:get_bool('gluon-provisioning', 'provisioning', 'enabled') then
	msg = site_i18n._translate('gluon-config-mode:provisioning')
else
	msg = site_i18n._translate('gluon-config-mode:no-provisioning')
end

if not msg then return end

renderer.render_string(msg, {
	location_name = uci:get('gluon-provisioning', 'provisioning', 'location_name'),
	node_name = uci:get('gluon-provisioning', 'provisioning', 'node_name'),
})
