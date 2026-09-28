# syntax=docker/dockerfile:1

FROM golang:1.22-bookworm AS build
WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .

# TARGETOS/TARGETARCH are populated automatically by `docker buildx build --platform ...`,
# so the same Dockerfile cross-compiles for Raspberry Pi (linux/arm64) without changes.
ARG TARGETOS
ARG TARGETARCH
ARG BUILD_UPSTREAM_URL=https://api.integrations.mattermost.com

RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build \
    -ldflags="-s -w -X main.upstreamURL=${BUILD_UPSTREAM_URL}" \
    -o /out/marketplace ./cmd/marketplace

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app

COPY --from=build /out/marketplace /app/marketplace
COPY plugins.json /app/plugins.json

EXPOSE 8085
ENTRYPOINT ["/app/marketplace"]
CMD ["server", "--listen", ":8085"]
