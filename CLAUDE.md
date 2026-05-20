# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

**Install all dependencies (Python deps + Ansible Galaxy collections):**
```bash
make setup
```
Requires `uv` (`brew install uv`). uv handles Python automatically.

**Run a playbook:**
```bash
ansible-playbook base.yml
ansible-playbook docker_server.yml --limit your-server.com
ansible-playbook nginx_server.yml --limit your-server.com
ansible-playbook k3s_server.yml --limit your-server.com
```

**Dry-run:**
```bash
ansible-playbook base.yml --check
```

**Lint:**
```bash
make lint
```

**Integration tests (against a local VM):**
```bash
vagrant up
ansible-playbook base.yml --limit test
# then validate with goss on the VM — see tests/
```

## Inventory

Copy `hosts.sample` to `hosts`. Inventory groups:
- `[docker_servers]` — `docker_server.yml`
- `[nginx_servers]` — `nginx_server.yml`
- `[k3s_servers]` — `k3s_server.yml`
- `[test]` — Vagrant VM at `192.168.56.2`

`ansible.cfg` sets `inventory = ./hosts` with `host_key_checking = False` always on.

## Architecture

**Playbook layering** via `import_playbook`:
- `base.yml` — foundation (packages, ufw, fail2ban, logrotate). Targets `all`.
- `docker_server.yml` — imports `base.yml`, then applies docker + traefik to `docker_servers`.
- `nginx_server.yml` — imports `base.yml`, then applies certbot to `nginx_servers`. Extend with your own nginx/passenger role.
- `k3s_server.yml` — imports `base.yml`, then applies k3s + helm + cert_manager + argocd to `k3s_servers`.

**Variables** live in `group_vars/`:
- `group_vars/all.yml` — `ufw_ssh_port`, `timezone`
- `group_vars/docker_servers.yml` — `traefik_email`, `traefik_dashboard_enabled`, `traefik_network`
- `group_vars/k3s_servers.yml` — `cert_manager_email`, `cert_manager_staging`, `argocd_chart_version`

**SSL strategy by playbook:**
- `docker_server.yml` — Traefik handles ACME automatically per-container via labels. No certbot.
- `nginx_server.yml` — certbot (via snap) manages certs in `/etc/letsencrypt/`.
- `k3s_server.yml` — cert-manager + ClusterIssuer. `cert_manager_staging: true` by default; set `false` for production.

**Traefik** runs as a Docker container in `/opt/traefik/` (templated `docker-compose.yml` + `traefik.yml`). The `traefik_network` Docker network is created by the traefik role and must be declared `external: true` in any other docker-compose stack that joins it.

**k3s role** copies `/etc/rancher/k3s/k3s.yaml` to `~/.kube/config` for `ansible_user`. The cert_manager and argocd roles run as root (`become: true`) and use `KUBECONFIG: /etc/rancher/k3s/k3s.yaml` directly.

## Testing

CI runs `ansible-lint` only (`.github/workflows/ci.yml`). Integration testing is done locally against Vagrant VMs using goss for assertions (see `tests/`).

**colima users:** set `DOCKER_HOST` in `~/.zshrc` if needed for other tooling:
```bash
export DOCKER_HOST="unix://${HOME}/.colima/default/docker.sock"
```

## Role Conventions

All roles target Ubuntu/Debian (apt). Structure: `tasks/main.yml`, optionally `defaults/main.yml`, `templates/`, `handlers/main.yml`. Use `template:` with a bare filename — Ansible resolves from the role's `templates/` directory automatically. Do not use absolute paths in `src:`.

All module calls use FQCN (`ansible.builtin.*`, `community.general.*`, `community.docker.*`). Handler names use title case (`Restart fail2ban`) — `notify:` references must match exactly. Role variable names must be prefixed with the role name (e.g. `ufw_ssh_port`, not `ssh_port`).
