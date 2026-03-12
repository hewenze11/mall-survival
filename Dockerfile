FROM node:20-alpine
WORKDIR /app
COPY server/package*.json ./
RUN npm ci --only=production
COPY server/dist/ ./dist/
COPY config/ ./config/
EXPOSE 2567
ENV NODE_ENV=production
CMD ["node", "dist/index.js"]
