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
    export LISTMONK_APP_ADDRESS="${LISTMONK_app__address:-0.0.0.0:${PORT:-9000}}"
    export LISTMONK_DB_HOST="${LISTMONK_db__host:-${PGHOST:-localhost}}"
    export LISTMONK_DB_PORT="${LISTMONK_db__port:-${PGPORT:-5432}}"
    export LISTMONK_DB_USER="${LISTMONK_db__user:-${PGUSER:-listmonk}}"
    export LISTMONK_DB_PASSWORD="${LISTMONK_db__password:-${PGPASSWORD:-listmonk}}"
    export LISTMONK_DB_DATABASE="${LISTMONK_db__database:-${PGDATABASE:-listmonk}}"
    export LISTMONK_DB_SSL_MODE="${LISTMONK_db__ssl_mode:-disable}"
    
    echo "Debug: Mapped variables for substitution:"
    echo "LISTMONK_APP_ADDRESS=$LISTMONK_APP_ADDRESS"
    echo "LISTMONK_DB_HOST=$LISTMONK_DB_HOST"
    echo "LISTMONK_DB_PORT=$LISTMONK_DB_PORT"
    echo "LISTMONK_DB_USER=$LISTMONK_DB_USER"
    echo "LISTMONK_DB_PASSWORD=$LISTMONK_DB_PASSWORD"
    echo "LISTMONK_DB_DATABASE=$LISTMONK_DB_DATABASE"
    echo "LISTMONK_DB_SSL_MODE=$LISTMONK_DB_SSL_MODE"
    
    # Use envsubst to substitute variables in config.toml
    if command -v envsubst >/dev/null 2>&1; then
      envsubst '$LISTMONK_APP_ADDRESS $LISTMONK_DB_HOST $LISTMONK_DB_PORT $LISTMONK_DB_USER $LISTMONK_DB_PASSWORD $LISTMONK_DB_DATABASE $LISTMONK_DB_SSL_MODE' < /listmonk/config.toml > /tmp/config.toml && mv /tmp/config.toml /listmonk/config.toml
      echo "Config substitution completed. Final config:"
      cat /listmonk/config.toml
    fi
  fi
}

substitute_env_vars

# Try to set the ownership of the app directory to the app user.
if ! chown -R ${PUID}:${PGID} /listmonk 2>/dev/null; then
  echo "Warning: Failed to change ownership of /listmonk. Readonly volume?"
fi

echo "Launching listmonk with user=[${USER_NAME}] group=[${GROUP_NAME}] PUID=[${PUID}] PGID=[${PGID}]"

# If running as root and PUID is not 0, then execute command as PUID
# this allows us to run the container as a non-root user
if [ "$(id -u)" = "0" ] && [ "${PUID}" != "0" ]; then
  su-exec ${PUID}:${PGID} "$@"
else
  exec "$@"
fi
