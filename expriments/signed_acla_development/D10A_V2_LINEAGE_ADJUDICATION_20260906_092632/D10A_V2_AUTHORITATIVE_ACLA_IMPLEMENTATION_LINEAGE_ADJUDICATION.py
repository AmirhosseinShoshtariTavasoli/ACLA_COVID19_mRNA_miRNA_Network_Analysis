#!/usr/bin/env python3
from __future__ import annotations

import ast, hashlib, json, math, re, sys, zipfile
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd

EXPECTED_NODES=4508
EXPECTED_EDGES=11531
EXPECTED_COMPONENTS=2
EXPECTED_LARGEST=4502
EXPECTED_SECOND=6
EXPECTED_WEIGHT_MIN=-0.7753835531973502
EXPECTED_WEIGHT_MAX=0.7428957195865319

TEXT_EXTS={'.py','.ps1','.txt','.md','.csv','.json','.yaml','.yml','.toml','.ini','.r','.R','.jl','.m','.xml','.log'}
CODE_EXTS={'.py','.ps1','.r','.R','.jl','.m'}
TIMESTAMP_RE=re.compile(r'(?<!\d)(20\d{6})(?:[_-]?(\d{6}))?(?!\d)')

STAGE_PATTERNS=[
 ('R1_IMPLEMENTATION',re.compile(r'(?i)\br1\b.*\bimplementation\b|\bimplementation\b.*\br1\b')),
 ('R1_PROTOTYPE',re.compile(r'(?i)\br1\b.*\bprototype\b|\bprototype\b.*\br1\b')),
 ('B1C',re.compile(r'(?i)\bb1c(?:[-_ ]?0|[-_ ]?1)?\b')),
 ('B1B',re.compile(r'(?i)\bb1b(?:[-_ ]?1)?\b')),
 ('B1A',re.compile(r'(?i)\bb1a(?:[-_ ]?1)?\b')),
 ('B1',re.compile(r'(?i)\bb1\b')),
 ('V6',re.compile(r'(?i)(?:candidate|acla)[^\\/\n]*\bv6\b|\bv6\b[^\\/\n]*(?:candidate|acla)')),
 ('V5',re.compile(r'(?i)(?:candidate|acla)[^\\/\n]*\bv5\b|\bv5\b[^\\/\n]*(?:candidate|acla)')),
 ('V4',re.compile(r'(?i)(?:candidate|acla)[^\\/\n]*\bv4\b|\bv4\b[^\\/\n]*(?:candidate|acla)')),
 ('V3',re.compile(r'(?i)(?:candidate|acla)[^\\/\n]*\bv3\b|\bv3\b[^\\/\n]*(?:candidate|acla)')),
 ('V2',re.compile(r'(?i)(?:candidate|acla)[^\\/\n]*\bv2\b|\bv2\b[^\\/\n]*(?:candidate|acla)')),
 ('V1',re.compile(r'(?i)(?:candidate|acla)[^\\/\n]*\bv1\b|\bv1\b[^\\/\n]*(?:candidate|acla)')),
 ('EARLY_REFINED_ACLA',re.compile(r'(?i)a[-_ ]?cla[_ -]?refin|refined[^\\/\n]*a[-_ ]?cla')),
 ('ORIGINAL_PUBLISHED_ACLA',re.compile(r'(?i)original[^\\/\n]*a[-_ ]?cla|published[^\\/\n]*a[-_ ]?cla|a[-_ ]?cla\.py$')),
]

ROLE_PATTERNS=[
 ('FINAL_DECISION',re.compile(r'(?i)final[_ -]?decision|decision')),
 ('MANIFEST',re.compile(r'(?i)manifest|sha256')),
 ('VALIDATION',re.compile(r'(?i)validation|validate|audit')),
 ('BENCHMARK',re.compile(r'(?i)benchmark|scalability')),
 ('PREFLIGHT',re.compile(r'(?i)preflight')),
 ('RUNNER',re.compile(r'(?i)run_|runner|execute|execution')),
 ('CONFIG',re.compile(r'(?i)config|parameter|specification|design')),
 ('REPORT',re.compile(r'(?i)report|summary|handoff|status')),
 ('CORE_SOURCE',re.compile(r'(?i)\.py$|\.r$|\.jl$|\.m$')),
]

REJECT_PATTERNS=[
 re.compile(r'(?i)\brejected\b'),
 re.compile(r'(?i)\bnot[_ ]accepted\b'),
 re.compile(r'(?i)\bready_for_full_network_run\s*=\s*no\b'),
 re.compile(r'(?i)\bready_for_r1_implementation\s*=\s*no\b'),
]
SUPERSEDE_PATTERNS=[re.compile(r'(?i)\bsuperseded\b'),re.compile(r'(?i)\bobsolete\b')]
DIAG_PATTERNS=[re.compile(r'(?i)\bdiagnostic[_ ]only\b'),re.compile(r'(?i)\bmethod[_ -]?diagnostic\b'),re.compile(r'(?i)\bdiagnostic branch\b')]
DESIGN_PATTERNS=[re.compile(r'(?i)\bprospective[_ ]design\b'),re.compile(r'(?i)\bdesign[_ ]preflight\b'),re.compile(r'(?i)\bfrozen_r1_design_hash\b'),re.compile(r'(?i)\bready_for_r1_prototype_implementation\b')]
ACCEPT_PATTERNS=[
 re.compile(r'(?i)\br1[_ -]?implementation[_ -]?accepted\s*=\s*yes\b'),
 re.compile(r'(?i)\br1[_ -]?prototype[_ -]?accepted\s*=\s*yes\b'),
 re.compile(r'(?i)\br1[_ -]?implementation[_ -]?validated\s*=\s*yes\b'),
 re.compile(r'(?i)\br1[_ -]?validation[_ -]?(?:status|decision)?\s*=\s*pass\b'),
 re.compile(r'(?i)\bready_for_full_network_run\s*=\s*yes\b'),
 re.compile(r'(?i)\bready_for_first_.*acla_execution\s*=\s*yes\b'),
]
PUBLISHED_PATTERNS=[
 re.compile(r'(?i)\bpublished\b.*\ba[-_ ]?cla\b'),
 re.compile(r'(?i)\ba[-_ ]?cla\b.*\bpublished\b'),
 re.compile(r'(?i)A-CLA: A Novel Adaptive Cellular Learning Automata Approach'),
]

