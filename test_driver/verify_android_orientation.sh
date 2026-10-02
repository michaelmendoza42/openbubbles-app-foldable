#!/usr/bin/env bash
# Android-only e01 native lock matrix entrypoint. It starts and stops exactly
# one foreground emulator per invocation; do not wrap it in nohup/backgrounding.
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 lock <openbubbles_avd> <android-phone|android-tablet-pre16|android-tablet-16-large>" >&2
  exit 2
fi

mode=$1
avd=$2
device_class=$3
source "$(dirname "$0")/android-env.sh"
export PATH="$HOME/.cargo/bin:$HOME/.local/share/protoc-28.3/bin:$PATH"

output_root="${E01_ANDROID_EVIDENCE_ROOT:-$HOME/.cache/openbubbles-android-validation}"
mkdir -p "$output_root"
output="$output_root/${mode}-${device_class}-$(date -u +%Y%m%dT%H%M%SZ)"
python3 "$(dirname "$0")/verify_android_orientation.py" "$mode" "$avd" "$device_class" --output "$output"
