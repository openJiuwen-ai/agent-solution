"""Callback 组合顺序正确性测试。

验证 build_callbacks() 的两步顺序约束：
1. SkillDocumentCallbacks — 执行 run_epoch_end()（slow_update + meta_skill）
2. ProgressCallback — 采集进度

skill_sync_callback 已在 Wave 3 中移除（由 operator factory 的
on_parameter_updated callback 替代）。
"""

from __future__ import annotations

import inspect
from unittest.mock import MagicMock

import pytest
from openjiuwen.agent_evolving.trainer.progress import Callbacks

from evo_agent.callbacks import ComposedCallbacks, SkillDocumentCallbacks, build_callbacks


def test_build_callbacks_two_steps() -> None:
    """ComposedCallbacks 包含 SkillDocumentCallbacks + ProgressCallback。"""
    optimizer = MagicMock()
    progress_cb = MagicMock(spec=Callbacks)

    result = build_callbacks(optimizer, progress_callback=progress_cb)

    assert isinstance(result, ComposedCallbacks)
    assert len(result._callbacks) == 2
    assert isinstance(result._callbacks[0], SkillDocumentCallbacks)
    assert result._callbacks[1] is progress_cb


def test_build_callbacks_no_progress() -> None:
    """无 progress_callback 时仅包含 SkillDocumentCallbacks。"""
    optimizer = MagicMock()

    result = build_callbacks(optimizer)

    assert isinstance(result, ComposedCallbacks)
    assert len(result._callbacks) == 1
    assert isinstance(result._callbacks[0], SkillDocumentCallbacks)


def test_skill_document_callbacks_always_first() -> None:
    """SkillDocumentCallbacks 始终在第一位。"""
    optimizer = MagicMock()
    progress_cb = MagicMock(spec=Callbacks)

    result = build_callbacks(optimizer, progress_callback=progress_cb)

    assert isinstance(result._callbacks[0], SkillDocumentCallbacks)


def test_build_callbacks_no_skill_sync_param() -> None:
    """build_callbacks() 签名中不存在 skill_sync_callback 参数。

    Wave 3 中 skill 回写由 operator factory 的 on_parameter_updated
    callback (AdapterClient.update_skill) 承担，不再需要独立的
    skill_sync_callback。
    """
    sig = inspect.signature(build_callbacks)
    assert "skill_sync_callback" not in sig.parameters


# ── fatal error 穿透（spec T10）──


class _RecordingCallbacks(Callbacks):  # type: ignore[misc]
    """记录每个 hook 调用顺序 + 可注入异常的测试 double。"""

    def __init__(self, name: str = "rec", exc: Exception | None = None) -> None:
        self.name = name
        self.exc = exc
        self.calls: list[str] = []

    def _maybe_raise(self, hook: str) -> None:
        self.calls.append(hook)
        if self.exc is not None:
            raise self.exc

    def on_train_begin(self, agent: object, progress: object, eval_info: list[object]) -> None:
        self._maybe_raise("on_train_begin")

    def on_train_end(self, agent: object, progress: object, eval_info: list[object]) -> None:
        self._maybe_raise("on_train_end")

    def on_train_epoch_begin(self, agent: object, progress: object) -> None:
        self._maybe_raise("on_train_epoch_begin")

    def on_train_epoch_end(self, agent: object, progress: object, eval_info: list[object]) -> None:
        self._maybe_raise("on_train_epoch_end")


def test_fatal_error_propagates_through_composed_callbacks() -> None:
    """FatalOptimizationError 子类异常穿透 ComposedCallbacks（重新抛出，不吞）。"""
    from evo_agent.errors import FatalOptimizationError, ManagedDocApplyError

    fatal = ManagedDocApplyError(
        agent_name="a", doc_kind="k", task_id=None, phase="post", adapter_error="boom"
    )
    assert isinstance(fatal, FatalOptimizationError)
    bad = _RecordingCallbacks(name="bad", exc=fatal)
    good = _RecordingCallbacks(name="good")
    composed = ComposedCallbacks(bad, good)

    with pytest.raises(ManagedDocApplyError):
        composed.on_train_epoch_end(MagicMock(), MagicMock(), [])  # type: ignore[arg-type]
    # bad 被调用，good 因 fatal 穿透未执行
    assert bad.calls == ["on_train_epoch_end"]
    assert good.calls == []


def test_ordinary_exception_swallowed_and_subsequent_callback_runs() -> None:
    """普通 callback 异常仍被吞 + log，后续 callback 继续。"""
    bad = _RecordingCallbacks(name="bad", exc=RuntimeError("transient"))
    good = _RecordingCallbacks(name="good")
    composed = ComposedCallbacks(bad, good)

    # 不抛出（被吞）
    composed.on_train_epoch_end(MagicMock(), MagicMock(), [])  # type: ignore[arg-type]
    assert bad.calls == ["on_train_epoch_end"]
    assert good.calls == ["on_train_epoch_end"]  # 后续 callback 仍执行


def test_composed_callbacks_does_not_import_adapter_client() -> None:
    """ComposedCallbacks 只认 FatalOptimizationError marker，不反向依赖 adapter_client。"""
    import ast
    import inspect

    from evo_agent.callbacks import composed_callbacks as mod

    tree = ast.parse(inspect.getsource(mod))
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                assert "adapter_client" not in alias.name
        elif isinstance(node, ast.ImportFrom):
            mod_name = node.module or ""
            assert "adapter_client" not in mod_name
