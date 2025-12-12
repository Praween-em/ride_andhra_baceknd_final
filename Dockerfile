# Base stage
FROM node:20-alpine AS base

# Development stage
FROM base AS development
WORKDIR /usr/src/app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

# Production stage
FROM base AS production
ARG NODE_ENV=production
ENV NODE_ENV=${NODE_ENV}
WORKDIR /usr/src/app
COPY package*.json ./
RUN npm install --only=production
COPY --from=development /usr/src/app/dist ./dist
# Copy database folder for migrations if needed or handle separately
COPY --from=development /usr/src/app/database ./database 

EXPOSE 3000
CMD ["npm", "run", "start:prod"]
