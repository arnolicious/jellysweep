# Fork-only image build (not part of upstream).
# Builds jellysweep from source and ships it on distroless, like release.Dockerfile.

# --- frontend assets (tailwind scans the .templ files for classes) ---
FROM --platform=$BUILDPLATFORM node:25-bookworm-slim AS assets
WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

# --- go binary ---
FROM --platform=$BUILDPLATFORM golang:1.27 AS build
ARG TARGETOS
ARG TARGETARCH
ARG VERSION=custom
ARG COMMIT=none
ARG DATE=unknown
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
COPY --from=assets /src/internal/static/static/dist ./internal/static/static/dist
RUN go tool templ generate
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath \
    -ldflags "-s -w \
      -X github.com/jon4hz/jellysweep/internal/version.Version=${VERSION} \
      -X github.com/jon4hz/jellysweep/internal/version.Commit=${COMMIT} \
      -X github.com/jon4hz/jellysweep/internal/version.Date=${DATE} \
      -X github.com/jon4hz/jellysweep/internal/version.BuiltBy=fork" \
    -o /out/jellysweep .

# --- runtime ---
FROM gcr.io/distroless/static@sha256:58133991db06659feaabe0f4e97a35cebf15ef4ea08f8a4c6d2ee5f75e4aa6a0

WORKDIR /app

VOLUME /app/data

# workaround to prevent slowness in docker when running with a tty
ENV CI="1"

EXPOSE 3002/tcp

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["/usr/local/bin/jellysweep", "healthcheck"]

ENTRYPOINT [ "/usr/local/bin/jellysweep"]
CMD [ "serve" ]

COPY --from=build /out/jellysweep /usr/local/bin/jellysweep
