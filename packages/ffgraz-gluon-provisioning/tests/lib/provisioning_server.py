#!/usr/bin/env python3
"""A sample gluon-provisioning server, stdlib only.

It speaks the API described in ../../API.md: it generates one random
token and a random set of node info, and hands every node that presents
that token an address per interface it asks for.

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

    def __init__(self, token=None, prefix4='10.12.0.0/16',
                 prefix6='2001:db8:23::/64', skip=(), seed=None):
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

        #: Interface names this server refuses to provision. Leaving out
        #: an interface is how a server says "this one gets no address" -
        #: for mesh_vpn that is also how it says "do not tunnel".
        self.skip = set(skip)

        #: Every request body received, in order.
        self.requests = []

        self._rnd = rnd
        self._assigned = {}
        self._taken = set()
        self._lock = threading.Lock()

    def address(self, name, family):
        """A stable address for this interface, in the requested family.

        Stable matters: a node that asks twice has to be told the same
        thing twice, or it would reconfigure itself on every run."""
        key = (name, family)
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
                self._assigned[key] = '%s/%d' % (addr, net.prefixlen)
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

        interfaces = {}
        for name, want in (request.get('interfaces') or {}).items():
            family = want.get('requested_type')
            if name in self.skip or family not in (4, 6):
                continue
            interfaces[name] = {'ip': self.address(name, family)}

        return {
            'ok': True,
            'location_name': self.location_name,
            'node_name': self.node_name,
            'contact': self.contact,
            'latitude': self.latitude,
            'longitude': self.longitude,
            'interfaces': interfaces,
        }


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

    def do_POST(self):
        if self.path.rstrip('/') != '/provision':
            self._reply(404, {'ok': False, 'error': 'no such endpoint'})
            return

        length = int(self.headers.get('Content-Length') or 0)
        raw = self.rfile.read(length)

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
    parser.add_argument('--prefix4', default='10.12.0.0/16')
    parser.add_argument('--prefix6', default='2001:db8:23::/64')
    parser.add_argument('--skip', default='', metavar='NAMES',
                        help='comma-separated interfaces to refuse,'
                             ' e.g. mesh_vpn')
    parser.add_argument('-q', '--quiet', action='store_true',
                        help='do not log requests')
    args = parser.parse_args()

    server = ProvisioningServer(
        host=args.host, port=args.port, verbose=not args.quiet,
        token=args.token, prefix4=args.prefix4, prefix6=args.prefix6,
        skip=[s for s in args.skip.split(',') if s])

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
