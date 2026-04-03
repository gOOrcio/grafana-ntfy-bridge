FROM --platform=$BUILDPLATFORM golang:1.23-alpine AS build
ARG TARGETARCH
WORKDIR /app
COPY go.mod ./
COPY *.go ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=$TARGETARCH go build -ldflags="-s -w" -o bridge .

FROM alpine:3.20.3
RUN addgroup -g 1000 bridge && adduser -u 1000 -G bridge -s /bin/sh -D bridge
COPY --from=build /app/bridge /bridge
USER bridge
EXPOSE 4000
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:4000/health || exit 1
ENTRYPOINT ["/bridge"]
