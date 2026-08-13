FROM golang:1.25.8-alpine@sha256:8e02eb337d9e0ea459e041f1ee5eece41cbb61f1d83e7d883a3e2fb4862063fa AS builder

ARG TEE_PROXY_REF=v0.0.18
WORKDIR /build
RUN apk add --no-cache git \
    && git clone --depth 1 --branch "$TEE_PROXY_REF" https://github.com/flare-foundation/tee-proxy.git /build/tee-proxy

WORKDIR /build/tee-proxy
RUN go mod download && go mod verify
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 GOFLAGS="-buildvcs=false" \
    go build -mod=readonly -trimpath -ldflags="-buildid= -s -w" -o /app/tee-proxy ./cmd/proxy

FROM alpine:3.23@sha256:fd791d74b68913cbb027c6546007b3f0d3bc45125f797758156952bc2d6daf40
WORKDIR /app
RUN addgroup -g 1001 -S appgroup && adduser -u 1001 -S appuser -G appgroup
COPY --chmod=755 --chown=1001:1001 --from=builder /app/tee-proxy /app/tee-proxy
USER 1001:1001
EXPOSE 6663 6664
CMD ["/app/tee-proxy"]
