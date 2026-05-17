.PHONY: setup lint test test-role

ROLES ?= packages fail2ban ufw logrotate

setup:
	pip install -r requirements.txt

lint:
	ansible-lint

test:
	@for role in $(ROLES); do \
		echo "=== Testing role: $$role ==="; \
		cd roles/$$role && molecule test && cd ../..; \
	done

test-role:
	cd roles/$(ROLE) && molecule test
