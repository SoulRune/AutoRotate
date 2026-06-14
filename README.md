# AutoRotate

Per-app **orientation lock** for jailbroken iOS 15–16+ (rootless and rootful).

Pick any app — system apps like Settings and Safari included — and hard-lock it to the
orientations you choose. Tick a single orientation for a true lock; tick several to allow
rotation only among them. Everything is configured from a **Settings → AutoRotate** panel
and nothing changes until you tap **Apply**.

> This is a ground-up rewrite. The original AutoRotate was a SpringBoard
> homescreen/lockscreen rotation tweak for iOS 10–16; v2 is a different tool focused on
> per-app orientation locking.

## Features

- **Master switch** — one toggle gates the whole tweak.
- **Per-app picker** (via AppList) — system + user apps, with icons; enabled apps are
  highlighted and floated to the top.
- **Four orientations per app** — Portrait, Portrait upside down, Landscape left,
  Landscape right, each its own switch.
- **Explicit Apply** — changes are staged in a draft and only go live on Apply. No
  silent auto-applying.
- **Reset to defaults** and **Respring** buttons.
- **Hard lock** — returns an exact orientation mask at both the app and view-controller
  level *and* actively drives the window-scene geometry on launch/activate, so apps
  (notably stubborn system apps) don't free-spin or snap back to portrait.

## How the lock works

The dylib is injected into every UIKit process. Inside each app it reads the applied
preferences, finds its own bundle id, and if that app is enabled it overrides:

- `-[UIApplication supportedInterfaceOrientationsForWindow:]` and
  `-[UIViewController supportedInterfaceOrientations]` → your exact mask,
- `-[UIViewController shouldAutorotate]` → `YES` (so UIKit re-evaluates the mask),
- `-[UIViewController preferredInterfaceOrientationForPresentation]` → your primary
  orientation,
- and on iOS 16 calls `requestGeometryUpdateWithPreferences:` (iOS 15: nudges the device
  orientation + `attemptRotationToDeviceOrientation`) when the app activates, to defeat
  the "launches in portrait then won't turn" behaviour.

Apps that aren't enabled are untouched (`%orig` everywhere).

## Install

Grab a `.deb` from the [Actions/Releases artifacts](../../actions) or build your own —
see [BUILD.md](BUILD.md). Requires a package manager with **AppList** available
(it's a dependency).

```bash
# rootless                                # rootful
make package                              make package THEOS_PACKAGE_SCHEME=
```

Then: **Settings → AutoRotate** → master on → enable apps → pick orientations → **Apply**.
If an app won't pick up its orientation, use the **Respring** button.

## Notes / known limits

- The home screen itself (SpringBoard) is a special case; this tweak targets normal app
  UI and most system apps rather than reimplementing SpringBoard rotation.
- Some apps hard-code their own orientation deep in their view-controller stack; the
  hard-lock handles the vast majority, but a stubborn outlier may still resist.

Contributions welcome.
