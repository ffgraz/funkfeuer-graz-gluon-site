# gluon-provisioning API

The node talks to a *gluon-provisioning server*. Server base URLs come from the
site config (`provisioning.api`, a list of mirrors); the node shuffles the list
and uses the first mirror that answers.

Authentication is a per-node token, stored in
`uci get gluon-provisioning.provisioning.token` and entered by the user in the
config mode wizard or via `gluon-provisioning enable <token>`. The token
identifies the node — it replaces the node id and node name a node used to be
configured with.

Requests are made with `uclient-fetch`, so the node needs no HTTP client library.

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
  "primary_mac": "e2:1a:c1:00:11:22",
  "node_id": "e21ac1001122",
  "interfaces": {
    "loopback":     { "requested_type": 6 },
    "mesh_radio0":  { "requested_type": 4, "mac": "e2:1a:c1:00:11:24" },
    "mesh_uplink":  { "requested_type": 4, "mac": "e2:1a:c1:00:11:2a" },
    "mesh_vpn":     { "requested_type": 4, "mac": "e2:1a:c1:00:11:27" }
  }
}
```

| Field | Meaning |
| --- | --- |
| `primary_mac` | The node's primary MAC (`gluon.sysconfig.primary_mac`). |
| `node_id` | `primary_mac` without the colons — Gluon's node id. |
| `interfaces` | The interfaces the node wants an address for, keyed by the Gluon network/UCI interface name. |
| `interfaces.*.requested_type` | `4` or `6` — the address family requested for that interface. |
| `interfaces.*.mac` | The interface's MAC, when it has one. Omitted otherwise. |

Which interfaces are sent:

* `loopback` — always, `requested_type: 6`. This is the node's IPv6 address.
* every mesh interface that exists and is not disabled — `requested_type: 4`.
  That is `mesh_<radio>`, `p2p_<radio>` and `ibss_<radio>` for each enabled
  radio, plus `mesh_uplink` and `mesh_other`.
* `mesh_vpn`, whenever the interface exists — also when the mesh VPN is
  currently off, because the answer is what decides whether it gets turned on.

A server may answer for a subset; interfaces it omits are left untouched.

### Response

```json
{
  "ok": true,
  "location_name": "Schlossberg",
  "node_name": "nord",
  "contact": "admin@example.org",
  "latitude": 47.0755,
  "longitude": 15.4370,
  "interfaces": {
    "loopback":    { "ip": "2001:470:75c5:23::42/64" },
    "mesh_radio0": { "ip": "10.12.34.56/16" }
  }
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
| `interfaces.*.ip` | The address to configure, **with prefix length**. Must match the `requested_type` that was asked for; a mismatched family is rejected and logged. |

The prefix length matters: it ends up verbatim in `network.<iface>.ipaddr` /
`ip6addr`, so a `/32` on a mesh interface breaks OLSR broadcasts. Hand out the
mesh prefix length (`/16` for ffgraz).

### What the node does with it

The node's hostname becomes `<location_name>-<node_name>`, or just
`<location_name>` when the response carries no `node_name` (and just
`<node_name>` when it carries no `location_name`). Both names are also kept in
UCI and announced over respondd as `nodeinfo.provisioning`.

`contact`, `latitude` and `longitude` go into `gluon-node-info`.

The mesh VPN is switched on exactly when the response provisions an address for
`mesh_vpn`, and off when it does not — so a server that wants a node to tunnel
answers for `mesh_vpn`, and one that does not, omits it.

For each answered interface the address is written to
`gluon-static-ip.<interface>.ip4` (or `.ip6` for `requested_type: 6`) and
committed. `ffgraz-static-ip` picks it up from there on the next
`gluon-reconfigure`, which the node runs — followed by `gluon-reload` — only if
something actually changed.

An HTTP error, an unreachable mirror or a non-JSON body makes the node move on
to the next mirror; if none answer, nothing is changed.
