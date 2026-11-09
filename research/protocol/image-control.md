# Image Control looks: blob contents, parameters and slot names

What the Image Control blob in the Custom 1–3 slots and `/imgctrl` holds, which parameters each base image has, what their values mean, and the rules for slot names. The wire layout itself is in [ble.md § Image Control blob](ble.md#image-control-blob); the HTTP read is in [http-api.md §4.3](http-api.md). Researched 2026-11-08 from GR WORLD 2.0.0 and GR IV firmware 1.20. The only hardware result so far is the blob length, observed on a GR IV HDF on 2026-11-09 and recorded in ble.md; nothing else here has been tried on a camera yet.

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
| **GR WORLD never encodes a blob.** No function turns the model back into bytes; every allocation of it is UI or parse code (0x82cd88, 0x834450, 0x959e84, 0x95a02c, 0x9b9028, 0x9c61e4, 0xd8e104). A slot write sends stored raw bytes unchanged. | write path [code 0xe32160 → 0xe34888 → 0xe34cac → 0xe623ac]; its database keeps `image_control.raw BLOB NOT NULL` (`work/libapp.strings`) |
| The raw bytes come from the camera's `/v1/photos/<dir>/<file>/imgctrl`, Ricoh's GR Gallery server, or a Custom slot read over BLE. So the version byte and byte 1 GR WORLD writes are always what a camera produced. | [code 0xd8f0fc]; Ricoh's GR WORLD Image Control page, https://www.ricoh-imaging.co.jp/english/products/app/gr-world/imagecontrol/ |
| The camera's BLE server passes a written blob straight on: `StillImageControlCustom{1..3}Data::WriteData` logs and calls the generic property write with the raw bytes. Validation happens in the RTOS and was not traced. | `bled` 0x70cc8 → 0x639b8 (`firmware/gr4-root/…/usr/bin/bled`) |
| GR WORLD's parser logs `Version: <b0>, CustomImage: <b2> -> <base>, parameter num: <b3>`; byte 1 is never read. | [code 0xd8e1dc–0xd8e318], [pp+0x2bcc8..0x2bce0] |
| Accepted versions: 1, 2 and 4. | [pp+0x2bcb8] |
| GR WORLD's fallback look is Standard with saturation, hue, key, contrast, highlight and shadow contrast, sharpness, shading and clarity, all 0. | [code 0x82cd88] |
| Which version and byte 1 a camera expects in a blob it did not produce, and what byte 1 means: **[unknown]**. Settling it needs a blob read from a camera. | — |

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
| Grainy 14 | Monochrome | 02 03 04 05 06 07 13 14 15 16 17 | `MonochromeGrainy` |
| Solid 15 | Monochrome | 02 03 04 05 06 07 13 14 15 16 17 | `MonochromeSolid` |
| HDR Tone 16 | Monochrome | 0b 18 | `MonochromeHdrCuisine` |
| Palette 17 | GR IVx | not in firmware 1.20; probably 1a–22 (Base Color, White Point, Black Point, RGB Tone) **[unknown]** | — |
| Solarized Effect 18 | Monochrome | 02 06 07 14 15 16 17 23 | `MonochromeSolarization` |
| Pictorialist Effect 19 | Monochrome | 02 03 04 05 06 07 13 15 16 17 | `MonochromePictorialism` |

Which bases each body offers:
- **GR IV and GR IV HDF:** 00–09 and 0d–10 (GR IV manual p.94, https://www.ricoh-imaging.co.jp/resources/english/support/man-pdf/gr-4_en.pdf).
- **GR IV Monochrome:** 11–16 in its manual (p.90, https://www.ricoh-imaging.co.jp/resources/english/support/man-pdf/grIVmonochrome_En.pdf), plus 18 and 19, which exist only as firmware keys and so presumably came with a firmware update. Its specifications page (p.160) lists High/Low Key, Contrast with Highlight and Shadow, Sharpness, Shading, Clarity, Toning, Grain Effect and HDR Tone Level: no saturation, hue or filter effect (its red filter is a hardware switch).
- That each body offers exactly its manual's list at runtime is **[inferred]**: the firmware is shared and the selection code was not traced.
- **GR IVx:** Palette 17 and parameters 1a–22 come from its development announcement (https://news.ricoh-imaging.co.jp/rim_info2/2026/20260827_042443.html) and GR WORLD's hard-coded Japanese labels [code 0x95baf0]; its parameter set is **[unknown]**.
- **GR III and GR IIIx** (firmware 2.20 and 1.70, same method `[fw]`): no Cinema, Cross Processing parameters or monochrome bases, and no grain size or strength. Standard, Vivid, Bleach Bypass and Retro as on the GR IV; Positive Film 00–06 13 14; HDR Tone 00 01 0b 18; Monotone 02–07 0c 13 14 15; Soft Monotone 02–07 0c 13 15; Hard Monotone 02–07 13 14 15; Hi-Contrast B&W 02–07 0c 13 14 15; Negative Film 00–06 13 14 15. GR WORLD does not write slots on these bodies (Ricoh's GR WORLD page).

## 4. Values

GR WORLD decodes each value as a signed byte [code 0xd8e504]. Its formatter [code 0x95a34c, values 0x95abc8–0x95b9ec] names the values of the enumerated parameters and prints every other value as the number itself, with `+` when above 0 ([pp+0xa108]). So for numeric parameters the wire value is the step the camera shows, −4..+4, not the firmware's internal 0..8 index **[inferred: otherwise +4 would show as +8]**. Values above the last named case show that case's name (toning 7 shows Purple). GR WORLD checks no ranges; it has no editor.

| Parameter (wire) | GR WORLD label | Values | Default | Evidence |
|---|---|---|---|---|
| saturation 00, hue 01, key 02, contrast 03, contrastHigh 04, contrastLow 05, sharpness 06, shading 13, clarity 14 | Saturation, Hue, High/Low Key Adjustment, Contrast, Contrast (Highlight), Contrast (Shadow), Sharpness, Shading, Clarity | −4..+4 **[inferred]** | 0 | shown as numbers [code 0x95b8ac]; range from `[fw3x]` `M4…P4`; the GR IV menu screenshot shows 0 (manual p.95) |
| toningMonotone 07 | Toning | 0 Off, 1 Sepia, 2 Red, 3 Green, 4 Blue, 5 Purple | 0 **[inferred]** | [code 0x95abc8–0x95ad54]; `[fw3x]` agrees |
| toningCinema 08 | Toning | 0 Low, 1 Medium, 2 High | **[unknown]** | [code 0x95ae18–0x95aee4], shared with grainStrength; GR IV only |
| toningBleachBypass 09 | Toning | GR WORLD names 0 Off, 1 Normal, 2 Cool, 3 Warm; the camera uses 1..3 **[inferred]** | **[unknown]** | [code 0x95af9c–0x95b0a0]; `[fw3x]` `Normal=1 Cool=2 Warm=3` (a stored setting, not the blob) |
| toningRetro 0a | Toning | −4..+4 **[inferred]** | 0 | shown as a number; `[fw3x]` `M4…P4` |
| toningHdr 0b | Toning | 0 Off, 1 Black & White, 2 Sepia | 0 **[inferred]** | [code 0x95b158–0x95b214]; `[fw3x]` agrees |
| filterEffect 0c | Filter Effect | 0 Off, anything else On; 1–4 selecting custom filter 1–4 is **[inferred]** | 0 **[inferred]** | [code 0x95b2cc–0x95b350] tells only zero from non-zero; `[fw3x]` `OFF=0 Custom1..4`; `[fw]` `FilterEffect{R,G,B}Custom1..4` |
| filter R/G/B, high byte 0d/0f/11, low byte 0e/10/12 | rows R, G, B | each channel a signed 16-bit value split over two parameters: `(hi << 8) \| (lo & 0xff)`, minus 0x10000 from 0x8000; range **[unknown]** | **[unknown]** | [code 0x834800–0x83489c]; hidden while 0c is 0 [code 0x95a02c, 0x834c4c] |
| grain 15 | Grain Effect | 0 Off, anything else On; that On is 1 is **[inferred]**. The GR IIIx kept one setting (`Off=0 High=1 Mid=2 Low=3`); the GR IV splits it into 15–17 | 0 **[inferred]** | [code 0x95b2dc–0x95b350]; size and intensity hidden while 0 [code 0x834c0c] |
| grainSize 16 | Size | 0 Small, 1 Medium, 2 Large | **[unknown]** | [code 0x95b408–0x95b4c8] |
| grainStrength 17 | Intensity | 0 Low, 1 Medium, 2 High | **[unknown]** | [code 0x95ae28] |
| hdrStrength 18 | HDR Tone Level | GR WORLD names 0 Off, 1 Low, 2 Medium, 3 High; the camera uses 1..3 **[inferred]** | **[unknown]** | [code 0x95b580–0x95b678]; `[fw3x]` `Low=1 Mid=2 High=3` |
| crossProcess 19 | Color Tone | 0 Basic, 1 Magenta, 2 Yellow | **[unknown]** | [code 0x95b730–0x95b7f8] |
| solarizationType 23 | Solarization Type | shown as a number; range **[unknown]** | **[unknown]** | no case in [code 0x95a34c] |
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
- **A new look** copies the version byte and byte 1 from a blob a camera produced (a slot's, else a saved look's), and GR Lab offers New look only when it has one.
- **Changing the base** keeps the values both bases share, drops the parameters the new base lacks and adds the missing ones at 0, or at the lowest value where 0 is out of range (bleach-bypass toning and HDR Tone Level start at 1). New parameters follow the ascending order of §3, and a base with the filter effect gets the six R, G and B bytes at 0. Whether the camera accepts a blob ordered differently from its own is **[unknown]**.
- **Editing** covers the parameters whose values are known: the numeric ones as −4..+4 and the enumerated ones as listed in §4, with bleach-bypass toning and HDR Tone Level limited to 1..3. The filter effect, the solarization type and the GR IVx parameters are shown but kept as the camera set them.
- **Slot names** follow §2: at most 32 characters from GR WORLD's character set.
- **Loading** writes the data, then the name, then reads the slot back, as GR WORLD does ([notes/ble/CamSvcChars.md](../notes/ble/CamSvcChars.md) §7), and traces whether the camera kept the bytes as written. Every look is written as a 56-byte blob with zeros after the parameters, the only length the camera has been seen to accept ([ble.md § Image Control blob](ble.md#image-control-blob)).
- **Before reading the slots** GR Lab turns the camera on into shooting mode, because the slots are served by the main firmware rather than the Bluetooth-only state of a camera that is off **[inferred]** ([firmware-bonding.md §6](firmware-bonding.md)).

## 7. Open questions

- The version byte and byte 1 for a blob the camera did not produce, and the meaning of byte 1.
- The GR IV's numeric ranges (±4 comes from the GR IIIx), the ranges of the solarization type, the custom filter values and the GR IVx parameters, and the camera's defaults for the enumerated parameters.
- Whether the camera rejects, clamps or keeps out-of-range values, unknown ids or a parameter set that does not match the base. The RTOS validator was not found: `rtos.bin` does not store its setting-name pointers as plain words, so the settings table could not be located quickly.
