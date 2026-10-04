#!/usr/bin/env python3
"""Run the Android-only e01 lock/relaunch fixture on one isolated AVD.

This command owns every child it starts: one foreground emulator and successive
foreground Flutter test processes. It never uses nohup or leaves an emulator
running. The lock phase is deliberately force-stopped after a real production
MiscPanel save; a fresh integration-test launch then proves persistence.
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
VIEWPORT = re.compile(r'E01_VIEWPORT scenario=(\w+) width=(\d+) height=(\d+) portrait=(true|false) pid=(\d+)')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['lock'])
    parser.add_argument('avd')
    parser.add_argument('device_class', choices=['android-phone', 'android-tablet-pre16', 'android-tablet-16-large'])
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
    if not all((adb, emulator, flutter)):
        parser.error('Source test_driver/android-env.sh and add approved Rust/protoc PATH entries first')
    assert adb is not None and emulator is not None and flutter is not None

    receipt = {
        'status': 'incomplete', 'mode': args.mode, 'avd': args.avd,
        'device_class': args.device_class, 'serial': args.serial,
        'source_revision': command(['git', 'rev-parse', 'HEAD']),
        'package': PACKAGE, 'build': 'alpha/debug integration fixture only; not a production or upgrade artifact',
        'scenarios': {}, 'screenshots': {}, 'logs': [],
    }
    emulator_process = None
    original_rotation = None
    try:
        emulator_log = args.output / 'emulator.log'
        with emulator_log.open('w') as log:
            emulator_process = subprocess.Popen([
                emulator, '-avd', args.avd, '-no-window', '-no-audio', '-no-boot-anim',
                '-gpu', 'swiftshader', '-cores', '4', '-memory', '3072', '-port', args.serial.rsplit('-', 1)[1],
            ], stdout=log, stderr=subprocess.STDOUT)
        receipt['logs'].append(str(emulator_log))
        wait_for_boot(adb, args.serial, emulator_process)
        validate_device(adb, args, receipt)
        landscape_rotation = 0 if receipt['display_pixels']['width'] > receipt['display_pixels']['height'] else 1
        receipt['landscape_rotation_value'] = landscape_rotation
        original_rotation = adb_text(adb, args.serial, 'shell', 'wm', 'user-rotation').split()
        if not original_rotation or original_rotation[0] not in ('free', 'lock'):
            raise RuntimeError(f'Unexpected initial user rotation state: {original_rotation}')

        # A physical landscape request before the switch establishes the
        # unlocked baseline. Subsequent requests test the app policy, not a
        # widget-only MediaQuery rotation.
        rotate(adb, args.serial, landscape_rotation)
        lock = run_phase(adb, flutter, args, 'lock', landscape_rotation, force_stop=True)
        receipt['scenarios']['lock'] = lock
        receipt['screenshots']['lock'] = lock.get('screenshots', {})

        rotate(adb, args.serial, landscape_rotation)
        relaunch = run_phase(adb, flutter, args, 'relaunch', landscape_rotation)
        receipt['scenarios']['relaunch'] = relaunch
        receipt['screenshots']['relaunch'] = relaunch.get('screenshots', {})

        # The fixture disables the lock in its successful relaunched process;
        # a completed Flutter integration run clears fixture app data, so do
        # not mislabel a third run as restart-continuation evidence.

        # MainActivity opts out of Android 16's large-screen orientation
        # override (PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY), so the lock
        # is expected to hold on every device class, including Android 16
        # large screens. A refusal there is still recorded as a measured failure.
        expected_lock = True
        all_persisted = relaunch.get('persisted') == True
        relaunch_viewport = relaunch.get('observations', {}).get('relaunch', {})
        unlock_viewport = relaunch.get('observations', {}).get('unlock', {})
        lock_enforced = lock.get('viewport_portrait') == True and relaunch_viewport.get('portrait') == True
        unlock_restored = unlock_viewport.get('portrait') == False
        receipt['summary'] = {
            'lock_expected_to_enforce': expected_lock,
            'lock_enforced': lock_enforced,
            'persistence_after_force_stop': all_persisted,
            'unlock_restored_device_landscape': unlock_restored,
        }
        if expected_lock and lock_enforced and all_persisted and unlock_restored:
            receipt['status'] = 'passed'
        elif args.device_class == 'android-tablet-16-large' and not lock_enforced:
            receipt['status'] = 'measured-failure-android16-large-screen'
        else:
            receipt['status'] = 'failed'
    except Exception as exc:  # receipt is evidence even for a blocked run
        receipt['status'] = 'failed'
        receipt['error'] = str(exc)
    finally:
        if original_rotation:
            try:
                adb_run(adb, args.serial, 'shell', 'wm', 'user-rotation', *original_rotation)
                restored_rotation = adb_text(adb, args.serial, 'shell', 'wm', 'user-rotation').split()
                receipt['rotation_original'] = original_rotation
                receipt['rotation_restored_value'] = restored_rotation
                receipt['rotation_restored'] = (restored_rotation[0] == original_rotation[0]
                                                and (original_rotation[0] != 'lock' or restored_rotation == original_rotation))
            except Exception as exc:
                receipt['rotation_restore_error'] = str(exc)
        if emulator_process:
            try:
                adb_run(adb, args.serial, 'emu', 'kill')
                shutdown_deadline = time.monotonic() + 30
                while time.monotonic() < shutdown_deadline:
                    devices = subprocess.check_output([adb, 'devices'], text=True, timeout=10)
                    device_line = next((line for line in devices.splitlines() if line.startswith(args.serial + '\\t')), '')
                    if not device_line or not device_line.endswith('device'):
                        receipt['emulator_shutdown_verified'] = True
                        break
                    time.sleep(1)
                if not receipt.get('emulator_shutdown_verified'):
                    raise RuntimeError('Emulator remained registered after adb emu kill')
            except Exception as exc:
                receipt['emulator_shutdown_error'] = str(exc)
            finally:
                if emulator_process.poll() is None:
                    # adb emu kill has already shut down the AVD; this only
                    # reaps the launcher wrapper if it remains attached.
                    emulator_process.kill()
        (args.output / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')

    print(json.dumps(receipt, indent=2))
    # A measured Android 16 refusal intentionally remains nonzero so no caller
    # can treat the platform limitation as native acceptance.
    sys.exit(0 if receipt['status'] == 'passed' else 1)


def command(args):
    return subprocess.check_output(args, text=True).strip()


def adb_run(adb, serial, *args):
    return subprocess.run([adb, '-s', serial, *args], text=True, capture_output=True, check=True, timeout=30)


def adb_text(adb, serial, *args):
    return adb_run(adb, serial, *args).stdout.strip()


def adb_text_optional(adb, serial, *args):
    result = subprocess.run([adb, '-s', serial, *args], text=True, capture_output=True, timeout=30)
    return result.stdout.strip() if result.returncode == 0 else ''


def wait_for_boot(adb, serial, emulator_process):
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        if emulator_process.poll() is not None:
            raise RuntimeError(f'Emulator exited before boot ({emulator_process.returncode})')
        try:
            if (adb_text(adb, serial, 'shell', 'getprop', 'sys.boot_completed') == '1'
                    and adb_text(adb, serial, 'shell', 'service', 'check', 'window') == 'Service window: found'):
                return
        except (subprocess.SubprocessError, FileNotFoundError):
            pass
        time.sleep(1)
    raise TimeoutError('Emulator did not boot')


def validate_device(adb, args, receipt):
    actual_avd = adb_text(adb, args.serial, 'emu', 'avd', 'name').splitlines()[0]
    if actual_avd != args.avd or not actual_avd.startswith('openbubbles_'):
        raise RuntimeError(f'Expected isolated requested AVD {args.avd}, got {actual_avd}')
    try:
        sdk = int(adb_text(adb, args.serial, 'shell', 'getprop', 'ro.build.version.sdk'))
        size = adb_text(adb, args.serial, 'shell', 'wm', 'size').split()[-1]
        density = adb_text(adb, args.serial, 'shell', 'wm', 'density').split()[-1]
        width, height = (int(item) for item in size.split('x'))
        density_value = float(re.sub(r'[^0-9.]', '', density))
    except (IndexError, ValueError) as exc:
        raise RuntimeError('Unable to parse Android SDK/display metrics') from exc
    if density_value <= 0:
        raise RuntimeError(f'Invalid Android display density: {density_value}')
    smallest_dp = min(width, height) * 160 / density_value
    expected = {
        'android-phone': (sdk >= 36, smallest_dp < 600),
        'android-tablet-pre16': (sdk < 36, smallest_dp >= 600),
        'android-tablet-16-large': (sdk >= 36, smallest_dp >= 600),
    }[args.device_class]
    if not all(expected):
        raise RuntimeError(f'Mislabeled device: sdk={sdk}, smallestWidthDp={smallest_dp:.1f}, class={args.device_class}')
    receipt.update({'sdk': sdk, 'display_pixels': {'width': width, 'height': height},
                    'density': density_value, 'smallest_width_dp': smallest_dp,
                    'target_sdk': 36})


def rotate(adb, serial, rotation):
    adb_run(adb, serial, 'shell', 'wm', 'user-rotation', 'lock', str(rotation))


def screenshot(adb, serial, output, phase):
    path = output / f'{phase}-physical-display.png'
    image = subprocess.check_output([adb, '-s', serial, 'exec-out', 'screencap', '-p'], timeout=30)
    if not image.startswith(b'\x89PNG\r\n\x1a\n'):
        raise RuntimeError(f'ADB screencap did not return PNG during {phase}')
    path.write_bytes(image)
    # PNG IHDR dimensions are a physical-display observation, intentionally
    # retained beside the Flutter viewport marker to expose letterboxing.
    return str(path)


def run_phase(adb, flutter, args, phase, landscape_rotation, force_stop=False):
    log_path = args.output / f'{phase}.log'
    command_line = [flutter, 'test', '--no-pub', 'integration_test/android_orientation_lock_test.dart',
                    '-d', args.serial, '--flavor', 'alpha', '--reporter', 'expanded',
                    f'--dart-define=NATIVE_PHASE={phase}']
    process = subprocess.Popen(command_line, cwd=Path.cwd(), text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert process.stdout is not None
    result = {'phase': phase, 'command': command_line, 'log': str(log_path),
              'status': 'incomplete', 'observations': {}}
    observation = None
    forced = False
    with log_path.open('w') as log:
        deadline = time.monotonic() + 780
        while time.monotonic() < deadline:
            line = process.stdout.readline()
            if line:
                log.write(line)
                log.flush()
                print(f'[{phase}] {line}', end='')
                if line.strip() in ('E01_LOCK_TOGGLED', 'E01_RELAUNCH_READY', 'E01_UNLOCK_TOGGLED'):
                    rotate(adb, args.serial, landscape_rotation)
                    result.setdefault('host_rotation_requests', []).append({
                        'checkpoint': line.strip(),
                        'requested_rotation': 'landscape',
                        'rotation_value': landscape_rotation,
                        'wm_user_rotation': adb_text(adb, args.serial, 'shell', 'wm', 'user-rotation'),
                    })
                matched = VIEWPORT.search(line)
                if matched:
                    scenario, width, height, portrait, pid = matched.groups()
                    try:
                        observation = {'scenario': scenario, 'width': int(width), 'height': int(height),
                                       'portrait': portrait == 'true', 'pid': int(pid)}
                    except ValueError as exc:
                        raise RuntimeError(f'Invalid fixture viewport marker: {line.rstrip()}') from exc
                    result['observations'][scenario] = observation
                    if scenario == phase:
                        result['viewport'] = observation
                        result['viewport_portrait'] = observation['portrait']
                    result.setdefault('screenshots', {})[scenario] = screenshot(adb, args.serial, args.output, scenario)
                    if force_stop:
                        adb_run(adb, args.serial, 'shell', 'am', 'force-stop', PACKAGE)
                        result['force_stop'] = {'requested': True, 'pid_before': observation['pid'],
                                                'pid_after': adb_text_optional(adb, args.serial, 'shell', 'pidof', PACKAGE)}
                        forced = True
                        break
                if 'E01_RELAUNCH_PERSISTED' in line:
                    result['persisted'] = True
                if 'E01_UNLOCK_PERSISTED' in line:
                    result['persisted'] = True
            elif process.poll() is not None:
                break
            else:
                time.sleep(.1)
        else:
            process.kill()
            raise TimeoutError(f'{phase} fixture timed out')
    if force_stop:
        if not forced:
            process.kill()
            raise RuntimeError('Lock fixture never produced a native viewport before force-stop')
        process.wait(timeout=30)
        result['status'] = 'force-stopped'
        return result
    exit_code = process.wait(timeout=30)
    result['exit_code'] = exit_code
    if exit_code != 0:
        raise RuntimeError(f'{phase} Flutter test failed with exit {exit_code}; see {log_path}')
    if observation is None:
        raise RuntimeError(f'{phase} fixture produced no native viewport; see {log_path}')
    if phase == 'relaunch' and result.get('persisted') != True:
        raise RuntimeError(f'{phase} fixture did not confirm persisted setting')
    result['status'] = 'passed'
    return result


if __name__ == '__main__':
    main()
