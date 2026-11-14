# Phantom-Ops

Mobile FPS — **Phantom Ops: Kasserine Operations**. Godot 4.2, Mobile renderer,
Android (arm64-v8a). No external art assets: the whole city, textures, weapon
and sounds are generated procedurally in GDScript at runtime.

## v0.3 — Working FIRE, big HUD, sound, richer city

- **FIRE fixed (was broken in v0.2.1)**: the HUD drew FIRE at one place and
  tested taps in a different, hard-coded rectangle, so tapping the FIRE
  centre actually jumped. Hit tests are now distance-to-centre tests
  against the same shared layout the drawing uses, for FIRE / JUMP / RUN /
  joystick / pause. Holding FIRE auto-fires (~8 shots/s, gated by the
  0.12 s fire cooldown). Every shot also shows a tracer line + impact
  puff, muzzle flash, recoil and camera kick, and ammo always decreases.
- **Bigger HUD**: buttons are ~1.7x — FIRE radius ~72, JUMP ~56, RUN ~54,
  joystick ~125, pause ~40 (scaled by viewport, 0.9–1.8x), with larger
  fonts, health bar, status bar and ammo text. Buttons no longer overlap.
- **Sound (new, no audio files)**: `scripts/sound_manager.gd` generates
  every sound as 16-bit PCM at runtime — gunshot, reload clicks, hit blip,
  kill two-tone, enemy death, hurt thud, UI click, wave horn, footsteps
  and a looping desert-wind ambience. Mute toggle in the pause menu
  (SOUND: ON/OFF), shared across scenes.
- **Richer city**: crosswalks + stop lines at intersections, tyre tracks,
  dirt patches, street-name signs, bollards, barrels, tyre stacks, market
  baskets, palm fronds, balconies, satellite dishes, laundry lines,
  facade shutters / mullions / AC boxes / balcony rails, sun disc + soft
  clouds, and drifting dust motes. Rendering stays Mobile-safe
  (colour background, no ProceduralSky / fog / ACES / MSAA — see v0.2.1).
- **Detail elsewhere**: rifle viewmodel now has sight, handguard, magazine,
  stock, suppressor and a left hand; enemies have arms, a vest plate and
  a red headband stripe.

## v0.2.1 — Black-screen fix

The v0.2 APK ran, and the HUD drew perfectly, but the 3D view was pure
black on Android. Root cause: the Sky-based `WorldEnvironment`
(`ProceduralSkyMaterial` + Sky ambient + fog + ACES tonemapping) does not
render on the Mobile renderer on device, even though the scene runs fine
headless. Fix: `main_game.tscn` now uses a Mobile-safe colour background
(warm sky blue) + colour ambient (0.9), Filmic tonemapping, fog off, glow
off; the warm directional sun (energy 1.15, shadows on) is unchanged, and
`kasserine_city_generator.gd` creates the same environment at runtime if
none exists. Also fixed: landscape orientation (`orientation=0`, was
portrait `1` — the v0.2 screenshot was a tall portrait phone), MSAA 3D off
(was 2x), camera `fov=75, near=0.05, far=500`, and parse errors in
`city_expansion.gd:102` / `psx_world_dressing.gd:81`
(`Cannot infer type` — `side` from an untyped array literal is a Variant,
now `float(side)` with an explicit `float` type). Version `0.2.1` (code 3).

## v0.2 — Kasserine Rebuilt

- **Real city, ~300×300 m**: grid streets with asphalt roads, lane markings
  and pavement slabs, a central plaza / market square, and distinct districts
  — dense low medina in the west, tall modern blocks in the east, market
  stalls around the plaza, and a checkpoint / military edge in the north.
  60–90 buildings with varied heights, footprints and facade colours
  (sand / white / ochre / terracotta), parapets, rooftop AC units and water
  tanks, and awnings. Seeded (`City.seed`, default `20261114`), so the city
  is the same every run.
- **Props**: palm trees, street lamps, crates, sandbags, barriers, parked
  cars, market stalls, benches and rocks — shared meshes/materials, collision
  where it matters, spawn kept clear.
- **Graphics**: procedural runtime textures (`scripts/procedural_textures.gd`)
  — asphalt, sand, sidewalk tiles, plaza tiles, facades with windows and
  shutters. Warm directional sun with shadows, glow off (Mobile renderer).
  (v0.2 shipped a `ProceduralSkyMaterial` + fog + ACES here — that rendered
  black on Android, see v0.2.1 above.) Distant skyline silhouette, a minaret
  landmark, and a
  mountain ring (Jebel Chambi) so the city reads from afar.
- **Gameplay**: enemy waves (8+, growing to 12) spawned on streets/plaza
  away from the player, wired to `GameManager` score/kills; procedural rifle
  viewmodel with muzzle flash, light and recoil; 30-round magazine with
  auto-reload; HUD with health bar, ammo, score/kills/wave, compass strip,
  crosshair and hit marker.
- **Main menu**: sunset gradient, bigger title, `v0.2 — Kasserine Rebuilt`,
  controls line, DEPLOY button.

## Controls (touch)

| Control | Action |
|---|---|
| Left thumbstick | Move |
| Drag right side | Look |
| FIRE | Shoot — tap or hold to auto-fire (30-round mag, auto-reloads) |
| Ⅱ → SOUND | Toggle sound on/off in the pause menu |
| JUMP | Jump |
| RUN (hold) | Sprint |
| Ⅱ | Pause — Resume / Main Menu |

On desktop: WASD/arrows to move, mouse drag to look, on-screen FIRE/JUMP
buttons work with the mouse, `ui_accept` (Enter/Space) to sprint,
`ui_select` to jump.

## How to build (Android APK)

The APK is built by GitHub Actions — push to `main` and download the
`PhantomOps-Release-APK` artifact from the workflow run
(`.github/workflows/build-android.yml`, Godot 4.2.2, Android SDK 33).

Local check (needs Godot 4.2.2, no Android SDK required for validation):

```sh
godot --headless --editor --path project --quit
godot --headless --path project --check-only --script scripts/kasserine_city_generator.gd
```

Local APK (needs Android SDK 33 + export templates + Java 17):

```sh
godot --headless --path project --export-debug "Android" build/PhantomOps.apk
```

Package: `com.phantomops.kasserine`, version `0.3.0` (code 4), arm64-v8a,
immersive mode.

## Project layout

```
project/
  project.godot            Godot 4.2, Mobile renderer, MSAA off, landscape
  export_presets.cfg       Android preset, v0.3.0 / code 4
  scenes/
    main_menu.tscn         Sunset menu + DEPLOY
    main_game.tscn         WorldEnvironment, City, Player, EnemySpawner
  scripts/
    kasserine_city_generator.gd   Procedural city (~300 m, seeded)
    procedural_textures.gd        Runtime ImageTextures + shared materials
    player.gd               Movement, ammo/reload, rifle viewmodel, HUD wiring
    mobile_hud.gd           Touch controls + health/ammo/score/compass HUD (v0.3: big buttons, distance hit tests, hold-to-fire, sound toggle)
    sound_manager.gd        Procedural sounds (WAV generated at runtime, no assets)
    enemy_ai.gd             Chases player, visible body, take_damage()
    enemy_spawner.gd        Waves, spawn points, score wiring
    game_manager.gd         Score/kills (+ score_changed signal)
    main_menu.gd            DEPLOY -> main game
```
