from pathlib import Path
import hashlib, csv, sys

ROOT = Path(__file__).resolve().parents[1]
required = [
    'README.md','LICENSE','CITATION.cff','CITATION.bib','requirements.txt','environment.yml',
    'config/analysis_parameters.yaml','docs/DATA_AVAILABILITY.md','docs/CODE_AVAILABILITY.md','docs/NONCODE_COMPONENTS.md',
    'provenance/AUTHORITATIVE_D10_LINEAGE.md','provenance/SOURCE_INVENTORY.csv','provenance/SHA256_MANIFEST.csv',
    'src/07_network_construction/D9_FINAL_MULTILAYER_NETWORK_CONSTRUCTION.py',
    'src/08_acla_community_detection/A-CLA.02.01.Modularity.PUBLICATION_PROVENANCE_COPY.py',
    'src/08_acla_community_detection/D10I_FROZEN_EXECUTION_WRAPPER.py',
    'src/08_acla_community_detection/D10J_POSTEXECUTION_TECHNICAL_AUDIT.py',
    'src/09_post_community_analysis/D10K_POSTHOC_COMMUNITY_CHARACTERIZATION.py',
    'src/10_enrichment_literature/D10N_R4_CERTIFI_TLS_REMEDIATION_EXECUTION.py',
    'src/10_enrichment_literature/D10Q_PUBMED_RETRIEVAL_PROVENANCE.py',
    'src/10_enrichment_literature/D10U_R2_CORRECTED_ZERO_RETRIEVAL_SCHEMA.py',
    'provenance/d10_authoritative_runs/D10J/D10J_FINAL_STATUS.txt',
    'provenance/d10_authoritative_runs/D10V/D10V_FINAL_STATUS.txt',
]
errors=[]
for rel in required:
    if not (ROOT/rel).is_file(): errors.append(f'MISSING: {rel}')

# verify executed A-CLA identities
expected={
 'src/08_acla_community_detection/A-CLA.02.01.Modularity.PUBLICATION_PROVENANCE_COPY.py':'ee3c3b735ba6593d5a6af155e599403e697f498b290dc75a39ff0e3ab90b07de',
 'src/08_acla_community_detection/D10I_FROZEN_EXECUTION_WRAPPER.py':'794e5564de1cea41a172692cb95f70199563128c2e01beae8c4fd7ed4f58a5a5',
}
for rel,h0 in expected.items():
    p=ROOT/rel
    if p.is_file():
        h=hashlib.sha256(p.read_bytes()).hexdigest()
        if h!=h0: errors.append(f'EXECUTED_HASH_MISMATCH: {rel}: {h}')

large=[]
for p in ROOT.rglob('*'):
    if p.is_file() and p.stat().st_size > 25*1024*1024:
        large.append(str(p.relative_to(ROOT)))
if large: errors.append('FILES_OVER_25MB: '+', '.join(large))

if errors:
    print('REPOSITORY_VALIDATION=FAIL')
    for e in errors: print(e)
    sys.exit(1)
print('REPOSITORY_VALIDATION=PASS')
print('AUTHORITATIVE_D10_SOURCE=RECOVERED')
print('D10J_EXECUTED_SOURCE_HASHES=PASS')
print('NOTE=VDGEI was an interactive AI-assisted evidence-synthesis step with no local executable; no replacement code was fabricated.')
print('NOTE=No dedicated manuscript figure-generation script was executed; no reconstructed plotting code is presented as original.')
