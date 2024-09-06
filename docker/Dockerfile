# Build stage for envsubst
FROM golang:bullseye as envsubst

# v1.2.0
ARG ENVSUBST_COMMIT_SHA=16035fe3571ad42c7796bf554f978bb2df64231b
# We ship `envsubst` with the final image to facilitate env. var. templating in
# the configuration file.
RUN go install github.com/a8m/envsubst/cmd/envsubst@$ENVSUBST_COMMIT_SHA \
    && strip -g /go/bin/envsubst

# Build stage for graph-node
FROM rust:bullseye AS graph-node-build

ARG COMMIT_SHA=unknown
ARG REPO_NAME="datachain-graph"
ARG BRANCH_NAME="alpha"
ARG TAG_NAME="flight"

ADD . /graph-node

# Install dependencies and build graph-node
RUN apt-get update && apt-get install -y \
    clang \
    cmake \
    libpq-dev \
    ca-certificates \
    protobuf-compiler \
    libprotobuf-dev \
    libssl-dev \
    pkg-config \
    postgresql \
    wget \
    && rm -rf /var/lib/apt/lists/* \
    && cd /graph-node \
    && RUSTFLAGS="-g" cargo build --release --package graph-node \
    && cp target/release/graph-node /usr/local/bin/graph-node \
    && cp target/release/graphman /usr/local/bin/graphman \
    # Reduce the size of the layer by removing unnecessary files.
    && cargo clean \
    && objcopy --only-keep-debug /usr/local/bin/graph-node /usr/local/bin/graph-node.debug \
    && strip -g /usr/local/bin/graph-node \
    && strip -g /usr/local/bin/graphman \
    && cd /usr/local/bin \
    && objcopy --add-gnu-debuglink=graph-node.debug graph-node \
    && echo "REPO_NAME='$REPO_NAME'" > /etc/image-info \
    && echo "TAG_NAME='$TAG_NAME'" >> /etc/image-info \
    && echo "BRANCH_NAME='$BRANCH_NAME'" >> /etc/image-info \
    && echo "COMMIT_SHA='$COMMIT_SHA'" >> /etc/image-info \
    && echo "CARGO_VERSION='$(cargo --version)'" >> /etc/image-info \
    && echo "RUST_VERSION='$(rustc --version)'" >> /etc/image-info \
    && echo "CARGO_DEV_BUILD='$CARGO_DEV_BUILD'" >> /etc/image-info

# Debug image to access core dumps
FROM graph-node-build as graph-node-debug
RUN apt-get update \
    && apt-get install -y curl gdb postgresql-client

COPY docker/Dockerfile /Dockerfile
COPY docker/bin/* /usr/local/bin/

# Runtime stage
FROM debian:bullseye-slim as graph-node

# Install runtime dependencies including full PostgreSQL
RUN apt-get update && apt-get install -y \
    libpq5 \
    ca-certificates \
    wget \
    netcat \
    postgresql \
    postgresql-contrib \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /var/lib/postgresql/data \
    && chown -R postgres:postgres /var/lib/postgresql/data \
    && chmod 700 /var/lib/postgresql/data

# Ensure PostgreSQL binaries are in PATH
ENV PATH="/usr/lib/postgresql/13/bin:${PATH}"

# Install IPFS
RUN wget https://dist.ipfs.tech/kubo/v0.18.1/kubo_v0.18.1_linux-amd64.tar.gz && \
    tar -xvzf kubo_v0.18.1_linux-amd64.tar.gz && \
    cd kubo && \
    bash install.sh && \
    cd .. && \
    rm -rf kubo_v0.18.1_linux-amd64.tar.gz kubo

# Set environment variables
ENV RUST_LOG="${RUST_BACKTRACE}"
ENV postgres_host="${POSTGRES_URL}"
ENV postgres_user="postgres"
ENV postgres_pass="${POSTGRES_PASSWORD}"
ENV postgres_db="graph-node"
ENV postgres_args="sslmode=prefer"
ENV ipfs="${IPFS_ADDRESS}"
ENV ethereum="${ETHEREUM_RPC_URL}"
ENV node_role="combined-node"

# Expose necessary ports
EXPOSE 8000 8001 8020 8030 8040 5001

# Copy necessary files and binaries
COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

ADD docker/wait_for docker/start /usr/local/bin/
COPY --from=graph-node-build /usr/local/bin/graph-node /usr/local/bin/graphman /usr/local/bin/
COPY --from=graph-node-build /etc/image-info /etc/image-info
COPY --from=envsubst /go/bin/envsubst /usr/local/bin/
COPY docker/Dockerfile /Dockerfile
COPY docker/config.toml /app/config/config.toml

CMD ["/usr/local/bin/start.sh"]
