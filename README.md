# Phantom-Ops

Mobile FPS — **Phantom Ops: Kasserine Operations**. Godot 4.2, Mobile renderer,
Android (arm64-v8a). The whole city, textures, weapon and sounds are
generated procedurally in GDScript at runtime. One exception: the hero is
Aymen's own 3D scan (`project/assets/characters/aymen.glb`, LowPoly).

## v0.5 — Death flow fixed + GTA IV-style grit

- **Death no longer dead-ends the game (was reported as a crash)**:
  `player_died` used to be emitted with nothing listening — the player
  froze, enemies swarmed the corpse, and there was no screen, no retry,
  no way out except force-closing the app. Now `mobile_hud.gd` shows a
  full-screen YOU DIED overlay (dark red wash, final SCORE / KILLS /
  WAVE, big RETRY + MAIN MENU buttons), `player.gd` stops the waves on
  death, `enemy_spawner.gd` gains `stop_waves()`, and `enemy_ai.gd`
  stops moving and attacking when its target `is_dead`. RETRY reloads
  `main_game.tscn` cleanly with a fresh HUD (verified headless: death
  → overlay shown → RETRY → new player alive at 100 HP, one HUD layer).
  A low death sting was added to `sound_manager.gd`.
- **GTA IV look (honest scope)**: this is still Godot 4.2 Mobile with
  procedural geometry — it cannot literally be Rockstar's RAGE engine —
  but v0.5 pushes the whole game toward that gritty, desaturated dusk
  Liberty City look: darker dusk sky + dim warm ambient (still
  BG_COLOR + COLOR ambient, Filmic, **no Sky / fog / ACES / MSAA** —
  see v0.2.1), low warm sun with longer shadows, mobile shadow size
  raised to 2048, grime/stain/soot/oil/crack textures on facades and
  roads, some windows lit warm, 3D windows with real depth on tall
  buildings, cornices, drain pipes, rooftop water tanks + antennas,
  more balconies, real warm light pools from lamps near the plaza,
  cars with windshields / bumpers / headlights / hubcaps, fuller
  market stalls, more dust and clouds. Enemies now have three uniform
  palettes, varied skin tones, boots, backpacks, vest pouches and a
  walk cycle; the rifle viewmodel gains a rail, charging handle,
  front sight and butt pad.

## v0.4 — AAA Kasserine: drone intro, live menu, mosque, citizens, voices

- **Drone intro cinematic** (`scenes/intro.tscn`, `scripts/intro_cinematic.gd`):
  the camera starts ~175 m over Kasserine at dawn, flies down over the
  plaza / minaret / market in ~11 s, and descends to Aymen standing at the
  player spawn — then the view becomes his first-person view and the game
  starts. Big SKIP button (any tap after 2 s also skips), "DRONE CAM"
  label, title fade, wind + whoosh sound. The flyover shows the real city
  (same generator), no enemies during the intro.
- **AAA main menu**: the menu is now a live 3D scene — the real Kasserine
  city behind the UI with a slow orbiting camera and Aymen standing in the
  plaza ("AYMEN — PHANTOM"). Huge PHANTOM OPS title, "KASSERINE — TUNISIA",
  large DEPLOY / HOW TO PLAY / SOUND: ON buttons, v0.4 label and controls
  line. DEPLOY goes through the drone intro. If the 3D city ever fails to
  build, a dark gradient is shown instead so the menu never goes black.
- **Mosque**: a proper mosque in the south-west block — prayer hall with
  Islamic geometric-pattern walls (8-pointed stars, geometric only, no
  text), big teal dome + small dome, gold crescent finial, two minarets,
  courtyard with colonnade and hanging lanterns, arched doorway. Low
  medina buildings also get small domes and arched doorways.
- **Citizens** (`scripts/citizen_spawner.gd`, `scripts/citizen.gd`): 24
  Tunisian civilians walk the sidewalks and plaza — men in long jebba +
  chechia (some bearded), women in long dress + hijab in several colours.
  They walk, pause and flee enemies. **Civilians are never targets**:
  they have no `take_damage`, and `player.gd` explicitly skips any hit
  collider in group "civilian" (no damage, no hit sound, no hitmarker,
  no impact puff). Enemies are the only targets.
- **Hero — Aymen** (`scripts/hero_aymen.gd`): Aymen's own 3D scan
  (`assets/characters/aymen.glb`, 3.9 MB LowPoly, head + torso, no legs)
  is the hero only — menu hero and intro ending. The figure is completed
  with a procedural long jebba robe below the scan, so he stands as a
  full figure. If the GLB ever fails to load, a procedural fallback hero
  is built instead. He is never an enemy or a target.
- **Voices / ambience**: market murmur loop (procedural), and Tunisian
  greetings ("Salam", "Marhaba", "Salam alaykum", "Ahla wa sahla") spoken
  via the OS text-to-speech when you walk close to a citizen — best
  effort only, guarded by `DisplayServer.has_feature(FEATURE_TEXT_TO_SPEECH)`
  and throttled to one greeting per 8 s, so a device without TTS simply
  stays silent. VOICES: ON/OFF toggle in the pause menu next to SOUND.
  No prayer audio is synthesised.