EVIDENCE_PATTERNS=[
 ('B1A_PREFLIGHT_PASS',re.compile(r'(?i)\bb1a\b.*\bpreflight\b.*\bpass\b|\bb1a[_ -]?preflight[_ -]?(?:status|decision)?\s*=\s*pass\b')),
 ('B1A1_ANALYSIS_PASS',re.compile(r'(?i)\bb1a[-_ ]?1\b.*\bpass\b|\bb1a[_ -]?(?:analysis|final).*?=\s*pass\b')),
 ('B1B_MORE_DIAGNOSTIC_DATA_REQUIRED',re.compile(r'(?i)\bb1b\b.*MORE_DIAGNOSTIC_DATA_REQUIRED|MORE_DIAGNOSTIC_DATA_REQUIRED.*\bb1b\b')),
 ('B1C0_PASS',re.compile(r'(?i)\bb1c[-_ ]?0\b.*\bpass\b|\bb1c0\b.*\bpass\b')),
 ('FROZEN_R1_DESIGN_HASH',re.compile(r'(?i)FROZEN_R1_DESIGN_HASH\s*=\s*([0-9a-f]{8,64})')),
 ('READY_FOR_R1_PROTOTYPE_IMPLEMENTATION',re.compile(r'(?i)READY_FOR_R1_PROTOTYPE_IMPLEMENTATION')),
 ('R1_IMPLEMENTATION_CREATED',re.compile(r'(?i)R1.*IMPLEMENTATION.*(?:CREATED|IMPLEMENTED).*YES')),
 ('R1_IMPLEMENTATION_EXECUTED',re.compile(r'(?i)R1.*IMPLEMENTATION.*EXECUTED.*YES')),
 ('R1_IMPLEMENTATION_BENCHMARKED',re.compile(r'(?i)R1.*IMPLEMENTATION.*BENCHMARK.*(?:PASS|YES)')),
 ('R1_IMPLEMENTATION_ACCEPTED',re.compile(r'(?i)R1.*IMPLEMENTATION.*ACCEPTED.*YES|READY_FOR_FULL_NETWORK_RUN\s*=\s*YES')),
 ('R1_PROTOTYPE_IMPLEMENTED',re.compile(r'(?i)R1.*PROTOTYPE.*(?:IMPLEMENTED|CREATED).*YES')),
 ('R1_PROTOTYPE_EXECUTED',re.compile(r'(?i)R1.*PROTOTYPE.*EXECUTED.*YES')),
 ('R1_PROTOTYPE_BENCHMARKED',re.compile(r'(?i)R1.*PROTOTYPE.*BENCHMARK.*(?:PASS|YES)')),
 ('R1_PROTOTYPE_ACCEPTED',re.compile(r'(?i)R1.*PROTOTYPE.*ACCEPTED.*YES')),
]


def sha256_file(path:Path,chunk=8*1024*1024):
 h=hashlib.sha256()
 with path.open('rb') as f:
  while True:
   b=f.read(chunk)
   if not b: break
   h.update(b)
 return h.hexdigest()


def recertify_manifest(path:Path,label:str):
 if not path.is_file(): raise RuntimeError(f'{label}_MANIFEST_MISSING={path}')
 df=pd.read_csv(path,dtype=str,keep_default_na=False)
 need={'full_path','size_bytes','SHA256'}
 miss=need-set(df.columns)
 if miss: raise RuntimeError(f'{label}_MANIFEST_COLUMNS_MISSING={sorted(miss)}')
 bad=[]
 for _,r in df.iterrows():
  p=Path(str(r['full_path']))
  if not p.is_file(): bad.append(f'MISSING:{p}'); continue
  if p.stat().st_size!=int(r['size_bytes']): bad.append(f'SIZE:{p}'); continue
  if sha256_file(p)!=str(r['SHA256']).lower(): bad.append(f'SHA256:{p}')
 if bad: raise RuntimeError(f'{label}_HASH_MISMATCHES={len(bad)}|'+'||'.join(bad[:20]))
 return df


class UF:
 def __init__(self,nodes): self.p={n:n for n in nodes}; self.sz={n:1 for n in nodes}
 def find(self,x):
  if self.p[x]!=x: self.p[x]=self.find(self.p[x])
  return self.p[x]
 def union(self,a,b):
  ra,rb=self.find(a),self.find(b)
  if ra==rb:return
  if self.sz[ra]<self.sz[rb]:ra,rb=rb,ra
  self.p[rb]=ra;self.sz[ra]+=self.sz[rb]


def comp_stats(nodes,edges):
 uf=UF(nodes);deg=Counter({n:0 for n in nodes})
 for s,t in zip(edges['source'],edges['target']):
  if s==t:continue
  uf.union(s,t);deg[s]+=1;deg[t]+=1
 c=defaultdict(int)
 for n in nodes:c[uf.find(n)]+=1
 sizes=sorted(c.values(),reverse=True)
 return {'components':len(sizes),'largest':sizes[0] if sizes else 0,'second':sizes[1] if len(sizes)>1 else 0,'isolated':sum(1 for n in nodes if deg[n]==0)}


def safe_text(path:Path,max_bytes=12_000_000):
 try:
  if path.stat().st_size>max_bytes:return ''
  if path.suffix.lower()=='.docx':
   with zipfile.ZipFile(path,'r') as z: xml=z.read('word/document.xml').decode('utf-8',errors='replace')
   xml=re.sub(r'<w:tab[^>]*/>','\t',xml);xml=re.sub(r'</w:p>','\n',xml)
   return re.sub(r'<[^>]+>','',xml)
  if path.suffix in TEXT_EXTS:return path.read_text(encoding='utf-8',errors='replace')
 except Exception:return ''
 return ''


