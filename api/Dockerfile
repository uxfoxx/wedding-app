# API server. Runs TypeScript directly on Node 22 (no build step). Fits a 1 GB server.
FROM node:22-slim
ENV NODE_ENV=production
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY src ./src
COPY migrations ./migrations
EXPOSE 8080
# Keep Node's heap well inside a 1 GB machine shared with nothing else.
CMD ["node", "--max-old-space-size=384", "src/server.ts"]
