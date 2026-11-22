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

**Routine checks (no running Docker daemon required):**
```bash
make check  # ansible-lint + shared-service configuration tests
make lint   # lint alone
```

**Base role integration (Docker required):** `make test` runs the root
`molecule/default` scenario for packages, fail2ban and logrotate together.

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
- `devbox.yml` — imports base, then applies `docker` and `dev_services` for `devboxes`. The profile defaults to a `dev` account with zsh and adds Stow; use `admin_user_name` to choose a personal account instead. Its UFW profile exposes SSH only, and `docker_default_bind_ip: 127.0.0.1` keeps Docker-published ports (which bypass UFW) on localhost. `dev_services` deploys shared PostgreSQL 18 and Redis from a static Compose file to `/opt/dev-services`, explicitly binding both ports to loopback. Set `dev_services_postgres_password` in private inventory before provisioning; secret file tasks suppress output/diffs. Runtime/CLI setup remains in dotfiles.
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

CI runs `make check` and one `make test` job via `.github/workflows/ci.yml`.
The root Molecule scenario tests packages, fail2ban and logrotate together,
including idempotency and configuration validation. It does not exercise the
full base playbook or host-level SSH/firewall/networking behavior. Deliberate
Ubuntu host checks can use the optional Lima workflow; do not create a VM for
routine changes.

Shared services: `uv run python -m unittest discover -s tests/dev_services -v`
checks Compose configuration/password rendering without a daemon.
See README for a short manual smoke test on a disposable Ubuntu host. Keep this
role small: it deploys a static Compose file/private environment and invokes the
Compose module. The Molecule scenario does not cover `docker` or
`dev_services`. Follow `AGENTS.md` for testing scope and deployment boundaries.

Keep optional MySQL/MariaDB support deferred. Add a future shared service to
`roles/dev_services/files/compose.yaml` with its own profile and keep it out of
the default deployment task's `services` list. Optional credentials must not
break Compose parsing when absent. Project-specific OpenSearch, Memcached and
Selenium normally belong in application Compose files. See README for the full
role catalog, extension locations, credentials, test isolation and operations.

**colima users:** set `DOCKER_HOST` in `~/.zshrc` if needed for other tooling:
```bash
export DOCKER_HOST="unix://${HOME}/.colima/default/docker.sock"
```

## Role Conventions

All roles target Ubuntu/Debian (apt). Structure: `tasks/main.yml`, optionally `defaults/main.yml`, `templates/`, `handlers/main.yml`. Use `template:` with a bare filename — Ansible resolves from the role's `templates/` directory automatically. Do not use absolute paths in `src:`.

All module calls use FQCN (`ansible.builtin.*`, `community.general.*`, `community.docker.*`). Handler names use title case (`Restart fail2ban`) — `notify:` references must match exactly. Role variable names must be prefixed with the role name (e.g. `ufw_ssh_port`, not `ssh_port`).