def archive_evidence(path:Path,max_members=5000,max_text_bytes=2_000_000):
 out=[]
 if path.suffix.lower()!='.zip':return out
 try:
  with zipfile.ZipFile(path,'r') as z:
   for info in z.infolist()[:max_members]:
    name=info.filename;low=name.lower()
    if not any(k in low for k in ['acla','a-cla','b1a','b1b','b1c','r1','candidate_v','final_decision','benchmark','validation']):continue
    text='';ext=Path(name).suffix
    if info.file_size<=max_text_bytes and ext in TEXT_EXTS:
     try:text=z.read(info).decode('utf-8',errors='replace')
     except Exception:pass
    out.append({'member_name':name,'text':text})
 except Exception:pass
 return out


def infer_role(s):
 for role,rgx in ROLE_PATTERNS:
  if rgx.search(s):return role
 return 'OTHER'


def family_from(path_text,content):
 combined=f'{path_text}\n{content[:100000]}'
 for fam,rgx in STAGE_PATTERNS:
  if rgx.search(combined):return fam
 stem=Path(path_text).stem
 cleaned=re.sub(r'[^A-Za-z0-9]+','_',stem).strip('_').upper()
 return f'OBSERVED_{cleaned[:80]}' if 'ACLA' in cleaned else 'UNCLASSIFIED_ACLA_ARTIFACT'


def timestamp_from(text,mtime):
 m=TIMESTAMP_RE.search(text)
 if m:
  try:return datetime.strptime(m.group(1)+(m.group(2) or '000000'),'%Y%m%d%H%M%S').isoformat()
  except Exception:pass
 return datetime.fromtimestamp(mtime).isoformat()


def scan_roots(roots):
 inv=[];evidence=[]
 for root_name,root in roots.items():
  if not root.exists():raise RuntimeError(f'AUTHORIZED_SEARCH_ROOT_MISSING={root}')
  for p in root.rglob('*'):
   if not p.is_file():continue
   rel=str(p.relative_to(root)).replace('\\','/');path_text=f'{root_name}/{rel}'
   text=safe_text(p);members=archive_evidence(p)
   blob='\n'.join(x['member_name']+'\n'+x.get('text','') for x in members[:1000])
   probe=f'{path_text}\n{text[:250000]}\n{blob[:500000]}';low=probe.lower()
   if not any(k in low for k in ['acla','a-cla','adaptive cellular learning automata','b1a','b1b','b1c','r1_prototype','r1 implementation','candidate_v1','candidate_v2','candidate_v3','candidate_v4','candidate_v5','candidate_v6']):continue
   fam=family_from(path_text,probe);ts=timestamp_from(path_text,p.stat().st_mtime)
   inv.append({'path':str(p),'relative_path':path_text,'filename':p.name,'SHA256':sha256_file(p),'size_bytes':p.stat().st_size,'file_type':p.suffix.lower() or '<none>','likely_role':infer_role(path_text),'implementation_family':fam,'version_or_branch_label':fam,'timestamp':ts,'is_code':'YES' if p.suffix in CODE_EXTS else 'NO','archive_relevant_members':len(members),'dependency_or_entrypoint_relationship':'','status_evidence':''})
   if text:evidence.append({'source_path':str(p),'relative_path':path_text,'family':fam,'text':text,'timestamp':ts})
   for m in members:evidence.append({'source_path':f"{p}::{m['member_name']}",'relative_path':f"{path_text}::{m['member_name']}",'family':family_from(f"{path_text}::{m['member_name']}",m.get('text','')),'text':m.get('text',''),'timestamp':ts})
 return inv,evidence


def parse_python(path:Path):
 text=safe_text(path,20_000_000)
 try:tree=ast.parse(text,filename=str(path))
 except Exception as e:return {'compile':'FAIL','error':str(e),'text':text}
 imports=[];funcs=[];constants={};main=False;argparse=False
 for n in ast.walk(tree):
  if isinstance(n,ast.Import):imports.extend(a.name for a in n.names)
  elif isinstance(n,ast.ImportFrom) and n.module:imports.append(n.module)
  elif isinstance(n,ast.FunctionDef):funcs.append(n.name)
  elif isinstance(n,ast.If):
   try:c=ast.unparse(n.test)
   except Exception:c=''
   if '__name__' in c and '__main__' in c:main=True
  elif isinstance(n,ast.Call):
   try:f=ast.unparse(n.func)
   except Exception:f=''
   if 'ArgumentParser' in f or 'add_argument' in f:argparse=True
  elif isinstance(n,(ast.Assign,ast.AnnAssign)):
   targets=n.targets if isinstance(n,ast.Assign) else [n.target];value=n.value
   for t in targets:
    if isinstance(t,ast.Name) and t.id.isupper():
     try:constants[t.id]=ast.literal_eval(value)
     except Exception:
      try:constants[t.id]=ast.unparse(value)
      except Exception:constants[t.id]='<NONLITERAL>'
 return {'compile':'PASS','error':'','text':text,'imports':sorted(set(imports)),'functions':sorted(set(funcs)),'constants':constants,'main_guard':main,'argparse':argparse}


