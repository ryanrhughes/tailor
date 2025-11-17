#!/bin/bash

# SSH Config Setup - Generate SSH config from 1Password
# Can be run standalone or called from tailor.sh

setup_ssh_config() {
  # Check if 1Password CLI is installed
  if ! command -v op &> /dev/null; then
    echo "⚠ 1Password CLI (op) not found. Skipping SSH config setup."
    echo "  Install with: https://developer.1password.com/docs/cli/get-started/"
    return
  fi
  
  # Use XDG config directory for ssh-hosts.json
  CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tailor"
  SSH_HOSTS_FILE="$CONFIG_DIR/ssh-hosts.json"
  
  # Check if ssh-hosts.json exists in config directory
  if [ ! -f "$SSH_HOSTS_FILE" ]; then
    echo "ℹ ssh-hosts.json not found at $SSH_HOSTS_FILE"
    echo "  Create your config file:"
    echo "    mkdir -p $CONFIG_DIR"
    echo "    cp ssh-hosts.json.example $SSH_HOSTS_FILE"
    echo "  Or fetch from 1Password:"
    echo "    op document get 'tailor-ssh-hosts' > $SSH_HOSTS_FILE"
    return
  fi
  
  # Check if jq is installed
  if ! command -v jq &> /dev/null; then
    echo "⚠ jq not found. Install it to use 1Password SSH config generation."
    return
  fi
  
  echo "🔐 Generating SSH config from 1Password..."
  
  mkdir -p ~/.ssh
  mkdir -p config/ssh
  
  # Backup existing SSH config if it exists
  if [ -f ~/.ssh/config ]; then
    cp ~/.ssh/config ~/.ssh/config.backup.$(date +%Y%m%d_%H%M%S)
  fi
  
  # Generate SSH config from 1Password
  > config/ssh/config  # Clear the file
  
  # Read each host from ssh-hosts.json
  jq -c '.[]' "$SSH_HOSTS_FILE" | while read -r host_config; do
    host=$(echo "$host_config" | jq -r '.host')
    uuid=$(echo "$host_config" | jq -r '.uuid')
    account=$(echo "$host_config" | jq -r '.account // empty')
    
    # Check if host already exists in SSH config
    if [ -f ~/.ssh/config ] && grep -q "^Host $host$" ~/.ssh/config; then
      echo "  ✓ Host $host already exists in SSH config, skipping"
      continue
    fi
    
    if [ -z "$account" ]; then
      echo "  ⚠ No account specified for $host, skipping"
      continue
    fi
    
    echo "  Fetching credentials for $host from $account..."
    
    # Get the full item as JSON from 1Password
    item_json=$(op item get "$uuid" --format json --account "$account" 2>/dev/null)
    
    if [ -z "$item_json" ]; then
      echo "  ⚠ Failed to fetch 1Password item with UUID '$uuid'"
      continue
    fi
    
    # Extract fields dynamically - try common field names
    hostname=$(echo "$item_json" | jq -r '
      .fields[] | 
      select(.label | ascii_downcase | test("^(ip|host|hostname|server|address)$")) | 
      .value // empty
    ' | head -n1)
    
    username=$(echo "$item_json" | jq -r '
      .fields[] | 
      select(.label | ascii_downcase | test("^(user|username)$")) | 
      .value // empty
    ' | head -n1)
    
    port=$(echo "$item_json" | jq -r '
      .fields[] | 
      select(.label | ascii_downcase | test("^port$")) | 
      .value // empty
    ' | head -n1)
    
    # Apply defaults
    [ -z "$port" ] && port=22
    
    # Check for required fields
    if [ -z "$hostname" ]; then
      echo "  ⚠ No IP/hostname field found for $host (looked for: ip, host, hostname, server, address)"
      continue
    fi
    
    if [ -z "$username" ]; then
      echo "  ⚠ No username field found for $host (looked for: user, username)"
      continue
    fi
    
    # Write SSH config entry
    {
      echo ""
      echo "Host $host"
      echo "    HostName $hostname"
      echo "    User $username"
      echo "    Port $port"
      
      # Add any override options from ssh-hosts.json
      echo "$host_config" | jq -r '.options // {} | to_entries[] | "    \(.key) \(.value)"'
    } >> config/ssh/config
    
    echo "  ✓ Added $host ($username@$hostname:$port)"
  done
  
  if [ -s config/ssh/config ]; then
    # Append or create SSH config in home directory
    if [ -f ~/.ssh/config ]; then
      echo "" >> ~/.ssh/config
      echo "# --- Tailor SSH Config (Generated from 1Password) ---" >> ~/.ssh/config
      cat config/ssh/config >> ~/.ssh/config
    else
      cp config/ssh/config ~/.ssh/config
    fi
    
    # Set proper permissions
    chmod 600 ~/.ssh/config
    chmod 600 config/ssh/config 2>/dev/null || true
    echo "✓ SSH config updated from 1Password"
    echo ""
    echo "Generated config:"
    cat config/ssh/config
  else
    echo "⚠ No SSH config entries were generated"
  fi
}

setup_ssh_config
