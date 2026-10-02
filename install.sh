#!/usr/bin/env bash
# install.sh - Raspberry Pi 5 + 32-bit Raspberry Pi OS 向け
#   /dev/gpiochip4 -> RP1 GPIO chip のシンボリックリンクを作る udev ルールを導入する
#   Install a udev rule that links /dev/gpiochip4 to the RP1 GPIO chip.
#
# 使い方 / Usage: sudo bash install.sh [--force]
#   --force  Pi 5 系 / 32-bit OS 以外でも警告のみで続行する
set -euo pipefail

RULE_NAME="99-rp1-gpiochip4.rules"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SRC_DIR/$RULE_NAME"
DEST="/etc/udev/rules.d/$RULE_NAME"
FORCE=0

info() { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

usage() {
    echo "Usage: sudo bash $(basename "$0") [--force]"
}

for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

# 指定デバイスが RP1 (pinctrl-rp1) の gpiochip かどうか
is_rp1() {
    udevadm info -a -n "$1" 2>/dev/null | grep -q 'DRIVERS=="pinctrl-rp1"'
}

# 条件を満たさないとき: --force なら警告、それ以外は中止
require() {
    local msg="$1"
    if [[ $FORCE -eq 1 ]]; then
        warn "$msg (--force により続行)"
    else
        die "$msg (続行する場合は --force)"
    fi
}

[[ $EUID -eq 0 ]] || die "root 権限が必要です: sudo bash install.sh"
[[ -f $SRC ]] || die "ルールファイルが見つかりません: $SRC"
command -v udevadm >/dev/null || die "udevadm が見つかりません"

# --- 環境確認 / Environment check ---
model="$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo unknown)"
arch="$(dpkg --print-architecture 2>/dev/null || echo unknown)"
info "Model : $model"
info "Arch  : $arch (userland)"
info "Kernel: $(uname -r)"

case "$model" in
    *"Raspberry Pi 5"*|*"Raspberry Pi 500"*|*"Compute Module 5"*) ;;
    *) require "Raspberry Pi 5 系ではありません" ;;
esac

if [[ $arch != "armhf" ]]; then
    require "32-bit (armhf) OS ではありません。64-bit OS では通常この対処は不要です"
fi

# RP1 の gpiochip を探す / Find the RP1 gpiochip
rp1_dev=""
for dev in /dev/gpiochip[0-9]*; do
    [[ -c $dev && ! -L $dev ]] || continue
    if is_rp1 "$dev"; then
        rp1_dev="$dev"
        break
    fi
done
[[ -n $rp1_dev ]] || die "RP1 (pinctrl-rp1) の gpiochip が見つかりません"
info "RP1 GPIO chip: $rp1_dev"

# すでに本物の gpiochip4 が存在する場合 / A real gpiochip4 already exists
if [[ -e /dev/gpiochip4 && ! -L /dev/gpiochip4 ]]; then
    if is_rp1 /dev/gpiochip4; then
        info "RP1 がもともと gpiochip4 です。対処は不要です"
        exit 0
    fi
    die "/dev/gpiochip4 が RP1 以外の実デバイスとして存在するため中止します"
fi

# --- ルール配置 / Install the rule (idempotent) ---
if [[ -f $DEST ]] && cmp -s "$SRC" "$DEST"; then
    info "ルールは導入済みです: $DEST"
else
    install -m 0644 "$SRC" "$DEST"
    info "ルールを配置しました: $DEST"
fi

# --- 即時反映 / Apply without reboot ---
udevadm control --reload-rules
udevadm trigger --action=change --subsystem-match=gpio
udevadm settle

# --- 確認 / Verify ---
if [[ -L /dev/gpiochip4 ]] && is_rp1 "$(readlink -f /dev/gpiochip4)"; then
    info "成功: /dev/gpiochip4 -> $(readlink /dev/gpiochip4)"
else
    warn "/dev/gpiochip4 がまだ作成されていません。再起動後に check.sh で確認してください"
    exit 1
fi
