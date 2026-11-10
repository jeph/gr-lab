# Image Control processing: what each base and slider does to the image

How the camera renders each Image Control base image and each of its parameters, worked out from the GR IV and GR III firmware so that GR Lab's look preview can approximate it. The wire format and parameter lists are in [protocol/image-control.md](protocol/image-control.md); this file covers the image processing behind them.

Researched 2026-11-09 by static analysis of the RTOS image (`rtos.bin`) of GR IV firmware 1.20 and GR III firmware 2.20. The GR IIIx 1.70 RTOS differs from the GR III 2.20 one in 27 bytes (version strings and model constants), and its tables are byte-identical, so everything said about the GR III applies to the GR IIIx. GR IV, GR IV HDF and GR IV Monochrome share one image ([camera-models.md §2](camera-models.md)). The GR IV part was then worked out a second time, independently of these notes, and the two results were compared; §12 lists what differed and how each difference was settled. **Nothing here has been checked against photos from a camera yet**, apart from one highlight check in §4.5; §11 lists the tests that would.

## How this was found

- The RTOS is raw little-endian ARMv7 loaded at 0x53000000. The reset handler at 0x5300038c copies `.data` to 0x55000000 from file offset 0x13B3100 (GR IV, 0x58500 bytes) or 0x107B640 (GR III, 0x3A0C0 bytes); the pointer tables that pick per-base data live there. Strings and tables are reached through `movw`/`movt` pairs, not literal pools.
- Ghidra 12.1.4 headless analysed both images in full with that memory map (the REA MCP call times out on a 21 MB raw image, see image-control.md §7). REA 6.8.0 `decompile-all` over the GR IV processing modules (0x53898000–0x53951000, 2461 functions, no failures) gives the evidence record `ev_7951f9b6dca0f4f634a707e9fbcd72f159bdfb0c1a0cba3799756f78b43a4dcb`, output in `work/rea-ic/gr4-pipeline/`.
- Where reading the code left a choice, the firmware's own functions were run in an emulator (Unicorn) with ROM and `.data` mapped: the tone-curve generator (re-implemented and checked bit for bit, all 6561 slider combinations on both cameras), the gamma setup for the slider signs, the Custom-slot blob parser, and the parameter builders and GPC program printer of the DigitalFilter effects.
- The independent pass (§12) used REA 6.8.0 with Ghidra 12.1.4 on the whole GR IV image, through a REA server of its own without the client's 30 s limit (38 798 functions decompiled, `work/ic-indep/dec-all/`). It ran the firmware's still tuning object in the emulator: `ImageTuningStill`'s `Initialize` (0x5393b9fc) and per-shot calculation (0x5393b644), for every base at neutral values and for every value of every slider (1498 runs, `work/ic-indep/emu_still.py` and `emu_sweep.py`), and read the register image they fill. It also ran the settings initialiser (0x53546c20) for the defaults in §7.1. Its notes, tables and scripts are in `work/ic-indep/` (`findings/`, `tables/`, `scratch/`).
- Workspace files (Ricoh's data, kept in `../gr`, never in this repository): notes per topic in `work/ic/notes/` (`tone.md`, `color.md`, `mono.md`, `effects.md`, `sensor.md`, and the follow-ups `ui-followup.md`, `isp-followup.md`, `dfhw-followup.md`), the extracted tables as JSON in `work/ic/data/`, and the scripts that regenerate them from the firmware by address in `work/ic/scripts/`. The full 256-entry curves and every table cited below are there.

Evidence tags: **[code]** read in the decompiled or disassembled firmware (function or table address given, GR IV unless marked); **[emulated]** reproduced exactly by running the firmware function; **[consistency]** the only reading of an undocumented hardware unit under which a constraint the firmware imposes holds (neutral settings give the identity, kernels sum to 1, a pyramid reconstructs), not run or observed; **[inferred]**; **[unknown]**. Addresses are RTOS virtual addresses.

## 1. Processing only: Image Control never changes the capture

On both cameras no code that drives the sensor, auto exposure, metering, ISO, exposure compensation, highlight correction or shadow correction reads the base or any slider **[code]**:

- A scan of every ARM load from the setting fields (GR IV record offsets 0x79c–0x7b9) and every caller of their getters finds readers only in the UI models, ImageTuning, the DigitalFilter effects, the maker-note writers, white balance and the lens vignetting correction. None is in the AE, ISO, sensor-driver or sensor pre-processing modules. The scan cannot see a reader that reaches the fields through a pointer to a sub-structure, or Thumb code; the two Thumb hits were data.
- The ImageTuning instance that serves auto exposure (`ImageTuningAeSensor`, built at 0x5393ba6c; GR III vtable 0x53dbda38) runs the processing stages without ever receiving the Image Control parameters. The still (0x5393b64c) and live-view (0x5393bc28) instances do receive them.
- RAW pixel data is the same for every base. The base and each slider are written to the maker note (encoders 0x53800f7c–0x53804f3c, decoder 0x537fbad0), and RAW Development runs the whole pipeline again from its own copy of the settings record. This matches the manual: Image Control "is not applied to RAW images. It can be set when [RAW Development] … is performed" (GR IV manual p.91, p.96).
- HDR Tone is a single-frame effect on the developed image (§8.4). The camera's sensor-HDR code (`STILL_HDR`, `SHDR…`) has no Image Control reader. Grainy, Hi-Contrast B&W and Bleach Bypass add no frames and no exposure bias.
- Live view uses the same ImageTuning stages with the same Image Control copy (0x53939128), so the live view on the camera shows the base's colour and tone. The DigitalFilter effects (§8) run only inside `DigitalFilterProcess`, which is created in the still-image module package (0x53729970) and scheduled only by the still recipe planner (0x53737504) **[code]**, so Clarity, Grain and HDR Tone very probably do not appear in live view. That is not proven: a live-view read of the effect settings through a copied structure or a 16-bit load would have been missed. Shading does appear, approximated by the ISP's own shading unit, whose tables the live-view process builds from the Shading value (§8.1) **[code]**. In a still capture the image for the instant review is produced before the effects run (still sequences place `DIRECT_VIEW` before `DIGITAL_FILTER`), so the review probably lacks them too **[inferred]**. In RAW Development the saved JPEG always gets the effects; the "speed" preview is made before them and the "quality" preview after them, and which one the RAW Development screen shows is **[unknown]**.

Three side effects reach outside the colour and tone stages, all still processing:

| Base | Effect | Evidence |
|---|---|---|
| Cross Processing (GR IV id 0x17, GR III 0x15) | Changes the auto white balance, only in the CTE white balance mode: colour bins 5–9 of 33 contribute alternate terms (×−0.6 and ÷10) before a fixed 3×3 matrix. The size of the shift is **[unknown]** because the bins' meaning was not decoded. The JPEG, PEF and DNG writers also add a three-word maker-note block, probably the cross-process parameters for RAW Development **[inferred]**. | 0x5395bdec, `CWhiteBalanceCte` 0x53960edc; GR III 0x53700510, 0x5370525c |
| Solarized Effect (GR IV id 0x20) | Turns off the lens vignetting correction (Peripheral Illumination Correction) in still development and live view, even when the menu setting is on. | still 0x539655d8 `if (setting == off \|\| id == 0x20) return`; live view 0x5365e760 |
| Bases with a DigitalFilter effect in use | Adds the effect stage (§8) to the still processing recipe. | 0x53739a5c |

The manual says Soft Monotone and HDR Tone cannot be selected in movie mode (GR IV manual p.94–95). It prints the mode as the movie-camera icon, which the PDF's text layer gives as the letter "B"; it is not bulb mode. The firmware agrees **[code]**: `ImageControlModel::IsValid` (0x533de144) makes Soft Monotone (0x0e) and HDR Tone (0x16) invalid while the model's flag at +0x1f is 1; that flag is set from the callers named `InitializeStillMovieMode`; the per-base default getters (§7.1) have no case for the two bases in that mode; and the firmware has no `MovieImageControl…` keys for them. A likely reason is that both depend on the DigitalFilter stage, which only the still recipe has: Soft Monotone for its forced Clarity (§8.2) and HDR Tone for its effect (§8.4) **[inferred]**. No exposure-side code tests the base, and no string gives a reason.

## 2. Pipeline

Order for a still on the GR IV **[code]** for the stage list, **[inferred]** for the exact hardware order inside the RAW-to-YCbCr block:

1. White balance gains on the camera RGB.
2. Colour matrix block 0: `M = B_base · A`, cut to 1/256, then the diagonal entry of each row is set so that the row sums to 1 and greys stay grey (`ColorMatrixTuning` 0x5393cc14). The diagonal is set, not the row rescaled, and Monotone, Soft Monotone and Hi-Contrast B&W skip this step: their rows stay as the product gives them, one of them summing to 257/256 **[emulated]** (the registers of all 28 base and toning variants, built this way, equal the emulated firmware's). `A` is the camera matrix, shared by all bases; `B_base` is the base's look matrix (§4.1).
3. Multi-axis colour correction for Standard, Positive Film and the two Cinema bases only (§4.5).
4. Tone: one gamma curve per R, G, B channel, applied to linear data, from the four tone sliders (§3). Some bases then apply an extra per-channel curve (§5).
5. Colour matrix block 1: saturation (§4.2) on colour bases, the black-and-white weights (§6.1) on Monotone, Soft Monotone and Hi-Contrast B&W. That this block comes after the tone curve is **[inferred]** from its separate register block (0x1120 onward).
6. RGB→YCbCr with BT.601 weights, combined with the hue rotation (§4.3).
7. YCbCr operation: toning offsets (§4.4, §6.2).
8. Edge enhancement (sharpness, §8.5) and noise reduction run inside the same hardware block.
9. JPEG-domain effects on the finished 8-bit YCbCr image, in this order: Shading, Clarity, Grain, HDR Tone (§8; GR IV 0x538ce51c, GR III 0x53680eac). Each is skipped when its value is 0.

No base or slider has noise-reduction tables of its own: the tables are chosen by capture mode, the High-ISO NR setting and ISO **[code]** (`LumaNrTuning`, `ColorLpfTuning` table getters 0x5394e86c, 0x5394e8ec). But High/Low Key, Contrast, Contrast (Shadow), Saturation and the base do shift the ISO index used to read those tables, by up to one stop (§8.6).

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

The exact integer algorithm is in `work/ic/notes/tone.md` §4.2 (about 40 lines), and every curve is precomputed in `work/ic/data/tone/` (each slider alone, and all 729 contrast × highlight × shadow combinations).

**Contrast (Shadow) +4 lightens the shadows** **[code] [emulated]**. The camera menu (slider table 0x53de5314), the Custom-slot blob parser (table 0x550a2930) and the maker note (table 0x53fd8118) all store UI value v as index v + 4, as for the other sliders, and the gamma receives 4 − index. Running the firmware's gamma setup with index 8 raises the 14-bit output by about 240 at 1/64 and 1/16 of full scale and leaves mid-grey and highlights unchanged; index 0 lowers it by about the same. So on every tone slider "+" makes that side of mid-grey brighter: Contrast +4 darkens the shadows and brightens the highlights, Highlight +4 brightens the highlights, and Shadow +4 brightens the shadows (less shadow contrast). The GR III behaves the same (0x536e84f8). No label or icon in the firmware gives the slider a direction.

HDR Tone and Mono HDR force all four sliders to neutral. Solarized Effect keeps Key and forces the three contrast sliders to neutral **[code]** (0x53939128).

The curve's mid-grey also tracks a per-shot gain that multiplies the white balance gains by the same amount, so a preview can ignore it **[inferred]**. Shadow Correction (`ToneControlTuning`, 0x53947230) is a separate brightness map driven by its own menu setting, not by Image Control. Retro alone writes four signed values into the ToneControl block: (−32, 0, 120, 0), or exactly half, (−16, 0, 60, 0), when Highlight Correction is in effect for the shot (the selecting flag comes from record +0xbb7, +0x38d34 or the setting +0x7e4, which the maker note records as `SetHighlightCorrect`) **[code]**. That block works on 12-bit data before the tone curve (its clip pairs are 4095/0, its luma weights 77/150/29), and the halving fits offsets added ahead of the curve and scaled with the exposure gain that Highlight Correction lowers **[inferred]**. Which channel or component each value acts on is not decidable from the firmware, because nothing reads them back after writing them.

## 4. Colour

### 4.1 Base look matrices

Each colour base is a 3×3 matrix `B` applied to linear RGB after the camera matrix; its rows sum to 1, so greys stay grey **[code]** (set table `.data` 0x55054800, indexed through `DAT_5407a53c[id]`; Q13 fixed point, 8192 = 1.0). Matrices act on column vectors (R, G, B). Effect relative to Standard is measured on linear test colours as BT.601 Cb/Cr hue shift and chroma ratio.

| Base | B (GR IV) | Relative to Standard |
|---|---|---|
| Standard | `[1.0664 0.0039 −0.0703; 0.0273 1.0117 −0.0391; −0.0234 0.0547 0.9688]` | — |
| Vivid | `[1.1218 −0.0070 −0.1149; −0.0022 1.1348 −0.1326; −0.0481 −0.0790 1.1271]` | chroma ×1.08–1.23, hue within ±5° |
| Positive Film | `[0.9688 0.3047 −0.2734; −0.0195 1.1758 −0.1562; −0.0703 0.3945 0.6758]` | chroma ×0.84–0.95; yellows and greens brighter (Y +0.13, +0.19) |
| Negative Film | `[1.0912 −0.2004 0.1092; 0.1522 0.7220 0.1257; 0.0070 0.2643 0.7288]` | chroma ×0.6–0.96; greens turn about 27° toward cyan and darken |
| Bleach Bypass, toning Off or Normal | `[0.5469 0.3445 0.1086; 0.1558 0.7135 0.1307; 0.1343 0.3202 0.5455]` | chroma ×0.38–0.42 |
| Bleach Bypass, Cool | `[0.4948 0.3391 0.1661; 0.1389 0.7261 0.1350; 0.0962 0.2999 0.6039]` | |
| Bleach Bypass, Warm | `[0.5837 0.3568 0.0595; 0.1891 0.6864 0.1245; 0.2277 0.3347 0.4376]` | |
| Retro | `[0.6182 0.3350 0.0469; 0.1395 0.8092 0.0513; 0.0582 0.3355 0.6063]` | chroma ×0.5, hue about +5° |
| Cinema (Yellow) | `[0.7656 0.2266 0.0078; 0.0078 0.9062 0.0859; 0.0000 0.2500 0.7500]` | chroma ×0.7, plus curves (§5) |
| Cinema (Green) | `[0.6758 0.3008 0.0234; 0.0234 0.7930 0.1836; −0.0078 0.2578 0.7500]` | chroma ×0.52–0.67, plus curves (§5) |
| HDR Tone with toning Off, Cross Processing | Standard's matrix | look comes from §5 and §8.4 |
| HDR Tone with toning B&W or Sepia | identity | the grey is made in block 1 (§6.1) **[emulated]** |
| Hard Monotone | every row `[0.7773 0.9297 −0.7070]` | a luminance mix that darkens blue (§6.1) |

Camera matrix `A` (GR IV): `[1.6418 −0.8031 0.1613; −0.1865 1.4833 −0.2968; 0.0635 −0.5145 1.4510]`. For a preview working on an sRGB photo, the base's change is `B_base · B_Standard⁻¹` applied in linear light.

GR III: Vivid, the three Bleach Bypass matrices, Retro, Negative Film and Hard Monotone are identical. Its Standard (also used by HDR Tone and Cross Processing) is `[0.9907 0.0907 −0.0814; 0.0018 1.0496 −0.0514; −0.0298 0.0662 0.9636]`, its Positive Film `[0.9773 0.2852 −0.2625; −0.0189 1.1692 −0.1503; −0.0651 0.3711 0.6940]`, and its camera matrix differs (different sensor).

### 4.2 Saturation

One global matrix per step, not per hue **[code]** (table pointer in the colour struct, 0x5501bd34; matrices 0x5408081c … 0x5408090c): `rgb' = s·rgb + (1 − s)·Y`, with Y ≈ BT.601 luma and **s = 1.1^step** (0.683 at −4, 0.909 at −1, 1.100 at +1, 1.465 at +4). That form alone is within 0.0038 of the stored entries. The rest is one fixed matrix `K`: the stored matrix of every step but 0 is the form applied after `K = [1.0020 −0.0002 −0.0018; 0.0011 0.9989 0.0000; 0.0029 −0.0029 1.0000]`, to 0.0002 an entry, and step 0 is exactly the identity **[consistency]** (`K` is the mean over the eight steps of the form's inverse times the stored matrix; it varies by 0.00016 between them). In YCbCr terms `K` adds 0.003 of Cr to the luma, scales Cb by 1.0009 and turns the chroma by 0.10°. Whether the GR III's matrices hold the same `K` was not checked; the 1.1 scaling is the same. On the GR IV the matrix sits in colour matrix block 1, which is after the tone curve **[inferred]** from its register block; on the GR III it is part of the linear matrix before the curve **[code]**.

### 4.3 Hue

A rotation of (Cb, Cr) after RGB→YCbCr, **2.46° per step**, ±9.9° at ±4 **[code]** (matrices 0x5408da1c … 0x5408db3c, Q13: +1 is `Cb' = Cb − 0.043·Cr`, `Cr' = 0.043·Cb + Cr`). Positive steps turn red toward yellow and blue toward magenta. Same on every colour base and on the GR III; monochrome bases use an identity table.

The stored matrices are whole numbers of 1/256: the cosine and sine of 2.46° × step times 256, rounded (256 and 11, 255 and 22, 254 and 33, 252 and 44 for steps 1 to 4), except that at ±4 Cr's own coefficient is 254 where the cosine gives 252, so that matrix is not a pure rotation **[code]**. `YCbCrMatrixTuning` (0x53942440) multiplies the step's matrix into the RGB→YCbCr matrix, which is the JFIF matrix rounded to 1/256 (`[77 150 29; −43 −85 128; 128 −107 −21]`), and rounds the product to 1/256 again: built this way, all 81 register values of the nine steps equal the emulated firmware's **[emulated]**. A JPEG viewer undoes the conversion with the exact JFIF matrix, so the rounding is in the photo. Against a model with the exact matrix and rotation, it moved saturated colours by up to 1.7 codes under Vivid and 3.5 with Vivid's sliders at their ends.

### 4.4 Toning on colour bases

Added to Cb and Cr in the YCbCr operation stage **[code] [emulated]** (registers 0x154c/0x154e, signed 10-bit, for the monochrome "set" pair; 0x1554/0x1556, signed 11-bit, for the "add" pair; offsets in the same register image as colour matrix block 1 at 0x1120). **The chroma there is 10-bit** (Y 0–1023, Cb/Cr ±512), so the values are a quarter of the size in 8-bit codes **[code]**: the gamma LUT outputs 10 bits, the RGB→YCbCr matrix applies no shift, and the same block's chroma gain curve has breakpoints at luma 56, 768 and 856, which only exist on a 10-bit axis. That curve suppresses chroma near black and white: the gain rises from 0 to 1 by Y = 56, stays at 1 to Y = 768, then falls to 0.84 at 856 and 0.27 at full scale (this piecewise reading of its start values and slopes is **[inferred]**). It is stored once per ISO step, but all 144 records are identical (0x540a6b54), so it is the same at every ISO and for every base **[code]**. Converted with the inverse of the firmware's matrix, in 8-bit RGB codes: Retro +4 adds R +22.3, G −4.6, B −35.5; Retro −4 adds R −8.3, G −1.9, B +31.9. Whether the toning is added before or after that chroma gain curve is **[unknown]**.

| Base, toning | (Cb, Cr) added |
|---|---|
| Retro −4 … +4 | Cb 72, 54, 36, 18, 0, −20, −40, −60, −80; Cr −24, −18, −12, −6, 0, 16, 32, 48, 64 (− cooler and bluer, + warmer and yellower) |
| Bleach Bypass Off / Normal / Cool / Warm | none / (+12, −36) / (+40, −60) / (−40, 0). Off uses Normal's matrix; Cool and Warm each have their own (§4.1) **[emulated]** |
| HDR Tone B&W / Sepia | chroma set to (0, 0) / (−36, +24), after a BT.601 conversion to grey |

Cinema toning (Low, Medium, High) is a curve blend, not an offset (§5). GR III: same values.

### 4.5 Multi-axis colour correction

`MultiAxialTuning` (0x5393d1a4, register writer 0x53942190) converts each pixel to Y, Cb, Cr with a BT.601 matrix of its own, divides the (Cb, Cr) plane into 12 hue areas and applies a 3×3 RGB matrix chosen by area. On the GR IV it is active for Standard, Positive Film, Cinema (Yellow) and Cinema (Green) (sets 0x54080aa0, 0x54081360, 0x540824b8, 0x5408338c); every other base, and every GR III base, uses a set whose enable field is 0 (GR IV 0x54081348) **[code]**.

The areas cover the whole hue circle, not only reds and skin tones. Each quadrant of the (Cb, Cr) plane has two thresholds, and the stored values 1298 and 750, 1448 and 843, 1298 and 750, 1205 and 843 are exactly 2048/(1 + tan θ) for θ = 30° and 60°, 22.5° and 55°, 30° and 60°, 35° and 55°, measured from the start of the quadrant. That puts the area boundaries at 0, 30, 60, 90, 112.5, 145, 180, 210, 240, 270, 305 and 325° of atan2(Cr, Cb), where magenta is at 52°, red 109°, yellow 171°, green 232°, cyan 289° and blue 351°. This reading is **[consistency]**: with it, the matrices of every two neighbouring areas give the same output on their shared boundary to within 0.005, in all four sets; moved 15° away they disagree by up to 0.15. So the block is a continuous map. Each matrix leaves greys and luma unchanged (rows sum to 1; luma changes by less than 0.002 per unit of chroma) and changes chroma and hue, by amounts that vary smoothly between the boundary axes. Chroma gain and hue shift in degrees on each boundary axis:

| Axis | Standard | Positive Film | Cinema (Yellow) | Cinema (Green) |
|---|---|---|---|---|
| 0° | 0.9865, +0.38 | 0.9936, +0.26 | 0.9907, +3.16 | 0.9474, +0.48 |
| 30° | 0.9713, −3.11 | 0.9599, −4.73 | 0.9768, −3.35 | 0.9991, +0.08 |
| 60° | 0.9961, −5.54 | 0.8010, −1.68 | 0.8557, −4.66 | 0.9568, −3.10 |
| 90° | 1.0175, +1.64 | 0.9192, −0.07 | 0.9774, +1.03 | 0.8792, −6.14 |
| 112.5° | 1.0191, −0.77 | 1.0363, −0.83 | 1.0820, −0.39 | 0.9417, −0.28 |
| 145° | 1.0949, −4.05 | 1.1429, −7.07 | 1.0635, −3.35 | 0.9811, +3.11 |
| 180° | 1.0179, −0.54 | 1.0941, −10.15 | 1.1123, −8.97 | 1.0276, +10.83 |
| 210° | 0.9786, −3.50 | 0.9790, −4.14 | 0.9857, −13.73 | 1.0557, +13.62 |
| 240° | 0.8953, −3.29 | 0.9808, +4.31 | 0.9188, −9.80 | 1.1585, +10.71 |
| 270° | 0.8871, −3.71 | 0.9454, +10.27 | 0.8050, −12.85 | 1.1214, +5.99 |
| 305° | 0.8999, −0.91 | 0.9574, +8.36 | 0.7630, +1.58 | 1.1150, −4.90 |
| 325° | 0.9826, +0.51 | 1.0007, +2.39 | 0.7996, +3.92 | 1.0208, −4.47 |

Standard itself therefore lowers chroma by about 10 % from green through cyan (240–305°) and raises orange (145°) by 10 %. Positive Film strengthens orange and yellow and turns them by 7–10°, and thins magenta by 20 %. Cinema (Yellow) cuts cyan and blue chroma by a fifth to a quarter and turns yellows and greens by 9–14°. Cinema (Green) strengthens greens and cyans by 12–16 % and turns yellows and greens by 11–14° the other way.

Each area has five matrices. Matrix *l* is matrix 0 times (1 − *l*/16), to within one unit of the 1/1024 scale, and the block interpolates between them along a 12-bit quantity with knots at 800, 1600, 2400 and 3200; the four values beside the knots, 328, 328, 328 and 293, are 2^18 divided by the knot spacing **[code]**. The firmware does not say which quantity that is (luminance or chroma magnitude), or whether the scaled matrix replaces the whole pixel or only its chroma: the code only copies tables to registers **[unknown]**. If it were luminance acting on the whole pixel, these four bases could not exceed 75 % of full scale ahead of the tone curve and so could not reach white. A Positive Film JPEG from a GR IV HDF has small flat areas at 254–255 in all three channels (one photo, firmware 1.11, 2026-11-07) **[observed]**, which speaks against that reading but is too little to settle it. A second strength curve in the same block is constant at 1.0 in every active set.

For a preview this is a second-order correction, but it is not confined to skin tones, and it matters most for the Cinema bases and when the preview starts from a Standard photo (§10).

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
- **Cross Processing** tone 0/1/2 selects the fixed triple **[code]** (0x5393a730 sets state 2/3/4, mapped to recipes by 0x5394d368). The firmware also has a random mode that permutes curves 0–2 and randomises saturation, hue, key, contrast and sharpness. It is unreachable in GR IV 1.20: state 1, the only one that maps to it, is never written, and no menu value or setting reaches it **[code]**; it is probably left over from the GR II's random Cross Processing **[inferred]**. The other sliders still apply on top. The GR III has the same 12 curves, the same presets and the same random code, with writers of the same structure.
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

Toning on the monochrome bases is an enum (0 Off, 1 Sepia, 2 Red, 3 Green, 4 Blue, 5 Purple), not a strength scale. A configuration bit that only the monochrome sets turn on makes the YCbCr operation **set** the chroma to a fixed (Cb, Cr) pair, the same at every brightness **[code]** (0x539450f0). Register values on the 10-bit chroma scale of §4.4 (divide by 4 for 8-bit codes):

| | Off | Sepia | Red | Green | Blue | Purple |
|---|---|---|---|---|---|---|
| GR IV colour bodies and GR III: Cb | 0 | −24 | −8 | 0 | 20 | 16 |
| Cr | 0 | 16 | 28 | −24 | −8 | 4 |
| GR IV Monochrome bases: Cb | 0 | −12 | −4 | 0 | 10 | 8 |
| Cr | 0 | 8 | 14 | −4 | −4 | 2 |

The GR IV Monochrome's toning is half strength, and its Green much weaker. In 8-bit RGB codes, Sepia on the colour bodies adds about R +5.6, G −0.8, B −10.7 to the grey, and HDR Tone Sepia R +8.4, G −1.2, B −16.0.

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
| Solarized Effect (0x20) | the solarization curve chosen by the Solarization Type (1–3 in a blob, stored as 0–2 in record 0x7ba); contrast sliders and Shading forced neutral; lens vignetting correction off (§1) |

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
| HDR Tone | Standard's with toning Off; identity with B&W or Sepia (BT.601 grey in block 1) | — | set (B&W/Sepia) | HDR effect, tone sliders forced neutral |
| Cinema (Yellow), Cinema (Green) | yes | R/G/B, blended by toning | — | multi-axis |
| Cross Processing | Standard's | R/G/B preset by Color Tone | — | CTE white balance |
| Monotone family and Monochrome bases | §6 | §5 where listed | set (enum) | §6.3 |

The sliders each body offers are the same mechanism on every base that has them: the four tone sliders (§3), saturation (§4.2), hue (§4.3), sharpness (§8.5), and the four JPEG-domain effects (§8).

### 7.1 Default values of each base

A base is more than its tables: each has its own default slider values, and those are what the camera's sliders show for it. `ImageControlModel`'s `GetDefaultValue<Parameter>` functions (0x533d053c–0x533ddc54) read them from the settings' initial-value structure, which a static initialiser fills with constants (`UserData/UserDataInitValue.cpp`, 0x53546c20; one copy per project type, chosen at 0x53546b8c). The table was made by running that initialiser in the emulator and reading, for each base, the byte each getter reads **[emulated]**; the getters' offsets were read from their decompiled switch statements, so a cell is only as sure as that reading. Values are the steps the camera shows (stored value − 4 for the ±4 sliders, the stored value for the others); a dash means the base has no such parameter.

| Base | Sat. | Hue | Key | Contrast | Highlight | Shadow | Sharpness | Shading | Clarity | Toning | Grain | Size | Intensity |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Standard | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | – | – | – | – |
| Vivid | 0 | 0 | 0 | +1 | 0 | 0 | +1 | 0 | 0 | – | – | – | – |
| Monotone | – | – | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 1 |
| Soft Monotone | – | – | +1 | −2 | 0 | 0 | −1 | 0 | – | 0 | 0 | 1 | 1 |
| Hard Monotone | – | – | −1 | +2 | 0 | −2 | +1 | 0 | 0 | 0 | 0 | 1 | 1 |
| Hi-Contrast B&W | – | – | 0 | 0 | 0 | 0 | +1 | 0 | 0 | 0 | 1 | 1 | 2 |
| Positive Film | 0 | 0 | −1 | +3 | −1 | −2 | 0 | 0 | 0 | – | 0 | 1 | 1 |
| Negative Film | 0 | 0 | +1 | +1 | 0 | −1 | 0 | 0 | 0 | – | 0 | 1 | 1 |
| Cinema (Yellow) | 0 | 0 | −1 | +3 | 0 | −2 | −3 | 0 | 0 | 1 | 0 | 1 | 1 |
| Cinema (Green) | −2 | 0 | 0 | +1 | 0 | −3 | −3 | 0 | 0 | 1 | 0 | 1 | 1 |
| Bleach Bypass | 0 | 0 | +4 | +4 | +4 | 0 | 0 | 0 | 0 | 1 | – | – | – |
| Retro | 0 | 0 | +2 | −3 | 0 | 0 | −3 | −3 | 0 | +1 | – | – | – |
| HDR Tone | +2 | 0 | – | – | – | – | – | – | – | 0 | – | – | – |
| Cross Processing | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | – | – | – |

- Toning is each base's own toning parameter: Cinema 1 is Medium, Bleach Bypass 1 is Normal, Retro is a step, Cross Processing 0 is the Basic colour tone. Grain size 1 and intensity 1 are Medium; Hi-Contrast B&W has grain on at High.
- HDR Tone Level defaults to 2 (Medium), and Filter Effect to Off on the three bases that have it.
- The GR IV Monochrome bases repeat the colour bodies' monochrome bases: Standard as Monotone, Soft as Soft Monotone (key +1, contrast −2, sharpness −1), High Contrast as Hi-Contrast B&W (sharpness +1, grain on at High), Grainy and Solid all at 0, with Grainy's grain on only in the Monochrome body's copy of the structure (project type 4).
- The same values hold in still and movie mode, for the bases movie mode has (§1).

So Positive Film as the camera ships it is the Positive Film tables rendered at Key −1, Contrast +3, Highlight −1 and Shadow −2, and Bleach Bypass at Key, Contrast and Highlight all +4. A base previewed with every slider at 0 is not what that base looks like on a camera at its defaults. Not established: that the camera applies these values when a base is first chosen in the menu, rather than only when the settings are reset **[unknown]**.

## 8. Detail effects

Shading, Clarity, Grain and HDR Tone run in the DigitalFilter module on the developed 8-bit YCbCr image (outputs clip to 0–255, chroma offset 128), in that order, each skipped at 0 **[code]**. They are computed by the IIP image-processing hardware (mapped around 0x2888xxxx; units for loading, a small programmable ALU called GPC, colour-space matrix, blend, spatial filter, LUT, store and resize), which the firmware programs with parameter blocks; nothing on the ARM side repeats the arithmetic. The formulas below come from running the firmware's own parameter builders in an emulator, from its printer for GPC programs (0x538c23f8, which renders them as expressions), and from the one reading of each unit under which a neutral setting is the identity. Sharpness is an ISP stage.

### 8.1 Shading

A radial gain about the centre of the final crop (GR IV 0x538c8c3c, GR III 0x5367b630, identical) **[code]**. The strength per step is a Q12 constant `c`, the gain at the corner:

| Step | −4 | −3 | −2 | −1 | +1 | +2 | +3 | +4 |
|---|---|---|---|---|---|---|---|---|
| c | 0.25 | 0.354 | 0.5 | 0.707 | 1.26 | 1.587 | 2.0 | 2.52 |
| EV at the corner | −2 | −1.5 | −1 | −0.5 | +⅓ | +⅔ | +1 | +4/3 |

- Radius: ρ² = r² / (half-diagonal · f)², with f = 1.0 for 3:2, 0.9245 for 4:3, 0.9547 for 16:9 and 0.7845 for 1:1, divided by the digital zoom factor, so ρ = 1 at the corner of the saved frame **[code]**.
- Transfer: the GPC program forms dx² + dy² and the colour matrix produces `min(255, c·Y)` and an alpha of `255·min(ρ², 1)` **[emulated]** (the firmware's own builders and GPC printer, run in the emulator; the hardware arithmetic itself was not run). The blend unit's operation is undocumented; the only reading under which step 0 is the identity and the radial alpha is used is an alpha blend, `Y' = (α·min(255, c·Y) + (255 − α)·Y)/255 ≈ Y · (1 + (c − 1)·min(ρ², 1))` **[consistency]**, with the operand order fixed by the live-view tables below. So the gain rises linearly with ρ² from 1 at the centre to c at the corner (there is no lookup table in the chain, so an exponential falloff is impossible), brightened pixels clip at 255, and **chroma is not changed** **[code]**. Whether the blend divides by 255 or 256 is not decidable from the firmware (at most 1/255).
- Negative steps darken the corners. Live view has no DigitalFilter stage and shows the slider through the ISP's own shading unit instead **[code]**: the live-view process (0x536596d4, called from `LiveViewProcess` 0x53661920) reads the Shading value from its copy of the settings and passes it as the step to `XoyShadingCoordinator` (0x5394ed38, plain C), which fills separate X and Y gain tables, parabolic along each axis, from nine per-step constants (0x54211614) and the aspect ratio. The tables give corner-to-centre ratios of 0.250, 0.363, 0.516, 0.721, 1.24, 1.53, 1.90 and 2.36 for the eight steps, close to the still values, so live view approximates the still result.
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

- **GR IV, all bases except Mono Grainy** ("Granulation", 0x538c9854) **[code]**: fresh random noise each shot (xorshift128 reseeded from a clock), no stored grain texture. Size is a blur of the noise with a symmetric kernel that sums to 1 (no darkening): Small is 3 × 3 (corner 7, edge 28, centre 116, /256); Medium and Large are 5 × 5, with the outer ring coming from a second coefficient set **[emulated]**:

  | Medium (/256) | Large (/256) |
  |---|---|
  | 0 1 3 1 0 / 1 14 29 14 1 / 3 29 64 29 3 / 1 14 29 14 1 / 0 1 3 1 0 | 1 3 6 3 1 / 3 15 25 15 3 / 6 25 44 25 6 / 3 15 25 15 3 / 1 3 6 3 1 |

  Luma amplitude A by strength and size: Low 8/10/13, Medium 15/20/25, High 30/40/50 on colour bases, doubled on monochrome bases; colour bases also get chroma noise of 1–12 with its own noise plane **[emulated]**. The blend is programmed with the same operation as Shading's, with the filtered noise *n* as the alpha between an upper and a lower lookup table **[code]**; under the blend reading of §8.1 that gives `Y' = Y + min(Y, 255 − Y, A)·(2n/255 − 1)` **[consistency]**.
- **GR IV Mono Grainy with Grain on** ("Rough", 0x538c6898) **[code]**: the Clarity pyramid with fixed strong gains (×2, ×2, ×3, ×1.4, ×1.3, ×1 on six levels) plus noise added to one octave chosen by Size (1, 2 or 4 pixel grain) and scaled by Intensity. So Grainy with grain on also raises fine and mid-scale contrast.
- **GR III** (0x5367ae2c): one setting (High, Mid, Low → scale 1, ½, ¼), luma only, no blur, with an amplitude that depends on brightness: about ±3 at black, ±33 at Y = 155, back to ±3 at white.

### 8.4 HDR Tone

A single-frame multi-scale local tone map on half-resolution Y (GR IV 0x538cd7e8, GR III 0x53680178, identical code and tables) **[code]**. The coefficients and lookup tables per level are **[emulated]**; the per-level formula `L' = a·G + b·Z + sign(d)·LUT(|d|)` with `d = Z − S`, where G is the level, Z its 3 × 3 prefiltered copy ([4 28 4; 28 128 28; 4 28 4]/256) and S the next coarser level upsampled and blurred, is **[consistency]**: these are the only roles under which the levels with a = 1, b = −1 reconstruct exactly. The lookup for fine and mid levels pushes small differences up to a constant size (strong boost of small detail); for the coarse levels (≥ about 256 pixels of the half-size image) it compresses contrast to about 0.35 and then 0.18. Level 0 uses a = 0.1975 (1.2 − 1.0024), which subtracts the input, so the rebuilt pyramid is the correction map D = HDR(Y) − Y **[consistency]**. The correction is added to Y only: `Y' = Y + s·up2(D)/256` with s = 4, 8, 16 for HDR Tone Level Low, Medium, High **[code]**. D is most likely in units of 1/16 of an 8-bit code (pyramid clips ±8191, D clipped to ±4095), which makes the strength 0.25, 0.5 and 1.0 of the full correction **[inferred]**; the alternative scale would make the effect only a few percent and is unlikely. HDR Tone also forces key, contrast, highlight, shadow, sharpness, shading and clarity to neutral.

### 8.5 Sharpness

Scales the ISP's edge-enhancement curves by a gain of `(step + 4)/4` (table 0, 32, …, 256 at GR IV 0x54091b0c, identical on the GR III) **[code]**: −4 turns edge enhancement off, +4 doubles it. There are three enhancers for high, middle and low frequencies; the first two use zero-sum high-pass kernels (centre 896 with taps −128 and −96, and centre 960 with taps −48 and −32), the same on the GR III. The curves themselves depend on ISO: at base ISO the enhancement ignores the smallest edges (coring), peaks at bin 12 and falls to zero at bin 79, so large edges get none (halo control); at high ISO the coring and the peak move to larger edges. How edge size maps to bins is not decidable from the firmware: it is set by two register fields (0x1223 = 4 and 0x1260 = 16) that are the same in every mode and that no code interprets; a similar curve in the same unit suggests bin = |edge| >> 3 on a 10-bit scale **[inferred]**. A preview therefore has to set the unsharp-mask amount by eye. A JPEG already carries the neutral sharpening, so a preview made from one should apply only the difference from neutral.

In the normal still record only the high and low enhancers are switched on. The middle one is enabled for Mono Solid alone, whose record turns on all three **[code]** (enable bytes of the records at 0x54091798 and 0x54091858). Every other base uses the same record, so bases differ in sharpening only through their default Sharpness value (§7.1).

### 8.6 Side effects on noise reduction

No base and no detail slider changes noise reduction, but three tone sliders, Saturation and the base shift the index with which the per-ISO tables are read **[code] [emulated]**. The index has 8 steps per ISO stop. The function that turns the shot's exposure data into table indices (0x5393a730, arithmetic at 0x5393a84c–0x5393a8b0) adds two terms to it, from the stored values 0..8:

- `2·key + trunc((shadow − 2·contrast + 4)/4) − 8`, used by luma noise reduction (`LumaNrTuning` 0x539421f0), the colour low-pass filter (0x53942b64) and the two filter units that follow the RGB-to-YCbCr block (0x53948fd8, 0x53948cb0; `m_SuppreFilterTuning` and `m_ReduceFilterTuning`, what they filter is **[unknown]**). Each High/Low Key step up reads the tables a quarter stop higher, so key +4 gets the noise reduction of one stop more ISO and key −4 of one stop less; Contrast +4 lowers the index by two steps and Contrast (Shadow) +4 raises it by one.
- `saturation − 4` plus a per-base offset (table 0x5407a560: +1 for Vivid and Positive Film, −1 for Cinema (Green) and Retro, −2 for Bleach Bypass, 0 for the other colour and monochrome bases **[emulated]**), used by the colour low-pass filter and the two filter units only. Saturation ±4 is therefore four steps, half a stop.

Running the tuning code agrees with it **[emulated]**: the index values it computes follow the two formulas for all 729 combinations of key, contrast and shadow and for every saturation value; key −4 and key +4 produce the filter units' register values of one ISO stop lower and higher, and Saturation −4 and +4 those of half a stop lower and higher; at high ISO key also changes the luma noise-reduction registers. Neighbouring records often repeat, so equal registers alone do not measure a shift; the sizes above come from the index arithmetic. The colour low-pass filter's 144 records are identical, so its index has no effect in this firmware. The reason is presumably that a brighter or more saturated rendering shows more noise **[inferred]**. For a preview the effect is negligible.

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

GR Lab previews a look on a photo the camera already developed, normally a Standard JPEG with every slider at 0. A faithful preview therefore undoes the photo's own rendering and applies the target look's. A photo taken with another base at its defaults was not rendered with every slider at 0 (§7.1), so the values to undo are the ones the photo records, not zeros. The camera's tone curve already produces sRGB-encoded values (§3), so the JPEG is undone with the inverse of that curve, not with the sRGB decoding. In order, per pixel of the encoded R, G, B:

1. Back to the camera's linear values: `lin = G_neutral⁻¹(encoded)` per channel, where `G_neutral` is the neutral tone curve (§3). This ignores the neutral saturation and hue, which are identity, and the Standard multi-axis correction (§4.5), which is not: it changed chroma by up to 11 % and hue by up to 5.5° in the photo, and a target base without the correction (Vivid, Negative Film, Bleach Bypass, Retro and the rest) strictly needs it undone.
2. Colour, in that linear domain: `lin' = B_target · B_Standard⁻¹ · lin` (§4.1). On the GR III the saturation matrix belongs here too (§4.2).
3. Tone: `enc = G_target(lin')` per channel, the curve for the look's key, contrast, highlight and shadow (§3). With a Standard target and all four at 0, steps 1–3 give back the photo.
4. Per-channel curve for the bases in §5, with the cinema blend.
5. In the encoded domain: on the GR IV, the saturation matrix of the step (§4.2) or the §6.1 black-and-white weights (this position is **[inferred]**, §2); then the camera's rounded RGB→YCbCr matrix with the hue rotation of 2.46° per step (§4.3), the toning offsets on its 10-bit chroma (§4.4, §6.2), and back to RGB with the exact JFIF matrix, as a JPEG viewer does.
6. Shading, Clarity, Grain, HDR Tone (§8) on the encoded 8-bit Y, scaled to the preview size; sharpness as an unsharp-mask difference.

Steps 1–5 are a per-pixel colour transform: one 3D lookup table per pair of looks (the photo's and the target) holds them at its grid points and blends in between (how closely, §10.1), and for bases without a per-channel curve (§5) or multi-axis correction (§4.5) a 1D curve per channel before and after one 3×3 matrix reproduces them exactly. A 4 × 5 colour matrix, which GR Lab's preview used until 2026-11-09, acts linearly on encoded values, so of all this it reproduces exactly only step 5 (saturation, hue, toning offsets). It can only approximate the base matrices, because they apply between two nonlinear curves, and it cannot reproduce the tone sliders or the per-channel curves (Cinema, Cross Processing, Hi-Contrast B&W, Solarized). The spatial effects of step 6 need image filters.

Undoing the photo's own rendering (step 1, and the values of §7.1) is best effort. Highlights the tone curve clipped (§3) stay clipped, a monochrome photo has no colour to recover (§6.1) and the Solarized curves are not one-to-one (§5). Of what a look does to the picture as a whole (§8), Grain and HDR Tone cannot be taken out again, and Shading and Clarity only where they did not clip (§10.2). A preview is therefore only as good as its source photo; a Standard photo with every slider at 0 is the best one.

### 10.1 What GR Lab implements

All of this is GR Lab's choice **[design]**, in `packages/gr_camera/lib/src/looks/render/`. Steps 1–5 are implemented for the GR IV family (since 2026-11-09), and so is step 6 apart from Sharpness (since 2026-11-10, §10.2).

- **Two halves per camera generation** (`LookRenderer`): a decoder from a photo's encoded R, G, B back to scene-linear RGB (the white-balanced RGB after the camera matrix `A`, §4.1), and an encoder from there to the encoded R, G, B of a look. `Gr4LookRenderer` is the GR IV family's, after firmware 1.20, and is the only one: every camera gets it for now, the GR III family included, although its colour differs (§9). A second generation gets its own implementation next to it rather than conditions inside this one; only arithmetic that knows nothing about cameras is shared (`render_maths.dart`).
- **The decoder undoes the photo's whole look**, not only the neutral tone curve of step 1: its toning, hue rotation and saturation, its per-channel curve, its tone curve for its own four slider values, its multi-axis correction and its base matrix, in reverse order. A value above the top of the look's curve, which undoing a toning leaves in the highlights, is taken as the curve's top, so it decodes to the point where the look clipped. A look saved from a photo keeps the look the photo was developed with (`SavedLook.photoData`), which stays as it was when the look is edited. A photo whose look is not known (a look saved before GR Lab kept it, and the bundled sample photo) is taken to be Standard with every adjustment at 0.
- **How well a photo suits a target look** (`LookSourceFit`) decides what the editor shows. *Good*: a colour photo whose look lost little. *Rough*, with a note: the photo's look used Grain, Shading or Clarity, is Bleach Bypass or Cross Processing, has saturation under 0.8 (−3 or −4) or curves that stop rising before nine tenths of the linear range, or the photo is black-and-white and so is the target. The neutral tone curve reaches white at 0.961 of the range (§3). High/Low Key +4 alone brings that to 0.860, and smaller steps do it together (+2 with Contrast +4, or +3 with Contrast (Highlight) +4: 0.891), while High/Low Key +3 alone (0.914) and Contrast +4 with Contrast (Highlight) +4 (0.906) stay good. *Unknown*, with a note: the photo's look was not kept. *Unusable*, where the sample photo stands in, with a note: a black-and-white photo under a colour look, or a photo developed with HDR Tone, Solarized Effect or a base GR Lab does not know. A target base GR Lab does not know (Palette) is another matter: the preview then shows the photo unchanged, without a note. Where these lines fall is a judgment, not a measurement.
- **A black-and-white photo** is decoded to the grey scene that would give each pixel's luma, which gives another black-and-white look its tones and nothing else. The luma a look gives a grey scene includes its black-and-white mix (§6.1): filter values need not add up to 100 % ([protocol/image-control.md §4](protocol/image-control.md)), and a filter of 200/0/0 doubles the photo's brightness, which the decoder takes out again. A photo whose brightest grey is a quarter of full scale or less, as with filter values that add up to 25 % or less, is too dark to undo and counts as unusable. The bases of the GR IV Monochrome are shown on a colour photo as the luma of its developed channels: there is no model of that body's sensor.
- **Values a camera would not send**: a slider value outside −4 to +4 renders as the nearest step, a choice outside its list as the nearest choice, and a parameter the look lacks as 0 (so a Bleach Bypass look without its toning renders as Off, though a new look starts on Normal). Filter values are used as they are, also beyond the ±200 % the camera offers.
- **The multi-axis correction** (§4.5) is modelled as a chroma gain and a hue turn on each of the 12 axes between the hue areas, linear in between. Fitted to the camera's 12 matrices per base, this reproduces them to 0.0013 of full scale. The level scaling of the block, whose input quantity is unknown (§4.5), is left out: the preview applies the correction at full strength at every level.
- **Left out as well**: the gain curve that fades chroma near black and white (§4.4), Retro's ToneControl values (§3) and Cross Processing's change to the CTE white balance (§1). The chroma gain curve is the same for every base and is already in the photo. If the camera adds the toning after that curve, leaving the curve out is wrong only where a look moves a pixel's luma into or out of the ranges it fades (under 56 or over 768 of 1023): the preview then keeps the colour the photo had there. If the toning comes first, which §4.4 leaves open, the camera fades the toning near white as well (to 0.27 at full scale), and the preview tones highlights too strongly and takes too much out of them when it undoes a toned photo.
- **The table**: `LookRerender` works the decoder out once per photo over a grid of 49 steps per channel and runs each target look's encoder over the result, giving a 49³ table (`LookLut`), an image of 2401 by 49 pixels. The app draws the photo through it with one fragment shader that blends the eight entries around each pixel's colour and knows nothing about cameras (`app/shaders/look_lut.frag`, `app/lib/src/looks/look_preview.dart`). Between its entries a table is only as good as straight lines are, and a look bends most where a channel clips. Blended as the shader does and compared with the renderer's own answer, over 140,608 colours (every fifth code of each channel) for nine pairs of looks (2026-11-09): 0.13 to 0.30 codes off on average, the worst hundredth of the colours by 2.3 codes or more in the worst pair (Positive Film at its defaults back to Standard), and the worst colour by 9.1, a saturated green with a channel at 255. With the 33 steps used at first those two figures were 4.3 and 16.7. 65 steps give 1.6 and 8.4, but an image 4225 pixels wide, more than the 4096 some phones' graphics allow **[inferred]**.
- **What the shader draws** was checked on 2026-11-09 on an Android 16 emulator (Flutter's Impeller on OpenGL ES) and an iOS 26.5 simulator, first with the 33-step table and again with the 49-step one: screenshots of the sample photo under Standard, Vivid and Monotone, and on iOS also Vivid with Contrast +4 and High/Low Key −4 and Positive Film, against the reference model below applied to the unaltered photo's pixels in the same screenshot. Averaged over blocks of 12 to 14 pixels the two differ by 0.3 of an 8-bit code or less on average and by 1.8 at most with the 49-step table. No phone was tested.

**Fitted curves.** The camera's curves are Ricoh's firmware data and are not shipped. GR Lab uses curves of its own fitted to them (`gr4_curves.dart`): each 256-entry table becomes a monotone cubic through a few knots, placed where the fit is worst and their values found by least squares over the whole table, and the tone-curve generator's arithmetic (§3) is written out in GR Lab's code (`gr4_tone.dart`). Measured against the GR IV 1.20 tables (`work/ic-indep/scratch/render/fit_all.py`):

| Curves | Knots | Error, in 8-bit codes |
|---|---|---|
| 12 base tone tables | 153 in place of 3072 values, 9 to 16 each | each table within 0.41; the tone curves generated for all 6561 slider combinations within 0.37 of the exact ones, 0.07 on average. The camera has 15: the three for mid-grey at linear 128 are reached by no High/Low Key step and are left out |
| Hi-Contrast B&W, Cinema, Grainy, Solid, Solarized curves (12) | 8 to 40 each | within 0.4, except Cinema (Green) blue, 0.73 |
| Cross Processing curves (9) | 9 to 32 each | within 1.0 |

The Cross Processing tables are not smooth, and those of Cinema (Green) red and blue and Cinema (Yellow) blue fall over their first few entries before they rise; the fits are to the nearest rising sequence, so they smooth this away. A fit that passes through table entries instead needs 880 values for the per-channel curves, 67 to 82 for each Cross Processing table.

The tests in `packages/gr_camera/test/looks/render/` compare the renderer with a reference model that uses the exact tables and registers (`work/ic-indep/scratch/render/reference.py`), over 55 pairs of looks and 27 colours, eight of them with channels at 0 or 255, where curves clip. Every colour is within 2.5 codes; the worst is 2.0, a near-black grey from Cinema (Green) at its defaults to Retro. The Hue slider alone is within 0.2. That measures the fits and GR Lab's arithmetic against the firmware model, not against a camera: no preview has been compared with a camera's photo yet (§11).

An independent audit of the renderer against these notes (2026-11-09, a second agent with the same reference model, 169 colours and 84 pairs) found the pipeline, constants and tables as described, and three shortcomings. Two had escaped the first tests, none of whose colours had a channel above 247: a value above a curve's top decoded to full scale instead of the clip point (highlights 5 to 11 codes off for a Standard photo, 20 to 120 for toned or strongly clipped ones), and the YCbCr matrix, hue rotation and saturation matrices were the ideal ones, not the camera's rounded ones (§4.2, §4.3; up to 5.4 codes for a Standard photo, 8.4 between Negative Film and Positive Film). The third was the 33-step table, whose blending error had not been measured. All three are corrected in what is described above.

### 10.2 The detail effects in the preview

The preview shows Shading, Clarity, Grain and HDR Tone's tone mapping for the GR IV family (`gr4/gr4_effects.dart`; the resizing and filtering that know nothing about cameras are in `render_planes.dart`). All of it is **[design]**: how to show at a preview's size what the camera does to its full frame. What the camera itself does is §8, and what in §8 no camera has confirmed is listed in §11.1.

These effects depend on where a pixel is or on the pixels around it, so the colour table cannot hold them. `LookRerender.render` works on a copy of the photo in JPEG luma and chroma: it takes the photo's own effects out (`LookRenderer.unfilter`), puts every pixel through the colour table of §10.1, and applies the target look's effects (`LookRenderer.filter`) in the camera's order, Shading, Clarity, Grain, HDR Tone, limiting each stage to 0–255 as the camera does. The copy is an eighth of the GR IV's frame on its long side, 774 pixels (`LookRenderer.pictureLongSide`). The app does this away from the UI's thread when the look, or the photo's own, has such an effect (`LookRerender.filters`) and shows the result in place of the shader's picture, so the picture can be a slider change behind; a look of colour and tone alone is still drawn by the shader (`look_preview.dart`).

- **A preview is a level of the camera's pyramids.** The camera works on its full frame, 6192 pixels wide. A picture 1/2ⁿ of that size is taken as level n of the Clarity pyramid and level n − 1 of HDR Tone's, which starts at half size (the nearest n for sizes in between), so the picture's finest band is the camera's band n. The bands finer than the picture are not there to change. One of them still shows for Clarity and Grainy's contrast: averaging band n − 1 down by two leaves a trace at the picture's size, the picture's difference from itself doubled and halved again (a blur of 1, 6, 1 over 8 each way), and that trace gets band n − 1's gain. A photo that was cropped, or saved at a smaller size, is taken to be the full frame too: the copy does not say what it was cut from.
- **Shading** is §8.1's formula with ρ = 1 at the picture's corners. It is smooth, so the picture's size does not matter.
- **Clarity** uses gains of `2^(e·step)` with e = 0.08 for band 1, 0.1 for bands 2–5, 0.08 for band 6 and 0.07 for band 7, which follows the camera's table (§8.2) to 0.0005, on a pyramid that halves by 2 × 2 averages and doubles with straight lines.
- **Grain** is not drawn the camera's way, with noise per frame pixel that is then blurred: the picture gets, per pixel, noise with the deviation the camera's would have left once the frame is averaged down to the picture. The camera's noise is uniform, so on the frame its deviation is `min(Y, 255 − Y, A)/√3` times what the Size's blur leaves (0.506, 0.356, 0.291 for Small, Medium, Large: the root of the sum of the squared kernel weights of §8.3). Averaging s frame pixels each way leaves `(s − e)/s²` of the unblurred deviation, with e = 0.55, 0.83, 1.03 for the three sizes (how far apart, on average, two pixels that share noise are). At an eighth of the frame, Intensity High gives 2.0, 2.6 and 3.1 codes on a colour base for the three sizes, against 8.8, 8.2 and 8.4 on the frame: a preview shows grain far fainter than the photo at full size does, and larger grain more than smaller. Cb and Cr get noise of their own, thinned near grey as the camera's table does. Grainy gets its band gains (×2, ×2, ×3, ×1.4, ×1.3; at an eighth only the trace of the third and the last two) and the noise of its three octaves averaged down the same way. The noise is the same for every render, so the preview does not flicker as a slider moves; the camera draws new noise for every shot.
- **Grain already in the photo** stays in it: nothing can take it out. A target look then gets only the grain it has beyond the photo's (deviations add as squares), and none when the photo has as much or more.
- **HDR Tone** is §8.4's per-level formula from the level the picture is, with curves of GR Lab's own in place of the camera's three lookup tables: straight lines through seven points for each of the two finer tables and through three for the coarse one, fitted by least squares to within 0.2 of a code. The table of the camera's two finest levels differs from the next five's only for differences of a code or less; a picture at an eighth of the frame has no such levels, so the preview never uses that curve. The curves turn a difference of a code and a half between a level and the next into 17 codes, so the result depends heavily on the last code of the picture it is given: the same photo made smaller by two different resizing filters, 1.0 code apart per pixel on average, came out 10.7 codes apart under HDR Tone High and 3.4 under Low (2026-11-10, §10.2's device check). Whether the camera's own result is that sensitive is not known (§11.1, rows 12 and 13).
- **Undoing a photo's own effects**: Shading by the inverse gain, where a pixel the gain clipped at white comes back as the darkest value that would have clipped; Clarity and Grainy's contrast by the inverse band gains, which is not quite the inverse of the whole filter (within 1 code for Clarity and 3 for Grainy on the test picture). Shading that darkens and Clarity therefore no longer make a photo a rough source (§10.1); Grain and Shading that brightens still do, and an HDR Tone photo stays unusable.
- **Sharpness is left out.** The camera sharpens edges one to a few pixels wide, which a picture at an eighth of the frame no longer holds: simulated with the high-frequency enhancer under §8.5's inferred bin scale, Sharpness −4 and +4 change the frame by 0.1 of a code on average and the picture at an eighth by 0.03 (0.5 for the worst hundredth).

How much a picture at an eighth loses, measured on one 26-megapixel photo (2026-11-10, `work/ic-indep/scratch/effects/`): the effect worked on the picture, against the same model worked on the full frame and then averaged down by 8. This measures the scaling, not the model:

| Effect | Size of the effect, mean (worst hundredth) | Off by, mean (worst hundredth) |
|---|---|---|
| Shading −4 | 13.7 (72.5) | 0.04 (0.2) |
| Shading +4 | 17.9 (89.3) | 0.2 (5.5), where neighbouring frame pixels clip and the picture's do not |
| Clarity −4 | 3.6 (23.0) | 0.07 (0.8) |
| Clarity +4 | 4.4 (24.4) | 0.2 (1.7) |
| Grainy's contrast | 4.0 (29.9) | 0.8 (13.1): three of its five bands are finer than the picture |
| HDR Tone Low | 7.6 (19.2) | 1.5 (7.1) |
| HDR Tone High | 24.1 (76.8) | 4.4 (25.9); 2.6 (15.4) once averaged over 4 × 4 pixels: HDR Tone raises detail finer than the picture, which the picture cannot show |

The tests in `packages/gr_camera/test/looks/render/gr4_effects_test.dart` compare the Dart code with a model that uses the camera's exact tables (`work/ic-indep/scratch/effects/effects_ref.py`) on a small test picture taken as the frame itself, an eighth and a 64th of it: Shading within 0.001 of a code, Clarity 0.03, Grainy's contrast 0.02, HDR Tone 0.3, and the grain's deviation within 1 %. That model is this section's reading of §8 in floating point; it is not the camera.

What the app draws was checked on 2026-11-10 against the same Dart code run off the device on the same photo. On an iOS 26.5 simulator, a throwaway screen drew the sample photo pixel for pixel under Shading −4, Clarity +4, Monotone with Grain Large and High, and HDR Tone Low and High: every pixel was the renderer's. On an Android 16 emulator (Impeller on OpenGL ES), in the editor in demo mode, the picture is not drawn at its own size, so 14-pixel blocks were compared: Shading −4, −2 and +4, Clarity ±4 and Monotone with grain differ by 0.2 of a code on average, as the photo without a look does, and HDR Tone Low, Medium and High by 0.3, 0.5 and 0.8, because the emulator's copy of the photo and the one made for the comparison were not resized by the same filter. No phone was tested.

## 11. Open questions

Settled from the firmware since the first version of these notes: the sign of Contrast (Shadow) (§3), the toning scale (§4.4), the grain kernels (§8.3), Cross Processing's random mode (unreachable, §5), why Soft Monotone and HDR Tone are missing in movie mode (§1), the hue areas of the multi-axis correction (§4.5), the live-view Shading path (§8.1) and the defaults of each base (§7.1). The Shading falloff and sign (§8.1), the grain blend (§8.3) and the HDR Tone plane roles (§8.4) are settled only as far as **[consistency]** goes: no hardware run or photo confirms them, and the tests below would. What remains, and what would settle it:

| Question | Why the firmware cannot settle it | Test |
|---|---|---|
| Shading, grain blend and HDR Tone formulas (§8.1, §8.3, §8.4) | the blend and pyramid units are undocumented hardware; the formulas are the only readings consistent with the firmware's settings | Shading −4 and +4 on a flat, evenly lit wall; Grain and HDR Tone at each level against Standard |
| HDR Tone strength scale (§8.4) | the scale of the correction map is set by a hardware field no code interprets | JPEGs at each HDR Tone Level against Standard |
| Which components Retro's four ToneControl values act on (§3) | written to hardware registers that nothing reads back | Retro against Standard on a grey ramp |
| Sharpening bin scale (§8.5) | set by hardware fields no code interprets | Sharpness −4 against +4 on a known edge |
| Which quantity selects the five multi-axis levels, and whether they scale the whole pixel (§4.5) | the code only copies tables to registers | a grey ramp and a saturated colour chart in Standard against Vivid |
| Whether Clarity, Grain and HDR Tone appear in live view (§1) | probably not, but a hidden read could have been missed | look at the camera's screen |
| Whether the camera applies a base's default values when the base is chosen (§7.1) | read from the settings initialiser, not from the menu code | choose each base after a reset and read its sliders |
| Whether toning is added before or after the chroma gain curve (§4.4) | register order in hardware | a toned look on a dark-to-bright ramp |
| How the GR IVx Monochrome renders Pictorialist Effect (§6.3) | not in firmware 1.20, and no GR IVx firmware is published yet | that body's firmware |

### 11.1 What the preview's detail effects assume that no camera has confirmed

The detail effects of §10.2 follow §8, and §8 was read from firmware that only programs the image-processing hardware: the arithmetic of that hardware is in no code. Each line below is something the preview relies on that is **[consistency]**, **[emulated]** or **[inferred]** and not **[observed]**. Choices GR Lab made for its preview (§10.2's scaling to the picture's size, the fitted curves, the fixed noise, leaving Sharpness out) are not listed: they are not claims about the camera.

All of it can be settled with one method, which needs a GR IV, a card and a way to get full-size JPEGs off it:

1. Shoot the RAW files named below at base ISO, and develop each one in the camera (Playback › RAW Development) into JPEGs at full size that differ in one setting. Developing one RAW several times gives pictures that line up pixel for pixel, which two shots never do.
2. Note for each JPEG the base and every value it was developed with (or read them back with `/imgctrl`).
3. Compare each JPEG with the model of §8 (`effects_ref.py`, at level 0, the full frame) applied to the luma of the JPEG developed without the effect. Averaging both down by 8 afterwards tests the preview's scaling (§10.2) as well.

| # | What the preview assumes | Source | RAW to shoot and JPEGs to develop | What confirms it | If it does not hold |
|---|---|---|---|---|---|
| 1 | Shading multiplies luma by `1 + (c − 1)·ρ²`, linear in ρ² from the centre to the corner | §8.1 **[consistency]** | an evenly lit, defocused grey wall; Shading −4, −2, 0, +2, +4 | Y(step)/Y(0) plotted against ρ² is a straight line from 1 to c | fit the falloff that is seen and replace `gr4Shade` |
| 2 | Negative Shading darkens the corners, and the corner gains are the table of §8.1 | §8.1 **[code]** for the constants, **[consistency]** for the operand order | the same JPEGs | the ratio at the corner is 0.25 at −4 and 2.52 at +4 | swap the sign, or correct the constants |
| 3 | ρ = 1 at the corner of the saved picture for every aspect ratio and crop | §8.1 **[code]** (aspect factors and zoom divisor), not run | the wall again at 1:1 and 4:3, and in the 35 mm and 50 mm crop modes; Shading −4 and 0 | the same straight line, reaching c at the corner of each | take the aspect or crop from the photo's metadata and scale ρ |
| 4 | Shading leaves chroma alone | §8.1 **[code]** | a coloured, evenly lit surface; Shading −4 and 0 | Cb and Cr of the two agree | scale chroma with luma |
| 5 | Clarity's pyramid halves by 2 × 2 averages and doubles with straight lines, and each band is multiplied by the table's gain | §8.2 **[code]** for the table, the resize filters **[emulated]** | a scene with detail at every size (foliage, brickwork, text); Clarity −4, −2, 0, +2, +4 | the model's result is within a code or two of the camera's on average, and the ratio of band energies per level matches the table | change the resize kernels in `Plane.halved` and `Plane.doubled`, or the gains |
| 6 | Grain is `Y + min(Y, 255 − Y, A)·(2n − 1)`: it never clips and fades towards black and white | §8.3 **[consistency]** | a defocused grey ramp from black to white; Grain Off and On at each Intensity, Size Medium | the difference from Grain Off has a deviation that follows `min(Y, 255 − Y, A)` along the ramp | fit the amplitude against Y and replace `_GrainAt.luma` |
| 7 | The amplitudes A by Intensity and Size, and which menu option is which stored value | §8.3 **[emulated]**; the menu mapping is **[inferred]** | the ramp at all nine Intensity and Size pairs | deviation at mid-grey of A/√3 times 0.506, 0.356, 0.291 by Size | correct the tables in `Gr4Grain` |
| 8 | The blur kernels by Size, and that the noise is uniform before the blur | §8.3 **[emulated]**; the outer ring of the 5 × 5 kernels is less certain | the same JPEGs | the autocorrelation of the difference matches the kernel's | correct `_blurWhole` and `_blurEdge` |
| 9 | Chroma noise on colour bases only, with limits of 1–12, thinned near grey; whether Cb and Cr share one noise is **[unknown]**, and the preview gives each its own | §8.3 **[emulated]** | the ramp, and a flat saturated colour, on Standard; a monochrome base for comparison | deviation of Cb and Cr, and their correlation (near 0 if separate, near ±1 if shared) | correct `_chromaLimit` and the noise per plane in `_addGrain` |
| 10 | Monochrome bases get twice the luma grain and no chroma grain | §8.3 **[emulated]** | the ramp on Monotone, Grain High | twice the Standard deviation | correct `_greyLimit` |
| 11 | Grainy's band gains and the size of its noise per octave (taken as 8-bit codes) | §8.3 **[emulated]**; the unit is **[inferred]** | needs a GR IV Monochrome: the ramp and a detailed scene, Grainy with Grain Off and On | deviation and contrast against the model | correct `_roughPeak` and `gr4RoughGains` |
| 12 | HDR Tone's per-level formula and which plane plays which part | §8.4 **[consistency]** | a scene with deep shadow and bright sky; HDR Tone at Low, Medium, High | with Y₀ = 2·Y(Low) − Y(Medium) as the picture without the effect, the model's correction for Y₀ matches Y(High) − Y₀ | re-read the unit chain (§8.4) with the camera's result as the target |
| 13 | HDR Tone's strength: the correction is added at a quarter, a half and the whole of its size | §8.4 **[inferred]** | the same JPEGs | Y(High) − Y(Medium) is twice Y(Medium) − Y(Low), and the size of the change matches the model's | scale `weight` in `_hdrTone` |
| 14 | The effects run on the full frame before a smaller JPEG size is made, in the order Shading, Clarity, Grain, HDR Tone | §8 **[code]**, not run | one RAW developed at L and at XS with Grain High and Clarity +4 | the XS picture is the L one made smaller, grain included | take the photo's size into the scale the effects are worked at |
| 15 | A JPEG taken with a look gets the same effects as RAW Development with it | assumed: one DigitalFilter module | one RAW+JPEG shot with Grain and Clarity set, and the RAW developed with the same values | the two JPEGs agree | note the difference in §8 |

Rows 1–10 and 12–15 need a GR IV; row 11 needs a GR IV Monochrome. The rows already in the table above for the Shading, grain and HDR Tone formulas and the HDR Tone strength are these same questions, stated more briefly.

## 12. The independent check

On 2026-11-09 the GR IV part of these notes was worked out a second time from firmware 1.20 without reading them (method in "How this was found"), and the two results were compared section by section. Most of it agreed, including every number the two passes both give: the tone-curve generator and the four tone sliders with their signs, the base matrices and camera matrix, saturation 1.1 per step, hue 2.46° per step, the toning tables, the per-channel curves and the Cinema blend, Cross Processing's presets and unreachable random mode, the Shading constants and aspect factors, the Clarity gain table, the grain amplitudes and kernels, the HDR Tone weights 4, 8 and 16, the Sharpness gain, and the main finding that Image Control changes processing only. Where they differed, the question was settled from the firmware with REA (Ghidra decompilation of the functions named, evidence records below) and the emulator:

| Point | First version | Independent pass | Settled as |
|---|---|---|---|
| Noise reduction (§2, §8.6) | never depends on the base or a slider | Key, Contrast, Shadow, Saturation and the base shift the ISO index | the index is shifted: read in 0x5393a730, 0x539421f0, 0x53948fd8 and 0x53948cb0, and seen in the emulated registers |
| Multi-axis hue areas (§4.5) | windows around red, skin and orange | 12 areas round the whole circle | whole circle: the thresholds are exact tangents of round angles, and only that reading makes neighbouring matrices meet at their boundaries |
| Multi-axis levels (§4.5) | a strength curve constant at 1.0, so no variation | five matrices per area scaled by 1 − *l*/16 along an unnamed 12-bit quantity | both hold: the scaling is in the tables; what selects the level stays unknown |
| "B mode" (§1) | bulb mode, reason for the restriction open | movie mode | movie mode: the manual's glyph is the movie icon, and `IsValid` and the default getters carry the same restriction |
| Live-view Shading (§8.1) | inferred from the table's layout | traced | traced: 0x536596d4 passes the Shading value of the live-view settings to 0x5394ed38 |
| Bleach Bypass toning 0 (§4.4) | what it renders unknown | Normal's matrix without the tint | confirmed in the emulator |
| Chroma gain curve (§4.4) | per ISO | the same at every ISO | stored per ISO step, all 144 records identical |
| Toning registers (§4.4) | 0x54c/0x54e and 0x554/0x556 | 0x154c/0x154e and 0x1554/0x1556 | the second: the emulated toning values appear there, in the numbering in which colour matrix block 1 is at 0x1120 |
| Default values of each base (§7.1) | not covered | table from the settings initialiser | added |
| Middle edge enhancer (§8.5) | three enhancers | middle one off except for Mono Solid | added |
| High/Low Key and the white point (§3) | the clip point moves from 0.99 to 0.86 of full scale | white stays fixed | the first version is right: the independent model gives clip points 0.988 at −4 and 0.859 at +4 |
| What computes the DigitalFilter effects (§8) | the IIP hardware, programmed by the firmware | a software pass | hardware: the independent pass's own unit programs (loader, LUT, blend, store) show it |
| Chroma grain (§8.3) | its own noise plane | not stated | consistent: the grain builder, run in the emulator, allocates two full-size noise buffers |
| Solarized Effect and vignetting (§1) | off in still development and live view | still path not traced | both: 0x539655d4 is called from the still develop path (0x5374f464) and from the live-view gain map (0x53965f94) |
| GR IV Monochrome toning and the Grainy and Solid curves (§5, §6.2) | half-strength table; matte and mild curves | not covered | confirmed in the emulator with the Monochrome project type |

REA evidence records for the functions that settled these (Ghidra 12.1.4 pseudocode of GR IV 1.20 `rtos.bin`, SHA-256 `cf51224e…61a9`):

| Function | Role | Record |
|---|---|---|
| 0x5393a730 | exposure data to table indices | `ev_8fbb72357023d25aed44595197c61f5d2ccc194e0dc0d34c74afe29b480633a6` |
| 0x539421f0 | luma noise-reduction record lookup | `ev_453b79ba2ac7bd1308fec7c9ed1bc14c98d9a13add461138ed2bff4be337c960` |
| 0x53948fd8, 0x53948cb0 | filter-unit record lookups | `ev_c2648cad8b3b201a74d055cec9f6dc98fbc79b23e4a71d0b16d477016616c3d3`, `ev_6e3a50e22d40750675b47f5e1f4031ce308d4794b3bc21ab9e97d4dbcee56341` |
| 0x53942190 (selected by its inner address 0x5393d284) | multi-axis register writer | `ev_2786e5a9ca1615590b94800b0475bc0bceba025964f952da0214f5d31e4de11f` |
| 0x533de144 | `ImageControlModel::IsValid` | `ev_77ca570e6c5419e9dbd00e14d10742597cd29ed8ce646921f687f3a8d672050d` |
| 0x536596d4, 0x5394ed38 | live-view Shading tables | `ev_e243689d88ccba3590356f5233fc5215823d1c6a97df00f6ee15c1f82f9e3416`, `ev_9384ffe31a4ef2a83bab2d4915a27850b6d3dbff7f2ac08534ba192cacfaec68` |
| 0x539655d4, 0x5374f464 | lens vignetting gain map and its still caller | `ev_8a8f31402e95c52ca6997186d2a57d97532ce32145d3643df0b266841fe3c11e`, `ev_7258c14e097fe69690cfac59664adcf41a362dd1691024b21309330564eb36eb` |
| 0x53939128 | settings to tuning values (forced values per base) | `ev_16f4358d478be94b9d0c90962b65f215f233b5d2ea075b473a85a6ad542c29a8` |

The GR III part of these notes was not re-derived.
