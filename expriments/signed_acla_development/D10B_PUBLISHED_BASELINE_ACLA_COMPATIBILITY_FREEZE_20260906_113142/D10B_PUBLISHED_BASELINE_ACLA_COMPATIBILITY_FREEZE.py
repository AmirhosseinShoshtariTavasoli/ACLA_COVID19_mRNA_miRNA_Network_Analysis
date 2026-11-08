#!/usr/bin/env python3
from __future__ import annotations
import ast, hashlib, json, math, re, sys, zipfile
from collections import Counter, defaultdict
from pathlib import Path
import numpy as np
import pandas as pd

NODES=4508; EDGES=11531; COMPS=2; WMIN=-0.7753835531973502; WMAX=0.7428957195865319
TITLE='A-CLA: A Novel Adaptive Cellular Learning Automata Approach for Uncovering Communities in Complex Networks'
DOI='10.1016/j.comnet.2026.112103'
TEXT_EXT={'.py','.ps1','.txt','.md','.csv','.json','.yaml','.yml','.toml','.ini','.log','.xml','.r','.R','.jl','.m'}
EXCLUDE=[
 re.compile(r'(?i)(?:^|[^a-z0-9])candidate[_ -]?v[1-6](?:[^a-z0-9]|$)'),
 re.compile(r'(?i)(?:^|[^a-z0-9])b1(?:a|b|c)?(?:\d+)?(?:[^a-z0-9]|$)'),
 re.compile(r'(?i)r1[_ -]?(?:prototype|implementation|benchmark|diagnostic|redesign)'),
 re.compile(r'(?i)(?:refined|probability[_ -]?guided|action[_ -]?remap|hard[_ -]?action)'),
]
BASE=re.compile(r'(?i)^(?:a-cla|a_cla|acla)(?:[_ -]?(?:main|original|published|baseline))?\.py$')
PUBPATH=re.compile(r'(?i)(published|publication|article|paper|original|journal|computer[_ -]?networks|repository|github|supplement|source[_ -]?code)')
PUBTXT=re.compile(r'(?i)(A-CLA:\s*A Novel Adaptive Cellular Learning Automata Approach|10\.1016/j\.comnet\.2026\.112103|Computer Networks.{0,80}112103)')
POS=[
 ('WHERE_POSITIVE',re.compile(r'(?is)\.where\s*\(\s*[^,\n]*(?:>|>=)\s*0\s*,\s*0(?:\.0+)?\s*\)')),
 ('NEGATIVE_ZERO',re.compile(r'(?is)\[[^\]]*<\s*0[^\]]*\]\s*=\s*0(?:\.0+)?')),
 ('NP_MAXIMUM_ZERO',re.compile(r'(?is)np\.maximum\s*\([^,\n]+,\s*0(?:\.0+)?\s*\)')),
 ('CLIP_MIN_ZERO',re.compile(r'(?is)(?:np\.)?clip\s*\([^\)]*(?:a_min|min)\s*=\s*0')),
 ('IF_WEIGHT_POSITIVE',re.compile(r'(?im)^\s*if\s+[^\n:]{0,120}(?:weight|w|adj|a\[)[^\n:]{0,120}(?:>|>=)\s*0\s*:')),
]
ABS=[('NP_ABS',re.compile(r'(?is)np\.abs\s*\([^\)]*(?:weight|adj|matrix|\bA\b)[^\)]*\)')),('ABS',re.compile(r'(?is)\babs\s*\([^\)]*(?:weight|adj|matrix|\bA\b)[^\)]*\)'))]
SIGNED=[('SIGNED_MODULARITY',re.compile(r'(?i)signed[_ -]?modularity|modularity[_ -]?signed')),('SIGNED_NETWORK',re.compile(r'(?i)signed[_ -]?(?:network|graph|edge|weight)')),('POS_NEG_SPLIT',re.compile(r'(?is)(?:positive|pos)[^\n]{0,120}(?:negative|neg)|(?:negative|neg)[^\n]{0,120}(?:positive|pos)'))]
UNSIGNED=[('MODULARITY',re.compile(r'(?i)quality\.modularity|\bmodularity\s*\('))]

