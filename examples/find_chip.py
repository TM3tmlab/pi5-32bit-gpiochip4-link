"""
udev ルールを使わずに、コード側で RP1 の gpiochip を探して gpiozero に渡す例。
Find the RP1 gpiochip by its label and hand it to gpiozero (no udev rule needed).

gpiozero 2.0.1.post1 以降が必要 (それ以前は chip 引数が無視される)。
Requires gpiozero >= 2.0.1.post1 (earlier versions ignore the chip argument).

使い方 / Usage:
    python3 find_chip.py          # 各 gpiochip のラベル一覧と RP1 の番号を表示

    # 自分のコードでは:
    from find_chip import use_header_gpiochip
    use_header_gpiochip()         # gpiozero のデバイスを作る前に呼ぶ
"""
import glob
import os

import lgpio

HEADER_LABELS = ("pinctrl-rp1",)  # Pi 5 の 40 ピンヘッダ / 40-pin header on Pi 5


def list_gpiochips():
    """(番号, ラベル, ライン数) のリストを返す"""
    chips = []
    for path in glob.glob("/dev/gpiochip*"):
        num = int(path.removeprefix("/dev/gpiochip"))
        try:
            h = lgpio.gpiochip_open(num)
        except lgpio.error:
            continue
        try:
            _, lines, _, label = lgpio.gpio_get_chip_info(h)
        finally:
            lgpio.gpiochip_close(h)
        chips.append((num, label, lines))
    return sorted(chips)


def find_header_gpiochip(labels=HEADER_LABELS):
    """40 ピンヘッダの gpiochip 番号を返す。シンボリックリンクより実体を優先する"""
    candidates = [num for num, label, _ in list_gpiochips() if label in labels]
    if not candidates:
        raise RuntimeError(f"gpiochip not found (labels={labels})")
    # /dev/gpiochip4 が udev ルールのリンクの場合も同じチップが見つかるため、実体を優先
    real = [n for n in candidates if not os.path.islink(f"/dev/gpiochip{n}")]
    return (real or candidates)[0]


def use_header_gpiochip():
    """gpiozero の既定ピンファクトリを、ヘッダの gpiochip を使う LGPIOFactory にする"""
    from gpiozero import Device
    from gpiozero.pins.lgpio import LGPIOFactory

    chip = find_header_gpiochip()
    Device.pin_factory = LGPIOFactory(chip=chip)
    return chip


if __name__ == "__main__":
    for num, label, lines in list_gpiochips():
        path = f"/dev/gpiochip{num}"
        note = f"  -> {os.readlink(path)} (symlink)" if os.path.islink(path) else ""
        print(f"gpiochip{num:<3} label={label:<24} lines={lines}{note}")
    print(f"header gpiochip: {find_header_gpiochip()}")
