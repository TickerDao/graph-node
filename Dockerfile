# Build stage
FROM rust:bullseye AS builder

# Install dependencies
RUN apt-get update && apt-get install -y \
    clang \
    libpq-dev \
    ca-certificates \
    protobuf-compiler \
    libprotobuf-dev \
    libssl-dev \
    pkg-config \
    postgresql \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Set the working directory in the container
WORKDIR /usr/src/graph-node

# Copy the current directory contents into the container
COPY . .

# Build the project
RUN cargo build --release

# Runtime stage
FROM debian:bullseye-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libpq5 \
    ca-certificates \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Install IPFS
RUN wget https://dist.ipfs.tech/kubo/v0.18.1/kubo_v0.18.1_linux-amd64.tar.gz && \
    tar -xvzf kubo_v0.18.1_linux-amd64.tar.gz && \
    cd kubo && \
    bash install.sh && \
    cd .. && \
    rm -rf kubo_v0.18.1_linux-amd64.tar.gz kubo

# Copy the build artifact from the builder stage
COPY --from=builder /usr/src/graph-node/target/release/graph-node /usr/local/bin/graph-node

# Set environment variables
ENV RUST_LOG=info

# Expose necessary ports
EXPOSE 8000 8001 8030 5001

# Create a startup script
RUN echo '#!/bin/bash\n\
set -e\n\
echo "Starting IPFS..."\n\
ipfs init\n\
ipfs daemon --offline &\n\
echo "Starting Graph Node..."\n\
graph-node \
    --postgres-url "$POSTGRES_URL" \
    --ethereum-rpc "$ETHEREUM_RPC_URL" \
    --ipfs "localhost:5001"\n' > /usr/local/bin/start.sh && \
    chmod +x /usr/local/bin/start.sh

# Start the Graph Node using the startup script
CMD ["/usr/local/bin/start.sh"]
