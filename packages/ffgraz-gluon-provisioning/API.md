# gluon-provisioning API

The node talks to a *gluon-provisioning server*. Server base URLs come from the
site config (`provisioning.api`, a list of mirrors); the node shuffles the list
and uses the first mirror that answers.

Authentication is a per-node token, stored in
`uci get gluon-provisioning.provisioning.token` and entered by the user in the
config mode wizard or via `gluon-provisioning enable <token>`. The token
identifies the node — it replaces the node id and node name a node used to be
configured with.

A device has exactly one, and the server hands out another only by rotating,
which revokes the old one at once: a node still carrying the old token is
refused until the new one is put on it. The uci file it lives in is a conffile,
so a sysupgrade leaves it alone.

Requests are made with `uclient-fetch`, so the node needs no HTTP client library.

Setting `GLUON_PROVISIONING_API` in the environment replaces the site's mirror
list with that one server, for testing against a local one:

```sh
GLUON_PROVISIONING_API=http://10.0.2.2:8080 gluon-provisioning force_provision
```

`tests/lib/provisioning_server.py` is a runnable sample server (stdlib only)
that hands out a random token and random node info, and prints the uci commands
to point a node at it:

```sh
python3 tests/lib/provisioning_server.py --port 8080
```

`tests/gluon_provisioning.py` drives the whole flow against it on a booted
node; `tests/provision_test.lua` checks the response handling on its own
(`lua tests/provision_test.lua`, no node needed).

## What a node is given

A node carries one address of its own per family, both on `loopback`
(`ffgraz-static-ip`). It no longer carries an address per mesh interface: olsrd6
and babel mesh on the node address, and a per-interface address only gave the
node more identities than it has.

Besides that it may carry

* a **link network** per interface in the `link` role — the `/30` transit to the
  device bridging this node to another one, and
* a range for its **exposed** network, where it has ports in that role.

Both come from `ffgraz-extra-networks`.

## POST /provision

### Request

Headers:

```
Content-Type: application/json
Authorization: Bearer <token>
```

Body:

```json
{
  "primary_mac": "d8:84:66:4f:fe:01",
  "node_id": "d884664ffe01",
  "model": "Extreme Networks WS-AP3805i",
  "board_name": "extreme-networks,ws-ap3805i",
  "networks": ["private", "exposed"],
  "links": [
    { "section": "iface_eth0_vlan10", "device": "eth0.10", "current": "10.13.208.0/30" }
  ]
}
```

| Field | Meaning |
| --- | --- |
| `primary_mac` | The node's primary MAC (`gluon.sysconfig.primary_mac`). |
| `node_id` | `primary_mac` without the colons — Gluon's node id. |
| `model` | The board's pretty name, from `ubus call system board`. |
| `board_name` | The board id from the same place, e.g. `extreme-networks,ws-ap3805i`. It names the vendor before the comma. |
| `networks` | The extra networks this hardware has ports for — the names from `extranets.NETWORKS` whose role has at least one interface. A node with no `exposed` ports does not ask for a range for one. |
| `links` | One entry per interface in the `link` role, from `extranets.links()`. |
| `links[].section` | The uci section the link lives in. This is what the answer is keyed by. |
| `links[].device` | The interface the role was given to, e.g. `eth0.10`. |
| `links[].current` | The `/30` the node carries for it now, or `null`. |

A link is named by its section and its device rather than by the positional
`lnk<n>` name, which only means anything inside one run of `extranets.links()`.

### Response

```json
{
  "ok": true,
  "location_name": "schlossberg",
  "node_name": "nord",
  "contact": "admin@example.org",
  "latitude": 47.0755,
  "longitude": 15.437,
  "mesh_vpn": true,
  "loopback": { "ip4": "10.13.0.1", "ip6": "2001:470:75c5::da84:66ff:fe4f:fe01" },
  "networks": { "exposed": { "prefix4": "10.13.230.8/29",
                             "prefix6": "2001:470:75c5:2::/64" } },
  "links": { "iface_eth0_vlan10": { "linknet": "10.13.208.4/30" } }
}
```

| Field | Meaning |
| --- | --- |
| `ok` | `false` means nothing is applied; the node logs `error` and exits non-zero. |
| `error` | Human readable reason, only meaningful when `ok` is `false`. |
| `location_name` | Name of the location the token belongs to. Optional. |
| `node_name` | Name of this node within the location. Optional — a location with a single node need not name it. |
| `contact` | Owner contact, written to `gluon-node-info`. Optional. |
| `latitude`, `longitude` | Node coordinates. Optional, but only applied when both are present; setting them also turns on location sharing. |
| `mesh_vpn` | Whether the node should tunnel. Optional: with the field absent the node leaves `gluon.mesh_vpn.enabled` exactly as the operator set it. |
| `loopback.ip4`, `loopback.ip6` | The node's own addresses, **without a prefix** — `310-static-ip` puts them on loopback as `/32` and `/128`. Either may be absent. A prefix sent anyway is dropped, since it would describe the server's pool rather than this node. |
| `networks.<name>.prefix4`, `.prefix6` | The **whole range** for that network, with its prefix length. |
| `links.<section>.linknet` | The **whole `/30`** for that link. |

Ranges rather than finished addresses: the node takes the first address of the
range itself, so "the node's address in it" is decided in one place. On a link
that is `minhost`, and the device on the far end takes `maxhost` — exactly what
`extranets.link_hosts` already defines.

### What the node does with it

The node's hostname becomes `<location_name>-<node_name>`, or just
`<location_name>` when the response carries no `node_name` (and just
`<node_name>` when it carries no `location_name`). Both names are also kept in
UCI and announced over respondd as `nodeinfo.provisioning`.

`contact`, `latitude` and `longitude` go into `gluon-node-info`.

The loopback addresses go into `gluon-static-ip.loopback.ip4` / `.ip6`, which
`ffgraz-static-ip` picks up on the next `gluon-reconfigure`.

Each `networks.<name>` range becomes `network.<name>.ipaddr` / `.ip6addr` at the
range's first address, which is what `extranets.routed4` and `.public6` need for
it to be announced to the mesh.

Each `links.<section>.linknet` becomes `gluon.<section>.linknet`, which
`115-gluon-linknets` turns into the interface and the address on it. A section
the response omits is left alone; an explicit `null` clears it.

`gluon-reconfigure` — followed by `gluon-reload` — runs only if something
actually changed.

Errors are in-band: a rejected token or an unknown node is an HTTP 200 carrying
`{"ok": false, "error": "..."}`, which the node reports and stops on. An HTTP
error status, an unreachable mirror or a non-JSON body instead makes the node
move on to the next mirror; if none answer, nothing is changed.
