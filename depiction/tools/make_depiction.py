# Writes the Sileo native depiction into the repo (aronsz26.github.io). Run: python3 depiction/tools/make_depiction.py https://aronsz26.github.io/depictions/lockscreenrestore ~/aronsz26.github.io/depictions/lockscreenrestore/depiction/sileo.json (and copy screenshots/ + depiction/banner.jpg, icon.png there)
import json, os, sys
base = sys.argv[1].rstrip('/')
out = sys.argv[2]
shot = lambda n, t: {"url": f"{base}/screenshots/{n}", "accessibilityText": t}
details = [
    {"class": "DepictionScreenshotsView", "itemCornerRadius": 14, "itemSize": "{160, 346}", "screenshots": [
        shot("lockscreen.jpg", "Lock screen"), shot("notifications.jpg", "Notifications"),
        shot("music.jpg", "Music player"), shot("settings.jpg", "Settings")]},
    {"class": "DepictionMarkdownView", "useSpacing": True, "markdown":
        "**The iOS 15 lock screen, back on iOS 16.** Thin clock with the date below it, the big padlock, "
        "notifications right under the clock, the iOS 15 music player, live and dynamic wallpapers and the "
        "old Settings → Wallpaper page.\n\nEvery part has its own switch, so you can mix iOS 15 and iOS 16 however you like."},
    {"class": "DepictionHeaderView", "title": "What it changes"},
    {"class": "DepictionMarkdownView", "useSpacing": True, "markdown":
        "🕘 **Clock** – thin iOS 15 clock and date, big padlock that stays open after Face ID, no depth effect\n\n"
        "🔔 **Notifications** – listed right under the clock with iOS 15 cards and the Notification Centre header\n\n"
        "🎵 **Music player** – large artwork with the app's icon, AirPlay button, volume slider\n\n"
        "🌙 **Focus** – the Focus pill under the date\n\n"
        "🔓 **Unlock animation** – the iOS 15 transition to the home screen\n\n"
        "🖼️ **Wallpapers** – Live and Dynamic wallpapers are back, Perspective Zoom, and the iOS 15 Settings → Wallpaper page with Apple's iOS 14/15 wallpapers to download\n\n"
        "🔋 **Charging** – the battery appears where the clock is"},
    {"class": "DepictionHeaderView", "title": "Good to know"},
    {"class": "DepictionMarkdownView", "useSpacing": True, "markdown":
        "Sizes and positions are calculated for every iPhone from iOS 15's own values. "
        "This is a **beta**: feedback and screenshots from other iPhones are very welcome on GitHub. "
        "iPads aren't supported. **iPhones with a Dynamic Island (14 Pro and newer) aren't optimized yet**: you can install it there, but it may look off."},
    {"class": "DepictionSeparatorView"},
    {"class": "DepictionTableTextView", "title": "Compatibility", "text": "iOS 16 · rootless"},
    {"class": "DepictionTableTextView", "title": "Developer", "text": "aronsz26"},
    {"class": "DepictionTableButtonView", "title": "Source code & issues", "action": "https://github.com/aronsz26/LockScreenRestore", "openExternal": True},
    {"class": "DepictionTableButtonView", "title": "Report a problem", "action": "https://github.com/aronsz26/LockScreenRestore/issues", "openExternal": True},
]
changelog = [
    {"class": "DepictionMarkdownView", "useSpacing": True, "markdown":
        "**1.9.4**\n- Music player: a tap on the artwork opens the playing app, like iOS 15\n- Date size follows Text Size like iOS 15\n"
        "- Date keeps iOS 15's font (was too big on iPhone 8)\n- Focus pill sits 19 pt below the date like iOS 15 and can be tapped"},
    {"class": "DepictionMarkdownView", "useSpacing": True, "markdown":
        "**1.9.3**\n- Settings → Wallpaper stays open when you leave Settings and come back\n"
        "- Perspective Zoom moves the right way again\n- iPhone 8 Plus: clock size exactly like iOS 15"},
    {"class": "DepictionMarkdownView", "useSpacing": True, "markdown":
        "**1.9.2**\n- The list below the clock starts where it did on iOS 15\n- Notifications are always shown as a list\n"
        "- The music player shows the playing app's icon on the artwork\n- Focus pill no longer jumps down after scrolling\n"
        "- Reset to Defaults in the settings\n- Settings → Wallpaper: iOS 15 spacing for Dynamic · Stills · Live"},
    {"class": "DepictionMarkdownView", "useSpacing": True, "markdown":
        "**1.9.1**\n- iOS 15 clock size and position on every iPhone"},
    {"class": "DepictionMarkdownView", "useSpacing": True, "markdown":
        "**1.9**\n- Dynamic wallpapers, Perspective Zoom and the iOS 15 unlock animation"},
    {"class": "DepictionTableButtonView", "title": "All releases", "action": "https://github.com/aronsz26/LockScreenRestore/releases", "openExternal": True},
]
dep = {"minVersion": "0.1", "class": "DepictionTabView", "headerImage": f"{base}/depiction/banner.jpg",
       "tintColor": "#8E44C8", "tabs": [
           {"tabname": "Details", "class": "DepictionStackView", "views": details},
           {"tabname": "Changelog", "class": "DepictionStackView", "views": changelog}]}
json.dump(dep, open(out, "w"), indent=2, ensure_ascii=False)
