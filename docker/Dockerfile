# Integra Layer Validator Node
# Multi-stage build: compile intgd from source, then copy into lean runtime.

# ---- Stage 1: Build ----
FROM golang:1.24-alpine AS builder
WORKDIR /work
ENV PACKAGES="curl build-base git bash file linux-headers eudev-dev"
RUN apk add --no-cache $PACKAGES

COPY go.mod go.sum* ./
COPY integra/go.mod integra/go.sum* integra/
RUN cd integra && go mod download

COPY . .
RUN LEDGER_ENABLED=false COSMOS_BUILD_OPTIONS="staticlink" BUILD_TAGS=muslc make build
RUN file /work/build/intgd

# ---- Stage 2: Runtime ----
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    curl jq wget ca-certificates bc \
    && rm -rf /var/lib/apt/lists/*

# Copy binary and scripts
COPY --from=builder /work/build/intgd /usr/local/bin/intgd
COPY docker/entrypoint.sh /usr/local/bin/entrypoint
COPY docker/lib.sh /usr/local/bin/lib.sh
COPY docker/setup-wizard.sh /usr/local/bin/setup-wizard
RUN chmod +x /usr/local/bin/intgd /usr/local/bin/entrypoint /usr/local/bin/setup-wizard

EXPOSE 26656 26657 1317 9090 8545 8546

VOLUME ["/root/.intgd"]

ENTRYPOINT ["entrypoint"]
CMD ["start"]
