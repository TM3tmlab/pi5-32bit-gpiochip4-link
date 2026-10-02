# pi5-32bit-gpiochip-fix

Raspberry Pi 5 に 32 ビット版 Raspberry Pi OS を入れた環境で、gpiozero / lgpio が GPIO を開けない問題の回避策です。udev ルールで `/dev/gpiochip4` → RP1(40 ピンヘッダの GPIO)のシンボリックリンクを作り、**利用者のコードを変えずに** gpiozero を動かします。

> **English summary**
> Workaround for **gpiozero / lgpio failing on Raspberry Pi 5 running 32-bit Raspberry Pi OS** (armhf userland, `rpi-v8` kernel, e.g. `6.12.x+rpt-rpi-v8`).
> On this setup the RP1 GPIO chip (`pinctrl-rp1`, 40-pin header) gets a dynamic number such as `gpiochip15`, and neither `/dev/gpiochip0` nor `/dev/gpiochip4` exists, even though the device tree has the alias `gpiochip0 = rp1 gpio`.
> As a result gpiozero's `LGPIOFactory` fails with `'can not open gpiochip'` and falls back to RPi.GPIO, which does not support Pi 5.
> This repository installs a udev rule that creates a `/dev/gpiochip4` symlink to the RP1 chip, so both the APT (`python3-gpiozero 2.0.1-0+rpt1`) and PyPI (`2.0.1.post1+`) versions of gpiozero work without code changes.
>
> Keywords: Raspberry Pi 5, Pi5, 32-bit, 32bit, armhf, Bookworm, rpi-v8, kernel8.img, gpiozero, lgpio, gpiochip0, gpiochip4, gpiochip15, pinctrl-rp1, RP1, udev, PinFactoryFallback, BadPinFactory, can not open gpiochip

## 対象環境

| 項目 | 内容 |
|---|---|
| ボード | Raspberry Pi 5(Pi 500 / CM5 も同系統) |
| OS | Raspberry Pi OS **32 ビット版**(armhf)Bookworm |
| カーネル | `rpi-v8`(`kernel8.img`)例: `6.12.109+rpt-rpi-v8` |
| ライブラリ | gpiozero(lgpio ピンファクトリ)、lgpio |

64 ビット版 Raspberry Pi OS(`rpi-2712` カーネル)では RP1 が `gpiochip0` になるため、この対処は不要です。

## 症状

gpiozero でデバイスを作ると、次のようなエラーになります。

```text
PinFactoryFallback: Falling back from lgpio: 'can not open gpiochip'
PinFactoryFallback: Falling back from rpigpio: No module named 'RPi'
PinFactoryFallback: Falling back from pigpio: No module named 'pigpio'
PinFactoryFallback: Falling back from native: unable to open /dev/gpiomem or /dev/mem; upgrade your kernel or run as root
gpiozero.exc.BadPinFactory: Unable to load any default pin factory!
```

RPi.GPIO がインストールされている環境では、最後のエラーが次のように変わります。

```text
RuntimeError: Cannot determine SOC peripheral base address
```

lgpio を直接使っても、root で実行しても失敗します。

```text
>>> lgpio.gpiochip_open(0)
lgpio.error: 'can not open gpiochip'
```

## 原因

実機で確認した状態は次のとおりです。

```text
$ gpiodetect
gpiochip11 [gpio-brcmstb@107d517c00] (17 lines)
gpiochip12 [gpio-brcmstb@107d517c20] (6 lines)
gpiochip13 [gpio-brcmstb@107d508500] (32 lines)
gpiochip14 [gpio-brcmstb@107d508520] (4 lines)
gpiochip15 [pinctrl-rp1] (54 lines)
```

| デバイスツリーの別名 | 指している実体 | 実際の番号 |
|---|---|---|
| `gpiochip0` | `/axi/pcie@1000120000/rp1/gpio@d0000`(RP1) | `gpiochip15` |
| `gpiochip10` | `/soc@107c000000/gpio@7d508500` | `gpiochip13` |

