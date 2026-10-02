#!/usr/bin/env python3
"""Run the account-free production ConversationView rotation fixture on one AVD.

The runner owns one foreground, isolated emulator and asks WindowManager for
portrait/landscape only after a fixture checkpoint. It records physical-display
screenshots and the Flutter test log; it neither starts the normal app nor uses
accounts, credentials, transport, or existing application data.
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

PACKAGE = 'com.bluebubbles.messaging.alpha'
REQUEST = re.compile(r'E01_DRAFT_ROTATE_REQUEST portrait=(true|false)')
ROTATED = re.compile(r'E01_DRAFT_ROTATED portrait=(true|false) width=(\d+) height=(\d+)')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('avd')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--serial', default='emulator-5554')
    args = parser.parse_args()
    if not args.serial.startswith('emulator-'):
        parser.error('Only an isolated emulator serial is allowed')
    if args.output.exists():
        parser.error(f'Output already exists: {args.output}')
    args.output.mkdir(parents=True)

    adb = shutil.which('adb')
    emulator = shutil.which('emulator')
    flutter = shutil.which('flutter')
    if adb is None or emulator is None or flutter is None:
        parser.error('Source test_driver/android-env.sh and add Rust/protoc paths first')

    receipt = {
        'status': 'incomplete', 'avd': args.avd, 'serial': args.serial,
        'package': PACKAGE,
        'build': 'alpha/debug integration fixture only; not a production or upgrade artifact',
        'test': 'integration_test/android_production_conversation_draft_test.dart',
        'screenshots': [], 'rotations': [], 'logs': [],
    }
    emulator_process = None
    original_rotation = None
    try:
        emulator_log = args.output / 'emulator.log'
        with emulator_log.open('w') as log:
            emulator_process = subprocess.Popen([
                emulator, '-avd', args.avd, '-no-window', '-no-audio', '-no-boot-anim',
                '-gpu', 'swiftshader', '-cores', '4', '-memory', '3072',
                '-port', args.serial.rsplit('-', 1)[1],
            ], stdout=log, stderr=subprocess.STDOUT)
        receipt['logs'].append(str(emulator_log))
        wait_for_boot(adb, args.serial, emulator_process)
        actual_avd = adb_text(adb, args.serial, 'emu', 'avd', 'name').splitlines()[0]
        if actual_avd != args.avd or not actual_avd.startswith('openbubbles_'):
            raise RuntimeError(f'Expected isolated requested AVD, got {actual_avd}')
        original_rotation = adb_text(adb, args.serial, 'shell', 'wm', 'user-rotation').split()
        if not original_rotation or original_rotation[0] not in ('free', 'lock'):
            raise RuntimeError(f'Unexpected original rotation state: {original_rotation}')
        size = adb_text(adb, args.serial, 'shell', 'wm', 'size').split()[-1]
        width, height = (int(part) for part in size.split('x'))
        landscape = 0 if width > height else 1
        portrait = 1 - landscape
        receipt['display_pixels'] = {'width': width, 'height': height}
        receipt['rotation_values'] = {'portrait': portrait, 'landscape': landscape}

        log_path = args.output / 'production-draft.log'
        receipt['logs'].append(str(log_path))
        command = [
            flutter, 'test', '--no-pub', 'integration_test/android_production_conversation_draft_test.dart',
            '-d', args.serial, '--flavor', 'alpha', '--reporter', 'expanded',
        ]
        receipt['command'] = command
        process = subprocess.Popen(command, cwd=Path.cwd(), text=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        assert process.stdout is not None
        passed = False
        deadline = time.monotonic() + 900
        with log_path.open('w') as log:
            while time.monotonic() < deadline:
                line = process.stdout.readline()
                if line:
                    print(line, end='')
                    log.write(line)
                    log.flush()
                    request = REQUEST.search(line)
                    if request:
                        expected_portrait = request.group(1) == 'true'
                        rotation = portrait if expected_portrait else landscape
                        adb_run(adb, args.serial, 'shell', 'wm', 'user-rotation', 'lock', str(rotation))
                        receipt['rotations'].append({
                            'requested_portrait': expected_portrait,
                            'rotation_value': rotation,
                            'wm_user_rotation': adb_text(adb, args.serial, 'shell', 'wm', 'user-rotation'),
                        })
                    rotated = ROTATED.search(line)
                    if rotated:
                        shot = screenshot(adb, args.serial, args.output, len(receipt['screenshots']))
                        receipt['screenshots'].append({
                            'portrait': rotated.group(1) == 'true', 'viewport': {
                                'width': int(rotated.group(2)), 'height': int(rotated.group(3))},
                            'path': str(shot),
                        })
                    if 'E01_PRODUCTION_DRAFT_PASSED' in line:
                        passed = True
                elif process.poll() is not None:
                    break
                else:
                    time.sleep(.1)
            else:
                process.kill()
                raise TimeoutError('Production draft fixture timed out')
        exit_code = process.wait(timeout=30)
        receipt['test_exit_code'] = exit_code
        if exit_code != 0:
            raise RuntimeError(f'Flutter test failed with exit {exit_code}; see {log_path}')
        if not passed or len(receipt['screenshots']) != 5:
            raise RuntimeError('Fixture did not produce all five rotations and completion marker')
        receipt['status'] = 'passed'
    except Exception as exc:
        receipt['status'] = 'failed'
        receipt['error'] = str(exc)
    finally:
        if original_rotation:
            try:
                adb_run(adb, args.serial, 'shell', 'wm', 'user-rotation', *original_rotation)
                receipt['rotation_restored'] = (
                    adb_text(adb, args.serial, 'shell', 'wm', 'user-rotation').split() == original_rotation)
            except Exception as exc:
                receipt['rotation_restore_error'] = str(exc)
        if emulator_process:
            try:
                adb_run(adb, args.serial, 'emu', 'kill')
                deadline = time.monotonic() + 30
                while time.monotonic() < deadline:
                    devices = subprocess.check_output([adb, 'devices'], text=True, timeout=10)
                    line = next((line for line in devices.splitlines()
                                 if line.startswith(args.serial + '\t')), '')
                    if not line.endswith('device'):
                        receipt['emulator_shutdown_verified'] = True
                        break
                    time.sleep(1)
            except (subprocess.SubprocessError, FileNotFoundError) as exc:
                receipt['emulator_shutdown_error'] = str(exc)
            finally:
                if emulator_process.poll() is None:
                    emulator_process.kill()
        (args.output / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt, indent=2))
    sys.exit(0 if receipt['status'] == 'passed' else 1)


def adb_run(adb, serial, *args):
    return subprocess.run([adb, '-s', serial, *args], text=True, capture_output=True,
                          check=True, timeout=30)


def adb_text(adb, serial, *args):
    return adb_run(adb, serial, *args).stdout.strip()


def wait_for_boot(adb, serial, emulator_process):
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        if emulator_process.poll() is not None:
            raise RuntimeError(f'Emulator exited before boot ({emulator_process.returncode})')
        try:
            if (adb_text(adb, serial, 'shell', 'getprop', 'sys.boot_completed') == '1'
                    and adb_text(adb, serial, 'shell', 'service', 'check', 'window') == 'Service window: found'):
                return
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
            pass
        time.sleep(1)
    raise TimeoutError('Emulator did not boot')


def screenshot(adb, serial, output, index):
    path = output / f'rotation-{index + 1}-physical-display.png'
    image = subprocess.check_output([adb, '-s', serial, 'exec-out', 'screencap', '-p'], timeout=30)
    if not image.startswith(b'\x89PNG\r\n\x1a\n'):
        raise RuntimeError('ADB screencap did not return PNG')
    path.write_bytes(image)
    return path


if __name__ == '__main__':
    main()
