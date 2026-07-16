"""Deployment capability discovery."""

from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from evo_agent.api.jobs import job_manager
from evo_agent.config import EvolveConfig

router = APIRouter(tags=["capabilities"])


class CapabilitiesResponse(BaseModel):
    managed_doc_optimization: bool
    managed_doc_epoch_contents: bool
    managed_doc_cooperative_cancellation: bool
    managed_doc_baseline_rollback: bool
    optimization_submit_idempotency: bool
    managed_doc_operation_idempotency: bool


@router.get("/capabilities", response_model=CapabilitiesResponse)
async def get_capabilities() -> CapabilitiesResponse:
    if not job_manager.durable_available:
        raise HTTPException(
            status_code=503,
            detail={
                "code": "CAPABILITY_STORAGE_UNAVAILABLE",
                "message": "optimization control store is unavailable",
            },
        )
    config = EvolveConfig.get()
    adapter_operation_idempotency = bool(
        config.adapter_url and config.managed_doc_operation_idempotency
    )
    return CapabilitiesResponse(
        managed_doc_optimization=adapter_operation_idempotency,
        managed_doc_epoch_contents=adapter_operation_idempotency,
        managed_doc_cooperative_cancellation=adapter_operation_idempotency,
        managed_doc_baseline_rollback=adapter_operation_idempotency,
        optimization_submit_idempotency=adapter_operation_idempotency,
        managed_doc_operation_idempotency=adapter_operation_idempotency,
    )


__all__ = ["CapabilitiesResponse", "router"]
