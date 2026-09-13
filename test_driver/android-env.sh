#!/usr/bin/env bash
# Source this file in a shell before using the user-local Android test tools.
export JAVA_HOME="$HOME/.local/share/jdk/temurin-21"
export ANDROID_HOME="$HOME/.local/share/android/sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$HOME/.local/share/flutter-3.24.0/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