def semantics(path:Path):
 m=parse_python(path)
 if m['compile']!='PASS':return {'compile':'FAIL','objective_function':'UNRESOLVED','community_update_rule':'UNRESOLVED','action_selection_rule':'UNRESOLVED','learning_automata_semantics':'UNRESOLVED','probability_update_semantics':'UNRESOLVED','initialization':'UNRESOLVED','stopping_rule':'UNRESOLVED','convergence_logic':'UNRESOLVED','randomness':'UNRESOLVED','weight_handling':'UNRESOLVED','signed_weight_policy':'UNRESOLVED','negative_edges_preserved':'UNRESOLVED','negative_edges_dropped':'UNRESOLVED','negative_edges_absolutized':'UNRESOLVED','negative_edges_transformed':'UNRESOLVED','regulatory_layer_handling':'UNRESOLVED','multilayer_handling':'UNRESOLVED','input_schema':'UNRESOLVED','constants':{}}
 text=m['text'];low=text.lower()
 objective='MODULARITY_OR_MODULARITY_DERIVED' if 'modularity' in low else ('CUSTOM_OBJECTIVE_PRESENT_REVIEW_REQUIRED' if 'objective' in low else 'UNRESOLVED')
 action='ARGMAX_BASED' if ('np.argmax' in low or 'argmax' in low) else ('STOCHASTIC_SELECTION' if ('np.random.choice' in low or 'random.choice' in low) else 'UNRESOLVED')
 prob='LEARNING_AUTOMATA_PROBABILITY_UPDATE' if ('update_prob' in low or 'probability update' in low) else 'UNRESOLVED'
 init='EACH_NODE_OWN_COMMUNITY' if ('each node is its own community' in low or re.search(r'hard_labels\s*=\s*\{n:\s*i',text)) else ('CUSTOM_INITIALIZATION_REVIEW_REQUIRED' if ('initial' in low and 'community' in low) else 'UNRESOLVED')
 stop='TOLERANCE_PLUS_PATIENCE' if ('patience' in low and ('tol' in low or 'threshold' in low)) else ('MAX_ITERATIONS_OR_CUSTOM' if ('max_iters' in low or 'max_iterations' in low) else 'UNRESOLVED')
 if 'read_edgelist' in low or ('read_csv' in low and 'source' in low and 'target' in low):schema='EDGE_LIST'
 elif 'from_pandas_adjacency' in low or 'adjacency matrix' in low:schema='ADJACENCY_MATRIX'
 elif 'np.load' in low and 'row' in low and 'col' in low:schema='SPARSE_COO_OR_NPZ'
 elif 'networkx' in low and re.search(r'def\s+\w+\s*\(\s*g\b',low):schema='NETWORKX_GRAPH_OBJECT'
 else:schema='UNRESOLVED'
 dropped=bool(re.search(r'\.where\(\s*[^)]*>\s*0\s*,\s*0',low) or re.search(r'weight\s*>\s*0',low))
 absolutized=bool(re.search(r'\babs\s*\([^)]*weight',low) or re.search(r'np\.abs\s*\(',low))
 clipped=bool(re.search(r'np\.clip\s*\(',low) or re.search(r'\.clip\s*\(',low))
 if dropped:sp='DROPS_OR_ZEROS_NONPOSITIVE_WEIGHTS';pres='NO';drop='YES';ab='NO';tr='YES'
 elif absolutized:sp='ABSOLUTE_VALUE_TRANSFORMATION_DETECTED';pres='NO';drop='NO';ab='YES';tr='YES'
 elif clipped:sp='CLIPPING_TRANSFORMATION_DETECTED';pres='NO_OR_UNCERTAIN';drop='UNRESOLVED';ab='NO';tr='YES'
 elif 'weight' in low:sp='NO_SIGN_REMOVAL_TRANSFORMATION_DETECTED_STATIC_ONLY';pres='YES_AT_INGESTION_STATIC_ONLY';drop='NO_TRANSFORM_DETECTED';ab='NO';tr='NO_TRANSFORM_DETECTED'
 else:sp='WEIGHT_USAGE_UNRESOLVED';pres=drop=ab=tr='UNRESOLVED'
 randomness='|'.join(x for x in ['random.seed','np.random.seed','default_rng','np.random','random.choice'] if x in low) or 'NO_EXPLICIT_RANDOM_CALL_DETECTED'
 return {'compile':'PASS','objective_function':objective,'community_update_rule':'COMMUNITY_LABEL_OR_ACTION_UPDATE' if ('community' in low and ('move' in low or 'label' in low or 'action' in low)) else 'UNRESOLVED','action_selection_rule':action,'learning_automata_semantics':'PROBABILITY_VECTOR_OVER_ACTIONS' if ('probab' in low and 'action' in low) else 'UNRESOLVED','probability_update_semantics':prob,'initialization':init,'stopping_rule':stop,'convergence_logic':'EXPLICIT_CONVERGENCE_LOGIC_PRESENT' if 'converg' in low else 'UNRESOLVED','randomness':randomness,'weight_handling':'WEIGHT_REFERENCED' if 'weight' in low else 'UNRESOLVED','signed_weight_policy':sp,'negative_edges_preserved':pres,'negative_edges_dropped':drop,'negative_edges_absolutized':ab,'negative_edges_transformed':tr,'regulatory_layer_handling':'NATIVE_REGULATORY_CHANNEL_REFERENCED' if any(k in low for k in ['regulatory','tarbase','targetscan','mirdb']) else 'NO_NATIVE_REGULATORY_CHANNEL_DETECTED','multilayer_handling':'NATIVE_MULTILAYER_LOGIC_DETECTED' if ('multilayer' in low or 'layer_mass' in low or 'within_layer' in low) else 'NO_NATIVE_MULTILAYER_LOGIC_DETECTED','input_schema':schema,'constants':m['constants'],'meta':m}


def local_deps(entry:Path,root:Path):
 req={entry.resolve()};q=[entry.resolve()]
 while q:
  p=q.pop();m=parse_python(p)
  if m['compile']!='PASS':continue
  for mod in m.get('imports',[]):
   top=mod.split('.')[0];cand=[p.parent/f'{top}.py',root/f'{top}.py',p.parent/top/'__init__.py',root/top/'__init__.py']
   found=next((c for c in cand if c.is_file()),None)
   if found:
    found=found.resolve()
    if found not in req:req.add(found);q.append(found)
 return sorted(req,key=lambda p:str(p).lower())


def ev_records(evidence):
 rec=[]
 for e in evidence:
  text=e['text']
  if not text:continue
  lines=text.splitlines()
  for typ,rgx in EVIDENCE_PATTERNS:
   for m in rgx.finditer(text):
    ln=text.count('\n',0,m.start())+1
    rec.append({'evidence_type':typ,'source_path':e['source_path'],'relative_path':e['relative_path'],'family':e['family'],'timestamp':e['timestamp'],'line_number':ln,'matched_text':m.group(0)[:2000],'line_text':lines[ln-1][:2000] if lines and ln<=len(lines) else '','SHA256':sha256_file(Path(e['source_path'])) if '::' not in e['source_path'] and Path(e['source_path']).is_file() else ''})
 return rec


def has(patterns,text):return any(p.search(text) for p in patterns)


