# Image Control processing: what each base and slider does to the image

How the camera renders each Image Control base image and each of its parameters, worked out from the GR IV and GR III firmware so that GR Lab's look preview can approximate it. The wire format and parameter lists are in [protocol/image-control.md](protocol/image-control.md); this file covers the image processing behind them.

Researched 2026-11-09 by static analysis of the RTOS image (`rtos.bin`) of GR IV firmware 1.20 and GR III firmware 2.20. The GR IIIx 1.70 RTOS differs from the GR III 2.20 one in 27 bytes (version strings and model constants), and its tables are byte-identical, so everything said about the GR III applies to the GR IIIx. GR IV, GR IV HDF and GR IV Monochrome share one image ([camera-models.md §2](camera-models.md)). **Nothing here has been checked against photos from a camera yet**; §11 lists the tests that would.

## How this was found

- The RTOS is raw little-endian ARMv7 loaded at 0x53000000. The reset handler at 0x5300038c copies `.data` to 0x55000000 from file offset 0x13B3100 (GR IV, 0x58500 bytes) or 0x107B640 (GR III, 0x3A0C0 bytes); the pointer tables that pick per-base data live there. Strings and tables are reached through `movw`/`movt` pairs, not literal pools.
- Ghidra 12.1.4 headless analysed both images in full with that memory map (the REA MCP call times out on a 21 MB raw image, see image-control.md §7). REA 6.8.0 `decompile-all` over the GR IV processing modules (0x53898000–0x53951000, 2461 functions, no failures) gives the evidence record `ev_7951f9b6dca0f4f634a707e9fbcd72f159bdfb0c1a0cba3799756f78b43a4dcb`, output in `work/rea-ic/gr4-pipeline/`.
- The tone-curve generator was re-implemented and checked bit for bit against the firmware's own function run in an emulator (Unicorn): all 6561 slider combinations match on both cameras.
- Workspace files (Ricoh's data, kept in `../gr`, never in this repository): notes per topic in `work/ic/notes/` (`tone.md`, `color.md`, `mono.md`, `effects.md`, `sensor.md`), the extracted tables as JSON in `work/ic/data/`, and the scripts that regenerate them from the firmware by address in `work/ic/scripts/`. The full 256-entry curves and every table cited below are there.

Evidence tags: **[code]** read in the decompiled or disassembled firmware (function or table address given, GR IV unless marked); **[emulated]** reproduced exactly by running the firmware function; **[inferred]**; **[unknown]**. Addresses are RTOS virtual addresses.

## 1. Processing only: Image Control never changes the capture

On both cameras no code that drives the sensor, auto exposure, metering, ISO, exposure compensation, highlight correction or shadow correction reads the base or any slider **[code]**:

- A scan of every ARM load from the setting fields (GR IV record offsets 0x79c–0x7b9) and every caller of their getters finds readers only in the UI models, ImageTuning, the DigitalFilter effects, the maker-note writers, white balance and the lens vignetting correction. None is in the AE, ISO, sensor-driver or sensor pre-processing modules. The scan cannot see a reader that reaches the fields through a pointer to a sub-structure, or Thumb code; the two Thumb hits were data.
- The ImageTuning instance that serves auto exposure (`ImageTuningAeSensor`, built at 0x5393ba6c; GR III vtable 0x53dbda38) runs the processing stages without ever receiving the Image Control parameters. The still (0x5393b64c) and live-view (0x5393bc28) instances do receive them.
- RAW pixel data is the same for every base. The base and each slider are written to the maker note (encoders 0x53800f7c–0x53804f3c, decoder 0x537fbad0), and RAW Development runs the whole pipeline again from its own copy of the settings record. This matches the manual: Image Control "is not applied to RAW images. It can be set when [RAW Development] … is performed" (GR IV manual p.91, p.96).
- HDR Tone is a single-frame effect on the developed image (§8.4). The camera's sensor-HDR code (`STILL_HDR`, `SHDR…`) has no Image Control reader. Grainy, Hi-Contrast B&W and Bleach Bypass add no frames and no exposure bias.
- Live view uses the same ImageTuning stages with the same Image Control copy (0x53939128), so the live view on the camera shows the base's colour and tone. Whether the DigitalFilter effects (§8) also run in live view is **[unknown]**.

Three side effects reach outside the colour and tone stages, all still processing:

| Base | Effect | Evidence |
|---|---|---|
| Cross Processing (GR IV id 0x17, GR III 0x15) | Changes the auto white balance, only in the CTE white balance mode: colour bins 5–9 of 33 contribute alternate terms (×−0.6 and ÷10) before a fixed 3×3 matrix. The size of the shift is **[unknown]** because the bins' meaning was not decoded. The JPEG, PEF and DNG writers also add a three-word maker-note block, probably the cross-process parameters for RAW Development **[inferred]**. | 0x5395bdec, `CWhiteBalanceCte` 0x53960edc; GR III 0x53700510, 0x5370525c |
| Solarized Effect (GR IV id 0x20) | Turns off the lens vignetting correction (Peripheral Illumination Correction) in still development and live view, even when the menu setting is on. | still 0x539655d8 `if (setting == off \|\| id == 0x20) return`; live view 0x5365e760 |
| Bases with a DigitalFilter effect in use | Adds the effect stage (§8) to the still processing recipe. | 0x53739a5c |

Why the manual forbids Soft Monotone and HDR Tone in B (bulb) mode (p.94–95) is **[unknown]**: no exposure-side code tests the base.

## 2. Pipeline

Order for a still on the GR IV **[code]** for the stage list, **[inferred]** for the exact hardware order inside the RAW-to-YCbCr block:

1. White balance gains on the camera RGB.
2. Colour matrix block 0: `M = B_base · A`, then each row is normalised to sum to 1 so greys stay grey (`ColorMatrixTuning` 0x5393cc14). `A` is the camera matrix, shared by all bases; `B_base` is the base's look matrix (§4.1).
3. Multi-axis hue correction for Standard, Positive Film and the two Cinema bases only (§4.5).
4. Tone: one gamma curve per R, G, B channel, applied to linear data, from the four tone sliders (§3). Some bases then apply an extra per-channel curve (§5).
5. Colour matrix block 1: saturation (§4.2) on colour bases, the black-and-white weights (§6.1) on Monotone, Soft Monotone and Hi-Contrast B&W. That this block comes after the tone curve is **[inferred]** from its separate register block (0x1120 onward).
6. RGB→YCbCr with BT.601 weights, combined with the hue rotation (§4.3).
7. YCbCr operation: toning offsets (§4.4, §6.2).
8. Edge enhancement (sharpness, §8.5) and noise reduction run inside the same hardware block.
9. JPEG-domain effects on the finished 8-bit YCbCr image, in this order: Shading, Clarity, Grain, HDR Tone (§8; GR IV 0x538ce51c, GR III 0x53680eac). Each is skipped when its value is 0.

Noise reduction depends only on capture mode, the High-ISO NR setting and ISO, never on the base or a slider **[code]** (`LumaNrTuning`, `ColorLpfTuning` table getters 0x5394e86c, 0x5394e8ec).

The GR III has the same pipeline, with these differences: saturation is folded into the single linear colour matrix (`S · B · A`, 0x536deea4), there is no per-channel base curve stage, and the multi-axis correction is present but off for every base.

## 3. Tone: the gamma curve and the four tone sliders

Every base uses the same curve generator (GR IV 0x539458c4, GR III 0x536e7b3c) **[code] [emulated]**. The base never picks a different gamma; the bases that look tonally different get an extra curve after it (§5).

- **Input and output:** 256 points over 12-bit linear input (point *i* = input 16·*i*), 14-bit output (0–16384), sRGB-encoded. Applied to R, G and B separately. A fourth table, `Y = (77R + 150G + 29B) >> 8`, is built from them.
- **Neutral curve** (all four sliders 0), output/16384 at linear input: 1/32 → 0.161, **0.125 → 0.468** (the curve's mid-grey), 0.18 → 0.563, 0.25 → 0.649, 0.5 → 0.836, reaches 1.0 at 0.96. It is darker than sRGB below 1/16 and brighter in the upper mid-tones, so a plain sRGB curve is not a good stand-in.
- **Source tables:** 15 tables of 256 × u16, three contrast sets (high, neutral, low) × five tables each designed for mid-grey at 12-bit input 128, 256, 512, 1024 and 2048. Set pointers at `.data` 0x55033880 (GR III 0x550204dc). The tables are byte-identical on both cameras.

The sliders, with steps −4..+4 as the camera shows them:

| Slider | What it does | Effect |
|---|---|---|
| High/Low Key (`key`) | Moves the input that maps to the curve's mid-grey by 2^(−step/4): ¼ EV per step, ±1 EV at ±4 (factors at 0x53b762a4: 0x200 … 0x80). The output at mid-grey stays 0.468. The generator interpolates between the five level tables, so the highlight end is reshaped rather than just scaled: key +4 clips at input 0.86, key −4 at 0.99. | Output at linear 0.18: 0.384 (−4), 0.474 (−2), 0.563 (0), 0.654 (+2), 0.731 (+4) |
| Contrast | Blends toward the high- or low-contrast set by 1/6 per step (2/3 of the way at ±4), pinned at mid-grey. | Log-log slope at mid-grey: 0.43 (−4), 0.49, 0.55 (0), 0.68, 0.80 (+4) |
| Contrast (Highlight) | The same blend at 1/12 per step, only above mid-grey, phased in over the 2 EV above it with the ramp table at 0x540b1eb4. | Output at linear 0.5: 0.802 (−4) to 0.862 (+4) |
| Contrast (Shadow) | The same, only below mid-grey, phased in over the 2 EV below. The firmware stores `4 − index` (0x5394607c `rsb r0, r0, #4`), so a higher index lightens shadows. | Output at linear 0.01: 0.049 to 0.068 |

The exact integer algorithm is in `work/ic/notes/tone.md` §4.2 (about 40 lines), and every curve is precomputed in `work/ic/data/tone/` (each slider alone, and all 729 contrast × highlight × shadow combinations). Whether the camera stores UI +4 of Contrast (Shadow) as index 8, which would make + lighten the shadows (the opposite of the other two contrast sliders), is **[unknown]**.

HDR Tone and Mono HDR force all four sliders to neutral. Solarized Effect keeps Key and forces the three contrast sliders to neutral **[code]** (0x53939128).

The curve's mid-grey also tracks a per-shot gain that multiplies the white balance gains by the same amount, so a preview can ignore it **[inferred]**. Shadow Correction (`ToneControlTuning`, 0x53947230) is a separate brightness map driven by its own menu setting, not by Image Control. Retro alone writes four ToneControl registers, (−32, 0, 120, 0); their meaning is **[unknown]** (a lifted black for the faded look is plausible but untraced).

## 4. Colour

### 4.1 Base look matrices

Each colour base is a 3×3 matrix `B` applied to linear RGB after the camera matrix; its rows sum to 1, so greys stay grey **[code]** (set table `.data` 0x55054800, indexed through `DAT_5407a53c[id]`; Q13 fixed point, 8192 = 1.0). Matrices act on column vectors (R, G, B). Effect relative to Standard is measured on linear test colours as BT.601 Cb/Cr hue shift and chroma ratio.

| Base | B (GR IV) | Relative to Standard |
|---|---|---|
| Standard | `[1.0664 0.0039 −0.0703; 0.0273 1.0117 −0.0391; −0.0234 0.0547 0.9688]` | — |
| Vivid | `[1.1218 −0.0070 −0.1149; −0.0022 1.1348 −0.1326; −0.0481 −0.0790 1.1271]` | chroma ×1.08–1.23, hue within ±5° |
| Positive Film | `[0.9688 0.3047 −0.2734; −0.0195 1.1758 −0.1562; −0.0703 0.3945 0.6758]` | chroma ×0.84–0.95; yellows and greens brighter (Y +0.13, +0.19) |
| Negative Film | `[1.0912 −0.2004 0.1092; 0.1522 0.7220 0.1257; 0.0070 0.2643 0.7288]` | chroma ×0.6–0.96; greens turn about 27° toward cyan and darken |
| Bleach Bypass, toning Normal | `[0.5469 0.3445 0.1086; 0.1558 0.7135 0.1307; 0.1343 0.3202 0.5455]` | chroma ×0.38–0.42 |
| Bleach Bypass, Cool | `[0.4948 0.3391 0.1661; 0.1389 0.7261 0.1350; 0.0962 0.2999 0.6039]` | |
| Bleach Bypass, Warm | `[0.5837 0.3568 0.0595; 0.1891 0.6864 0.1245; 0.2277 0.3347 0.4376]` | |
| Retro | `[0.6182 0.3350 0.0469; 0.1395 0.8092 0.0513; 0.0582 0.3355 0.6063]` | chroma ×0.5, hue about +5° |
| Cinema (Yellow) | `[0.7656 0.2266 0.0078; 0.0078 0.9062 0.0859; 0.0000 0.2500 0.7500]` | chroma ×0.7, plus curves (§5) |
| Cinema (Green) | `[0.6758 0.3008 0.0234; 0.0234 0.7930 0.1836; −0.0078 0.2578 0.7500]` | chroma ×0.52–0.67, plus curves (§5) |
| HDR Tone, Cross Processing | Standard's matrix | look comes from §5 and §8.4 |
| Hard Monotone | every row `[0.7773 0.9297 −0.7070]` | a luminance mix that darkens blue (§6.1) |

Camera matrix `A` (GR IV): `[1.6419 −0.8031 0.1613; −0.1865 1.4833 −0.2968; 0.0635 −0.5145 1.4510]`. For a preview working on an sRGB photo, the base's change is `B_base · B_Standard⁻¹` applied in linear light.

GR III: Vivid, the three Bleach Bypass matrices, Retro, Negative Film and Hard Monotone are identical. Its Standard (also used by HDR Tone and Cross Processing) is `[0.9907 0.0907 −0.0814; 0.0018 1.0496 −0.0514; −0.0298 0.0662 0.9636]`, its Positive Film `[0.9773 0.2852 −0.2625; −0.0189 1.1692 −0.1503; −0.0651 0.3711 0.6940]`, and its camera matrix differs (different sensor).

### 4.2 Saturation

One global matrix per step, not per hue **[code]** (table pointer in the colour struct, 0x5501bd34; matrices 0x5408081c … 0x5408090c): `rgb' = s·rgb + (1 − s)·Y`, with Y ≈ BT.601 luma and **s = 1.1^step** (0.683 at −4, 0.909 at −1, 1.100 at +1, 1.465 at +4). The fit to the stored matrices is within 0.002. GR III uses the same values. On the GR IV it sits in colour matrix block 1, which is after the tone curve **[inferred]** from its register block; on the GR III it is part of the linear matrix before the curve **[code]**.

### 4.3 Hue

A rotation of (Cb, Cr) after RGB→YCbCr, **2.46° per step**, ±9.9° at ±4 **[code]** (matrices 0x5408da1c … 0x5408db3c, Q13: +1 is `Cb' = Cb − 0.043·Cr`, `Cr' = 0.043·Cb + Cr`). Positive steps turn red toward yellow and blue toward magenta. Same on every colour base and on the GR III; monochrome bases use an identity table.

### 4.4 Toning on colour bases

Added to Cb and Cr in the YCbCr operation stage **[code]** (registers 0x54c/0x54e, signed 10-bit). The values below are the raw register values; their scale relative to 8-bit chroma is **[unknown]** (one reading takes them as 8-bit, another as 10-bit, a factor of 4 apart). A comparison shot would settle it (§11).

| Base, toning | (Cb, Cr) added |
|---|---|
| Retro −4 … +4 | Cb 72, 54, 36, 18, 0, −20, −40, −60, −80; Cr −24, −18, −12, −6, 0, 16, 32, 48, 64 (− cooler and bluer, + warmer and yellower) |
| Bleach Bypass Normal / Cool / Warm | (+12, −36) / (+40, −60) / (−40, 0), each with its own matrix (§4.1) |
| HDR Tone B&W / Sepia | chroma set to (0, 0) / (−36, +24), after a BT.601 conversion to grey |

Cinema toning (Low, Medium, High) is a curve blend, not an offset (§5). GR III: same values.

### 4.5 Multi-axis hue correction

`MultiAxialTuning` holds 12 groups × 5 levels of 3×3 matrices that act only inside hue windows. On the GR IV it is active for Standard, Positive Film, Cinema (Yellow) and Cinema (Green); every other base, and every GR III base, uses a set that is off **[code]**. The windows all lie around red, skin and orange **[inferred]** from their angles, and inside them the change is within ±15° of hue and ×0.7–1.3 chroma. How the hardware blends windows and levels is **[unknown]**. For a preview this is a second-order skin and red correction that can be left out.

## 5. Per-channel curves after the gamma

Some bases replace each channel's output with a 256-entry curve applied to the gamma's output (GR IV 0x53946130, table `.data` 0x55054158) **[code] [emulated]**: `out_c = T_c(gamma_c(x))`, looked up at `g >> 6` with linear interpolation, 14-bit in and out. All other bases have no curve at this stage.

| Base | Curves | Shape |
|---|---|---|
| Hi-Contrast B&W, Mono High Contrast | one S-curve on all channels (0x540b6d98) | at 0, ¼, ½, ¾, 1: 0, 0.073, 0.500, 0.958, 1 (slope about 3.3 at the middle) |
| Cinema (Yellow) | separate R, G, B (0x540b7bac, 0x540b77ac, 0x540b71ac) | black raised to 0.055; blue held down in the upper mid-tones and highlights (0.635 at ¾ against about 0.77 for R and G), giving yellow highlights |
| Cinema (Green) | separate R, G, B (0x540b6798, 0x540b6384, 0x540b4578) | black raised; green lifted in the shadows, blue in the mid-tones, red lowered in the shadows |
| Mono Grainy (GR IV Monochrome only) | 0x540b6584 | matte: black 0.055, white 0.98, steep middle |
| Mono Solid (GR IV Monochrome only) | 0x540b53bc | mild shadow lift |
| Solarized Effect, type 0 / 1 / 2 | 0x540b1f78 / 0x540b51bc / 0x540b6998 | not monotonic. Type 0 rises to 0.85 at input 0.31, falls to 0.19 at 0.70, then rises to 1 |
| Cross Processing, tone Basic / Magenta / Yellow | R/G/B curve triples 3-4-5, 6-7-8, 9-10-11 of the 12 at `.data` 0x55053c54 | Basic: strong red S-curve, blue lifted at black (0.117) and capped at 0.884, so cyan shadows and warm highlights. Magenta: green lowered in the mid-tones, blue lifted in the shadows. Yellow: blue capped at 0.775 |

- **Cinema toning** blends the R and B deviation from the G curve: `w = toning + 1` (Low 1, Medium 2, High 3), `R' = (w·R + (3 − w)·G)/3`, `B' = (w·B + (3 − w)·G)/3`, `G' = G` **[code]**.
- **Cross Processing** tone 0/1/2 selects the fixed triple **[code]** (0x5393a730 sets state 2/3/4, mapped to recipes by 0x5394d368). The firmware also has a random mode that permutes curves 0–2 and randomises saturation, hue, key, contrast and sharpness, but nothing reachable from the three Image Control tones selects it **[code]**; what does is **[unknown]**. The other sliders still apply on top. The GR III has the same 12 curves, the same presets and the same random mode.
- The GR III has no per-channel curve stage. Its Hi-Contrast B&W instead uses a hard linear clip from the DigitalFilter gamma coordinator (0x536f00fc): `y = clamp((256·x − 60)/136, 0, 1)` on the 8-bit-scaled curve input.

## 6. Monochrome

### 6.1 Black-and-white conversion and Filter Effect

- **Monotone, Soft Monotone, Hi-Contrast B&W** convert in colour matrix block 1, the place saturation takes on colour bases, with three equal rows **[code]** (0x5393a9e0, 0x5393cc14). With Filter Effect off each weight is 0xaaa/8192 = **1/3: a plain average of R, G and B**, not a luma weighting. With it on, the weights are the look's R, G and B filter values as signed percentages (record 0x7ac, 0x7ae, 0x7b0, ×8192/100). Whether the weights act on linear or tone-mapped RGB on the GR IV is **[inferred]** as for saturation (§2); on the GR III they are part of the linear matrix before the tone curve **[code]**.
- **Filter values:** there is no yellow/orange/red list, only four global custom sets. Their factory defaults, from the settings initialiser (GR IV 0x53547fe4, GR III the same constants) **[code]**:

| Set | R | G | B | Acts like **[inferred]** |
|---|---|---|---|---|
| Custom 1 | 10 | 70 | 20 | green filter |
| Custom 2 | 40 | 50 | 10 | yellow filter |
| Custom 3 | 90 | 20 | −10 | orange/red |
| Custom 4 | 120 | −10 | −10 | deep red |

  Each sums to 100, so greys keep their level.
- **Hard Monotone** has no filter: its look matrix has three equal rows `[0.7773 0.9297 −0.7070]` (§4.1), so blue skies go very dark.
- **HDR Tone with B&W or Sepia toning, and Mono HDR** use BT.601-like weights `[0.301 0.586 0.113]`.
- **GR IV Monochrome bases** need no conversion: the sensor has no colour filter array and their matrices are identity.

### 6.2 Toning

Toning on the monochrome bases is an enum (0 Off, 1 Sepia, 2 Red, 3 Green, 4 Blue, 5 Purple), not a strength scale. A configuration bit that only the monochrome sets turn on makes the YCbCr operation **set** the chroma to a fixed (Cb, Cr) pair, the same at every brightness **[code]** (0x539450f0). Raw register values, scale **[unknown]** as in §4.4:

| | Off | Sepia | Red | Green | Blue | Purple |
|---|---|---|---|---|---|---|
| GR IV colour bodies and GR III: Cb | 0 | −24 | −8 | 0 | 20 | 16 |
| Cr | 0 | 16 | 28 | −24 | −8 | 4 |
| GR IV Monochrome bases: Cb | 0 | −12 | −4 | 0 | 10 | 8 |
| Cr | 0 | 8 | 14 | −4 | −4 | 2 |

The GR IV Monochrome's toning is half strength, and its Green much weaker.

### 6.3 The monochrome bases one by one

| Base (GR IV id) | What sets it apart |
|---|---|
| Monotone (0x0d) | average or filter conversion, neutral curve |
| Soft Monotone (0x0e), Mono Soft (0x1a) | Clarity forced to −3 (§8.2); no other softening stage |
| Hard Monotone (0x0f) | the blue-darkening matrix |
| Hi-Contrast B&W (0x10), Mono High Contrast (0x1b) | the S-curve (§5) |
| Mono Standard (0x19) | neutral |
| Mono Grainy (0x1c) | matte curve (§5), Clarity forced neutral, and "Rough" grain (§8.3) when Grain is on |
| Mono Solid (0x1d) | mild curve (§5) and its own edge-enhancement tables |
| Mono HDR (0x1e) | HDR Tone effect (§8.4), tone sliders neutral |
| Pictorialist Effect (0x1f) | **no processing of its own in firmware 1.20**: every table it loads matches Mono Standard's, and no soft-focus or glow stage is keyed on it **[code]**. The base belongs to the GR IVx Monochrome, which is not among the bodies in this image (project list: GR IV, GR IV HDF, GR IV Monochrome, GR IVx, GR IVx HDF), so its look is presumably in that body's firmware **[inferred]** |
| Solarized Effect (0x20) | the solarization curve chosen by the Solarization Type (0–2, record 0x7ba); contrast sliders and Shading forced neutral; lens vignetting correction off (§1) |

The ids of Pictorialist (0x1f) and Solarized (0x20) are settled by the camera's log routine (0x535be434), which prints `img : [M] Solarisation` for id 0x20, and by the Solarization Type read that only id 0x20 has (0x5393a9e0).

## 7. Which stages each base changes

| Base | Matrix | Curve after gamma | Toning | Other |
|---|---|---|---|---|
| Standard | yes | — | — | multi-axis |
| Vivid | yes | — | — | — |
| Positive Film | yes | — | — | multi-axis |
| Negative Film | yes | — | — | — |
| Bleach Bypass | yes, one per toning | — | offset | — |
| Retro | yes | — | offset (−4..+4) | ToneControl registers |
| HDR Tone | Standard's (BT.601 grey with B&W/Sepia toning) | — | set (B&W/Sepia) | HDR effect, tone sliders forced neutral |
| Cinema (Yellow), Cinema (Green) | yes | R/G/B, blended by toning | — | multi-axis |
| Cross Processing | Standard's | R/G/B preset by Color Tone | — | CTE white balance |
| Monotone family and Monochrome bases | §6 | §5 where listed | set (enum) | §6.3 |

The sliders each body offers are the same mechanism on every base that has them: the four tone sliders (§3), saturation (§4.2), hue (§4.3), sharpness (§8.5), and the four JPEG-domain effects (§8).

## 8. Detail effects

Shading, Clarity, Grain and HDR Tone run in the DigitalFilter module on the developed 8-bit YCbCr image (outputs clip to 0–255, chroma offset 128), in that order, each skipped at 0 **[code]**. Sharpness is an ISP stage.

### 8.1 Shading

A radial gain about the centre of the final crop (GR IV 0x538c8c3c, GR III 0x5367b630, identical) **[code]**. The strength per step is a Q12 constant `c`, the gain at the corner:

| Step | −4 | −3 | −2 | −1 | +1 | +2 | +3 | +4 |
|---|---|---|---|---|---|---|---|---|
| c | 0.25 | 0.354 | 0.5 | 0.707 | 1.26 | 1.587 | 2.0 | 2.52 |
| EV at the corner | −2 | −1.5 | −1 | −0.5 | +⅓ | +⅔ | +1 | +4/3 |

- Radius: ρ² = r² / (half-diagonal · f)², with f = 1.0 for 3:2, 0.9245 for 4:3, 0.9547 for 16:9 and 0.7845 for 1:1, divided by the digital zoom factor, so ρ = 1 at the corner of the saved frame **[code]**.
- The falloff between centre and corner is **[inferred]**: the constants fit `Y' = Y · c^(ρ²)` (or the linear `Y · (1 + (c − 1)·ρ²)`), applied to Y and to chroma about 128. That negative steps darken the corners is also **[inferred]** from the constants.
- This is separate from the lens vignetting correction (§1).

### 8.2 Clarity

A Laplacian pyramid on Y only (GR IV 0x538c98b8, GR III 0x5367c248) **[code]**: up to 11 levels of 2:1 reduction, each detail band multiplied by a gain from a 9 × 11 table in Q10 (GR IV 0x53b754c0, byte-identical on the GR III), then rebuilt. Chroma is untouched.

| Step | L0 | L1 | L2–L5 | L6 | L7 | L8–L10 |
|---|---|---|---|---|---|---|
| −4 | 1 | 0.801 | 0.758 | 0.801 | 0.823 | 1 |
| −2 | 1 | 0.896 | 0.870 | 0.896 | 0.907 | 1 |
| +2 | 1 | 1.117 | 1.148 | 1.117 | 1.102 | 1 |
| +4 | 1 | 1.248 | 1.319 | 1.248 | 1.214 | 1 |

The gains are geometric, about ×1.071 per step at L2–L5 (the full table is in `work/ic/data/effects/clarity.json`). The finest band (2-pixel detail) and the coarsest are never changed, so Clarity is local contrast at wavelengths of about 4–256 pixels of the full-size image. A preview at a smaller size has to shift the levels by log2(full width ÷ preview width).

### 8.3 Grain

- **GR IV, all bases except Mono Grainy** ("Granulation", 0x538c9854) **[code]**: fresh random noise each shot (xorshift128 reseeded from a clock), no stored grain texture. Size is a 3 × 3 blur of the noise (corner, edge, centre weights /256: Small 7, 28, 116; Medium 14, 29, 64; Large 15, 25, 44). Luma amplitude A by strength and size: Low 8/10/13, Medium 15/20/25, High 30/40/50 on colour bases, doubled on monochrome bases; colour bases also get chroma noise of 1–12. The blend, **[inferred]** from the lookup tables: `Y' = Y + min(Y, 255 − Y, A)·(2n/255 − 1)` with *n* the blurred noise byte.
- **GR IV Mono Grainy with Grain on** ("Rough", 0x538c6898) **[code]**: the Clarity pyramid with fixed strong gains (×2, ×2, ×3, ×1.4, ×1.3, ×1 on six levels) plus noise added to one octave chosen by Size (1, 2 or 4 pixel grain) and scaled by Intensity. So Grainy with grain on also raises fine and mid-scale contrast.
- **GR III** (0x5367ae2c): one setting (High, Mid, Low → scale 1, ½, ¼), luma only, no blur, with an amplitude that depends on brightness: about ±3 at black, ±33 at Y = 155, back to ±3 at white.

### 8.4 HDR Tone

A single-frame multi-scale local tone map on half-resolution Y (GR IV 0x538cd7e8, GR III 0x53680178, identical code and tables) **[code]**. Fine and mid levels pass through a lookup that pushes small differences up to a constant size (strong boost of small detail); the coarse levels (≥ about 256 pixels of the half-size image) are compressed to about 0.35 and then 0.18 of their contrast. The resulting correction is added to Y only, with strength 4, 8 and 16 for HDR Tone Level Low, Medium and High (1 : 2 : 4). The exact per-level arithmetic is **[inferred]**. HDR Tone also forces key, contrast, highlight, shadow, sharpness, shading and clarity to neutral.

### 8.5 Sharpness

Scales the ISP's edge-enhancement curves by a gain of `(step + 4)/4` (table 0, 32, …, 256 at GR IV 0x54091b0c, identical on the GR III) **[code]**: −4 turns edge enhancement off, +4 doubles it. The curves themselves depend on ISO: at base ISO the enhancement ignores the smallest edges (coring), peaks at bin 12 and falls to zero at bin 79, so large edges get none (halo control); at high ISO the coring and the peak move to larger edges. How edge size maps to bins is **[unknown]**, so a preview has to set the unsharp-mask amount by eye. A JPEG already carries the neutral sharpening, so a preview made from one should apply only the difference from neutral.

## 9. GR III and GR IIIx

Same code structure, and mostly the same data. The differences:

| Area | GR III 2.20 / GR IIIx 1.70 |
|---|---|
| Ids | 0x0b Standard, 0x0c Vivid, 0x0d Monotone, 0x0e Soft Monotone, 0x0f Hard Monotone, 0x10 Hi-Contrast B&W, 0x11 Positive Film, 0x12 Bleach Bypass, 0x13 Retro, 0x14 HDR Tone, 0x15 Cross Processing, 0x16 Negative Film. Record offsets are the GR IV's minus 0x20 |
| Tone curve | identical generator, tables and slider handling **[emulated]**; one extra slider-less gamma path for an internal id 9 that no user setting produces |
| Colour | different camera matrix and Standard/Positive Film matrices (§4.1); saturation folded into the linear matrix; no multi-axis correction; no Cinema bases or per-channel curve stage |
| Hi-Contrast B&W | hard linear clip instead of the S-curve (§5) |
| Monochrome | same 1/3 average, same filter rule and defaults, same toning tables, same Hard Monotone matrix; no Monochrome-model bases |
| Cross Processing | same 12 curves, presets and CTE white-balance effect |
| Clarity, Shading, HDR Tone, Sharpness gain | identical code and tables; sharpness curves are the GR III's own but the same shape |
| Grain | different (§8.3) |
| Lens vignetting override | none (no Solarized Effect) |

## 10. Approximating a look in GR Lab's preview

GR Lab previews a look on a photo the camera already developed, normally a Standard JPEG. A faithful preview therefore applies the difference between the target look and the photo's own look, not the look from scratch. In order:

1. Decode sRGB to linear. Apply `B_base · B_Standard⁻¹` (§4.1) for colour bases, or the §6.1 weights for monochrome ones.
2. Tone: find for each value the linear input of the neutral curve that produces it, then output the curve for the look's key, contrast, highlight and shadow (§3). With all four at 0 this is the identity.
3. Per-channel curve for the bases in §5, with the cinema blend.
4. Saturation `s = 1.1^step` and hue rotation 2.46° per step.
5. Toning offsets (§4.4, §6.2) once their scale is confirmed.
6. Shading, Clarity, Grain, HDR Tone (§8) on Y, scaled to the preview size; sharpness as an unsharp-mask difference.

A single 4 × 5 colour matrix, which is what `app/lib/src/looks/look_preview.dart` uses today, can reproduce steps 1 and 4 and the toning offsets. It cannot reproduce the tone curves, the per-channel curves (Cinema, Cross Processing, Hi-Contrast B&W, Solarized) or the spatial effects; those need a lookup table per channel (a 1D LUT, or a 3D LUT for the combined colour and tone) and image filters. The full curves are Ricoh's firmware data; shipping them in GR Lab is a decision for the project, not something these notes settle.

## 11. Open questions and hardware tests

Each needs a set of JPEGs of one scene from a GR IV (and a GR III for the differences) with one setting changed at a time:

- The scale of the toning offsets (§4.4, §6.2): Sepia Monotone against plain Monotone.
- The sign of Contrast (Shadow) (§3): −4 against +4.
- The Shading falloff and sign (§8.1): −4 and +4 on a flat, evenly lit wall.
- HDR Tone strength and the per-level arithmetic (§8.4): each level against Standard.
- What Retro's ToneControl registers do (§3).
- The sharpening bin scale (§8.5).
- Whether Clarity, Grain, Shading and HDR Tone appear in the camera's live view.
- How the multi-axis windows blend (§4.5) and what selects Cross Processing's random mode (§5).
- Why Soft Monotone and HDR Tone are unavailable in B mode (§1).
- How the GR IVx Monochrome renders Pictorialist Effect: not in firmware 1.20 (§6.3).
