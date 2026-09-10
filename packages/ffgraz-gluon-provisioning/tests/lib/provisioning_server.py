#!/usr/bin/env python3
"""A sample gluon-provisioning server, stdlib only.

It speaks the API described in ../../API.md: it generates one random
token and a random set of node info, and hands every node that presents
that token its own addresses, a range for each extra network it has
ports for, and a /30 for each of its links.

Run it by hand and point a node at it:

    python3 provisioning_server.py --port 8080
    # on the node:
    uci set gluon-provisioning.provisioning.token=<the printed token>
    GLUON_PROVISIONING_API=http://10.0.2.2:8080 gluon-provisioning force_provision

Or drive it from a test, where it also records what the node sent:

    server = ProvisioningServer()
    server.start()
    ...  # server.token, server.port, server.requests
    server.stop()
"""

import argparse
import ipaddress
import json
import random
import secrets
import threading

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

#: Made-up place and node names, so a run looks like the real thing.
LOCATIONS = ('schlossberg', 'lend', 'gries', 'jakomini', 'eggenberg',
             'geidorf', 'waltendorf', 'ries', 'plabutsch', 'murinsel')
NODES = ('nord', 'sued', 'ost', 'west', 'dach', 'turm', 'giebel', 'mast')


class Provisioner:
    """The provisioning decisions, without the HTTP around them."""

    def __init__(self, token=None, prefix4='10.13.0.0/16',
                 prefix6='2001:db8:23::/48', skip=(), seed=None,
                 mesh_vpn=None):
        rnd = random.Random(seed)

        #: The one token this server accepts.
        self.token = token or secrets.token_hex(16)

        self.location_name = '%s%d' % (rnd.choice(LOCATIONS), rnd.randint(1, 99))
        self.node_name = rnd.choice(NODES)
        self.contact = '%s@example.org' % self.location_name
        # somewhere over Graz
        self.latitude = round(rnd.uniform(47.03, 47.12), 6)
        self.longitude = round(rnd.uniform(15.38, 15.50), 6)

        self.net4 = ipaddress.ip_network(prefix4)
        self.net6 = ipaddress.ip_network(prefix6)

        #: Names this server refuses to provision - a link section or an
        #: extra network. Leaving one out is how a server says "this one
        #: gets no range", and the node leaves what it has alone.
        self.skip = set(skip)

        #: What to tell the node about the mesh VPN, or None to say nothing
        #: and leave its setting alone.
        self.mesh_vpn = mesh_vpn

        #: The hardware the last node reported about itself.
        self.board = None

        #: Every request body received, in order.
        self.requests = []

        self._rnd = rnd
        self._assigned = {}
        self._taken = set()
        self._lock = threading.Lock()

    def address(self, name, family):
        """A stable host address for this name, in the requested family.

        Stable matters: a node that asks twice has to be told the same
        thing twice, or it would reconfigure itself on every run."""
        key = ('address', name, family)
        with self._lock:
            if key not in self._assigned:
                net = self.net4 if family == 4 else self.net6
                size = net.num_addresses
                while True:
                    # skip the network address and the first host
                    addr = net.network_address + self._rnd.randrange(2, min(size, 1 << 16))
                    if addr not in self._taken:
                        break
                self._taken.add(addr)
                self._assigned[key] = str(addr)
            return self._assigned[key]

    def prefix(self, name, family, prefix_len):
        """A stable range for this name, aligned to its own size."""
        key = ('prefix', name, family, prefix_len)
        with self._lock:
            if key not in self._assigned:
                net = self.net4 if family == 4 else self.net6
                size = 1 << (net.max_prefixlen - prefix_len)
                count = min(net.num_addresses // size, 1 << 16)
                while True:
                    start = int(net.network_address) + self._rnd.randrange(1, count) * size
                    if start not in self._taken:
                        break
                self._taken.add(start)
                self._assigned[key] = str(ipaddress.ip_network((start, prefix_len)))
            return self._assigned[key]

    def provision(self, token, request):
        """Answer one /provision request. Errors are in-band, so the
        node can report why it was turned away instead of retrying the
        next mirror."""
        self.requests.append(request)

        if token != self.token:
            return {'ok': False, 'error': 'unknown token'}

        if not request.get('primary_mac') or not request.get('node_id'):
            return {'ok': False, 'error': 'request names no node'}

        if request.get('board_name'):
            self.board = (request.get('model'), request['board_name'])

        node = request['node_id']

        networks = {}
        for name in request.get('networks') or []:
            # only the exposed network is provisioned: the private one is
            # the operator's to choose and is translated on the way out
            if name in self.skip or name != 'exposed':
                continue
            networks[name] = {
                'prefix4': self.prefix('%s-%s' % (node, name), 4, 29),
                'prefix6': self.prefix('%s-%s' % (node, name), 6, 64),
            }

        links = {}
        for link in request.get('links') or []:
            section = link.get('section')
            if not section or section in self.skip:
                continue
            links[section] = {
                'linknet': self.prefix('%s-%s' % (node, section), 4, 30),
            }

        answer = {
            'ok': True,
            'location_name': self.location_name,
            'node_name': self.node_name,
            'contact': self.contact,
            'latitude': self.latitude,
            'longitude': self.longitude,
            'loopback': {
                'ip4': self.address(node, 4),
                'ip6': self.address(node, 6),
            },
            'networks': networks,
            'links': links,
        }

        if self.mesh_vpn is not None:
            answer['mesh_vpn'] = self.mesh_vpn

        return answer


class _Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def _reply(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self._reply(200, {'ok': True, 'endpoints': ['POST /provision']})

    def _read_body(self):
        """The request body, however the client framed it.

        uclient-fetch sends --post-data chunked, which
        BaseHTTPRequestHandler does not decode on its own: it would
        read Content-Length (absent, so nothing) and then choke on the
        chunk header as if it were the next request."""
        if 'chunked' in (self.headers.get('Transfer-Encoding') or '').lower():
            chunks = []
            while True:
                size = int(self.rfile.readline().split(b';')[0] or b'0', 16)
                if size == 0:
                    break
                chunks.append(self.rfile.read(size))
                self.rfile.read(2)  # CRLF after the chunk
            while True:  # trailers, then the final empty line
                line = self.rfile.readline()
                if not line or line in (b'\r\n', b'\n'):
                    break
            return b''.join(chunks)

        return self.rfile.read(int(self.headers.get('Content-Length') or 0))

    def do_POST(self):
        if self.path.rstrip('/') != '/provision':
            self._reply(404, {'ok': False, 'error': 'no such endpoint'})
            return

        raw = self._read_body()

        try:
            request = json.loads(raw)
        except ValueError as err:
            self._reply(400, {'ok': False, 'error': 'malformed JSON: %s' % err})
            return

        auth = self.headers.get('Authorization') or ''
        token = auth[len('Bearer '):] if auth.startswith('Bearer ') else None

        self._reply(200, self.server.provisioner.provision(token, request))

    def log_message(self, fmt, *args):
        if self.server.verbose:
            print('%s - %s' % (self.address_string(), fmt % args), flush=True)


class ProvisioningServer:
    """The sample server, running in a background thread."""

    def __init__(self, host='0.0.0.0', port=0, verbose=False, **kwargs):
        self.provisioner = Provisioner(**kwargs)
        self._httpd = ThreadingHTTPServer((host, port), _Handler)
        self._httpd.provisioner = self.provisioner
        self._httpd.verbose = verbose
        self._httpd.daemon_threads = True
        self._thread = None

    #: The port actually bound, which is what matters when port=0.
    @property
    def port(self):
        return self._httpd.server_address[1]

    def __getattr__(self, name):
        # token, location_name, requests, ... come from the provisioner
        return getattr(self.__dict__['provisioner'], name)

    def start(self):
        self._thread = threading.Thread(target=self._httpd.serve_forever,
                                        daemon=True)
        self._thread.start()
        return self

    def stop(self):
        self._httpd.shutdown()
        self._httpd.server_close()
        if self._thread:
            self._thread.join()

    def __enter__(self):
        return self.start()

    def __exit__(self, *_):
        self.stop()


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--host', default='0.0.0.0')
    parser.add_argument('--port', type=int, default=8080)
    parser.add_argument('--token', help='fixed token (default: random)')
    parser.add_argument('--prefix4', default='10.13.0.0/16')
    parser.add_argument('--prefix6', default='2001:db8:23::/48')
    parser.add_argument('--skip', default='', metavar='NAMES',
                        help='comma-separated link sections or networks to'
                             ' refuse, e.g. exposed')
    parser.add_argument('--mesh-vpn', choices=('on', 'off'),
                        help='tell the node whether to tunnel'
                             ' (default: say nothing)')
    parser.add_argument('-q', '--quiet', action='store_true',
                        help='do not log requests')
    args = parser.parse_args()

    server = ProvisioningServer(
        host=args.host, port=args.port, verbose=not args.quiet,
        token=args.token, prefix4=args.prefix4, prefix6=args.prefix6,
        skip=[s for s in args.skip.split(',') if s],
        mesh_vpn={'on': True, 'off': False}.get(args.mesh_vpn))

    print('listening on %s:%d' % (args.host, server.port))
    print('token:         %s' % server.token)
    print('location_name: %s' % server.location_name)
    print('node_name:     %s' % server.node_name)
    print('contact:       %s' % server.contact)
    print('coordinates:   %s, %s' % (server.latitude, server.longitude))
    print()
    print('on the node:')
    print('  uci set gluon-provisioning.provisioning.token=%s' % server.token)
    print('  uci set gluon-provisioning.provisioning.enabled=1')
    print('  uci commit gluon-provisioning')
    print('  GLUON_PROVISIONING_API=http://<host>:%d'
          ' gluon-provisioning force_provision' % server.port, flush=True)

    try:
        server.start()
        server._thread.join()
    except KeyboardInterrupt:
        server.stop()


if __name__ == '__main__':
    main()
