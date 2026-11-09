# Image Control looks: blob contents, parameters and slot names

What the Image Control blob in the Custom 1–3 slots and `/imgctrl` holds, which parameters each base image has, what their values mean, and the rules for slot names. The wire layout itself is in [ble.md § Image Control blob](ble.md#image-control-blob); the HTTP read is in [http-api.md §4.3](http-api.md). Researched 2026-11-08 from GR WORLD 2.0.0 and GR IV firmware 1.20, and on 2026-11-09 with REA (Ghidra) on the GR IV 1.20 and GR III 2.20 `bled`, `libcamera-controller` and `webapid` and a byte scan of the GR III, GR IIIx and GR IV `rtos.bin`. The hardware results so far, all from a GR IV HDF on firmware 1.20 on 2026-11-09, are the blob length (ble.md) and the `effectList` in §3; nothing else here has been tried on a camera yet.

What the camera does to the image for each base and parameter, and the finding that Image Control changes processing only, never the capture, is in [image-control-processing.md](../image-control-processing.md).

Evidence tags:
- `[code 0x…]`: address in GR WORLD's Dart AOT disassembly (`work/dis/dis.txt`).
- `[pp+0x…]`: object pool entry (`work/cs/blutter_out/pp.txt`).
- `[fw]`: setting-name string in GR IV `rtos.bin` (`firmware/gr4_v120/rtos.bin`). GR IV, GR IV HDF and GR IV Monochrome use the same file ([camera-models.md §2](../camera-models.md)).
- `[fw3x]`: GR IIIx firmware 1.70 setting vocabulary as read by the third-party Ricoh3x project (https://github.com/Trimz/Ricoh3x/blob/main/docs/image-control.md and its `data/userdata_set_values.tsv`). Not checked against GR IV code.
- Manual pages with their URL, **[inferred]** and **[unknown]**.

GR WORLD reads its English labels through virtual getters. They were resolved by dumping the Dart dispatch table with a locally patched blutter build: the English localisation class is cid 1253 and an entry is `table[cid + selector + 4096]`.

## 1. Who builds a blob

| Fact | Evidence |
|---|---|
| GR WORLD's look model is a base image plus a list of (parameter, value). It has no field for the version byte or byte 1. | [code 0x82cd88] builds one; the parser [code 0xd8e104] reads only byte 0 (version check), byte 2, byte 3 and the pairs |
| **GR WORLD never encodes a blob.** No function turns the model back into bytes; every allocation of it is UI or parse code (0x82cd88, 0x834450, 0x959e84, 0x95a02c, 0x9b9028, 0x9c61e4, 0xd8e104). A slot write sends stored raw bytes unchanged: nothing on the path pads, truncates, re-encodes or checks the length. It writes with response and with long writes turned off, so the Android plugin refuses anything longer than MTU − 3 and a 56-byte write relies on GR WORLD's MTU 512 request ([ble.md](ble.md)). | write path [code 0xe32160 → 0xe34888 → 0xe34cac → 0xe623ac → 0xe5c094]; `allow_long_write` hard-coded 0 [code 0xa12ea4]; FBP plugin `C4069h.java:669-677`; its database keeps `image_control.raw BLOB NOT NULL` (`work/libapp.strings`) |
| The raw bytes come from the camera's `/v1/photos/<dir>/<file>/imgctrl`, Ricoh's GR Gallery server, or a Custom slot read over BLE. So the version byte and byte 1 GR WORLD writes are always what a camera produced. | [code 0xd8f0fc]; Ricoh's GR WORLD Image Control page, https://www.ricoh-imaging.co.jp/english/products/app/gr-world/imagecontrol/ |
| The camera's BLE server registers each Custom data characteristic with a maximum of 56 bytes (0x38) and each name with 32 (0x20), read and write. A write longer than the maximum is dropped with the log "overMaxLen" and gets no write response. Any shorter write is passed on unchanged: bled and `libcamera-controller` check only the slot number, then send the raw bytes and their length to the RTOS (IPC command `SetStillImageCtrlCustomData`, id 0x16). When the RTOS fails it, bled answers the write with an application error. A slot read succeeds only when the RTOS returns exactly the length the read asks for; that this is the 56-byte maximum, so the RTOS stores 56 bytes, is **[inferred]** from the reads in ble.md. What the RTOS validates is in the next row. | GR IV 1.20 `bled`: `Shooting::InitService` 0x73c98, `Characteristic::Write` 0x66ee0 → `IsValidRequestByte` 0x66bcc, `StillImageControlCustom{1,2,3}Data::WriteData` 0x80cc8 / 0x80f04 / 0x81140 → 0x739b8, `RespondWriteRequest` 0x963dc, read 0x66cc8 → 0x7e774; `libcamera-controller` `SetStillImageCtrlCustomData` 0x8de28, cmdset ids at 0x5e272 / 0x5e286. REA evidence bundle `firmware/evidence/image-control-ghidra-bundle.json`, decompiles in `work/rea-ic/` |
| **The RTOS checks every blob strictly and rejects the whole write on any mismatch; nothing is clamped.** The slot must be 0–2 and the length exactly 56 bytes (else status 2). Then a parser fills a default record: byte 0, the format version, must be ≤ 1 on the GR IV and GR IV HDF and ≤ 4 on the GR IV Monochrome (0 is accepted); byte 2, the base, must be one of that body's bases (colour bodies 00–09 and 0d–10, Monochrome 11–16 and 18; 0a–0c, Palette 17, Pictorialist 19 and anything higher are refused everywhere); then come (id, value) pairs from byte 4, two bytes each, and **each base expects exactly the ids of §3, in ascending order, at fixed positions**. Every value must be in that parameter's set (§4). Byte 1, byte 3 (the parameter count) and everything after the last expected pair are never read. A parse failure answers status 4. Found by running the firmware's own parser in an emulator on GR IV 1.20; not yet seen on a camera. | GR IV 1.20 `rtos.bin`: IPC handler 0x535ba4bc, parser 0x53605c08 with tables set up by 0x53605f20 (base table 0x550a28f8), version limit from 0x535fd76c; emulation `work/ic/scripts/ui_blob_emu.py`, notes `work/ic/notes/ui-followup.md` §5 |
| The base byte is the camera's `effect` property value: webapid names the same numbers (`off` 0, `col_vivid` 1 … `efc_HDRTone` 9, `efc_negaFilm` 13 … `efc_pictorialism` 25), and 10–12 are `col_custom1..3`, the slots themselves, which is why the base enum skips 0x0a–0x0c **[inferred]**. | GR IV 1.20 `webapid` `effect::SetPropIdAndTable` 0xb2b30, table built at 0xb2488 |
| GR WORLD's parser logs `Version: <b0>, CustomImage: <b2> -> <base>, parameter num: <b3>`; byte 1 is never read. | [code 0xd8e1dc–0xd8e318], [pp+0x2bcc8..0x2bce0] |
| Accepted versions: 1, 2 and 4. | [pp+0x2bcb8] |
| GR WORLD's fallback look is Standard with saturation, hue, key, contrast, highlight and shadow contrast, sharpness, shading and clarity, all 0. It is stored as a 56-byte constant: `01 00 00 09`, the nine pairs, then 34 zero bytes, the same length and padding as every blob a camera produces. | [code 0x82cd88], constant [pp+0x2be68] set at [code 0x82cd20] |
| GR WORLD offers Image Control for a GR IV only from firmware 1.04 (`isImageControlSupported`); its check returns true for every other model, and a GR III is kept out only because the photo viewer's Image Control button needs "GR IV" in the model name and a slot write fails when the characteristics are missing. | [code 0x8349f8 → 0x834b8c], [pp+0x2bda0]; [code 0x967e6c]; [code 0xe34cac] |
| A written blob needs version ≤ 1 on the GR IV and GR IV HDF and ≤ 4 on the GR IV Monochrome; the camera never reads byte 1 (the RTOS check above). What byte 1 means in the camera's own blobs is **[unknown]**. | GR IV 1.20 `rtos.bin` parser 0x53605c08 |

## 2. Slot names

| Fact | Evidence |
|---|---|
| At most 32 characters: GR WORLD's name field has maxLength 32 and a 32-character length formatter. | [code 0x960724, 0x9605cc]; again at [code 0x96fed4, 0x96fd7c] |
| Only ASCII letters, digits, whitespace and the symbols in ``[a-zA-Z0-9@#%:.,/+\\"'`~^*=()<>\[\]!?&_\s-]``. | [pp+0x32898], used by a FilteringTextInputFormatter at [code 0x9605dc] |
| Ricoh: "up to 32 single-byte characters, alphanumeric characters and symbols". | Ricoh's GR WORLD Image Control page (above) |
| Written as plain UTF-8, with no padding and no terminator; the read side strips NULs. | write [code 0xe62600]; read [notes/ble/CamSvcChars.md](../notes/ble/CamSvcChars.md) |

## 3. Parameters of each base image

The firmware names each stored setting `StillImageControlNo0Param<Base><Param>` for the colour bases and `AfterReleaseStillImageControlNo0Param<Base><Param>` for the monochrome ones `[fw]`. The parameter names map to wire ids by meaning, and the firmware's key order is exactly GR WORLD's wire-id order: Saturation 00, ColorHue 01, ImageKey 02, Contrast 03, ContrastHighLight 04, ContrastShadow 05, Sharpness 06, ColorToneMonotone 07, ColorToneCinema 08, ColorToneBleechBypass 09, ColorToneRetro 0a, ColorToneHdrIntense 0b, FilterEffectCustom 0c, Shading 13, ClarityControl 14, Particle 15, ParticleSize 16, ParticleStrength 17, HdrIntense 18, ColorToneCrossProcess 19, SolarizationType 23 **[inferred from names and order]**.

The custom filter's R, G and B values (0d–12) are not per-base settings: the firmware keeps four global sets, `FilterEffect{R,G,B}Custom1..4` `[fw]`. A base with the filter effect is listed with "+0d–12" below.

Ids are in ascending order. Whether a camera's blob lists them in this order is **[unknown]**; GR WORLD shows them in blob order (§5).

| Base (wire) | Body | Parameter ids | Firmware name |
|---|---|---|---|
| Standard 00 | colour | 00 01 02 03 04 05 06 13 14 | `Standard` |
| Vivid 01 | colour | 00 01 02 03 04 05 06 13 14 | `Vivid` |
| Monotone 02 | colour | 02 03 04 05 06 07 0c (+0d–12) 13 14 15 16 17 | `MonotoneGR` |
| Soft Monotone 03 | colour | 02 03 04 05 06 07 0c (+0d–12) 13 15 16 17 (no clarity) | `SoftMonotone` |
| Hard Monotone 04 | colour | 02 03 04 05 06 07 13 14 15 16 17 (no filter) | `HardMonotone` |
| Hi-Contrast B&W 05 | colour | 02 03 04 05 06 07 0c (+0d–12) 13 14 15 16 17 | `HighContrastBW` |
| Positive Film 06 | colour | 00 01 02 03 04 05 06 13 14 15 16 17 | `PositiveFilm` |
| Bleach Bypass 07 | colour | 00 01 02 03 04 05 06 09 13 14 | `BleechBypass_GR` |
| Retro 08 | colour | 00 01 02 03 04 05 06 0a 13 14 | `Retro` |
| HDR Tone 09 | colour | 00 01 0b 18 | `HdrCuisine` |
| Negative Film 0d | colour | 00 01 02 03 04 05 06 13 14 15 16 17 | `NegativeFilm` |
| Cinema (Yellow) 0e | colour | 00 01 02 03 04 05 06 08 13 14 15 16 17 | `CinemaYellow` |
| Cinema (Green) 0f | colour | 00 01 02 03 04 05 06 08 13 14 15 16 17 | `CinemaGreen` |
| Cross Processing 10 | colour | 00 01 02 03 04 05 06 13 14 19 | `CrossProcess` |
| Standard 11 | Monochrome | 02 03 04 05 06 07 13 14 15 16 17 | `MonochromeStandard` |
| Soft 12 | Monochrome | 02 03 04 05 06 07 13 15 16 17 (no clarity) | `MonochromeSoft` |
| High Contrast 13 | Monochrome | 02 03 04 05 06 07 13 14 15 16 17 | `MonochromeHighContrast` |
| Grainy 14 | Monochrome | 02 03 04 05 06 07 13 15 16 17 (no clarity: the blob parser expects none, and the image processing forces clarity neutral, although a `MonochromeGrainyClarityControl` key exists) | `MonochromeGrainy` |
| Solid 15 | Monochrome | 02 03 04 05 06 07 13 14 15 16 17 | `MonochromeSolid` |
| HDR Tone 16 | Monochrome | 0b 18 | `MonochromeHdrCuisine` |
| Palette 17 | GR IVx | not in firmware 1.20; probably 1a–22 (Base Color, White Point, Black Point, RGB Tone) **[unknown]** | — |
| Solarized Effect 18 | Monochrome | 02 06 07 14 15 16 17 23 | `MonochromeSolarization` |
| Pictorialist Effect 19 | Monochrome | 02 03 04 05 06 07 13 15 16 17 | `MonochromePictorialism` |

Which bases each body offers:
- **GR IV and GR IV HDF:** 00–09 and 0d–10 (GR IV manual p.94, https://www.ricoh-imaging.co.jp/resources/english/support/man-pdf/gr-4_en.pdf).
- **GR IV Monochrome:** 11–16 in its manual (p.90, https://www.ricoh-imaging.co.jp/resources/english/support/man-pdf/grIVmonochrome_En.pdf), plus Solarized Effect 18 by GR WORLD's table below. Pictorialist Effect 19 has firmware keys in the shared 1.20 image, but GR WORLD gives it only to the GR IV**x** Monochrome, so it is presumably that body's. Its specifications page (p.160) lists High/Low Key, Contrast with Highlight and Shadow, Sharpness, Shading, Clarity, Toning, Grain Effect and HDR Tone Level: no saturation, hue or filter effect (its red filter is a hardware switch).
- **GR WORLD's per-model table** ([code 0x82ca84], used by `findSupportedByCameraType` [code 0xda1db4]): each base in its look database carries a group (DB column `custom_image_version`, unrelated to the blob's version byte): 1 = the 14 colour bases 00–09 and 0d–10, 2 = monochrome 11–16, 3 = Palette 17, 4 = Solarized 18, 5 = Pictorialist 19. GR IV and GR IV HDF accept {1}, GR IV Monochrome {2, 4}, GR IVx {1, 3} and GR IVx Monochrome {2, 4, 5}. GR WORLD uses the table to split its library into a colour list and a monochrome list. When writing, it checks the camera type the look was saved from instead ([code 0x958740–0x9588ac]): Monochrome looks only to a body whose name contains "Mono", GR IV and GR IV HDF looks only to the others, GR IVx looks to none in 2.0.0. On a mismatch the write button is left out.
- At runtime a body lists the bases it offers in the `effectList` of `GET /v1/props`, by `effect` name (§1). Observed on a GR IV HDF, firmware 1.20, on 2026-11-09: `off col_vivid efc_monochrome efc_softMonochrome efc_hardMonochrome efc_highContrast efc_negaFilm efc_posiFilm efc_cineYellow efc_cineGreen efc_crossProcess efc_bleachBypass efc_retro efc_HDRTone col_custom1 col_custom2 col_custom3`, which is exactly its manual's list plus the three slots. The firmware is shared, so the list comes from a per-model choice in the RTOS that was not traced; the GR IV Monochrome's list has not been read **[unknown]**.
- **GR IVx:** Palette 17 and parameters 1a–22 come from its development announcement (https://news.ricoh-imaging.co.jp/rim_info2/2026/20260827_042443.html) and GR WORLD's hard-coded Japanese labels [code 0x95baf0]; its parameter set is **[unknown]**.
- **GR III and GR IIIx** (firmware 2.20 and 1.70, same method `[fw]`; their key sets are identical): no Cinema and no monochrome bases, and grain is one parameter (15) with no size or strength. Standard, Vivid, Bleach Bypass and Retro as on the GR IV; Positive Film 00–06 13 14; HDR Tone 00 01 0b 18; Monotone 02–07 0c 13 14 15; Soft Monotone 02–07 0c 13 15; Hard Monotone 02–07 13 14 15; Hi-Contrast B&W 02–07 0c 13 14 15; Negative Film 00–06 13 14 15. A firmware update added Cross Processing, 00–06 13 14 19 (`StillFwupImageControlNo{0,1,2}ParamCrossProcess*`), but the GR III `webapid`'s `effect` table names neither it nor Negative Film.
- **GR III and GR IIIx slots** (observed in the firmware, not on hardware): they have two Custom slots, `StillImageControlNo1/No2` with full per-base settings, selectable over HTTP as `effect=col_custom1|col_custom2`. Nothing reads or writes their contents from outside the camera: GR III `bled`'s `Shooting::InitService` 0x71a2c registers none of the six Image Control characteristics (none of their UUIDs occurs in it in any byte order), its `webapid` has no `imgctrl` route, and its RTOS has none of the GR IV's slot-name strings (`IsValidUserCustomName` and others) or `ipcu command - set/get imgctrl` debug commands. Ricoh's apps agree: GR WORLD does not write slots on these bodies (Ricoh's GR WORLD page), and Image Sync 2.1.32 has no Image Control characteristic, route or string; its only related setting is `effect`. Loading looks into a GR III or GR IIIx is therefore not possible over BLE or Wi-Fi.

## 4. Values

GR WORLD decodes each value as a signed byte [code 0xd8e504]. Its formatter [code 0x95a34c, values 0x95abc8–0x95b9ec] names the values of the enumerated parameters and prints every other value as the number itself, with `+` when above 0 ([pp+0xa108]). So for numeric parameters the wire value is the step the camera shows, −4..+4, not the firmware's internal 0..8 index **[inferred: otherwise +4 would show as +8]**. Values above the last named case show that case's name (toning 7 shows Purple). GR WORLD checks no ranges; it has no editor.

| Parameter (wire) | GR WORLD label | Values | Default | Evidence |
|---|---|---|---|---|
| saturation 00, hue 01, key 02, contrast 03, contrastHigh 04, contrastLow 05, sharpness 06, shading 13, clarity 14 | Saturation, Hue, High/Low Key Adjustment, Contrast, Contrast (Highlight), Contrast (Shadow), Sharpness, Shading, Clarity | −4..+4 **[inferred]** | 0 | shown as numbers [code 0x95b8ac]; range from `[fw3x]` `M4…P4`; the GR IV menu screenshot shows 0 (manual p.95) |
| toningMonotone 07 | Toning | 0 Off, 1 Sepia, 2 Red, 3 Green, 4 Blue, 5 Purple | 0 **[inferred]** | [code 0x95abc8–0x95ad54]; `[fw3x]` agrees |
| toningCinema 08 | Toning | 0 Low, 1 Medium, 2 High | **[unknown]** | [code 0x95ae18–0x95aee4], shared with grainStrength; GR IV only |
| toningBleachBypass 09 | Toning | GR WORLD names 0 Off, 1 Normal, 2 Cool, 3 Warm. The camera accepts 0..3 in a blob; the image processing has a matrix for Normal, Cool and Warm, and what 0 renders is **[unknown]** | **[unknown]** | [code 0x95af9c–0x95b0a0]; `[fw3x]` `Normal=1 Cool=2 Warm=3` (a stored setting, not the blob); GR IV `rtos.bin` parser 0x53605c08 |
| toningRetro 0a | Toning | −4..+4 **[inferred]** | 0 | shown as a number; `[fw3x]` `M4…P4` |
| toningHdr 0b | Toning | 0 Off, 1 Black & White, 2 Sepia. The GR IV Monochrome's HDR Tone (16) accepts only 0 and 2 | 0 **[inferred]** | [code 0x95b158–0x95b214]; `[fw3x]` agrees; GR IV `rtos.bin` parser 0x53605c08 |
| filterEffect 0c | Filter Effect | 0 Off, 1 On. The camera refuses any other value in a blob, and the image processing applies the filter with the R, G and B values stored with the look ([image-control-processing.md §6.1](../image-control-processing.md)). GR WORLD's labels treat any non-zero value as On | 0 **[inferred]** | [code 0x95b2cc–0x95b350]; `[fw]` `FilterEffect{R,G,B}Custom1..4`; GR IV `rtos.bin` parser 0x53605c08 (table 0x550a2934), processing 0x5393a9e0 |
| filter R/G/B, high byte 0d/0f/11, low byte 0e/10/12 | rows R, G, B | each channel a signed 16-bit value split over two parameters: `(hi << 8) \| (lo & 0xff)`, minus 0x10000 from 0x8000. The camera accepts −200..+200 per channel and does not check the sum. The image processing reads them as percent weights of a black-and-white mix (×8192/100); the four factory custom sets are 10/70/20, 40/50/10, 90/20/−10 and 120/−10/−10, each summing to 100 | **[unknown]** | [code 0x834800–0x83489c]; hidden while 0c is 0 [code 0x95a02c, 0x834c4c]; GR IV `rtos.bin` parser 0x53605c08, processing 0x5393a9e0, defaults 0x53547fe4 |
| grain 15 | Grain Effect | 0 Off, 1 On; the camera refuses any other value in a blob. The GR IIIx kept one setting (`Off=0 High=1 Mid=2 Low=3`); the GR IV splits it into 15–17 | 0 **[inferred]** | [code 0x95b2dc–0x95b350]; size and intensity hidden while 0 [code 0x834c0c]; GR IV `rtos.bin` parser 0x53605c08 |
| grainSize 16 | Size | 0 Small, 1 Medium, 2 Large | **[unknown]** | [code 0x95b408–0x95b4c8] |
| grainStrength 17 | Intensity | 0 Low, 1 Medium, 2 High | **[unknown]** | [code 0x95ae28] |
| hdrStrength 18 | HDR Tone Level | GR WORLD names 0 Off, 1 Low, 2 Medium, 3 High. The camera accepts 0..3 in a blob, and level 0 turns the HDR effect off | **[unknown]** | [code 0x95b580–0x95b678]; `[fw3x]` `Low=1 Mid=2 High=3`; GR IV `rtos.bin` parser 0x53605c08, effect strength ([image-control-processing.md §8.4](../image-control-processing.md)) |
| crossProcess 19 | Color Tone | 0 Basic, 1 Magenta, 2 Yellow | **[unknown]** | [code 0x95b730–0x95b7f8] |
| solarizationType 23 | Solarization Type | 1..3 in a blob; the camera refuses 0. It stores them as 0..2, and each selects one of three solarization curves | **[unknown]** | no case in [code 0x95a34c]; GR IV `rtos.bin` parser 0x53605c08, curves chosen in 0x5393a9e0 ([image-control-processing.md §6.3](../image-control-processing.md)) |
| baseColor 1a, whitePoint 1b, blackPoint 1c, RGB tone 1d–22 | Japanese labels only | shown as numbers; range **[unknown]** | **[unknown]** | [code 0x95baf0] |

## 5. How GR WORLD shows a look

| Rule | Evidence |
|---|---|
| Rows follow the blob's order, except Solarization Type, which moves to the top. | [code 0x959e84], closure [code 0x95c1a8] |
| Filter Effect is followed, while On, by one row each for R, G and B (combining the two bytes); the six byte rows are never shown. | [code 0x95a02c, 0x834450] |
| Grain Effect is followed, while On, by Size and Intensity. | [code 0x95a02c, 0x834c0c] |
| English base names: Standard, Vivid, Monotone, Soft Monotone, Hard Monotone, Hi-Contrast B&W, Positive Film, Bleach Bypass, Retro, HDR Tone, Negative Film, Cinema (Yellow), Cinema (Green), Cross Processing; monochrome Standard, Soft, High Contrast, Grainy, Solid, HDR Tone, Palette, Solarized Effect, Pictorialist Effect. | [code 0x95c764] and the base enum's labels (`work/cs/blutter_out/objs.txt`) |
| A second id on each base (Standard 1, Vivid 2, Palette 3, Monotone 4 … Pictorialist 0x17) looks like the camera's menu order, with the GR IVx's Palette after Vivid **[inferred]**. | base enum objects in `objs.txt` |

## 6. What GR Lab does where the facts stop

These are GR Lab's choices **[design]**, in `packages/gr_camera/lib/src/looks/`:
- **A new look** copies the version byte and byte 1 from a blob a camera produced (a slot's, else a saved look's). With neither, as on the home dock's Looks page before any look is saved, it uses `01 00`: the header of GR WORLD's fallback constant (§1), and version 1 is what a GR IV HDF on firmware 1.20 stores (ble.md). Whether every body accepts that header in a written blob is **[unknown]**; a refusal shows as a failed load. On the home dock such a look starts on Standard and keeps to the colour bases (`lookBasesWith`).
- **Changing the base** keeps the values both bases share, drops the parameters the new base lacks and adds the missing ones at 0, or at the lowest value where 0 is out of range (bleach-bypass toning and HDR Tone Level start at 1). New parameters follow the ascending order of §3, and a base with the filter effect gets the six R, G and B bytes at 0. The camera requires exactly that order (§1).
- **Editing** covers the parameters whose values are known: the numeric ones as −4..+4 and the enumerated ones as listed in §4, with bleach-bypass toning and HDR Tone Level limited to 1..3. The filter effect, the solarization type and the GR IVx parameters are shown but kept as the camera set them.
- **Slot names** follow §2: at most 32 characters from GR WORLD's character set.
- **Loading** writes the data, then the name, then reads the slot back, as GR WORLD does ([notes/ble/CamSvcChars.md](../notes/ble/CamSvcChars.md) §7), and traces whether the camera kept the bytes as written. Every look is written as a 56-byte blob with zeros after the parameters, the only length the camera has been seen to accept ([ble.md § Image Control blob](ble.md#image-control-blob)).
- **Which bases a body gets** follows GR WORLD's per-model table (§3): the 14 colour bases on the GR IV and GR IV HDF, monochrome 11–16 plus Solarized on the GR IV Monochrome. The GR IVx gets the colour bases without Palette, whose parameters are unknown. GR Lab refuses, before writing anything, to load a look whose base the connected body does not get, or whose base GR Lab does not know; the editor disables Load for it. GR WORLD instead checks the camera type a look was saved from, and what the camera does with a base it does not offer is **[unknown]**.
- **Where looks live**: saved looks are kept on the phone, not with the camera they came from, so forgetting a camera keeps them. The home dock's Looks page edits them with no camera: a look keeps to the base list that holds its base (the monochrome one for a monochrome base, the colour one otherwise; `lookBasesWith`), so an edit never moves it off the bodies that could load it. Only a model with Custom slots GR Lab can reach (the GR IV family, `CameraFeature.lookSlots`) has a Looks page of its own, which loads looks into C1–C3, or on a GR IV older than 1.04 asks for the update; the GR III family has none, since GR Lab cannot load into it.
- **Which looks are the same**: two looks are the same when their settings are equal (`LookSettings`): the same base number and the same value for every parameter number. The version byte, byte 1, the order of the pairs, the zeros after them and the blob's length are not compared, so a look still matches after a camera stores it in another format version, and a base or parameter GR Lab does not know is compared by its number. A parameter listed twice counts with its first value. A look that lacks a parameter differs from one that has it at its initial value, because what a camera takes a missing parameter to be is **[unknown]** (the GR IV's RTOS refuses such a blob, §1). The settings are worked out from the stored blob each time and never saved, so this rule can change without converting saved looks.
- **Saved looks differ**: the library on the phone refuses to save or rename a look when another saved look has its name (compared exactly, including case), its settings or both, and says which look is in the way. Looks saved before this rule are kept as they are; one of them can't be saved again until it differs from the others. GR Lab does not hold the camera's slots to the rule: it loads the same look or name into more than one slot when asked. Whether the camera or GR WORLD refuses a repeated look or slot name was not looked into **[unknown]**.
- **Before reading the slots** GR Lab turns the camera on into shooting mode, because the slots are served by the main firmware rather than the Bluetooth-only state of a camera that is off **[inferred]** ([firmware-bonding.md §6](firmware-bonding.md)).
- **Which bodies can load looks** follows GR WORLD's `isImageControlSupported` (§1): a GR IV from firmware 1.04, the GR IV HDF, GR IV Monochrome and GR IVx on any version, and no GR III body. On an older GR IV the Looks tab asks for a firmware update and does not turn the camera on. Whether a GR IV before 1.04 actually lacks the slot characteristics is **[unknown]**.

## 7. Open questions

- The GR IVx parameters, and the camera's defaults for the enumerated parameters. The GR IV accepts −4..+4 for every numeric parameter (§1), but whether its menu offers the full range is not checked against a camera.
- What the camera's own blobs carry in byte 1 and what it means; the camera never reads it (§1).
- The GR IV Monochrome's and GR IVx's `effectList` (§3).
