# Camera menu languages and menu text

GR Photo is translated into the languages the camera's own menus offer, and words camera things (menu entries, Image Control names, values) as the camera does in each language. This file records which languages those are, where the camera's text is, and what is still unknown.

## The languages

Twenty-one, on every body examined:

| Ricoh's name | GR Photo locale | The camera's name for it |
|---|---|---|
| English | `en` | English |
| French | `fr` | Français |
| German | `de` | Deutsch |
| Spanish | `es` | Español |
| Portuguese | `pt` | Português |
| Italian | `it` | Italiano |
| Dutch | `nl` | Nederlands |
| Danish | `da` | Dansk |
| Swedish | `sv` | Svenska |
| Finnish | `fi` | Suomi |
| Polish | `pl` | Polski |
| Czech | `cs` | Čeština |
| Hungarian | `hu` | Magyar |
| Turkish | `tr` | Türkçe |
| Greek | `el` | Ελληνικά |
| Russian | `ru` | Русский |
| Thai | `th` | ไทย |
| Korean | `ko` | 한국어 |
| Simplified Chinese | `zh` | 中文简体 |
| Traditional Chinese | `zh_Hant` | 中文繁體 |
| Japanese | `ja` | 日本語 |

- **Found in Ricoh's published specifications** (read 2026-11-10): the "Language" row of the GR IV specifications (`ricoh-imaging.co.jp/english/products/gr-4/spec/`) lists these 21 in the order above, which is the order of GR Photo's `app/l10n.yaml` and of its language list in Settings. The GR III page lists the same languages.
- **Found in firmware**: the RTOS image of GR IV 1.20, GR III 2.20 and GR IIIx 1.70 holds one table of menu text per language, 21 tables each (see below). The names in the third column are entry 598 of the GR IV tables, the name each language gives itself in the camera's Language menu.
- The GR IV manual says the languages offered can depend on where the camera was bought. Which bodies ship with fewer is **[unknown]**; GR Photo offers all 21 regardless.
- **The camera's Portuguese is European** (found in firmware: `ecrã`, `ficheiro`, `definições`, `câmara`, `comunicação sem fios`), so GR Photo's `pt` is European Portuguese and is what a phone set to Brazilian Portuguese gets too.
- GR IV Monochrome 1.10 was not examined: its RTOS image is not extracted in the workspace. It shares the GR IV firmware family ([camera-models.md](camera-models.md)), so the same tables are expected **[inferred]**.

## Where the menu text is

Found in code, in `firmware/gr4_v120/rtos.bin` (GR IV 1.20):

- The image loads at `0x53000000` **[inferred]**: with that base every pointer below lands on what it should.
- From file offset `0x13b5270`, 21 arrays of 880 little-endian pointers follow one another with a zero word between them. Each array is one language; the order is Czech, Danish, English, Finnish, French, German, Greek, Hungarian, Italian, Japanese, Korean, Dutch, Polish, Portuguese, Russian, Simplified Chinese, Spanish, Swedish, Thai, Traditional Chinese, Turkish (alphabetical by English name).
- Each pointer leads to an 8-byte record: a `u32` tag and the address of a NUL-terminated UTF-16LE string. In the tag, the low byte is the string's length with its terminator and the next byte the number of lines **[inferred]** from samples (`0x0108` for "English", `0x0351` for an 80-character, three-line help text).
- The arrays are parallel: entry *n* is the same text in every language. Entry 702 is "Paired Devices", 698 "Execute Pairing", 688 "Action Mode", 307 "Image Control", 309 to 330 the Image Control names.
- Many texts appear twice in a row with the same English: a menu label and the title of the screen it opens. In other languages the label is often abbreviated to fit the menu's width (`Dispositiv. Emparelhados`) and the title is written out (`Dispositivos Emparelhados`).
- GR III 2.20 and GR IIIx 1.70 use the same layout with 785 entries per language; entry numbers differ from the GR IV's.

`research/tools/menu_strings.py` finds the tables in an RTOS image without fixed offsets and prints an entry in every language:

```
python3 research/tools/menu_strings.py ../gr/firmware/gr4_v120/rtos.bin "Paired Devices"
```

The tables are Ricoh's text. GR Photo's translations use individual terms from them so that the app matches the camera; the tables themselves are not in this repository.

## How GR Photo uses it

- A message whose description in `app/lib/l10n/app_en.arb` says it is the camera's wording ("as Ricoh names it", "Use the text the GR shows in this language") carries the camera's text for that entry in each translation, abbreviations included, because that is what the user sees on the camera.
- Sentences that name a camera menu entry use the written-out title.
- Texts the tables do not hold are GR Photo's own wording in every language **[design]**: the values of Toning, Color Tone, Grain Effect size and Filter Effect (Sepia, Cool, Warm, Basic, the colours, Large, Small), Astro, and everything about GR Photo itself.
- The translations were made from the GR IV 1.20 tables. Where a GR III words an entry differently, GR Photo follows the GR IV **[design]**; the differences were not compared, except for pairing. The messages shown only for a GR III or GR IIIx (their descriptions in `app_en.arb` say so) name its Bluetooth Setting menu and Action Mode values from the GR III 2.20 tables (entries 608 and 614 to 616), and the pairing entries both families have (Action Mode, Pairing, Execute Pairing, Paired Devices, Authentication Code) read the same in the GR III 2.20 and GR IV 1.20 tables in all 21 languages ([GR III firmware bonding §4](protocol/firmware-bonding-gr3.md#4-menu-and-on-camera-text), compared 2026-11-13).

## Unknown, for a hardware check

- **The name of the E6 menu page.** The GR IV manual (English) calls it "E6 Wireless Connection", and GR Photo's English says so. No GR IV 1.20 table has that text; where the other pages' names sit (File Setting, Display Settings, LCD Setting, Sound Effects Setting, Power Supply Settings, About This Device), the entry before USB Setting, Bluetooth Settings, Wireless LAN Settings and Wireless Communication is "Communication Settings" (entry 670). What the camera shows as the E6 page's name is **[unknown]**. Until a camera settles it, the translations name the page by its number alone (`MENU → E6 → Wireless Communication`), which holds either way. Test: open MENU, go to E6 on a GR IV with firmware 1.20, read the page title, in English and in one other language.
- **Which OK the pairing code screen shows.** The tables have two entries reading "OK" in English (867 beside a "Cancel", 869 alone); in Japanese, Korean, Chinese and Turkish they differ (`決定` and `了解` in Japanese). GR Photo's drawing of that screen uses 867 **[inferred]** because the screen offers a cancel too. Test: start pairing with the camera set to Japanese and read the button.
