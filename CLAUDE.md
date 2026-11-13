# Wololo Royale

A portrait strategy game in Godot 4.3 for Android and the web: Age of Empires 2
economy and eras (villagers, huts, eras, upgrades, three civs: Romans, Greeks,
Franks) with Clash Royale lanes (three lanes, towers, a town center to destroy).
Low-poly 3D look (the old 2D look is kept on branch `2d`). Single player against
the computer, or online with a friend.

## Working with the owner

- The owner writes in Polish or English: answer in the language they wrote in.
- Work in small steps (10-20 minutes): one or two sentences on the plan before,
  a few short bullets after (what changed, what was checked, the link). Details
  only when asked. Ask about real choices; don't ask for permission on obvious ones.
- After every step: run the tests, commit, push to `main` (and keep `2.5d` equal:
  `git push origin main:2.5d`), build the web version and publish it to the
  artifact https://claude.ai/artifact/AVskfntPJfZ1aFkMEKSucX.
- Commit as `raddko15 <raddko15@gmail.com>`
  (`git -c user.name=raddko15 -c user.email=raddko15@gmail.com commit ...`).
  Never use the owner's work email in commits. End commit messages with the
  attribution lines the session gives; never put model names or ids in commits.
- Show screenshots of what changed (see below) before calling it done; for
  movement, a filmstrip of frames.

## Commands

    # tests (must end with "FAILURES: 0"; always wrap in timeout: script errors hang)
    timeout 120 ~/tools/godot --headless --path . -s res://tests/run_tests.gd
    # after adding a new class_name script
    ~/tools/godot --headless --path . --import
    # screenshot (modes: era1 era2 era2up era3 window mill mine jobs sites sites0
    # corpses start menu victory unique paused gather lobby hutsite leaving)
    xvfb-run -a -s "-screen 0 720x1440x24" ~/tools/godot --rendering-driver opengl3 \
      --path . --resolution 720x1440 -s res://tests/screenshot.gd -- OUT.png MODE [civ] [enemy civ]
    # web build (OUT: a folder in the session scratchpad), then publish OUT/index.html
    # with root OUT and files index.js, index.audio.worklet.js, game-data.wasm,
    # engine0.wasm, engine1.wasm, engine2.wasm, index.png, index.icon.png,
    # index.apple-touch-icon.png
    OUT=<scratchpad>/web tools/build_web.sh
    # computer vs computer balance check (A B games; "old:hard" = tests/baseline_ai.gd)
    timeout 600 ~/tools/godot --headless --path . -s res://tests/ai_sim.gd -- hard normal 2
    # two players through a local relay (start: cd server && PORT=8099 node relay.js)
    xvfb-run ... -s res://tests/net_e2e.gd -- OUT.png ws://127.0.0.1:8099

GDScript is strict: a `:=` on a Variant is an error, so give such variables a
type (`var x: float = ...`), and loop variables can't reuse a name in scope.

## How the code is laid out

- `data/config.json` - every rule and number (costs, times, units, eras,
  upgrades, AI levels, relay address, `testing` aids). Tests read times from it.
- `scripts/economy.gd` - one side's economy: resources, villagers and their
  walks (`workers`, `leaving`), build/train jobs, huts, towers per lane.
- `scripts/battlefield.gd` - the battle, one dimension per lane: each unit has
  `lane` and `y` (0 = player's tower line, 1 = enemy's; <0 / >1 on the roads to
  the forts). Lane orders (march/retreat; "stop" only for the AI), rally point
  behind the tower, siege places (7 melee per building per lane, the rest
  "queue"), at most 3 melee on one foe, towers, fort regen.
- `scripts/match.gd` - one game: both economies, the battle, the AI; players
  act only through commands `apply(team, {"op": ...})`.
- `scripts/enemy_ai.gd` - the computer opponent (build order, lanes, charges).
- Online: `net.gd` (WebSocket client), `snapshot.gd` (host -> guest state,
  flipped so the guest plays at the bottom), `mirror.gd` (the guest's copy),
  `lobby.gd`, relay server in `server/` (Node, deployed on Render:
  wss://wololo-royale.onrender.com; Docker from the root `Dockerfile`).
- `scripts/battle_view.gd` - the map's layout in pixels (every position is a
  map point), taps, flat ground drawing, and in 3D (`in_3d`) it records what
  people do into `figures_3d` instead of drawing them; buttons, labels and bars
  go over the 3D view via `draw_overlay()`.
- `scripts/crowd.gd` - troop movement on screen: each figure walks to a goal
  at its own pace and steers round neighbours (never jumps). Goals come from
  `BattleView.unit_positions()`: own place in a marching group, home block
  behind the tower, siege ring / queue block, next to its foe.
- `scripts/world_view.gd` - the 3D view: tilted camera, the map as the ground
  texture (laid out taller so lanes fill the screen), buildings, figures in
  batches, olive trees, scenery, testing zoom, auto quality.
- `scripts/models.gd` (buildings), `figures.gd` (troops, villagers, horses),
  `low_poly.gd` (shapes, merging, flat shading).
- UI: `main.gd` (screen, cards, menus), `start_screen.gd`, `radial_menu.gd`
  (building menus with emblems from `assets/art/emblem`), `unit_icon.gd`
  (card portraits from `assets/art/portrait`), `card.gd`, `ui_style.gd`.

## Branches and links

- `main` - the game (3D). `2.5d` - kept equal to `main`.
- `2d` - the 2D version before 3D. Artifact: https://claude.ai/artifact/S99LVP5bXY4nMEofjBLZCL
- `proto-one-lane` - one wide lane (config `map.one_lane`). Artifact:
  https://claude.ai/artifact/2jC5v35ygju22QA8b4uqsz
- `proto-merge` - lanes merge in the middle (owner rejected it).
- GitHub Pages (built from `main` by `.github/workflows/pages.yml`):
  https://raddko15.github.io/wololo-royale/ - the page friends play on.
