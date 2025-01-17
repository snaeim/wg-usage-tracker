
# WireGuard Usage Tracker

The **WireGuard Usage Tracker** monitors and stores traffic usage data for WireGuard peers. It ensures traffic statistics are consistently tracked and saved, even if the WireGuard interface goes down (e.g., due to a system reboot or network reset). The tool calculates and provides total traffic usage for each WireGuard interface by summing the usage of its peers.

## Requirements

- **Python 3**
- **SQLite3**
- **WireGuard (`wg`)**

Ensure these dependencies are installed before proceeding with the installation.

## Installation

To install the **WireGuard Usage Tracker** Run the following command to install the tracker, set up the database, and configure periodic updates:
   ```bash
   sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/snaeim/wg-usage-tracker/refs/heads/main/wg-usage-helper.sh)"
   ```

   This will:
   - Install the tracker script.
   - Create necessary directories
      - `/var/lib/wg-usage-tracker` for the database 
      - `/var/log/wg-usage-tracker` for logs
   - Set up the SQLite database 
   - Set up cron job to update the tracker every minute.

## How to Use

Once the **WireGuard Usage Tracker** is installed, you can use it with the following commands:

### Display Usage Data
To display the current traffic usage for WireGuard interfaces and peers, run:

```bash
wg-usage-tracker
```

### Update Traffic Data
To manually update the database with the latest WireGuard traffic data, use:

```bash
wg-usage-tracker -u
```

This will fetch the latest traffic statistics from WireGuard and store them in the database.

### Suppress Output
If you want to update the database without any output to the terminal, use the `-q` (quiet) flag:

```bash
wg-usage-tracker -uq
```

This is useful for running updates in automated scripts or cron jobs.

## Reset or Uninstall

If you need to reset or uninstall the **WireGuard Usage Tracker**, run the installation script again:

```bash
sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/snaeim/wg-usage-tracker/refs/heads/main/wg-usage-helper.sh)"
```

You will be prompted to choose one of the following options:

1. **Reset the database**: This option will clear all the tracked traffic data stored in the database and reset the usage history.
2. **Uninstall the tracker**: This option will remove the tracker script, database, log files, and the cron job, effectively uninstalling the tool.