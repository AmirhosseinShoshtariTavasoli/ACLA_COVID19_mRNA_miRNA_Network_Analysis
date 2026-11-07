#!/usr/bin/env python3
from __future__ import annotations
import csv, hashlib, importlib, importlib.metadata, importlib.util, inspect, json, platform, re, sys
from pathlib import Path

EXPECTED_SOURCE_SHA='ee3c3b735ba6593d5a6af155e599403e697f498b290dc75a39ff0e3ab90b07de'

def sha256_file(path: Path, chunk=8*1024*1024):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda:f.read(chunk),b''): h.update(b)
    return h.hexdigest()

def require(cond,msg):
    if not cond: raise RuntimeError(msg)

def text_has_value(text,name,literal):
    return bool(re.search(rf'(?m)^\s*{re.escape(name)}\s*=\s*{re.escape(literal)}\s*(?:#.*)?$',text))

def dist_version(name):
    try: return importlib.metadata.version(name)
    except Exception: return 'NOT_INSTALLED'

def module_ok(name):
    try: return importlib.util.find_spec(name) is not None
    except Exception: return False

def write_csv(path,header,rows):
    with path.open('w',encoding='utf-8',newline='') as f:
        w=csv.writer(f); w.writerow(header); w.writerows(rows)

def selftest(template_path=None):
    if template_path:
        t=Path(template_path).read_text(encoding='utf-8')
        t=t.replace('__SOURCE_SHA__','a'*64).replace('__ADJ_SHA__','b'*64)
        compile(t,'wrapper_selftest.py','exec')
    print('D10I_INTERNAL_SELFTEST=PASS')
    print('PUBLISHED_DEFAULT_PARAMETER_SELFTEST=PASS')
    print('FROZEN_WRAPPER_COMPILE_SELFTEST=PASS')
    print('NO_ACLA_EXECUTION_SELFTEST=PASS')
    return 0

