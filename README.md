<p align="center">
  <img src="depiction/icon.png" width="160" alt="LockScreenRestore">
</p>

<h1 align="center">LockScreenRestore</h1>

<p align="center">
  <a href="../../releases/latest"><img src="https://img.shields.io/github/v/release/aronsz26/LockScreenRestore?label=release&color=1E6FE0" alt="Latest release"></a>
  <a href="https://aronsz26.github.io/"><img src="https://img.shields.io/badge/repo-aronsz26.github.io-1E6FE0?logo=github&logoColor=white" alt="Sileo repo"></a>
  <img src="https://img.shields.io/badge/iOS-16-555555?logo=apple&logoColor=white" alt="iOS 16">
  <img src="https://img.shields.io/badge/jailbreak-rootless-555555" alt="Rootless">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="License MIT"></a>
</p>

Brings the iOS 15 lock screen back to iOS 16: clock, notifications, music player, unlock animation, live and dynamic wallpapers and the old **Settings → Wallpaper** page. Every part has its own switch.

<p align="center">
  <img src="screenshots/lockscreen.png" width="200" alt="Lock screen with the iOS 15 clock, padlock and Focus pill">
  &nbsp;
  <img src="screenshots/notifications.png" width="200" alt="iOS 15 notification cards listed under the clock">
  &nbsp;
  <img src="screenshots/music.png" width="200" alt="iOS 15 music player with large artwork, app icon, AirPlay button and volume slider">
</p>

## Links

| | |
| --- | --- |
| Sileo / Zebra repo | `https://aronsz26.github.io/` |
| Download | [latest release](../../releases/latest) (`.deb`) |
| Help | [issues](../../issues): please add your model, iOS version and a screenshot |

## What it changes

| | |
| --- | --- |
| Clock | thin iOS 15 clock and date, big padlock, no depth effect or widgets |
| Focus | the Focus pill under the date |
| Notifications | iOS 15 cards right under the clock, Notification Centre on swipe up, pull down for search |
| Music player | iOS 15 layout with large artwork, AirPlay and volume slider |
| Unlock | the home screen wallpaper follows your swipe |
| Wallpaper | live, dynamic and still wallpapers with Perspective Zoom, separate lock and home screen, the iOS 15 Settings → Wallpaper page with downloads |
| Home screen | the lighter iOS 15 shadow under app names |

Switches are in **Settings → Tweaks → LockScreenRestore** and apply after **Apply (Respring)**. Apple's wallpapers are not in this repository; the Wallpaper page downloads them from the [SniperGER/iOS-Wallpapers](https://github.com/SniperGER/iOS-Wallpapers) archive.

## Devices

| iPhone | iOS | Status |
| --- | --- | --- |
| 13 Pro, 12 Pro | 16.1.1, 16.5 | tested |
| X, 11, 8 Plus | 16.7, 16.1, 16.2 | reported working by users |
| other iPhones without Dynamic Island | 16.x | should work, untested |
| 14 Pro and newer (Dynamic Island) | 16.x | installs, but not adjusted |

Rootless jailbreaks (tested with Dopamine) on iOS 16 only; the package does not install on iOS 17 and later.

> [!NOTE]
> Support for iOS 17 and later is planned. I'm busy with other projects right now, so it will take a while.

> [!TIP]
> If your iPhone lands in Safe Mode, turn the part that caused it off in the tweak's settings or uninstall the package, and please open an issue.

## Building

```bash
export THEOS=~/theos
make package FINALPACKAGE=1
```

Needs [Theos](https://theos.dev) and the iOS 16.5 SDK. Without `FINALPACKAGE=1`, debug tools for SSH testing are built in (`DebugTools.m`).

## License

[MIT](LICENSE)
