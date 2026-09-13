#!/usr/bin/env python3
"""Check an already-started, isolated OpenBubbles AVD; not an app feature test."""
import argparse
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', default=str(Path.home() / '.local/share/android/sdk/platform-tools/adb'))
    parser.add_argument('--serial', default='emulator-5554')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--shutdown', action='store_true')
    args = parser.parse_args()
    if not args.serial.startswith('emulator-'):
        parser.error('Only isolated emulator serials are supported')

    def adb(*command):
        result = subprocess.run([args.adb, '-s', args.serial, *command],
                                capture_output=True, timeout=20, check=True)
        return result.stdout.decode().strip()

    args.output.mkdir(parents=True, exist_ok=True)
    args.output = Path(tempfile.mkdtemp(prefix='run-', dir=args.output))
    (args.output / 'result.json').write_text('{"status": "incomplete"}\n')
    print(f'Run artifacts: {args.output}', flush=True)
    deadline = time.monotonic() + 120
    while True:
        try:
            if (adb('shell', 'getprop', 'sys.boot_completed') == '1'
                    and adb('shell', 'service', 'check', 'window') == 'Service window: found'):
                break
        except subprocess.SubprocessError:
            pass
        if time.monotonic() >= deadline:
            raise TimeoutError('Android window service did not become ready')
        time.sleep(2)

    avd = adb('emu', 'avd', 'name').splitlines()[0]
    if not avd.startswith('openbubbles_tablet_'):
        raise RuntimeError(f'Expected an isolated landscape-native tablet AVD: {avd}')
    result = {'avd': avd, 'serial': args.serial, 'output': str(args.output),
              'sdk': adb('shell', 'getprop', 'ro.build.version.sdk'),
              'size': adb('shell', 'wm', 'size'),
              'density': adb('shell', 'wm', 'density'),
              'scope': 'Android OS infrastructure; not OpenBubbles behavior'}
    original = adb('shell', 'wm', 'user-rotation').split()
    if not original or original[0] not in ('free', 'lock'):
        raise RuntimeError(f'Unexpected rotation state: {original}')
    try:
        adb('shell', 'input', 'keyevent', '82')
        adb('shell', 'am', 'start', '-a', 'android.settings.SETTINGS')
        for name, rotation in [('landscape-before', 0), ('portrait', 1), ('landscape-after', 0)]:
            adb('shell', 'wm', 'user-rotation', 'lock', str(rotation))
            deadline = time.monotonic() + 20
            while True:
                image = subprocess.check_output(
                    [args.adb, '-s', args.serial, 'exec-out', 'screencap', '-p'], timeout=20)
                if image[:8] != b'\x89PNG\r\n\x1a\n':
                    raise RuntimeError('ADB did not return a PNG screenshot')
                width, height = struct.unpack('>II', image[16:24])
                # Pixel Tablet natural orientation is landscape.
                if (width > height) == (rotation == 0) and width != height:
                    break
                if time.monotonic() >= deadline:
                    raise TimeoutError(f'Rotation {rotation} not observed: {width}x{height}')
                time.sleep(1)
            (args.output / f'{name}.png').write_bytes(image)
            result[name] = {'width': width, 'height': height}
        result['round_trip'] = 'landscape -> portrait -> landscape'
        result['status'] = 'passed'
    finally:
        try:
            adb('shell', 'wm', 'user-rotation', *original)
            restored = adb('shell', 'wm', 'user-rotation').split()
            if restored != original:
                raise RuntimeError(f'Rotation restore mismatch: {restored} != {original}')
            result['rotation_restored'] = True
        finally:
            if args.shutdown:
                adb('emu', 'kill')
                deadline = time.monotonic() + 15
                while True:
                    devices = subprocess.check_output([args.adb, 'devices'], timeout=10).decode()
                    if args.serial not in devices:
                        result['shutdown_verified'] = True
                        break
                    if time.monotonic() >= deadline:
                        raise TimeoutError('Emulator remained registered after shutdown')
                    time.sleep(1)
    temporary = args.output / 'result.json.tmp'
    temporary.write_text(json.dumps(result, indent=2) + '\n')
    temporary.replace(args.output / 'result.json')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
