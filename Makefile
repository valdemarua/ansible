.PHONY: setup lint test

setup:
	uv sync
	uv run ansible-galaxy collection install -r requirements.yml

lint:
	uv run ansible-lint

test:
	@for role in packages fail2ban logrotate; do \
		echo "=== Testing $$role ==="; \
		(cd roles/$$role && uv run molecule test) || exit 1; \
	done