def family_status(fam,rows,evidence):
 texts='\n'.join(e['text'][:500000] for e in evidence if e['family']==fam and e['text']);paths='\n'.join(r['relative_path'] for r in rows);blob=paths+'\n'+texts
 if has(REJECT_PATTERNS,blob):return 'REJECTED'
 if has(SUPERSEDE_PATTERNS,blob):return 'SUPERSEDED'
 if has(DIAG_PATTERNS,blob):return 'DIAGNOSTIC_ONLY'
 if fam=='ORIGINAL_PUBLISHED_ACLA' and has(PUBLISHED_PATTERNS,blob):return 'PUBLISHED_BASELINE'
 if has(ACCEPT_PATTERNS,blob):return 'VALIDATED'
 if fam.startswith('R1_') and any(r['is_code']=='YES' for r in rows):return 'IMPLEMENTED_UNVALIDATED'
 if has(DESIGN_PATTERNS,blob) or fam=='B1C':return 'PROSPECTIVE_DESIGN_ONLY'
 return 'UNKNOWN'


def entry_candidates(rows):
 out=[]
 for r in rows:
  p=Path(r['path'])
  if p.suffix.lower()!='.py':continue
  m=parse_python(p)
  if m['compile']!='PASS':continue
  score=(5 if m.get('main_guard') else 0)+(3 if m.get('argparse') else 0)+(2 if r['likely_role'] in {'RUNNER','CORE_SOURCE'} else 0)
  low=m['text'].lower();name=p.name.lower()
  if 'benchmark' in name:score-=4
  if 'audit' in name or 'validation' in name:score-=3
  if 'run_acla' in low or 'def run_acla' in low:score+=4
  if 'community' in low and 'probab' in low:score+=2
  out.append((score,p))
 return sorted(out,key=lambda x:(-x[0],str(x[1]).lower()))


def fp(sem):
 keys=['objective_function','community_update_rule','action_selection_rule','learning_automata_semantics','probability_update_semantics','initialization','stopping_rule','convergence_logic','weight_handling','signed_weight_policy','regulatory_layer_handling','multilayer_handling','input_schema']
 return '|'.join(str(sem.get(k,'')) for k in keys)


