# Age Royale

A portrait mobile strategy game in Godot 4.3: Age of Empires-style economy and eras,
Clash Royale-style lanes. Shapes-only graphics for now.

## Run tests
    godot --headless --path . -s res://tests/run_tests.gd

## Build for the web
    tools/build_web.sh        # writes ../build/web

Game rules and numbers live in `data/config.json`; its `"testing"` block holds the
Fast ×10 speed and the +10k button amount.

## Credits
- Font: [Cinzel](https://github.com/NDISCOVER/Cinzel) by Natanael Gama, SIL Open Font
  License 1.1 (`assets/fonts/Cinzel-OFL.txt`).
- All other art is made for this game (`assets/art`).
