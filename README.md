# Age Royale

A portrait mobile strategy game in Godot 4.3: Age of Empires-style economy and eras,
Clash Royale-style lanes. Shapes-only graphics for now.

## Run tests
    godot --headless --path . -s res://tests/run_tests.gd

## Build for the web
    tools/build_web.sh        # writes ../build/web

Game rules and numbers live in `data/config.json`. Remove the `"testing"` block there
to go back to the normal 100 food / 100 wood start.
