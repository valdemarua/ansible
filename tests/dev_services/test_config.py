"""Daemon-free checks for the deployed Compose/credential contract.

Run with: uv run python -m unittest discover -s tests/dev_services -v
Requires the Docker Compose CLI, but never starts containers or pulls images.
"""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from ansible.plugins.filter.core import to_json
from jinja2 import Environment, StrictUndefined


ROLE = Path(__file__).resolve().parents[2] / "roles" / "dev_services"


class ComposeConfigurationTest(unittest.TestCase):
    def compose(self, password=None, *args):
        template_env = Environment(undefined=StrictUndefined)
        template_env.filters["to_json"] = to_json
        template = template_env.from_string(
            (ROLE / "templates" / "dev-services.env.j2").read_text()
        )
        # Eliminate operator environment overrides from these synthetic tests.
        env = {key: value for key, value in os.environ.items()
               if not key.startswith("COMPOSE_") and key != "POSTGRES_PASSWORD"}
        with tempfile.TemporaryDirectory() as directory:
            env_file = Path(directory) / ".env"
            env_file.write_text("" if password is None else template.render(
                dev_services_postgres_password=password
            ))
            return subprocess.run(
                ["docker", "compose", "--env-file", str(env_file), "-f",
                 str(ROLE / "files" / "compose.yaml"), "config", *args],
                env=env, capture_output=True, text=True, check=False,
            )

    def test_password_round_trips_without_dotenv_interpolation(self):
        for password in ["simple", "quote'\"-slash\\-dollar$abc-${abc}-$$-# space",
                         "literal\\n-is-not-a-newline", "пароль-秘密"]:
            with self.subTest(password=password):
                result = self.compose(password, "--environment")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("POSTGRES_PASSWORD=" + password,
                              result.stdout.splitlines())

    def test_unconfigured_credentials_fail_closed(self):
        for password in (None, ""):
            result = self.compose(password, "--quiet")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("PostgreSQL password", result.stderr)

    def test_only_core_services_publish_explicit_loopback_ports(self):
        result = self.compose("synthetic", "--format", "json")
        self.assertEqual(result.returncode, 0, result.stderr)
        config = json.loads(result.stdout)
        self.assertEqual(config["name"], "dev-services")
        self.assertEqual(set(config["services"]), {"postgres", "redis"})
        for name, port in (("postgres", 5432), ("redis", 6379)):
            service = config["services"][name]
            self.assertEqual(len(service["ports"]), 1)
            self.assertEqual(service["ports"][0]["host_ip"], "127.0.0.1")
            self.assertEqual(str(service["ports"][0]["published"]), str(port))
            self.assertEqual(service["ports"][0]["target"], port)
            self.assertNotIn("profiles", service)


if __name__ == "__main__":
    unittest.main()
