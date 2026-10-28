# Multiplayer relay

A tiny Node server that pairs two players by a 4-letter room code and passes
their messages on. The host's device runs the game; the relay only forwards.

## Run it locally

    cd server
    npm install
    PORT=8080 npm start

Then open the web build with `?relay=ws://127.0.0.1:8080` added to its address
(or set `network.relay_url` in `data/config.json`).

## Deploy on Render

The relay runs on Render's free plan as a Docker web service, from the
`Dockerfile` at the top of the repo (Root Directory empty, Dockerfile Path
`./Dockerfile`, no environment variables: Render sets `PORT`). It redeploys on
every commit to main; Build Filters with Included Paths `server/**` and
`Dockerfile` keep game-only commits from restarting it.

`https://<service name>.onrender.com` answers `ok`; the game connects to
`wss://<service name>.onrender.com` (`network.relay_url` in `data/config.json`).
Free services sleep after about 15 minutes without players; the first one to
connect then waits up to a minute while it wakes.
