.PHONY: setup lint test link-inventory

# Private inventory lives in dotfiles-private; override to point elsewhere.
INVENTORY ?= $(HOME)/dotfiles-private/ansible/hosts

setup:
	uv sync
	uv run ansible-galaxy collection install -r requirements.yml

# Link the private inventory into this repo (hosts is gitignored).
link-inventory:
	@test -f "$(INVENTORY)" || { \
		echo "No inventory at $(INVENTORY)"; \
		echo "Clone dotfiles-private, or run: make link-inventory INVENTORY=/path/to/hosts"; \
		exit 1; }
	@ln -sfn "$(INVENTORY)" hosts
	@echo "hosts -> $(INVENTORY)"

lint:
	uv run ansible-lint

test:
	@for role in packages fail2ban logrotate; do \
		echo "=== Testing $$role ==="; \
		(cd roles/$$role && uv run molecule test) || exit 1; \
	done
