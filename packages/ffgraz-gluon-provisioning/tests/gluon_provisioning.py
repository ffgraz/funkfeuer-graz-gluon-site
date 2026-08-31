#!/usr/bin/env python3
"""A node provisions itself against a gluon-provisioning server.

The whole flow, end to end: the sample server in tests/lib hands out one
random token and random node info, the node is given that token and
pointed at the server through GLUON_PROVISIONING_API, and then has to
ask for the right things, apply what it is told, and leave itself alone
on the second run.

The server runs on the test host, which a node reaches at 10.0.2.2 over
QEMU's user networking - so the node needs its uplink up first.
"""
import os
import sys

from pynet import Node, start, finish
from meshlib import wait_uplink

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib'))
from provisioning_server import ProvisioningServer  # noqa: E402

#: The test host, as seen from a node on QEMU's user networking.
HOST = os.environ.get('GLUON_TEST_HOST_ADDR', '10.0.2.2')


def node_info(node, section, option):
    """Read an option from gluon-node-info's anonymous sections."""
    return node.succeed(
        'uci get "$(uci show gluon-node-info'
        ' | sed -n \'s/={}$//p\' | head -1).{}"'.format(section, option))


a = Node()

start()

wait_uplink(a, 4)

server = ProvisioningServer(port=0).start()
endpoint = 'http://%s:%d' % (HOST, server.port)
a.dbg('sample provisioning server on %s, token %s' % (endpoint, server.token))


RUNNER, LOG, STATUS = ('/tmp/provision.sh', '/tmp/provision.log',
                       '/tmp/provision.status')


def provision(command, timeout=300):
    """Run gluon-provisioning detached, and wait for it to finish.

    A run that changes something ends in gluon-reload, which stops and
    starts the network - killing the ssh session the command was
    started from. So it has to outlive its own connection:
    start-stop-daemon -b detaches it, and its exit status comes back
    through a file once the node is reachable again."""
    a.succeed('rm -f {} {}'.format(LOG, STATUS))
    a.succeed("printf '%s\\n' '#!/bin/sh'"
              " 'GLUON_PROVISIONING_API={} gluon-provisioning {} > {} 2>&1'"
              " 'echo $? > {}' > {}"
              .format(endpoint, command, LOG, STATUS, RUNNER))
    a.succeed('chmod +x ' + RUNNER)
    a.succeed('start-stop-daemon -S -b -x ' + RUNNER)
    a.wait_until_succeeds('[ -f {} ]'.format(STATUS), timeout)
    return int(a.succeed('cat ' + STATUS)), a.succeed('cat ' + LOG)


try:
    # --- a node without a token does not even ask ---

    status, out = provision('force_provision')
    if 'no provisioning token' not in out:
        raise AssertionError('untokened node did not refuse:\n' + out)
    if server.requests:
        raise AssertionError('untokened node called the server anyway')

    # --- a wrong token is refused, in words the node repeats ---

    a.succeed('uci set gluon-provisioning.provisioning.token=notthetoken')
    a.succeed('uci set gluon-provisioning.provisioning.enabled=1')
    a.succeed('uci commit gluon-provisioning')

    before = a.execute('uci get gluon-static-ip.loopback.ip6')

    status, out = provision('force_provision')
    if 'unknown token' not in out:
        raise AssertionError('a wrong token was not reported:\n' + out)
    if a.execute('uci get gluon-static-ip.loopback.ip6') != before:
        raise AssertionError('a rejected node reconfigured itself anyway')

    # --- with the right one, it provisions ---

    a.succeed('uci set gluon-provisioning.provisioning.token=' + server.token)
    a.succeed('uci commit gluon-provisioning')

    status, out = provision('force_provision')
    if 'E:' in out:
        raise AssertionError('provisioning reported an error:\n' + out)

    # what the node asked for
    request = server.requests[-1]

    primary_mac = a.succeed('cat /lib/gluon/core/sysconfig/primary_mac')
    if request.get('primary_mac') != primary_mac:
        raise AssertionError('primary_mac: sent %r, node has %r'
                             % (request.get('primary_mac'), primary_mac))
    if request.get('node_id') != primary_mac.replace(':', ''):
        raise AssertionError('node_id does not match primary_mac: %r'
                             % request.get('node_id'))

    asked = request.get('interfaces') or {}
    loopback = asked.get('loopback')
    if not loopback:
        raise AssertionError('the node did not ask for a loopback address')
    if loopback.get('requested_type') != 6 or loopback.get('type') != 'loopback':
        raise AssertionError('loopback asked for the wrong thing: %r' % loopback)

    mesh = {n: i for n, i in asked.items() if n != 'loopback'}
    if not mesh:
        raise AssertionError('the node asked for no mesh interface at all')
    for name, want in mesh.items():
        if want.get('requested_type') != 4:
            raise AssertionError('%s must be requested as IPv4, got %r' % (name, want))
        if want.get('type') not in ('wifi', 'ethernet', 'vpn'):
            raise AssertionError('%s has no usable type: %r' % (name, want))

    # what the node did with the answer. address() is what the server
    # handed out, and is stable, so it can be asked again here.
    for name, want in asked.items():
        family = want['requested_type']
        assigned = server.address(name, family)
        option = 'ip6' if family == 6 else 'ip4'

        # the loopback holds a single host address, so the pool prefix the
        # server answers with is not part of what the node stores
        expected = assigned.split('/')[0] if want['type'] == 'loopback' \
            else assigned

        stored = a.succeed('uci get gluon-static-ip.%s.%s' % (name, option))
        if stored != expected:
            raise AssertionError('%s: uci holds %r, expected %r'
                                 % (name, stored, expected))

        # applied to the running system, not merely stored
        a.wait_until_succeeds("ip addr show | grep -qF '%s'" % expected, 60)

    hostname = a.succeed('uci get system.@system[0].pretty_hostname')
    expected = '%s-%s' % (server.location_name, server.node_name)
    if hostname != expected:
        raise AssertionError('hostname is %r, expected %r' % (hostname, expected))

    contact = node_info(a, 'owner', 'contact')
    if contact != server.contact:
        raise AssertionError('contact is %r, expected %r' % (contact, server.contact))

    if node_info(a, 'location', 'share_location') != '1':
        raise AssertionError('coordinates were set but not shared')
    for option, value in (('latitude', server.latitude),
                          ('longitude', server.longitude)):
        stored = float(node_info(a, 'location', option))
        if abs(stored - value) > 1e-6:
            raise AssertionError('%s is %r, expected %r' % (option, stored, value))

    # the mesh VPN follows whether mesh_vpn was provisioned
    if 'mesh_vpn' in asked:
        if a.succeed('uci get gluon.mesh_vpn.enabled') != '1':
            raise AssertionError('mesh_vpn was provisioned but the vpn is off')

    # --- and a second run changes nothing ---

    before = len(server.requests)
    status, out = provision('provision')
    if status != 0:
        raise AssertionError('the repeated run failed:\n' + out)
    if 'No settings changes' not in out:
        raise AssertionError('a repeated run was not a no-op:\n' + out)
    if len(server.requests) <= before:
        raise AssertionError('the repeated run never reached the server')

    # --- disabled means disabled ---

    a.succeed('uci set gluon-provisioning.provisioning.enabled=0')
    a.succeed('uci commit gluon-provisioning')

    before = len(server.requests)
    status, out = provision('provision')
    if len(server.requests) != before:
        raise AssertionError('a disabled node still called the server:\n' + out)
finally:
    server.stop()

finish()
