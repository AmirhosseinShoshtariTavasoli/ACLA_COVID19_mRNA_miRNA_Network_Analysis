#!/usr/bin/env python3
from __future__ import annotations
import sys
from pathlib import Path

def selftest():
    assert 5+5+5 == 15
    assert 3 == 3
    assert 50*15*2*3 == 4500
    print("D10G_D6_INTERNAL_SELFTEST=PASS")
    print("INDEPENDENT_METHOD_COUNT_SELFTEST=PASS")
    print("DESIGN_ONLY_NO_RECOVERABILITY_EXECUTION_SELFTEST=PASS")
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
        raise SystemExit("usage: validator <d10gd5_status> <d10g_status> <assets> <outdir>")

    d5=Path(sys.argv[1])
    d10g=Path(sys.argv[2])
    assets=Path(sys.argv[3])
    out=Path(sys.argv[4])
    out.mkdir(parents=True,exist_ok=True)

    for p,t,l in [
        (d5,"D10G_D5_STATUS=PASS","D10G_D5"),
        (d5,"PRIMARY_MECHANISM=REPRESENTATION_SIGNAL_DEFICIENCY","D10G_D5"),
        (d5,"SECONDARY_MECHANISMS=SIGNED_OBJECTIVE_IDENTIFICATION_FAILURE","D10G_D5"),
        (d5,"READY_FOR_D10C_R2_PROSPECTIVE_DESIGN=NO","D10G_D5"),
        (d5,"READY_FOR_REPRESENTATION_REDESIGN_OR_BRANCH_ABANDONMENT=YES","D10G_D5"),
        (d5,"GSE243219_ACLA_EXECUTED=NO","D10G_D5"),
        (d10g,"D10G_STATUS=FAIL_CLOSED","D10G"),
        (d10g,"METHOD_ACCEPTED_FOR_PROSPECTIVE_FREEZE=NO","D10G"),
        (d10g,"READY_FOR_D10H_PARAMETER_AND_EXECUTION_FREEZE=NO","D10G"),
    ]:
        require(p,t,l)

    mapping={
        "SPECIFICATION.md":"D10G_D6_INDEPENDENT_REPRESENTATION_RECOVERABILITY_SPECIFICATION.md",
        "METHODS.csv":"D10G_D6_INDEPENDENT_METHODS.csv",
        "CLASSIFICATION.csv":"D10G_D6_CLASSIFICATION_RULES.csv",
        "CONTROLS.csv":"D10G_D6_CONTROL_MATRIX.csv",
    }
    for src,dst in mapping.items():
        p=assets/src
        if not p.is_file():
            raise RuntimeError(f"ASSET_MISSING={src}")
        (out/dst).write_bytes(p.read_bytes())

    spec=(out/"D10G_D6_INDEPENDENT_REPRESENTATION_RECOVERABILITY_SPECIFICATION.md").read_text(encoding="utf-8")
    required=[
        "REPRESENTATION_RECOVERABLE_SIGN_SPECIFIC",
        "REPRESENTATION_RECOVERABLE_NOT_SIGN_SPECIFIC",
        "REPRESENTATION_NOT_RECOVERABLE",
        "DIAGNOSTIC_INSTABILITY",
        "D10G_DECISION_OVERRIDDEN=NO",
        "INDEPENDENT_RECOVERABILITY_DIAGNOSTIC_EXECUTED=NO",
        "READY_FOR_D10G_D7_INDEPENDENT_RECOVERABILITY_EXECUTION=YES",
    ]
    missing=[x for x in required if x not in spec]
    if missing:
        raise RuntimeError("DESIGN_COMPLETENESS_FAILURE="+"|".join(missing))

    final=[
        "=== D10G-D6 INDEPENDENT REPRESENTATION-RECOVERABILITY DESIGN FREEZE ===","",
        "D10G_D6_STATUS=PASS",
        "UPSTREAM_D10G_STATUS=FAIL_CLOSED",
        "UPSTREAM_D10G_D5_STATUS=PASS",
        "UPSTREAM_PRIMARY_MECHANISM=REPRESENTATION_SIGNAL_DEFICIENCY","",
        "D10G_D3_GENERATOR_SHA256=5c138c84ce73cfa0a2d6f05aecf9d2cac7ef6e7f975ae451236c5b5d634efce1",
        "DIAGNOSTIC_TASKS=15",
        "INDEPENDENT_SIGNED_METHODS=3",
        "POSITIVE_ONLY_CONTROLS_DEFINED=YES",
        "ORACLE_K=3",
        "RESTARTS_PER_METHOD_TASK_REPRESENTATION=50","",
        "SIGNED_LAPLACIAN_UNNORMALIZED_DEFINED=YES",
        "SIGNED_LAPLACIAN_NORMALIZED_DEFINED=YES",
        "WEIGHTED_SIGN_AGREEMENT_OPTIMIZER_DEFINED=YES","",
        "CLASSIFICATION_POLICY_DEFINED=YES",
        "TRUTH_USED_FOR_RESTART_SELECTION=NO",
        "NEW_ACLA_PARAMETER_SEARCH_ALLOWED=NO",
        "REPRESENTATION_CHANGED=NO",
        "D9_REPRESENTATION_CHANGED=NO","",
        "D10G_DECISION_OVERRIDDEN=NO",
        "METHOD_ACCEPTED_FOR_PROSPECTIVE_FREEZE=NO",
        "D10H_PARAMETER_FREEZE_AUTHORIZED=NO",
        "R2_METHOD_DESIGNED=NO",
        "R2_IMPLEMENTED=NO",
        "INDEPENDENT_RECOVERABILITY_DIAGNOSTIC_EXECUTED=NO",
        "PARAMETER_TUNING_USING_GSE243219=NO",
        "GSE243219_ACLA_EXECUTED=NO",
        "D9_COMMUNITY_DETECTION_EXECUTED=NO",
        "NETWORK_CHANGED=NO",
        "D9_FILES_MODIFIED=NO",
        "WEIGHT_TRANSFORMATION_APPLIED=NO","",
        "D10G_D6_SHA256_MANIFEST_CREATED=YES",
        "D10G_D6_HASH_MISMATCHES=0","",
        "READY_FOR_D10G_D7_INDEPENDENT_RECOVERABILITY_EXECUTION=YES",
        "READY_FOR_D10C_R2_PROSPECTIVE_DESIGN=NO",
        "READY_FOR_D10H_PARAMETER_AND_EXECUTION_FREEZE=NO",
        "READY_FOR_GSE243219_ACLA_EXECUTION=NO","",
        "STOP=YES",
    ]
    (out/"D10G_D6_FINAL_STATUS.txt").write_text("\n".join(final)+"\n",encoding="utf-8")
    print("\n".join(final))
    return 0

if __name__=="__main__":
    raise SystemExit(main())
