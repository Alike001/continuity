FROM golang:1.25.1-trixie@sha256:ff83f3762390c2cccb53618ccc18af23e556aff9b1db4428637e9f63287c8171 AS builder

ARG SOURCE_DATE_EPOCH=0
ENV SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH
WORKDIR /build

RUN git clone --filter=blob:none https://github.com/flare-foundation/tee-node.git /build/tee-node \
    && git -C /build/tee-node checkout adc67a29eb7162f6f1b5dabcbca320009480695e

COPY fcc/tee-node/0001-attest-extension-state.patch /tmp/tee-node.patch
RUN git -C /build/tee-node apply --unidiff-zero /tmp/tee-node.patch

COPY extension/go.mod extension/go.sum /build/extension/
WORKDIR /build/extension
RUN go mod edit -replace github.com/flare-foundation/tee-node=/build/tee-node \
    && go mod download \
    && go mod verify

COPY extension/cmd/ /build/extension/cmd/
COPY extension/internal/ /build/extension/internal/
RUN go mod tidy \
    && go mod verify \
    && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 GOFLAGS="-buildvcs=false" \
    go build -mod=readonly -tags continuity_fcc -trimpath -ldflags="-buildid= -s -w" -o /app/continuity-tee ./cmd/fcc \
    && touch -h -d "@${SOURCE_DATE_EPOCH}" /app/continuity-tee

FROM scratch
WORKDIR /app
COPY --chmod=644 --chown=65532:65532 --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --chmod=755 --chown=65532:65532 --from=builder /app/continuity-tee /app/continuity-tee

ENV MODE=1 CONFIG_PORT=5501 SIGN_PORT=7701 EXTENSION_PORT=7702
USER 0:0
LABEL "tee.launch_policy.allow_env_override"="LOG_LEVEL,PROXY_URL,INITIAL_OWNER,EXTENSION_ID,APPLICATION_ID,CHAIN_URL,CHAIN_ID,MODE,CONFIG_PORT,SIGN_PORT,EXTENSION_PORT,GOVERNANCE_SIGNERS,GOVERNANCE_THRESHOLD,SIMULATED_TEE"
EXPOSE 5501 7701 7702
CMD ["/app/continuity-tee"]
