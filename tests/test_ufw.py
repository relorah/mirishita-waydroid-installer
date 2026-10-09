import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('ufw_rules', ROOT / 'lib/ufw_rules.py')
rules = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rules)


class RuleTests(unittest.TestCase):
    def test_existing_ipv4_defaults_and_comments(self):
        text = '\n'.join('ufw ' + rule + " comment 'MWI Waydroid rule'" for rule in rules.required('eth0'))
        self.assertEqual(rules.missing(text, 'eth0'), [])
        text = text.replace('to any port 67', 'from 0.0.0.0/0 to 0.0.0.0/0 port 67')
        self.assertEqual(rules.missing(text, 'eth0'), [])

    def test_partial_wrong_interface_ipv6_deny(self):
        self.assertEqual(len(rules.missing('ufw ' + rules.required('eth0')[0], 'eth0')), 3)
        for text in ['ufw deny in on waydroid0 to any port 67 proto udp',
                     'ufw allow in on waydroid0 from ::/0 to ::/0 port 67 proto udp',
                     'ufw allow in on other to any port 67 proto udp']:
            self.assertEqual(len(rules.missing(text, 'eth0')), 4)

    def test_uplink_changed(self):
        text = '\n'.join('ufw ' + rule for rule in rules.required('eth0'))
        self.assertEqual(rules.missing(text, 'eth1'), [rules.required('eth1')[-1]])

    def test_existing_dns_from_any_covers_required_subnet(self):
        text = '\n'.join('ufw ' + rule.replace('from 192.168.240.0/24 ', '') for rule in rules.required('eth0'))
        self.assertEqual(rules.missing(text, 'eth0'), [])


@unittest.skipUnless(sys.platform == 'linux' and shutil.which('bash'), 'Linux Bash/PTY required')
class SmokeTests(unittest.TestCase):
    def run_case(self, answer, existing='', active=True, tty=True):
        with tempfile.TemporaryDirectory() as tmp:
            script = Path(tmp) / 'case.sh'
            script.write_text('''set -Eeuo pipefail
WORK_ROOT=/tmp
WAYDROID_SCRIPT_COMMIT=test
source "$ROOT/lib/lifecycle.sh"
SCRIPT_DIR="$ROOT"
PYTHON_BIN=python3
LOG_DIR="$CASE_DIR"
msg() { printf '%s\\n' "$*"; }
warn() { printf '%s\\n' "$*"; }
die() { printf '%s\\n' "$*"; exit 1; }
ufw() { :; }
ip() { printf '1.1.1.1 via 192.0.2.1 dev eth0\\n'; }
sudo() {
    shift 2
    [[ "$1" == ufw ]] || exit 22
    shift
    case "$*" in
        'status') printf 'Status: %s\\n' "$ACTIVE" ;;
        'show added') cat "$CASE_DIR/existing" ;;
        'status verbose') : ;;
        *)
            printf '%s\\n' "$*" >>"$CASE_DIR/applied"
            local canonical="$*"
            canonical="${canonical/insert 1 /}"
            canonical="${canonical%% comment *}"
            printf 'ufw %s\\n' "$canonical" >>"$CASE_DIR/existing"
            ;;
    esac
}
prepare_ufw
prepare_ufw
ufw_declined_hint
''')
            Path(tmp, 'existing').write_text(existing + '\n' if existing else '')
            env = dict(os.environ, ROOT=str(ROOT), CASE_DIR=tmp, ACTIVE='active' if active else 'inactive')
            if tty:
                import pty
                master, slave = pty.openpty()
                proc = subprocess.Popen(['bash', str(script)], stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env)
                os.close(slave)
                os.write(master, (answer + '\n').encode())
                try:
                    output = proc.communicate(timeout=15)[0].decode()
                finally:
                    os.close(master)
            else:
                proc = subprocess.run(['bash', str(script)], input=b'y\n', stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env, timeout=15)
                output = proc.stdout.decode()
            self.assertEqual(proc.returncode, 0, output)
            applied = Path(tmp, 'applied')
            return output, applied.read_text().splitlines() if applied.exists() else []

    def test_yes_uppercase_and_repeat(self):
        for answer in ('y', 'Y'):
            output, applied = self.run_case(answer)
            self.assertEqual(output.count('[y/N]'), 1)
            self.assertEqual(len(applied), 4)
            self.assertTrue(all('insert 1 allow' in line for line in applied))

    def test_decline_enter_other_and_noninteractive(self):
        for answer in ('n', '', 'yes'):
            output, applied = self.run_case(answer)
            self.assertEqual(applied, [])
            self.assertEqual(output.count('[y/N]'), 1)
            self.assertIn('DHCP/DNSが遮断', output)
        output, applied = self.run_case('y', tty=False)
        self.assertEqual(applied, [])

    def test_existing_partial_and_inactive(self):
        all_rules = '\n'.join('ufw ' + rule + " comment 'MWI'" for rule in rules.required('eth0'))
        output, applied = self.run_case('y', all_rules)
        self.assertNotIn('[y/N]', output)
        self.assertEqual(applied, [])
        output, applied = self.run_case('y', '\n'.join(all_rules.splitlines()[:3]))
        self.assertEqual(len(applied), 1)
        self.assertTrue(all(line.startswith('route insert') for line in applied))
        output, applied = self.run_case('y', active=False)
        self.assertNotIn('[y/N]', output)
        self.assertEqual(applied, [])


if __name__ == '__main__':
    unittest.main()
