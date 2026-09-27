# LockScreenRestore

Brings the iOS 15 lock screen back to iOS 16.

<p align="center">
  <img src="screenshots/lockscreen.jpg" width="300" alt="Lock screen with the iOS 15 clock, date and Focus pill">
  &nbsp;&nbsp;
  <img src="screenshots/notifications.jpg" width="300" alt="Notifications listed under the clock like on iOS 15">
</p>

## Features

Every part can be switched on and off separately in Settings.

- **iOS 15 Clock**
  - Thin clock with the date below it, written out as "Sunday, September 27"
  - Plain white text instead of iOS 16's tinted, slightly see-through look
  - Big padlock that stays open after Face ID instead of shrinking away
  - No depth effect: the wallpaper no longer covers the clock
  - No lock screen widgets (iOS 15 had none)
  - Sizes and positions measured against Apple's iOS 15 lock screen
- **iOS 15 Focus**
  - The Focus pill under the date (tap it to switch Focus), instead of the Focus name at the bottom of the screen
- **iOS 15 Notifications**
  - Notifications listed right under the clock instead of collected at the bottom of the screen
  - iOS 15's narrower side margins

## Settings

**Settings → LockScreenRestore**

| Switch | Default |
|---|---|
| iOS 15 Clock | On |
| iOS 15 Focus | On |
| iOS 15 Notifications | On |

Changes take effect after a respring. Use the **Apply (Respring)** button at the bottom of the page.

## Compatibility

| | |
|---|---|
| Tested on | iPhone 13 Pro, iOS 16.1.1, Dopamine (rootless), ElleKit |
| Jailbreak type | Rootless only |
| Other iOS 16 versions | Untested |
| Other devices | Untested. Positions are tuned for 390pt-wide screens (iPhone 12, 12 Pro, 13, 13 Pro, 14), so other screen sizes may be slightly off. |

If you try it on another device or iOS version, please open an issue and tell me how it went.

## Installation

1. Download the `.deb` from the [latest release](../../releases/latest).
2. Open it with Sileo, Zebra or Filza and install it.
3. The package needs **PreferenceLoader**. Your package manager installs it automatically if it's missing.

For the full iOS 15 look, also set **Settings → Notifications → Display As → List**.

## Building from source

You need [Theos](https://theos.dev) and the iOS 16.5 SDK (included in `theos/sdks`).

```bash
git clone https://github.com/aronsz26/LockScreenRestore.git
cd LockScreenRestore
export THEOS=~/theos
make package FINALPACKAGE=1
```

To install straight onto a device over SSH:

```bash
export THEOS_DEVICE_IP=<your iPhone's IP>
make package FINALPACKAGE=1 install
```

### Debug builds

`make package` without `FINALPACKAGE=1` also compiles [`DebugTools.m`](DebugTools.m), which lets you inspect the running SpringBoard over SSH: dump the view hierarchy, list a class's methods, or call a getter on a live object. The comment at the top of the file explains how. Release builds leave it out.

## Known limitations

- Notification banners keep iOS 16's style.
- Stacked vs. list view still follows **Settings → Notifications → Display As**.
- Other tweaks that change the lock screen clock, padlock or notification list may conflict.

## License

[MIT](LICENSE)
