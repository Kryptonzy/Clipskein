#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
export CLANG_MODULE_CACHE_PATH="$SCRIPT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$SCRIPT_DIR/.build/module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
cd "$SCRIPT_DIR"
swift run ClipNest
