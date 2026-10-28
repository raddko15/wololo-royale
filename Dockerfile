# The multiplayer relay (server/), for Fly.io. The game itself is built
# separately (GitHub Pages).
FROM node:22-alpine
WORKDIR /app
COPY server/package.json server/package-lock.json ./
RUN npm ci --omit=dev
COPY server/relay.js ./
ENV PORT=8080
EXPOSE 8080
CMD ["node", "relay.js"]
