#!/usr/bin/env python3
"""Development-only native build gate. Never part of the application runtime."""
import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--release', action='store_true', help='Also build the release application')
    parser.add_argument('--report', type=Path, help='Write the actual results as JSON')
    args = parser.parse_args()
    result = {'checks': [], 'status': 'blocked', 'playback_tested': False}
    def save():
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    cargo = shutil.which('cargo')
    if not cargo:
        result['reason'] = 'Rust/Cargo is not installed or not on PATH.'
        print(result['reason'], file=sys.stderr)
        save()
        return 2
    commands = [
        [cargo, '--version'],
        [cargo, 'test', '-p', 'aperture-core', '-p', 'aperture-vlc'],
        [cargo, 'check', '-p', 'aperture-app'],
        [cargo, 'test', '-p', 'aperture-app'],
    ]
    if args.release:
        commands.append([cargo, 'build', '--release', '-p', 'aperture-app'])
    for command in commands:
        print('+ ' + ' '.join(command), flush=True)
        try:
            completed = subprocess.run(command, cwd=ROOT, timeout=1800, check=False)
            code = completed.returncode
        except (OSError, subprocess.TimeoutExpired) as error:
            result['reason'] = str(error)
            code = -1
        result['checks'].append({'command': command[1:], 'exit_code': code})
        if code:
            result['status'] = 'failed'
            save()
            return 1
    result['status'] = 'passed'
    print('Native build checks passed. Window launch and real playback still require validation.')
    save()
    return 0

if __name__ == '__main__':
    sys.exit(main())
