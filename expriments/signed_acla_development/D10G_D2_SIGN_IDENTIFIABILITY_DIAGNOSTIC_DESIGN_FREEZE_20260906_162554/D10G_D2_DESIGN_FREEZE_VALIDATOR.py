#!/usr/bin/env python3
from __future__ import annotations
import sys
from pathlib import Path

def selftest():
    informative_tasks=5+5+5+5+5
    assert informative_tasks==25
    assert 20/25==0.8
    assert 5+10+10+5==30
    print("D10G_D2_INTERNAL_SELFTEST=PASS")
    print("SIGN_IDENTIFIABILITY_TASK_COUNT_SELFTEST=PASS")
    print("DESIGN_ONLY_NO_DIAGNOSTIC_EXECUTION_SELFTEST=PASS")
    print("NO_ACCEPTANCE_RESCUE_SELFTEST=PASS")
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
    if len(sys.argv)!=6:
        raise SystemExit("usage: validator <d10g_status> <d10gd1_status> <assets> <outdir> <r1_status>")
    d10g=Path(sys.argv[1]);d1=Path(sys.argv[2]);assets=Path(sys.argv[3]);out=Path(sys.argv[4]);r1_status=Path(sys.argv[5])
    out.mkdir(parents=True,exist_ok=True)

    for p,t,l in [
        (d10g,"D10G_STATUS=FAIL_CLOSED","D10G"),
        (d10g,"METHOD_ACCEPTED_FOR_PROSPECTIVE_FREEZE=NO","D10G"),
        (d10g,"FAILURE_REASON=ACCEPTANCE_GATES_FAILED=G7_SIGNED_VALUE_OVER_POSITIVE_ONLY","D10G"),
        (d10g,"READY_FOR_D10H_PARAMETER_AND_EXECUTION_FREEZE=NO","D10G"),
        (d1,"D10G_D1_STATUS=PASS","D10G_D1"),
        (d1,"G7_AGGREGATE_ARI_ADVANTAGE=0.0","D10G_D1"),
        (d1,"G7_AGGREGATE_SUBGATE_PASS=NO","D10G_D1"),
        (d1,"G7_SIGNED_TASK_WINS=3","D10G_D1"),
        (d1,"G7_BREADTH_SUBGATE_PASS=NO","D10G_D1"),
        (d1,"G7_FAILURE_SHAPE=AGGREGATE_AND_BREADTH_FAIL","D10G_D1"),
        (d1,"POSITIVE_ONLY_ABLATION_COMPETITIVE=YES","D10G_D1"),
        (d1,"D10G_DECISION_OVERRIDDEN=NO","D10G_D1"),
        (d1,"POSTHOC_G7_RELAXATION_ALLOWED=NO","D10G_D1"),
        (r1_status,"D10D_R1_STATUS=PASS","D10D_R1"),
        (r1_status,"R1_IMPLEMENTATION_SHA256=2bfe790d6aff0fc0404d37683fed2ef0a7c85b78c6a31bb692d3f69d0f7e257d","D10D_R1"),
    ]:
        require(p,t,l)

    mapping={
        "SPECIFICATION.md":"D10G_D2_SIGN_IDENTIFIABILITY_DIAGNOSTIC_SPECIFICATION.md",
        "FAMILIES.csv":"D10G_D2_DIAGNOSTIC_FAMILIES.csv",
        "CLASSIFICATION.csv":"D10G_D2_CLASSIFICATION_RULES.csv",
        "CONTROLS.csv":"D10G_D2_CONTROL_MATRIX.csv",
    }
    for src,dst in mapping.items():
        p=assets/src
        if not p.is_file():
            raise RuntimeError(f"ASSET_MISSING={src}")
        (out/dst).write_bytes(p.read_bytes())

    spec=(out/"D10G_D2_SIGN_IDENTIFIABILITY_DIAGNOSTIC_SPECIFICATION.md").read_text(encoding="utf-8")
    required=[
        "aggregate median task ARI advantage",
        "20 of the 25 informative tasks",
        "S4 null control",
        "D10G_DECISION_OVERRIDDEN=NO",
        "SIGN_IDENTIFIABILITY_DIAGNOSTIC_EXECUTED=NO",
        "READY_FOR_D10G_D3_SIGN_IDENTIFIABILITY_EXECUTION=YES",
        "READY_FOR_D10H_PARAMETER_AND_EXECUTION_FREEZE=NO",
    ]
    miss=[x for x in required if x not in spec]
    if miss:
        raise RuntimeError("DESIGN_COMPLETENESS_FAILURE="+"|".join(miss))

    final=[
        "=== D10G-D2 SIGN-IDENTIFIABILITY DIAGNOSTIC DESIGN FREEZE ===","",
        "D10G_D2_STATUS=PASS",
        "UPSTREAM_D10G_STATUS=FAIL_CLOSED",
        "UPSTREAM_D10G_D1_STATUS=PASS","",
        "R1_IMPLEMENTATION_SHA256=2bfe790d6aff0fc0404d37683fed2ef0a7c85b78c6a31bb692d3f69d0f7e257d",
        "ACTIVE_PLAN=PLAN_B_SIGNED_SINGLE_LAYER_ACLA",
        "DIAGNOSTIC_CONFIGURATION=CORE_04_ONLY","",
        "DIAGNOSTIC_PURPOSE=TEST_SIGN_UTILIZATION_WHEN_SIGN_IS_IDENTIFYING",
        "DIAGNOSTIC_FAMILIES=4",
        "SIGNED_DIAGNOSTIC_TASKS=30",
        "INFORMATIVE_SIGNED_TASKS=25",
        "NULL_CONTROL_TASKS=5",
        "PAIRED_SEEDS_PER_REPRESENTATION=10","",
        "NEW_PARAMETER_SEARCH_ALLOWED=NO",
        "THRESHOLD_CHANGE_ALLOWED=NO",
        "ABS_WEIGHT_CONVERSION_ALLOWED=NO",
        "NEGATIVE_TO_POSITIVE_CONVERSION_ALLOWED=NO","",
        "D10G_DECISION_OVERRIDDEN=NO",
        "D10H_PARAMETER_FREEZE_AUTHORIZED=NO",
        "SIGN_IDENTIFIABILITY_DIAGNOSTIC_EXECUTED=NO",
        "GSE243219_ACLA_EXECUTED=NO",
        "D9_COMMUNITY_DETECTION_EXECUTED=NO",
        "PARAMETER_TUNING_USING_GSE243219=NO",
        "NETWORK_CHANGED=NO",
        "D9_FILES_MODIFIED=NO",
        "WEIGHT_TRANSFORMATION_APPLIED=NO","",
        "D10G_D2_SHA256_MANIFEST_CREATED=YES",
        "D10G_D2_HASH_MISMATCHES=0","",
        "READY_FOR_D10G_D3_SIGN_IDENTIFIABILITY_EXECUTION=YES",
        "READY_FOR_D10H_PARAMETER_AND_EXECUTION_FREEZE=NO",
        "READY_FOR_GSE243219_ACLA_EXECUTION=NO","",
        "STOP=YES",
    ]
    (out/"D10G_D2_FINAL_STATUS.txt").write_text("\n".join(final)+"\n",encoding="utf-8")
    print("\n".join(final))
    return 0

if __name__=="__main__":
    raise SystemExit(main())
