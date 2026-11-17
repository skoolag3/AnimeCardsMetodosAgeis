FROM node:22-alpine AS migrate
WORKDIR /app
RUN apk add --no-cache openssl
COPY migration/package*.json ./
RUN npm ci --ignore-scripts --no-audit --no-fund
COPY prisma.config.ts ./
COPY prisma ./prisma
CMD ["./node_modules/.bin/prisma", "migrate", "deploy"]

FROM node:22-alpine AS build
WORKDIR /app
ENV DATABASE_URL=postgres://animecards:build@localhost:5432/animecards
RUN apk add --no-cache openssl
COPY package*.json prisma.config.ts ./
COPY prisma ./prisma
RUN npm ci
COPY nest-cli.json tsconfig*.json ./
COPY src ./src
RUN npm run build

FROM node:22-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production PORT=3001
RUN apk add --no-cache openssl
COPY package*.json ./
RUN npm ci --omit=dev --ignore-scripts --no-audit --no-fund
COPY --from=build /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=build /app/dist ./dist
EXPOSE 3001
CMD ["node", "dist/main.js"]
