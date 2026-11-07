#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import math
import sys
from pathlib import Path

import pandas as pd

EXPECTED_COMMUNITIES=8
EXPECTED_NODES=4508

def sha256_file(path: Path, chunk=8*1024*1024):
    h=hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda:f.read(chunk), b""):
            h.update(b)
    return h.hexdigest()

def require(cond,msg):
    if not cond:
        raise RuntimeError(msg)

def verify_manifest(path: Path):
    df=pd.read_csv(path,dtype=str,keep_default_na=False)
    required={"full_path","size_bytes","SHA256"}
    require(required.issubset(df.columns),f"MANIFEST_SCHEMA_INVALID={path}")
    bad=0
    for row in df.itertuples(index=False):
        p=Path(row.full_path)
        if not p.is_file():
            bad+=1; continue
        if int(p.stat().st_size)!=int(row.size_bytes):
            bad+=1; continue
        if sha256_file(p)!=str(row.SHA256).lower():
            bad+=1
    require(bad==0,f"MANIFEST_HASH_MISMATCHES={bad}")

def norm_bool(x):
    return str(x).strip().lower() in {"true","1","yes"}

def clean_term_df(df):
    if len(df)==0:
        return df.copy()
    needed=["query","source","name","p_value"]
    for c in needed:
        require(c in df.columns,f"ENRICHMENT_COLUMN_MISSING={c}")
    z=df.copy()
    z["p_value"]=pd.to_numeric(z["p_value"],errors="coerce")
    require(z["p_value"].notna().all(),"ENRICHMENT_PVALUE_PARSE_FAILURE")
    if "native" not in z.columns:
        z["native"]=""
    return z

def top_terms(df, qname, sources, n):
    if len(df)==0:
        return []
    z=df[(df["query"].astype(str)==qname) & (df["source"].astype(str).isin(sources))].copy()
    if len(z)==0:
        return []
    z=z.sort_values(["p_value","source","native","name"],ascending=[True,True,True,True])
    out=[]
    for row in z.head(n).itertuples(index=False):
        out.append({
            "source":str(getattr(row,"source")),
            "native":str(getattr(row,"native","")),
            "name":str(getattr(row,"name")),
            "p_value":float(getattr(row,"p_value")),
        })
    return out

def fmt_terms(terms, limit=5):
    if not terms:
        return "No significant terms under the frozen FDR criterion."
    chunks=[]
    for x in terms[:limit]:
        chunks.append(f"{x['name']} [{x['source']}, {x['native']}, p={x['p_value']:.3g}]")
    return "; ".join(chunks)

