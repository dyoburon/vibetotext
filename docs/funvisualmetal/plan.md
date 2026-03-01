# Frequency Tree — Living Data Visualization

## Concept

A single procedural tree that grows from your transcription data. It's a generative art piece — unique to each user, shaped entirely by how and when they speak. You open the app and see *your* tree.

## Core Visual

- **Metal shader-driven** — procedural geometry for branches, particle system for leaves
- **Single tree, centered** — not a forest, not explorable. One focused, beautiful thing
- **Grows over time** — scrub through your history and watch the tree build itself

## Data Mapping (3 elements, no more)

| Visual Element | Data Source |
|---|---|
| **Branches** | Topics — each major topic becomes a branch splitting from the trunk |
| **Leaves** | Words — leaf density reflects how much you talked on a given day |
| **Growth/height** | Time — the tree grows taller as days pass, new branches emerge |

## Gamification

### 1. The Tamagotchi Effect (daily engagement)
If you don't talk for a day or two, leaves start falling. The tree doesn't die, but it visibly wilts — branches droop slightly, leaves turn dull and drift off. Open the app and see your tree looking sad. That's the motivation.

Talk again and it recovers: new growth appears, leaves fill back in, colors brighten. The recovery is visible and satisfying.

**Mechanic:** Days since last transcription controls a "health" value (1.0 = active today, decays over ~3 days to a floor of ~0.3). Health drives leaf opacity, droop angle, and particle spawn rate.

### 2. Streaks = Blooms (streak reward)
Consecutive days of talking make flowers or fruit appear on branches. Miss a day, no new blooms. The tree still grows but it's bare wood vs. a flowering tree.

- **3-day streak** — small buds appear
- **7-day streak** — flowers bloom on recent branches
- **14-day streak** — fruit appears (glowing particles)
- **30-day streak** — the whole canopy glows, full bloom

**Mechanic:** Current streak length stored in DB. Streak tier determines bloom shader pass intensity and particle type (bud → flower → fruit → glow).

### 3. Seasonal Cycles (weekly consistency)
The tree reflects your consistency over the past few weeks, mapped to seasons:

| Consistency | Season | Visual |
|---|---|---|
| Daily use, steady | **Summer** — lush green canopy, full leaves, warm light |
| Regular but gaps | **Spring** — light green, new growth, some bare branches |
| Sporadic | **Autumn** — golden/orange leaves, some falling, thinning canopy |
| Long inactivity | **Winter** — bare branches, muted colors, still/quiet particles |

Come back after a gap and you see spring — new buds, fresh green pushing through bare branches.

**Mechanic:** Rolling 14-day activity ratio (days active / 14) maps to season float (0.0 = winter, 1.0 = summer). Season drives leaf color palette, particle density, and ambient lighting.

## Technical Foundation

- Lives in the existing **WordGalaxy** native Swift app (`native-app/`)
- Uses the existing **Metal** rendering pipeline (`GalaxyRenderer.swift`, `ShaderSource.swift`, `ParticleSystem.swift`)
- Data comes from **DatabaseManager.swift** which already reads transcription history
- Branch geometry: L-system or recursive subdivision, driven by topic/session data
- Leaf particles: existing particle system adapted with health/season uniforms
- Bloom/glow: reuse bloom shader passes from the sphere visualization

## Open Questions

- How to extract "topics" from transcriptions for branch mapping — keyword clustering? LLM summary?
- Camera: fixed or allow orbit/zoom?
- Should the tree persist visually between sessions (screenshot/cache) or regenerate each launch?
- Replay mode: linear time scrub, or day-by-day step?
