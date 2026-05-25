## Playbooks

| Playbook | Roles applied | Target group | When to use |
|---|---|---|---|
| `base.yml` | deploy_user, ssh_hardening, packages, ufw, fail2ban, logrotate | `all` | Every run — first time as the provider's default user, after that as deploy |
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

A dedicated SSH key is used for all server access. The public key is stored in `group_vars/all.yml`. Set up the private key once per Mac:

```bash
# Copy the private key to ~/.ssh/server, then fix permissions
chmod 600 ~/.ssh/server
```

## Usage

1. Copy `hosts.sample` to `hosts` and update server addresses with `ansible_user=deploy`.
2. Set `traefik_email` in `group_vars/docker_servers.yml`.
3. Set `cert_manager_email` in `group_vars/k3s_servers.yml`.

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

### Updating Dokploy

Dokploy updates are intentionally left as a manual operation. SSH to the server and run:

```bash
curl -sSL https://dokploy.com/install.sh | sh -s update
```

This re-pulls the latest Docker images and restarts services while preserving all data.

## Variables

Key variables to configure per environment (see `group_vars/`):

| Variable | Default | Description |
|---|---|---|
| `ufw_ssh_port` | `22` | SSH port opened in ufw |
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

`bin/vm-setup` creates a Lima VM from `lima/test.yaml` (Ubuntu 24.04, Apple Virtualization.Framework) and writes connection details to `hosts.local`.
