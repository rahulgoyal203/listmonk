#!/bin/sh

set -e

export PUID=${PUID:-0}
export PGID=${PGID:-0}
export GROUP_NAME="app"
export USER_NAME="app"

# This function evaluates if the supplied PGID is already in use
# if it is not in use, it creates the group with the PGID
# if it is in use, it sets the GROUP_NAME to the existing group
create_group() {
  if ! getent group ${PGID} > /dev/null 2>&1; then
    addgroup -g ${PGID} ${GROUP_NAME}
  else
    existing_group=$(getent group ${PGID} | cut -d: -f1)
    export GROUP_NAME=${existing_group}
  fi
}

# This function evaluates if the supplied PUID is already in use
# if it is not in use, it creates the user with the PUID and PGID
create_user() {
  if ! getent passwd ${PUID} > /dev/null 2>&1; then
    adduser -u ${PUID} -G ${GROUP_NAME} -s /bin/sh -D ${USER_NAME}
  else
    existing_user=$(getent passwd ${PUID} | cut -d: -f1)
    export USER_NAME=${existing_user}
  fi
}

# Run the needed functions to create the user and group
create_group
create_user

load_secret_files() {
  # Save and restore IFS
  old_ifs="$IFS"
  IFS='
'
  # Capture all env variables starting with LISTMONK_ and ending with _FILE.
  # It's value is assumed to be a file path with its actual value.
  for line in $(env | grep '^LISTMONK_.*_FILE='); do
    var="${line%%=*}"
    fpath="${line#*=}"

    # If it's a valid file, read its contents and assign it to the var
    # without the _FILE suffix.
    # Eg: LISTMONK_DB_USER_FILE=/run/secrets/user -> LISTMONK_DB_USER=$(contents of /run/secrets/user)
    if [ -f "$fpath" ]; then
      new_var="${var%_FILE}"
      export "$new_var"="$(cat "$fpath")"
    fi
  done
  IFS="$old_ifs"
}

# Load env variables from files if LISTMONK_*_FILE variables are set.
load_secret_files

# Substitute environment variables in config.toml
substitute_env_vars() {
  if [ -f /listmonk/config.toml ]; then
    echo "Debug: Railway environment variables:"
    echo "PORT=$PORT"
    echo "PGHOST=$PGHOST"
    echo "PGPORT=$PGPORT"
    echo "PGUSER=$PGUSER"
    echo "PGPASSWORD=$PGPASSWORD"
    echo "PGDATABASE=$PGDATABASE"
    
    echo "Debug: LISTMONK environment variables from Railway:"
    env | grep LISTMONK_ || echo "No LISTMONK_ variables found"
    
    # Convert LISTMONK_ environment variables to the config format
    # Simplified - expecting LISTMONK_app__address to already have the port (e.g., 0.0.0.0:8080)
    export LISTMONK_APP_ADDRESS="${LISTMONK_app__address:-0.0.0.0:9000}"
    export LISTMONK_DB_HOST="${LISTMONK_db__host:-localhost}"
    export LISTMONK_DB_PORT="${LISTMONK_db__port:-5432}"
    export LISTMONK_DB_USER="${LISTMONK_db__user:-listmonk}"
    export LISTMONK_DB_PASSWORD="${LISTMONK_db__password:-listmonk}"
    export LISTMONK_DB_DATABASE="${LISTMONK_db__database:-listmonk}"
    export LISTMONK_DB_SSL_MODE="${LISTMONK_db__ssl_mode:-disable}"
    
    echo "Debug: Mapped variables for substitution:"
    echo "LISTMONK_APP_ADDRESS=$LISTMONK_APP_ADDRESS"
    echo "LISTMONK_DB_HOST=$LISTMONK_DB_HOST"
    echo "LISTMONK_DB_PORT=$LISTMONK_DB_PORT"
    echo "LISTMONK_DB_USER=$LISTMONK_DB_USER"
    echo "LISTMONK_DB_PASSWORD=$LISTMONK_DB_PASSWORD"
    echo "LISTMONK_DB_DATABASE=$LISTMONK_DB_DATABASE"
    echo "LISTMONK_DB_SSL_MODE=$LISTMONK_DB_SSL_MODE"
    
    # Use manual substitution since envsubst doesn't work with our ${VAR:-default} syntax
    echo "Original config before substitution:"
    cat /listmonk/config.toml
    
    echo "Running manual substitution..."
    sed -i "s|\${LISTMONK_APP_ADDRESS:-0.0.0.0:9000}|${LISTMONK_APP_ADDRESS}|g" /listmonk/config.toml
    sed -i "s|\${LISTMONK_DB_HOST:-localhost}|${LISTMONK_DB_HOST}|g" /listmonk/config.toml
    sed -i "s|\${LISTMONK_DB_PORT:-5432}|${LISTMONK_DB_PORT}|g" /listmonk/config.toml
    sed -i "s|\${LISTMONK_DB_USER:-listmonk}|${LISTMONK_DB_USER}|g" /listmonk/config.toml
    sed -i "s|\${LISTMONK_DB_PASSWORD:-listmonk}|${LISTMONK_DB_PASSWORD}|g" /listmonk/config.toml
    sed -i "s|\${LISTMONK_DB_DATABASE:-listmonk}|${LISTMONK_DB_DATABASE}|g" /listmonk/config.toml
    sed -i "s|\${LISTMONK_DB_SSL_MODE:-disable}|${LISTMONK_DB_SSL_MODE}|g" /listmonk/config.toml
    
    echo "Manual substitution completed. Final config:"
    cat /listmonk/config.toml
  fi
}

