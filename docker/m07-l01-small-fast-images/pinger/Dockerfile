# syntax=docker/dockerfile:1
FROM golang:1.26.5-alpine3.23 AS build
WORKDIR /src
COPY go.mod main.go ./
# timetzdata: embed the time zone database in the binary
RUN CGO_ENABLED=0 go build -tags timetzdata -o /pinger .

FROM scratch
# scratch is empty: bring the CA certificates for HTTPS
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=build /pinger /pinger
ENTRYPOINT ["/pinger"]
