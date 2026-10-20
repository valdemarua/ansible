## Playbooks

| Playbook | Roles applied | Target group | When to use |
|---|---|---|---|
| `base.yml` | packages, admin_user, ssh_hardening, sysctl, ufw, fail2ban, logrotate | `all` | Every run — first time as the provider's default user, after that as the configured administrator |
| `devbox.yml` | base + docker | `devboxes` | Development machines with Docker and an SSH-only firewall |
| `dokploy_server.yml` | base + docker, dokploy | `dokploy_servers` | Dokploy PaaS servers |
| `k3s_server.yml` | base + k3s, helm, cert_manager, argocd | `k3s_servers` | k3s servers |

## Roles

| Role | Purpose |
|---|---|
| `admin_user` | Creates a configurable administrator with SSH keys and optional passwordless sudo |
| `dokploy` | Dokploy PaaS — installs via official script (Docker Swarm + Traefik + Postgres + Redis) |
| `packages` | Essential system packages plus profile-specific additions |
| `sysctl` | Kernel tuning — memory overcommit (Redis), low swappiness, larger TCP backlog |
| `ufw` | Firewall — allows SSH plus profile-specific ports; denies everything else |
| `fail2ban` | Bans IPs after repeated SSH failures |
| `logrotate` | Configures system log rotation |
| `docker` | Docker CE + compose plugin via official apt repo |
| `k3s` | Lightweight Kubernetes via k3s |
| `helm` | Helm CLI |
| `cert_manager` | cert-manager + ClusterIssuer for Let's Encrypt |
| `argocd` | ArgoCD GitOps controller via Helm |

## SSH Key Setup

Authorized public keys belong in your private inventory. This repository does not
provide personal keys, and provisioning stops if `admin_user_ssh_keys` is empty.
The default administrator remains `deploy` and has passwordless sudo.

Generate a key on the client or in your password manager. For a local key file:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/server -C "server access"
chmod 600 ~/.ssh/server
```

Set `admin_user_ssh_keys` as shown in the inventory example below, and append
more public keys as additional list entries. Keep private keys on their
client devices or in a password manager; never commit them. The inventory's
`ansible_ssh_private_key_file` selects the local private key Ansible connects with.

Use a private inventory directory so Ansible also loads its `group_vars` files.
For a standalone `hosts` file copied from `hosts.sample`, set `admin_user_ssh_keys`
as a JSON-style list under `[all:vars]` instead.

Removing a key from `admin_user_ssh_keys` does not revoke it: `authorized_key`
adds keys but never prunes ones already on a server. Remove those by hand, or with
`state: absent`.

## Usage

1. Provide an inventory:
   - `cp hosts.sample hosts`, then set server addresses with `ansible_user=deploy`, or
   - `make link-inventory INVENTORY=/path/to/inventory` to symlink an external
     inventory directory, including its `group_vars`. Rerun this command if
     `hosts` previously linked to the inventory file rather than its directory.
2. Set `cert_manager_email` in `group_vars/k3s_servers.yml` when provisioning k3s.

### Inventory example

Keep machine-specific data in an external inventory directory:

```text
inventory/
  hosts
  group_vars/
    all.yml
```

Example `inventory/hosts`:

```ini
[devboxes]
devbox ansible_host=192.0.2.10 ansible_user=dev

[dokploy_servers]
production ansible_host=192.0.2.20 ansible_user=deploy

[all:vars]
ansible_become=yes
ansible_ssh_private_key_file=~/.ssh/server
```

Example `inventory/group_vars/all.yml`:

```yaml
---
admin_user_ssh_keys:
  - "ssh-ed25519 AAAA... laptop"
  - "ssh-ed25519 AAAA... another-client"
```

Replace the example addresses and public-key placeholders with your own values.
The inventory supplies the server groups and addresses, SSH login users, local
private-key path, and public keys to authorize. Omit `ansible_ssh_private_key_file`
when using your SSH agent or default identities. Private-key contents never
belong in the inventory.

The key list in `group_vars/all.yml` applies to every server. For a group-specific
list, use `group_vars/devboxes.yml`, for example; include every key that should
remain authorized for that group, because lists replace inherited lists.

Link the directory once:

```sh
make link-inventory INVENTORY=/absolute/path/to/inventory
```

### Running playbooks

A server is bootstrapped once as the provider's default user, and run as the
configured administrator from then on. Production machines default to `deploy`:

```bash
# Fresh server — connect as the provider's default user.
# AWS uses 'ubuntu', most others (Hetzner, DigitalOcean, Vultr) use 'root'.
# This creates the configured administrator, hardens SSH, and configures the base system.
ansible-playbook base.yml --limit your-server.com -e ansible_user=root

