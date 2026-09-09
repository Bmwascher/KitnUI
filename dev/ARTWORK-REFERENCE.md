# KitnUI artwork reference

This file is the durable source of truth for generating or editing KitnUI's
installer and EllesmereUI options artwork. Use the tracked assets below as
references. Files in Downloads, chat attachments, screenshots, and old raw
generations are not authoritative.

Last measured: 2026-09-09 at KitnUI `3ed2f0a` and installed EllesmereUI 9.1.6.
Re-measure hashes and external-version details after an asset or EllesmereUI
update.

## Authoritative assets

| ID | Surface | Theme name | Tracked file | Canvas and PNG format | Alpha | Bytes | SHA-256 |
| --- | --- | --- | --- | --- | --- | ---: | --- |
| Installer A | KitnUI installer | `KitnUI` | [`Media/Background/KitnUI-EUI-Background.png`](../Media/Background/KitnUI-EUI-Background.png) | 1024 x 808, 8-bit RGB truecolor | Fully opaque | 761,814 | `865B8B27E2C8A5019ED476227768DCFF1D8B4E78B04C5A7D1E679F0A315A63C4` |
| Installer B | KitnUI installer | `KitnUI Rasta` | [`Media/Background/KitnUI-EUI-Background-Rasta.png`](../Media/Background/KitnUI-EUI-Background-Rasta.png) | 1024 x 808, 8-bit RGB truecolor | Fully opaque | 826,389 | `C9D089AC65DB408DEEE554C1F47775139D398FD74393B8BB450B040438E145DA` |
| Options A | EUI options panel | `KitnUI` | [`KitnUI_EUI/Media/Backgrounds/KitnUI-EUI-Options.png`](../KitnUI_EUI/Media/Backgrounds/KitnUI-EUI-Options.png) | 1500 x 1154, 8-bit RGBA truecolor | Mixed 0-255 alpha | 1,656,221 | `BDACFCA6F4F302422D316026BF33176BC3A9E8CC601B0A9A83217BEF5E6E5F72` |
| Options B | EUI options panel | `KitnUI Rasta` | [`KitnUI_EUI/Media/Backgrounds/KitnUI-EUI-Options-Rasta.png`](../KitnUI_EUI/Media/Backgrounds/KitnUI-EUI-Options-Rasta.png) | 1500 x 1154, 8-bit RGBA truecolor | Binary 0/255 alpha | 1,707,517 | `60F59C84FC7810E11271C20640954D5654DE18CFF0F07C8FB66728C993F84C74` |

All four files are directly uploadable as ChatGPT Images references. Do not
make JPEG copies. JPEG compression damages the thin rails, particles, text,
and transparency edges.

## Shared character language

Both themes use the same basic cat silhouette and jewelry language:

- a centered, forward-facing, fluffy black cat with upright pointed ears;
- a symmetrical four-point diamond mark centered on the forehead;
- an ornate dark collar;
- a circular paw-print medallion;
- a small faceted point hanging below the medallion.

The cat is a background subject. It must remain behind live labels and controls,
not read as a bright foreground portrait.

### Theme A identity

- Dark black-to-burgundy fur with restrained magenta rim light.
- Magenta-pink eyes and forehead diamond.
- Dark collar with a magenta paw medallion and hanging crystal.
- Deep burgundy, wine red, muted magenta, and pink palette.
- Highlights are controlled. Avoid neon bloom, bright white, and crushed black.
- No cigarette, blunt, smoke, teal, gold, orange, or rainbow color treatment.

### Theme B identity

- Black fur with low teal light from the left and muted amber light from the
  right.
- Amber-gold eyes, forehead diamond, collar details, paw medallion, and hanging
  point.
- One blunt held at the viewer-right side of the mouth, with a small ember and
  thin restrained smoke. Do not enlarge it or turn the smoke into a focal point.
- The background moves from deep teal/cyan on the left through subdued
  green-gold/amber to dark burgundy/red on the right.
- Keep the palette smoky and low-saturation. It is not a bright red-yellow-green
  stripe treatment.
- No magenta Theme A recolor.

## Installer surface

`Installer/Wizard.lua` loads the two installer PNGs. The files must have
identical geometry so a theme swap changes only the artwork and color family.

### Fixed file and display geometry

- Full source canvas: 1024 x 808 pixels, aspect 1.267327:1.
- The source contains a black outer margin around the baked panel.
- Runtime texture crop: left `0.065`, right `0.940`, top `0.099`, bottom
  `0.916`.
- That crop spans 896 source pixels horizontally and about 660.136 vertically.
- Displayed installer frame: 760 x 560 UI units, aspect 1.357143:1.
- Canonical normalization anchors:
  - X: outer-left `68`, sidebar divider `277`, outer-right `971`.
  - Y: outer-top `73`, sidebar-header rule `136`, bright main-header rule
    `168`, lower-header rule `202`, footer-top rule `694`, outer-bottom `754`.
- The baked sidebar becomes about 178 displayed units after the runtime crop.
  Live content starts at displayed X `200`.

The source anchors of a new generated image must be measured from that image.
Do not reuse source coordinates from an earlier generation. Normalize each
region piecewise to the canonical target anchors so the sidebar, header, main
area, and footer do not drift independently.

### Baked elements that must not move

- Outer panel rectangle and black margin.
- Sidebar width and divider.
- Header and footer heights.
- Horizontal rails, bevels, corners, and glow intersections.
- Top-left cat-head logo and the exact text `KitnUI`.
- Upper-right close-button box.
- Empty main-panel areas reserved for live installer text and controls.

