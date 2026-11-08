from pathlib import Path
from typing import Optional

import networkx as nx
import pandas as pd


def load_adjacency(path: str | Path) -> pd.DataFrame:
    """Load a square labeled adjacency matrix from Excel or CSV."""
    path = Path(path)
    suffix = path.suffix.lower()
    if suffix in {".xlsx", ".xls"}:
        df = pd.read_excel(path, index_col=0)
    elif suffix in {".csv", ".txt"}:
        df = pd.read_csv(path, index_col=0)
    else:
        raise ValueError(f"Unsupported adjacency format: {suffix}")

    if df.shape[0] != df.shape[1]:
        raise ValueError(f"Adjacency matrix must be square, got {df.shape}")

    # Normalize labels to strings only when necessary; preserve original labels otherwise.
    if not df.index.equals(df.columns):
        if set(map(str, df.index)) == set(map(str, df.columns)):
            col_lookup = {str(c): c for c in df.columns}
            ordered_cols = [col_lookup[str(i)] for i in df.index]
            df = df.loc[:, ordered_cols]
            df.columns = df.index
        else:
            raise ValueError("Adjacency row and column labels do not describe the same node set")
    return df


def graph_from_adjacency(
    df: pd.DataFrame,
    *,
    binarize: bool = True,
    threshold: Optional[float] = None,
    use_weights: bool = False,
) -> nx.Graph:
    """Create a simple undirected graph from an adjacency matrix."""
    work = df.astype(float).copy()
    if threshold is not None:
        work = (work >= threshold).astype(float)
    elif binarize:
        work = (work > 0).astype(float)
    else:
        work = work.where(work > 0, 0.0)

    if not work.equals(work.T):
        work = (work + work.T) / 2.0

    graph = nx.from_pandas_adjacency(work)
    graph.remove_edges_from(nx.selfloop_edges(graph))

    if not use_weights:
        for u, v in graph.edges():
            graph[u][v]["weight"] = 1.0
    return graph
