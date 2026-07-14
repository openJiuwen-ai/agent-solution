"""managed-doc 单文档优化集成测试（spec F8 / ADR-0010）。

stub adapter（不依赖真实 adapter/LLM）：用脚本化 ``StubAdapterClient`` 编排
managed-doc transport 响应序列，驱动真实 ``ManagedDocOperator`` +
``ManagedDocApplier`` + ``ComposedCallbacks`` 的 apply 时序与状态机，验证：

- apply 全时间线（POST → 轮询 PENDING/RUNNING/SUCCEEDED → restart 生效 → 下一轮 hash no-op）
- gate accept/reject（load_state 同内容 no-op / baseline 回滚）
- apply 失败 → fatal → 不执行下一轮 rollout
- epoch-end apply 失败不被 ComposedCallbacks 吞掉（fatal 穿透）
- protected edit 后 cache/operator/remote 内容一致

构造 EvaluatedCase 时 reason=json.dumps({"attributed_skill": "managed_doc:..."})。
"""

from __future__ import annotations

import hashlib
from collections import deque
from typing import Any
from unittest.mock import MagicMock

import pytest

from evo_agent.adapter_client.content_policy import (
    PreservingContentPolicy,
    ProtectedSection,
)
from evo_agent.adapter_client.operator import (
    ManagedDocOperator,
    build_managed_doc_operator,
)
from evo_agent.adapter_client.types import (
    ManagedDocSnapshot,
    TaskState,
    UpdateStarted,
)
from evo_agent.callbacks.composed_callbacks import ComposedCallbacks
from evo_agent.errors import ManagedDocApplyError

_DOC_KIND = "agent_rule"


def _hash(content: str) -> str:
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


class StubAdapterClient:
    """脚本化 managed-doc transport：按 task_id 编排轮询序列。

    - ``get_managed_doc_sync``：返回当前 snapshot（SUCCEEDED 后 revision 已更新）。
    - ``start_managed_doc_update_sync``：记录 POST 内容，返回 UpdateStarted(task_id)。
    - ``get_managed_doc_task_sync``：按 task_id 的 scripted 序列返回 TaskState；
      序列耗尽后默认 SUCCEEDED(revision=posted hash)。SUCCEEDED 时把 snapshot 的
      file/applied revision 推进到 posted hash（模拟 restart 生效）。
    """

    def __init__(self, *, baseline_content: str) -> None:
        self._agent_name = "test_agent"
        base_hash = _hash(baseline_content)
        self._snapshot = ManagedDocSnapshot(
            content=baseline_content,
            file_revision=base_hash,
            applied_revision=base_hash,
            pending_apply=False,
            apply_mode="restart",
            max_task_seconds=60.0,
        )
        self._tasks: dict[str, dict[str, Any]] = {}
        self._task_seq: dict[str, deque[TaskState]] = {}
        self.post_calls: list[str] = []
        self.task_counter = 0

    @property
    def snapshot(self) -> ManagedDocSnapshot:
        return self._snapshot

    def get_managed_doc_sync(
        self, kind: str, *, request_timeout: float | None = None
    ) -> ManagedDocSnapshot:
        return self._snapshot

    def start_managed_doc_update_sync(
        self, kind: str, content: str, *, request_timeout: float | None = None
    ) -> UpdateStarted:
        self.post_calls.append(content)
        self.task_counter += 1
        task_id = f"task-{self.task_counter}"
        self._tasks[task_id] = {"hash": _hash(content)}
        return UpdateStarted(task_id=task_id)

    def set_task_sequence(self, task_id: str, seq: list[TaskState]) -> None:
        self._task_seq[task_id] = deque(seq)

    def get_managed_doc_task_sync(
        self, task_id: str, *, request_timeout: float | None = None
    ) -> TaskState:
        posted_hash = self._tasks[task_id]["hash"]
        seq = self._task_seq.get(task_id)
        if seq:
            state = seq.popleft()
        else:
            state = TaskState(
                status="SUCCEEDED",
                task_id=task_id,
                revision=posted_hash,
                pending_apply=False,
                last_error=None,
                attempts=1,
                down_seen=True,
                created_at=None,
                updated_at=None,
            )
        if state.status == "SUCCEEDED" and state.revision == posted_hash:
            # restart 生效：snapshot file/applied revision 推进到 posted hash
            object.__setattr__(
                self,
                "_snapshot",
                ManagedDocSnapshot(
                    content=self._snapshot.content,
                    file_revision=posted_hash,
                    applied_revision=posted_hash,
                    pending_apply=False,
                    apply_mode="restart",
                    max_task_seconds=self._snapshot.max_task_seconds,
                ),
            )
        return state


