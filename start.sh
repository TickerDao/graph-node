#!/bin/bash
set -e

# Function for logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}
# Debug information
log "initdb: $(locate initdb)"
log "Current user: $(whoami)"
log "Current directory: $(pwd)"
log "PGDATA: $PGDATA"
log "PATH: $PATH"
log "PostgreSQL version: $(psql --version)"
log "Listing PostgreSQL binaries:"
ls -l /usr/lib/postgresql/13/bin

# Ensure PGDATA is set
if [ -z "$PGDATA" ]; then
    PGDATA="/var/lib/postgresql/data"
    log "PGDATA was not set. Using default: $PGDATA"
fi

# Ensure the PGDATA directory exists
if [ ! -d "$PGDATA" ]; then
    log "Creating PGDATA directory: $PGDATA"
    mkdir -p "$PGDATA"
    chown postgres:postgres "$PGDATA"
    chmod 700 "$PGDATA"
fi

# Check PostgreSQL installation
if ! command -v psql &> /dev/null; then
    log "ERROR: PostgreSQL is not installed or not in PATH"
    log "PATH: $PATH"
    log "Installed packages:"
    dpkg -l | grep postgres
    exit 1
fi

# Check if PostgreSQL is initialized
PGDATA="${PGDATA:-/var/lib/postgresql/data}"
if [ -z "$(ls -A "$PGDATA")" ]; then
    echo "Initializing PostgreSQL..."
    mkdir -p "$PGDATA"
    chown -R postgres:postgres "$PGDATA"
    chmod 700 "$PGDATA"
    su - postgres -c "initdb -D /var/lib/postgresql/data -E UTF8 --locale=C"
    su - postgres -c "pg_ctl -D /var/lib/postgresql/data -E UTF8 --locale=C -l logfile start"

    su postgres -c "createdb graph-node -T template0 -E UTF8 --lc-collate='C' --lc-ctype='C'"
    su postgres -c "psql -d graph-node -c 'CREATE EXTENSION pg_trgm;'"
    su postgres -c "psql -d graph-node -c 'CREATE EXTENSION pg_stat_statements;'"
    su postgres -c "psql -d graph-node -c 'CREATE EXTENSION btree_gist;'"
    su postgres -c "psql -d graph-node -c 'CREATE EXTENSION postgres_fdw;'"
else
    echo "PostgreSQL data directory already initialized, starting PostgreSQL..."
    su postgres -c "pg_ctl -D $PGDATA -l logfile start"
fi


echo "Checking database locale..."
DB_LOCALE=$(psql -tAc "SELECT datcollate FROM pg_database WHERE datname = current_database();" $POSTGRES_URL)
echo "Current database locale: $DB_LOCALE"
if [ "$DB_LOCALE" != "C" ]; then
    echo "WARNING: Database locale is not C. This may cause issues with Graph Node."
    echo "To fix this, create a new database with the correct locale:"
    echo "CREATE DATABASE graph_node WITH TEMPLATE template0 LC_COLLATE 'C' LC_CTYPE 'C';"
    echo "Then, update your POSTGRES_URL to use the new database."
fi

# Initialize and start IPFS
if [ ! -f ~/.ipfs/config ]; then
    echo "Initializing IPFS..."
    ipfs init
fi

echo "Starting IPFS daemon..."
ipfs daemon &
IPFS_PID=$!

# Wait for IPFS to start
echo "Waiting for IPFS to start..."
for i in {1..30}; do
    if nc -z localhost 5001; then
        echo "IPFS is up!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "Timed out waiting for IPFS to start"
        exit 1
    fi
    sleep 1
done

# Test IPFS connection
echo "Testing IPFS connection..."
ipfs id

#--postgres-url "postgresql://postgres:${POSTGRES_PASSWORD}@localhost:5432/graph-node" \
echo "Starting Graph Node..."
exec graph-node \
    --postgres-url "${POSTGRES_URL}" \
    --ethereum-rpc "${ETHEREUM_RPC_URL}" \
    --ipfs "localhost:5001"

# If graph-node exits, kill IPFS daemon
kill $IPFS_PID