def sha(path):
 h=hashlib.sha256();
 with open(path,'rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''): h.update(b)
 return h.hexdigest()

def shab(b): return hashlib.sha256(b).hexdigest()
def excluded(s): return any(x.search(s.replace('\\','/')) for x in EXCLUDE)

def text(path,limit=30_000_000):
 try:
  if path.stat().st_size>limit:return ''
  if path.suffix.lower()=='.docx':
   with zipfile.ZipFile(path) as z: x=z.read('word/document.xml').decode('utf-8','replace')
   x=re.sub(r'</w:p>','\n',x); return re.sub(r'<[^>]+>','',x)
  if path.suffix in TEXT_EXT:return path.read_text(encoding='utf-8',errors='replace')
 except Exception:return ''
 return ''

def recert(man,label):
 d=pd.read_csv(man,dtype=str,keep_default_na=False); need={'full_path','size_bytes','SHA256'}
 if need-set(d.columns): raise RuntimeError(label+'_MANIFEST_SCHEMA')
 bad=[]
 for _,r in d.iterrows():
  p=Path(r.full_path)
  if not p.is_file() or p.stat().st_size!=int(r.size_bytes) or sha(p)!=r.SHA256.lower(): bad.append(str(p))
 if bad: raise RuntimeError(f'{label}_HASH_MISMATCHES={len(bad)}')

def snap(root):
 return {str(p):(p.stat().st_size,p.stat().st_mtime_ns) for p in root.rglob('*') if p.is_file()}

class UF:
 def __init__(self,n): self.p={x:x for x in n}; self.s={x:1 for x in n}
 def f(self,x):
  if self.p[x]!=x:self.p[x]=self.f(self.p[x])
  return self.p[x]
 def u(self,a,b):
  a,b=self.f(a),self.f(b)
  if a==b:return
  if self.s[a]<self.s[b]:a,b=b,a
  self.p[b]=a;self.s[a]+=self.s[b]

def cstats(nodes,e):
 u=UF(nodes);deg=Counter({x:0 for x in nodes})
 for a,b in zip(e.source,e.target):
  if a==b:continue
  u.u(a,b);deg[a]+=1;deg[b]+=1
 c=defaultdict(int)
 for x in nodes:c[u.f(x)]+=1
 s=sorted(c.values(),reverse=True)
 return len(s),s[0],s[1],sum(v==0 for v in deg.values())

def pubdocs(roots):
 out=[]
 for rn,r in roots.items():
  for p in r.rglob('*'):
   if not p.is_file():continue
   rel=f'{rn}/{str(p.relative_to(r)).replace(chr(92),"/")}'
   if excluded(rel):continue
   if p.suffix.lower() not in {'.txt','.md','.csv','.json','.docx'} and not PUBPATH.search(rel):continue
   t=text(p)
   if PUBTXT.search(t):out.append((p,rel,sha(p)))
 return out

def candidates(roots):
 docs=pubdocs(roots); out=[]
 for rn,r in roots.items():
  for p in r.rglob('*'):
   if not p.is_file() or p.suffix.lower()!='.py':continue
   rel=f'{rn}/{str(p.relative_to(r)).replace(chr(92),"/")}'
   if excluded(rel):continue
   t=text(p)
   score=0;why=[]
   if BASE.match(p.name):score+=10;why.append('BASELINE_FILENAME')
   if PUBPATH.search(rel):score+=5;why.append('PUBLICATION_PATH')
   if PUBTXT.search(t):score+=8;why.append('PUBLICATION_FINGERPRINT_IN_SOURCE')
   if re.search(r'(?i)adaptive cellular learning automata|\bA-CLA\b',t):score+=2;why.append('ACLA_TEXT')
   if not (BASE.match(p.name) or PUBTXT.search(t) or (PUBPATH.search(rel) and 'acla' in p.name.lower())):continue
   # nearby publication doc
   pp=set(p.parent.parts)
   if any(len(pp & set(d[0].parent.parts))>=max(1,len(pp)-2) for d in docs):score+=6;why.append('NEAR_PUBLICATION_DOC')
   out.append({'path':str(p),'rel':rel,'name':p.name,'sha':sha(p),'size':p.stat().st_size,'score':score,'why':'|'.join(why),'text':t})
 return docs,out

def select(cs):
 strong=[c for c in cs if c['score']>=10]
 by=defaultdict(list)
 for c in strong:by[c['sha']].append(c)
 if len(by)!=1:return None,strong
 v=next(iter(by.values()));v.sort(key=lambda c:(-c['score'],len(c['path']),c['path'].lower()));return v[0],strong

def hits(t,pats):
 lines=t.splitlines();out=[]
 for lab,rg in pats:
  for m in rg.finditer(t):
   ln=t.count('\n',0,m.start())+1;ctx=' | '.join(lines[max(0,ln-2):min(len(lines),ln+1)])[:2000]
   out.append((lab,ln,m.group(0)[:700],ctx))
 return out

def astinfo(t,label):
 try:tr=ast.parse(t,filename=label)
 except Exception as e:return None,[],[],str(e)
 calls=[];imports=[]
 for n in ast.walk(tr):
  if isinstance(n,ast.Call):
   try:calls.append(ast.unparse(n.func))
   except:pass
  elif isinstance(n,ast.Import):imports += [a.name for a in n.names]
  elif isinstance(n,ast.ImportFrom) and n.module:imports.append(n.module)
 return tr,sorted(set(calls)),sorted(set(imports)),''

def schema(t,calls):
 l=t.lower()
 if any('read_edgelist' in c.lower() or 'from_pandas_edgelist' in c.lower() for c in calls) or ('read_csv' in l and 'source' in l and 'target' in l):return 'EDGE_LIST'
 if any('from_numpy' in c.lower() for c in calls) or ('read_csv' in l and ('adjacency' in l or 'adj_matrix' in l)):return 'ADJACENCY_MATRIX'
 if 'np.load' in l and 'row' in l and 'col' in l:return 'SPARSE_COO_NPZ'
 if 'networkx' in l or 'nx.graph' in l:return 'NETWORKX_GRAPH_OBJECT_OR_INTERNAL_CONSTRUCTION'
 return 'UNRESOLVED'

def semantics(t,calls):
 l=t.lower(); ph=hits(t,POS);ah=hits(t,ABS);sh=hits(t,SIGNED);uh=hits(t,UNSIGNED)
 consumes=bool(re.search(r'(?i)weight\s*=|\[[\'\"]weight[\'\"]\]|(?:adj|matrix|\bA\b)\s*\[[^\]]+\]',t))
 topology=(not consumes) and any(x in l for x in ['neighbors(','.neighbors(','.has_edge(','.add_edge(','number_of_edges'])
 if ph:policy='POSITIVE_ONLY_FILTER_OR_ZEROING'
 elif ah:policy='ABSOLUTE_VALUE_SIGN_REMOVAL'
 elif topology:policy='TOPOLOGY_ONLY_BINARY_EDGE_EXISTENCE'
 elif consumes:policy='RAW_WEIGHT_VALUES_PROPAGATED_STATICALLY'
 else:policy='WEIGHT_USAGE_NOT_DEMONSTRATED'
 explicit=bool(sh); unsigned=bool(uh) and not explicit
 signed='SIGNED_EXPLICIT' if explicit and not ph and not ah else ('UNSIGNED' if ph or ah or topology or unsigned else 'UNCERTIFIED')
 negzero='YES' if any(x[0] in {'WHERE_POSITIVE','NEGATIVE_ZERO','NP_MAXIMUM_ZERO','CLIP_MIN_ZERO'} for x in ph) else 'NO'
 negdrop='YES' if any(x[0]=='IF_WEIGHT_POSITIVE' for x in ph) else 'NO'
 negabs='YES' if ah else 'NO'
 negpres='YES' if consumes and not ph and not ah else 'NO'
 direction='DIRECTED' if 'nx.digraph(' in l else ('UNDIRECTED' if 'nx.graph(' in l else 'UNRESOLVED')
 objective='MODULARITY_OR_DERIVED' if 'modularity' in l else 'UNRESOLVED'
 init='RANDOM_OR_STOCHASTIC' if 'random' in l and ('community' in l or 'label' in l) else ('EACH_NODE_OWN_COMMUNITY' if 'own community' in l or 'singleton' in l else 'UNRESOLVED')
 update='LEARNING_AUTOMATA_NEIGHBORHOOD_UPDATE' if ('probability' in l and 'neighbor' in l) else 'UNRESOLVED'
 action='ARGMAX_PROBABILITY' if 'argmax' in l else ('STOCHASTIC_CHOICE' if 'random.choice' in l or 'np.random.choice' in l else 'UNRESOLVED')
 prob='REWARD_PENALTY_UPDATE' if 'reward' in l and 'penalty' in l else ('LEARNING_RATE_PROBABILITY_UPDATE' if 'probability' in l and ('alpha' in l or 'beta' in l or 'learning_rate' in l) else 'UNRESOLVED')
 stop='TOLERANCE_PLUS_PATIENCE' if 'patience' in l and ('tol' in l or 'converg' in l) else ('MAX_ITERATIONS' if 'max_iter' in l or 'max_iterations' in l else ('CONVERGENCE_RULE_PRESENT' if 'converg' in l else 'UNRESOLVED'))
 multilayer='YES' if re.search(r'(?i)\bmultilayer\b|\blayer[_ -]?(?:weight|mass|id|type)\b',t) else 'NO'
 regulatory='YES' if re.search(r'(?i)\bregulatory\b|tarbase|targetscan|mirdb|mirna.*mrna',t) else 'NO'
 nodeused='YES' if re.search(r'(?i)node[_ -]?type|mirna|mrna|bipartite',t) else 'NO'
 hetero='NO' if re.search(r'(?i)(?:requires?|assert).{0,80}(?:homogeneous|single node type)',t) else 'YES'
 giant='YES' if re.search(r'(?i)largest_connected_component|giant_component',t) else 'NO'
 artificial='YES' if re.search(r'(?i)connect_components|add_edge.{0,100}component',t) else 'NO'
 connreq=bool(re.search(r'(?i)is_connected|connected graph required|assert.{0,80}connected',t))
 generic=bool(re.search(r'(?i)for\s+\w+\s+in\s+G\.nodes|graph\.nodes|nodes\(\)',t))
 disconnected='NO' if giant=='YES' or artificial=='YES' or connreq else ('YES' if generic else 'NO')
 return locals()

def localdeps(entry,imports,root):
 req={entry.resolve()}
 for mod in imports:
  top=mod.split('.')[0]
  for c in [entry.parent/f'{top}.py',root/f'{top}.py',entry.parent/top/'__init__.py',root/top/'__init__.py']:
   if c.is_file():req.add(c.resolve());break
 return sorted(req,key=lambda p:str(p).lower())

def d9input(d9,sc):
 idir=d9/'D9_ACLA_INPUT'
 cand=[]
 if sc=='EDGE_LIST':cand=[idir/'structural_edge_list.csv',d9/'D9_MASTER_EDGES.csv']
 elif sc=='SPARSE_COO_NPZ':cand=[idir/'association_score_symmetric_coo.npz']
 elif sc=='NETWORKX_GRAPH_OBJECT_OR_INTERNAL_CONSTRUCTION':cand=[idir/'structural_edge_list.csv',d9/'D9_MASTER_EDGES.csv']
 for p in cand:
  if p.is_file():return 'YES',str(p),sha(p)
 return 'NO','',''

def refined_positive(roots):
 out=[]
 for rn,r in roots.items():
  for p in r.rglob('*.py'):
   rel=f'{rn}/{str(p.relative_to(r)).replace(chr(92),"/")}'
   if not re.search(r'(?i)(refined|probability[_ -]?guided|candidate[_ -]?v|action[_ -]?remap)',rel):continue
   h=hits(text(p),POS)
   if h:out.append({'path':str(p),'SHA256':sha(p),'line':h[0][1],'match':h[0][2]})
 return out

def selftest():
 assert excluded('x/Candidate_V6/A-CLA.py');assert excluded('x/B1C41/R1_PROTOTYPE.py');assert not excluded('x/PUBLISHED/A-CLA.py')
 assert BASE.match('A-CLA.py')
 s=semantics('A = A.where(A > 0, 0.0)\n',[]);assert s['negzero']=='YES'
 s=semantics('A=np.abs(A)\n',[]);assert s['negabs']=='YES'
 s=semantics('G.add_edge(u,v)\nfor n in G.neighbors(u): pass\n',[]);assert s['topology']
 print('D10B_INTERNAL_SELFTEST=PASS');print('BASELINE_BRANCH_EXCLUSION_SELFTEST=PASS');print('WEIGHT_POLICY_SELFTEST=PASS');print('NO_GSE243219_ALGORITHM_EXECUTION_SELFTEST=PASS')

def main():
 if len(sys.argv)==2 and sys.argv[1]=='--self-test':selftest();return 0
 if len(sys.argv)!=6:raise SystemExit('usage: script project reusable d9 out result')
 project,reusable,d9,out,result=map(Path,sys.argv[1:]);out.mkdir(parents=True,exist_ok=True)
 before=snap(d9);recert(d9/'D9_SHA256_MANIFEST.csv','D9')
 stat=(d9/'D9_FINAL_STATUS.txt').read_text(encoding='utf-8-sig',errors='replace')
 for tok in ['D9_STATUS=PASS','TOTAL_NODES=4508','TOTAL_STRUCTURAL_EDGES=11531','CONNECTED_COMPONENTS=2','LARGEST_COMPONENT_NODES=4502','SELF_LOOPS=0','DUPLICATE_STRUCTURAL_EDGES=0','ACLA_EXECUTED=NO','D9_HASH_MISMATCHES=0']:
  if tok not in stat:raise RuntimeError('D9_STATUS_TOKEN_MISSING='+tok)
 nd=pd.read_csv(d9/'D9_MASTER_NODES.csv',dtype={'node_id':str});ed=pd.read_csv(d9/'D9_MASTER_EDGES.csv',dtype={'source':str,'target':str},float_precision='round_trip')
 if len(nd)!=NODES or len(ed)!=EDGES or nd.node_id.duplicated().any() or ed.duplicated(['source','target']).any():raise RuntimeError('D9_GRAPH_GATE_FAILED')
 w=pd.to_numeric(ed.association_score,errors='coerce').to_numpy(float)
 if not np.isfinite(w).all() or not np.any(w<0) or not math.isclose(float(w.min()),WMIN,abs_tol=1e-15,rel_tol=0) or not math.isclose(float(w.max()),WMAX,abs_tol=1e-15,rel_tol=0):raise RuntimeError('D9_WEIGHT_GATE_FAILED')
 if cstats(nd.node_id.tolist(),ed)!=(2,4502,6,0):raise RuntimeError('D9_COMPONENT_GATE_FAILED')
 roots={'01_ACLA_CODE':reusable/'01_ACLA_CODE','07_METHODS_AND_DOCUMENTATION':reusable/'07_METHODS_AND_DOCUMENTATION','09_OLD_METHOD_HISTORY':reusable/'09_OLD_METHOD_HISTORY'}
 for r in roots.values():
  if not r.is_dir():raise RuntimeError('SEARCH_ROOT_MISSING='+str(r))
 docs,cs=candidates(roots);sel,strong=select(cs)
 pd.DataFrame([{k:c[k] for k in ['path','rel','name','sha','size','score','why']} for c in cs],columns=['path','rel','name','sha','size','score','why']).to_csv(out/'D10B_PUBLISHED_ACLA_IDENTIFICATION_CANDIDATES.csv',index=False)
 pd.DataFrame([{'path':str(p),'relative_path':rel,'SHA256':sh} for p,rel,sh in docs],columns=['path','relative_path','SHA256']).to_csv(out/'D10B_PUBLICATION_PROVENANCE_EVIDENCE.csv',index=False)
 later=refined_positive(roots);pd.DataFrame(later,columns=['path','SHA256','line','match']).to_csv(out/'D10B_LATER_BRANCH_POSITIVE_ONLY_COMPARISON.csv',index=False)
 semrows=[];flow=[];cm=[];synth=[{'test':'SYNTHETIC_SIGNED_WEIGHT_TEST','executed':'NO','result':'NOT_RUN','reason':'Static source/method audit only; published code is never imported or executed.'}]
 found=sel is not None;entry='';entrysha='';pkgsha='';sc='';native='NO';infile='';insha='';compat='FAIL';ready='NO';fail='PUBLISHED_ACLA_IMPLEMENTATION_AMBIGUOUS_OR_MISSING';signedext='NO';newmeth='NO';toppossible='NO';toppreserve='NO'
 default={'consumes':False,'topology':False,'policy':'','negpres':'NO','negdrop':'NO','negzero':'NO','negabs':'NO','signed':'UNCERTIFIED','ph':[],'sh':[],'uh':[],'direction':'UNRESOLVED','objective':'UNRESOLVED','init':'UNRESOLVED','update':'UNRESOLVED','action':'UNRESOLVED','prob':'UNRESOLVED','stop':'UNRESOLVED','multilayer':'NO','regulatory':'NO','nodeused':'NO','hetero':'NO','giant':'NO','artificial':'NO','disconnected':'NO'}
 s=default
 if found:
  entry=sel['path'];entrysha=sel['sha'];tr,calls,imports,err=astinfo(sel['text'],entry)
  if tr is None:fail='PUBLISHED_ACLA_SOURCE_PARSE_FAILED:'+err
  else:
   sc=schema(sel['text'],calls);s=semantics(sel['text'],calls);deps=localdeps(Path(entry),imports,roots['01_ACLA_CODE'])
   mh=hashlib.sha256();mrows=[]
   for p in deps:
    sh=sha(p);role='ENTRYPOINT' if p.resolve()==Path(entry).resolve() else 'DEPENDENCY';mrows.append({'role':role,'full_path':str(p),'size_bytes':p.stat().st_size,'SHA256':sh});mh.update((role+'\0'+p.name+'\0'+sh+'\n').encode())
   pd.DataFrame(mrows).to_csv(out/'D10B_PUBLISHED_ACLA_IMPLEMENTATION_MANIFEST.csv',index=False);pkgsha=mh.hexdigest();native,infile,insha=d9input(d9,sc)
   fields=[('INPUT_SCHEMA',sc,''),('DIRECTED_OR_UNDIRECTED',s['direction'],''),('WEIGHTED_OR_UNWEIGHTED','WEIGHTED' if s['consumes'] else 'UNWEIGHTED',''),('SIGNED_OR_UNSIGNED',s['signed'],'Explicit signed semantics required.'),('OBJECTIVE_FUNCTION',s['objective'],''),('INITIALIZATION_METHOD',s['init'],''),('COMMUNITY_UPDATE_RULE',s['update'],''),('ACTION_SELECTION_RULE',s['action'],''),('PROBABILITY_UPDATE_RULE',s['prob'],''),('STOPPING_CRITERION',s['stop'],''),('MULTICOMPONENT_GRAPH_SUPPORTED',s['disconnected'],''),('MULTILAYER_SUPPORTED',s['multilayer'],''),('REGULATORY_METADATA_SUPPORTED',s['regulatory'],''),('HETEROGENEOUS_NODE_TYPES_SUPPORTED',s['hetero'],''),('NODE_TYPE_USED_BY_OPTIMIZATION',s['nodeused'],'')]
   semrows=[{'field':a,'value':b,'evidence':c} for a,b,c in fields]
   modes=[]
   modes.append(('D9_INPUT_EDGE_WEIGHT','RAW_SIGNED_WEIGHT_USED','D9 association_score is signed and frozen.'))
   parsermode='POSITIVE_ONLY_WEIGHT_USED' if s['ph'] else ('BINARY_EDGE_ONLY' if s['topology'] else ('RAW_SIGNED_WEIGHT_USED' if s['consumes'] else 'WEIGHT_UNUSED'))
   modes.append(('PARSER',parsermode,s['policy']));modes.append(('ADJACENCY_CONSTRUCTION',parsermode,s['policy']))
   objmode='RAW_SIGNED_WEIGHT_USED' if s['signed']=='SIGNED_EXPLICIT' else ('BINARY_EDGE_ONLY' if s['topology'] else ('POSITIVE_ONLY_WEIGHT_USED' if s['signed']=='UNSIGNED' and s['consumes'] else 'WEIGHT_UNUSED'))
   modes.append(('OBJECTIVE_CALCULATION',objmode,s['objective']));modes.append(('LOCAL_UPDATE_REWARD',parsermode,s['update']));modes.append(('GLOBAL_OBJECTIVE',objmode,s['objective']));modes.append(('CONVERGENCE_LOGIC',objmode if 'CONVERGENCE' in s['stop'] else 'WEIGHT_UNUSED',s['stop']))
   for st,mo,ev in modes:flow.append({'stage':st,'mode':mo,'raw_signed_weight_used':'YES' if mo=='RAW_SIGNED_WEIGHT_USED' else 'NO','positive_only_weight_used':'YES' if mo=='POSITIVE_ONLY_WEIGHT_USED' else 'NO','binary_edge_only':'YES' if mo=='BINARY_EDGE_ONLY' else 'NO','weight_unused':'YES' if mo=='WEIGHT_UNUSED' else 'NO','evidence':ev})
   signedok=s['consumes'] and s['negpres']=='YES' and s['signed']=='SIGNED_EXPLICIT' and not s['ph'] and s['negabs']=='NO'
   toppossible='YES' if s['topology'] or not s['consumes'] else 'NO';toppreserve='NO'
   dims=[('PUBLISHED_IMPLEMENTATION_IDENTIFIED','PASS','Unique baseline hash.',False),('INPUT_SCHEMA_NATIVE_D9_EXPORT','PASS' if native=='YES' else 'FAIL',infile or 'No native D9 export matches required schema.',native!='YES'),('SIGNED_WEIGHT_SEMANTICS','PASS' if signedok else 'FAIL',f"policy={s['policy']}; signed={s['signed']}",not signedok),('NEGATIVE_WEIGHT_PRESERVATION','PASS' if s['negpres']=='YES' else 'FAIL',f"drop={s['negdrop']}; zero={s['negzero']}; abs={s['negabs']}",s['negpres']!='YES'),('DISCONNECTED_GRAPH','PASS' if s['disconnected']=='YES' else 'FAIL',f"giant={s['giant']}; artificial={s['artificial']}",s['disconnected']!='YES'),('MIXED_NODE_IDENTIFIERS','PASS' if s['hetero']=='YES' else 'FAIL',f"node_type_used={s['nodeused']}",s['hetero']!='YES'),('MULTILAYER_CHANNEL','INFO' if s['multilayer']=='NO' else 'PASS',f"native_multilayer={s['multilayer']}",False),('REGULATORY_SEMANTIC_CHANNEL','INFO' if s['regulatory']=='NO' else 'PASS',f"native_regulatory={s['regulatory']}",False),('TOPOLOGY_ONLY_PRESERVES_D9_SIGNED_SEMANTICS','FAIL' if toppossible=='YES' else 'N/A','D9 freezes sign and magnitude.' if toppossible=='YES' else 'Not topology-only.',toppossible=='YES')]
   cm=[{'compatibility_dimension':a,'status':b,'evidence':c,'blocking':'YES' if d else 'NO'} for a,b,c,d in dims];blocks=[x for x in cm if x['blocking']=='YES']
   if not blocks:compat='PASS';ready='YES';fail=''
   else:
    fail=';'.join(x['compatibility_dimension'] for x in blocks)
    if any(x['compatibility_dimension'] in {'SIGNED_WEIGHT_SEMANTICS','NEGATIVE_WEIGHT_PRESERVATION','TOPOLOGY_ONLY_PRESERVES_D9_SIGNED_SEMANTICS'} for x in blocks):signedext='YES';newmeth='YES'
 if not (out/'D10B_PUBLISHED_ACLA_IMPLEMENTATION_MANIFEST.csv').exists():pd.DataFrame([{'role':'NOT_IDENTIFIED','full_path':'','size_bytes':'','SHA256':''}]).to_csv(out/'D10B_PUBLISHED_ACLA_IMPLEMENTATION_MANIFEST.csv',index=False)
 pd.DataFrame(semrows,columns=['field','value','evidence']).to_csv(out/'D10B_PUBLISHED_ACLA_SEMANTICS.csv',index=False);pd.DataFrame(flow,columns=['stage','mode','raw_signed_weight_used','positive_only_weight_used','binary_edge_only','weight_unused','evidence']).to_csv(out/'D10B_PUBLISHED_ACLA_WEIGHT_DATAFLOW.csv',index=False);pd.DataFrame(cm,columns=['compatibility_dimension','status','evidence','blocking']).to_csv(out/'D10B_D9_COMPATIBILITY_MATRIX.csv',index=False);pd.DataFrame(synth).to_csv(out/'D10B_SYNTHETIC_TEST_REPORT.csv',index=False)
 recert(d9/'D9_SHA256_MANIFEST.csv','D9_POST');d9mod='NO' if before==snap(d9) else 'YES'
 if d9mod!='NO':raise RuntimeError('D9_FILES_MODIFIED')
 lateronly='YES' if s['ph']==[] and later else ('NO' if s['ph'] else ('UNKNOWN' if not later else 'YES'))
 res={'D10B_STATUS':'PASS' if found and compat=='PASS' else 'FAIL_CLOSED','PUBLISHED_ACLA_IMPLEMENTATION_FOUND':'YES' if found else 'NO','PUBLISHED_ACLA_ENTRYPOINT':entry,'PUBLISHED_ACLA_ENTRYPOINT_SHA256':entrysha,'PUBLISHED_ACLA_IMPLEMENTATION_PACKAGE_SHA256':pkgsha,'PUBLISHED_ACLA_REQUIRED_INPUT_SCHEMA':sc,'PUBLISHED_ACLA_CONSUMES_EDGE_WEIGHTS':'YES' if s['consumes'] else 'NO','PUBLISHED_ACLA_TOPOLOGY_ONLY':'YES' if s['topology'] else 'NO','PUBLISHED_ACLA_WEIGHT_POLICY':s['policy'],'NEGATIVE_WEIGHTS_PRESERVED':s['negpres'],'NEGATIVE_WEIGHTS_DROPPED':s['negdrop'],'NEGATIVE_WEIGHTS_ZEROED':s['negzero'],'NEGATIVE_WEIGHTS_ABSOLUTIZED':s['negabs'],'NEGATIVE_WEIGHTS_OTHER_TRANSFORMATION':'YES' if s['topology'] else 'NO','POSITIVE_ONLY_LOGIC_PRESENT_IN_PUBLISHED_ACLA':'YES' if s['ph'] else 'NO','POSITIVE_ONLY_LOGIC_PRESENT_ONLY_IN_LATER_BRANCH':lateronly,'D9_NATIVE_COMPATIBLE_INPUT_AVAILABLE':native,'D9_COMPATIBLE_INPUT_FILE':infile,'D9_COMPATIBLE_INPUT_SHA256':insha,'INPUT_NODES':4508,'INPUT_EDGES':11531,'INPUT_COMPONENTS':2,'DISCONNECTED_GRAPH_SUPPORTED':s['disconnected'],'GIANT_COMPONENT_ONLY_REQUIRED':s['giant'],'ARTIFICIAL_CONNECTIVITY_REQUIRED':s['artificial'],'HETEROGENEOUS_NODE_TYPES_SUPPORTED':s['hetero'],'NODE_TYPE_USED_BY_OPTIMIZATION':s['nodeused'],'PUBLISHED_ACLA_MULTILAYER_SUPPORT':s['multilayer'],'PUBLISHED_ACLA_REGULATORY_CHANNEL_SUPPORT':s['regulatory'],'TOPOLOGY_ONLY_APPLICATION_POSSIBLE':toppossible,'TOPOLOGY_ONLY_APPLICATION_PRESERVES_D9_SEMANTICS':toppreserve,'PUBLISHED_ACLA_D9_COMPATIBILITY':compat,'SIGNED_ACLA_EXTENSION_REQUIRED':signedext,'NEW_METHODOLOGY_REQUIRED':newmeth,'SYNTHETIC_TEST_EXECUTED':'NO','SYNTHETIC_SIGNED_WEIGHT_TEST':'NOT_RUN','NETWORK_CHANGED':'NO','D9_FILES_MODIFIED':d9mod,'WEIGHT_TRANSFORMATION_APPLIED':'NO','NEGATIVE_EDGES_REMOVED':'NO','PARAMETER_FREEZE_EXECUTED':'NO','PARAMETER_TUNING_EXECUTED':'NO','GSE243219_ACLA_EXECUTED':'NO','FAILURE_REASON':fail,'READY_FOR_D10C_PARAMETER_AND_EXECUTION_FREEZE':ready,'READY_FOR_ACLA_EXECUTION':'NO','STOP':'YES'}
 result.write_text(json.dumps(res,indent=2,sort_keys=True),encoding='utf-8');return 0
if __name__=='__main__':raise SystemExit(main())
