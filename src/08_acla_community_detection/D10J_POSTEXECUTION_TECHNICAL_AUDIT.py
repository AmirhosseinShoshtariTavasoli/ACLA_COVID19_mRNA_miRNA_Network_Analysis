#!/usr/bin/env python3
from __future__ import annotations
import csv,hashlib,json,math,sys
from collections import defaultdict
from pathlib import Path
import networkx as nx
from networkx.algorithms.community.quality import modularity
SOURCE="ee3c3b735ba6593d5a6af155e599403e697f498b290dc75a39ff0e3ab90b07de"
ADJ="51dd8e6d5bfcec0dfef48be679878677e52d5a4de6eea3f7b2f6ef88a85558ee"
WRAP="794e5564de1cea41a172692cb95f70199563128c2e01beae8c4fd7ed4f58a5a5"
N=4508; E=11531

def sha(p):
    h=hashlib.sha256()
    with open(p,'rb') as f:
        for b in iter(lambda:f.read(8*1024*1024),b''): h.update(b)
    return h.hexdigest()

def req(c,m):
    if not c: raise RuntimeError(m)

def main():
    if len(sys.argv)!=8: raise SystemExit('usage: audit result source wrapper adjacency topology assignments summary')
    result,source,wrapper,adj,topo,assignout,sumout=map(Path,sys.argv[1:])
    req(sha(source)==SOURCE,'SOURCE_SHA_MISMATCH')
    req(sha(wrapper)==WRAP,'WRAPPER_SHA_MISMATCH')
    req(sha(adj)==ADJ,'ADJACENCY_SHA_MISMATCH')
    r=json.loads(result.read_text(encoding='utf-8'))
    for k,v in [('source_sha256',SOURCE),('adjacency_sha256',ADJ)]: req(r.get(k)==v,f'RESULT_{k}_MISMATCH')
    req(r.get('binarize') is True,'BINARIZE_CHANGED')
    req(int(r['iterations'])==200,'ITERATIONS_CHANGED')
    req(abs(float(r['alpha0'])-.2)<1e-15,'ALPHA0_CHANGED')
    req(abs(float(r['alpha_min'])-.01)<1e-15,'ALPHA_MIN_CHANGED')
    req(abs(float(r['global_weight'])-.35)<1e-15,'GLOBAL_WEIGHT_CHANGED')
    req(int(r['patience'])==10,'PATIENCE_CHANGED')
    req(int(r['seed'])==42,'SEED_CHANGED')
    labels={str(k):int(v) for k,v in r['labels'].items()}
    req(len(labels)==N,f'LABEL_COUNT={len(labels)}')
    with adj.open('r',encoding='utf-8',newline='') as f: header=next(csv.reader(f))
    nodes=header[1:]
    req(len(nodes)==N and len(set(nodes))==N,'ADJ_HEADER_NODE_ERROR')
    req(set(nodes)==set(labels),'LABEL_NODE_SET_MISMATCH')
    groups=defaultdict(list)
    for n in nodes: groups[labels[n]].append(n)
    ordered=sorted(groups.values(),key=lambda g:(-len(g),g[0]))
    req(len(ordered)==int(r['communities']),'COMMUNITY_COUNT_MISMATCH')
    canon={n:i for i,g in enumerate(ordered,1) for n in g}
    with assignout.open('w',encoding='utf-8',newline='') as f:
        w=csv.writer(f,lineterminator='\n'); w.writerow(['node_id','original_label','canonical_community_id'])
        for n in nodes: w.writerow([n,labels[n],canon[n]])
    sizes=assignout.parent/'D10J_COMMUNITY_SIZES.csv'
    with sizes.open('w',encoding='utf-8',newline='') as f:
        w=csv.writer(f,lineterminator='\n'); w.writerow(['canonical_community_id','size'])
        for i,g in enumerate(ordered,1): w.writerow([i,len(g)])
    G=nx.Graph(); G.add_nodes_from(nodes); rows=0
    with topo.open('r',encoding='utf-8',newline='') as f:
        for row in csv.DictReader(f): G.add_edge(str(row['source']),str(row['target'])); rows+=1
    req(rows==E and G.number_of_edges()==E and G.number_of_nodes()==N,'TOPOLOGY_RECONSTRUCTION_MISMATCH')
    comms=[set(g) for g in ordered]
    q2=float(modularity(G,comms,weight=None)); q1=float(r['modularity'])
    diff=abs(q2-q1); req(math.isfinite(q1) and math.isfinite(q2) and diff<=1e-12,f'MODULARITY_MISMATCH diff={diff}')
    elapsed=float(r['elapsed_seconds']); req(math.isfinite(elapsed) and elapsed>=0,'INVALID_RUNTIME')
    disconnected=sum(1 for g in comms if len(g)>1 and not nx.is_connected(G.subgraph(g)))
    s={
      'D10J_TECHNICAL_VALIDATION':'PASS','nodes':N,'edges':E,'communities':len(ordered),
      'largest_community_size':max(map(len,ordered)),'smallest_community_size':min(map(len,ordered)),
      'singleton_communities':sum(len(g)==1 for g in ordered),'disconnected_induced_communities':disconnected,
      'wrapper_modularity':q1,'independent_modularity':q2,'modularity_abs_diff':diff,'elapsed_seconds':elapsed,
      'biological_interpretation_executed':'NO','signed_edge_characterization_executed':'NO','regulatory_characterization_executed':'NO'}
    sumout.write_text(json.dumps(s,indent=2),encoding='utf-8')
    return 0
if __name__=='__main__': raise SystemExit(main())
