return function(form, uci)
	local pkg_i18n = i18n 'gluon-config-mode-gluon-provisioning'

	local msg = pkg_i18n.translate(
		'Provision this node by entering the token you were given.<br>' ..
		'This will automatically keep the node addresses in sync with ' ..
		'the values assigned by the provisioning server.'
	)

	local s = form:section(Section, nil, msg)

	local enabled = s:option(Flag, 'provisioning', pkg_i18n.translate('Enable provisioning'))
	enabled.default = uci:get_bool('gluon-provisioning', 'provisioning', 'enabled')
	function enabled:write(data)
		uci:set('gluon-provisioning', 'provisioning', 'enabled', data)
	end

	local token = s:option(Value, 'provisioning_token', pkg_i18n.translate('Provisioning token'))
	token:depends(enabled, true)
	token.default = uci:get('gluon-provisioning', 'provisioning', 'token')
	token.datatype = 'maxlength(128)'
	function token:write(data)
		uci:set('gluon-provisioning', 'provisioning', 'token', data)
	end

	function s:write()
		uci:save('gluon-provisioning')
	end
end
