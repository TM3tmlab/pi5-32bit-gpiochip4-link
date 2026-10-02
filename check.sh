#!/usr/bin/env bash
# check.sh - Pi 5 の GPIO チップ構成と gpiozero / lgpio の状態を診断する
#   Diagnose gpiochip numbering and gpiozero / lgpio status on Raspberry Pi 5.
#
# 使い方 / Usage: bash check.sh   (root 不要 / no root required)
#   venv を有効にした状態で実行すると、その venv の gpiozero / lgpio も確認する
set -u

PY="${PYTHON:-python3}"

section() { printf '\n=== %s ===\n' "$*"; }

driver_of() {
    udevadm info -a -n "$1" 2>/dev/null \
        | grep -m1 -o 'DRIVERS=="[^"]\+"' | cut -d'"' -f2
}

section "System"
echo "Model     : $(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo unknown)"
echo "Arch      : $(dpkg --print-architecture 2>/dev/null || echo unknown) (userland), LONG_BIT=$(getconf LONG_BIT)"
echo "Kernel    : $(uname -r)"

section "gpiochip devices"
for dev in /dev/gpiochip*; do
    [[ -e $dev ]] || { echo "(none)"; break; }
    if [[ -L $dev ]]; then
        echo "$dev -> $(readlink "$dev")  [symlink]"
    else
        echo "$dev  driver=$(driver_of "$dev")"
    fi
done
if command -v gpiodetect >/dev/null; then
    echo "--- gpiodetect (シンボリックリンク分も重複して表示されます) ---"
    gpiodetect
fi

section "Device tree aliases (gpiochip*)"
found=0
for a in /proc/device-tree/aliases/gpiochip*; do
    [[ -e $a ]] || continue
    found=1
    echo "$(basename "$a") = $(tr -d '\0' < "$a")"
done
[[ $found -eq 1 ]] || echo "(none)"

section "udev rule"
if [[ -f /etc/udev/rules.d/99-rp1-gpiochip4.rules ]]; then
    echo "installed: /etc/udev/rules.d/99-rp1-gpiochip4.rules"
else
    echo "not installed"
fi

section "Python packages ($PY)"
echo "APT python3-gpiozero : $(dpkg-query -W -f='${Version}' python3-gpiozero 2>/dev/null || echo 'not installed')"
echo "APT python3-lgpio    : $(dpkg-query -W -f='${Version}' python3-lgpio 2>/dev/null || echo 'not installed')"
"$PY" - <<'EOF'
try:
    import gpiozero
    try:
        from importlib.metadata import version
        ver = version("gpiozero")
    except Exception:
        ver = getattr(gpiozero, "__version__", "unknown")
    print(f"import gpiozero       : {ver}  ({gpiozero.__file__})")
except Exception as e:
    print(f"import gpiozero       : NG ({e})")
try:
    import lgpio
    print(f"import lgpio          : OK  ({lgpio.__file__})")
except Exception as e:
    print(f"import lgpio          : NG ({e})")
EOF

section "lgpio open test"
"$PY" - <<'EOF'
import glob
try:
    import lgpio
except ImportError:
    print("lgpio not available")
    raise SystemExit
for n in (0, 4):
    try:
        h = lgpio.gpiochip_open(n)
        _, lines, name, label = lgpio.gpio_get_chip_info(h)
        lgpio.gpiochip_close(h)
        print(f"gpiochip{n}: OK  label={label} lines={lines}")
    except lgpio.error as e:
        print(f"gpiochip{n}: NG  ({e})")
EOF

section "Verdict"
if [[ -e /dev/gpiochip0 ]] && [[ "$(driver_of /dev/gpiochip0)" == "pinctrl-rp1" ]]; then
    echo "OK: RP1 は gpiochip0 です (標準構成)。この対処は不要です"
elif [[ -e /dev/gpiochip4 ]] && [[ "$(driver_of "$(readlink -f /dev/gpiochip4)")" == "pinctrl-rp1" ]]; then
    echo "OK: /dev/gpiochip4 が RP1 を指しています。gpiozero はそのまま動くはずです"
else
    echo "NG: gpiochip0 / gpiochip4 のどちらも RP1 ではありません"
    echo "    sudo bash install.sh を実行してください"
fi
