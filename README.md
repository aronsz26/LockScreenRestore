# LockScreenRestore

Brings the iOS 15 lock screen back to iOS 16.

<p align="center">
  <img src="screenshots/lockscreen.jpg" width="250" alt="Lock screen with the iOS 15 clock and padlock">
  &nbsp;
  <img src="screenshots/notifications.jpg" width="250" alt="Notifications listed under the clock with iOS 15 cards">
  &nbsp;
  <img src="screenshots/settings.jpg" width="250" alt="LockScreenRestore settings">
</p>

## Features

Every part can be switched on and off separately in Settings.

- **iOS 15 Clock**
  - Thin clock with the date below it, written out as "Sunday, September 27"
  - Plain white text instead of iOS 16's tinted, slightly see-through look
  - Big padlock that stays open after Face ID instead of shrinking away
  - No depth effect: the wallpaper no longer covers the clock
  - No lock screen widgets (iOS 15 had none)
  - Sizes and positions adapt to your iPhone's screen (see [How positions are calculated](#how-positions-are-calculated))
- **iOS 15 Focus**
  - The Focus pill under the date (tap it to switch Focus), instead of the Focus name at the bottom of the screen
- **iOS 15 Notifications**
  - Notifications listed right under the clock instead of collected at the bottom of the screen
  - iOS 15's narrower side margins
  - iOS 15 card shape: smaller rounded corners (13 pt instead of 23.5 pt), tighter padding, one-line cards 58 pt tall instead of 66 pt, app icon always vertically centered
- **iOS 15 Music Player**
  - The iOS 15 layout on the lock screen: large artwork, device name above the title, AirPlay next to the title
  - Progress bar with a knob and the times below it, bigger play/pause, previous and next buttons
  - Volume slider (iOS 16 removed it from the lock screen)
  - "Artist — Album" under the title instead of only the artist
- **iOS 15 Live Wallpaper**
  - Live wallpapers are back (iOS 16 removed them): press and hold the lock screen to play
  - Switches automatically between the Light and Dark version with the system appearance
  - Shown on the lock screen and the home screen, including while unlocking
  - Wallpapers aren't included, see [Live wallpapers](#live-wallpapers)

## Settings

**Settings → LockScreenRestore**

| Switch | Default |
|---|---|
| iOS 15 Clock | On |
| iOS 15 Focus | On |
| iOS 15 Notifications | On |
| iOS 15 Music Player | On |
| iOS 15 Live Wallpaper | On (does nothing until wallpapers are added) |
| Wallpaper | Pick one of the wallpapers you added |

Changes take effect after a respring. Use the **Apply (Respring)** button at the bottom of the page.

**Fix Positions** shows which iPhone and screen size were detected and recalculates all positions with a respring. The tweak also does this on its own every time SpringBoard starts.

## Compatibility

Rootless jailbreaks on iOS 16 only. Tested with Dopamine and ElleKit on iOS 16.1.1; other iOS 16 versions are untested.

| iPhone | Screen | Status |
|---|---|---|
| iPhone 13 Pro | 390 × 844 pt | ✅ Tested |
| iPhone 12, 12 Pro, 13, 14 | 390 × 844 pt | Should work (same screen as tested) |
| iPhone X, XS, 11 Pro, 12 mini, 13 mini | 375 × 812 pt | Supported, untested |
| iPhone XR, XS Max, 11, 11 Pro Max | 414 × 896 pt | Supported, untested |
| iPhone 12 Pro Max, 13 Pro Max, 14 Plus | 428 × 926 pt | Supported, untested |
| iPhone 14 Pro, 14 Pro Max | 393 / 430 pt, Dynamic Island | Supported, untested (padlock least certain) |
| iPhone 8, 8 Plus, SE (2nd/3rd gen) | 375 / 414 pt, Touch ID | Supported, untested (padlock least certain) |

Positions are calculated for each screen (see below). If you try it on an untested iPhone, please open an issue with a screenshot.

## How positions are calculated

SpringBoard on iOS 16 still carries per-device lock screen measurements from iOS 15 (`SBFLockScreenMetrics`). The tweak reads them on every launch and combines them with ratios measured on Apple's iOS 15 lock screen:

| Element | Source |
|---|---|
| Date position and size | iOS's own per-device values (`subtitleBaselineOffsetFromTopOfScreen`, `dateLabelFontSize`) |
| Padlock size | iOS's own scale factor (`proudLockScaleFactor`) |
| Clock size | 0.8 × iOS 16's clock size on the same device |
| Clock, padlock and Focus pill position | fixed ratios to the clock size and the date, measured on iOS 15 |

On Touch ID iPhones (iPhone 8, 8 Plus, SE) and Dynamic Island iPhones (iPhone 14 Pro, 14 Pro Max), iOS draws the padlock differently, so the padlock part is the least certain there.

## Live wallpapers

Apple's wallpapers are copyrighted, so they're not part of this repository. Each wallpaper is a folder with four files, the still image and the video for Light and Dark:

```
/var/mobile/Library/LockScreenRestore/Wallpapers/
└── Light Beams Blue/
    ├── Light.heic
    ├── Light.mov
    ├── Dark.heic
    └── Dark.mov
```

The folder name is what **Settings → LockScreenRestore → Wallpaper** shows. Apple's iOS 14/15 live wallpapers (Orbs, Resonance, Light Beams, Twist) come as exactly these still + video pairs; use the files made for your screen size.

While **iOS 15 Live Wallpaper** is on, pressing and holding the lock screen plays the wallpaper instead of opening iOS 16's lock screen editor. Turn the switch off to get the editor back.

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

- Notification text follows **Settings → Display & Brightness → Text Size**. Apple's iOS 15 screenshots use the default size.
- With **iOS 15 Live Wallpaper** on, the long press no longer opens iOS 16's lock screen editor.
- Stacked vs. list view still follows **Settings → Notifications → Display As**.
- Some apps send their own text for the music player (Spotify Connect shows "Listening on …"); that text is shown as the app sends it.
- Other tweaks that change the lock screen clock, padlock, notification list or music player may conflict.

## License

[MIT](LICENSE)
