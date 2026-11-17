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

FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production PORT=3001
RUN apk add --no-cache openssl
COPY --from=build /app/package*.json /app/prisma.config.ts ./
COPY --from=build /app/prisma ./prisma
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
EXPOSE 3001
CMD ["node", "dist/main.js"]
