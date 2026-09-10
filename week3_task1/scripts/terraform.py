#!/usr/bin/env python3
"""Bridge AWS CLI v2 login sessions to the AWS 5.x provider's credential chain."""
import json
import os
from pathlib import Path
import subprocess
import sys

if len(sys.argv) < 3 or sys.argv[1] not in ('dev', 'production'):
    sys.exit('Usage: python3 scripts/terraform.py dev|production <terraform command> [arguments...]')

root = Path(__file__).resolve().parents[1]
env = dict(os.environ)
if not (env.get('AWS_ACCESS_KEY_ID') and env.get('AWS_SECRET_ACCESS_KEY')):
    result = subprocess.run(['aws', 'configure', 'export-credentials', '--format', 'process'],
                            stdout=subprocess.PIPE, text=True)
    if result.returncode:
        sys.exit('AWS credentials unavailable. Run aws login (or aws sso login for an SSO profile), then retry.')
    credentials = json.loads(result.stdout)
    env['AWS_ACCESS_KEY_ID'] = credentials['AccessKeyId']
    env['AWS_SECRET_ACCESS_KEY'] = credentials['SecretAccessKey']
    if credentials.get('SessionToken'):
        env['AWS_SESSION_TOKEN'] = credentials['SessionToken']
    else:
        env.pop('AWS_SESSION_TOKEN', None)
env['AWS_EC2_METADATA_DISABLED'] = 'true'
os.execvpe('terraform', ['terraform', f'-chdir={root / "infrastructure" / sys.argv[1]}', *sys.argv[2:]], env)
