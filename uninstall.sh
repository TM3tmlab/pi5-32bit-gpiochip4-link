#!/usr/bin/env bash
# uninstall.sh - install.sh で導入した udev ルールを削除する
#   Remove the udev rule installed by install.sh.
#
# 使い方 / Usage: sudo bash uninstall.sh
set -euo pipefail

DEST="/etc/udev/rules.d/99-rp1-gpiochip4.rules"

info() { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "root 権限が必要です: sudo bash uninstall.sh"

if [[ -f $DEST ]]; then
    rm -f "$DEST"
    info "ルールを削除しました: $DEST"
else
    info "ルールは導入されていません: $DEST"
fi

udevadm control --reload-rules
udevadm trigger --action=change --subsystem-match=gpio
udevadm settle

if [[ -L /dev/gpiochip4 ]]; then
    warn "/dev/gpiochip4 のリンクが残っています。再起動すると消えます"
else
    info "完了しました"
fi
