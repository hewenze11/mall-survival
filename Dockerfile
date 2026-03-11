FROM node:20-alpine
WORKDIR /app

# Copy server dependency files
COPY server/package*.json ./
RUN npm ci --only=production

# Copy compiled artifacts (pre-built in CI)
COPY server/dist/ ./dist/

# CRITICAL: Copy config directory from project root into image
COPY config/ ./config/

EXPOSE 2567
ENV NODE_ENV=production
CMD ["node", "dist/index.js"]
