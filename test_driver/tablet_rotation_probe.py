#!/usr/bin/env python3
"""Coordinate OS rotation for integration_test/tablet_portrait_test.dart only."""
import argparse
import json
from pathlib import Path
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--test-log', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    adb = str(Path.home() / '.local/share/android/sdk/platform-tools/adb')
    prefix = [adb, '-s', 'emulator-5554']

    def run(*command):
        return subprocess.check_output(prefix + list(command), stderr=subprocess.PIPE, timeout=30).decode().strip()

    deadline = time.monotonic() + 780
    while True:
        try:
            if run('shell', 'service', 'check', 'window') == 'Service window: found':
                break
        except subprocess.SubprocessError:
            pass
        if time.monotonic() > deadline:
            raise TimeoutError('Emulator did not boot')
        time.sleep(1)
    if not run('emu', 'avd', 'name').splitlines()[0].startswith('openbubbles_tablet_'):
        raise RuntimeError('Not an isolated tablet AVD')
    original = run('shell', 'wm', 'user-rotation').split()
    if not original or original[0] not in ('free', 'lock'):
        raise RuntimeError(f'Unexpected rotation mode: {original}')
    consumed = 0
    rotations = []
    status = 'incomplete'
    try:
        while time.monotonic() < deadline:
            lines = args.test_log.read_text().splitlines() if args.test_log.exists() else []
            pending = lines[consumed:]
            consumed = len(lines)
            for line in pending:
                if 'Some tests failed' in line or 'Error: Gradle task' in line:
                    status = 'failed'
                    raise RuntimeError('Flutter integration test failed; see test log')
                if line.strip() in ('E01_ROTATE_PORTRAIT', 'E01_ROTATE_LANDSCAPE'):
                    portrait = line.strip() == 'E01_ROTATE_PORTRAIT'
                    run('shell', 'wm', 'user-rotation', 'lock', '1' if portrait else '0')
                    rotations.append('portrait' if portrait else 'landscape')
                if line.strip() == 'E01_CAPTURE_PORTRAIT':
                    image = subprocess.check_output(prefix + ['exec-out', 'screencap', '-p'], timeout=30)
                    (args.output / 'native-fixture-portrait.png').write_bytes(image)
                if line.strip() == 'E01_NATIVE_LAYOUT_PASSED':
                    status = 'reported'
            if status == 'reported':
                break
            time.sleep(0.5)
        if status != 'reported':
            raise TimeoutError('Native fixture did not report success')
        if rotations != ['portrait', 'landscape', 'portrait', 'landscape', 'portrait']:
            status = 'failed'
            raise RuntimeError(f'Unexpected rotation sequence: {rotations}')
        status = 'passed'
    finally:
        try:
            run('shell', 'wm', 'user-rotation', *original)
        except subprocess.SubprocessError:
            status = 'cleanup_failed'
        (args.output / 'result.json').write_text(json.dumps({
            'status': status, 'rotations': rotations,
            'scope': 'Native production wrapper/navigator with local draft fixture, not account-backed app or OS lock enforcement',
        }, indent=2) + '\n')
    if status != 'passed':
        raise RuntimeError(f'Native probe ended with status {status}')
    print('Native host rotation sequence passed; settings restored.')


if __name__ == '__main__':
    main()