def main():
    if len(sys.argv)!=9:
        raise SystemExit(
            "usage: D10O <d10n_status> <d10n_manifest> <module_summary> <go_reac> "
            "<kegg> <reg_enrich> <hub_candidates> <node_evidence>"
        )

    status_path=Path(sys.argv[1])
    manifest_path=Path(sys.argv[2])
    module_path=Path(sys.argv[3])
    go_path=Path(sys.argv[4])
    kegg_path=Path(sys.argv[5])
    reg_path=Path(sys.argv[6])
    hubs_path=Path(sys.argv[7])
    nodes_path=Path(sys.argv[8])
    outdir=Path.cwd()

    t=status_path.read_text(encoding="utf-8-sig",errors="replace")
    for tok in [
        "D10N_STATUS=PASS",
        "COMMUNITIES_ANALYZED=8",
        "ALL_8_COMMUNITIES_REPORTED=YES",
        "COMMUNITY_ASSIGNMENTS_CHANGED=NO",
        "ENRICHMENT_EXECUTED=YES",
        "HUB_ANALYSIS_EXECUTED=YES",
        "BIOLOGICAL_EVIDENCE_CALCULATION_EXECUTED=YES",
        "BIOLOGICAL_INTERPRETATION_NARRATIVE_EXECUTED=NO",
        "READY_FOR_D10O_BIOLOGICAL_INTERPRETATION=YES",
    ]:
        require(tok in t,f"D10N_AUTHORITY_TOKEN_MISSING={tok}")

    verify_manifest(manifest_path)

    modules=pd.read_csv(module_path)
    go=clean_term_df(pd.read_csv(go_path))
    kegg=clean_term_df(pd.read_csv(kegg_path))
    reg=clean_term_df(pd.read_csv(reg_path))
    hubs=pd.read_csv(hubs_path,low_memory=False)
    nodes=pd.read_csv(nodes_path,low_memory=False)

    require(len(modules)==EXPECTED_COMMUNITIES,f"MODULE_SUMMARY_ROWS={len(modules)}")
    require(set(modules["community_id"].astype(int))==set(range(1,9)),"MODULE_IDS_NOT_1_TO_8")
    require(len(nodes)==EXPECTED_NODES,f"NODE_EVIDENCE_ROWS={len(nodes)}")
    require("community" in nodes.columns,"NODE_COMMUNITY_COLUMN_MISSING")
    require(set(nodes["community"].astype(int).unique())==set(range(1,9)),"NODE_COMMUNITY_IDS_CHANGED")
    require("primary_topological_hub" in hubs.columns,"HUB_PRIMARY_FLAG_MISSING")

    # Freeze transparent display rules before synthesis:
    # - top 10 primary GO:BP/REAC terms per community by p-value
    # - top 5 KEGG terms
    # - top 10 regulatory-target GO:BP/REAC terms
    # All original D10N result files remain authoritative and complete.
    display_rows=[]
    interpretation_rows=[]
    md=[]
    md.append("# D10O — Biological Interpretation Evidence Synthesis")
    md.append("")
    md.append("This report synthesizes the fixed D10N results for all eight communities. "
              "It does not alter community membership, re-run enrichment, create a composite "
              "hub/module score, or claim multi-seed stability.")
    md.append("")
    md.append("## Global interpretation limits")
    md.append("")
    md.append("- A-CLA optimized the unweighted all-association topology, not signed edge semantics.")
    md.append("- Functional enrichment is post-hoc characterization, not independent validation of A-CLA.")
    md.append("- RUN_COUNT=1; multi-seed or perturbation stability is not established.")
    md.append("- Topological hubs are candidate priorities, not validated biomarkers.")
    md.append("- COVID-vs-sepsis evidence is reported directly; no binary COVID-specific classifier is created.")
    md.append("")

    for cid in range(1,9):
        m=modules.loc[modules["community_id"].astype(int)==cid].iloc[0]
        q=f"C{cid}"

        go_terms=top_terms(go,q,["GO:BP","REAC"],10)
        kegg_terms=top_terms(kegg,q,["KEGG"],5)
        reg_terms=top_terms(reg,q,["GO:BP","REAC"],10)

        for family,terms in [
            ("PRIMARY_GO_BP_REAC",go_terms),
            ("SECONDARY_KEGG",kegg_terms),
            ("SECONDARY_REGULATORY_TARGET_GO_BP_REAC",reg_terms),
        ]:
            for rank,x in enumerate(terms,1):
                display_rows.append({
                    "community_id":cid,
                    "analysis_family":family,
                    "display_rank":rank,
                    **x,
                })

        g=nodes[nodes["community"].astype(int)==cid].copy()

        def count_flag(c):
            require(c in g.columns,f"NODE_EVIDENCE_FLAG_MISSING={c}")
            return int(g[c].astype(str).str.lower().isin(["true","1","yes"]).sum())

        hubg=hubs[hubs["community"].astype(int)==cid].copy()
        hub_count=len(hubg)
        cov_hub=count_flag("cov_associated_hub")
        discr_hub=count_flag("cov_vs_sepsis_discriminating_hub")
        reg_hub=count_flag("regulatory_hub_evidence")

        row={
            "community_id":cid,
            "nodes_total":int(m["nodes_total"]),
            "mrna_nodes":int(m["mrna_nodes"]),
            "mirna_nodes":int(m["mirna_nodes"]),
            "primary_GO_BP_REAC_significant_terms":int(m["primary_GO_BP_REAC_significant_terms"]),
            "secondary_KEGG_significant_terms":int(m["secondary_KEGG_significant_terms"]),
            "secondary_regulatory_GO_BP_REAC_significant_terms":int(
                m["secondary_regulatory_GO_BP_REAC_significant_terms"]
            ),
            "COV_vs_H_significant_nodes":int(m["COV_vs_H_significant_nodes"]),
            "P_vs_H_significant_nodes":int(m["P_vs_H_significant_nodes"]),
            "COV_vs_P_significant_nodes":int(m["COV_vs_P_significant_nodes"]),
            "shared_directional_response_nodes":int(m["shared_directional_response_nodes"]),
            "cov_associated_with_direct_sepsis_difference_nodes":int(
                m["cov_associated_with_direct_sepsis_difference_nodes"]
            ),
            "primary_topological_hubs":int(m["primary_topological_hubs"]),
            "regulatory_hub_evidence_nodes":int(m["regulatory_hub_evidence_nodes"]),
            "cov_associated_hubs":int(m["cov_associated_hubs"]),
            "large_effect_cov_hubs":int(m["large_effect_cov_hubs"]),
            "cov_vs_sepsis_discriminating_hubs":int(m["cov_vs_sepsis_discriminating_hubs"]),
            "top_primary_terms_text":fmt_terms(go_terms,5),
            "top_secondary_kegg_terms_text":fmt_terms(kegg_terms,3),
            "top_regulatory_target_terms_text":fmt_terms(reg_terms,5),
        }
        interpretation_rows.append(row)

        md.append(f"## Community {cid}")
        md.append("")
        md.append(
            f"**Composition.** {int(m['nodes_total'])} nodes "
            f"({int(m['mrna_nodes'])} mRNAs; {int(m['mirna_nodes'])} miRNAs)."
        )
        md.append("")
        md.append(
            f"**Primary functional characterization.** "
            f"{int(m['primary_GO_BP_REAC_significant_terms'])} significant GO:BP/Reactome terms "
            f"under the frozen FDR≤0.05 custom-background analysis. "
            f"Most statistically significant displayed terms: {fmt_terms(go_terms,5)}"
        )
        md.append("")
        md.append(
            f"**Secondary KEGG characterization.** "
            f"{int(m['secondary_KEGG_significant_terms'])} significant KEGG terms. "
            f"Displayed terms: {fmt_terms(kegg_terms,3)}"
        )
        md.append("")
        md.append(
            f"**Frozen regulatory-target characterization.** "
            f"{int(m['secondary_regulatory_GO_BP_REAC_significant_terms'])} significant "
            f"GO:BP/Reactome terms among within-community frozen regulatory targets. "
            f"Displayed terms: {fmt_terms(reg_terms,5)}"
        )
        md.append("")
        md.append(
            f"**Disease/comparator evidence.** "
            f"COV-vs-H significant nodes: {int(m['COV_vs_H_significant_nodes'])}; "
            f"P-vs-H significant nodes: {int(m['P_vs_H_significant_nodes'])}; "
            f"COV-vs-P significant nodes: {int(m['COV_vs_P_significant_nodes'])}; "
            f"shared-directional COV/P response nodes: {int(m['shared_directional_response_nodes'])}; "
            f"COV-associated nodes with direct COV-vs-P difference: "
            f"{int(m['cov_associated_with_direct_sepsis_difference_nodes'])}."
        )
        md.append("")
        md.append(
            f"**Hub evidence.** Primary topology hubs: {int(m['primary_topological_hubs'])}; "
            f"regulatory-hub evidence nodes: {int(m['regulatory_hub_evidence_nodes'])}; "
            f"COVID-associated hubs: {int(m['cov_associated_hubs'])}; "
            f"large-effect COVID hubs: {int(m['large_effect_cov_hubs'])}; "
            f"COV-vs-sepsis discriminating hubs: {int(m['cov_vs_sepsis_discriminating_hubs'])}."
        )
        md.append("")
        md.append(
            "**Interpretive boundary.** These observations support community-level biological "
            "characterization and hypothesis generation only. They do not establish causality, "
            "clinical utility, independent A-CLA validation, or strict COVID specificity."
        )
        md.append("")

    pd.DataFrame(display_rows).to_csv(
        outdir/"D10O_DISPLAYED_ENRICHMENT_TERMS.csv",index=False,float_format="%.17g"
    )
    interp=pd.DataFrame(interpretation_rows)
    interp.to_csv(outdir/"D10O_ALL_COMMUNITY_INTERPRETATION_TABLE.csv",index=False)

    # Keep all primary hubs, but sort transparently by community, node type, and internal degree only.
    hubs2=hubs.copy()
    require("internal_degree" in hubs2.columns,"HUB_INTERNAL_DEGREE_MISSING")
    hubs2["internal_degree"]=pd.to_numeric(hubs2["internal_degree"],errors="coerce")
    require(hubs2["internal_degree"].notna().all(),"HUB_DEGREE_PARSE_FAILURE")
    hubs2=hubs2.sort_values(
        ["community","node_type","internal_degree","node_id"],
        ascending=[True,True,False,True]
    )
    hubs2.to_csv(outdir/"D10O_ALL_PRIMARY_HUBS_TRANSPARENTLY_SORTED.csv",index=False)

    # Separate evidence-category hub tables; no combined ranking.
    flag_tables={
        "D10O_COVID_ASSOCIATED_HUBS.csv":"cov_associated_hub",
        "D10O_LARGE_EFFECT_COVID_HUBS.csv":"large_effect_cov_hub",
        "D10O_COV_VS_SEPSIS_DISCRIMINATING_HUBS.csv":"cov_vs_sepsis_discriminating_hub",
        "D10O_REGULATORY_HUB_EVIDENCE_NODES.csv":"regulatory_hub_evidence",
    }
    for filename,flag in flag_tables.items():
        require(flag in nodes.columns,f"NODE_FLAG_MISSING={flag}")
        z=nodes[nodes[flag].astype(str).str.lower().isin(["true","1","yes"])].copy()
        if "internal_degree" in z.columns:
            z["internal_degree"]=pd.to_numeric(z["internal_degree"],errors="coerce")
            z=z.sort_values(["community","node_type","internal_degree","node_id"],
                            ascending=[True,True,False,True])
        z.to_csv(outdir/filename,index=False)

    (outdir/"D10O_BIOLOGICAL_INTERPRETATION_REPORT.md").write_text(
        "\n".join(md),encoding="utf-8"
    )

    limitations = """# D10O Interpretation Limitations

1. The A-CLA partition is topology-derived from the all-association projection.
2. Positive/negative signs were not optimization terms and must not be presented as signed-community structure.
3. Functional enrichment is post-hoc biological characterization, not independent validation of A-CLA.
4. The network and enrichment universe are selected/conditional; whole-genome claims are not appropriate.
5. RUN_COUNT=1; no multi-seed or perturbation stability claim is authorized.
6. Hub status is topology-based and does not establish biomarker validity.
7. DE associations are observational contrasts and do not establish causality.
8. P-vs-H non-significance is not evidence of absence in sepsis.
9. No binary COVID-specific classifier was created.
10. External literature contextualization has not yet been performed in D10O.
"""
    (outdir/"D10O_INTERPRETATION_LIMITATIONS.md").write_text(limitations,encoding="utf-8")

    summary={
        "D10O_STATUS":"PASS",
        "COMMUNITIES_INTERPRETED":8,
        "ALL_8_COMMUNITIES_REPORTED":"YES",
        "PRIMARY_ENRICHMENT_DISPLAY_RULE":"TOP_10_PER_COMMUNITY_BY_P_VALUE",
        "SECONDARY_KEGG_DISPLAY_RULE":"TOP_5_PER_COMMUNITY_BY_P_VALUE",
        "REGULATORY_TARGET_DISPLAY_RULE":"TOP_10_PER_COMMUNITY_BY_P_VALUE",
        "ALL_PRIMARY_HUBS_RETAINED":"YES",
        "COMPOSITE_HUB_SCORE_CREATED":"NO",
        "MODULE_COMPOSITE_RANKING_CREATED":"NO",
        "COMMUNITY_ASSIGNMENTS_CHANGED":"NO",
        "ENRICHMENT_RERUN":"NO",
        "HUB_ANALYSIS_RERUN":"NO",
        "BIOLOGICAL_INTERPRETATION_EXECUTED":"YES_EVIDENCE_SYNTHESIS_ONLY",
        "EXTERNAL_LITERATURE_CONTEXTUALIZATION_EXECUTED":"NO",
        "CAUSAL_CLAIMS_CREATED":"NO",
        "CLINICAL_VALIDATION_CLAIMS_CREATED":"NO",
        "FUNCTIONAL_ENRICHMENT_COUNTS_AS_ACLA_VALIDATION":"NO",
        "MULTISEED_STABILITY_CLAIM_AUTHORIZED":"NO",
        "READY_FOR_D10P_EXTERNAL_LITERATURE_CONTEXTUALIZATION":"YES",
        "STOP":"YES",
    }
    (outdir/"D10O_SUMMARY.json").write_text(json.dumps(summary,indent=2),encoding="utf-8")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
