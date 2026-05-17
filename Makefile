.PHONY: setup lint test test-role

ROLES ?= packages fail2ban ufw logrotate

setup:
	uv sync

lint:
	uv run ansible-lint

test:
	@for role in $(ROLES); do \
		echo "=== Testing role: $$role ==="; \
		cd roles/$$role && uv run molecule test && cd ../..; \
	done

test-role:
	cd roles/$(ROLE) && uv run molecule test
