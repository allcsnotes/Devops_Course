# syntax=docker/dockerfile:1
# allcsvideos storefront: Node only builds; unprivileged nginx serves (M07-L01, M07-L03)
FROM --platform=$BUILDPLATFORM node:22.23.3-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN --mount=type=cache,id=allcsvideos-npm,target=/root/.npm \
    npm ci
COPY index.html ./
COPY src/ src/
RUN npm run build

FROM nginxinc/nginx-unprivileged:1.29.8-alpine AS runtime
COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist/ /usr/share/nginx/html/
USER 101
EXPOSE 8080
HEALTHCHECK --interval=2s --timeout=2s --start-period=5s --retries=3 \
  CMD ["wget", "-q", "-O", "/dev/null", "http://127.0.0.1:8080/healthz"]