substitute_env_vars

# Verify critical files exist
echo "Verifying required files:"
for file in config.toml.sample queries.sql schema.sql permissions.json; do
  if [ -f "/listmonk/$file" ]; then
    echo "✓ $file exists"
  else
    echo "✗ $file missing - creating fallback..."
    # Create empty fallback files if they don't exist
    case "$file" in
      config.toml.sample)
        printf '[app]\naddress = "localhost:9000"\n\n[db]\nhost = "localhost"\nport = 5432\nuser = "listmonk"\npassword = "listmonk"\ndatabase = "listmonk"\nssl_mode = "disable"\n' > "/listmonk/$file"
        ;;
      permissions.json)
        echo '[]' > "/listmonk/$file"
        ;;
      *)
        touch "/listmonk/$file"
        ;;
    esac
  fi
done

# Try to set the ownership of the app directory to the app user.
if ! chown -R ${PUID}:${PGID} /listmonk 2>/dev/null; then
  echo "Warning: Failed to change ownership of /listmonk. Readonly volume?"
fi

echo "Launching listmonk with user=[${USER_NAME}] group=[${GROUP_NAME}] PUID=[${PUID}] PGID=[${PGID}]"

# Check if database needs initialization
echo "Checking and initializing database if needed..."

# Only run install if database is truly empty
# Check if the settings table exists (indicates an initialized database)
if ./listmonk --version >/dev/null 2>&1; then
  echo "Checking if database is already initialized..."
  # Try to run listmonk without install - if it fails, then install
  if ! ./listmonk --config /listmonk/config.toml --version 2>&1 | grep -q "settings"; then
    echo "Database appears uninitialized. Running installation..."
    ./listmonk --install --idempotent --yes 2>&1 || {
      echo "Installation returned an error, checking if already installed..."
    }
  else
    echo "Database already initialized, skipping installation"
  fi
else
  echo "First time setup - running installation..."
  ./listmonk --install --idempotent --yes 2>&1
fi

# Give it a moment to ensure database is ready
sleep 2

# Now run the main application
echo "Starting listmonk application..."
# If running as root and PUID is not 0, then execute command as PUID
# this allows us to run the container as a non-root user
if [ "$(id -u)" = "0" ] && [ "${PUID}" != "0" ]; then
  su-exec ${PUID}:${PGID} "$@"
else
  exec "$@"
fi
