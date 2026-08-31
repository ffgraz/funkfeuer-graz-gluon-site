-- Self-check for gluon-provisioning: stubs out the node (uci, gluon libs,
-- uclient-fetch) and asserts what a canned /provision response does to uci.
-- Run with: lua tests/provision_test.lua

local dir = arg[0]:match('^(.*)/[^/]*$') or '.'
local script = dir .. '/../luasrc/usr/bin/gluon-provisioning'

-- the response the fake server hands out
local RESPONSE = [[{"ok":true,
	"location_name":"schlossberg","node_name":"nord",
	"contact":"admin@example.org","latitude":47.0755,"longitude":15.437,
	"interfaces":{
		"loopback":{"ip":"2001:470:75c5:23::42/64"},
		"mesh_radio0":{"ip":"10.12.34.56/16"},
		"mesh_uplink":{"ip":"2001:db8::1/64"}
	}}]]

local RESPONSE_TABLE = {
	ok = true,
	location_name = 'schlossberg', node_name = 'nord',
	contact = 'admin@example.org', latitude = 47.0755, longitude = 15.437,
	interfaces = {
		loopback = { ip = '2001:470:75c5:23::42/64' },
		mesh_radio0 = { ip = '10.12.34.56/16' },
		-- wrong family for a requested_type 4 interface: must be rejected
		mesh_uplink = { ip = '2001:db8::1/64' },
		-- mesh_vpn deliberately absent: the vpn must end up off
	},
}

-- what netifd reports: a device for the interfaces that are up, none for
-- ibss_radio0 and mesh_vpn, which are configured but down
local UBUS_DUMP = 'ubus dump'
local UBUS_TABLE = {
	interface = {
		{ interface = 'loopback', l3_device = 'lo' },
		{ interface = 'mesh_radio0', l3_device = 'wlan0' },
		{ interface = 'mesh_uplink', l3_device = 'm_uplink' },
		{ interface = 'ibss_radio0' },
		{ interface = 'mesh_vpn' },
	},
}

-- uci ------------------------------------------------------------------

local config = {
	['gluon-provisioning'] = { provisioning = { enabled = '1', token = 'tok3n' } },
	['gluon'] = { mesh_vpn = { enabled = '1' } },
	['gluon-static-ip'] = { mesh_radio0 = { ip4 = '10.12.0.1/16' } },
	['gluon-node-info'] = { owner = {}, location = {} },
	['network'] = {
		loopback = { proto = 'static' },
		mesh_radio0 = { proto = 'static' },
		mesh_uplink = { proto = 'static' },
		mesh_other = { proto = 'static', disabled = '1' },
		-- configured and enabled, but netifd has no device for it
		ibss_radio0 = { proto = 'static' },
		-- no device either, but exempt: the vpn is asked for regardless
		mesh_vpn = { proto = 'static' },
	},
	['wireless'] = { mesh_radio0 = { macaddr = 'e2:1a:c1:00:11:24' } },
}

local cursor = {}
function cursor:get(c, s, o)
	local sec = config[c] and config[c][s]
	if not sec then return nil end
	return sec[o]
end
function cursor:get_bool(c, s, o)
	local v = self:get(c, s, o)
	return v == '1' or v == true
end
function cursor:set(c, s, o, v)
	config[c] = config[c] or {}
	config[c][s] = config[c][s] or {}
	config[c][s][o] = v
end
function cursor:save() end
-- gluon-node-info sections are looked up by type; in this stub they are named
-- after their type
function cursor:get_first(c, t)
	return config[c] and config[c][t] and t or nil
end

-- stubs ----------------------------------------------------------------

local hostname = 'gluon-e21ac1001122'

package.preload['simple-uci'] = function()
	return { cursor = function() return cursor end }
end

package.preload['luci.ip'] = function()
	local function cidr(addr, len)
		local v6 = addr:find(':') ~= nil
		return {
			is6 = function() return v6 end,
			-- a host address is the address on its own
			host = function() return cidr(addr, '') end,
			string = function() return addr .. (len ~= '' and ('/' .. len) or '') end,
		}
	end

	return {
		new = function(str)
			local addr, len = str:match('^([^/]+)/?(%d*)$')
			if not addr then return nil end
			return cidr(addr, len)
		end,
	}
end

local sent -- the request table, captured instead of encoded
package.preload['luci.jsonc'] = function()
	return {
		stringify = function(t) sent = t; return RESPONSE end,
		parse = function(raw)
			if raw == UBUS_DUMP then return UBUS_TABLE end
			return RESPONSE_TABLE
		end,
	}
end

package.preload['gluon.site'] = function()
	return { provisioning = { api = function() return { 'http://provisioning.invalid' } end } }
end

