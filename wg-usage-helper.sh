#!/bin/bash

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root."
  exit 1
fi

# Check for required dependencies
check_dependencies() {
  dependencies=("python3" "sqlite3" "wg")
  for dep in "${dependencies[@]}"; do
    if ! command -v "$dep" &>/dev/null; then
      echo "Dependency $dep is missing. Please install it first."
      exit 1
    fi
  done
}

# Install the script and dependencies
install_script() {
  echo "Installing wg-usage-tracker..."

  # Download the script
  wget -q -O /usr/local/bin/wg-usage-tracker "https://raw.githubusercontent.com/snaeim/wg-usage-tracker/refs/heads/main/wg-usage-tracker.sh"

  # Make it executable
  chmod +x /usr/local/bin/wg-usage-tracker

  # Create directories
  mkdir -p /var/lib/wg-usage-tracker
  mkdir -p /var/log/wg-usage-tracker

  # Create SQLite DB file
  touch /var/lib/wg-usage-tracker/data.db

  # Create tables in the database
  sqlite3 /var/lib/wg-usage-tracker/data.db <<EOF
CREATE TABLE IF NOT EXISTS interfaces (
  name TEXT PRIMARY KEY NOT NULL,
  private_key TEXT,
  public_key TEXT,
  listen_port INTEGER,
  fwmark INTEGER,
  last_updated INTEGER
);

CREATE TABLE IF NOT EXISTS peers (
  interface_name TEXT NOT NULL,
  peer_id TEXT NOT NULL,
  endpoint TEXT,
  allowed_ips TEXT,
  transfer_rx INTEGER,
  transfer_tx INTEGER,
  total_rx INTEGER DEFAULT 0,
  total_tx INTEGER DEFAULT 0,
  latest_handshake INTEGER,
  persistent_keepalive TEXT,
  PRIMARY KEY (interface_name, peer_id),
  FOREIGN KEY (interface_name) REFERENCES interfaces (name) ON DELETE CASCADE
);
EOF

  # Create log file
  touch /var/log/wg-usage-tracker/error.log

  # Add cron job to update every minute
  (crontab -l 2>/dev/null; echo "* * * * * /usr/local/bin/wg-usage-tracker -uq") | crontab -

  echo "wg-usage-tracker installed successfully."
}

# Reset the database
reset_db() {
  echo "Resetting the database..."

  sqlite3 /var/lib/wg-usage-tracker/data.db <<EOF
DELETE FROM interfaces;
DELETE FROM peers;
EOF

  echo "Database reset successfully."
}

# Uninstall the script and related files
uninstall_script() {
  echo "Uninstalling wg-usage-tracker..."

  # Remove cron job
  crontab -l | grep -v "/usr/local/bin/wg-usage-tracker" | crontab -

  # Remove the script
  rm -f /usr/local/bin/wg-usage-tracker

  # Remove database and log files
  rm -rf /var/lib/wg-usage-tracker
  rm -rf /var/log/wg-usage-tracker

  echo "wg-usage-tracker uninstalled successfully."
}

# Main script logic
check_dependencies

# Check if the script is already installed
if [ -f "/usr/local/bin/wg-usage-tracker" ]; then
  echo "wg-usage-tracker is already installed."
  echo "What would you like to do?"
  echo "1) Clear database"
  echo "2) Uninstall the script"
  read -p "Enter option (1 or 2): " option

  case $option in
    1)
      reset_db
      ;;
    2)
      uninstall_script
      ;;
    *)
      echo "Invalid option. Exiting."
      exit 1
      ;;
  esac
else
  echo "wg-usage-tracker is not installed."
  echo "Installing now..."
  install_script
fi
