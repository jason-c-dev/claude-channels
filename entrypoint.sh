#!/bin/bash
set -e

# Set timezone from TZ env var
if [ -n "$TZ" ] && [ -f "/usr/share/zoneinfo/$TZ" ]; then
  ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
  echo "$TZ" > /etc/timezone
fi

# Fix ownership of .claude dir (volume mount creates it as root)
chown -R claude:claude /home/claude/.claude

# Start SSH daemon
/usr/sbin/sshd

# Start cron for scheduled tasks
cron

echo "claude-channels: ready"
echo "claude-channels: SSH in: ssh -p 2222 claude@<host> (password: claude)"
echo "claude-channels: then: cd /app && claude --dangerously-skip-permissions --dangerously-load-development-channels server:webhook-channel --channels plugin:telegram@claude-plugins-official"

# Keep container alive
exec tail -f /dev/null
