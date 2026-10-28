# allcsvideos storefront (lab build): a static page on unprivileged nginx (port 8080).
FROM nginxinc/nginx-unprivileged:1.29.8-alpine
LABEL course=devops
ARG VERSION=1.4.0
USER root
RUN printf '<!doctype html><title>allcsvideos</title><h1>allcsvideos storefront %s</h1>\n' "$VERSION" > /usr/share/nginx/html/index.html
USER 101
