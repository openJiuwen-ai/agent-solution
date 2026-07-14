"""Generate a natural-language user goal from a conversation trajectory."""

from __future__ import annotations

import math
from typing import Any

from openjiuwen.core.foundation.llm import (
    Model,
    ModelClientConfig,
    ModelRequestConfig,
    UserMessage,
)

from evo_agent.evaluator.domain.models import (
    GoalGenerationInput,
    GoalGenerationOutput,
)
from evo_agent.evaluator.domain.scoring import EvaluationError
from evo_agent.evaluator.json_util import JsonRepairPolicy, extract_json
from evo_agent.evaluator.prompts.goal_generation import GOAL_GENERATION_PROMPT_TEMPLATE
from evo_agent.llm.invocation import (
    LLMInvocation,
    LLMInvocationContext,
    LLMInvocationRequest,
    LLMProviderCapabilities,
    LLMRetryPolicy,
)
from evo_agent.llm.trajectory_compaction import (
    TrajectoryCompactionContext,
    TrajectoryCompactionError,
    TrajectoryCompactionPolicy,
    compact_trajectory,
)


class TrajectoryGoalGenerator:
    """Generate a Chinese natural-language user goal from trajectory messages."""

    def __init__(
        self,
        model_config: ModelRequestConfig,
        model_client_config: ModelClientConfig,
        invocation: LLMInvocation | None = None,
    ) -> None:
        self._model = Model(model_client_config, model_config)
        self._invocation = invocation or LLMInvocation(
            self._model,
            capabilities=LLMProviderCapabilities(32768, False, True, True, True, "either"),
            parallelism=4,
            safety_margin_tokens=512,
            chars_per_token=2.0,
            default_output_reserve_tokens=1200,
        )

    def generate(self, value: GoalGenerationInput) -> GoalGenerationOutput:
        """Generate the final user goal represented by the full trajectory."""
        if not value.trajectory.messages:
            raise EvaluationError("Empty trajectory: no messages to generate goal from")

        prompt_without_trajectory = GOAL_GENERATION_PROMPT_TEMPLATE.replace("{messages}", "")
        trajectory_budget = self._invocation.input_token_budget("goal_generator", 1200)
        trajectory_budget -= self._invocation.estimate_messages(
            (UserMessage(content=prompt_without_trajectory),)
        )
        try:
            compacted = compact_trajectory(
                value.trajectory,
                policy=TrajectoryCompactionPolicy(stage="goal_generator"),
                context=TrajectoryCompactionContext(),
                token_budget=trajectory_budget,
            )
        except TrajectoryCompactionError as exc:
            raise EvaluationError(
                category="prompt_budget_exceeded",
                safe_message=f"Goal trajectory cannot fit prompt budget: {exc}",
            ) from exc
        prompt = GOAL_GENERATION_PROMPT_TEMPLATE.replace("{messages}", compacted.text)

        try:
            result = self._invocation.invoke_sync(
                LLMInvocationRequest(
                    stage="goal_generator",
                    messages=(UserMessage(content=prompt),),
                    context=LLMInvocationContext(run_id="goal_generator"),
                    retry_policy=LLMRetryPolicy(2, 120.0, 300.0, 1.0, 0.0),
                    output_schema_name="goal_generation",
                    reserved_output_tokens=1200,
                )
            )
            response = result.text
        except Exception as e:
            raise EvaluationError(f"LLM goal generation failed: {e}") from e

        data = _parse_goal_response(response)
        goal = data["goal"]

        metadata: dict[str, Any] = {}
        reason = data.get("reason", "")
        if isinstance(reason, str):
            metadata["reason"] = reason

        confidence = data.get("confidence")
        if isinstance(confidence, (int, float)) and math.isfinite(confidence):
            metadata["confidence"] = max(0.0, min(1.0, float(confidence)))

        return GoalGenerationOutput(goal=goal, metadata=metadata)


def _parse_goal_response(response: str) -> dict[str, Any]:
    try:
        data = extract_json(response, policy=JsonRepairPolicy()).data
    except Exception as e:
        raise EvaluationError(f"Failed to extract JSON from LLM response: {e}") from e

    if not isinstance(data, dict):
        raise EvaluationError(f"Failed to extract JSON from LLM response: {response[:200]}")

    goal = data.get("goal")
    if not isinstance(goal, str) or not goal.strip():
        raise EvaluationError(f"LLM response missing valid 'goal' field: {goal!r}")
    data["goal"] = goal.strip()
    return data
