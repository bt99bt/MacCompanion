FROM --platform=$BUILDPLATFORM golang:1.22-alpine AS build

ARG TARGETOS
ARG TARGETARCH

WORKDIR /src
COPY go.mod go.sum* ./

COPY . .
RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} go build -trimpath -ldflags="-s -w" -o /out/wifi-code-server .

FROM alpine:3.20

COPY --from=build /out/wifi-code-server /usr/local/bin/wifi-code-server

ENV HTTP_ADDR=:8080
ENV DNS_ADDR=:53
ENV BASE_DOMAIN=wifi-code.example.com
ENV HEALTH_ADDRESS=1.255.255.255
ENV EMPTY_ADDRESS=0.0.0.0
ENV DEFAULT_DNS_REPLY=0.0.0.0

EXPOSE 53/udp
EXPOSE 53/tcp
EXPOSE 8080/tcp

ENTRYPOINT ["/usr/local/bin/wifi-code-server"]
