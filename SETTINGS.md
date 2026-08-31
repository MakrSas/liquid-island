# Liquid Island settings

*[Русская версия](SETTINGS.ru.md)*

Everything about the look and behaviour lives in
`~/Library/Application Support/LiquidIsland/theme.json`.
The file is re-read on the fly — edits show up without a restart.

The settings window covers all of this, but the same keys can be edited by
hand. The type column says what kind of control each one is: a slider, a
switch or a choice.

## Geometry — `geometry`

| Key | Type | Default | What it does |
|---|---|---|---|
| `closedSize` | size | 168 × 26 | The pill at rest, when nothing is playing |
| `compactSize` | size | 304 × 26 | The now playing card at rest. Same height — the island grows sideways, not down |
| `hudSize` | size | 268 × 30 | The system HUD: volume, brightness, power |
| `warningSize` | size | 360 × 64 | The low battery warning: two lines and a button |
| `hoverPadding` | size | 14 × 24 | How much it grows under the cursor. Downward growth happens only here |
| `expandedSize` | size | 420 × 168 | The expanded player |
| `topRadius` | 0…20 | 9 | Top corners, curving outward into the screen edge |
| `bottomRadiusClosed` | 0…20 | 8 | Bottom corners at rest |
| `bottomRadiusOpen` | 0…40 | 11 | Bottom corners when expanded |
| `artworkRadius` | 0…16 | 5 | Artwork corner radius at rest |
| `artworkRadiusHovered` | 0…16 | 8 | The same under the cursor |
| `floatingTopInset` | 0…20 | 0 | Gap from the screen edge. Zero means the island grows out of it |
| `contentPadding` | insets | 12/16/14/16 | Padding of the expanded island |
| `compactPadding` | insets | 4/7/4/12 | Padding of the card |
| `glassFadeStart` | 0…1 | 0.44 | Where black starts giving way to glass, as a fraction of height |
| `glassFadeEnd` | 0…1 | 0.72 | Where black is gone entirely |

## Colours and glass — `palette`

| Key | Type | Default | What it does |
|---|---|---|---|
| `background` | colour | black | The body of the island. An alpha below one makes it translucent in every state, not just when expanded |
| `primaryText` | colour | white | Track title |
| `secondaryText` | colour | white 60% | Artist and times |
| `accent` | colour | orange | Fallback accent when no colour could be pulled from the artwork |
| `progressTrack` / `progressFill` | colour | — | The progress bar |
| `rimLight` / `rimWidth` | colour, 0…2 | white 16%, 0.6 | Glow along the edge |
| `useLiquidGlass` | yes/no | yes | Glass in the lower part of the expanded island |
| `glassStyle` | `clear` / `regular` | `clear` | `regular` is frosted. The system has a say too, through the Liquid Glass slider in Appearance |
| `glassTint` | colour or empty | black 34% | Glass tint. Without it the island washes out on a light background: the glass goes almost white and the white buttons disappear |
| `glassInteractive` | yes/no | yes | Glass responds to the cursor |
| `activateForGlass` | yes/no | yes | The system only renders liquid glass in a key window, so the island takes key focus when it expands. With this off the glass degrades to a flat blur |
| `releaseKeyAfterGlass` | yes/no | yes | Give the key focus straight back after drawing. Verified: the glass survives losing key and stays alive, so the window underneath loses focus only for an instant |
| `releaseKeyDelay` | 0.1…1 s | 0.45 | How soon to give the focus back |

## Animation — `motion`

| Key | Type | Default | What it does |
|---|---|---|---|
| `openResponse` / `openDamping` | 0.1…1 | 0.34 / 0.95 | The expansion spring. Damping below 0.8 gives a visible wobble |
| `closeResponse` / `closeDamping` | 0.1…1 | 0.28 / 1.0 | The collapse spring |
| `contentResponse` / `contentDamping` | 0.1…1 | 0.24 / 1.0 | Content changes: track, artwork |

