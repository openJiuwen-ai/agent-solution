"""Adapter sidecar 通信层 — AdapterClient + RemoteAgent + Operator 工厂。"""

from evo_agent.adapter_client.client import AdapterClient
from evo_agent.adapter_client.operator import build_skill_document_operator
from evo_agent.adapter_client.remote_agent import RemoteAgent
from evo_agent.adapter_client.types import (
    AlreadyApplied,
    ManagedDocSnapshot,
    ManagedDocUpdateResult,
    TaskState,
    UpdateStarted,
)

__all__ = [
    "AdapterClient",
    "AlreadyApplied",
    "ManagedDocSnapshot",
    "ManagedDocUpdateResult",
    "RemoteAgent",
    "TaskState",
    "UpdateStarted",
    "build_skill_document_operator",
]
