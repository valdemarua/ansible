.PHONY: setup lint test link-inventory

# Pass the path to your inventory file or directory when linking it.
INVENTORY ?=

setup:
	uv sync
	uv run ansible-galaxy collection install -r requirements.yml

# Link the inventory directory, including group_vars (hosts is gitignored).
link-inventory:
	@test -e "$(INVENTORY)" || { \
		echo "No inventory at $(INVENTORY)"; \
		echo "Run: make link-inventory INVENTORY=/path/to/inventory"; \
		exit 1; }
	@test ! -e hosts || test -L hosts || { \
		echo "hosts already exists and is not a symlink; move it before linking an inventory"; \
		exit 1; }
	@ln -sfn "$(abspath $(INVENTORY))" hosts
	@echo "hosts -> $(INVENTORY)"

lint:
	uv run ansible-lint

test:
	@for role in packages fail2ban logrotate; do \
		echo "=== Testing $$role ==="; \
		(cd roles/$$role && uv run molecule test) || exit 1; \
	done