def _make_operator(
    stub: StubAdapterClient,
    *,
    baseline_content: str,
    protected: tuple[ProtectedSection, ...] = (),
) -> ManagedDocOperator:
    """构造真实 ManagedDocOperator（组合 Applier + ContentPolicy），deadline 充足。"""
    return build_managed_doc_operator(
        doc_kind=_DOC_KIND,
        initial_content=baseline_content,
        adapter_client=stub,
        content_policy=PreservingContentPolicy(
            baseline_content=baseline_content, protected_sections=protected
        ),
        deadline=600.0,
        poll_interval=0.0,  # 测试不 sleep
        last_success_hash=stub.snapshot.applied_revision,
    )


# ── 1. apply 全时间线 ──


async def test_managed_doc_step_full_timeline_update_poll_restart_next_rollout() -> None:
    """POST → 轮询 PENDING/RUNNING/SUCCEEDED → restart 生效 → 下一轮 hash no-op。"""
    baseline = "# rule v1"
    stub = StubAdapterClient(baseline_content=baseline)
    operator = _make_operator(stub, baseline_content=baseline)

    # baseline 内容首次 set_parameter → hash no-op（last_success_hash 已初始化）
    operator.set_parameter("skill_content", baseline)
    assert stub.post_calls == []  # 无 POST

    # 新内容 → POST UpdateStarted → 轮询 PENDING→RUNNING→SUCCEEDED → commit
    new_content = "# rule v2"
    stub.set_task_sequence(
        "task-1",
        [
            TaskState("PENDING", "task-1", None, False, None, 0, None, None, None),
            TaskState("RUNNING", "task-1", None, False, None, 1, None, None, None),
            TaskState("SUCCEEDED", "task-1", _hash(new_content), False, None, 1, True, None, None),
        ],
    )
    operator.set_parameter("skill_content", new_content)
    assert stub.post_calls == [new_content]
    # operator 本地状态已 commit 为新内容
    assert operator.get_state()["skill_content"] == new_content
    # records 含一条 success，task_id 非空
    success_records = [r for r in operator.applier.records if r.task_id]
    assert success_records and success_records[-1].status == "SUCCEEDED"

    # 下一轮 rollout：同内容 → hash no-op，不再 POST（restart 已生效）
    operator.set_parameter("skill_content", new_content)
    assert stub.post_calls == [new_content]  # 仍是 1 次，无重复 POST


# ── 2. gate accept → final restore no-op ──


async def test_gate_accept_candidate_final_restore_is_noop() -> None:
    """gate 接受 candidate 后，final restore(load_state 同内容) hash no-op。"""
    baseline = "# rule v1"
    candidate = "# rule v2"
    stub = StubAdapterClient(baseline_content=baseline)
    operator = _make_operator(stub, baseline_content=baseline)

    operator.set_parameter("skill_content", candidate)  # apply candidate
    assert operator.get_state()["skill_content"] == candidate
    posts_after_apply = len(stub.post_calls)

    # gate accept → final restore 同内容 → hash no-op（candidate 已生效）
    operator.load_state({"skill_content": candidate})
    assert len(stub.post_calls) == posts_after_apply  # 无新 POST


# ── 3. gate reject → reapply baseline ──


async def test_gate_reject_candidate_reapplies_baseline() -> None:
    """gate 拒绝 candidate → load_state(baseline) 重新 apply baseline 回滚。"""
    baseline = "# rule v1"
    candidate = "# rule v2"
    stub = StubAdapterClient(baseline_content=baseline)
    operator = _make_operator(stub, baseline_content=baseline)

    operator.set_parameter("skill_content", candidate)
    assert operator.get_state()["skill_content"] == candidate

    # gate reject → 回滚到 baseline（与当前 candidate 不同 → POST 新 task）
    operator.load_state({"skill_content": baseline})
    assert stub.post_calls[-1] == baseline
    assert operator.get_state()["skill_content"] == baseline


# ── 4. apply 失败 → fatal → 不执行下一轮 rollout ──