## Behaviour — `behavior`

| Key | Type | Default | What it does |
|---|---|---|---|
| `expandOnHover` | yes/no | no | Expand fully on hover rather than on a click |
| `hoverShowsMedia` | yes/no | yes | Show the track on hover |
| `hoverOpenDelay` | 0…2 s | 0.45 | Delay before expanding, if hover expansion is on |
| `hoverCloseDelay` | 0…2 s | 0.35 | Delay before collapsing after the cursor leaves |
| `dismissOnOutsideClick` | yes/no | yes | Collapse the expanded island on a click outside it, and when switching to another app |
| `displayMode` | choice | `notchedOrMain` | Where to show it: the notched screen or the main one, main only, follow the mouse, or all screens |
| `alwaysUseNotchShape` | yes/no | yes | Use the notch shape on screens without a notch too |
| `showVolumeHUD` | yes/no | yes | HUD when the volume changes |
| `showBrightnessHUD` | yes/no | yes | HUD when the brightness changes |
| `showPowerHUD` | yes/no | yes | HUD when power is connected or disconnected |
| `showLowBatteryWarning` | yes/no | yes | Warn when the battery runs low |
| `lowBatteryThreshold` | 5…50 % | 20 | The percentage to warn at |
| `warningDuration` | 2…15 s | 6 | How long the warning stays — longer than a HUD, there is a button to hit |
| `hudDuration` | 0.5…5 s | 1.6 | How long a HUD stays |
| `showLiveActivities` | yes/no | yes | Groundwork for pop-up activities |
| `liveActivityDuration` | 1…10 s | 3 | How long those stay |

## Planned

| Setting | Status | What's known |
|---|---|---|
| Scrubbing on the progress bar | not done | The bar should be draggable to seek, and grow thicker while held — the way the iPhone player does it. Needs a drag gesture on `ProgressBarView` plus a seek command in `MediaProvider`: AppleScript can set `player position` in both Spotify and Music, so the scriptable sources can do it; the CoreAudio source can't and should keep the bar read-only |
| Equalizer lags during the morph | bug | The last bar of the equalizer trails behind the rest while the island expands or collapses. Most likely the `WaveformView` bars get their own implicit animation from the level updates, which fights the spring driving the morph — the same class of problem as the glass that used to run ahead of the island. Worth checking whether pinning the bar heights to the phase animation fixes it |
| Turning off the glass saturation boost | not done | Liquid Glass tints and intensifies the colours behind it. Over dark artwork or a busy wallpaper this is noticeable, and not everyone wants it. There is no public API: `NSGlassEffectView` exposes only `style`, `tintColor`, `cornerRadius` and `effectIsInteractive`. Among the private properties, `_tintOpacityReduced`, `_vibrantBlendingStyleForSubtree`, `_variant` and `_subvariant` look related — they need to be tried one by one on the bench (`--glass-lab`) to see which one kills the tinting. If none of them fits, the fallback is a compensating layer above the glass with inverse saturation |

## Worth remembering

- **Liquid glass needs a key window at the moment it is drawn.**
  `NSGlassEffectView` in a non-key window renders a flat blur. But the key
  status is only needed for the composition itself: after that the effect
  lives on its own and the focus can be handed back — verified, and on by
  default (`releaseKeyAfterGlass`). The settings UI has to explain this pair,
  otherwise anyone who turns `activateForGlass` off will think the glass broke.
- **Blur in animations is not an option.** `blur` in SwiftUI creates a
  rasterised layer, and in a transparent window its snapshot stays on screen
  after the island collapses. Softness comes from scale and opacity instead.
- **Previews can be rendered without launching the UI:**
  `swift run LiquidIsland --render-preview ./preview` draws every phase to PNG.
- **The glass bench:** `--glass-lab` shows the variants side by side. Useful
  whenever the effect has to be told apart from an imitation of it.
