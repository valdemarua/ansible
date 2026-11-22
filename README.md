## Playbooks

| Playbook | Roles applied | Target group | When to use |
|---|---|---|---|
| `base.yml` | packages, admin_user, ssh_hardening, sysctl, ufw, fail2ban, logrotate | `all` | Every run — first time as the provider's default user, after that as the configured administrator |
| `devbox.yml` | base + docker, dev_services | `devboxes` | Development machines with Docker, shared PostgreSQL/Redis and an SSH-only firewall |
| `dokploy_server.yml` | base + docker, dokploy | `dokploy_servers` | Dokploy PaaS servers |
| `k3s_server.yml` | base + k3s, helm, cert_manager, argocd | `k3s_servers` | k3s servers |

## Roles

Every role lives under `roles/<name>/`. The links below lead to its implementation
and default configuration. Profile overrides belong in `group_vars/`; private or
host-specific settings belong in the external inventory.

| Role | Behavior and scope | Configuration |
|---|---|---|
| [`packages`](roles/packages/tasks/main.yml) | Base system tools and native build libraries; adds profile-specific packages without purging existing ones. | [`packages_base`, `packages_extra`](roles/packages/defaults/main.yml) |
| [`admin_user`](roles/admin_user/tasks/main.yml) | Creates the administrator and home, adds supplied SSH keys, and manages the optional passwordless sudo rule. Adding keys does not revoke old ones. | [`admin_user_name`, `admin_user_shell`, `admin_user_ssh_keys`, `admin_user_passwordless_sudo`](roles/admin_user/defaults/main.yml); keys are required |
| [`ssh_hardening`](roles/ssh_hardening/tasks/main.yml) | Installs the SSH hardening configuration and restarts SSH when it changes. | [`ssh_hardening_max_auth_tries`](roles/ssh_hardening/defaults/main.yml); see the [configuration template](roles/ssh_hardening/templates/hardening.conf.j2) |
| [`sysctl`](roles/sysctl/tasks/main.yml) | Sets Redis-friendly memory overcommit, low swappiness, TCP backlog and inotify limits. | [`sysctl_settings`](roles/sysctl/defaults/main.yml) |
| [`ufw`](roles/ufw/tasks/main.yml) | Allows SSH and profile-specific TCP/UDP ports, denying other incoming traffic. Docker-published ports bypass UFW. | [`ufw_ssh_port`, `ufw_allowed_tcp_ports`, `ufw_allowed_udp_ports`](roles/ufw/defaults/main.yml) |
| [`fail2ban`](roles/fail2ban/tasks/main.yml) | Installs/enables fail2ban and deploys the SSH jail configuration. | [Daemon settings](roles/fail2ban/templates/fail2ban.local), [jail settings](roles/fail2ban/templates/jail.local) |
| [`logrotate`](roles/logrotate/tasks/main.yml) | Installs logrotate and manages system log rotation. | [`logrotate_frequency`, `logrotate_keep`, `logrotate_compress`](roles/logrotate/defaults/main.yml) |
| [`docker`](roles/docker/tasks/main.yml) | Installs Docker CE, Compose and Buildx from Docker's APT repository; enables Docker, configures log limits/default binding, and adds administrator accounts to the Docker group. | [`docker_users`, `docker_default_bind_ip`, `docker_log_*`](roles/docker/defaults/main.yml) |
| [`dev_services`](roles/dev_services/tasks/main.yml) | DevBox only: deploys one shared PostgreSQL 18 and Redis instance, loopback ports, persistent volumes and health checks. Requires the Docker role first. | [`dev_services_dir`, `dev_services_postgres_password`](roles/dev_services/defaults/main.yml); [operating guide below](#shared-development-services) |
| [`dokploy`](roles/dokploy/tasks/main.yml) | Installs Dokploy through its official installer, including its Swarm application stack and Traefik. Restricts direct dashboard access with Docker-aware firewall rules. | [`dokploy_port`, `dokploy_dashboard_allowed_ips`, `dokploy_public_interface`](roles/dokploy/defaults/main.yml) |
| [`k3s`](roles/k3s/tasks/main.yml) | Installs the k3s server and copies kubeconfig for the connection user. | [`k3s_version`, `k3s_extra_args`](roles/k3s/defaults/main.yml) |
| [`helm`](roles/helm/tasks/main.yml) | Installs the Helm CLI using the official Helm installer. | [`helm_version`](roles/helm/defaults/main.yml) |
| [`cert_manager`](roles/cert_manager/tasks/main.yml) | Installs cert-manager and CRDs via Helm, waits for readiness, then applies the Let's Encrypt ClusterIssuer. | [`cert_manager_version`, namespace, email and staging settings](roles/cert_manager/defaults/main.yml) |
| [`argocd`](roles/argocd/tasks/main.yml) | Installs ArgoCD via Helm and waits for the server deployment. | [`argocd_chart_version`, `argocd_namespace`](roles/argocd/defaults/main.yml) |

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
the second run onward. First configure the shared PostgreSQL password as described
under [shared development services](#shared-development-services):

```bash
# Ubuntu images normally expose the ubuntu account initially.
ansible-playbook devbox.yml --limit devbox.example.com -e ansible_user=ubuntu

# The configured administrator now exists.
ansible-playbook devbox.yml --limit devbox.example.com
```

The profile also installs Stow and libvips (with its CLI tools) for native
development. These profile-specific packages are listed in `group_vars/devboxes.yml`.

The profile installs Docker Engine, Compose, and Buildx, and adds the configured
administrator to the Docker group. Log out and reconnect before using Docker
without sudo. The firewall opens SSH only. Docker-published ports bypass UFW, so
the devbox profile sets `docker_default_bind_ip: "127.0.0.1"`: a mapping such as
`"5432:5432"` listens on localhost only. Writing the address explicitly keeps the
same behavior on machines without that default, and an explicit
`"0.0.0.0:5432:5432"` still publishes to the internet. Reach services through an
SSH tunnel:

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

### Shared development services

`devbox.yml` runs `dev_services` after `docker`, only for the `devboxes` group.
The role copies [its static Compose file](roles/dev_services/files/compose.yaml)
to `/opt/dev-services/compose.yaml` with the fixed project name `dev-services`.
It starts PostgreSQL 18 (`postgres:18.7-bookworm`) and Redis
(`redis:8.10.3-alpine`), with named volumes, health checks and
`restart: unless-stopped`. PostgreSQL 18 mounts `/var/lib/postgresql`; Redis
mounts `/data` and enables AOF with a one-second fsync policy. A host crash can
lose approximately the last second of Redis writes; persistence is not a backup.

| Service | Host-native endpoint | Authentication / storage |
|---|---|---|
| PostgreSQL | `127.0.0.1:5432` | Bootstrap user `postgres`; password from private inventory; volume `dev-services_postgres_data` |
| Redis | `127.0.0.1:6379` | No password; trusted local development processes only; volume `dev-services_redis_data` |

Both ports bind explicitly to IPv4 loopback, independently of the Docker daemon
default. Containerized applications cannot reach them through their own
`127.0.0.1`; design their networking separately before migrating them.

#### Credentials and provisioning

Set this in your **external inventory's** `group_vars/devboxes.yml` or the
DevBox's host variables, not in this public repository:

```yaml
dev_services_postgres_password: "replace-with-a-unique-private-password"
# Optional; normally leave this unchanged:
# dev_services_dir: /opt/dev-services
```

Use a nonempty single-line string. Quotes, backslashes, dollar signs and Unicode
are supported. Ansible Vault can encrypt the private variable file; pass
`--ask-vault-pass` or your configured vault identity when provisioning.
The role rejects missing credentials before changing shared-service files and
suppresses secret values/diffs in Ansible output. It creates the directory as
`root:docker` mode `0750` and `.env` as `root:docker` mode `0640`. The existing
Docker administrator can read them and run Compose after reconnecting for group
membership to take effect. Docker-group membership is root-equivalent; this is
not isolation between untrusted developers or agents.

```bash
ansible-playbook devbox.yml --limit your-devbox
cd /opt/dev-services
docker compose ps
docker compose logs --tail 100 postgres redis
docker compose up -d
docker compose exec postgres psql -U postgres
docker compose exec redis redis-cli ping
```

The default run targets only PostgreSQL/Redis, pulls missing images and avoids
unnecessary recreation. Provisioning restarts a stopped default service.
`--check` validates inputs and predicts file changes, but skips Compose
startup; it cannot verify readiness. A pending Docker configuration
restart is applied before services start. No additional systemd unit, automatic
image updater or Docker pruning is installed.

Before first deployment, inspect occupied ports with `sudo ss -ltnp` and
`docker ps`. Compose reports a port-binding failure if another instance owns
5432 or 6379; it does not stop the other listener. Back up any
retained data, then deliberately stop/migrate the project-local instance. Do not
delete its volume. A failed Compose deployment can be inspected using `docker
compose ps -a` and `docker compose logs` from the shared directory. Avoid sharing
resolved `docker compose config`, `.env` or container inspection output: they
can contain the PostgreSQL password.

#### Project databases and parallel tests

Use separate non-superuser application roles and databases. From the interactive
`psql` session above, for example:

```sql
CREATE ROLE content_flow LOGIN CREATEDB;
\password content_flow
CREATE DATABASE content_flow_development OWNER content_flow;
CREATE DATABASE content_flow_test_worktree_a OWNER content_flow;
CREATE DATABASE content_flow_test_worktree_b OWNER content_flow;
```

Use that application's role/password in its host-native database configuration
with host `127.0.0.1`, port `5432`, and its own database name. Grant `CREATEDB`
only when framework test setup needs it. Include project, worktree and parallel
worker identity in test database names; a test suite must never drop or recreate
another worktree's database. Different projects should have different roles.

For Redis, allocate distinct database indexes and key prefixes per project,
environment and worktree. Redis has a finite number of logical databases; keep
the allocation documented in the application. Prefixes **do not protect against
`FLUSHDB` or `FLUSHALL`**. Do not run these against a shared instance. A suite
that requires destructive resets needs its own isolated Redis instance or a
safe application-specific reset strategy before adoption.

Existing project Compose files remain available for standalone use. On DevBox,
agents should use the shared endpoints rather than starting duplicate database
containers. Application repository changes and data migration are separate from
this infrastructure change. Verify extensions, client compatibility, database
names and test isolation before switching each application.

#### Adding other services when needed

OpenSearch, Memcached, MySQL and MariaDB are **not installed by this role**.
MySQL/MariaDB credentials and image choices are deferred until a project needs
them. Add services at the appropriate location:

| Need | Where to add it |
|---|---|
| Project-specific OpenSearch, Selenium, Memcached or another dependency | That application's `compose.yaml` / `docker-compose.yml`. Start the named service explicitly, for example `docker compose up -d opensearch`, after checking that `depends_on` will not also start duplicate PostgreSQL/Redis instances. |
| A service deliberately shared by several DevBox projects | Add its definition to [`roles/dev_services/files/compose.yaml`](roles/dev_services/files/compose.yaml). Use an explicit tested image, loopback-only port and health check; add persistence where appropriate. Use a separate Compose profile for optional services so ordinary provisioning does not pull or start them. |
| Credentials for a future shared service | Add role-prefixed private inputs in [`roles/dev_services/defaults/main.yml`](roles/dev_services/defaults/main.yml), render them in [`templates/dev-services.env.j2`](roles/dev_services/templates/dev-services.env.j2), and validate them when that service is requested. Supply real values only through the external inventory. |
| A change to which shared services Ansible starts | Update the explicit `services` list in [`roles/dev_services/tasks/main.yml`](roles/dev_services/tasks/main.yml), tests under [`tests/dev_services/`](tests/dev_services/) and this guide. Keep optional services outside that list. |

For future optional MySQL/MariaDB profiles, reserve `127.0.0.1:3306` and
`127.0.0.1:3307` respectively and mount distinct volumes at `/var/lib/mysql`.
Avoid `${OPTIONAL_PASSWORD:?…}` in disabled profiles: Compose still interpolates
their configuration, so missing optional secrets would break default commands.
Require safe credentials at optional startup without enabling empty-password
modes. Then document targeted `docker compose up -d mysql` / `mariadb` and
`docker compose stop mysql` / `mariadb` operations. With `unless-stopped`, a
previously running optional container returns after reboot; a manually stopped
one stays stopped, including across default provisioning.

#### Backups, updates and recovery

Keep database backups outside the stack's volumes and copy important backups
off the VM. Treat role dumps and database dumps as private data. For example,
from `/opt/dev-services`, with an existing project database:

```bash
umask 077
mkdir -p ~/dev-services-backups
docker compose exec -T postgres pg_dumpall -U postgres --globals-only > ~/dev-services-backups/roles.sql
docker compose exec -T postgres pg_dump -U postgres -Fc content_flow_development > ~/dev-services-backups/content_flow.dump

# Rehearse restoration into a separate database, preserving the original.
docker compose exec -T postgres createdb -U postgres restore_check
docker compose exec -T postgres pg_restore -U postgres -d restore_check < ~/dev-services-backups/content_flow.dump
```

Verify the restored data before adopting the backup procedure. For a replacement
server, review/restore the saved roles first (the bootstrap `postgres` role
already exists), create databases with their original owners, then restore each
dump. Check available disk space and extensions. Never copy a live PostgreSQL
data directory as a logical backup. Redis AOF persistence does not provide an
off-host backup; when its contents matter, use Redis's documented backup
procedure or stop Redis during a consistent volume backup, and rehearse restore
on a separate instance.

Image updates are deliberate: back up, edit the pinned tag in the role's Compose
file, test it on the disposable VM, and provision the selected DevBox. For an
explicit refresh of the same tag, use `docker compose pull postgres redis`, then
`docker compose up -d --wait postgres redis` during a chosen maintenance window.
Ordinary provisioning/manual `up` uses `pull_policy: missing` and does not
refresh cached images. Do not run `down -v`, remove volumes or prune Docker.

Changing the PostgreSQL major version requires a separate tested migration
(`pg_dump`/restore or `pg_upgrade`); changing the tag alone cannot upgrade the
data directory. Changing `.env` alone does not rotate an initialized database
password: use `\password postgres` in `psql` as well, then update the private
inventory and reprovision during the same controlled operation.

For application rollback, stop its use of the shared endpoint and deliberately
restart its original Compose service with its retained volume, resolving port
conflicts first. Reconcile writes made after cutover before switching back; an
old volume is not an automatically current copy of the shared database.

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
| `docker_default_bind_ip` | `""` (all interfaces) | Host address for published ports that name none; devboxes use `127.0.0.1` |
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

### Routine checks

```bash
make check  # lint + shared-service configuration tests; no running Docker needed
make lint   # lint alone
```

`make check` needs the Docker Compose CLI for parsing, but does not start
containers or pull images. Documentation-only changes need no infrastructure
test run.

### Molecule (base role integration, Docker required)

One scenario under [`molecule/default/`](molecule/default/) applies `packages`,
`fail2ban` and `logrotate` together on one Ubuntu 26.04/systemd container. It
checks idempotency, a configured extra package, fail2ban configuration and the
active SSH jail, plus logrotate configuration and a nondefault retention value.

```bash
make test

# Useful during development, from the repository root
uv run molecule converge   # apply the three roles to the test container
uv run molecule verify     # run assertions only
uv run molecule destroy    # tear down
uv run molecule login      # shell into container for debugging
```

Run this for changes to those three roles when Docker is available. It does not
cover all roles in `base.yml` or the shared-service stack. SSH access, UFW,
Docker networking and reboot behavior need a deliberate Ubuntu-host check
before deployment when those behaviors change. Do not automatically create a
VM or start Docker to compensate for unavailable local runtime checks.

### CI

GitHub Actions runs two jobs: `make check` and the single `make test` scenario.
See [the workflow](.github/workflows/ci.yml). Both use the same commands as local
development.

### Integration (Lima VM)

Requires [Lima](https://github.com/lima-vm/lima) (`brew install lima`). If [colima](https://github.com/abiosoft/colima) is already installed, `limactl` is available without any extra steps.

```bash
bin/vm-setup                                            # create + start VM
ansible-playbook base.yml -i hosts.local --limit test  # run against VM

# SSH into the VM as deploy user
ssh -F ~/.lima/test/ssh.config -i ~/.ssh/server -l deploy lima-test
```

`bin/vm-setup` creates a Lima VM from `lima/test.yaml` (Ubuntu 26.04, Apple Virtualization.Framework) and writes connection details to `hosts.local`.

### Shared-services validation

Daemon-free configuration checks require the Docker Compose CLI:

```bash
uv run python -m unittest discover -s tests/dev_services -v
```

They check literal credential rendering, rejection of missing credentials and
loopback-only core endpoints without pulling images or starting containers.

For a manual smoke test, use a disposable Ubuntu host in a test inventory's
`devboxes` group, with test SSH keys and a synthetic PostgreSQL password. Run
`devbox.yml` against that explicit inventory/host twice and check that the second
run reports no changes. From `/opt/dev-services` on that host:

```bash
docker compose ps
docker compose exec -T postgres psql -U postgres -Atc 'SELECT 1'
docker compose exec -T redis redis-cli ping
```

Expect two healthy containers, `1` and `PONG`, and only `127.0.0.1` port bindings.
These checks do not prove host-native authentication or reboot durability; verify
those during a deliberate test deployment when needed. Do not create a VM or
start Docker just to run the daemon-free configuration checks. The existing
Molecule scenario covers the three selected base roles, not this Compose stack.
