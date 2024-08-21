# Use the official Rust image as a parent image
FROM rust:latest as builder

  # Set the working directory in the container
WORKDIR /usr/src/graph-node

  # Copy the current directory contents into the container
COPY . .

  # Build the project
RUN cargo build --release

  # Use a smaller base image for the final image
FROM debian:buster-slim

  # Install necessary dependencies
RUN apt-get update && apt-get install -y libpq5 ca-certificates protobuf-compiler libprotobuf-dev && rm -rf /var/lib/apt/lists/*

  # Copy the build artifact from the builder stage
COPY --from=builder /usr/src/graph-node/target/release/graph-node /usr/local/bin/graph-node

  # Set environment variables
ENV RUST_LOG=info

  # Expose necessary ports
EXPOSE 8000 8001 8020

  # Run graph-node when the container launches
CMD ["graph-node", \
"--postgres-url", "${POSTGRES_URL}", \
"--ethereum-rpc", "${ETHEREUM_RPC_URL}", \
"--ipfs", "${IPFS_ADDRESS}"]
