#!/usr/bin/env python3
from __future__ import annotations
import hashlib, json, sys
from pathlib import Path
import pandas as pd

EXP={
 'communities':8,'targets':187,'queries':374,'pairs':2531,'pmids':2137,
 'direct':2137,'irrelevant':389,'metadata':5,'concordant':75,'discordant':28,
 'mixed':62,'noncomp':1051,'nondir':921,'zero':194
}

def sha(p):
    h=hashlib.sha256()
    with Path(p).open('rb') as f:
        for b in iter(lambda:f.read(8*1024*1024),b''): h.update(b)
    return h.hexdigest()

def req(c,m):
    if not c: raise RuntimeError(m)

def verify_manifest(path):
    d=pd.read_csv(path,dtype=str,keep_default_na=False)
    req({'full_path','size_bytes','SHA256'}.issubset(d.columns),f'MANIFEST_SCHEMA_INVALID={path}')
    bad=0
    for r in d.itertuples(index=False):
        p=Path(r.full_path)
        if not p.is_file() or int(p.stat().st_size)!=int(r.size_bytes) or sha(p)!=str(r.SHA256).lower(): bad+=1
    req(bad==0,f'MANIFEST_HASH_MISMATCHES={bad}')

def synth_state(r):
    if int(r.retrieved_pairs)==0: return 'ZERO_RETRIEVAL_UNDER_FROZEN_SEARCH'
    if int(r.direct_pairs)==0: return 'NO_DIRECT_RELEVANT_ABSTRACT_EVIDENCE'
    con,dis,mix=int(r.concordant_pairs),int(r.discordant_pairs),int(r.mixed_pairs)
    if con>0 and (dis>0 or mix>0): return 'CONCORDANT_WITH_CONTRADICTORY_OR_MIXED_EVIDENCE'
    if con>0: return 'CONCORDANT_CONTEXTUAL_SUPPORT_PRESENT'
    if dis>0 or mix>0: return 'CONTRADICTORY_OR_MIXED_EVIDENCE_WITHOUT_CONCORDANT_PAIR'
    return 'DIRECT_RELEVANCE_WITHOUT_DIRECTIONAL_CONCORDANCE_CLASS'

