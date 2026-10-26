# aerox-buttons

Extra mouse buttons → real macOS actions.

Configure your mouse's side buttons to emit `F3` / `F4`, and this daemon turns
them into **Mission Control** and the **Applications** launcher.

Tested on **SteelSeries Aerox 5 Wireless** with **macOS 26.6.2** on Apple
Silicon (M4 Pro). See [Supported devices](#supported-devices).

---

## Why this exists

SteelSeries GG, the official configurator, does not work on modern Macs.

The reason is a hard architectural block, not a bug you can fix by reinstalling:

```
kernelmanager_helper: unable to load extension:
/Library/Extensions/SteelSeriesEngine3Driver.kext:
Incompatible architecture: Binary is for x86_64, but needed arch arm64e
```

That kext is **still shipped as x86_64-only** in the current macOS installer
(`SteelSeriesGG108.3.0.pkg`, verified by extracting the payload). On Apple
Silicon the kernel is `arm64e` and Rosetta does not translate kernel code, so
the driver can never load — and without it Engine enumerates zero devices.
GG on macOS is also in maintenance mode: SteelSeries states it "will no longer
receive new features or regular updates on macOS".

So GG is not an option. The mouse itself is fine, and its onboard memory holds
button mappings independently of any software. That is the opening this project
uses: configure the buttons *once* with [rivalcfg](https://github.com/flozz/rivalcfg)
(open source, works on macOS), then translate the resulting keystrokes with a
tiny native daemon.

## How it works

```
rivalcfg ──writes once──> mouse onboard memory ──emits F3/F4──> aerox-buttons ──> macOS action
```

1. **`rivalcfg`** writes the mapping to the mouse's onboard profile. Requires a
   USB cable (or the 2.4 GHz dongle) — rivalcfg cannot talk to the mouse over
   Bluetooth. Once written, it survives unplugging.
2. **The mouse** now sends `F3` / `F4` on the configured buttons, over USB or
   Bluetooth.
3. **`aerox-buttons`** watches the SteelSeries HID device, and on those keys
   runs `open -b com.apple.exposelauncher` (Mission Control) or
   `open -b com.apple.apps.launcher` (Applications).

## Why a daemon at all?

Because a plain `F3` keystroke does not trigger Mission Control.

The keyboard's F3 key does not send the standard `F3` keycode — it sends a
consumer-control event, which is what macOS binds to Mission Control. rivalcfg
can only emit standard keyboard-page (`0x07`) usages for the keys it supports,
and the macOS shortcut system will not accept a synthetic F3 for Mission
Control either (writing `com.apple.symbolichotkeys` is reverted by `cfprefsd`).

So the keystroke has to be translated by something that listens to HID directly.
That is all this daemon is: ~100 lines of C.

## Supported devices

Written and verified for the **Aerox 5 Wireless**. The daemon is not
model-specific — it reacts to `F3`/`F4` from any SteelSeries device — but the
`configure-mouse.sh` mapping assumes the Aerox 5 Wireless button layout:

| Button | Physical location    | Mapping          |
|--------|----------------------|------------------|
| 8      | left side, `←`       | `F3` → Mission Control |
| 9      | left side, top       | `F4` → Applications    |

`rivalcfg` also supports, in the same family: **Aerox 5** (wired), **Aerox 3**
and **Aerox 3 Wireless**, **Aerox 9 Wireless** — with different button counts.
Adjust the button numbers in `scripts/configure-mouse.sh`.

> Aerox 9 Wireless has no `buttons_mapping` in rivalcfg, so its extra buttons
> cannot be remapped at all.

Over Bluetooth, the Aerox 5 Wireless exposes vendor ID **`0x0111`**; over USB it
is **`0x1038`**. The daemon matches both.

## Requirements

- macOS on **Apple Silicon** (also fine on Intel)
- Xcode Command Line Tools (`xcode-select --install`) for `clang`
- Python 3.9+ (system Python is enough) for rivalcfg
- A USB cable, for the one-time mapping

## Install

```bash
git clone https://github.com/RFernandesCaldas/aerox-buttons.git
cd aerox-buttons

# 1. Configure the mouse (USB cable plugged in)
./scripts/configure-mouse.sh

# 2. Install the daemon + login item
./scripts/install.sh
```

`install.sh` compiles the daemon, wraps it in a signed `.app`, and registers a
LaunchAgent that **starts it at login and restarts it if it dies**.

It will ask for **Input Monitoring** permission. If no prompt appears:

**System Settings → Privacy & Security → Input Monitoring → enable "Aerox Buttons"**

then reload the agent:

```bash
launchctl unload ~/Library/LaunchAgents/com.roberto.aerox-buttons.plist
launchctl load   ~/Library/LaunchAgents/com.roberto.aerox-buttons.plist
```

Check it is alive:

```bash
cat /tmp/aerox-buttons.log     # expect: started OK
```

Press the buttons. The log should gain a line per press:

```
F3 -> Mission Control (toggle)
F4 -> Applications
```

## Manual install

If you prefer to do it by hand:

```bash
mkdir -p ~/.aerox-buttons
clang -O2 -o ~/.aerox-buttons/aerox-buttons src/aerox-buttons.c \
    -framework IOKit -framework CoreFoundation -framework ApplicationServices
~/.aerox-buttons/aerox-buttons &        # run in the foreground to test
```

A bare binary launched from a terminal works. To start it at login it must be
wrapped in a signed `.app` — `launchd` will not grant Input Monitoring to a
plain executable (it fails with `kIOReturnNotPermitted` / `0xe00002c7`). That is
what `install.sh` builds for you.

The installed LaunchAgent runs the bundle binary directly (not via `open`), so
launchd owns the process:

| Key | Value | Why |
|---|---|---|
| `RunAtLoad` | `true` | starts at login |
| `KeepAlive` | `SuccessfulExit: false` | restarts if it crashes; does not loop when it is quit normally |
| `ThrottleInterval` | `10` | back-off so a persistent failure cannot spin |
| `LimitLoadToSessionType` | `Aqua` | GUI session only, needed for TCC |

Check it:

```bash
launchctl print gui/$(id -u)/com.roberto.aerox-buttons | grep -E 'state|pid|runs'
```

Expect `state = running` and a `pid`. Verified that killing the process gets it
restarted automatically (`runs` increments).

## Configure different actions

Edit the two `run(...)` calls in `src/aerox-buttons.c`:

```c
if (idx == 0) {
    logmsg("F3 -> Mission Control (toggle)");
    run((const char *const[]){ "/usr/bin/open", "-b", "com.apple.exposelauncher", NULL });
} else {
    logmsg("F4 -> Applications");
    run((const char *const[]){ "/usr/bin/open", "-b", "com.apple.apps.launcher", NULL });
}
```

Then re-run `./scripts/install.sh`.

Useful bundle IDs:

| Action              | Command                                          |
|---------------------|--------------------------------------------------|
| Mission Control     | `open -b com.apple.exposelauncher`               |
| Applications        | `open -b com.apple.apps.launcher`                |
| Spotlight           | `open -b com.apple.Spotlight`                    |
| Notification Center | `open -b com.apple.notificationcenterui`         |

`com.apple.exposelauncher` is a **toggle**, exactly like the keyboard's F3 key:
press once to open, again to close.

### Mapping other keys

`rivalcfg` accepts keyboard keys, mouse buttons and a few multimedia keys:

```bash
~/.rivalcfg/bin/rivalcfg -b "buttons(layout=QWERTY; button8=F13; button9=VolumeUp)"
```

Available: `A`–`Z`, `F1`–`F24`, modifiers, navigation keys, keypad, plus
`Mute`, `PlayPause`, `Next`, `Previous`, `VolumeUp`, `VolumeDown`, `dpi`,
`disabled`. If you use a key your physical keyboard does not have (`F13`+), you
can bind it in System Settings without any conflict.

Always keep `button1=` mapped, or you lose left click.

## Troubleshooting

**Nothing happens, log is empty.**
Input Monitoring is not granted. See above. Verify:

```bash
sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
  "select client,auth_value from access where service='kTCCServiceListenEvent';"
```

`auth_value=2` means allowed, `0` means denied.

**Log says `FAILED to open HID manager`.**
Same cause — missing Input Monitoring, or the daemon was started by `launchd`
from a bare binary instead of the signed `.app`.

**Buttons do nothing but the log shows presses.**
Your `open` target failed. Test it by hand:
`open -b com.apple.exposelauncher`.

**Override the log path.** It is hardcoded to `/tmp/aerox-buttons.log` — edit
`LOG` in the source.

**Keep SteelSeries GG uninstalled (or quit).** GG grabs the same HID events and
consumes them, so the buttons appear dead while it runs. Verified: with GG
running the volume keys did nothing; after quitting GG the same mapping worked.

**You re-ran `install.sh` and the buttons stopped working.**
The ad-hoc signature's `cdhash` is the TCC identity, and builds are not
bit-reproducible — so a rebuild revokes the grant silently. `install.sh` only
rebuilds when `src/aerox-buttons.c` is newer than the binary; when it does
rebuild it warns you. Re-enable Input Monitoring after any rebuild. To clear a
stale entry:

```bash
tccutil reset ListenEvent com.roberto.aerox-buttons
```

**The mouse stopped responding to the mapping.** Reconnect the cable and re-run
`scripts/configure-mouse.sh`. Check the mapping is really stored:

```bash
~/.rivalcfg/bin/rivalcfg --battery-level       # proves HID comms work
```

## Uninstall

```bash
./scripts/uninstall.sh
```

This removes the daemon and the login item. The mouse keeps its F3/F4 mapping —
reset it with `~/.rivalcfg/bin/rivalcfg -b default` if you want the buttons back
to factory behaviour.

## Files

| Path | Purpose |
|---|---|
| `src/aerox-buttons.c` | The daemon (~100 lines of C) |
| `scripts/install.sh` | Compile, bundle, sign, install login item |
| `scripts/configure-mouse.sh` | Write F3/F4 into the mouse's onboard memory |
| `scripts/uninstall.sh` | Remove everything |

## Notes and limitations

- No GUI. It is a background agent.
- Mission Control is a toggle, matching the keyboard's F3 behaviour. An earlier
  version tried to detect whether Mission Control was already open and skip the
  press; that was removed because the window-list signal is unreliable (opening
  the Applications launcher produces the same Dock window pattern).
- `LSBackgroundOnly` is set, so the app has no Dock icon and no window.
- Only `F3` / `F4` are handled. Add more usages in `cb()` if you need them.

## Licence

MIT
