#!/usr/bin/env bash
set -euo pipefail

WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"
compiler="$WASI_SDK_PATH/bin/clang"

for arg in "$@"; do
  case "$arg" in
    *.cc|*.cpp|*.cxx|*.C)
      compiler="$WASI_SDK_PATH/bin/clang++"
      break
      ;;
  esac
done

filtered=()
for arg in "$@"; do
  case "$arg" in
    -Wl,--start-group|-Wl,--end-group|--start-group|--end-group|-pthread)
      ;;
    *)
      filtered+=("$arg")
      ;;
  esac
done

exec "$compiler" "${filtered[@]}"
