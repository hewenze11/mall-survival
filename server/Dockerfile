FROM node:20-alpine
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install production dependencies only
RUN npm ci --only=production

# Copy source and build artifacts
COPY . .

# Build TypeScript
RUN npm install && npm run build

EXPOSE 2567

CMD ["node", "dist/index.js"]
