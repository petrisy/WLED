#!/usr/bin/env bash
#set -euo pipefail

usage() {
  cat <<'EOF'
Usage: tools/flash-built-bin.sh [--erase-fs] <platformio-env> <serial-port> [baud] [firmware-bin]

Flashes the already-built ESP32-C5/P4 PlatformIO artifacts:
  bootloader.bin at 0x2000
  partitions.bin at 0x8000
  boot_app0.bin at 0xe000
  firmware.bin at 0x10000

Options:
  --erase-fs   Erase the data filesystem partition before flashing. This removes
               WLED settings and presets, and is useful after partition changes.

Examples:
  tools/flash-built-bin.sh esp32c5dev_N4R2 /dev/ttyACM0
  tools/flash-built-bin.sh esp32p4_16MB /dev/ttyUSB0 460800
  tools/flash-built-bin.sh --erase-fs esp32p4_16MB /dev/ttyUSB0 460800
  tools/flash-built-bin.sh esp32c5dev_N4R2 /dev/ttyACM0 460800 build_output/release/WLED_17.0.0-devV5_ESP32-C5_N4R2.bin
EOF
}

erase_fs="${ERASE_FS:-0}"

while [[ "${1:-}" == --* ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --erase-fs|--erase-data)
      erase_fs=1
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

env_name="${1:-}"
port="${2:-}"
baud="${3:-460800}"
firmware_arg="${4:-}"

if [[ -z "$env_name" || -z "$port" ]]; then
  usage
  exit 2
fi

case "$env_name" in
  esp32c5*) chip="${ESP_CHIP:-esp32c5}" ;;
  esp32p4*) chip="${ESP_CHIP:-esp32p4}" ;;
  *)
    echo "Unsupported env '$env_name'. This helper currently knows ESP32-C5 and ESP32-P4 upload layouts." >&2
    echo "Set ESP_CHIP explicitly or use tools/pio-upload.sh for other boards." >&2
    exit 2
    ;;
esac

build_dir=".pio/build/$env_name"
bootloader="$build_dir/bootloader.bin"
partitions="$build_dir/partitions.bin"
firmware="${firmware_arg:-$build_dir/firmware.bin}"

find_esptool() {
  if [[ -n "${ESPTOOL:-}" && -x "$ESPTOOL" ]]; then
    printf '%s\n' "$ESPTOOL"
    return 0
  fi

  local candidate
  for candidate in \
    "${PLATFORMIO_CORE_DIR:-/tmp/wled-tools/platformio-core}/penv/bin/esptool" \
    /tmp/wled-tools/platformio-core/penv/bin/esptool \
    "$HOME/.platformio/penv/bin/esptool" \
    "$HOME/.espressif/python_env/idf6.1_py3.12_env/bin/esptool" \
    "$HOME/.espressif/python_env/idf6.1_py3.12_env/bin/esptool.py"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  if command -v esptool >/dev/null 2>&1; then
    command -v esptool
    return 0
  fi

  if command -v esptool.py >/dev/null 2>&1; then
    command -v esptool.py
    return 0
  fi

  return 1
}

find_boot_app0() {
  local candidate
  for candidate in \
    "${PLATFORMIO_CORE_DIR:-/tmp/wled-tools/platformio-core}/packages/framework-arduinoespressif32/tools/partitions/boot_app0.bin" \
    /tmp/wled-tools/platformio-core/packages/framework-arduinoespressif32/tools/partitions/boot_app0.bin \
    "$HOME/.platformio/packages/framework-arduinoespressif32/tools/partitions/boot_app0.bin"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

find_python() {
  if [[ -n "${PYTHON:-}" && -x "$PYTHON" ]]; then
    printf '%s\n' "$PYTHON"
    return 0
  fi

  local candidate
  for candidate in \
    "${PLATFORMIO_CORE_DIR:-/tmp/wled-tools/platformio-core}/penv/bin/python" \
    /tmp/wled-tools/platformio-core/penv/bin/python \
    "$HOME/.platformio/penv/bin/python" \
    "$HOME/.espressif/python_env/idf6.1_py3.12_env/bin/python3"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  if command -v python3 >/dev/null 2>&1; then
    command -v python3
    return 0
  fi

  return 1
}

find_fs_partition() {
  local python
  if ! python="$(find_python)"; then
    echo "Could not find python3 to inspect $partitions." >&2
    return 1
  fi

  "$python" - "$1" <<'PY'
import struct
import sys

partition_file = sys.argv[1]
fs_labels = {"spiffs", "littlefs", "ffat", "fatfs", "fs"}

with open(partition_file, "rb") as handle:
    data = handle.read()

for pos in range(0, len(data) - 31, 32):
    entry = data[pos:pos + 32]
    magic = struct.unpack_from("<H", entry, 0)[0]
    if magic == 0xFFFF:
        break
    if magic != 0x50AA:
        continue

    part_type = entry[2]
    offset = struct.unpack_from("<L", entry, 4)[0]
    size = struct.unpack_from("<L", entry, 8)[0]
    label = entry[12:28].split(b"\0", 1)[0].decode("ascii", "replace")

    if part_type == 0x01 and label.lower() in fs_labels:
        print(f"{label} 0x{offset:x} 0x{size:x}")
        sys.exit(0)

print("No filesystem data partition found in partition table.", file=sys.stderr)
sys.exit(1)
PY
}

missing=false
for required in "$bootloader" "$partitions" "$firmware"; do
  if [[ ! -f "$required" ]]; then
    echo "Missing required file: $required" >&2
    missing=true
  fi
done

if [[ "$missing" == true ]]; then
  echo "Build the environment first, or use tools/pio-upload.sh $env_name $port to build and upload in one step." >&2
  exit 1
fi

if ! esptool="$(find_esptool)"; then
  echo "Could not find esptool. Install PlatformIO Core or ESP-IDF esptool first." >&2
  exit 1
fi

if ! boot_app0="$(find_boot_app0)"; then
  echo "Could not find boot_app0.bin from an Arduino ESP32 framework package." >&2
  echo "Run a PlatformIO build once, or set PLATFORMIO_CORE_DIR to the PlatformIO core directory." >&2
  exit 1
fi

echo "Flashing $env_name on $port with $esptool"
echo "Chip: $chip, baud: $baud"

if [[ "$erase_fs" == "1" || "$erase_fs" == "true" || "$erase_fs" == "yes" ]]; then
  if ! fs_partition="$(find_fs_partition "$partitions")"; then
    exit 1
  fi

  read -r fs_label fs_offset fs_size <<< "$fs_partition"
  echo "Erasing $fs_label filesystem partition at $fs_offset, size $fs_size"
  "$esptool" \
    --chip "$chip" \
    --port "$port" \
    --baud "$baud" \
    --before default-reset \
    --after no-reset \
    erase-region "$fs_offset" "$fs_size" || exit 1
fi

"$esptool" \
  --chip "$chip" \
  --port "$port" \
  --baud "$baud" \
  --before default-reset \
  --after hard-reset \
  write-flash \
  -z \
  --flash-mode dio \
  --flash-freq 80m \
  --flash-size detect \
  0x2000 "$bootloader" \
  0x8000 "$partitions" \
  0xe000 "$boot_app0" \
  0x10000 "$firmware"
