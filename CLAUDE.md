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
# First run on a fresh server (as provider's default user)
ansible-playbook base.yml --limit your-server.com -e ansible_user=root

# All subsequent runs (as the configured administrator from inventory)
ansible-playbook base.yml --limit your-server.com
ansible-playbook devbox.yml --limit your-devbox.com
ansible-playbook dokploy_server.yml --limit your-server.com
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

**Integration tests (against a local Lima VM):**
```bash
bin/vm-setup                           # create + start VM, writes hosts.local
ansible-playbook base.yml -i hosts.local --limit test
```

## Inventory

Copy `hosts.sample` to `hosts`, or run
`make link-inventory INVENTORY=/absolute/path/to/inventory` to link an external
inventory directory, including its `group_vars`. `hosts` is gitignored.
Keep authorized public keys in the inventory's `admin_user_ssh_keys` list;
the administrator role rejects an empty list. See the README's inventory example
for the expected hosts, connection settings, and key data. Inventory groups:
- `[dokploy_servers]` — `dokploy_server.yml`
- `[devboxes]` — `devbox.yml`; defaults to the `dev` administrator, overridable per host
- `[k3s_servers]` — `k3s_server.yml`
- `[test]` — local Lima VM, populated by `bin/vm-setup` into `hosts.local`

`ansible.cfg` sets `inventory = ./hosts` with `host_key_checking = False` always on.

## Architecture

**Playbook layering** via `import_playbook`:
- `base.yml` — foundation (packages, admin_user, ssh_hardening, sysctl, ufw, fail2ban, logrotate). Targets `all`. First run: pass `-e ansible_user=ubuntu` (or whatever the provider's default user is) to create the configured administrator. All subsequent runs: use that administrator from inventory. The account defaults to `deploy` for backward compatibility.
- `devbox.yml` — imports base, then installs Docker for `devboxes`. The profile defaults to a `dev` account with zsh and adds Stow; use `admin_user_name` to choose a personal account instead. Its UFW profile exposes SSH only, and `docker_default_bind_ip: 127.0.0.1` keeps Docker-published ports (which bypass UFW) on localhost.
- `dokploy_server.yml` — imports `base.yml`, then installs Docker and Dokploy for `dokploy_servers`. Dokploy owns its application stack and Traefik instance.
- `k3s_server.yml` — imports `base.yml`, then applies k3s + helm + cert_manager + argocd to `k3s_servers`.

**Variables** live in `group_vars/`:
- `group_vars/all.yml` — `ufw_ssh_port`, `timezone`
- `group_vars/devboxes.yml` — development administrator defaults and additional packages
- `group_vars/dokploy_servers.yml` — public web ports
- `group_vars/k3s_servers.yml` — `cert_manager_email`, `cert_manager_staging`, `argocd_chart_version`, public web ports

**TLS strategy by playbook:**
- `dokploy_server.yml` — Dokploy manages its own Traefik proxy and certificates.
- `k3s_server.yml` — cert-manager + ClusterIssuer. `cert_manager_staging: true` by default; set `false` for production.

**k3s role** copies `/etc/rancher/k3s/k3s.yaml` to `~/.kube/config` for `ansible_user`. The cert_manager and argocd roles run as root (`become: true`) and use `KUBECONFIG: /etc/rancher/k3s/k3s.yaml` directly.

## Testing

CI runs `ansible-lint` + molecule (Docker) via `.github/workflows/ci.yml`. Integration testing is done locally against a Lima VM (`bin/vm-setup` + `ansible-playbook -i hosts.local`).

**colima users:** set `DOCKER_HOST` in `~/.zshrc` if needed for other tooling:
```bash
export DOCKER_HOST="unix://${HOME}/.colima/default/docker.sock"
```

## Role Conventions

All roles target Ubuntu/Debian (apt). Structure: `tasks/main.yml`, optionally `defaults/main.yml`, `templates/`, `handlers/main.yml`. Use `template:` with a bare filename — Ansible resolves from the role's `templates/` directory automatically. Do not use absolute paths in `src:`.

All module calls use FQCN (`ansible.builtin.*`, `community.general.*`, `community.docker.*`). Handler names use title case (`Restart fail2ban`) — `notify:` references must match exactly. Role variable names must be prefixed with the role name (e.g. `ufw_ssh_port`, not `ssh_port`).
