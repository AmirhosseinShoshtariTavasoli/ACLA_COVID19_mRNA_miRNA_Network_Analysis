from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd

from .io import graph_from_adjacency, load_adjacency
from .metrics import overlap_summary, top_betweenness_nodes
from .nonoverlap import detect_nonoverlapping
from .overlap import detect_overlap_extension


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run the A-CLA reference implementation")
    parser.add_argument("--input", required=True, help="Adjacency matrix (.xlsx/.csv)")
    parser.add_argument("--mode", choices=["nonoverlap", "overlap"], default="nonoverlap")
    parser.add_argument("--iterations", type=int, default=None)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--alpha", type=float, default=0.20, help="Initial alpha for non-overlap mode")
    parser.add_argument("--global-weight", type=float, default=0.35)
    parser.add_argument("--weighted", action="store_true")
    parser.add_argument("--output-dir", default="outputs")
    return parser


def main(argv=None) -> int:
    args = _parser().parse_args(argv)
    input_path = Path(args.input)
    adjacency = load_adjacency(input_path)
    graph = graph_from_adjacency(adjacency, binarize=not args.weighted, use_weights=args.weighted)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    if args.mode == "nonoverlap":
        labels, communities, q = detect_nonoverlapping(
            graph,
            iterations=args.iterations or 200,
            alpha0=args.alpha,
            global_weight=args.global_weight,
            seed=args.seed,
        )
        rows = [{"node": node, "community": community} for node, community in labels.items()]
        out_csv = output_dir / f"{input_path.stem}_acla_partition.csv"
        pd.DataFrame(rows).to_csv(out_csv, index=False)
        summary = {
            "mode": "nonoverlap",
            "input": str(input_path),
            "nodes": graph.number_of_nodes(),
            "edges": graph.number_of_edges(),
            "communities": len(communities),
            "modularity": q,
            "seed": args.seed,
            "output": str(out_csv),
            "top_betweenness": top_betweenness_nodes(graph, 3, weighted=args.weighted),
        }
    else:
        communities, memberships, _, _ = detect_overlap_extension(
            graph,
            iterations=args.iterations or 300,
            seed=args.seed,
            use_weights=args.weighted,
            beta_global=args.global_weight,
        )
        rows = [
            {"node": node, "communities": ",".join(map(str, sorted(labels))), "multiplicity": len(labels)}
            for node, labels in memberships.items()
        ]
        out_csv = output_dir / f"{input_path.stem}_acla_overlap_membership.csv"
        pd.DataFrame(rows).to_csv(out_csv, index=False)
        summary = {
            "mode": "overlap (exploratory extension)",
            "input": str(input_path),
            "nodes": graph.number_of_nodes(),
            "edges": graph.number_of_edges(),
            **overlap_summary(memberships),
            "seed": args.seed,
            "output": str(out_csv),
        }

    print(json.dumps(summary, indent=2, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
