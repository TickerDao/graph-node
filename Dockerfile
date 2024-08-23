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
    netcat \
    postgresql-client \
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
\n\
echo "Checking database locale..."\n\
DB_LOCALE=$(psql -tAc "SELECT datcollate FROM pg_database WHERE datname = current_database();" $POSTGRES_URL)\n\
echo "Current database locale: $DB_LOCALE"\n\
if [ "$DB_LOCALE" != "C" ]; then\n\
    echo "Database locale is not C. Please note that this may cause issues with Graph Node."\n\
    echo "To fix this, you may need to create a new database with the correct locale:"\n\
    echo "CREATE DATABASE graph_node WITH TEMPLATE template0 LC_COLLATE '"'"'C'"'"' LC_CTYPE '"'"'C'"'"';"\n\
    echo "Then, update your POSTGRES_URL to use the new database."\n\
fi\n\
\n\
echo "Initializing IPFS..."\n\
if [ ! -f /root/.ipfs/config ]; then\n\
    ipfs init\n\
fi\n\
\n\
echo "Starting IPFS daemon..."\n\
ipfs daemon &\n\
IPFS_PID=$!\n\
\n\
# Wait for IPFS to start\n\
echo "Waiting for IPFS to start..."\n\
for i in {1..30}; do\n\
    if nc -z localhost 5001; then\n\
        echo "IPFS is up!"\n\
        break\n\
    fi\n\
    if [ $i -eq 30 ]; then\n\
        echo "Timed out waiting for IPFS to start"\n\
        exit 1\n\
    fi\n\
    sleep 1\n\
done\n\
\n\
# Test IPFS connection\n\
echo "Testing IPFS connection..."\n\
ipfs id\n\
\n\
echo "Starting Graph Node..."\n\
graph-node \
    --postgres-url "$POSTGRES_URL" \
    --ethereum-rpc "$ETHEREUM_RPC_URL" \
    --ipfs "localhost:5001"\n\
\n\
# If graph-node exits, kill IPFS daemon\n\
kill $IPFS_PID\n' > /usr/local/bin/start.sh && \
    chmod +x /usr/local/bin/start.sh

# Start the Graph Node using the startup script
CMD ["/usr/local/bin/start.sh"]