- **Icon + no Godot splash**: `icon.png` (512×512, gold minaret +
  Kasserine mountains + "PO" on dark navy) is the app icon
  (`config/icon`), and `boot_splash/show_image=false` with a dark
  background, so the Godot logo never shows on startup.
- **Graphics**: facade textures raised to 256×256, shop signs
  ("SOUK", "CAFE", "BAKERY", "PHARMACIE", "BOULANGERIE", "EPICERIE") on
  market stalls, hanging lanterns in the mosque courtyard. Rendering
  stays Mobile-safe (colour background, Filmic, no Sky / fog / ACES /
  MSAA — see v0.2.1).

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

Package: `com.phantomops.kasserine`, version `0.6.0` (code 7), arm64-v8a,
immersive mode. App icon: `icon.png` (512×512); Godot boot splash off.

## v0.5 — death screen fix, GTA IV dusk graphics

YOU DIED overlay (score/kills/wave, RETRY + MAIN MENU), spawner stops,
enemies idle when the player is dead. Gritty desaturated dusk palette,
grime/stains, 3D recessed windows (~22% lit), cornices, drain pipes,
rooftop tanks/antennas, more balconies, shadow mobile 2048, low warm sun,
6 lamp OmniLights, 11 clouds, 60 dust motes, detailed cars/enemies/rifle.
City 73 buildings.

## v0.6 — Kasserine Police (massive upgrade)

- **Languages:** FR / EN / العربية switch in the menu (74 keys × 3
  languages, Noto Naskh Arabic font, persisted). HUD, pause menu, death
  screen and mission text all translated.
- **Police missions:** the player is a Kasserine police officer.
  RESPOND (stop a robbery), HELP (aid a poor citizen), CHASE (catch a
  fleeing criminal), PATROL (3 checkpoints) — chained, repeatable,
  rewards in dinars + XP, objective beacon + HUD panel.
- **Citizens:** rebuilt skeleton (two-segment arms/legs, hands, feet,
  varied heights/builds), walk/idle/chat/suspicious/beg/flee states,
  speech bubbles, conversations in pairs, funny lines, ~15% criminals
  in disguise, ~20% poor citizens asking for help.
- **Interaction + money:** dinars in the HUD. HELP / GIVE (10 DT, +score)
  / CHECK prompts near citizens. Civilians stay non-targetable by gunfire.
- **Cars:** 10 traffic cars on road loops with procedural engine sounds.
  Drivable police car (white/blue, POLICE markings, red/blue light bar,
  siren, ENTER/EXIT, arcade driving with the joystick).
- **Adhan:** a REAL human adhan ("Beautiful adhan", CC0 public domain,
  Wikimedia Commons, 2 min 34 s) plays in full from the mosque at dusk,
  with an ADHAN ON/OFF toggle in the menu. Never looped, never synthesised.
- **Day/night + rain:** 4-minute cycle (BG_COLOR only — no Sky/fog, the
  v0.2 black-screen cause), night lamps + lit windows, occasional rain
  with thunder + lightning flash, on-screen clock.
- **Buildings:** real 3D depth — recessed windows, protruding balconies
  with railings, arched doorways, shop fronts with awnings, steps,
  rooftop structures. City filled with benches, bins, palms, bus stops,
  fountain, crates, signs. City 74 buildings.
- **Hero:** high-detail PBR scan of Aymen (33 MB, 32,768 verts) is now
  the default hero, LowPoly kept as fallback. Expected APK ~55–65 MB.

## Project layout

```
project/
  project.godot            Godot 4.2, Mobile renderer, MSAA off, landscape
  export_presets.cfg       Android preset, v0.4.0 / code 5
  icon.png                 App icon (512×512, gold minaret + PO)
  assets/characters/aymen.glb   Aymen's own 3D scan (hero only)
  scenes/
    main_menu.tscn         Live 3D city menu + DEPLOY / HOW TO PLAY / SOUND
    intro.tscn             Drone flyover cinematic -> main game
    main_game.tscn         WorldEnvironment, City, Player, EnemySpawner, CitizenSpawner
  scripts/
    kasserine_city_generator.gd   Procedural city (~300 m, seeded) + mosque
    procedural_textures.gd        Runtime ImageTextures + shared materials (256px facades, geometric pattern)
    player.gd               Movement, ammo/reload, rifle viewmodel, HUD wiring, civilian-safe fire, greetings
    mobile_hud.gd           Touch controls + health/ammo/score/compass HUD (v0.3: big buttons, distance hit tests, hold-to-fire, sound + voices toggles)
    sound_manager.gd        Procedural sounds (WAV generated at runtime, no assets) + murmur, whoosh, TTS greetings
    hero_aymen.gd           Aymen scan + jebba robe hero builder (menu + intro)
    citizen_spawner.gd      Spawns 24 civilians (men/women) from citizen.gd
    citizen.gd              Tunisian civilians: jebba/chechia, dress/hijab, walk + flee
    intro_cinematic.gd      Drone camera flight, title fade, SKIP, handover
    enemy_ai.gd             Chases player, visible body, take_damage()
    enemy_spawner.gd        Waves, spawn points, score wiring
    game_manager.gd         Score/kills (+ score_changed signal)
    main_menu.gd            Live 3D menu, orbit camera, DEPLOY -> intro
```
