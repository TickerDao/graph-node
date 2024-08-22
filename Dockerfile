# Build stage
FROM rust:latest AS builder

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
    && rm -rf /var/lib/apt/lists/*

# Set the working directory in the container
WORKDIR /usr/src/graph-node

# Copy the current directory contents into the container
COPY . .

# Build the project
RUN cargo build --release

# Runtime stage
FROM debian:buster-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libpq5 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy the build artifact from the builder stage
COPY --from=builder /usr/src/graph-node /usr/src/graph-node

# Set environment variables
ENV RUST_LOG=info

# Expose necessary ports
EXPOSE 8000 8001 8030

# Create a startup script
RUN echo '#!/bin/bash\n\
set -e\n\
echo "Environment variables:"\n\
env | grep -E "POSTGRES_URL|ETHEREUM_RPC_URL|RUST_LOG"\n\
echo "Starting Graph Node..."\n\
cd /usr/src/graph-node && \
cargo run -p graph-node --release -- \
    --postgres-url "$POSTGRES_URL" \
    --ethereum-rpc "$ETHEREUM_RPC_URL" \
    --ipfs "https://ipfs.network.thegraph.com"\n' > /usr/local/bin/start.sh && \
    chmod +x /usr/local/bin/start.sh

# Start the Graph Node using the startup script
CMD ["/usr/local/bin/start.sh"]
