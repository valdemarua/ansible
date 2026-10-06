## Playbooks

| Playbook | Roles applied | Target group | When to use |
|---|---|---|---|
| `base.yml` | deploy_user, ssh_hardening, packages, sysctl, ufw, fail2ban, logrotate | `all` | Every run — first time as the provider's default user, after that as deploy |
| `dokploy_server.yml` | base + docker, dokploy | `dokploy_servers` | Dokploy PaaS servers |
| `docker_server.yml` | base + docker, traefik | `docker_servers` | Plain Docker + Traefik servers |
| `nginx_server.yml` | base + certbot | `nginx_servers` | nginx/passenger/puma servers |
| `k3s_server.yml` | base + k3s, helm, cert_manager, argocd | `k3s_servers` | k3s servers |

## Roles

| Role | Purpose |
|---|---|
| `deploy_user` | Creates deploy user with SSH key and passwordless sudo |
| `dokploy` | Dokploy PaaS — installs via official script (Docker Swarm + Traefik + Postgres + Redis) |
| `packages` | Essential system packages (tmux, vim, git, curl, …) |
| `sysctl` | Kernel tuning — memory overcommit (Redis), low swappiness, larger TCP backlog |
| `ufw` | Firewall — allows SSH, 80, 443; denies everything else |
| `fail2ban` | Bans IPs after repeated SSH failures |
| `logrotate` | Configures system log rotation |
| `certbot` | Let's Encrypt via snap — for nginx/passenger/puma setups |
| `docker` | Docker CE + compose plugin via official apt repo |
| `traefik` | Traefik v3 reverse proxy with automatic Let's Encrypt (ACME) |
| `k3s` | Lightweight Kubernetes via k3s |
| `helm` | Helm CLI |
| `cert_manager` | cert-manager + ClusterIssuer for Let's Encrypt |
| `argocd` | ArgoCD GitOps controller via Helm |

## SSH Key Setup

A dedicated SSH key is used for all server access. The public key is stored in
`group_vars/all.yml`. Set up the private key once per machine:

```bash
# Copy the private key to ~/.ssh/server, then fix permissions
chmod 600 ~/.ssh/server
```

**If you are using this repo for your own servers, replace that key first.** The
checked-in key is the repo author's; leaving it in place grants them SSH access to
every server you provision, and `deploy` has passwordless sudo. Generate your own
and swap it in:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/server -C "server access"
```

```yaml
# group_vars/all.yml
deploy_user_ssh_keys:
  - "ssh-ed25519 AAAA... your-key"
```

Removing a key from `deploy_user_ssh_keys` does not revoke it: `authorized_key`
adds keys but never prunes ones already on a server. Remove those by hand, or with
`state: absent`.

## Usage

1. Provide an inventory, either by hand or from a private repo:
   - `cp hosts.sample hosts`, then set server addresses with `ansible_user=deploy`, or
   - `make link-inventory` to symlink one in (defaults to
     `~/dotfiles-private/ansible/hosts`; override with
     `make link-inventory INVENTORY=/path/to/hosts`).
2. Set `traefik_email` in `group_vars/docker_servers.yml`.
3. Set `cert_manager_email` in `group_vars/k3s_servers.yml`.

A server is bootstrapped once as the provider's default user, and run as the
deploy user from then on:

```bash
# Fresh server — connect as the provider's default user.
# AWS uses 'ubuntu', most others (Hetzner, DigitalOcean, Vultr) use 'root'.
# This creates the deploy user, hardens SSH, and configures the base system.
ansible-playbook base.yml --limit your-server.com -e ansible_user=root

# All subsequent runs — the deploy user now exists and is in inventory
ansible-playbook base.yml --limit your-server.com
ansible-playbook dokploy_server.yml --limit your-server.com
ansible-playbook docker_server.yml --limit your-server.com
ansible-playbook nginx_server.yml --limit your-server.com
ansible-playbook k3s_server.yml --limit your-server.com

# Dry-run
ansible-playbook base.yml --check --limit your-server.com
```

If the inventory pins `ansible_ssh_private_key_file` (the deploy key), SSH still
falls back to your default keys during bootstrap, so the above works unchanged on
a fresh server. Pass `-e ansible_ssh_private_key_file=...` to force a specific one.

### Updating system packages

`update.yml` runs `apt upgrade` across all servers (or a subset). Ubuntu's `unattended-upgrades` already handles security patches automatically, so this is for when you want to deliberately update everything:

```bash
# All servers
ansible-playbook update.yml

# Specific server or group
ansible-playbook update.yml --limit your-server.com
ansible-playbook update.yml --limit docker_servers

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
| `ufw_ssh_port` | `22` | SSH port opened in ufw |
| `sysctl_settings` | see `roles/sysctl/defaults/main.yml` | Kernel parameters written to `/etc/sysctl.d/99-server-tuning.conf` |
| `traefik_email` | `admin@example.com` | ACME registration email |
| `traefik_dashboard_enabled` | `false` | Enable Traefik dashboard |
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
