# syntax=docker/dockerfile:1
# v2: Node only builds; nginx serves the static files
FROM --platform=$BUILDPLATFORM node:22.23.3-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN --mount=type=cache,id=small-npm,target=/root/.npm \
    npm ci
COPY . .
RUN npm run build

FROM nginx:1.29.8-alpine
COPY --from=build /app/dist/ /usr/share/nginx/html/
