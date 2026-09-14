# syntax=docker/dockerfile:1
#
# Multi-stage build for herdr-relay-hub (docs/12-relay-hosting.md R-12-012).
# Build context is the repository root: `docker build -f crates/herdr-relay-hub/Dockerfile .`
#
# A developer workstation needs only a Docker client and Docker Engine for relay work.
# This Dockerfile owns the x86_64-unknown-linux-musl toolchain and every relay build
# dependency; nothing musl- or Rust-related is installed on the host.

FROM rust:1.98.0 AS chef
WORKDIR /workspace
RUN rustup target add x86_64-unknown-linux-musl \
    && rustup component add rustfmt clippy \
    && apt-get update \
    && apt-get install -y --no-install-recommends musl-tools ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY crates/Cargo.toml crates/rust-toolchain.toml ./
COPY crates/herdr-relay-proto ./herdr-relay-proto
COPY crates/herdr-relay ./herdr-relay
COPY crates/herdr-relay-hub ./herdr-relay-hub

# Test stage: formatter, the relay's strict clippy gate, and its tests
# (docs/41-code-standards.md R-41-114, R-41-115; docs/40-repo-tooling.md §7.2.3).
FROM chef AS test
RUN cargo fmt --check
RUN cargo clippy -p herdr-relay-hub --all-targets --all-features -- -D warnings
RUN sh -c "ulimit -n 65536 && cargo test -p herdr-relay-hub"

# Build stage: one static musl binary.
FROM chef AS build
RUN cargo build --release -p herdr-relay-hub --target x86_64-unknown-linux-musl

# Final stage: the binary and the CA certificate bundle only (R-12-012).
FROM scratch
COPY --from=build /workspace/target/x86_64-unknown-linux-musl/release/herdr-relay-hub /herdr-relay-hub
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
ENTRYPOINT ["/herdr-relay-hub"]
