# Title image

Generated with the built-in imagegen tool on 26 October 2026. The Alchemy Tower
example supplied by the owner informed the level of painterly detail; each scene
was composed for this game's setting and live menu. Text remains native Godot UI.

Asset: `assets/art/ui/title_screen.png`. Original artwork remains preserved.

## Generation prompt

Use case: stylized-concept. Create original polished hand-painted title background for The Bound God, wide 16:9 1920x1080. Sacred ancient tree towering above a small cultivation sect in a misty mountain valley. Massive gnarled trunk at left, emerald and jade canopy, subtle golden qi motes in its roots, tiny robed spirit avatar beneath tree and mortals meditating and tending simple timber halls, terraces, lanterns, small river. Underlying terrain has intentional stepped stone and earth terraces recalling a voxel world, softened by lush foliage. Painterly ink-influenced fantasy illustration, elegant silhouettes, tactile bark and stone, atmospheric blue distant mountains, dawn sunlight in leaves. Main tree and settlement on left half, RIGHT 40 percent dark soft misty foliage and shadow with low detail for live menu. Quiet nurturing divinity rather than conquest. No giant human deity, no battle, no copied franchise characters. No text, letters, logo, watermark, UI or borders. Save generated image locally and return path.

## Integration and verification

- The title uses this project-local image with aspect-preserving cover scaling.
- Text, focus, settings, saves and start actions remain native Godot UI.
- Godot 4.7.2 headless editor import completed successfully.
- Silent automated windowed capture ran on the OpenGL Compatibility renderer;
  the rendered title was visually inspected at one fixed size.
- Capture: `docs/verification/title.png`. Reproduce with
  `Godot --path . --audio-driver Dummy --script res://tools/capture_title.gd`.
- Capture exited with code 0 and reported ObjectDB/resource cleanup warnings
  during shutdown. These remain unresolved; title rendering succeeded.
- No gameplay simulation suite, export, browser/touch pass or human playtest
  was run for this title-art change. Nothing was pushed or published.
