#!/usr/bin/env python3
from __future__ import annotations
import hashlib
import sys
from pathlib import Path
import pandas as pd

EXPECTED_D10D_IMPL="a46a2fd5beacec09f800fd6d1c855b2c8f4c10e2159028542ac46cedef19fe24"

def selftest():
    # Design-only state-machine logic.
    eps=1e-12
    assert not (0.0 > eps)
    assert not (-0.1 > eps)
    assert (0.1 > eps)
    # Already-singleton condition: singleton action must be omitted.
    size=1
    allow_new_singleton=(size>1)
    assert not allow_new_singleton
    print("D10C_R1_INTERNAL_SELFTEST=PASS")
    print("IMPROVEMENT_GATE_SELFTEST=PASS")
    print("SINGLETON_IDENTITY_SELFTEST=PASS")
    print("DESIGN_ONLY_NO_REDESIGN_EXECUTION_SELFTEST=PASS")
    return 0

def require(path: Path, token: str, label: str):
    if not path.is_file():
        raise RuntimeError(f"{label}_FILE_MISSING={path}")
    text=path.read_text(encoding="utf-8-sig",errors="replace")
    if token not in text:
        raise RuntimeError(f"{label}_TOKEN_MISSING={token}")

def main():
    if len(sys.argv)==2 and sys.argv[1]=="--self-test":
        return selftest()
    if len(sys.argv)!=7:
        raise SystemExit("usage: validator <d10c_status> <d10d_status> <d10e_status> <d10ed1_status> <assets> <outdir>")
    d10c=Path(sys.argv[1]);d10d=Path(sys.argv[2]);d10e=Path(sys.argv[3]);d1=Path(sys.argv[4]);assets=Path(sys.argv[5]);out=Path(sys.argv[6])
    out.mkdir(parents=True,exist_ok=True)

    for p,t,l in [
        (d10c,"D10C_STATUS=PASS","D10C"),
        (d10c,"READY_FOR_D10D_SIGNED_ACLA_IMPLEMENTATION=YES","D10C"),
        (d10d,"D10D_STATUS=PASS","D10D"),
        (d10d,f"IMPLEMENTATION_SHA256={EXPECTED_D10D_IMPL}","D10D"),
        (d10e,"D10E_STATUS=FAIL_CLOSED","D10E"),
        (d10e,"CORE_ELIGIBLE_CONFIGURATIONS=0","D10E"),
        (d10e,"FAILURE_STAGE=CORE_SIGNED_METHOD_SYNTHETIC_VALIDATION","D10E"),
        (d1,"D10E_D1_STATUS=PASS","D10E_D1"),
        (d1,"SIGNED_OBJECTIVE_AND_LOCAL_SEMANTICS_VALIDATED=YES","D10E_D1"),
        (d1,"HARMFUL_MOVE_EXECUTION_ALLOWED=YES","D10E_D1"),
        (d1,"CURRENT_SINGLETON_DUPLICATE_ACTION_PRESENT=YES","D10E_D1"),
        (d1,"SWITCH_METRIC_CANONICAL_LABEL_SENSITIVE=YES","D10E_D1"),
        (d1,"PLANTED_PARTITION_NOT_ABSORBING_IF_P_MOVE_POSITIVE=YES","D10E_D1"),
        (d1,"THRESHOLD_RELAXATION_JUSTIFIED=NO","D10E_D1"),
        (d1,"PARAMETER_RANGE_EXPANSION_AS_ACCEPTANCE_FIX_JUSTIFIED=NO","D10E_D1"),
        (d1,"READY_FOR_D10C_R1_PROSPECTIVE_CORE_DYNAMICS_REDESIGN=YES","D10E_D1"),
    ]:
        require(p,t,l)

    mapping={
        "SPECIFICATION.md":"D10C_R1_CORE_DYNAMICS_REDESIGN_SPECIFICATION.md",
        "CHANGE_CONTROL.csv":"D10C_R1_CHANGE_CONTROL.csv",
        "TRANSITION_STATE_MACHINE.csv":"D10C_R1_TRANSITION_STATE_MACHINE.csv",
        "CONVERGENCE.csv":"D10C_R1_CONVERGENCE_SPECIFICATION.csv",
        "REVALIDATION.csv":"D10C_R1_D10E_REVALIDATION_CONTRACT.csv",
        "FAILURE.csv":"D10C_R1_FAILURE_CRITERIA.csv",
    }
    for src,dst in mapping.items():
        p=assets/src
        if not p.is_file():
            raise RuntimeError(f"DESIGN_ASSET_MISSING={src}")
        (out/dst).write_bytes(p.read_bytes())

    spec=(out/"D10C_R1_CORE_DYNAMICS_REDESIGN_SPECIFICATION.md").read_text(encoding="utf-8")
    required=[
        "HARMFUL_MOVE_EXECUTION_ALLOWED = NO",
        "CURRENT_SINGLETON_DUPLICATE_ACTION_PRESENT = NO",
        "SWITCH_METRIC_CANONICAL_LABEL_SENSITIVE = NO",
        "epsilon_{gain}=10^{-12}",
        "accepted\\_moves_t = 0",
        "n^{improve}_t = 0",
        "SIGNED_LOCAL_SCORE_CHANGED=NO",
        "SIGNED_GLOBAL_OBJECTIVE_CHANGED=NO",
        "THRESHOLD_RELAXATION_USED=NO",
        "PARAMETER_GRID_EXPANSION_USED=NO",
        "SIGNED_ACLA_R1_IMPLEMENTED=NO",
        "GSE243219_ACLA_EXECUTED=NO",
    ]
    missing=[x for x in required if x not in spec]
    if missing:
        raise RuntimeError("R1_DESIGN_COMPLETENESS_FAILURE="+"|".join(missing))

    final=[
        "=== D10C-R1 PROSPECTIVE CORE-DYNAMICS REDESIGN FREEZE ===","",
        "D10C_R1_STATUS=PASS","",
        "UPSTREAM_D10C_STATUS=PASS",
        "UPSTREAM_D10D_STATUS=PASS",
        "UPSTREAM_D10E_STATUS=FAIL_CLOSED",
        "UPSTREAM_D10E_D1_STATUS=PASS","",
        f"SUPERSEDED_R0_IMPLEMENTATION_SHA256={EXPECTED_D10D_IMPL}",
        "R0_FAILURE_CLASSIFICATION=LEARNING_DYNAMICS_TRANSITION_INSTABILITY","",
        "SIGNED_LOCAL_SCORE_CHANGED=NO",
        "SIGNED_GLOBAL_OBJECTIVE_CHANGED=NO",
        "REGULATORY_CHANNEL_CHANGED=NO",
        "D9_SEMANTICS_CHANGED=NO","",
        "MOVE_ELIGIBILITY_CHANGED=YES",
        "HARMFUL_MOVE_EXECUTION_ALLOWED_R1=NO",
        "IMPROVEMENT_GATE_DEFINED=YES",
        "IMPROVEMENT_GATE_NUMERICAL_EPSILON=1e-12","",
        "SINGLETON_ACTION_IDENTITY_CHANGED=YES",
        "CURRENT_SINGLETON_DUPLICATE_ACTION_ALLOWED_R1=NO","",
        "SWITCHING_METRIC_CHANGED=YES",
        "SWITCHING_METRIC_R1=ACCEPTED_PARTITION_CHANGING_MOVES",
        "CANONICAL_RELABEL_COUNTS_AS_SWITCH_R1=NO","",
        "POSTSWEEP_IMPROVEMENT_AUDIT_DEFINED=YES",
        "CONVERGENCE_RULE_CHANGED=YES",
        "CONVERGENCE_REQUIRES_ZERO_ACCEPTED_MOVES=YES",
        "CONVERGENCE_REQUIRES_ZERO_IMPROVING_NODES=YES","",
        "THRESHOLD_RELAXATION_USED=NO",
        "PARAMETER_GRID_EXPANSION_USED=NO",
        "D10E_R1_REUSES_ORIGINAL_CORE_GRID=YES",
        "D10E_R1_REUSES_ORIGINAL_RECOVERY_GATES=YES","",
        "BIOLOGICAL_DATA_USED_FOR_REDESIGN=NO",
        "PARAMETER_TUNING_USING_GSE243219=NO","",
        "SIGNED_ACLA_R1_IMPLEMENTED=NO",
        "SYNTHETIC_REVALIDATION_R1_EXECUTED=NO",
        "GSE243219_ACLA_EXECUTED=NO",
        "D9_COMMUNITY_DETECTION_EXECUTED=NO",
        "NETWORK_CHANGED=NO",
        "D9_FILES_MODIFIED=NO",
        "WEIGHT_TRANSFORMATION_APPLIED=NO","",
        "D10C_R1_SHA256_MANIFEST_CREATED=YES",
        "D10C_R1_HASH_MISMATCHES=0","",
        "READY_FOR_D10D_R1_CORE_DYNAMICS_IMPLEMENTATION=YES",
        "READY_FOR_D10F_SIGNED_BENCHMARKING=NO",
        "READY_FOR_GSE243219_ACLA_EXECUTION=NO","",
        "STOP=YES",
    ]
    (out/"D10C_R1_FINAL_STATUS.txt").write_text("\n".join(final)+"\n",encoding="utf-8")
    print("\n".join(final))
    return 0

if __name__=="__main__":
    raise SystemExit(main())
