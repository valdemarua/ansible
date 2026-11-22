# Repository instructions

Read `CLAUDE.md` for architecture, commands and role conventions, and `README.md`
for the role catalog and operating procedures. Use FQCN modules and role-prefixed
variables. Reuse the existing playbooks and external-inventory workflow.

## Keep changes and tests proportional

- `dev_services` is a small Compose deployment: static service definitions,
  protected private configuration, and `community.docker.docker_compose_v2`.
  Avoid custom lifecycle managers, elaborate test harnesses or general-purpose
  service generation.
- Run `make check` for Ansible/Compose changes: lint plus three daemon-free
  configuration tests for secret interpolation, missing credentials and
  loopback-only core endpoints. This needs the Compose CLI, not a running Docker
  daemon. Documentation-only changes need no infrastructure test run.
- Run `make test` when changing `packages`, `fail2ban` or `logrotate` and Docker
  is available. One root `molecule/default` scenario applies these roles together,
  checks idempotency, and verifies an extra package, the active SSH jail and valid
  logrotate configuration with a nondefault override. It does not test all of
  `base.yml`, other roles or `dev_services`; do not claim broader coverage.
- Use the README's short manual smoke test on an explicitly selected disposable
  host when runtime verification is warranted. Do not create VMs, start Docker,
  reboot machines or install extra test infrastructure for routine checks unless
  the user requests it. Report unavailable checks and their reason accurately.
- SSH access, firewall, Docker networking and boot behavior need a deliberate
  Ubuntu-host check before deployment when those behaviors change. A privileged
  Molecule container does not establish those host-level guarantees.
- Add tests for material behavior or regression risk; avoid tests that merely
  duplicate task definitions. Never claim persistence, native connectivity or
  idempotency was verified from lint/configuration parsing alone.

## Scope and safety

- Apply `dev_services` only through the `devboxes` play after `docker`. Preserve
  Dokploy, k3s and base provisioning behavior.
- Default shared services are PostgreSQL 18 and Redis. Keep MySQL/MariaDB
  deferred until requested; project-specific OpenSearch, Memcached and Selenium
  normally remain in application Compose files. README gives extension paths.
- Keep credentials in private inventory, never in Git. Suppress secret task
  output/diffs; retain explicit loopback ports, named volumes and controlled
  image updates. Do not remove data volumes or prune Docker automatically.
- Keep README's role catalog, operating guide and relevant architecture notes
  accurate when adding or changing a role.
- Implementation does not authorize live deployment or application data
  migration. Use explicit test inventories for checks and obtain separate
  direction before deploying to a live host.