Do not bake page titles, navigation steps, addon names, buttons, a progress bar,
a step counter, warnings, or other live installer content into the image. Do not
use an in-game installer screenshot as a generation reference; it invites the
model to bake those overlays into the background.

### Theme-specific installer treatment

- Installer A uses Theme A's cat identity and pink palette. The cat is subdued,
  centered in the main area, below the header, and fades before the footer.
- Installer B uses Theme B's cat identity, blunt, and teal-to-amber-to-burgundy
  palette. It keeps exactly the same panel geometry and negative space as A.
- Installer artwork says `KitnUI` only. Never import `x EllesmereUI` or
  `KitnUI x EllesmereUI` from an options-panel reference.

## EUI options surface

`KitnUI_EUI/Theme.lua` registers the names `KitnUI` and `KitnUI Rasta`. It
places the selected image on an overlay that fills EllesmereUI's main frame.
KitnUI applies no texture crop to these files.

### Fixed file and display geometry

- Canvas: 1500 x 1154 pixels, aspect 1.299827:1.
- Format: 8-bit RGBA truecolor PNG. Preserve transparency; never flatten an
  options image onto black.
- The overlay uses `SetAllPoints` on the host main frame. The host may scale its
  panel, so the source is not guaranteed to display one source pixel per screen
  pixel.
- The two assets must retain the same outer frame, sidebar, header, lower rail,
  close-button location, and content-safe areas.
- Options A currently uses a graded alpha channel. Options B currently uses
  transparent or opaque pixels only. Preserve the selected edit target's alpha
  behavior unless a deliberate replacement workflow reconstructs it.
- Current Options A alpha counts: 501,666 transparent pixels, 1,226,151
  partially transparent pixels, and 3,183 opaque pixels.
- Current Options B alpha counts: 500,270 transparent pixels and 1,230,730
  opaque pixels, with no partially transparent pixels.

### Baked elements that must not move

- Outer panel and border.
- Sidebar and vertical divider.
- Top header, bright rail, lower header rail, and bottom rail.
- Upper-right close-button box.
- Top-left cat icon and the exact identity line `KitnUI × EllesmereUI`.
- Main-panel negative space used by EllesmereUI controls.

Preserve the visible multiplication mark from the selected edit target. It must
not be changed into a second word, duplicated, omitted, or smudged.
Do not bake settings labels, tabs, dropdowns, sliders, buttons, or footer links
into the artwork.

### Runtime accent

Both registered options themes intentionally share the same host accent preset:
RGB `(1, 0, 0.549)`, approximately `#FF008C`. The image selects artwork only;
it does not silently recolor the EUI panel or the Top Bar. Theme B's teal and
amber are therefore artwork colors, not a second runtime accent setting.

## Optional host tonal reference

For a new EUI options image, the installed Midnight background is the preferred
reference for black level, overall luminance, and highlight restraint:

`C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\EllesmereUI\media\backgrounds\eui-bg-midnight-compressed.png`

Measured against installed EllesmereUI 9.1.6 on 2026-09-09:

- 1500 x 1154 indexed PNG with transparency;
- 880,817 bytes;
- SHA-256
  `C849B8D4323CC0541551B9504EE75499504A509FCD5B6F4F8B055A4FE643CDD8`.

Use it only as a tonal reference. The tracked KitnUI image remains the geometry,
text, cat-identity, and palette-direction authority. Recheck the installed EUI
version and hash before relying on this external file because an addon update
may replace it.

## Reference order for future image chats

Use a fresh image chat for a new surface or major variant. Old chat context can
carry the wrong cat, palette, brightness, or layout into the next result. Upload
only the references needed for that edit and assign each one a single role.

### Editing an installer image

1. Upload the installer image being changed as **Image 1: strict edit target and
   absolute geometry/palette authority**.
2. Upload the matching EUI options image as **Image 2: cat identity and jewelry
   authority only**.
3. State: change only the named subject or feature; keep every other Image 1
   pixel family, structural element, text element, negative-space region, and
   brightness relationship unchanged.
4. Explicitly forbid importing `x EllesmereUI`, options controls, or Image 2's
   background geometry.

For Theme A, use Installer A then Options A. For Theme B, use Installer B then
Options B.

### Editing an EUI options image

1. Upload the options image being changed as **Image 1: strict edit target,
   geometry, alpha, text, and identity authority**.
2. When luminance is changing, upload the installed Midnight image as **Image 2:
   black-level, brightness, and highlight-intensity authority only**.
3. Add another identity or color reference only when it supplies a named feature
   that the first two images do not contain. State that it has no authority over
   layout, text, or brightness.

### Creating a coordinated new pair

Finish the EUI options image first. It becomes the identity reference for the
installer image. Then create the installer image in a fresh chat using the
existing installer as Image 1 and the approved options image as Image 2.

Always download and preserve the raw generated result. Do not ask the image
model to repeatedly resize or repair the complete frame. Measure and normalize
the selected result deterministically afterward.

## Acceptance and verification

Before replacing a tracked asset:

1. Judge the generated cat, icon, text, rails, and fine details at the actual
   displayed size, not only enlarged.
2. Decode the final PNG and verify dimensions, bit depth, color type, and alpha
   behavior from the shipped bytes.
3. Compare the rendered/cropped installer preview built from the final PNG bytes.
4. Run `lua dev/tests/eui-theme.lua` from the repository root.
5. Run `git diff --check`.
6. In game, `/reload`, open `/kitn install`, switch between both installer
   themes, and inspect text readability and all frame alignments.
7. Open EllesmereUI options, select both `KitnUI` themes, and inspect the full
   panel at the supported scale settings.

Static image checks cannot establish final in-game brightness, readability, or
host scaling. The in-game check remains required before merge or release.