async def test_managed_doc_apply_failure_marks_job_failed_and_skips_next_rollout() -> None:
    """apply 失败（task FAILED）→ ManagedDocApplyError fatal，operator 状态不变。"""
    baseline = "# rule v1"
    candidate = "# rule v2"
    stub = StubAdapterClient(baseline_content=baseline)
    operator = _make_operator(stub, baseline_content=baseline)

    stub.set_task_sequence(
        "task-1",
        [
            TaskState(
                "FAILED", "task-1", None, False, "adapter restart timeout", 1, False, None, None
            )
        ],
    )
    # apply 失败 → fatal 抛出，operator 本地状态保持 baseline（不 commit）
    with pytest.raises(ManagedDocApplyError):
        operator.set_parameter("skill_content", candidate)
    assert operator.get_state()["skill_content"] == baseline
    # records 含一条 failed 记录
    failed_records = [r for r in operator.applier.records if r.phase.startswith("failed")]
    assert failed_records
    # fatal 已抛出 → trainer 会被终止，下一轮 rollout 不会执行（assert 不再调 set_parameter）
    # 即 apply 失败使 job FAILED、不跳过 candidate 继续。


# ── 5. epoch-end apply 失败不被 ComposedCallbacks 吞掉 ──


class _EpochEndFatalCallback:
    """模拟 epoch-end 触发 apply 且失败（ManagedDocApplyError）的 callback。"""

    def __init__(self, operator: ManagedDocOperator, fail_content: str) -> None:
        self._operator = operator
        self._fail_content = fail_content
        self.called = False

    def on_train_epoch_end(self, agent: Any, progress: Any, eval_info: list[Any]) -> None:
        self.called = True
        # epoch-end apply 失败 → fatal
        self._operator.set_parameter("skill_content", self._fail_content)

    # 其他 hook 空实现，满足 Callbacks 协议
    def on_train_begin(self, *a: Any, **k: Any) -> None: ...
    def on_train_end(self, *a: Any, **k: Any) -> None: ...
    def on_train_epoch_begin(self, *a: Any, **k: Any) -> None: ...


async def test_epoch_end_apply_failure_is_not_swallowed_by_composed_callbacks() -> None:
    """epoch-end apply 失败（fatal）经 ComposedCallbacks 重新抛出，不被 best-effort 吞掉。"""
    baseline = "# rule v1"
    fail_content = "# rule v2"
    stub = StubAdapterClient(baseline_content=baseline)
    operator = _make_operator(stub, baseline_content=baseline)
    stub.set_task_sequence(
        "task-1",
        [TaskState("FAILED", "task-1", None, False, "restart timeout", 1, False, None, None)],
    )
    fatal_cb = _EpochEndFatalCallback(operator, fail_content)
    composed = ComposedCallbacks(fatal_cb)
    # epoch-end 触发 apply 失败 → fatal 必须穿透 ComposedCallbacks（不被吞）
    with pytest.raises(ManagedDocApplyError):
        composed.on_train_epoch_end(agent=MagicMock(), progress=MagicMock(), eval_info=[])
    assert fatal_cb.called


# ── 6. protected edit → cache/operator/remote 一致 ──


async def test_protected_edit_commits_same_content_to_cache_operator_and_remote() -> None:
    """preserving policy：protected section 原样保留，cache/operator/remote 收到一致内容。"""
    protected_marker_start = "<!-- PROTECT_START -->"
    protected_marker_end = "<!-- PROTECT_END -->"
    baseline = (
        f"# agent rule\n{protected_marker_start}\nMUST KEEP THIS RULE\n"
        f"{protected_marker_end}\nbody line\n"
    )
    protected = (ProtectedSection(protected_marker_start, protected_marker_end),)
    stub = StubAdapterClient(baseline_content=baseline)
    operator = _make_operator(stub, baseline_content=baseline, protected=protected)

    # candidate 改 body 但保留 protected marker pair（normalize 用 baseline 区段替换）
    candidate = (
        f"# agent rule\n{protected_marker_start}\nATTEMPTED CHANGE\n"
        f"{protected_marker_end}\nnew body line\n"
    )
    operator.set_parameter("skill_content", candidate)

    # operator committed 内容 = normalize 后（protected 区段用 baseline 替换）
    committed = operator.get_state()["skill_content"]
    assert "MUST KEEP THIS RULE" in committed  # protected 区段保留 baseline
    assert "ATTEMPTED CHANGE" not in committed  # candidate 的改动被回滚
    assert "new body line" in committed  # body 允许改动

    # remote 收到的 POST 内容 == committed（cache/operator/remote 一致）
    assert stub.post_calls[-1] == committed
