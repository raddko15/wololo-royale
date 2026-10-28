# Multiplayer relay

A tiny Node server that pairs two players by a 4-letter room code and passes
their messages on. The host's device runs the game; the relay only forwards.

## Run it locally

    cd server
    npm install
    PORT=8080 npm start

Then open the web build with `?relay=ws://127.0.0.1:8080` added to its address
(or set `network.relay_url` in `data/config.json`).

## Deploy on Fly.io

1. Install flyctl: https://fly.io/docs/flyctl/install/ and sign in: `fly auth login`
2. From this folder: `fly launch --copy-config --no-deploy`
   (keep the settings; if the name `wololo-royale-relay` is taken, pick another)
3. `fly deploy`
4. Check it: `https://<app name>.fly.dev` answers `ok`.
5. If the app name differs, put `wss://<app name>.fly.dev` in
   `network.relay_url` in `data/config.json`.

It stops when nobody plays (no cost) and wakes on the first connection, which
takes a couple of seconds.
