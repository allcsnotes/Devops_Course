# allcsvideos lab service image (M18-L04): a tiny HTTP service on port 8080 plus the client tools the lab needs
# (curl, jq, psql/pg_isready). Same image for catalog and api; SVC and VERSION go into the page it serves.
FROM alpine:3.23.6
ARG SVC=catalog
ARG VERSION=1.0
RUN apk add --no-cache curl jq postgresql18-client busybox-extras \
 && mkdir -p /srv && echo "{\"service\":\"$SVC\",\"version\":\"$VERSION\"}" > /srv/index.html \
 && adduser -D -u 10001 app
USER 10001
EXPOSE 8080
CMD ["busybox-extras", "httpd", "-f", "-p", "8080", "-h", "/srv"]
