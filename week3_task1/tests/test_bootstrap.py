"""Exercise the rendered EC2 script without Docker, AWS access, or root access."""
import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BootstrapTest(unittest.TestCase):
    def run_bootstrap(self, mode):
        with tempfile.TemporaryDirectory() as directory:
            tmp = Path(directory)
            variables = {
                'aws_region': 'eu-central-1',
                'docker_image': '123456789012.dkr.ecr.eu-central-1.amazonaws.com/demo:test',
                'app_port': 8080,
                'container_port': 3001,
                'health_check_path': '/healthz',
            }
            expression = 'base64encode(templatefile(%s, %s))' % (
                json.dumps(str(ROOT / 'user_data/user_data.sh')), json.dumps(variables))
            env = dict(os.environ)
            env.pop('TF_DATA_DIR', None)
            rendered = subprocess.run(['terraform', 'console', '-no-color'], cwd=tmp,
                                      env=env, input=expression, text=True, capture_output=True, check=True)
            script = base64.b64decode(json.loads(rendered.stdout)).decode()
            self.assertNotIn('${', script)
            self.assertIn('%{http_code}', script)
            # Redirect only the logging destination; execute all bootstrap logic unchanged.
            script = script.replace('exec > >(tee -a /var/log/nodejs-demoapp-bootstrap.log /dev/console) 2>&1',
                                    'exec >>"$BOOTSTRAP_TEST_LOG" 2>&1')
            (tmp / 'bootstrap.sh').write_text(script)
            subprocess.run(['bash', '-n', str(tmp / 'bootstrap.sh')], check=True)
            mock = tmp / 'mock'
            mock.write_text(f'#!{sys.executable}\n' + '''
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
root = pathlib.Path(os.environ['MOCK_ROOT'])
with (root / 'commands.jsonl').open('a') as f:
    f.write(json.dumps([name] + args) + '\\n')
key = name + ('-' + args[0] if args else '')
counter = root / (key + '.count')
n = int(counter.read_text()) + 1 if counter.exists() else 1
counter.write_text(str(n))
mode = os.environ['MOCK_MODE']
if name == 'aws':
    if n < 3: sys.exit(1)
    print('mock-login-password')
if name == 'docker':
    if args[:2] == ['container', 'inspect']: sys.exit(1)
    if args[0] == 'login':
        sys.exit(0 if sys.stdin.read().strip() else 1)
    if args[0] == 'pull' and (mode == 'pull-failure' or n == 1): sys.exit(1)
    if args[0] == 'run': print('mock-container-id')
if name == 'curl':
    print('503' if mode == 'unready' or n < 3 else '200', end='')
''')
            mock.chmod(0o755)
            for command in ['dnf', 'aws', 'docker', 'systemctl', 'curl', 'sleep']:
                (tmp / command).symlink_to(mock)
            env.update(PATH=str(tmp) + os.pathsep + env['PATH'], MOCK_ROOT=str(tmp),
                       MOCK_MODE=mode, BOOTSTRAP_TEST_LOG=str(tmp / 'bootstrap.log'))
            result = subprocess.run(['bash', str(tmp / 'bootstrap.sh')], env=env, timeout=30)
            calls = [json.loads(line) for line in (tmp / 'commands.jsonl').read_text().splitlines()]
            return result.returncode, calls

    def test_retries_and_distinct_host_container_ports(self):
        status, calls = self.run_bootstrap('success')
        self.assertEqual(status, 0)
        self.assertEqual(len([c for c in calls if c[:2] == ['aws', 'ecr']]), 3)
        self.assertEqual(len([c for c in calls if c[:2] == ['docker', 'pull']]), 2)
        run = next(c for c in calls if c[:2] == ['docker', 'run'])
        self.assertIn('8080:3001', run)
        self.assertIn('PORT=3001', run)
        pull = next(c for c in calls if c[:2] == ['docker', 'pull'])
        self.assertIn('linux/amd64', pull)
        self.assertIn('http://127.0.0.1:8080/healthz', next(c for c in calls if c[0] == 'curl'))

    def test_bad_image_fails_without_starting_container(self):
        status, calls = self.run_bootstrap('pull-failure')
        self.assertNotEqual(status, 0)
        self.assertFalse(any(c[:2] == ['docker', 'run'] for c in calls))

    def test_never_healthy_exits_with_failure_and_logs(self):
        status, calls = self.run_bootstrap('unready')
        self.assertNotEqual(status, 0)
        self.assertTrue(any(c[:2] == ['docker', 'logs'] for c in calls))


if __name__ == '__main__':
    unittest.main()
