"""Deployment contract tests for managed-doc Docker restart wiring."""

import os
from pathlib import Path

import yaml

_ROOT = Path(__file__).resolve().parents[2]
_DEPLOYMENT = _ROOT / "deployment"


def test_documented_shell_entrypoints_are_executable() -> None:
    for name in ("start.sh", "stop.sh", "export-bundle.sh", "import-bundle.sh"):
        path = _DEPLOYMENT / name
        assert path.is_file(), path
        assert os.access(path, os.X_OK), f"{path} must be executable"


def test_docker_restart_is_disabled_by_default() -> None:
    env_template = (_DEPLOYMENT / "config" / ".env.example").read_text(encoding="utf-8")
    start_script = (_DEPLOYMENT / "start.sh").read_text(encoding="utf-8")

    assert "ADAPTER_ENABLE_DOCKER_RESTART=false" in env_template
    assert 'case "${ADAPTER_ENABLE_DOCKER_RESTART,,}"' in start_script
    assert 'DOCKER_RESTART_OPTS=(-v "$HOST_DOCKER_SOCKET:/var/run/docker.sock")' in start_script


def test_base_compose_shares_docs_without_docker_socket() -> None:
    compose = yaml.safe_load((_DEPLOYMENT / "docker-compose.yml").read_text(encoding="utf-8"))
    volumes = compose["services"]["adapter"]["volumes"]

    assert any(str(volume).endswith(":/data/agents") for volume in volumes)
    assert not any("docker.sock" in str(volume) for volume in volumes)


def test_managed_doc_compose_override_grants_docker_socket() -> None:
    override = yaml.safe_load(
        (_DEPLOYMENT / "docker-compose.managed-doc.yml").read_text(encoding="utf-8")
    )
    volumes = override["services"]["adapter"]["volumes"]

    assert volumes == ["${HOST_DOCKER_SOCKET:-/var/run/docker.sock}:/var/run/docker.sock"]


def test_runtime_image_contains_docker_cli_package() -> None:
    dockerfile = (_DEPLOYMENT / "Dockerfile").read_text(encoding="utf-8")

    assert "curl ca-certificates patch docker-cli" in dockerfile
    assert " docker.io" not in dockerfile


def test_tracked_guide_contains_managed_doc_bootstrap() -> None:
    guide = (_ROOT / "docs" / "deployment-guide.md").read_text(encoding="utf-8")

    assert "AgentRule managed-doc 配置与首启 bootstrap" in guide
    assert '"action": "update"' in guide
    assert 'state["down_seen"] is True' in guide
    assert "exec -T adapter python" in guide
    assert "managed-doc-deploy.md" not in guide

    config_template = (_DEPLOYMENT / "config" / "agent_adapter_config.yaml").read_text(
        encoding="utf-8"
    )
    assert "managed-doc-deploy.md" not in config_template
    assert "docs/deployment-guide.md §3.5.6" in config_template


def test_offline_readme_uses_current_host_variable_names() -> None:
    exporter = (_DEPLOYMENT / "export-bundle.sh").read_text(encoding="utf-8")

    assert "HOST_LOG_ROOT / HOST_SKILLS_ROOT / HOST_AGENTS_ROOT" in exporter
    assert "HOST_LOG_DIR" not in exporter
    assert "HOST_SKILLS_DIR" not in exporter
