"""Fatal optimization error marker + structured managed-doc apply error.

``FatalOptimizationError`` is the generic marker for errors that must abort the
optimization job: ``ComposedCallbacks`` re-raises any subclass of it instead of
swallowing it (ordinary progress/observability callback exceptions are still
best-effort logged and skipped).

``ManagedDocApplyError`` is the structured exception raised when a managed-doc
apply fails (task FAILED / unknown terminal state / revision mismatch / deadline
exceeded / TASK_NOT_FOUND not confirmable). It carries the context needed for
log/artifact records without leaking the full document content.
"""

from __future__ import annotations


class FatalOptimizationError(Exception):
    """Generic marker for errors that must abort the optimization job.

    ``ComposedCallbacks`` re-raises any subclass of this marker; ordinary
    callback exceptions are still best-effort logged and skipped. Subclass to
    mark a new category of fatal failures (e.g. ``ManagedDocApplyError``).
    """


class ManagedDocApplyError(FatalOptimizationError):
    """Apply of a managed-doc failed — abort the job, keep baseline artifact.

    Raised by ``ManagedDocApplier`` / ``ManagedDocOperator`` on:
    task ``FAILED``, unknown terminal state, revision mismatch, total deadline
    exceeded, or ``TASK_NOT_FOUND`` not confirmable via revision. No graceful
    skip / auto-retry / auto-compensation: surface the structured context so an
    operator can inspect adapter state and recover from the baseline manually.

    Fields:
        agent_name: the optimization job's agent name.
        doc_kind: the exact managed-doc kind being applied.
        task_id: adapter task id if one was obtained (``None`` when the POST
            itself failed before a task was created).
        phase: apply phase that failed (``"post"`` / ``"poll"`` / ``"snapshot"``).
        adapter_error: the underlying adapter/transport error message.
    """

    def __init__(
        self,
        *,
        agent_name: str,
        doc_kind: str,
        task_id: str | None,
        phase: str,
        adapter_error: str,
    ) -> None:
        self.agent_name = agent_name
        self.doc_kind = doc_kind
        self.task_id = task_id
        self.phase = phase
        self.adapter_error = adapter_error
        super().__init__(
            f"managed-doc apply failed: agent={agent_name} doc_kind={doc_kind} "
            f"task_id={task_id} phase={phase} adapter_error={adapter_error}"
        )