# All subsequent runs — the configured administrator now exists and is in inventory
ansible-playbook base.yml --limit your-server.com
ansible-playbook devbox.yml --limit your-devbox.com
ansible-playbook dokploy_server.yml --limit your-server.com
ansible-playbook k3s_server.yml --limit your-server.com

# Dry-run
ansible-playbook base.yml --check --limit your-server.com
```

If the inventory pins `ansible_ssh_private_key_file` (the deploy key), SSH still
falls back to your default keys during bootstrap, so the above works unchanged on
a fresh server. Pass `-e ansible_ssh_private_key_file=...` to force a specific one.

### Bootstrapping a development machine

Members of the `devboxes` group default to a `dev` administrator with zsh:

```ini
[devboxes]
devbox.example.com ansible_user=dev ansible_become=yes
```

Use the inventory alias for Ansible commands such as `--limit`, and set the
built-in `ansible_host` connection variable when the address differs. Set
`server_hostname` when Ansible should manage the system hostname. For example:

```ini
[devboxes]
devbox ansible_host=192.0.2.10 server_hostname=devbox ansible_user=dev ansible_become=yes
```

When `server_hostname` is set, the base playbook configures cloud-init to
preserve it and applies it immediately; no reboot is required. Leave it unset
on hosts where the system hostname should remain provider-managed.

To choose a different neutral account name, override both the managed account
and the normal SSH connection account, for example:

```ini
devbox.example.com ansible_user=admin admin_user_name=admin ansible_become=yes
```

Use the provider account for the first run; the inventory account is used from
the second run onward:

```bash
# Ubuntu images normally expose the ubuntu account initially.
ansible-playbook devbox.yml --limit devbox.example.com -e ansible_user=ubuntu

# The configured administrator now exists.
ansible-playbook devbox.yml --limit devbox.example.com
```

The profile installs Docker Engine, Compose, and Buildx, and adds the configured
administrator to the Docker group. Log out and reconnect before using Docker
without sudo. The firewall opens SSH only. Docker-published ports bypass UFW, so
bind development services to localhost and reach them through an SSH tunnel:

```yaml
ports:
  - "127.0.0.1:3000:3000"
```

```bash
ssh -L 3000:127.0.0.1:3000 devbox.example.com
```

After Ansible finishes, connect as the development user, clone the dotfiles, and
run their Linux bootstrap script. If zsh displays its new-user setup wizard, press
`q`; the bootstrap script will install the managed `.zshrc`:

```bash
ssh dev@devbox.example.com
git clone https://github.com/valdemarua/dotfiles.git ~/dotfiles
~/dotfiles/bin/bootstrap-linux
exec zsh
```

The idempotent script links the headless Linux configuration, installs mise and
Oh My Zsh when needed, and installs the configured runtimes and Linux CLI tools.

Verify the user environment and Docker installation:

```bash
mise config ls
mise ls --current
mise doctor
docker run --rm hello-world
```

The mise-managed tools remain scoped to the development user's home directory.
The dotfiles repository contains more detail about optional editor and tmux
plugin setup.

### Updating system packages

`update.yml` runs `apt upgrade` across all servers (or a subset). Ubuntu's `unattended-upgrades` already handles security patches automatically, so this is for when you want to deliberately update everything:

```bash
# All servers
ansible-playbook update.yml

# Specific server or group
ansible-playbook update.yml --limit your-server.com
ansible-playbook update.yml --limit dokploy_servers

# Test locally against Lima VM first
ansible-playbook update.yml -i hosts.local --limit lima-test
```

### Updating Dokploy

Dokploy updates are intentionally left as a manual operation. SSH to the server and run:

```bash
curl -sSL https://dokploy.com/install.sh | sh -s update
```

This re-pulls the latest Docker images and restarts services while preserving all data.

## Security Notes

### Dokploy dashboard is closed by default

Dokploy makes **the first visitor to `/register` the admin**. An exposed port 3000
is therefore a race against internet scanners, and the scanners win — they find a
new host within minutes. From there the panel grants privileged containers with
the host filesystem mounted, i.e. root.

So the `dokploy` role does not expose port 3000. Do the initial admin registration
over an SSH tunnel, which needs no open port:

```bash
ssh -N -L 3000:127.0.0.1:3000 your-server
# then browse http://localhost:3000 and register
```

Afterwards, serve the panel properly over HTTPS via Settings -> Web Server (it is
published through Traefik on 443) and enable 2FA. To allow direct access from
fixed addresses instead, set `dokploy_dashboard_allowed_ips`:

```yaml
dokploy_dashboard_allowed_ips:
  - 203.0.113.4