def main():
 if len(sys.argv)!=7:raise SystemExit('usage: script project reusable d9 d10a_v1_or_NONE outdir result_json')
 project,reusable,d9=Path(sys.argv[1]),Path(sys.argv[2]),Path(sys.argv[3]);v1arg=sys.argv[4];v1=None if v1arg=='NONE' else Path(v1arg);out=Path(sys.argv[5]);result_path=Path(sys.argv[6]);out.mkdir(parents=True,exist_ok=True)
 # D9
 recertify_manifest(d9/'D9_SHA256_MANIFEST.csv','D9');txt=(d9/'D9_FINAL_STATUS.txt').read_text(encoding='utf-8-sig',errors='replace')
 for tok in ['D9_STATUS=PASS','TOTAL_NODES=4508','TOTAL_STRUCTURAL_EDGES=11531','CONNECTED_COMPONENTS=2','LARGEST_COMPONENT_NODES=4502','ACLA_EXECUTED=NO','D9_HASH_MISMATCHES=0','READY_FOR_ACLA_PREEXECUTION_FREEZE=YES','STOP=YES']:
  if tok not in txt:raise RuntimeError(f'D9_STATUS_TOKEN_MISSING={tok}')
 nodes=pd.read_csv(d9/'D9_MASTER_NODES.csv',dtype={'node_id':str,'node_type':str});edges=pd.read_csv(d9/'D9_MASTER_EDGES.csv',dtype={'source':str,'target':str},float_precision='round_trip')
 if len(nodes)!=EXPECTED_NODES or nodes['node_id'].duplicated().any():raise RuntimeError('D9_NODE_IDENTITY_GATE_FAILED')
 if len(edges)!=EXPECTED_EDGES or edges.duplicated(['source','target']).any():raise RuntimeError('D9_EDGE_IDENTITY_GATE_FAILED')
 w=pd.to_numeric(edges['association_score'],errors='coerce').to_numpy(float)
 if (~np.isfinite(w)).sum():raise RuntimeError('D9_INVALID_WEIGHT_GATE_FAILED')
 wmin,wmax=float(w.min()),float(w.max())
 if not math.isclose(wmin,EXPECTED_WEIGHT_MIN,rel_tol=0,abs_tol=1e-15) or not math.isclose(wmax,EXPECTED_WEIGHT_MAX,rel_tol=0,abs_tol=1e-15):raise RuntimeError(f'D9_WEIGHT_RANGE_CHANGED={wmin},{wmax}')
 c=comp_stats(nodes['node_id'].tolist(),edges)
 if c!={'components':2,'largest':4502,'second':6,'isolated':0}:raise RuntimeError(f'D9_COMPONENT_GATE_FAILED={c}')
 # V1 provenance
 v1rec='NO'
 if v1 and (v1/'D10A_SHA256_MANIFEST.csv').is_file() and (v1/'D10A_FINAL_STATUS.txt').is_file():
  recertify_manifest(v1/'D10A_SHA256_MANIFEST.csv','D10A_V1');vtxt=(v1/'D10A_FINAL_STATUS.txt').read_text(encoding='utf-8-sig',errors='replace')
  for tok in ['D10A_STATUS=FAIL_CLOSED','GSE243219_ACLA_EXECUTED=NO','D10A_HASH_MISMATCHES=0','READY_FOR_FIRST_GSE243219_ACLA_EXECUTION=NO']:
   if tok not in vtxt:raise RuntimeError(f'D10A_V1_TOKEN_MISSING={tok}')
  v1rec='YES'
 roots={'01_ACLA_CODE':reusable/'01_ACLA_CODE','07_METHODS_AND_DOCUMENTATION':reusable/'07_METHODS_AND_DOCUMENTATION','08_REPRODUCIBILITY_UTILITIES':reusable/'08_REPRODUCIBILITY_UTILITIES','09_OLD_METHOD_HISTORY':reusable/'09_OLD_METHOD_HISTORY'}
 inv,evidence=scan_roots(roots)
 if not inv:raise RuntimeError('DISCOVERED_ACLA_FILES=0')
 invdf=pd.DataFrame(inv);invdf.to_csv(out/'D10A_V2_ACLA_FILE_INVENTORY.csv',index=False)
 vals=pd.DataFrame(ev_records(evidence));vals.to_csv(out/'D10A_V2_VALIDATION_EVIDENCE.csv',index=False)
 def found(x):return not vals.empty and 'evidence_type' in vals.columns and vals['evidence_type'].eq(x).any()
 b1a=found('B1A_PREFLIGHT_PASS') or found('B1A1_ANALYSIS_PASS');b1b=found('B1B_MORE_DIAGNOSTIC_DATA_REQUIRED');b1c=found('B1C0_PASS') or found('FROZEN_R1_DESIGN_HASH') or found('READY_FOR_R1_PROTOTYPE_IMPLEMENTATION');r1design=b1c and found('READY_FOR_R1_PROTOTYPE_IMPLEMENTATION')
 famrows={f:g.to_dict('records') for f,g in invdf.groupby('implementation_family')};statuses={};entries={};sems={};fout=[]
 for fam,rows in sorted(famrows.items()):
  st=family_status(fam,rows,evidence);statuses[fam]=st;cands=entry_candidates(rows);entry=cands[0][1] if cands else None;entries[fam]=entry;sem=semantics(entry) if entry else None;sems[fam]=sem;req=local_deps(entry,roots['01_ACLA_CODE']) if entry and entry.suffix.lower()=='.py' else []
  timestamps=sorted(r['timestamp'] for r in rows if r['timestamp']);evfiles=sorted(set(e['source_path'] for e in evidence if e['family']==fam and e['text']))
  fout.append({'FAMILY_ID':fam,'ENTRYPOINT_CANDIDATES':'|'.join(str(x[1]) for x in cands[:10]),'FAMILY_ENTRYPOINT':str(entry) if entry else '','ENTRYPOINT_SHA256':sha256_file(entry) if entry else '','CORE_SOURCE_FILES':'|'.join(r['path'] for r in rows if r['is_code']=='YES'),'REQUIRED_FILES':'|'.join(str(p) for p in req),'DEPENDENCIES':'|'.join(str(p) for p in req if entry and p.resolve()!=entry.resolve()),'FIRST_TIMESTAMP':timestamps[0] if timestamps else '','LAST_TIMESTAMP':timestamps[-1] if timestamps else '','SCIENTIFIC_STATUS':st,'STATUS_EVIDENCE_FILES':'|'.join(evfiles[:100]),'ARTIFACT_COUNT':len(rows)})
 fdf=pd.DataFrame(fout);fdf.to_csv(out/'D10A_V2_IMPLEMENTATION_FAMILIES.csv',index=False)
 # timeline
 order=['ORIGINAL_PUBLISHED_ACLA','EARLY_REFINED_ACLA','V1','V2','V3','V4','V5','V6','B1','B1A','B1B','B1C','R1_PROTOTYPE','R1_IMPLEMENTATION'];timeline=[]
 for stage in order:
  if stage in famrows:
   r=fdf[fdf.FAMILY_ID.eq(stage)].iloc[0];timeline.append({'lineage_stage':stage,'first_timestamp':r.FIRST_TIMESTAMP,'last_timestamp':r.LAST_TIMESTAMP,'scientific_status':r.SCIENTIFIC_STATUS,'evidence':r.STATUS_EVIDENCE_FILES})
 for label,val,note in [('B1A_EVIDENCE',b1a,'B1A read-only preflight / analysis evidence'),('B1B_EVIDENCE',b1b,'B1B MORE_DIAGNOSTIC_DATA_REQUIRED evidence'),('B1C0_R1_DESIGN_EVIDENCE',b1c,'B1C-0 prospective R1 design evidence')]:timeline.append({'lineage_stage':label,'first_timestamp':'','last_timestamp':'','scientific_status':'VALIDATED_EVIDENCE' if val else 'NOT_FOUND','evidence':note})
 pd.DataFrame(timeline).to_csv(out/'D10A_V2_LINEAGE_TIMELINE.csv',index=False)
 # semantics
 srows=[]
 for fam in sorted(famrows):
  sem=sems[fam]
  if not sem:
   sem={k:'UNRESOLVED' for k in ['objective_function','community_update_rule','action_selection_rule','learning_automata_semantics','probability_update_semantics','initialization','stopping_rule','convergence_logic','randomness','weight_handling','signed_weight_policy','negative_edges_preserved','negative_edges_dropped','negative_edges_absolutized','negative_edges_transformed','regulatory_layer_handling','multilayer_handling','input_schema']}
  srows.append({'FAMILY_ID':fam,'SCIENTIFIC_STATUS':statuses[fam],'ENTRYPOINT':str(entries.get(fam) or ''),**{k:sem.get(k,'') for k in ['objective_function','community_update_rule','action_selection_rule','learning_automata_semantics','probability_update_semantics','initialization','stopping_rule','convergence_logic','randomness','weight_handling']},'SIGNED_WEIGHT_POLICY':sem.get('signed_weight_policy',''),'NEGATIVE_EDGES_PRESERVED':sem.get('negative_edges_preserved',''),'NEGATIVE_EDGES_DROPPED':sem.get('negative_edges_dropped',''),'NEGATIVE_EDGES_ABSOLUTIZED':sem.get('negative_edges_absolutized',''),'NEGATIVE_EDGES_TRANSFORMED':sem.get('negative_edges_transformed',''),'regulatory_layer_handling':sem.get('regulatory_layer_handling',''),'multilayer_handling':sem.get('multilayer_handling',''),'input_schema':sem.get('input_schema',''),'semantic_fingerprint':fp(sem)})
 pd.DataFrame(srows).to_csv(out/'D10A_V2_ALGORITHM_SEMANTIC_COMPARISON.csv',index=False)
 # R1 stages
 r1families=[f for f in famrows if f in {'R1_PROTOTYPE','R1_IMPLEMENTATION'} or (f.startswith('OBSERVED_') and 'R1' in f)]
 r1code=[r['path'] for f in r1families for r in famrows[f] if r['is_code']=='YES' and any(k in r['relative_path'].lower() for k in ['r1','prototype','implementation'])]
 r1found=bool(r1code);r1exec=found('R1_IMPLEMENTATION_EXECUTED') or found('R1_PROTOTYPE_EXECUTED');r1bench=found('R1_IMPLEMENTATION_BENCHMARKED') or found('R1_PROTOTYPE_BENCHMARKED');r1accept=found('R1_IMPLEMENTATION_ACCEPTED') or found('R1_PROTOTYPE_ACCEPTED') or any(statuses.get(f)=='VALIDATED' for f in ['R1_PROTOTYPE','R1_IMPLEMENTATION'])
 # authority
 accepted_r1=[f for f in ['R1_PROTOTYPE','R1_IMPLEMENTATION'] if statuses.get(f)=='VALIDATED'];authfam='';authentry=None;basis='';amb=False;failstage='';failreason='';outcome=''
 if accepted_r1:
  fps=defaultdict(list)
  for f in accepted_r1:fps[fp(sems[f])].append(f)
  if len(fps)==1:
   authfam='R1_IMPLEMENTATION' if 'R1_IMPLEMENTATION' in accepted_r1 else accepted_r1[0];authentry=entries.get(authfam);basis='HIGHEST_AUTHORITY_PROSPECTIVE_R1_IMPLEMENTED_VALIDATED_ACCEPTED';outcome='A'
  else:outcome='C';amb=True;failstage='MULTIPLE_ACCEPTED_R1_IMPLEMENTATIONS';failreason='Multiple accepted R1 families have incompatible static semantic fingerprints.'
 else:
  published=[f for f,s in statuses.items() if s=='PUBLISHED_BASELINE']
  if r1design:
   outcome='B'
   if not r1found:failstage='R1_IMPLEMENTATION_NOT_FOUND';failreason='B1C-0 prospectively validated an R1 design, but no later R1 prototype/implementation source satisfying the implementation evidence gate was found.'
   elif not r1exec:failstage='R1_IMPLEMENTED_BUT_NOT_EXECUTED';failreason='R1 implementation/prototype source exists, but no preserved evidence demonstrates execution.'
   elif not r1bench:failstage='R1_IMPLEMENTED_BUT_NOT_BENCHMARKED';failreason='R1 implementation was executed, but no preserved benchmark validation evidence reached PASS.'
   elif not r1accept:failstage='R1_VALIDATION_NOT_ACCEPTED';failreason='R1 implementation was benchmarked, but preserved evidence does not demonstrate explicit acceptance.'
   else:outcome='C';amb=True;failstage='R1_ACCEPTANCE_EVIDENCE_NOT_MAPPED_TO_UNIQUE_FAMILY';failreason='Acceptance-like R1 evidence exists but could not be mapped to one unique executable family.'
  elif len(published)==1 and not any(s in {'SUPERSEDED','DIAGNOSTIC_ONLY','REJECTED'} and f!='ORIGINAL_PUBLISHED_ACLA' for f,s in statuses.items()):authfam=published[0];authentry=entries.get(authfam);basis='PUBLISHED_BASELINE_ONLY_SURVIVING_NON_SUPERSEDED_IMPLEMENTATION';outcome='A'
  elif len(published)>1:outcome='C';amb=True;failstage='MULTIPLE_PUBLISHED_BASELINE_FAMILIES';failreason='Multiple published baseline families remain plausible.'
  else:outcome='B';failstage='NO_ACCEPTED_IMPLEMENTATION_LINEAGE_FOUND';failreason='No prospectively accepted implementation and no unique surviving published baseline could be established.'
 authfound=outcome=='A' and authentry is not None
 if outcome=='A' and authentry is None:authfound=False;outcome='B';failstage='AUTHORITATIVE_FAMILY_WITHOUT_EXECUTABLE_ENTRYPOINT';failreason=f'Family {authfam} satisfied authority evidence but no executable/import entrypoint could be resolved.';authfam=''
 # compatibility / manifest if A
 entrysha=packagesha='';required=[];signedpol='';d9signed=d9schema=d9comp=d9reg='NOT_TESTED';blocker='NO'
 authmanifest=out/'D10A_V2_AUTHORITATIVE_ACLA_IMPLEMENTATION_MANIFEST.csv'
 if authfound:
  entrysha=sha256_file(authentry);sem=sems[authfam];signedpol=sem['signed_weight_policy'];required=local_deps(authentry,roots['01_ACLA_CODE']);h=hashlib.sha256();arows=[]
  for p in required:
   try:rel=str(p.relative_to(roots['01_ACLA_CODE'])).replace('\\','/')
   except Exception:rel=p.name
   sh=sha256_file(p);h.update(rel.encode());h.update(b'\0');h.update(sh.encode());h.update(b'\n');arows.append({'role':'ENTRYPOINT' if p.resolve()==authentry.resolve() else 'DEPENDENCY','path':str(p),'relative_path':rel,'SHA256':sh,'size_bytes':p.stat().st_size})
  packagesha=h.hexdigest();pd.DataFrame(arows).to_csv(authmanifest,index=False)
  idir=d9/'D9_ACLA_INPUT';schema=sem['input_schema'];d9schema='YES' if ((schema=='EDGE_LIST' and (idir/'structural_edge_list.csv').is_file()) or (schema=='SPARSE_COO_OR_NPZ' and (idir/'association_score_symmetric_coo.npz').is_file())) else 'NO'
  if sem['negative_edges_dropped']=='YES' or sem['negative_edges_absolutized']=='YES' or sem['negative_edges_transformed']=='YES':d9signed='NO';blocker='YES'
  elif str(sem['negative_edges_preserved']).startswith('YES'):d9signed='YES'
  else:d9signed='NO';blocker='YES'
  et=safe_text(authentry,20_000_000).lower();d9comp='NO' if ('is_connected' in et and ('raise' in et or 'assert' in et)) else 'YES';d9reg='YES' if (sem['regulatory_layer_handling']=='NO_NATIVE_REGULATORY_CHANNEL_DETECTED' or (idir/'regulatory_semantic_edge_list.csv').is_file()) else 'NO'
 elif authmanifest.exists():authmanifest.unlink()
 # parameter provenance; never carried forward
 prows=[]
 for fam in sorted(famrows):
  sem=sems[fam]
  if not sem:continue
  for name,val in sem.get('constants',{}).items():
   if re.search(r'(?i)(seed|iter|alpha|beta|tol|patience|tau|delta|penalty|epsilon|run|threshold)',name):prows.append({'FAMILY_ID':fam,'SCIENTIFIC_STATUS':statuses[fam],'PARAMETER_NAME':name,'VALUE':val,'PROVENANCE_CLASS':'PROSPECTIVELY_VALIDATED_R1' if fam.startswith('R1_') and statuses[fam]=='VALIDATED' else ('DIAGNOSTIC_ONLY' if fam in {'V5','V6','B1','B1A','B1B'} else 'UNKNOWN'),'CARRIED_FORWARD_TO_GSE243219':'NO','SOURCE_ENTRYPOINT':str(entries.get(fam) or '')})
 pd.DataFrame(prows).to_csv(out/'D10A_V2_PARAMETER_PROVENANCE_AUDIT.csv',index=False)
 status='PASS' if authfound else 'FAIL_CLOSED';ready='YES' if authfound else 'NO'
 published='|'.join(sorted(f for f,s in statuses.items() if s=='PUBLISHED_BASELINE'));sup='|'.join(sorted(f for f,s in statuses.items() if s=='SUPERSEDED'));diag='|'.join(sorted(f for f,s in statuses.items() if s=='DIAGNOSTIC_ONLY'));rej='|'.join(sorted(f for f,s in statuses.items() if s=='REJECTED'))
 result={'D10A_V2_STATUS':status,'DISCOVERED_ACLA_FILES':len(inv),'IMPLEMENTATION_FAMILIES_IDENTIFIED':len(famrows),'PUBLISHED_BASELINE_FAMILY':published,'SUPERSEDED_FAMILIES':sup,'DIAGNOSTIC_ONLY_FAMILIES':diag,'REJECTED_FAMILIES':rej,'B1A_EVIDENCE_FOUND':'YES' if b1a else 'NO','B1B_EVIDENCE_FOUND':'YES' if b1b else 'NO','B1C0_R1_DESIGN_EVIDENCE_FOUND':'YES' if b1c else 'NO','R1_DESIGN_VALIDATED':'YES' if r1design else 'NO','R1_IMPLEMENTATION_FOUND':'YES' if r1found else 'NO','R1_IMPLEMENTATION_EXECUTED':'YES' if r1exec else 'NO','R1_IMPLEMENTATION_BENCHMARKED':'YES' if r1bench else 'NO','R1_IMPLEMENTATION_ACCEPTED':'YES' if r1accept else 'NO','AUTHORITATIVE_ACLA_IMPLEMENTATION_FOUND':'YES' if authfound else 'NO','ACLA_IMPLEMENTATION_AMBIGUOUS':'YES' if amb else 'NO','ACLA_AUTHORITATIVE_FAMILY':authfam,'ACLA_AUTHORITATIVE_ENTRYPOINT':str(authentry) if authfound else '','ACLA_ENTRYPOINT_SHA256':entrysha,'ACLA_IMPLEMENTATION_PACKAGE_SHA256':packagesha,'ACLA_REQUIRED_FILES':len(required),'AUTHORITATIVE_SELECTION_BASIS':basis,'INPUT_NODES':EXPECTED_NODES,'INPUT_EDGES':EXPECTED_EDGES,'SIGNED_WEIGHTS_PRESENT':'YES','INPUT_WEIGHT_MIN':wmin,'INPUT_WEIGHT_MAX':wmax,'AUTHORITATIVE_SIGNED_WEIGHT_POLICY':signedpol,'D9_SIGNED_WEIGHT_COMPATIBLE':d9signed,'D9_SCHEMA_COMPATIBLE':d9schema,'D9_COMPONENT_STRUCTURE_COMPATIBLE':d9comp,'D9_REGULATORY_CHANNEL_COMPATIBLE':d9reg,'SIGNED_WEIGHT_COMPATIBILITY_BLOCKER':blocker,'OLD_DATASET_DERIVED_PARAMETER_CARRIED_FORWARD':'NO','NETWORK_CHANGED':'NO','WEIGHT_TRANSFORMATION_APPLIED':'NO','PARAMETER_TUNING_EXECUTED':'NO','GSE243219_ACLA_EXECUTED':'NO','COMMUNITY_RESULTS_CREATED':'NO','FAILURE_STAGE':failstage,'FAILURE_REASON':failreason,'READY_FOR_ACLA_PARAMETER_FREEZE':ready,'READY_FOR_ACLA_EXECUTION':'NO','D10A_V1_RECERTIFIED':v1rec,'STOP':'YES'}
 result_path.write_text(json.dumps(result,indent=2,sort_keys=True),encoding='utf-8')
 (out/'D10A_V2_ADJUDICATION_SPECIFICATION.txt').write_text('GSE243219_D10A_V2_AUTHORITATIVE_IMPLEMENTATION_LINEAGE_ADJUDICATION\nMODE=STATIC_READ_ONLY_LINEAGE_ADJUDICATION\nAUTHORITY_RULE=PROSPECTIVE_DESIGN_PLUS_IMPLEMENTATION_PLUS_BENCHMARK_PLUS_ACCEPTANCE\nPUBLISHED_BASELINE_LOWER_AUTHORITY=YES\nLATEST_FILENAME_SELECTION_ALLOWED=NO\nSIGNED_WEIGHT_TRANSFORMATION_ALLOWED=NO\nOLD_DATASET_PARAMETER_CARRY_FORWARD_ALLOWED=NO\nGSE243219_ACLA_EXECUTED=NO\nNETWORK_CHANGED=NO\nWEIGHT_TRANSFORMATION_APPLIED=NO\nPARAMETER_TUNING_EXECUTED=NO\nSTOP_AFTER_D10A_V2=YES\n',encoding='utf-8')
 return 0

if __name__=='__main__':raise SystemExit(main())
