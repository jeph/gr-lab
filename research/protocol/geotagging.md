# Geotagging: sending the phone's location to the camera

GR cameras have no GPS receiver. A phone writes its position to the camera over Bluetooth, and the camera records it in the pictures it takes while the position is still valid. This file covers what the camera firmware does with a written position, how Ricoh's two apps decide when to write one, what GR Photo does with all of that, and what is still to be tested on a camera.

Nothing here has been run on hardware yet: the camera facts come from the GR IV 1.20 and GR III 2.20 firmware, and the app facts from GR WORLD 2.0.0 and Image Sync 2.1.32, all read on 2026-11-12. Each fact is tagged **[found]** (in code, with its address or file), **[inferred]** or **[unknown]**; what GR Photo does that no camera or Ricoh app prescribes is tagged **[design]**.

The wire format of the record is in [ble.md §GPS push](ble.md#gps-push); the setting that enables it is the GEO Tag characteristic `A36AFDCF` (Camera State service), which is the camera's Store Location Info menu item.

## Contents

1. [What the camera does with a record](#1-what-the-camera-does-with-a-record)
2. [GR WORLD 2.0.0](#2-gr-world-200)
3. [Image Sync 2.1.32](#3-image-sync-2132)
4. [Other apps](#4-other-apps)
5. [What the camera writes into a file](#5-what-the-camera-writes-into-a-file)
6. [Consequences for a client](#6-consequences-for-a-client)
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
- The DNGs are little-endian classic TIFF, and their GPS pointer is one LONG. A JPEG's EXIF segment is about 39 KB of the 64 KB a segment can hold, so a GPS directory with a position fits in it.

Observed 2026-11-11 (GR IV HDF, firmware 1.20): for a photo saved with a location, `GET /v1/photos/<dir>/<file>/info` reports it in `gpsInfo` as the string of §1.1, the position's own time included, and for a photo without one `gpsInfo` is empty ([HTTP API §2.2](http-api.md#22-per-photo-info)). The files themselves were not read.

**[unknown]** Which GPS tags the camera writes when it has a location (the time and date stamp in particular, which would show the age of the position at capture), and what it writes after the 600 s.

## 6. Consequences for a client

- Write GEO Tag `01` before the first record; a record written while it is off is refused.
- Any interval comfortably under 600 s keeps a location valid. Writing more often only makes the position fresher.
- The camera cannot tell an old position from a new one, and neither of Ricoh's apps checks. A client that rewrites its last position keeps a stale one valid for as long as it does so; the age of a position has to be judged on the phone before it is written.
- Write after a clock sync, never just before one (GR IV).
- A refused write means the setting is off or the camera could not take it; it is not a lost link.
- After the link drops, or the phone stops writing, the camera tags with the last position for up to 600 s more. Only turning Store Location Info off clears it sooner.

GR Photo's geotagging (2026-11-12) is built on these. On a camera only its linking and first write have been watched (§6.5), and none of it has run on an iPhone; the simulated camera treats a location and its clock as §1 says the firmware does, and the tests run against that.

### 6.1 Live geotagging: what is written, and when

All **[design]**, to be tuned on hardware (test 11):

- **Only to a camera that is on.** The phone is located while the camera is linked, on (Operation Mode other than `02`) and has GEO Tag `01`, and for 5 minutes after such a camera turned off or dropped the link (§6.5). Nothing is written to a camera in its off state, which could not record it and drops the link within seconds ([firmware bonding §6.1](firmware-bonding.md#61-the-radio-runs-a-different-firmware-image-in-each-power-state)).
- **The setting.** Turning live geotagging on for a camera writes GEO Tag `01`; turning it off writes `00`, which clears the location the camera holds (§1.3). A change made while the camera is off or away is written at the next link that finds it on. GEO Tag is read at every such link and its notifications are followed: a user who turns Store Location Info off in the camera's menu is not overruled, and the phone is no longer located.
- **Which positions.** A position is written only when it is at most 60 s old and accurate to 100 m, the first one after power-on included, because the camera cannot tell an old position from a new one.
- **How often.** The first usable position is written at once. After that one is written when the phone moved more than 5 m from the last one written, or more than the new position's own accuracy when that is larger (a fixed 5 m would fire on GPS noise), with at least 5 s between writes. A phone that does not move has a new position taken and written every 180 s, well inside the 600 s; a stored position is never sent again.
- **The record.** Fix time in UTC, as both Ricoh apps send it; altitude `0` when the phone gave none, held to the camera's ±9999 m.
- **A refused write.** GEO Tag is read again; when it is off, geotagging shows as off on the camera. The link is not treated as lost.
- **The first shots.** Between power-on and the first write the camera uses the location it still holds, if that is under 600 s old (§1.3), and otherwise none.

### 6.2 The camera's clock

GR WORLD writes Date Time on every connect when its per-camera time-sync flag is set ([ble.md, Date/time sync](ble.md#datetime-sync)). GR Photo does not copy that, because on a GR IV a clock change clears the location one second later (§1.3) **[design]**:

- The clock is read (Date Time `FA46BBDD`) at each link that finds the camera on, and every 60 minutes while it stays on and linked, and compared with the phone's local time. Date Time has no zone and whole seconds.
- It is written only when the two differ by 2 s or more. After a write GR Photo waits 2 s and then writes a newly taken position.
- The clock is checked before the first position of a link is written.
- This runs while the camera's own switch (Sync camera clock, on by default) is on, and always while background geotagging is on for the camera, which matches photos by the time the camera wrote into them (§6.4). Live geotagging does not turn it on: a camera with only live geotagging has its clock left alone when the user turned the switch off.

What the camera reads back just after a write, and whether a write that changes nothing still clears the location, are **[unknown]** (test 12).

### 6.3 Starting when the camera comes on

Live geotagging starts from an app that is running: opened by the user, and carrying on after it is left. It is off for a camera until the user turns it on, and the phone is asked for its location only then **[design]**.

A camera that is off cannot be held on a link ([GR WORLD power-on §8](power-on-grworld.md#8-gr-photo-link-drops-at-power-changes)), so its power-on is noticed from its advertisement: on, it advertises the Camera Information service `9A5ED1C5` in the primary packet where it advertised Client Registration `0F291746` while off, and power tag `01` in the scan response ([camera models §4.1](../camera-models.md#41-before-connecting-ble-advertising-recommended); observed on a GR IV HDF, [hardware results](../hardware-validation.md#4-results-log)). A session that let go of its camera scans for that service itself while the app's process runs, and links the camera when it is seen **[design]**.

A link that is still up when the camera is switched on is the other way in: Camera Power `01` notified on it, or an Operation Mode other than `02` read on a link that returns ([GR WORLD power-on §8](power-on-grworld.md#8-gr-photo-link-drops-at-power-changes)).

Once the camera is linked and on, locating the phone with the app off screen needs, on Android, a foreground service of the location type, which Android 12 and later let an app start from the background only in listed cases (location allowed all the time is one; Android, "Restrictions on starting a foreground service from the background"), and on iOS location updates under the `location` background mode. With location allowed only while the app is in use, a camera switched on while GR Photo is not on screen therefore starts geotagging when the app is next opened.

**Stop on the phone's notice** (Android's notification, the Live Activity on iOS) turns live geotagging off for the camera, as its switch does **[design]**. With GR Photo's window closed the app's engine lives only as long as the run is held, so after Stop the run stays held, with its notification gone, until the app has saved the setting and, where the camera is on and linked, written Store Location Info off. Observed on an Android 16 emulator with the simulated camera (2026-11-12): Stop was pressed with the window closed; the run was released 0.1 s later, by then the saved setting was off and Store Location Info had been written off, and the switch was off when GR Photo was opened again.

**The notice on iOS** is a Live Activity (ActivityKit), on iOS 17 and later, the first with buttons in one; earlier versions show none **[design]**. It shows what Android's notification does: the camera's name, the status and Stop. A widget extension (`LiveActivity`) draws it; the camera layer only tells the app what to show (`GrCameraRun.noticePresenter`). What iOS allows shapes it:

- iOS starts a Live Activity only for an app that is on screen (Apple, "Displaying live data with Live Activities"). Live geotagging is turned on in GR Photo, so the run is first held there. A run held from the background (the camera came on after the hour of waiting had released the run) has no activity until GR Photo is next opened, when the notice is shown again. Starting one from the background takes a push from a server, which GR Photo does not have.
- The user can swipe it away, and iOS ends it after eight hours, with the run going on. It is started anew the next time its text changes or GR Photo is opened.
- Stop is a `LiveActivityIntent`, which iOS runs in the app's process and starts the app for. The activity names its run by the camera's serial number, so a Stop on an activity that outlived its app (iOS ended GR Photo while a run was held) is kept by native code until the app takes it, and turns live geotagging off for that camera before a run is held again.
- GR Photo ended in the app switcher ends its activity before the process goes; an app iOS ended without notice leaves it up until GR Photo next starts.

Observed on an iOS 26.5 simulator (iPhone 17) with the simulated camera (2026-11-12): the activity appeared on the Lock Screen and in the Dynamic Island when live geotagging was turned on, and followed the status ("Camera not connected" with the simulated camera off). Stop took it away, the saved setting was off and Store Location Info was written off. After a swipe it came back when GR Photo was opened. Ending GR Photo in the app switcher took it away. With the process killed instead, it stayed; Stop on it started GR Photo in the background, which turned the saved setting off and ended it. Not run on an iPhone, and a simulator does not suspend apps as a phone does.

**Starting with the app closed: tried and removed.** The first build (2026-11-12) also watched for the on-state advertisement with no app running, to start GR Photo with no screen: on Android a Bluetooth scan filed with a `PendingIntent` for a broadcast receiver (`BluetoothLeScanner.startScan`), one filter per camera on the service and the camera's address, behind a companion device association, filed again after a restart of the phone; on iOS a scan for the service by a central manager with a restore identifier under the `bluetooth-central` background mode. Observed on an Android phone with a GR IV HDF (2026-11-12, reported by the user; no trace kept, firmware and the phone's permissions at the time not recorded, [hardware results](../hardware-validation.md#4-results-log)): switching the camera on with GR Photo closed did not start the app and no location was sent. Why was not found: whether the scan reported the camera, or the start from the receiver failed, is **[unknown]**. The iOS half was never run on an iPhone. The watch, the association and the engine start without a screen were removed the same day; `bluetooth-central` stays, for the link an app that was left keeps.


### 6.4 Background geotagging: the history, and writing into files

- **The history.** Background geotagging is a setting of each paired camera. While it is on for any of them, the phone records where it is the cheapest way each platform has **[design]**: on Android a standing request to the location service for a position every five minutes at balanced power, delivered to a broadcast receiver, which Android answers only a few times an hour for an app not in front (Android, "Background Location Limits"); on iOS significant location changes (about 500 m or more, at most one every five minutes: Apple, `startMonitoringSignificantLocationChanges`) and visits, for which iOS starts the app again after ending it. Native code stores the positions with no Flutter engine running, and the app takes them over when it runs. Observed on an Android 16 emulator (2026-11-12): with GR Photo in the background Android stretched the request to one position every ten minutes, and with the app's process ended it started the process for the receiver at the next one, which stored the position. On the iOS 26.5 simulator the switch turned on with location allowed all the time; no significant change or visit was delivered there, and none has been on an iPhone. Positions live geotagging took go into the history too, one every 15 s of the about one a second the phone takes while the camera is on. Each is kept 90 days.
- **Matching.** At download from a camera that has background geotagging on, a JPEG or DNG whose GPS directory has no latitude gets the recorded position nearest in time to its capture time, before or after. A photo taken more than 90 days ago gets none, and a photo with no position before it takes the next one only when that came within 10 minutes. The capture time is EXIF `DateTimeOriginal`, the camera's local time with no zone (§5), read as local time in the phone's current zone: a camera clock that is wrong, or set to another zone, shifts every match by as much.
- **Writing.** The file's bytes stay where they are: a new GPS directory is appended to the TIFF data (in a JPEG, the EXIF segment) and only the four bytes of the pointer to it change, which a camera file already has in IFD0 (tag `0x8825`, §5). It holds `GPSVersionID` 2.3.0.0, latitude, longitude, altitude when known, the UTC time and date the phone took the position (so the file shows how old its position is) and `GPSMapDatum` WGS-84. A file that already has a latitude, a movie, and a file that cannot be parsed are left as they are. A file given a location no longer matches the copy on the memory card.
- **Checked on camera files** (observed 2026-11-12, on copies of two DNGs and two JPEGs from a GR IV, firmware 1.20, on a Mac): in each DNG four bytes changed inside the original length and 227 were appended; in each JPEG the EXIF segment grew by 226 bytes and everything after it was the same bytes further on. `exiftool -validate` reported the same as for the untouched files and read every tag written, the embedded preview was byte-identical, and macOS's ImageIO read the location and still decoded the raw image. Photos apps on a phone and Lightroom are still to try (test 15).

### 6.5 A phone that stops the app with the screen off

Observed 2026-11-12 (GR IV HDF, fw 1.20, an Android phone whose maker's build of Android freezes apps that are off screen; [GR WORLD power-on §8.1](power-on-grworld.md#81-watching-for-a-camera-that-is-off)): with the screen off the phone froze GR Photo seconds after the camera turned off, so the camera was not linked when it was switched on again until the screen came on. The freezer left GR Photo alone while a Bluetooth link was up and while the phone was being located, and, as the user reported, once GR Photo was left out of battery optimisation. In the same logs the first position was written 1.5–3.4 s after the link came up, nearly all of it the wait for a new position.

GR WORLD probably does not meet this **[inferred]**, never tested: it goes on locating the phone and holds a wake lock for as long as its service runs (§2.1), and its manifest asks for `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` ([ble.md, Android plugin](ble.md#android-plugin--os-settings-flutter_blue_plus-jadx-p326m6c4069hjava)).

What GR Photo does about it, all **[design]**:

- **Standby.** After a camera it was located for turned off or dropped the link, the phone stays located for 5 minutes, with no wake lock. A camera switched on again in that time has the newest of those positions considered at once, by the rules of §6.1 (at most 60 s old, accurate to 100 m), instead of waiting for a new one; a position already written to the camera is not kept for this. The standby ends early when live geotagging is turned off, by its switch or by Stop on the notice (which turns the camera's setting off as the switch does), or the session ends. On the phone above it also keeps the freezer away for those 5 minutes.
- **The exemption (Android).** Turning live geotagging on asks Android whether GR Photo may be left out of battery optimisation (`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`), once the location is allowed. Live geotagging is on whatever the answer. While the app is not exempt, the camera's card says that the phone may pause GR Photo with the screen off, with a button that asks again. The state is read at start and whenever the app comes back on screen. Google Play allows this request only for listed kinds of app; GR Photo's Android build is released outside it.
- **iOS** has no such setting and always answers that nothing restricts the app. It suspends an app that neither locates the phone nor holds a link, and wakes it for a filtered scan result under the `bluetooth-central` background mode; the standby keeps it from being suspended for its 5 minutes. None of this has run on an iPhone; only the Live Activity has run, on a simulator (§6.3).

## 7. Hardware tests

Run so far: part of test 8 and test 10 on Android (2026-11-12, §6.5). The rest is open.

1. Write one record, then shoot at +1, +9 and +11 minutes: read the GPS tags of each file and watch the positioning icon. Confirms the 600 s and shows the tags the camera writes.
2. Write a record with GEO Tag off, and one with an out-of-range latitude: the ATT error for each.
3. Write a record whose fix time is an hour old: is it recorded as it is?
4. Sync the clock just after a record (GR IV): is the location gone a second later?
5. Auto power off at 1 minute, with no link, an idle link, a write every 5 s and a write every 180 s: when the camera turns off in each case, and what a held link costs the camera's battery.
6. Turn the camera off for 5 and for 15 minutes after a record, then shoot: is the first picture tagged?
7. A record written while the camera is in its off state (Bluetooth only): accepted, refused, or does the link drop first?
8. How long after power-on a phone in a pocket has linked and written its first record, on Android and iOS.
9. GR III and IIIx: all of the above, and whether a clock change clears the location.
10. Switch the camera on with GR Photo in the background (opened before, not swiped away), phone locked, on Android and on iOS: whether the session's scan sees the camera and geotagging starts, and how long that takes (§6.3). With GR Photo closed nothing starts, by design since 2026-11-12. Android, on a phone that freezes apps: not until the screen is on unless GR Photo is left out of battery optimisation (§6.5). Still to run: the same with the 5-minute standby and the faster watch, on a Pixel, and on iOS.
11. GR Photo's thresholds (§6.1) on a walk and indoors: how many writes an hour, how far the recorded position is from where each picture was taken, and how often pictures go untagged.
12. Date Time read and write on a GR IV and a GR III: the offset GR Photo measures just after its own write, and whether a write that changes nothing still clears the location.
13. Switch the camera on at its power button while a link to it is still up (inside the 8 s after a connect to the off camera): is Camera Power `01` notified, or does the link drop?
14. A day out with background geotagging on: how many positions the history gets on Android and on iOS, and how far the matched position of each downloaded photo is from where it was taken.
15. A DNG and a JPEG given a location by GR Photo, opened in Apple Photos, Google Photos and Lightroom: is the location shown, and does the raw still develop?
16. A DNG and a JPEG shot while a location was valid: which GPS tags the camera writes itself (§5), so GR Photo's can match.
17. The Live Activity on an iPhone (§6.3), with location allowed while in use and always: that it stays up and follows the status with the phone locked for an hour; Stop with the phone locked, with GR Photo suspended; whether iOS ends GR Photo while a run is held, and what Stop on the activity left behind then does.

## 8. Evidence

- Firmware: `firmware/gr4-root/…/usr/bin/bled`, `firmware/gr4_v120/rtos.bin`, `firmware/gr3-root/…/usr/bin/bled`, `firmware/gr3_v220/rtos.bin`. GR IV `bled` addresses are Ghidra's (objdump + 0x10000); RTOS images load at 0x53000000 and most functions start 4-8 bytes before the `FUN_` address given. Decompiled output and the full report: `work/scratch/geotagging/firmware-gps.md`, `work/scratch/geotagging/firmware-decomp/`.
- GR WORLD: `work/dis/dis.txt`, `work/cs/blutter_out/pp.txt`, `work/jadx`; full report with every call site in `work/scratch/geotagging/grworld-location.md`.
- Image Sync: `work/imagesync-jadx/sources/`; full report in `work/scratch/geotagging/imagesync-location.md`.
- Manual: `work/manuals/gr4.txt` lines 762, 808, 821-822, 5208-5218.