```

Note this is enforced in iptables' `DOCKER-USER` chain, **not** ufw — see below.

### Docker bypasses UFW

UFW does not protect Docker-published ports. When a service has a `ports:` mapping in docker-compose, Docker inserts iptables rules directly, bypassing UFW entirely — even if UFW has no rule allowing that port. **Any published port is reachable from the internet.**

Only publish ports that genuinely need to be public (reverse proxy, Dokploy dashboard). Internal services like Redis, PostgreSQL, or OpenSearch should never have a `ports:` mapping in production compose files.

### Removing a port mapping requires a container recreate

Deleting `ports:` from docker-compose and redeploying only recreates containers whose configuration changed. If only app containers are rebuilt (e.g. new image), the database container keeps running with its old port binding. To close the port, the container must be explicitly recreated:

```bash
docker compose -f /path/to/docker-compose.yml up -d --force-recreate redis
```

Or trigger a full redeploy from the Dokploy UI.

## Variables

Key variables to configure per environment (see `group_vars/`):

| Variable | Default | Description |
|---|---|---|
| `server_hostname` | unset | Optional system hostname; when set, cloud-init is configured to preserve it |
| `admin_user_name` | `deploy` | Administrator created by the base profile; devboxes override this to `dev` |
| `admin_user_shell` | `/bin/bash` | Login shell for the administrator; devboxes use `/bin/zsh` |
| `admin_user_ssh_keys` | `[]` | SSH public keys installed for the administrator |
| `admin_user_passwordless_sudo` | `true` | Whether to create a passwordless sudoers entry |
| `ufw_ssh_port` | `22` | SSH port always opened in ufw |
| `ufw_allowed_tcp_ports` | `[]` | Additional TCP ports opened for a server profile |
| `ufw_allowed_udp_ports` | `[]` | Additional UDP ports opened for a server profile |
| `packages_extra` | `[]` | Additional APT packages installed for a server profile |
| `docker_users` | configured administrator | Users added to the `docker` group |
| `sysctl_settings` | see `roles/sysctl/defaults/main.yml` | Kernel parameters written to `/etc/sysctl.d/99-server-tuning.conf` |
| `cert_manager_email` | `admin@example.com` | ACME registration email |
| `cert_manager_staging` | `true` | Use Let's Encrypt staging (set `false` for prod) |
| `argocd_chart_version` | `7.7.0` | ArgoCD Helm chart version |
| `k3s_version` | `""` | k3s version (empty = latest) |

## Testing

### Setup

Requires `uv` (`brew install uv`). uv manages Python and all dependencies automatically.

```bash
make setup
```

### Lint

```bash
make lint
```

### Molecule (role-level tests, Docker required)

Each base role has a Molecule scenario under `roles/<role>/molecule/default/`.

```bash
make test   # run all roles

# Useful during development
cd roles/fail2ban
uv run molecule converge   # apply role to container
uv run molecule verify     # run assertions only
uv run molecule destroy    # tear down
uv run molecule login      # shell into container for debugging
```

### CI

GitHub Actions runs `ansible-lint` + `molecule test` for each base role in parallel on every push. See `.github/workflows/ci.yml`.

### Integration (Lima VM)

Requires [Lima](https://github.com/lima-vm/lima) (`brew install lima`). If [colima](https://github.com/abiosoft/colima) is already installed, `limactl` is available without any extra steps.

```bash
bin/vm-setup                                            # create + start VM
ansible-playbook base.yml -i hosts.local --limit test  # run against VM

# SSH into the VM as deploy user
ssh -F ~/.lima/test/ssh.config -i ~/.ssh/server -l deploy lima-test
```

`bin/vm-setup` creates a Lima VM from `lima/test.yaml` (Ubuntu 26.04, Apple Virtualization.Framework) and writes connection details to `hosts.local`.
