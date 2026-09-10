-- Self-check for gluon-provisioning: stubs out the node (uci, gluon libs,
-- uclient-fetch) and asserts what a canned /provision response does to uci.
-- Run with: lua tests/provision_test.lua

local dir = arg[0]:match('^(.*)/[^/]*$') or '.'
local script = dir .. '/../luasrc/usr/bin/gluon-provisioning'

-- the response the fake server hands out
local RESPONSE = [[{"ok":true,"...":"see RESPONSE_TABLE"}]]

local RESPONSE_TABLE = {
	ok = true,
	location_name = 'schlossberg', node_name = 'nord',
	contact = 'admin@example.org', latitude = 47.0755, longitude = 15.437,
	mesh_vpn = true,
	config_access = { pubkey = '-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEA\n-----END PUBLIC KEY-----\n' },
	loopback = {
		ip4 = '10.13.0.1',
		-- a prefix the server should not have sent: it describes the pool,
		-- not this node, and must be dropped rather than stored
		ip6 = '2001:470:75c5::da84:66ff:fe4f:fe01/64',
	},
	networks = {
		exposed = {
			prefix4 = '10.13.230.8/29',
			prefix6 = '2001:470:75c5:2::/64',
		},
		-- wrong family for the key: must be rejected, not written
		private = { prefix4 = '2001:db8::/64' },
	},
	links = {
		iface_eth0_vlan10 = { linknet = '10.13.208.4/30' },
		-- not a /30: must be rejected
		iface_eth0_vlan11 = { linknet = '10.13.209.0/24' },
	},
}

local FINGERPRINT = string.rep('ab', 32)
local UBUS_BOARD = 'ubus board'
local BOARD_TABLE = {
	model = 'Extreme Networks WS-AP3805i',
	board_name = 'extreme-networks,ws-ap3805i',
}

-- uci ------------------------------------------------------------------