package.preload['gluon.util'] = function()
	return { node_id = function() return 'e21ac1001122' end }
end

package.preload['gluon.sysconfig'] = function()
	return { primary_mac = 'e2:1a:c1:00:11:22' }
end

package.preload['gluon.wireless'] = function()
	return {
		foreach_radio = function(_, fn) fn({ ['.name'] = 'radio0' }, 1, {}) end,
	}
end

package.preload['pretty_hostname'] = function()
	return {
		get = function() return hostname end,
		set = function(_, name) hostname = name end,
	}
end

-- fake uclient-fetch: writes the canned response to the -O target
local real_execute = os.execute
local commands = {}
os.execute = function(cmd) -- luacheck: ignore
	table.insert(commands, cmd)
	local out = cmd:match("uclient%-fetch.* %-O '([^']+)'")
	local dump = cmd:match("^ubus call network%.interface dump > '([^']+)'")
	if out or dump then
		local f = io.open(out or dump, 'w')
		f:write(out and RESPONSE or UBUS_DUMP)
		f:close()
	end
	return 0
end

-- run ------------------------------------------------------------------

-- the script exits with the command's status; exec_cmd is its last
-- statement, so returning from a stubbed exit is the same as falling off
-- the end
local real_exit, exit_code = os.exit
os.exit = function(code) exit_code = code end -- luacheck: ignore

arg = { [0] = 'gluon-provisioning', 'force_provision' }
assert(loadfile(script))()

os.execute = real_execute -- luacheck: ignore
os.exit = real_exit -- luacheck: ignore

-- assert ---------------------------------------------------------------

local function eq(got, want, what)
	assert(got == want, string.format('%s: got %s, want %s', what, tostring(got), tostring(want)))
end

eq(exit_code, 0, 'exit status')

local request
for _, c in ipairs(commands) do
	if c:match('uclient%-fetch') then request = c end
end
assert(request, 'no request was made')
assert(request:match("Authorization: Bearer tok3n"), 'token is not sent as bearer auth')
assert(request:match('/provision'), 'wrong endpoint: ' .. request)

eq(sent.primary_mac, 'e2:1a:c1:00:11:22', 'primary_mac')
eq(sent.node_id, 'e21ac1001122', 'node_id')
eq(sent.interfaces.loopback.requested_type, 6, 'loopback asks for v6')
eq(sent.interfaces.loopback.type, 'loopback', 'loopback type')
eq(sent.interfaces.mesh_radio0.requested_type, 4, 'mesh asks for v4')
eq(sent.interfaces.mesh_radio0.type, 'wifi', 'wifi type')
eq(sent.interfaces.mesh_radio0.mac, 'e2:1a:c1:00:11:24', 'wifi mac')
eq(sent.interfaces.mesh_uplink.type, 'ethernet', 'ethernet type')
eq(sent.interfaces.mesh_other, nil, 'disabled interface is not requested')
eq(sent.interfaces.ibss_radio0, nil, 'interface without a device is not requested')
assert(sent.interfaces.mesh_vpn, 'the mesh vpn is asked for even with no device')
eq(sent.interfaces.mesh_vpn.requested_type, 4, 'mesh vpn asks for v4')
eq(sent.interfaces.mesh_vpn.type, 'vpn', 'mesh vpn type')

eq(cursor:get('gluon-static-ip', 'mesh_radio0', 'ip4'), '10.12.34.56/16', 'mesh v4 address')
eq(cursor:get('gluon-static-ip', 'loopback', 'ip6'), '2001:470:75c5:23::42',
	'loopback v6 address is stored without the pool prefix')
eq(cursor:get('gluon-static-ip', 'mesh_uplink', 'ip4'), nil, 'v6 answer to a v4 request must be rejected')
eq(cursor:get('gluon-static-ip', 'mesh_other', 'ip4'), nil, 'disabled interface must not be provisioned')

eq(hostname, 'schlossberg-nord', 'hostname')
eq(cursor:get('gluon-node-info', 'owner', 'contact'), 'admin@example.org', 'contact')
eq(cursor:get('gluon-node-info', 'location', 'latitude'), 47.0755, 'latitude')
eq(cursor:get('gluon-node-info', 'location', 'share_location'), '1', 'share_location')
eq(cursor:get('gluon', 'mesh_vpn', 'enabled'), false, 'mesh vpn off when not provisioned')
eq(cursor:get('gluon-provisioning', 'provisioning', 'location_name'), 'schlossberg', 'location_name')

-- a change happened, so the node must reconfigure
local reloaded = false
for _, c in ipairs(commands) do
	if c:match('gluon%-reload') then reloaded = true end
end
assert(reloaded, 'changed config but did not reload')

print('ok')
