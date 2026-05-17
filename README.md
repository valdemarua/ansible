## Playbooks

Three layered playbooks — each higher-level one imports the one below it:

| Playbook | Roles applied | Target group |
|---|---|---|
| `base.yml` | packages, ufw, fail2ban, logrotate | `all` |
| `docker_server.yml` | base + docker, traefik | `docker_servers` |
| `nginx_server.yml` | base + certbot | `nginx_servers` |
| `k3s_server.yml` | base + k3s, helm, cert_manager, argocd | `k3s_servers` |

## Roles

| Role | Purpose |
|---|---|
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

## Usage

1. Copy `hosts.sample` to `hosts` and update server addresses.
2. Set `traefik_email` in `group_vars/docker_servers.yml`.
3. Set `cert_manager_email` in `group_vars/k3s_servers.yml`.

```bash
# Generic server setup only
ansible-playbook base.yml

# Docker + Traefik (Let's Encrypt handled by Traefik)
ansible-playbook docker_server.yml --limit your-docker-server.com

# nginx / passenger / puma (certbot handles Let's Encrypt)
ansible-playbook nginx_server.yml --limit your-nginx-server.com

# k3s cluster
ansible-playbook k3s_server.yml --limit your-k3s-server.com

# Dry-run any playbook
ansible-playbook docker_server.yml --check
```

## Variables

Key variables to configure per environment (see `group_vars/`):

| Variable | Default | Description |
|---|---|---|
| `ssh_port` | `22` | SSH port opened in ufw |
| `traefik_email` | `admin@example.com` | ACME registration email |
| `traefik_dashboard_enabled` | `false` | Enable Traefik dashboard |
| `cert_manager_email` | `admin@example.com` | ACME registration email |
| `cert_manager_staging` | `true` | Use Let's Encrypt staging (set `false` for prod) |
| `argocd_chart_version` | `7.7.0` | ArgoCD Helm chart version |
| `k3s_version` | `""` | k3s version (empty = latest) |

## Testing

### Local: ansible-lint

```bash
pip install -r requirements.txt
ansible-lint
```

### Local: Molecule (role-level integration tests, Docker required)

Each base role has a Molecule scenario under `roles/<role>/molecule/default/`.

```bash
# Test a single role
cd roles/packages && molecule test

# Available steps (useful during development)
molecule converge   # apply the role to the container
molecule verify     # run verify.yml assertions only
molecule destroy    # tear down the container
molecule login      # SSH into the running container for debugging
```

### CI

GitHub Actions runs `ansible-lint` on every push, then runs `molecule test` for each base role in parallel. See `.github/workflows/ci.yml`.

### Manual: Vagrant

```bash
vagrant up
ansible-playbook base.yml --limit test
```

Use Vagrant for full end-to-end smoke tests of playbook combinations (e.g. docker_server.yml) that are harder to cover with Molecule's Docker driver alone.
