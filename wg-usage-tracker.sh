#!/usr/bin/env python3

import os
import sqlite3
import argparse
import subprocess
from datetime import datetime

def parse_wireguard_dump():
    """
    Parse the output of 'wg show all dump' and organize the data.
    """
    result = subprocess.run(["wg", "show", "all", "dump"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, check=True)
    lines = result.stdout.strip().split("\n")
    interfaces = {}

    for line in lines:
        parts = line.split("\t")

        if len(parts) == 5:
            # Interface line
            interfaces[parts[0]] = {
                "private_key": parts[1],
                "public_key": parts[2],
                "listen_port": int(parts[3]),
                "fwmark": parts[4] if parts[4] != "(none)" else None,
                "peers": {}
            }
        elif len(parts) == 9:
            # Peer line
            interface_name = parts[0]
            if interface_name in interfaces:
                interfaces[interface_name]["peers"][parts[1]] = {
                    "preshared_key": parts[2] if parts[2] != "(none)" else None,
                    "endpoint": parts[3] if parts[3] != "(none)" else None,
                    "allowed_ips": parts[4],
                    "latest_handshake": int(parts[5]),
                    "transfer_rx": int(parts[6]),
                    "transfer_tx": int(parts[7]),
                    "persistent_keepalive": parts[8] if parts[8] != "(none)" else None
                }

    return interfaces

def update_database(cursor, data):
    """
    Update the database with interface and peer data.
    """
    now = int(datetime.now().timestamp())

    for interface_name, interface_info in data.items():
        # Update or insert interface
        cursor.execute("""
            INSERT INTO interfaces (name, private_key, public_key, listen_port, fwmark, last_updated)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(name) DO UPDATE SET
                private_key = excluded.private_key,
                public_key = excluded.public_key,
                listen_port = excluded.listen_port,
                fwmark = excluded.fwmark,
                last_updated = excluded.last_updated
        """, (
            interface_name, interface_info["private_key"], interface_info["public_key"],
            interface_info["listen_port"], interface_info["fwmark"], now
        ))

        # Update or insert peers
        for peer_id, peer_data in interface_info["peers"].items():
            cursor.execute("""
                SELECT transfer_rx, transfer_tx, latest_handshake FROM peers
                WHERE interface_name = ? AND peer_id = ?
            """, (interface_name, peer_id))
            row = cursor.fetchone()

            if row:
                prev_rx, prev_tx, prev_handshake = row
                if (peer_data["transfer_rx"], peer_data["transfer_tx"], peer_data["latest_handshake"]) == (prev_rx, prev_tx, prev_handshake):
                    continue  # Skip if unchanged

                delta_rx = max(0, peer_data["transfer_rx"] - prev_rx)
                delta_tx = max(0, peer_data["transfer_tx"] - prev_tx)

                cursor.execute("""
                    UPDATE peers
                    SET endpoint = ?, allowed_ips = ?, transfer_rx = ?, transfer_tx = ?,
                        total_rx = total_rx + ?, total_tx = total_tx + ?,
                        latest_handshake = ?, persistent_keepalive = ?
                    WHERE interface_name = ? AND peer_id = ?
                """, (
                    peer_data["endpoint"], peer_data["allowed_ips"],
                    peer_data["transfer_rx"], peer_data["transfer_tx"],
                    delta_rx, delta_tx,
                    peer_data["latest_handshake"], peer_data["persistent_keepalive"],
                    interface_name, peer_id
                ))
            else:
                cursor.execute("""
                    INSERT INTO peers (interface_name, peer_id, endpoint, allowed_ips, transfer_rx, transfer_tx,
                                       total_rx, total_tx, latest_handshake, persistent_keepalive)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    interface_name, peer_id, peer_data["endpoint"], peer_data["allowed_ips"],
                    peer_data["transfer_rx"], peer_data["transfer_tx"], peer_data["transfer_rx"],
                    peer_data["transfer_tx"], peer_data["latest_handshake"], peer_data["persistent_keepalive"]
                ))

def bytes_to_human_readable(num):
    """
    Convert bytes to a human-readable format.
    """
    for unit in ['B', 'KiB', 'MiB', 'GiB', 'TiB']:
        if num < 1024.0:
            return f"{num:.2f} {unit}"
        num /= 1024.0
    return f"{num:.2f} PiB"

def format_duration(seconds):
    """
    Format duration in seconds into a human-readable string.
    """
    if seconds == 0:
        return "just now"
    if seconds < 60:
        return f"{seconds} seconds ago"
    minutes, seconds = divmod(seconds, 60)
    if minutes < 60:
        return f"{minutes} minutes, {seconds} seconds ago"
    hours, minutes = divmod(minutes, 60)
    if hours < 24:
        return f"{hours} hours, {minutes} minutes ago"
    days, hours = divmod(hours, 24)
    return f"{days} days, {hours} hours, {minutes} minutes ago"

def generate_wireguard_output(cursor):
    """
    Generate WireGuard-like output from the database.
    """
    now = int(datetime.now().timestamp())

    cursor.execute("""
        SELECT name, public_key, listen_port, last_updated
        FROM interfaces
    """)
    interfaces = cursor.fetchall()

    output = []
    for interface in interfaces:
        name, public_key, listen_port, last_updated = interface

        # Format last updated
        if last_updated:
            last_update_formatted = format_duration(now - last_updated)
        else:
            last_update_formatted = "unknown"

        # Fetch peers for the interface
        cursor.execute("""
            SELECT peer_id, endpoint, allowed_ips, total_rx, total_tx,
                   latest_handshake
            FROM peers
            WHERE interface_name = ?
        """, (name,))
        peers = cursor.fetchall()

        # Sort peers by latest handshake (most recent first, nulls last)
        peers.sort(key=lambda x: x[5] if x[5] is not None else 0, reverse=True)

        # Calculate total transfer for the interface
        total_rx = sum(peer[3] or 0 for peer in peers)
        total_tx = sum(peer[4] or 0 for peer in peers)

        # Add interface information to the output
        output.append(f"interface: {name}")
        output.append(f"  public key: {public_key}")
        output.append(f"  listening port: {listen_port}")
        output.append(f"  last updated: {last_update_formatted}")
        if total_rx > 0 or total_tx > 0:
            output.append(f"  transfer: {bytes_to_human_readable(total_rx)} received, {bytes_to_human_readable(total_tx)} sent")
        output.append("")  # Blank line for separation

        for peer in peers:
            peer_id, endpoint, allowed_ips, total_rx, total_tx, latest_handshake = peer

            # Format latest handshake
            if latest_handshake:
                handshake_duration = int(datetime.now().timestamp()) - latest_handshake
                latest_handshake_formatted = format_duration(handshake_duration)
            else:
                latest_handshake_formatted = None

            # Add peer information to the output
            output.append(f"peer: {peer_id}")
            if endpoint:
                output.append(f"  endpoint: {endpoint}")
            if allowed_ips:
                output.append(f"  allowed ips: {allowed_ips}")
            if latest_handshake_formatted:
                output.append(f"  latest handshake: {latest_handshake_formatted}")
            if total_rx > 0 or total_tx > 0:
                output.append(f"  transfer: {bytes_to_human_readable(total_rx)} received, {bytes_to_human_readable(total_tx)} sent")
            output.append("")  # Blank line for separation

    # Print the final output
    print("\n".join(output))

def main():
    parser = argparse.ArgumentParser(description="WireGuard Usage Tracker")
    parser.add_argument("--update", "-u", action="store_true", help="Update the database with the latest WireGuard data.")
    parser.add_argument("--quiet", "-q", action="store_true", help="Suppress all output except errors.")
    args = parser.parse_args()

    # Connect to the database
    conn = sqlite3.connect("/var/lib/wg-usage-tracker/data.db")
    cursor = conn.cursor()

    try:
        if args.update:
            if os.geteuid() != 0:
                raise PermissionError("Root privilege required.")
            # Update the database
            data = parse_wireguard_dump()
            update_database(cursor, data)
            conn.commit()
        
        # If not quiet, print the WireGuard output
        if not args.quiet:
            generate_wireguard_output(cursor)
    except Exception as e:
        # Log error to a file if have quiet flag
        if args.quiet:
            with open("/var/log/wg-usage-tracker/error.log", "a") as error_log:
                error_log.write(f"Error: {e}\n")
        else:
            print(f"Error: {e}")
    finally:
        conn.close()

if __name__ == "__main__":
    main()