#!/usr/bin/env python3
"""Print missing Waydroid rules from `ufw show added`, ignoring comments."""
import shlex
import sys
import ipaddress


def normalized(command):
    tokens = shlex.split(command)
    if tokens and tokens[0] == 'ufw':
        tokens.pop(0)
    if 'comment' in tokens:
        tokens = tokens[:tokens.index('comment')]
    result = {'route': False, 'from': 'any', 'to': 'any'}
    if tokens and tokens[0] == 'route':
        result['route'] = True
        tokens.pop(0)
    if not tokens or tokens.pop(0) != 'allow':
        return None
    i = 0
    while i < len(tokens):
        key = tokens[i]
        if key in ('in', 'out'):
            result['direction'] = key
            if tokens[i + 1:i + 2] == ['on'] and i + 2 < len(tokens):
                result[key + '_interface'] = tokens[i + 2]
                i += 3
            else:
                i += 1
        elif key in ('from', 'to', 'port', 'proto') and i + 1 < len(tokens):
            result[key] = tokens[i + 1]
            i += 2
        else:
            return None
    # route in/out interfaces do not represent the INPUT/OUTPUT direction.
    if result['route']:
        result.pop('direction', None)
    for key in ('from', 'to'):
        if result[key] == '0.0.0.0/0':
            result[key] = 'any'
    return result


def required(egress):
    return [
        'allow in on waydroid0 to any port 67 proto udp',
        'allow in on waydroid0 from 192.168.240.0/24 to 192.168.240.1 port 53 proto udp',
        'allow in on waydroid0 from 192.168.240.0/24 to 192.168.240.1 port 53 proto tcp',
        f'route allow in on waydroid0 out on {egress} from 192.168.240.0/24',
    ]


def missing(text, egress):
    existing = []
    for line in text.splitlines():
        if not line.startswith('ufw '):
            continue
        try:
            existing.append(normalized(line))
        except ValueError:
            continue
    def covers(actual, wanted):
        if actual is None:
            return False
        if {k: v for k, v in actual.items() if k not in ('from', 'to')} != {k: v for k, v in wanted.items() if k not in ('from', 'to')}:
            return False
        for key in ('from', 'to'):
            if actual[key] == wanted[key] or actual[key] == 'any':
                continue
            try:
                target = ipaddress.ip_network('0.0.0.0/0' if wanted[key] == 'any' else wanted[key], strict=False)
                allowed = ipaddress.ip_network(actual[key], strict=False)
                if target.version != allowed.version or not target.subnet_of(allowed):
                    return False
            except ValueError:
                return False
        return True
    return [rule for rule in required(egress) if not any(covers(item, normalized(rule)) for item in existing)]


if __name__ == '__main__':
    print('\n'.join(missing(sys.stdin.read(), sys.argv[1])))
