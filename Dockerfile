# Use the official Rust image as a parent image
FROM rust:latest

# Install dependencies
RUN apt-get update && apt-get install -y \
    clang \
    libpq-dev \
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

  # Use a smaller base image for the final image
FROM debian:buster-slim

  # Set environment variables
ENV RUST_LOG=info

  # Expose necessary ports
EXPOSE 8000 8001 8030

  # Run graph-node when the container launches
CMD ["cargo", "run", "-p", "graph-node", "--release", "--", \
     "--postgres-url", "${POSTGRES_URL}", \
     "--ethereum-rpc", "${ETHEREUM_RPC_URL}", \
     "--ipfs", "https://ipfs.network.thegraph.com"]
