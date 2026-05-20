.PHONY: setup lint

setup:
	uv sync
	uv run ansible-galaxy collection install -r requirements.yml

lint:
	uv run ansible-lint
