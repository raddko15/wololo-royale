# Art style

One flat low-poly style for every asset, drawn as SVG so it stays editable
(Inkscape, Figma, any vector tool).

- Light comes from the top left: faces turned left/up are lighter, faces
  turned right are darker (about -25%).
- Every object sits on a soft ground shadow (black, 25% opacity).
- Outlines: #2b1d10, 1.5 px, round joins.
- Civ colors: parts that should take the civ color live in a separate
  `*_tint.svg` drawn in white; the game tints it at runtime. Shading on top
  of those parts is in the main file as semi-transparent black/white.
- Files are authored at 2x (the width/height attributes are twice the
  viewBox) so they stay sharp on phones; the game draws them at 1x.

## Palette
| Use | Light | Base | Shade |
|---|---|---|---|
| Wood | #c08a50 | #a0703f | #6e4a28 |
| Straw | #f0d68a | #e2c36b | #b8984a |
| Mud | #c9a27a | #a8835c | #7c5d3e |
| Stone | #d6d2c6 | #b9b4a8 | #8c877c |
| Leaves | #6fb34d | #4f8f37 | #346626 |
| Trunk | #8a5a33 | #6b4426 | #4a2f1a |
| Outline | | #2b1d10 | |
