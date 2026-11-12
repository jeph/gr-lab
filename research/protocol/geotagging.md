# Geotagging: sending the phone's location to the camera

GR cameras have no GPS receiver. A phone writes its position to the camera over Bluetooth, and the camera records it in the pictures it takes while the position is still valid. This file covers what the camera firmware does with a written position, how Ricoh's two apps decide when to write one, and what is still to be tested on a camera.

Nothing here has been run on hardware yet: the camera facts come from the GR IV 1.20 and GR III 2.20 firmware, and the app facts from GR WORLD 2.0.0 and Image Sync 2.1.32, all read on 2026-11-12. Each fact is tagged **[found]** (in code, with its address or file), **[inferred]** or **[unknown]**.

The wire format of the record is in [ble.md §GPS push](ble.md#gps-push); the setting that enables it is the GEO Tag characteristic `A36AFDCF` (Camera State service), which is the camera's Store Location Info menu item.

## Contents

1. [What the camera does with a record](#1-what-the-camera-does-with-a-record)
2. [GR WORLD 2.0.0](#2-gr-world-200)
3. [Image Sync 2.1.32](#3-image-sync-2132)
4. [Other apps](#4-other-apps)
5. [What the camera writes into a file](#5-what-the-camera-writes-into-a-file)
6. [Consequences for a client](#6-consequences-for-a-client)
   - [What GR Photo does](#61-what-gr-photo-does)
7. [Hardware tests](#7-hardware-tests)
8. [Evidence](#8-evidence)

## 1. What the camera does with a record

Summary: a record is accepted only while Store Location Info is on, is range-checked, and is then valid for 600 s by the camera's own clock. Each accepted record restarts the 600 s. When they run out the location is cleared and pictures get none.

### 1.1 Bluetooth daemon (`bled`)

GR IV `GPSControl::GPSInformation::Write` (0x69fe8), GR III the same (0x679a4):

- **[found]** A length other than 32 only logs a message; the handler goes on and reads 31 bytes regardless. `bled` does no range check.
- **[found]** It formats the record as the string `<lat %.6f>,<lon %.6f>,<alt %.1f>,<YYYY-MM-DDThh:mm:ss>,WGS84` and sets camera property `0x10` to it. The datum byte (offset 31) is never read: `,WGS84` is a constant.
- **[found]** The write response reports whether the camera accepted the property (`AIC_GsRespondWriteRequest(conn, handle, ok)`). Nothing is notified and no other property changes.
- **[unknown]** Which ATT error the phone sees for a rejected record.
- **[found]** `GEOTag::Write` (0x5a9fc) accepts only `00` or `01` and sets property `0x11`. The RTOS takes that only while property `0x2d` and four bytes of property `0x2e` are zero (dispatcher case `0x11`); what those two properties are is **[unknown]**, so the conditions under which the camera refuses to change the setting are too.

The Wi-Fi route for the same two properties is `PUT /v1/params/device` with `geoTagging=on|off` and `gpsInfo="<the same string>"` (Image Sync, §3); the string `bled` builds is that format.

### 1.2 Main firmware (RTOS, `PropertyCommandProcessor`)

Addresses are for GR IV 1.20; the GR III 2.20 equivalents are in §1.5.

- **[found]** The set-property dispatcher (FUN_535d709c, case `0x10`) runs the GPS setter only when property `0x11` (GEO Tag) is true, the property is settable and a global lock byte is 0. Otherwise it fails with error 4. So **a record written while Store Location Info is off is rejected**, not stored for later.
- **[found]** The setter (FUN_535d5898) splits the string on commas into five fields and rejects it (error 2) unless: the datum is `WGS84`; latitude is within ±90, longitude within ±180 and altitude within ±9999; and the time is exactly `YYYY-MM-DDThh:mm:ss` with a real calendar date and a year from the camera's base year to base + 49.
- **[found]** On success it stores the string in property `0x10`, takes the camera clock as the time of receipt and hands the position to `HTCommonPropertyUpdater` (FUN_535fb3e8), which posts a block (valid flag, latitude, longitude, altitude, the record's date and time) to the camera service.
- **[unknown]** The readers of that block (the EXIF writer and the shooting screen's positioning icon) were not traced.

### 1.3 Validity, expiry and what clears a location

- **[found]** A location is valid for **600 s from receipt**: on every accepted record FUN_535fb2d4 subtracts the time of receipt from the camera clock and arms a one-shot timer for the rest (event `0x92c20401`). When it fires, property `0x10` becomes empty, the valid flag 0, and the cleared block is posted.
- **[found]** The record's own timestamp is checked for syntax and range and copied into the block. It is **not compared with the camera clock** and does not set it. A record with an old fix time is therefore valid for a full 600 s like any other.
- **[inferred]** The camera treats the timestamp as UTC: playback has a `GetGpsUtcDateIconAscii` and the setter converts no time zone. Both of Ricoh's apps send UTC (§2.5, §3).
- **[found]** Three things clear a location: the 600 s timer; Store Location Info turned off (FUN_535eed44 posts the same event when property `0x11` becomes false; it runs from the settings sync, so the camera's menu takes this path, and a BLE write of `00` is **[inferred]** to as well); and, on the GR IV, a change of the camera clock, which clears it 1 s later (event `0x2660041d`). A position must therefore be written after a clock sync, not before.
- **[found]** A Bluetooth disconnect clears nothing: `BleServer::OnDisconnect` (0x47a74) writes no property, and no other caller of the clear routine was found. **[inferred]** After the link drops the camera goes on tagging with its last position until the 600 s run out.
- **[found]** The state survives power-off: at shutdown it is written to storage (`DomainDataStorage` item 8) and read back at start-up, where the 600 s check runs again against the stored time of receipt. A camera turned back on within 10 minutes of the last record still has the location.
- **[unknown]** Whether sleep goes through the same path, and whether the timer runs during sleep.

### 1.4 Cost of a write to the camera

- **[found]** An accepted record costs a property set, a mutex, one timer re-arm and one message. Nothing in the dispatcher, the setter or the updater calls power or shutdown control.
- **[found]** The auto power off countdown is in `AppShutDownModel`; the only resets found are its own key-event handler. **[inferred]** A GPS write does not postpone auto power off and does not wake the camera.
- **[found]** Auto power off is suspended while camera-info byte `+0x518` is non-zero or byte `+0x24a` is 2 or 3. **[unknown]** What those bytes mean. If one of them is "a phone is linked", a held Bluetooth link keeps the camera on whatever the write cadence.

### 1.5 GR III and IIIx

- **[found]** GR III 2.20 has the same setter (FUN_533c0138) behind the same GEO Tag gate, the same 600 s timer, the same storage at shutdown and the same clear when the setting goes off.
- **[found]** No reference to the clock-change event `0x2660041d` is in the GR III image, so no clear on a clock change was found there. **[unknown]** Whether it uses another event. Only GR III 2.20 was read, not GR IIIx 1.70.

### 1.6 Manual

GR IV manual, p.128 and the screen legends: Store Location Info ([Smartphone Link], E6 menu) defaults to Off and "records the location information of the communication device in taken images". The shooting screen's "GPS positioning status" item appears when the setting is On and a device is linked; playback shows "GPS information". The manual gives no timeout, send interval or icon states.

## 2. GR WORLD 2.0.0

Addresses are in `work/dis/dis.txt`. The service is class `UPb`: a position stream that only stores the newest position, and a separate timer that writes whatever is stored.

### 2.1 Acquiring location

- **[found]** `geolocator`'s `getPositionStream` (0xd46f20) with accuracy high, distance filter 0, interval equal to the write interval, `forceLocationManager: true`, a foreground notification and a wake lock. Natively (`work/jadx`, `F2/h.java`): `LocationManager.requestLocationUpdates` on the `fused` provider when the phone lists it, else `gps`, else `network`, with no batching. The Android service is of type `location`; the app does not declare background location.
- **[found]** `getLastKnownPosition` is read once at every start and written at once.
- **[found]** Starting is **not gated on the camera's GEO Tag setting or on a camera being connected**: the home screen starts the service after its scan whenever it does not connect instead (0xdd140c), and pairing, the GEO Tag switch turning on, resume and a frequency change start it too. Four more start callers were not read.
- **[found]** A normal connect does not start it: the call at 0xd2fc9c is in the connect flow's exception handler.
- **[found]** Nothing stops it when the camera disconnects or turns off. It stops when the app has been in the background for 60 s with the background limit off, when the limit runs out, on an explicit disconnect, during a firmware update and Wi-Fi connect, and when the last camera is a GR II.

### 2.2 Writing

The write timer (0xd47664 → 0xd47794) runs every **5 s (default, "High"), 30 s or 180 s** (`locationFreqNum` 0, 1, 2). Each tick:

1. Returns while a connect or a location reconnect is in progress.
2. Connected: writes the stored position if the camera's GEO Tag is true (the value it last read or was notified of); otherwise only logs.
3. Not connected, app in the background: scans for the camera and connects when it advertises on (0xd2b5b4).
4. Not connected, app in front: only logs. A separate 5 s timer (0xd2b384) does the reconnecting there; it is a reconnect watchdog, not a location write.

- **[found]** There is no comparison with the previous position and no age check: a phone that gets no new fix rewrites the same position with its original fix time on every tick.
- **[found]** A failed write is logged and swallowed; it does not reconnect.
- **[inferred]** With the camera off and the app in the background, every tick starts a scan, so at the default 5 s the phone scans almost continuously.

### 2.3 Background limit

- **[found]** `bgLocationLimit`: off (default), 1 hour, 3 hours, no limit. With it off the service stops 60 s after the app leaves the foreground. With a time limit a timer stops the service and posts a notification that sending has ended.

### 2.4 The switch

- **[found]** One switch. On writes GEO Tag `01` and starts the phone service; off writes `00` and stops nothing, so the stream keeps running and ticks do nothing. There is no phone-side preference: the camera's setting is the only state.
- **[found]** A GEO Tag notification (the user changing the camera's menu) only updates the value the next tick reads.

### 2.5 Timestamp

- **[found]** The record carries the **fix time in UTC**: the encoder (0xe608e8) reads `Position.timestamp`, which geolocator builds with `isUtc: true` (0xc28bd4), with no conversion in between. This settles the question ble.md had left open.

## 3. Image Sync 2.1.32

Paths are under `work/imagesync-jadx/sources/`.

- **[found]** Location: Google's fused provider at 1 s intervals, high accuracy, started whenever the app is in front with location and notification permission, whether or not a camera is connected or its GEO Tag is on (`m/b2.java:44-69`, `SvApplication.java:136-167`).
- **[found]** A 2 s timer (`m/a2.java:33-93`) writes the newest position when the camera is connected and on, its cached GEO Tag is true, and the position differs from the last one by more than 0 m (`m/z1.java:19-32`). A failed write is retried on the next tick.
- **[found]** When the position has not changed, the last one is written again after **600 s** (`b2/e.java:133-138`), with its original fix time: a keep-alive that matches the camera's validity time (§1.3).
- **[inferred]** Consecutive 1 s fixes almost never match exactly, so in practice it writes every 2 s.
- **[found]** Background sending is a preference: off (default), 1, 3 or 6 hours, or no limit. While the camera is away the app scans for it for up to 30 s at a time.
- **[found]** The timestamp is the fix time in UTC (`BleCameraSettingConverter.java:486-494`), over Wi-Fi too (`RestCameraSettingConverter.java:237-257`).
- **[found]** The switch writes the camera's setting; there is no app-side preference. Nothing is written while the camera reports itself off.

## 4. Other apps

GR Snap (iOS, a third-party app) is closed and was not analysed. Its published guides (read 2026-11-12) describe: sending the location over Bluetooth to a GR III, IIIx or IV, with an "Auto Send to Camera" setting of Always, Only While On (the default) or Never; turning the camera's Store Location Info on at the first send; an update-frequency setting whose intervals are not published; and a route recorded on the phone that fills in photos without a location after download, matched by capture time. None of this was verified.

## 5. What the camera writes into a file

Observed 2026-11-12 in files a GR IV and a GR IV HDF (firmware 1.20) had saved with no location set, reading tag names only:

- Every DNG has a GPS directory holding only `GPSVersionID`, pointed to from IFD0 (tag `0x8825`). Seven of eight JPEGs have the same; one has no GPS directory.
- No file carries a time zone (`OffsetTimeOriginal`) or sub-second capture time: only the camera's local time.

**[unknown]** Which GPS tags the camera writes when it has a location (the time and date stamp in particular, which would show the age of the position at capture), and what it writes after the 600 s.

## 6. Consequences for a client

- Write GEO Tag `01` before the first record; a record written while it is off is refused.
- Any interval comfortably under 600 s keeps a location valid. Writing more often only makes the position fresher.
- The camera cannot tell an old position from a new one, and neither of Ricoh's apps checks. A client that rewrites its last position keeps a stale one valid for as long as it does so; the age of a position has to be judged on the phone before it is written.
- Write after a clock sync, never just before one (GR IV).
- A refused write means the setting is off or the camera could not take it; it is not a lost link.
- After the link drops, or the phone stops writing, the camera tags with the last position for up to 600 s more. Only turning Store Location Info off clears it sooner.

### 6.1 What GR Photo does

All of this is GR Photo's choice **[design]** (2026-11-12), built from §1 and tested against the simulated camera only. No value has been tuned on hardware; the values are in `packages/gr_camera/lib/src/geotag/geotag_options.dart`.

**When the phone is located.** Live geotagging is a per-camera switch, offered once when a camera is first linked. With it on, the phone's precise location is requested only while that camera is linked, on, and has Store Location Info on. A camera linked in its off state takes no record and is not woken; the location starts when it reports Camera Power on. Ricoh's apps locate the phone whenever their service runs (§2.1, §3).

**The run.** A location run (on Android a foreground service of the location type with a notification and a wake lock, on iOS background location updates under "While Using" access) begins as soon as the camera is linked, on or off, and idles without a location request while the camera is off. It begins then because neither Android nor iOS lets it begin later with the app not in front. On iOS an idle run cannot be held without any location request, so it asks for the coarsest one (3 km accuracy, 3 km distance filter); those positions are never sent to the camera. With the camera out of reach and the app not in front, GR Photo links it again every 20 s for as long as the run lasts. The run ends after 1 hour without a camera that is on, when the user stops it from the Android notification, or when the app is closed.

**What is written.** One fix is requested every 5 s. A fix is written when it is at most 60 s old and accurate to 100 m or better, and either the phone moved more than 5 m (or more than the fix's own accuracy, when that is larger) since the last write, with at least 5 s between writes, or 180 s have passed since the last write. At the 180 s write a coarser fix that agrees with the better one already sent re-sends the better position with the new fix time. When fixes stop arriving nothing is written, and the camera lets its location run out after 600 s rather than keep a position that is no longer known to be right. Ricoh's apps rewrite their last position with no check of its age (§2.2, §3).

**Store Location Info.** Turning geotagging on writes GEO Tag `01`; turning it off writes `00`, which clears the camera's location at once (§1.3). GR Photo follows the characteristic's notifications: when the user turns the setting off in the camera's menu, GR Photo stops locating the phone and does not turn it back on until the user asks.

**Clock.** The fix time is written in UTC, as both of Ricoh's apps do (§2.5). The camera's clock is local time with no zone ([ble.md §Date/time sync](ble.md#datetime-sync)). GR Photo reads Date Time when the camera is linked and on, every hour while it stays so, and when the phone's time zone changes, and writes the phone's local time only when the two differ by 2 s or more. GR WORLD writes on every connect; GR Photo does not, because a GR IV clears its location 1 s after any clock change (§1.3). After a clock write GR Photo writes the next fix whether or not the phone moved. The write is made as a new second begins, since the camera takes whole seconds. This runs while live geotagging is on, and otherwise while the camera's Sync time option is on (the default).

**Not in front.** On Android the foreground service keeps the process and its Bluetooth link working. On iOS the app declares the `location` background mode only, not `bluetooth-central`: the location updates keep it running, and whether Core Bluetooth then delivers the held link's notifications (Camera Power on) and lets a camera that went out of reach be linked again is **[unknown]** until tried on an iPhone (§7 test 10).

**Platforms.** Android reads fixes from `LocationManager` (the fused provider where the phone has one, GPS otherwise), so no Google Play services library is needed. iOS reads them from `CLLocationManager` and shows its own indicator instead of a notification; it has no Stop button and no way to open the phone-wide location switch.

**Run on an emulator.** Observed on an Android 16 emulator (API 36, 2026-11-12) with the simulated camera and the phone's real location code: the permission prompt, the foreground service (type `location`) with its wake lock, a fused-provider request every 5 s, fixes written to the camera, and the notification's Stop ending the run until the app is opened again. A notification the service posts before the user allows notifications is dropped and does not appear when they are allowed, so GR Photo posts it again when the prompt is answered. The iOS code has been compiled but not run.

## 7. Hardware tests

None run yet.

1. Write one record, then shoot at +1, +9 and +11 minutes: read the GPS tags of each file and watch the positioning icon. Confirms the 600 s and shows the tags the camera writes.
2. Write a record with GEO Tag off, and one with an out-of-range latitude: the ATT error for each.
3. Write a record whose fix time is an hour old: is it recorded as it is?
4. Sync the clock just after a record (GR IV): is the location gone a second later?
5. Auto power off at 1 minute, with no link, an idle link, a write every 5 s and a write every 180 s: when the camera turns off in each case, and what a held link costs the camera's battery.
6. Turn the camera off for 5 and for 15 minutes after a record, then shoot: is the first picture tagged?
7. A record written while the camera is in its off state (Bluetooth only): accepted, refused, or does the link drop first?
8. How long after power-on a phone in a pocket has linked and written its first record, on Android and iOS.
9. GR III and IIIx: all of the above, and whether a clock change clears the location.
10. GR Photo's run (§6.1) with the phone in a pocket and the screen off, on Android and on iOS: whether the camera turning on starts the location, how long that takes, and what the idle run (wake lock on Android, coarse updates on iOS) costs the phone's battery over an hour.
11. GR Photo's thresholds (§6.1) on a walk and indoors: how many writes an hour, how far the recorded position is from where each picture was taken, and how often pictures go untagged.
12. Date Time read and write on a GR IV and a GR III: the offset GR Photo measures just after its own write, and whether a write that changes nothing still clears the location.

## 8. Evidence

- Firmware: `firmware/gr4-root/…/usr/bin/bled`, `firmware/gr4_v120/rtos.bin`, `firmware/gr3-root/…/usr/bin/bled`, `firmware/gr3_v220/rtos.bin`. GR IV `bled` addresses are Ghidra's (objdump + 0x10000); RTOS images load at 0x53000000 and most functions start 4-8 bytes before the `FUN_` address given. Decompiled output and the full report: `work/scratch/geotagging/firmware-gps.md`, `work/scratch/geotagging/firmware-decomp/`.
- GR WORLD: `work/dis/dis.txt`, `work/cs/blutter_out/pp.txt`, `work/jadx`; full report with every call site in `work/scratch/geotagging/grworld-location.md`.
- Image Sync: `work/imagesync-jadx/sources/`; full report in `work/scratch/geotagging/imagesync-location.md`.
- Manual: `work/manuals/gr4.txt` lines 762, 808, 821-822, 5208-5218.
