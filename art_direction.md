# Art Direction Brief: Painterly Voxel World

## Objective

Transform the game's current Minecraft-like appearance into a **playable painting inspired by Japanese ink wash, woodblock prints, and soft pastel illustrations**.

The goal is for ordinary gameplay screenshots to resemble artwork while preserving the freedom, readability, and construction capabilities of a 3D voxel sandbox.

**Target style:** Soft pastel environments with selective ink outlines, subtle paper textures, and Japanese-inspired painterly composition.

## Visual Principles

### 1. Painterly, Not Pixelated
- Replace noisy, pixelated block textures with simplified painted surfaces.
- Use broad colour shapes, subtle brush variation, and restrained material detail.
- Apply subtle paper grain across the rendered world to unify the appearance.
- Avoid photorealistic, glossy, or heavily pixelated materials.

### 2. Soft, Cohesive Colour Palette
- Use muted greens, warm creams, earthy browns, faded blues, and soft greys.
- Reserve stronger colours for sacred objects, important characters, and meaningful events.
- Avoid oversaturated grass, harsh contrast, and Minecraft-style primary colours.
- Ensure different materials remain distinguishable during construction.

### 3. Ink-Inspired Shapes and Outlines
- Introduce subtle, selective ink-style outlines along important silhouettes and environmental features.
- Avoid outlining every individual voxel.
- Emphasise natural forms such as trees, rocks, hills, and flowing water.
- Use stylised foliage shapes rather than uniform cube clusters where practical.

### 4. Illustrated Lighting and Atmosphere
- Use soft, directional lighting with gentle shadows.
- Introduce atmospheric distance fading and subtle environmental mist.
- Use restrained bloom and spiritual effects around sacred objects.
- Avoid harsh shadows, excessive specular highlights, and realistic lighting that conflicts with the painted aesthetic.

### 5. Sacred Tree as the Visual Centrepiece
- Make the sacred tree visually distinct from ordinary vegetation.
- Give it a recognisable silhouette, layered foliage, expressive roots, and subtle spiritual characteristics.
- Sacred effects should feel magical without dominating the scene.
- The surrounding environment should gradually reflect the god's influence.

### 6. Preserve Voxel Gameplay
- Retain editable voxel terrain and block-based construction.
- Prioritise readability of block boundaries when building or targeting blocks.
- Allow terrain, buildings, and foliage to remain visually cohesive at different viewing distances.
- Do not replace the voxel world with static illustrations or purely decorative scenery.

## UI Direction

Keep the gameplay screen minimal.

- Use restrained, semi-transparent panels with subtle ink or parchment influence.
- Avoid excessive decorative borders and oversized UI elements.
- Keep the hotbar compact and unobtrusive.
- Maintain clear, modern typography for readability.
- Let the world occupy as much of the screen as possible.

## Implementation Priorities

Make changes incrementally, starting with the largest visual improvements:

1. **Palette and materials:** Reduce texture noise and establish the painterly colour palette.
2. **Lighting and atmosphere:** Introduce softer lighting, atmospheric depth, and controlled shadows.
3. **Foliage and silhouettes:** Improve tree canopies, vegetation, and terrain readability.
4. **Ink and paper treatment:** Experiment with selective outlines, subtle grain, and gentle colour grading.
5. **Sacred identity:** Refine the sacred tree and spiritual visual effects.
6. **UI refinement:** Align the existing HUD with the new aesthetic.

Prefer reusable rendering techniques and procedural variation over creating large numbers of individual assets.

## Constraints

- Do not redesign gameplay systems or change voxel interaction mechanics.
- Do not simply replace existing blocks with Japanese-themed materials.
- Do not apply heavy full-screen filters that obscure detail.
- Do not sacrifice construction readability for artistic appearance.
- Avoid introducing expensive rendering techniques without evaluating performance.
- Preserve the existing camera and world layout unless adjustments materially improve visibility.

## Success Criteria

The updated game should:

- Look recognisably different from Minecraft.
- Resemble a soft ink-and-pastel illustration in normal gameplay.
- Remain readable and practical for building, exploration, and NPC interaction.
- Maintain a consistent visual identity across terrain, vegetation, buildings, characters, and weather.
- Look attractive without requiring carefully staged camera angles.

**Guiding principle:** The game should feel like the player is walking through and reshaping a living painting, not assembling textured cubes.