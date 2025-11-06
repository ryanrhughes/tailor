# Tailor

Environment setup scripts to quickly replicate your development environment across machines.

## Quick Start

1. **Install prerequisites**:
   - [1Password CLI](https://developer.1password.com/docs/cli/get-started/) (`op`)
   - `jq`

2. **Sign in to 1Password**:
   ```bash
   op account add
   eval $(op signin)
   ```

3. **Create config files**:
   ```bash
   mkdir -p ~/.config/tailor
   cp ssh-hosts.json.example ~/.config/tailor/ssh-hosts.json
   cp config/hypr/envs.conf.example ~/.config/tailor/envs.conf
   # Edit both files with your actual values
   ```

4. **Run setup**:
   ```bash
   ./tailor.sh
   ```

## Configuration

### Environment Variables

Create `~/.config/tailor/envs.conf` for sensitive URLs and environment variables:

```bash
env = WEBUI,https://your-webui-url.example.com/
```

These will be copied to `~/.config/hypr/envs.conf` and sourced by Hyprland. Use them in your bindings:

```bash
bind = SUPER SHIFT, A, exec, omarchy-launch-webapp "$WEBUI"
```

### SSH Hosts File

Create `~/.config/tailor/ssh-hosts.json` with your server information:

```json
[
  {
    "host": "my-server",
    "uuid": "your-1password-item-uuid",
    "account": "your-account.1password.com"
  }
]
```

Get UUIDs from 1Password: click item → copy UUID, or run `op item list`.

### 1Password Items

Each server needs a 1Password item with these fields:
- **hostname** (or `ip`, `host`, `server`, `address`) - server IP/hostname
- **username** (or `user`) - SSH username  
- **port** (optional, defaults to 22)

Field matching is case-insensitive. SSH keys are managed by 1Password SSH agent.

### Advanced Options

Add SSH config options per host:

```json
{
  "host": "prod",
  "uuid": "item-uuid",
  "account": "your-account.1password.com",
  "options": {
    "ForwardAgent": "yes",
    "ServerAliveInterval": 60
  }
}
```

## What Gets Configured

- Hyprland config files
- SSH config from 1Password credentials
- Monitor settings for 4K displays
- Mailcatcher Docker container

## Security

- `ssh-hosts.json` and `envs.conf` live in `~/.config/tailor/` (not in the repo)
- Consider storing your configs as 1Password documents for backup
- Generated files in `~/.config/hypr/` are git-ignored
