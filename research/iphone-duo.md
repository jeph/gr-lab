# iPhone Duo: what iOS tells an app, and what GR Photo does with it

iPhone Duo is Apple's foldable (iOS 27.1): a 5.4-inch outer display when closed and a 7.6-inch inner display when open. This file records what the system reports to GR Photo in each pose, how that was found, and how the app lays itself out. It is about the phone, not the camera; nothing here changes the camera protocol.

Status of each statement: **observed** (iOS 27.1 simulator, build 24A94425, Xcode 27.1, 2026-11-13, with GR Photo's `dev` build in demo mode), **found in code** (the iOS 27.1 SDK headers or Apple's documentation), **inferred**, or **unknown**. Nothing here has been seen on a real iPhone Duo yet.

## 1. What iOS provides

Found in the iOS 27.1 SDK (`UIKit.framework/Headers`) and Apple's "Preparing your app for iPhone Duo" and tech talks 111461 to 111463:

- **Vertical bar.** Closed, and open and held wide, iOS stands its bars upright in a strip down one side of the window. `UITraitCollection.verticalBarEdge` (`UIVerticalBarEdge.h`) names the side, leading or trailing, and is `unspecified` where the system uses no vertical bar. It names the edge iOS prefers "regardless of whether a vertical bar is currently visible". Only bars from system containers (`UINavigationController`, `UITabBarController` and the SwiftUI equivalents) move into the strip by themselves.
- **Reserved regions.** `UIView.reservedRegions(kind:options:)` (`UIViewReservedRegion.h`) returns the regions of a view that something else has a claim on: `.division` for the fold, which is active only while the phone is folded part of the way and is returned while inactive only with the `.includeInactive` option, and `.occlusion` for what the system draws over the view.
- **Hinge.** `UIHingeInteraction` (`UIHingeInteraction.h`) reports a `UIHinge` with a status (`closed`, `partiallyOpen`, `fullyOpen`) and an angle.
- **Full screen.** An app built with Xcode 27.1 gets the whole display; built with an older Xcode it does not extend under the status and the camera. GR Photo's releases are built with Xcode 27.1 (`.github/workflows/release.yml`).

