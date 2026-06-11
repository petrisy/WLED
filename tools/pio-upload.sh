#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: tools/pio-upload.sh <platformio-env> <serial-port>

Builds the selected PlatformIO environment and flashes it through the given serial port.

Examples:
  tools/pio-upload.sh esp32c5dev_N4R2 /dev/ttyACM0
  tools/pio-upload.sh esp32p4_16MB /dev/ttyUSB0
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

env_name="${1:-}"
port="${2:-}"

if [[ -z "$env_name" || -z "$port" ]]; then
  usage
  exit 2
fi

if [[ -d /tmp/wled-tools/node-v20.18.3-linux-x64/bin ]]; then
  export PATH="/tmp/wled-tools/node-v20.18.3-linux-x64/bin:$PATH"
fi

if [[ -d /tmp/wled-tools/pio-venv/bin ]]; then
  export PATH="/tmp/wled-tools/pio-venv/bin:$PATH"
fi

export PLATFORMIO_CORE_DIR="${PLATFORMIO_CORE_DIR:-/tmp/wled-tools/platformio-core}"
export PLATFORMIO_SETTING_ENABLE_TELEMETRY="${PLATFORMIO_SETTING_ENABLE_TELEMETRY:-no}"

if [[ -n "${PIO_BIN:-}" ]]; then
  pio="$PIO_BIN"
elif [[ -x /tmp/wled-tools/pio-venv/bin/pio ]]; then
  pio="/tmp/wled-tools/pio-venv/bin/pio"
elif command -v pio >/dev/null 2>&1; then
  pio="$(command -v pio)"
else
  echo "Could not find PlatformIO Core." >&2
  echo "Install PlatformIO, or set PIO_BIN to the pio executable." >&2
  exit 1
fi

exec "$pio" run -e "$env_name" -t upload --upload-port "$port"