local config = {
	['gluon-provisioning'] = { provisioning = { enabled = '1', token = 'tok3n' } },
	['gluon'] = {
		mesh_vpn = { enabled = '0' },
		iface_eth0_vlan10 = { name = 'eth0.10', role = 'link' },
		iface_eth0_vlan11 = { name = 'eth0.11', role = 'link',
			linknet = '10.13.208.0/30' },
	},
	['gluon-static-ip'] = { loopback = { ip4 = '10.12.5.208' } },
	['gluon-node-info'] = { owner = {}, location = {} },
	['gluon-config-mode-remote'] = { remote = {} },
	['network'] = { exposed = {}, private = {} },
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

local hostname = 'gluon-d884664ffe01'

package.preload['simple-uci'] = function()
	return { cursor = function() return cursor end }
end

package.preload['luci.ip'] = function()
	local function cidr(addr, len)
		local v6 = addr:find(':') ~= nil

		local self
		self = {
			is6 = function() return v6 end,
			is4 = function() return not v6 end,
			prefix = function() return len ~= '' and tonumber(len) or nil end,
			-- a host address is the address on its own
			host = function() return cidr(addr, '') end,
			-- enough of minhost for the test: the ranges it is given end in
			-- .0 or ::, so the first host is the last octet or group plus one
			minhost = function()
				if v6 then return cidr(addr:gsub('::$', '::1'), '') end
				local head, tail = addr:match('^(%d+%.%d+%.%d+%.)(%d+)$')
				return cidr(head .. tostring(tonumber(tail) + 1), '')
			end,
			string = function() return addr .. (len ~= '' and ('/' .. len) or '') end,
		}
		return self
	end

	return {
		new = function(str)
			local addr, len = tostring(str):match('^([^/]+)/?(%d*)$')
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
			if raw == UBUS_BOARD then return BOARD_TABLE end
			return RESPONSE_TABLE
		end,
	}
end

package.preload['gluon.site'] = function()
	return { provisioning = { api = function() return { 'http://provisioning.invalid' } end } }
end

package.preload['gluon.util'] = function()
	return {
		node_id = function() return 'd884664ffe01' end,
		-- exposed has a port, private does not
		get_role_interfaces = function(_, role)
			if role == 'exposed' then return { 'eth0.11' } end
			return {}
		end,
	}
end

package.preload['gluon.sysconfig'] = function()
	return { primary_mac = 'd8:84:66:4f:fe:01' }
end

package.preload['gluon.extranets'] = function()
	return {
		NETWORKS = {
			{ name = 'private', role = 'private' },
			{ name = 'exposed', role = 'exposed' },
		},
		links = function()
			return {
				{ section = 'iface_eth0_vlan10', device = 'eth0.10', cidr = nil },
				{ section = 'iface_eth0_vlan11', device = 'eth0.11',
					cidr = '10.13.208.0/30' },
			}
		end,
		linknet = function(value)
			return type(value) == 'string' and value:match('/30$') and value or nil
		end,
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
	if cmd:match('gluon%-config%-mode%-remote%-fingerprint') then
		return nil
	end
	local out = cmd:match("uclient%-fetch.* %-O '([^']+)'")
	local dump = cmd:match("^ubus call system board > '([^']+)'")
	if out or dump then
		local f = io.open(out or dump, 'w')
		f:write(out and RESPONSE or UBUS_BOARD)
		f:close()
	end
	return 0
end

local real_popen = io.popen
io.popen = function(cmd) -- luacheck: ignore
	if cmd:match('gluon%-config%-mode%-remote%-fingerprint') then
		return { read = function() return FINGERPRINT end, close = function() end }
	end
	return real_popen(cmd)
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
io.popen = real_popen -- luacheck: ignore

-- assert ---------------------------------------------------------------

local function eq(got, want, what)
	assert(got == want, string.format('%s: got %s, want %s', what, tostring(got), tostring(want)))
end

eq(exit_code, 0, 'exit status')

-- the request ----------------------------------------------------------

local request
for _, c in ipairs(commands) do
	if c:match('uclient%-fetch') then request = c end
end
assert(request, 'no request was made')
assert(request:match("Authorization: Bearer tok3n"), 'token is not sent as bearer auth')
assert(request:match('/provision'), 'wrong endpoint: ' .. request)

eq(sent.primary_mac, 'd8:84:66:4f:fe:01', 'primary_mac')
eq(sent.node_id, 'd884664ffe01', 'node_id')
eq(sent.model, 'Extreme Networks WS-AP3805i', 'model')
eq(sent.board_name, 'extreme-networks,ws-ap3805i', 'board_name')
eq(sent.tls_fingerprint, FINGERPRINT, 'the certificate fingerprint is reported')

eq(#sent.networks, 1, 'only networks with ports are asked for')
eq(sent.networks[1], 'exposed', 'exposed is asked for')

eq(#sent.links, 2, 'every link is asked for')
eq(sent.links[1].section, 'iface_eth0_vlan10', 'link section')
eq(sent.links[1].device, 'eth0.10', 'link device')
eq(sent.links[1].current, nil, 'a link with no range says so')
eq(sent.links[2].current, '10.13.208.0/30', 'a link reports what it carries')

-- the answer -----------------------------------------------------------

eq(cursor:get('gluon-static-ip', 'loopback', 'ip4'), '10.13.0.1', 'loopback v4')
eq(cursor:get('gluon-static-ip', 'loopback', 'ip6'),
	'2001:470:75c5::da84:66ff:fe4f:fe01', 'loopback v6 is stored without a prefix')

eq(cursor:get('network', 'exposed', 'ipaddr'), '10.13.230.9/29',
	'the node takes the first address of its exposed range')
eq(cursor:get('network', 'exposed', 'ip6addr'), '2001:470:75c5:2::1/64',
	'and the same on v6')
eq(cursor:get('network', 'private', 'ipaddr'), nil,
	'a v6 range under prefix4 must be rejected')

eq(cursor:get('gluon', 'iface_eth0_vlan10', 'linknet'), '10.13.208.4/30', 'linknet')
eq(cursor:get('gluon', 'iface_eth0_vlan11', 'linknet'), '10.13.208.0/30',
	'a range that is not a /30 must be rejected, leaving what was there')

eq(hostname, 'schlossberg-nord', 'hostname')
eq(cursor:get('gluon-node-info', 'owner', 'contact'), 'admin@example.org', 'contact')
eq(cursor:get('gluon-node-info', 'location', 'latitude'), 47.0755, 'latitude')
eq(cursor:get('gluon-node-info', 'location', 'share_location'), '1', 'share_location')
eq(cursor:get('gluon', 'mesh_vpn', 'enabled'), true, 'mesh vpn follows the answer')
eq(cursor:get('gluon-provisioning', 'provisioning', 'location_name'), 'schlossberg',
	'location_name')
assert(cursor:get('gluon-config-mode-remote', 'remote', 'pubkey'):match('BEGIN PUBLIC KEY'),
	'the config access key was not stored')

-- a change happened, so the node must reconfigure
local reloaded = false
for _, c in ipairs(commands) do
	if c:match('gluon%-reload') then reloaded = true end
end
assert(reloaded, 'changed config but did not reload')

print('ok')