- Raspberry Pi のカーネルは、Pi 5 で RP1 を `gpiochip0` に固定する変更を入れています([raspberrypi/linux#6144](https://github.com/raspberrypi/linux/pull/6144))。デバイスツリーにもその別名が入っています。
- しかし、32 ビット版 OS が Pi 5 で使う `rpi-v8` カーネルでは、この別名が使われていないようで、番号が自動割り当て(上の例では 11〜15)になります。
- gpiozero は Pi 5 では「`/dev/gpiochip4` があれば 4、なければ 0」を開きます(APT 版 `2.0.1-0+rpt1` は無条件に 4)。この環境ではどちらも存在しないため失敗します。

関連: [gpiozero/gpiozero#1166](https://github.com/gpiozero/gpiozero/issues/1166)(カーネル 6.6.45 で Pi 5 のチップ番号が 4 → 0 に変わった件)

## 使い方

### 1. 診断する(任意)

```bash
git clone https://github.com/TM3tmlab/pi5-32bit-gpiochip4-link.git
cd pi5-32bit-gpiochip-fix
bash check.sh
```

最後の `Verdict` に `NG` と出ていれば、この対処の対象です。

### 2. 導入する

```bash
sudo bash install.sh
```

成功すると、次のように表示されます。再起動は不要です。

```text
[INFO]  成功: /dev/gpiochip4 -> gpiochip15
```

- 何度実行しても問題ありません。
- Pi 5 系以外、または 64 ビット版 OS では中止します。それでも入れる場合は `--force` を付けてください。

### 3. 確認する

```bash
bash check.sh
```

`Verdict` が `OK` になっていれば完了です。以後は gpiozero のコードを変えずに動きます。

```python
from gpiozero import LED
led = LED(25)
led.on()
```

### 削除する

```bash
sudo bash uninstall.sh
```

## 仕組み

`/etc/udev/rules.d/99-rp1-gpiochip4.rules` に次のルールを置きます。

```text
SUBSYSTEM=="gpio", KERNEL=="gpiochip*", DRIVERS=="pinctrl-rp1", SYMLINK+="gpiochip4"
```

番号ではなくドライバ名(`pinctrl-rp1`)で RP1 を特定するので、カーネル更新で番号が変わっても追従します。リンク先のデバイスの権限(`root:gpio`, `0660`)はそのままです。

## 代替: コード側で対処する

udev ルールを入れられない場合は、ラベルで RP1 を探してピンファクトリに渡す方法もあります。gpiozero **2.0.1.post1 以降**が必要です(それ以前の版は `chip` 引数を無視します)。

```python
from find_chip import use_header_gpiochip   # examples/find_chip.py
use_header_gpiochip()                       # gpiozero のデバイスを作る前に呼ぶ

from gpiozero import LED
led = LED(25)
```

## FAQ

**Q. 64 ビット版 OS に入れたままでも問題ありませんか?**
A. 問題ありません。RP1 が `gpiochip0` なので、`gpiochip4` も同じ RP1 を指すリンクになるだけです。ただし不要なので、移行後は `uninstall.sh` で削除しておくと整理できます。

**Q. SPI(MCP3208 など)にも影響しますか?**
A. 影響しません。SPI は `/dev/spidev*` を使います。`raspi-config` で SPI を有効にしてください。

**Q. 複数台に展開するには?**
A. 1 台で `install.sh` が成功したことを確認してから、各台で実行してください。SD カードを複製する場合は、マスターに導入しておけば済みます。

## この対処が不要になる条件

- 64 ビット版 Raspberry Pi OS に移行したとき
- `rpi-v8` カーネルでも RP1 が `gpiochip0` になるよう、カーネル側が修正されたとき

どちらかになったら、このリポジトリはアーカイブして構いません。

## 免責

現状のまま提供します。自己責任で使ってください。

## ライセンス

[The Unlicense](LICENSE)(パブリックドメイン)