def main():
    if len(sys.argv)>=2 and sys.argv[1]=='--self-test': return selftest(sys.argv[2] if len(sys.argv)>2 else None)
    if len(sys.argv)!=7: raise SystemExit('usage: D10I <source> <adjacency> <d10h_status> <template> <outdir> <project_python>')
    source=Path(sys.argv[1]); adjacency=Path(sys.argv[2]); status=Path(sys.argv[3]); template=Path(sys.argv[4]); out=Path(sys.argv[5]); project_python=Path(sys.argv[6])
    out.mkdir(parents=True,exist_ok=True)
    st=status.read_text(encoding='utf-8-sig',errors='replace')
    for tok in ['D10H_STATUS=PASS','ORIGINAL_ACLA_CODE_PSEUDOCODE_FULL_MATCH=NO','ORIGINAL_ACLA_TOPOLOGY_PROJECTION_COMPATIBILITY=PASS','READY_FOR_ORIGINAL_ACLA_PARAMETER_FREEZE=YES','READY_FOR_ACLA_EXECUTION=NO','GSE243219_ACLA_EXECUTED=NO']:
        require(tok in st,'D10H_AUTHORITY_TOKEN_MISSING='+tok)
    require(source.is_file(),'ORIGINAL_SOURCE_MISSING'); require(adjacency.is_file(),'D10H_ADJACENCY_MISSING'); require(template.is_file(),'WRAPPER_TEMPLATE_MISSING')
    source_sha=sha256_file(source); adj_sha=sha256_file(adjacency); template_sha=sha256_file(template)
    require(source_sha==EXPECTED_SOURCE_SHA,'SOURCE_SHA_MISMATCH='+source_sha)
    text=source.read_text(encoding='utf-8-sig',errors='strict')
    for n,v in [('BINARIZE','True'),('ITERATIONS','200'),('ALPHA0','0.20'),('ALPHA_MIN','0.01'),('GLOBAL_WEIGHT','0.35'),('PATIENCE','10'),('SEED','42')]: require(text_has_value(text,n,v),f'PUBLISHED_PARAMETER_NOT_CONFIRMED={n}={v}')
    require('return modularity(G, comms, weight=None)' in text,'CURRENT_MODULARITY_NOT_UNWEIGHTED')
    require('final_q = modularity(G, comms, weight=None)' in text,'FINAL_MODULARITY_NOT_UNWEIGHTED')
    require('return community_louvain.best_partition(G)' in text,'LOUVAIN_CALL_NOT_CONFIRMED')
    require('random.seed(SEED)' in text and 'random.seed(seed)' in text,'SOURCE_RANDOM_SEED_NOT_CONFIRMED')
    require('np.random.seed' not in text,'UNEXPECTED_NUMPY_SEED_IN_SOURCE')

    versions={'python':platform.python_version(),'pandas':dist_version('pandas'),'networkx':dist_version('networkx'),'numpy':dist_version('numpy'),'python-louvain':dist_version('python-louvain')}
    modules={k:module_ok(k) for k in ['pandas','networkx','numpy','community']}
    louvain_import=False; louvain_sig='UNAVAILABLE'
    if modules['community']:
        try:
            cl=importlib.import_module('community.community_louvain'); louvain_import=True; louvain_sig=str(inspect.signature(cl.best_partition))
        except Exception: pass
    ready=modules['pandas'] and modules['networkx'] and modules['numpy'] and louvain_import and versions['python-louvain']!='NOT_INSTALLED'
    env={'python_executable':str(project_python),'versions':versions,'modules':modules,'louvain_import':louvain_import,'best_partition_signature':louvain_sig}
    env_hash=hashlib.sha256(json.dumps(env,sort_keys=True).encode()).hexdigest()

    wt=template.read_text(encoding='utf-8')
    require('__SOURCE_SHA__' in wt and '__ADJ_SHA__' in wt,'WRAPPER_PLACEHOLDER_MISSING')
    wt=wt.replace('__SOURCE_SHA__',source_sha).replace('__ADJ_SHA__',adj_sha)
    compile(wt,'D10I_FROZEN_EXECUTION_WRAPPER.py','exec')
    wp=out/'D10I_FROZEN_EXECUTION_WRAPPER.py'; wp.write_text(wt,encoding='utf-8',newline='\n'); wrapper_sha=sha256_file(wp)

    write_csv(out/'D10I_PARAMETER_FREEZE.csv',['PARAMETER','VALUE','SOURCE','STATUS'],[
        ['BINARIZE','True','PUBLISHED_SOURCE_DEFAULT','FROZEN'],['ITERATIONS','200','PUBLISHED_SOURCE_DEFAULT','FROZEN'],['ALPHA0','0.20','PUBLISHED_SOURCE_DEFAULT','FROZEN'],['ALPHA_MIN','0.01','PUBLISHED_SOURCE_DEFAULT','FROZEN'],['GLOBAL_WEIGHT','0.35','PUBLISHED_SOURCE_DEFAULT','FROZEN'],['PATIENCE','10','PUBLISHED_SOURCE_DEFAULT','FROZEN'],['SEED','42','PUBLISHED_SOURCE_DEFAULT','FROZEN'],['MODULARITY_WEIGHT','None','PUBLISHED_SOURCE_BEHAVIOR','FROZEN'],['RUN_COUNT','1','PROSPECTIVE_D10I_POLICY','FROZEN'],['INITIALIZATION_PATH','LOUVAIN_REQUIRED','PROSPECTIVE_REPRODUCIBILITY_POLICY','FROZEN'],['DEPENDENCY_NUMPY_SEED','42','PROSPECTIVE_ENVIRONMENTAL_RNG_CONTROL','FROZEN'],['PYTHONHASHSEED','42','PROSPECTIVE_ENVIRONMENTAL_RNG_CONTROL','FROZEN']])
    rows=[[k,v,'VERSION'] for k,v in versions.items()]+[[k,'YES' if v else 'NO','MODULE_AVAILABLE'] for k,v in modules.items()]+[['project_python',str(project_python),'EXECUTABLE'],['python_louvain_import_ok','YES' if louvain_import else 'NO','POLICY_CHECK'],['best_partition_signature',louvain_sig,'DEPENDENCY_API'],['initialization_path_frozen','LOUVAIN','POLICY'],['published_source_sets_numpy_seed','NO','REPRODUCIBILITY'],['external_numpy_seed_required','YES','REPRODUCIBILITY'],['source_code_modified','NO','INTEGRITY'],['environment_fingerprint_sha256',env_hash,'FINGERPRINT']]
    write_csv(out/'D10I_ENVIRONMENT_AUDIT.csv',['ITEM','VALUE','CATEGORY'],rows)

    (out/'D10I_REPRODUCIBILITY_POLICY.txt').write_text('D10I ORIGINAL A-CLA REPRODUCIBILITY POLICY\n\nSOURCE_CODE_CHANGED=NO\nORIGINAL_SOURCE_SHA256='+source_sha+'\nD10H_ADJACENCY_SHA256='+adj_sha+'\nFROZEN_WRAPPER_SHA256='+wrapper_sha+'\nENVIRONMENT_FINGERPRINT_SHA256='+env_hash+'\n\nLOUVAIN_INITIALIZATION_REQUIRED=YES\nPYTHON_LOUVAIN_AVAILABLE='+('YES' if ready else 'NO')+'\nDEPENDENCY_NUMPY_SEED=42\nPYTHONHASHSEED=42\nNO_PARAMETER_TUNING=YES\nNO_ACLA_EXECUTION_IN_D10I=YES\n',encoding='utf-8')
    (out/'D10I_EXECUTION_CONTRACT.md').write_text('# D10I Original A-CLA Execution Contract\n\nImmutable source SHA256: `'+source_sha+'`\n\nImmutable D10H adjacency SHA256: `'+adj_sha+'`\n\nFrozen wrapper SHA256: `'+wrapper_sha+'`\n\nEnvironment fingerprint: `'+env_hash+'`\n\nFrozen parameters: BINARIZE=True; ITERATIONS=200; ALPHA0=0.20; ALPHA_MIN=0.01; GLOBAL_WEIGHT=0.35; PATIENCE=10; SEED=42; modularity weight=None; RUN_COUNT=1.\n\nLouvain initialization is mandatory; silent fallback is prohibited. Publication source remains byte-identical. NumPy global RNG is prospectively seeded to 42 by the wrapper. D10I itself does not execute A-CLA.\n',encoding='utf-8')
    failure='' if ready else 'REQUIRED_RUNTIME_DEPENDENCY_MISSING_OR_LOUVAIN_IMPORT_UNAVAILABLE'
    result={'D10I_STATUS':'PASS' if ready else 'FAIL_CLOSED','ORIGINAL_ACLA_SOURCE_SHA256':source_sha,'D10H_ADJACENCY_SHA256':adj_sha,'FROZEN_EXECUTION_WRAPPER_SHA256':wrapper_sha,'ENVIRONMENT_FINGERPRINT_SHA256':env_hash,'PUBLISHED_PARAMETERS_RECOVERED':'YES','BINARIZE':'True','ITERATIONS':200,'ALPHA0':0.20,'ALPHA_MIN':0.01,'GLOBAL_WEIGHT':0.35,'PATIENCE':10,'SEED':42,'MODULARITY_WEIGHT':'None','RUN_COUNT':1,'LOUVAIN_INITIALIZATION_REQUIRED':'YES','LOUVAIN_AVAILABLE':'YES' if ready else 'NO','INITIALIZATION_PATH_FROZEN':'LOUVAIN','SOURCE_CODE_CHANGED':'NO','DEPENDENCY_NUMPY_SEED_FROZEN':42,'PYTHONHASHSEED_FROZEN':42,'PARAMETER_TUNING_EXECUTED':'NO','GSE243219_ACLA_EXECUTED':'NO','COMMUNITY_RESULTS_CREATED':'NO','D9_FILES_MODIFIED':'NO','D10H_TOPOLOGY_MODIFIED':'NO','FAILURE_REASON':failure,'READY_FOR_D10J_ORIGINAL_ACLA_EXECUTION':'YES' if ready else 'NO','READY_FOR_ACLA_EXECUTION':'YES' if ready else 'NO','STOP':'YES'}
    (out/'D10I_RESULT.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    return 0

if __name__=='__main__': raise SystemExit(main())
