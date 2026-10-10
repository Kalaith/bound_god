# Font Direction: Japanese Woodblock Print

Update the game's typography to complement **Direction 1: Woodblock Voxel**, inspired by traditional Japanese ukiyo-e prints, aged paper, and hand-printed lettering.

## Typography Style

- Use a **traditional, expressive serif** for headings, shrine names, divine messages, and important events.
- Letterforms should feel slightly organic, resembling ink pressed onto paper rather than perfectly geometric digital text.
- Use restrained variation in stroke thickness and subtle irregularity.
- Avoid overly decorative, calligraphic, or difficult-to-read fonts.
- Keep English text readable. Japanese character support is desirable but not required for the initial implementation.

## Font Hierarchy

- **Display font:** Woodblock-inspired serif for titles, shrine names, divine announcements, and event headings.
- **Body font:** Clean, readable serif or humanist font for dialogue, descriptions, and menus.
- **Utility font:** Simple, highly legible font for numbers, hotbar labels, resource quantities, and controls.

Prefer two complementary font families rather than introducing numerous typefaces.

## Colours and Presentation

- Use warm charcoal or dark brown ink on parchment backgrounds.
- Use muted cream text on dark panels.
- Avoid pure black, bright white, neon colours, and heavy text shadows.
- Keep text crisp. Apply any paper grain or ink irregularity to surrounding UI surfaces rather than compromising glyph legibility.

## Implementation

1. Inspect the existing font rendering and UI system.
2. Select suitable open-source fonts that fit the visual direction and have appropriate licensing.
3. Establish reusable display, body, and utility font styles.
4. Apply them consistently across HUD, menus, inventory, dialogue, and tooltips.
5. Adjust sizing, weight, line spacing, and contrast for desktop readability.
6. Preserve UI scaling and avoid unnecessary changes to panel layouts.

## Constraints

- Do not use Japanese characters decoratively in place of readable English.
- Avoid novelty or exaggerated brushstroke fonts for general UI text.
- Do not make ordinary gameplay information look like an ornate historical manuscript.
- Prioritise legibility at small sizes, especially for the hotbar and resource counters.
- Avoid adding permanent decorative UI elements purely to reinforce the theme.

## Success Criteria

The typography should feel like it belongs within an illustrated Japanese woodblock print while remaining comfortable to read during extended gameplay.

**Target:** Traditional printed-ink character, modern game readability.