Flutter 3.47.9 passes none of this on: `MediaQuery.displayFeatures` is empty on the Duo and there is no API for the bar edge (flutter/flutter #193038 and #193062, open when read on 2026-11-13). Flutter does report the strip as a safe-area inset.

## 2. What the simulator reports

Observed, in points, through `WindowPosePlugin` (§3) and `MediaQuery`. The simulator has no CLI for the hinge: Device Hub (which replaces Simulator.app in Xcode 27) has Closed, Partially Open, Open and Rotate buttons. `xcrun simctl io <device> screenshot --display=1` captures the outer display and `--display=3` the inner one; whichever is not in use is black. Without `--display` the capture was the inner display in one session and the outer one, black while the phone was open, in another (2026-11-13), so name the display. The pose does not survive a restart of the simulator: it boots closed. A touch sent to the simulator as an IOKit HID digitizer event, which lands on an iPhone 17 Pro Max and an iPad Pro simulator (iOS 26.5), does nothing on the Duo's open inner display (2026-11-13).

| Pose | Window | Safe-area insets | `verticalBarEdge` | Division region | Occlusion regions |
|---|---|---|---|---|---|
| Closed (outer display) | 466 × 678 | right 84, bottom 34 | trailing | none | the status, 382..466 × 0..174, and the camera inside it, 399.7..436.7 × 29.3..66.3 |
| Open, held wide, flat | 951 × 669 | right 84, bottom 34 | trailing | 455.5..495.5 × 0..669, inactive | the status, 867..951 × 0..124 |
| Open, held wide, partially open | 951 × 669 | right 84, bottom 34 | trailing | the same band, active | the same |
| Open, held upright, flat | 669 × 951 | top 82, bottom 34 | unspecified | 0..669 × 455.5..495.5, inactive | the status, 525..669 × 0..82 |
| Held upright, partially open | 669 × 951 | top 82, bottom 34 | unspecified | the same band, active | the same |

- The scale is 3 in every pose.
- The window has no inset at the top while the bar stands at the side: the time and the status are at the top of the strip, and the app's part of the strip starts under them.
- Held upright, the status takes only the last 144 pt of an 82 pt band across the top; the rest of the band is empty and inside the safe-area inset.
- While the phone unfolds, the app's window moves to the inner display and the regions follow within a few frames; the hinge status passes through `partiallyOpen`.
- Apple's published inner display size, 626 × 890 pt, is not what the simulator gives an app (669 × 951). Unknown: which of the two a real phone reports.
- Unknown: the insets and regions with Display Zoom, in Split View (half the inner display, where the bar can be on either side) and in right-to-left languages. The plugin resolves leading and trailing against the view's layout direction, so a bar on the left is handled, but it has not been seen.

## 3. How GR Photo reads it

`app/ios/Runner/WindowPosePlugin.swift` (channel `io.jeph.grphoto/window`) watches the Flutter view: a layout watcher for size and safe-area changes, the traits behind `verticalBarEdge`, and a hinge interaction. It sends the bar side (resolved to left or right), the division region with its active flag, and the occlusion regions, on `get` and on every change. Before iOS 27.1 it sends nothing. `PlatformWindowPose` (`app/lib/src/platform/window_pose.dart`) holds the result as a `WindowPose`; Android has no such channel and keeps `WindowPose.none`.

`WindowPoseScope` (`app/lib/src/widgets/window_layout.dart`) wraps the app and turns the pose into three things the pages ask for:

- `VerticalBar.of`: the strip, when iOS names a bar edge **and** the window has a safe-area inset of at least 56 pt on that side. The app's part starts under the status occlusion.
- `StatusBand.of`: the top band of the upright pose, with the part the status takes.
- The fold as a `DisplayFeature` in `MediaQuery.displayFeatures`, as Flutter reports an Android foldable's: a zero-width line down the middle of the band with `postureFlat` while the region is inactive, the band with `postureHalfOpened` while it is active. So `WindowFold` and Flutter's own dialogs treat both platforms' folds alike. It is left out as soon as Flutter reports a fold of the window itself.

These are [design]: the bar is drawn by Flutter rather than by a native `UINavigationController`, because the app's dock and buttons are themed Flutter widgets shared with Android, and a native bar would be an iOS-only path to keep in step with every route.

## 4. Layouts

All [design], following the mock-ups in the local research workspace (`design/mockups/iphone-duo.html`).

- **Vertical bar** (closed; open and held wide). The dock stands upright at the foot of the strip, icons only. Each page puts its bar buttons under the status: Back and Settings on the camera's pages, plus New look on Looks; Back, Info and Download in the viewer, which opens with the details shown on the closed display; Back and the menu in the look editor; Close and the exposure mode in live view. The camera pill stays at the top of the page. Toasts are centred over the page, not the strip.
- **Two pages** (a fold standing upright in the window with a page of at least 300 pt either side, which is the open Duo held wide and an Android foldable held the same way). Nothing but a picture lies across a fold that is partially open.
  - Library: the grid keeps the first page with three columns and the filters under the title, and the second page asks for a photo until one is tapped there; the tapped photo then shows on the second page with its details and map. The grid never changes its layout when a photo is tapped: an earlier layout put six columns across both pages until the first tap and then reflowed to three, which moved every photo and scrolled the grid after it (reported on 2026-11-13). A tap on the photo opens the full-screen viewer, and Back leaves the Library. Turning the phone upright or closing it puts the photo away and keeps the place in the grid.
  - Viewer: on the Duo, Info puts the details and the map on the second page beside the photo. An Android foldable keeps them under the photo, as before.
  - Looks: the camera's slots are rows on the first page and the saved looks are on the second; a saved look can be dragged onto a slot, which loads it after the same confirmation as the menu.
  - Look editor: the pictures on the first page, with the sample photos in a grid, and the controls on the second.
  - A phone on its side and an iPad have no fold, so they keep their layouts.
- **Open and upright.** Bars lie across the window again: the ordinary top bar, moved up into the status band beside the status, and the floating dock. Live view's top bar (Close, the camera pill and the exposure mode) is in the band too.
- **Live view, open and held wide.** The camera pill and the mode switch are in a row above the picture and the readouts and quick settings in a row below it, each row split at the fold, so only the picture lies across it. Nothing is drawn over the picture. The shutter is at mid-height in the strip, where the right thumb rests, with the last shot at the strip's foot.
- **The mode switch** (Remote / Live view) is in the same place in both modes, so it does not move when tapped: in the top bar where the bar is at least 600 pt wide (an open Duo held wide, split at the fold as above; an Android foldable open; a tablet), else in a row under it. Remote used to keep it under the top bar while live view put it in the bar, so it jumped up and down when switching on foldables and tablets (reported on 2026-11-13). Two layouts still move it on purpose: a phone on its side, whose live view rails have no room for it, and tabletop.
- **Tabletop** (upright and partially open). Live view has the picture in the upright half and every control in the half lying flat; an Android foldable half-open across the window gets the same. The look editor already split this way for Android foldables.
- The Remote page keeps one column in every pose; with the phone partially open like a book its shutter lies across the fold.
- Not changed: Cameras, pairing, Settings, the camera sheet and the dialogs keep their phone layouts inside the safe area.

## 5. Still to settle on hardware

- Everything in §2 on a real iPhone Duo, including the window sizes.
- Split View, Display Zoom and a right-to-left system language.
- Whether the division region or the hinge status is the better sign of "partially open" (the app uses the region's active flag; in the simulator they change together).
