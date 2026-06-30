#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# PostgreSQL setup script for Ubuntu
# - Installs PostgreSQL if not already present
# - Sets the postgres superuser password
# - Creates a database
# - Optionally creates a dedicated app user with access to that database
# ---------------------------------------------------------------------------

# Must run with root privileges (uses apt + sudo -u postgres)
if [[ $EUID -ne 0 ]]; then
  echo "Please run with sudo: sudo $0"
  exit 1
fi

# --- Helper: run SQL as the postgres OS user ---
run_sql() {
  sudo -u postgres psql -v ON_ERROR_STOP=1 -tAc "$1"
}

# --- Helper: escape single quotes for SQL string literals ---
sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

echo "==> Checking for existing PostgreSQL installation..."
if command -v psql >/dev/null 2>&1 && dpkg -s postgresql >/dev/null 2>&1; then
  echo "PostgreSQL is already installed: $(psql --version)"
else
  echo "==> Installing PostgreSQL..."
  apt update
  apt install -y postgresql postgresql-contrib
fi

# --- Ensure service is running and enabled on boot ---
echo "==> Ensuring PostgreSQL service is running..."
systemctl enable postgresql >/dev/null 2>&1 || true
systemctl start postgresql
systemctl --no-pager status postgresql | head -n 3 || true

# --- Prompt for postgres superuser password (silent + confirm) ---
echo
while true; do
  read -rsp "Enter password for the 'postgres' superuser: " PG_PASS
  echo
  read -rsp "Confirm password: " PG_PASS_CONFIRM
  echo
  if [[ -z "$PG_PASS" ]]; then
    echo "Password cannot be empty. Try again."
  elif [[ "$PG_PASS" != "$PG_PASS_CONFIRM" ]]; then
    echo "Passwords do not match. Try again."
  else
    break
  fi
done

PG_PASS_ESC="$(sql_escape "$PG_PASS")"
run_sql "ALTER USER postgres WITH PASSWORD '${PG_PASS_ESC}';"
echo "==> postgres password set."

# --- Prompt for database name (validate) ---
echo
while true; do
  read -rp "Enter the name of the database to create: " DB_NAME
  if [[ "$DB_NAME" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    break
  else
    echo "Invalid name. Use letters, digits, underscores; must not start with a digit."
  fi
done

# --- Create database if it doesn't already exist (idempotent) ---
DB_EXISTS="$(run_sql "SELECT 1 FROM pg_database WHERE datname='$(sql_escape "$DB_NAME")';" || true)"
if [[ "$DB_EXISTS" == "1" ]]; then
  echo "==> Database '${DB_NAME}' already exists. Skipping creation."
else
  run_sql "CREATE DATABASE \"${DB_NAME}\";"
  echo "==> Database '${DB_NAME}' created."
fi

# --- Optional: dedicated application user ---
echo
read -rp "Create a dedicated app user for this database? [y/N]: " MAKE_USER
APP_USER=""
APP_PASS=""
if [[ "$MAKE_USER" =~ ^[Yy]$ ]]; then
  while true; do
    read -rp "Enter the app username: " APP_USER
    if [[ "$APP_USER" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
      break
    else
      echo "Invalid username. Use letters, digits, underscores; must not start with a digit."
    fi
  done

  while true; do
    read -rsp "Enter password for '${APP_USER}': " APP_PASS
    echo
    read -rsp "Confirm password: " APP_PASS_CONFIRM
    echo
    if [[ -z "$APP_PASS" ]]; then
      echo "Password cannot be empty. Try again."
    elif [[ "$APP_PASS" != "$APP_PASS_CONFIRM" ]]; then
      echo "Passwords do not match. Try again."
    else
      break
    fi
  done

  APP_PASS_ESC="$(sql_escape "$APP_PASS")"

  # Create role if missing, else update password
  USER_EXISTS="$(run_sql "SELECT 1 FROM pg_roles WHERE rolname='$(sql_escape "$APP_USER")';" || true)"
  if [[ "$USER_EXISTS" == "1" ]]; then
    run_sql "ALTER ROLE \"${APP_USER}\" WITH LOGIN PASSWORD '${APP_PASS_ESC}';"
    echo "==> Existing role '${APP_USER}' password updated."
  else
    run_sql "CREATE ROLE \"${APP_USER}\" WITH LOGIN PASSWORD '${APP_PASS_ESC}';"
    echo "==> Role '${APP_USER}' created."
  fi

  # Grant privileges on the database
  run_sql "GRANT ALL PRIVILEGES ON DATABASE \"${DB_NAME}\" TO \"${APP_USER}\";"

  # Postgres 15+ requires explicit schema grant; make app user own the schema
  sudo -u postgres psql -v ON_ERROR_STOP=1 -d "${DB_NAME}" -tAc \
    "GRANT ALL ON SCHEMA public TO \"${APP_USER}\"; ALTER SCHEMA public OWNER TO \"${APP_USER}\";"
  echo "==> Schema privileges granted to '${APP_USER}'."
fi

# --- Summary ---
echo
echo "============================================================"
echo " Setup complete."
echo "============================================================"
echo " Database: ${DB_NAME}"
echo " Host:     localhost"
echo " Port:     5432"
echo
echo " Connection string (postgres superuser):"
echo "   postgresql://postgres:<password>@localhost:5432/${DB_NAME}"
if [[ -n "$APP_USER" ]]; then
  echo
  echo " Connection string (app user):"
  echo "   postgresql://${APP_USER}:<password>@localhost:5432/${DB_NAME}"
fi
echo
echo " Passwords are not printed for security."
echo " This setup is local-only (listening on localhost:5432)."
echo "============================================================"