def main():
    if len(sys.argv)!=10:
        raise SystemExit('usage: D10T <d10s_status> <d10s_manifest> <pairs> <target_summary> <d10o_status> <d10o_manifest> <targets> <query_plan> <outdir>')
    sstatus,sman,pairs_p,ts_p,ostatus,oman,targets_p,plan_p,out=map(Path,sys.argv[1:])
    out.mkdir(parents=True,exist_ok=True)

    st=sstatus.read_text(encoding='utf-8-sig',errors='replace')
    for tok in [
        'D10S_STATUS=PASS','COMMUNITIES_SCREENED=8','SCREENING_QUERY_PMID_PAIRS=2531',
        'UNIQUE_PMIDS_IN_SCREENING_UNIVERSE=2137','DIRECT_TARGET_DISEASE_PAIRS=2137',
        'IRRELEVANT_OR_AMBIGUOUS_PAIRS=389','NO_ABSTRACT_METADATA_ONLY_PAIRS=5',
        'CONCORDANT_CONTEXTUAL_SUPPORT_PAIRS=75','DISCORDANT_OR_CONTRADICTORY_PAIRS=28',
        'MIXED_WITHIN_RECORD_PAIRS=62','RELEVANT_NOT_DIRECTIONALLY_COMPARABLE_PAIRS=1051',
        'NO_DIRECTIONAL_CLAIM_PAIRS=921','ZERO_HIT_QUERIES=194',
        'ALL_QUERY_PMID_PAIRS_SCREENED=YES','CONTRADICTORY_EVIDENCE_RETAINED=YES',
        'BIOLOGICAL_NARRATIVE_EXECUTED=NO','READY_FOR_D10T_LITERATURE_SYNTHESIS_DESIGN=YES']:
        req(tok in st,f'D10S_AUTHORITY_TOKEN_MISSING={tok}')
    verify_manifest(sman)

    ot=ostatus.read_text(encoding='utf-8-sig',errors='replace')
    for tok in ['D10O_STATUS=PASS','COMMUNITIES_INTERPRETED=8','ALL_8_COMMUNITIES_REPORTED=YES','COMMUNITY_ASSIGNMENTS_CHANGED=NO']:
        req(tok in ot,f'D10O_AUTHORITY_TOKEN_MISSING={tok}')
    verify_manifest(oman)

    pairs=pd.read_csv(pairs_p,dtype=str,keep_default_na=False)
    ts=pd.read_csv(ts_p,dtype=str,keep_default_na=False)
    targets=pd.read_csv(targets_p,dtype=str,keep_default_na=False)
    plan=pd.read_csv(plan_p,dtype=str,keep_default_na=False)

    req(len(pairs)==EXP['pairs'],'PAIR_COUNT_CHANGED')
    req(pairs.screening_pair_id.nunique()==EXP['pairs'],'PAIR_IDS_CHANGED')
    req(pairs.pmid.nunique()==EXP['pmids'],'PMID_COUNT_CHANGED')
    req(len(targets)==EXP['targets'] and targets.target_id.nunique()==EXP['targets'],'TARGET_COUNT_CHANGED')
    req(len(plan)==EXP['queries'] and plan.query_id.nunique()==EXP['queries'],'QUERY_COUNT_CHANGED')
    req(set(pd.to_numeric(targets.community_id).astype(int))==set(range(1,9)),'TARGET_COMMUNITY_COVERAGE_CHANGED')

    checks={
      'DIRECT_TARGET_DISEASE':EXP['direct'],'IRRELEVANT_OR_AMBIGUOUS':EXP['irrelevant'],
      'NO_ABSTRACT_METADATA_ONLY':EXP['metadata']}
    for cls,n in checks.items(): req(int((pairs.relevance_class==cls).sum())==n,f'RELEVANCE_COUNT_CHANGED={cls}')
    for cls,n in {
      'CONCORDANT_CONTEXTUAL_SUPPORT':EXP['concordant'],'DISCORDANT_OR_CONTRADICTORY':EXP['discordant'],
      'MIXED_WITHIN_RECORD':EXP['mixed'],'RELEVANT_NOT_DIRECTIONALLY_COMPARABLE':EXP['noncomp'],
      'NO_DIRECTIONAL_CLAIM':EXP['nondir']}.items():
        req(int((pairs.evidence_class==cls).sum())==n,f'EVIDENCE_COUNT_CHANGED={cls}')
    req(EXP['direct']+EXP['irrelevant']+EXP['metadata']==EXP['pairs'],'RELEVANCE_ARITHMETIC_INVALID')
    req(EXP['concordant']+EXP['discordant']+EXP['mixed']+EXP['noncomp']+EXP['nondir']==EXP['direct'],'EVIDENCE_ARITHMETIC_INVALID')

    # Master 374 units from pre-literature D10P query plan.
    units=plan[['query_id','target_id','community_id','target_category','target_label','disease_context']].copy()
    units['community_id']=pd.to_numeric(units.community_id).astype(int)
    req(units[['target_id','disease_context']].drop_duplicates().shape[0]==EXP['queries'],'TARGET_DISEASE_UNIT_COUNT_CHANGED')

    nums=['retrieved_pairs','direct_pairs','irrelevant_or_ambiguous_pairs','metadata_only_pairs','concordant_pairs','discordant_pairs','mixed_pairs','nondirectional_pairs','noncomparable_pairs']
    for c in nums:
        if c in ts.columns: ts[c]=pd.to_numeric(ts[c],errors='coerce').fillna(0).astype(int)
    units=units.merge(ts,on=['target_id','community_id','target_category','target_label','disease_context'],how='left',validate='one_to_one')
    for c in nums:
        if c not in units.columns: units[c]=0
        units[c]=pd.to_numeric(units[c],errors='coerce').fillna(0).astype(int)
    units['frozen_literature_synthesis_state']=[synth_state(r) for r in units.itertuples(index=False)]
    req(int((units.retrieved_pairs==0).sum())==EXP['zero'],'ZERO_RETRIEVAL_UNIT_COUNT_CHANGED')

    # Narrative inclusion depends only on D10P category rank, never literature outcome.
    t=targets[['target_id','community_id','target_category','category_rank','target_label','target_native_id','source_family','selection_rule']].copy()
    t['community_id']=pd.to_numeric(t.community_id).astype(int); t['category_rank']=pd.to_numeric(t.category_rank).astype(int)
    limits={'PRIMARY_FUNCTIONAL_TERM':3,'SECONDARY_KEGG_TERM':2,'REGULATORY_TARGET_FUNCTIONAL_TERM':3,'COVID_ASSOCIATED_HUB':3,'COV_VS_SEPSIS_DISCRIMINATING_HUB':3,'REGULATORY_HUB_EVIDENCE_NODE':3}
    req(set(t.target_category).issubset(limits),'UNEXPECTED_TARGET_CATEGORY')
    t['narrative_display_limit']=t.target_category.map(limits)
    t['narrative_target_included']=t.category_rank<=t.narrative_display_limit
    t['narrative_target_rule']='PRE_LITERATURE_D10P_CATEGORY_RANK_ONLY'
    t.to_csv(out/'D10T_NARRATIVE_TARGET_REGISTRY.csv',index=False)
    units=units.merge(t[['target_id','category_rank','narrative_target_included']],on='target_id',how='left',validate='many_to_one')
    req(units.narrative_target_included.notna().all(),'NARRATIVE_TARGET_MAPPING_FAILED')
    units.to_csv(out/'D10T_TARGET_DISEASE_SYNTHESIS_PLAN.csv',index=False)

    cp=[]
    for cid in range(1,9):
        g=t[t.community_id==cid]
        cp.append({'community_id':cid,'all_literature_targets':len(g),'narrative_targets':int(g.narrative_target_included.sum()),'both_disease_contexts_required':'YES'})
    pd.DataFrame(cp).to_csv(out/'D10T_COMMUNITY_NARRATIVE_PLAN.csv',index=False)

    citation=[
      ['CONCORDANT_SYSTEMATIC_REVIEW','CONCORDANT + SYSTEMATIC_REVIEW_OR_META_ANALYSIS',1,'publication_year DESC, PMID ASC'],
      ['CONCORDANT_ORIGINAL_HUMAN','CONCORDANT + ORIGINAL_HUMAN_CLINICAL_OR_COHORT/ORIGINAL_HUMAN_OMICS_OR_COMPUTATIONAL',2,'publication_year DESC, study_type ASC, PMID ASC'],
      ['DISCORDANT_OR_CONTRADICTORY','DISCORDANT_OR_CONTRADICTORY',2,'publication_year DESC, PMID ASC'],
      ['MIXED_WITHIN_RECORD','MIXED_WITHIN_RECORD',1,'publication_year DESC, PMID ASC'],
      ['DIRECT_NONDIRECTIONAL_CONTEXT','NO_DIRECTIONAL_CLAIM or RELEVANT_NOT_DIRECTIONALLY_COMPARABLE',1,'study-type priority, publication_year DESC, PMID ASC']]
    pd.DataFrame(citation,columns=['CITATION_SLOT','ELIGIBILITY','MAX_PER_TARGET_DISEASE','DETERMINISTIC_ORDER']).to_csv(out/'D10T_CITATION_SELECTION_RULES.csv',index=False)

    wording=[
      ['ZERO_RETRIEVAL_UNDER_FROZEN_SEARCH','No PubMed records retrieved under frozen query; do not infer biological absence.'],
      ['NO_DIRECT_RELEVANT_ABSTRACT_EVIDENCE','Retrieved records lacked direct target/disease abstract evidence under frozen screening.'],
      ['CONCORDANT_CONTEXTUAL_SUPPORT_PRESENT','Use consistent with / compatible with / contextually supported by; never validated or confirmed.'],
      ['CONCORDANT_WITH_CONTRADICTORY_OR_MIXED_EVIDENCE','Present supportive and contradictory/mixed evidence together; no vote-counting.'],
      ['CONTRADICTORY_OR_MIXED_EVIDENCE_WITHOUT_CONCORDANT_PAIR','Foreground inconsistency/mixed evidence without declaring project result disproved.'],
      ['DIRECT_RELEVANCE_WITHOUT_DIRECTIONAL_CONCORDANCE_CLASS','Describe relevance only; no directional agreement claim.']]
    pd.DataFrame(wording,columns=['SYNTHESIS_STATE','FROZEN_NARRATIVE_RULE']).to_csv(out/'D10T_NARRATIVE_WORDING_RULES.csv',index=False)

    policies=[
      ['SYNTHESIS_UNIT','TARGET_DISEASE','All 374 units retained'],['NARRATIVE_COMMUNITIES','ALL_8','Every community narrated'],
      ['NARRATIVE_TARGET_SELECTION','PRE_LITERATURE_D10P_CATEGORY_RANK_ONLY','Literature outcome cannot select targets'],
      ['FULL_MATRIX','ALL_187_TARGETS_X_2_DISEASE_CONTEXTS','Narrative truncation never deletes matrix rows'],
      ['EVIDENCE_SCORE','PROHIBITED','No weighted score'],['VOTE_COUNTING','PROHIBITED','Counts are descriptive, not evidence weights'],
      ['PMID_DUPLICATION','ONE_PUBLICATION_NOT_MULTIPLE_INDEPENDENT_STUDIES','Pair mappings retained without study double-counting'],
      ['CONTRADICTION_VISIBILITY','MANDATORY','Discordant/mixed evidence surfaced for displayed targets'],
      ['ZERO_HIT_USE','NOT_NEGATIVE_BIOLOGY','Search outcome only'],['NO_ABSTRACT_USE','METADATA_ONLY','No mechanistic inference'],
      ['AUTOMATED_SCREENING_DISCLOSURE','MANDATORY','D10S deterministic title/abstract classifier must be disclosed'],
      ['SYSTEMATIC_REVIEW_CLAIM','PROHIBITED','Not PRISMA/systematic review'],['FULL_TEXT_REVIEW_CLAIM','PROHIBITED','No full text used'],
      ['LITERATURE_VALIDATION_LANGUAGE','PROHIBITED','No validation of A-CLA/modules/hubs'],
      ['MODULE_HUB_ENRICHMENT_EFFECT','NONE','Literature cannot change upstream results'],
      ['CAUSAL_OR_CLINICAL_CLAIM','PROHIBITED','Hypothesis-generating context only'],
      ['NEW_SEARCH_OR_ANALYSIS','PROHIBITED_IN_D10U','D10U synthesis only']]
    pd.DataFrame(policies,columns=['POLICY_ITEM','FROZEN_VALUE','RATIONALE']).to_csv(out/'D10T_LITERATURE_SYNTHESIS_POLICY.csv',index=False)

    limits_md='''# D10T Mandatory Limitations\n\n1. D10S used deterministic automated PubMed title/abstract/metadata screening.\n2. No full-text review or formal risk-of-bias assessment was performed.\n3. This is not a PRISMA systematic review or meta-analysis.\n4. One PMID can map to multiple target/query pairs but remains one publication.\n5. Citation counts are not evidence-strength scores.\n6. Zero-hit queries do not establish biological absence.\n7. Five no-abstract records are metadata-only.\n8. Contradictory/mixed evidence must be reported when present.\n9. Concordance means contextual compatibility, not A-CLA validation.\n10. Literature cannot change communities, hubs, enrichment, or upstream statistics.\n'''
    (out/'D10T_MANDATORY_LIMITATIONS.md').write_text(limits_md,encoding='utf-8')

    contract={
      'D10T_STATUS':'PASS','COMMUNITIES_FROZEN':8,'LITERATURE_TARGETS':187,'TARGET_DISEASE_SYNTHESIS_UNITS':374,
      'SCREENED_QUERY_PMID_PAIRS':2531,'UNIQUE_PMIDS':2137,'ALL_TARGET_DISEASE_UNITS_RETAINED':'YES',
      'ALL_8_COMMUNITIES_REQUIRE_NARRATIVE':'YES','NARRATIVE_TARGET_SELECTION':'PRE_LITERATURE_D10P_CATEGORY_RANK_ONLY',
      'LITERATURE_OUTCOME_CAN_CHANGE_NARRATIVE_TARGET_SELECTION':'NO','EVIDENCE_SCORE_CREATED':'NO','VOTE_COUNTING_AUTHORIZED':'NO',
      'CONTRADICTORY_EVIDENCE_DISPLAY_MANDATORY':'YES','ZERO_RETRIEVAL_COUNTS_AS_NEGATIVE_BIOLOGICAL_EVIDENCE':'NO',
      'NO_ABSTRACT_MECHANISTIC_INFERENCE_AUTHORIZED':'NO','AUTOMATED_SCREENING_DISCLOSURE_REQUIRED':'YES',
      'SYSTEMATIC_REVIEW_CLAIM_AUTHORIZED':'NO','FULL_TEXT_REVIEW_CLAIM_AUTHORIZED':'NO',
      'LITERATURE_CAN_CHANGE_COMMUNITIES':'NO','LITERATURE_CAN_CHANGE_HUB_STATUS':'NO','LITERATURE_CAN_CHANGE_ENRICHMENT':'NO',
      'LITERATURE_CONCORDANCE_COUNTS_AS_ACLA_VALIDATION':'NO','CAUSAL_OR_CLINICAL_CLAIMS_AUTHORIZED':'NO',
      'NEW_LITERATURE_SEARCH_AUTHORIZED':'NO','NEW_BIOLOGICAL_ANALYSIS_AUTHORIZED':'NO','LITERATURE_SYNTHESIS_EXECUTED':'NO',
      'READY_FOR_D10U_LITERATURE_SYNTHESIS_EXECUTION':'YES','STOP':'YES'}
    (out/'D10T_EXECUTION_CONTRACT.json').write_text(json.dumps(contract,indent=2),encoding='utf-8')

    spec='''# D10T Literature Synthesis Design Freeze\n\nAll 374 target-disease units remain in the evidence matrix. Narrative target selection is fixed by pre-literature D10P category rank only. If a selected target has weak or contradictory literature, it remains selected and is reported transparently. No evidence score, vote-counting, new search, full-text review, or upstream biological change is permitted in D10U.\n'''
    (out/'D10T_DESIGN_SPECIFICATION.md').write_text(spec,encoding='utf-8')
    return 0

if __name__=='__main__': raise SystemExit(main())
