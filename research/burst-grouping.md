# Grouping continuous shots (idea, not scheduled)

Goal: show a burst as one item in the library grid, the way Sony's apps stack continuous shots, so one press of the shutter doesn't fill the grid. This is a feature idea. It is not in the v1 design and no code exists for it.

The camera has no burst or group ID that we know of. Any grouping the app does is a heuristic. The open questions below decide how good that heuristic can be.

## What we know

**What the camera's HTTP API returns** ([http-api](protocol/http-api.md) §2):

| Request | Returns | Burst information |
|---|---|---|
| Photo list `GET /v1/photos` | Folder and file names only | None, apart from consecutive file numbers |
| Per-photo info `GET /v1/photos/<dir>/<file>/info` | `datetime`, `recordedTime`, size, orientation, aspect ratio, `av`/`tv`/`sv`/`xv`, location | No drive mode, sequence number or group ID |
| Thumbnail / preview `?size=thumb`, `?size=view` | Image bytes | **Unknown**: not inspected (see below) |

**What GR WORLD does with that** (static analysis of 2.0.0, see [http-api](protocol/http-api.md) §2.2): after listing, it runs a background loop that requests the info for each listed photo, shows "Getting info" (情報取得中です), stops the loop when a download starts, and stores the results in a local `photo_info` table. So one info request per photo is GR WORLD's normal behaviour. Whether it skips photos already in the table is **[inferred]**, not traced.

**What the photo file contains** (one GR IV HDF fw 1.11 JPEG, read with ExifTool 13.55):
- A Pentax-format maker note with `DriveMode` (here `0 0 0 0`, "Single-frame"), `ShutterCount` and `AutoBracketing`.
- The whole EXIF block (APP1) is about 39 KB at the start of a full-size JPEG, so the drive mode sits in the first ~40 KB.
- No `SubSecTimeOriginal`: the capture time is in whole seconds.
- ExifTool's Pentax table records `DriveMode` byte 0 = `1` (Continuous) for GR III/IIIx. Pentax bodies with three continuous speeds use `1`/`4`/`5` for high/medium/low.

**Other sources:**
- The GR IV firmware's `webapid` contains the drive values `continuousH`, `continuousM` and `continuousL` (`strings` on `usr/bin/webapid`). Whether the GR IV offers more than one continuous speed is **[unknown]**: these may be shared enum names, and the GR IV manual (p.76-77) describes a single "Continuous Shooting" mode with no speed setting.
- The BLE Drive mode characteristic `B29E6DE3-...` notifies on change ([ble](protocol/ble.md)). That only helps while the app is connected during shooting.
- Interval shooting and interval composite put each run in a new folder (GR IV manual, "Interval Shooting" memo). Those groups can be taken from the folder.

## What we don't know

1. **Which `DriveMode` values the GR IV writes** for continuous shooting (and per speed, if it has more than one) and for bracketing. We have no GR IV burst file.
2. **Whether thumbnails or previews carry the EXIF/maker note.** If they do, the grid gets the drive mode with no extra requests.
3. **The time formats.** The one JPEG we have stores its capture time in whole seconds (no `SubSecTimeOriginal`). The format of the info's `datetime` and `recordedTime` is untested, so whether any time field has sub-second precision is unknown.
4. **Whether the camera supports HTTP range requests** (`Range: bytes=0-65535` answered with 206). Without them, reading the start of a file means starting a full download and closing it early. TCP buffering means more than 40 KB may cross the network, and the camera may do the same work as for a full download. The cost of that is unmeasured.
5. **Request cost.** The only timed request so far took 72 ms (the `latest/info` error in `trace-2026-11-08T00-33-30-489977Z.jsonl`). Info, thumbnail and partial-read timings on a full card are unmeasured.
6. **Whether any field marks press boundaries**, such as a frame counter that restarts with each press. `DriveMode` only says the camera was in continuous mode. Finer timestamps alone would not separate one long press from several quick presses.

## Possible approach

From cheapest to most expensive. Each is a heuristic until question 6 finds a per-press field.

1. **Info only:** consecutive file numbers in one folder with capture times within a gap threshold. If times turn out to be whole seconds (as in the one JPEG we have), adjacent frames can appear 1 s apart across a second boundary, so a split rule needs a gap of at least 2 s. The threshold depends on question 3. This also groups fast single shots.
2. **Drive mode + time:** as above, but only for photos whose `DriveMode` says continuous or bracketing. Sources for the drive mode, if they work:
   - files already downloaded (no camera cost),
   - thumbnails, if question 2 is yes,
   - a range or early-aborted read of each file's start, if question 4 and 5 show it is cheap.
3. **Interval runs:** group by folder.

The UI should let the user split or merge a group, since none of these is exact.

## Test to settle the open questions

On a GR IV, with the Mac on the camera Wi-Fi:
1. Check the camera's drive menu for continuous speed options. Shoot several short bursts (at each speed, if there are several), with some presses less than 2 s apart, plus one bracketed set and one long hold.
2. For each new photo, request the info, the thumbnail and the preview, and time each request.
3. Request the start of each file with a `Range` header; record the status code and the bytes received. If there's no 206, start a plain GET, close it after 64 KB, and measure how many bytes arrived.
4. Read the EXIF and maker note of the thumbnails, previews and file starts. Compare `DriveMode`, `ShutterCount`, any frame or sequence fields, and the time fields across presses.
