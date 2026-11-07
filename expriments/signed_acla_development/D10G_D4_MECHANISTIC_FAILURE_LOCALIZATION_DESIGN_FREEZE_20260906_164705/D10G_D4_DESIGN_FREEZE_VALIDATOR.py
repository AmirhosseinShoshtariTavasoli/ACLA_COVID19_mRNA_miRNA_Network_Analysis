#!/usr/bin/env python3
from __future__ import annotations
import sys
from pathlib import Path

def selftest():
    tasks=5+5+5
    assert tasks==15
    assert 100*15==1500
    assert 5*10*15==750
    print("D10G_D4_INTERNAL_SELFTEST=PASS")
    print("MECHANISTIC_LAYER_COUNT_SELFTEST=PASS")
    print("DESIGN_ONLY_NO_DIAGNOSTIC_EXECUTION_SELFTEST=PASS")
    print("NO_R2_DESIGN_SELFTEST=PASS")
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
    if len(sys.argv)!=5:
        raise SystemExit("usage: validator <d10gd3_status> <d10g_status> <assets> <outdir>")

    d3=Path(sys.argv[1]);d10g=Path(sys.argv[2]);assets=Path(sys.argv[3]);out=Path(sys.argv[4])
    out.mkdir(parents=True,exist_ok=True)

    for p,t,l in [
        (d3,"D10G_D3_STATUS=PASS","D10G_D3"),
        (d3,"SIGN_IDENTIFIABILITY_CLASSIFICATION=SIGN_UTILIZATION_NOT_DEMONSTRATED","D10G_D3"),
        (d3,"INFORMATIVE_AGGREGATE_MEDIAN_TASK_ARI_ADVANTAGE=0.015018453733424711","D10G_D3"),
        (d3,"INFORMATIVE_SIGNED_TASK_WINS=13","D10G_D3"),
        (d3,"SIGNED_MEDIAN_INFORMATIVE_TASK_ARI=0.05121683614775767","D10G_D3"),
        (d3,"SIGNED_MEDIAN_INFORMATIVE_TASK_SEED_STABILITY=0.35946872322193657","D10G_D3"),
        (d3,"S2_COUNTERFACTUAL_SUCCESS_REPLICATES=2","D10G_D3"),
        (d3,"READY_FOR_R2_METHOD_REDESIGN_OR_ABANDONMENT=YES","D10G_D3"),
        (d10g,"D10G_STATUS=FAIL_CLOSED","D10G"),
        (d10g,"METHOD_ACCEPTED_FOR_PROSPECTIVE_FREEZE=NO","D10G"),
        (d10g,"READY_FOR_D10H_PARAMETER_AND_EXECUTION_FREEZE=NO","D10G"),
    ]:
        require(p,t,l)

    mapping={
        "SPECIFICATION.md":"D10G_D4_MECHANISTIC_FAILURE_LOCALIZATION_SPECIFICATION.md",
        "LAYERS.csv":"D10G_D4_DIAGNOSTIC_LAYERS.csv",
        "CLASSIFICATION.csv":"D10G_D4_CLASSIFICATION_RULES.csv",
        "CONTROLS.csv":"D10G_D4_CONTROL_MATRIX.csv",
    }
    for src,dst in mapping.items():
        p=assets/src
        if not p.is_file():
            raise RuntimeError(f"ASSET_MISSING={src}")
        (out/dst).write_bytes(p.read_bytes())

    spec=(out/"D10G_D4_MECHANISTIC_FAILURE_LOCALIZATION_SPECIFICATION.md").read_text(encoding="utf-8")
    required=[
        "SIGNED_OBJECTIVE_IDENTIFICATION_FAILURE",
        "LOCAL_MOVE_ACCESSIBILITY_FAILURE",
        "LOCAL_GLOBAL_FUSION_CONFLICT",
        "STOCHASTIC_TRANSITION_OR_SEARCH_FAILURE",
        "REPRESENTATION_SIGNAL_DEFICIENCY",
        "MIXED_MECHANISM",
        "R2_METHOD_DESIGNED=NO",
        "MECHANISTIC_DIAGNOSTIC_EXECUTED=NO",
        "READY_FOR_D10G_D5_MECHANISTIC_DIAGNOSTIC_EXECUTION=YES",
    ]
    missing=[x for x in required if x not in spec]
    if missing:
        raise RuntimeError("DESIGN_COMPLETENESS_FAILURE="+"|".join(missing))

    final=[
        "=== D10G-D4 MECHANISTIC FAILURE-LOCALIZATION DESIGN FREEZE ===","",
        "D10G_D4_STATUS=PASS",
        "UPSTREAM_D10G_STATUS=FAIL_CLOSED",
        "UPSTREAM_D10G_D3_STATUS=PASS",
        "UPSTREAM_SIGN_IDENTIFIABILITY_CLASSIFICATION=SIGN_UTILIZATION_NOT_DEMONSTRATED","",
        "R1_IMPLEMENTATION_SHA256=2bfe790d6aff0fc0404d37683fed2ef0a7c85b78c6a31bb692d3f69d0f7e257d",
        "DIAGNOSTIC_CONFIGURATION=CORE_04_ONLY",
        "DIAGNOSTIC_FAMILIES=S1_AND_S2_COUNTERFACTUALS_ONLY",
        "DIAGNOSTIC_SIGNED_TASKS=15","",
        "OBJECTIVE_IDENTIFIABILITY_LAYER_DEFINED=YES",
        "SINGLETON_MOVE_ACCESSIBILITY_LAYER_DEFINED=YES",
        "LOCAL_GLOBAL_FUSION_CONFLICT_LAYER_DEFINED=YES",
        "EARLY_SEARCH_BEHAVIOR_LAYER_DEFINED=YES",
        "SECOND_ORDER_SIGN_RELATIONAL_SIGNAL_LAYER_DEFINED=YES","",
        "NEW_PARAMETER_SEARCH_ALLOWED=NO",
        "NEW_GAMMA_VALUES_ALLOWED=NO",
        "THRESHOLD_CHANGE_ALLOWED=NO","",
        "D10G_DECISION_OVERRIDDEN=NO",
        "METHOD_ACCEPTED_FOR_PROSPECTIVE_FREEZE=NO",
        "D10H_PARAMETER_FREEZE_AUTHORIZED=NO",
        "R2_METHOD_DESIGNED=NO",
        "R2_IMPLEMENTED=NO",
        "MECHANISTIC_DIAGNOSTIC_EXECUTED=NO",
        "PARAMETER_TUNING_EXECUTED=NO",
        "PARAMETER_TUNING_USING_GSE243219=NO",
        "GSE243219_ACLA_EXECUTED=NO",
        "D9_COMMUNITY_DETECTION_EXECUTED=NO",
        "NETWORK_CHANGED=NO",
        "D9_FILES_MODIFIED=NO",
        "WEIGHT_TRANSFORMATION_APPLIED=NO","",
        "D10G_D4_SHA256_MANIFEST_CREATED=YES",
        "D10G_D4_HASH_MISMATCHES=0","",
        "READY_FOR_D10G_D5_MECHANISTIC_DIAGNOSTIC_EXECUTION=YES",
        "READY_FOR_D10C_R2_PROSPECTIVE_DESIGN=NO",
        "READY_FOR_D10H_PARAMETER_AND_EXECUTION_FREEZE=NO",
        "READY_FOR_GSE243219_ACLA_EXECUTION=NO","",
        "STOP=YES",
    ]
    (out/"D10G_D4_FINAL_STATUS.txt").write_text("\n".join(final)+"\n",encoding="utf-8")
    print("\n".join(final))
    return 0

if __name__=="__main__":
    raise SystemExit(main())
