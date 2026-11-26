"""
Jaeger trace -> call tree -> per-request segment table, for muBench spans.

Copied from tracesim (github fpoltronieri/tracesim, tracesim/traces.py,
commit fb572c2): build_tree, call_chains, call_signature, segments and
load_level, unchanged. KubeTwin uses it to extract per-service processing
times from ragbench traces (train_ragbench.py).

    <svc>.self<i>   time the service spends on its own work between its i-th
                    and (i+1)-th downstream call (self0 = before the first
                    call, self<k> = after the last one)
    <a>-><b>.req    client span start -> server span start
    <a>-><b>.resp   server span end -> client span end
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
import pandas as pd


def _tag(span, key):
    for t in span.get("tags", ()):
        if t["key"] == key:
            return t["value"]
    return None


def _service(span, processes):
    # "productpage.validation" -> "productpage"; ingress keeps its full name
    return processes[span["processID"]]["serviceName"].split(".")[0]


@dataclass
class Call:
    target: str
    client_start: float  # all times in ms
    client_end: float
    node: "Node"


@dataclass
class Node:
    service: str
    start: float
    end: float
    calls: list[Call] = field(default_factory=list)
    caller_span: tuple | None = None  # root only: (start, end) of the caller's client span

    @property
    def duration(self):
        return self.end - self.start


def build_tree(trace, root_service: str) -> Node | None:
    """Server-side call tree rooted at the first server span of root_service."""
    procs = trace["processes"]
    spans = trace["spans"]
    children: dict[str, list] = {}
    for s in spans:
        for ref in s.get("references", ()):
            if ref.get("refType") == "CHILD_OF":
                children.setdefault(ref["spanID"], []).append(s)

    def server_node(server_span) -> Node:
        node = Node(
            service=_service(server_span, procs),
            start=server_span["startTime"] / 1e3,
            end=(server_span["startTime"] + server_span["duration"]) / 1e3,
        )
        for c in children.get(server_span["spanID"], ()):
            if _tag(c, "span.kind") != "client":
                continue
            servers = [
                g for g in children.get(c["spanID"], ())
                if _tag(g, "span.kind") == "server"
            ]
            if not servers:
                continue  # call with no server-side span (e.g. failed); skip
            child = server_node(servers[0])
            node.calls.append(Call(
                target=child.service,
                client_start=c["startTime"] / 1e3,
                client_end=(c["startTime"] + c["duration"]) / 1e3,
                node=child,
            ))
        node.calls.sort(key=lambda k: k.client_start)
        return node

    roots = [
        s for s in spans
        if _tag(s, "span.kind") == "server" and _service(s, procs) == root_service
    ]
    if not roots:
        return None
    root = min(roots, key=lambda s: s["startTime"])
    node = server_node(root)
    # the caller's client span (e.g. the ingress gateway's), if traced
    by_id = {s["spanID"]: s for s in spans}
    for ref in root.get("references", ()):
        parent = by_id.get(ref["spanID"])
        if ref.get("refType") == "CHILD_OF" and parent is not None \
                and _tag(parent, "span.kind") == "client":
            node.caller_span = (parent["startTime"] / 1e3,
                                (parent["startTime"] + parent["duration"]) / 1e3)
    return node


def call_chains(node: Node) -> list[int]:
    """Chain index of each call (in start order). Calls in one chain run one
    after the other; chains run in parallel (e.g. muBench call groups). A
    call joins the chain whose last call ended most recently before it
    started; if every chain is still busy, it opens a new one. Purely
    sequential services have every call in chain 0."""
    ends, out = [], []
    for c in node.calls:
        free = [k for k, e in enumerate(ends) if e <= c.client_start]
        if free:
            k = max(free, key=lambda k: ends[k])
        else:
            k = len(ends)
            ends.append(-np.inf)
        ends[k] = c.client_end
        out.append(k)
    return out


def call_signature(node: Node) -> tuple:
    """Hashable call-graph shape: (service, ((target, chain, sub), ...)),
    `chain` as in call_chains (0 for sequential calls)."""
    return (node.service, tuple((c.target, k, call_signature(c.node))
                                for c, k in zip(node.calls, call_chains(node))))


def segments(node: Node, out: dict | None = None) -> dict:
    """Flatten a tree into {segment_name: ms}.

    self0 runs from the node's start to its first call. Before call i
    (i >= 1), self{i} is the gap since the previous call of the same chain
    ended or, for the first call of a parallel chain, since the first call
    started (all chains are forked when self0 ends). The last self segment
    runs from the end of the last call to the node's end."""
    out = {} if out is None else out
    chains = call_chains(node)
    cursor = {0: node.start}
    fork = node.calls[0].client_start if node.calls else node.start
    for i, (c, k) in enumerate(zip(node.calls, chains)):
        out[f"{node.service}.self{i}"] = c.client_start - cursor.get(k, fork)
        edge = f"{node.service}->{c.target}"
        out[f"{edge}.req"] = c.node.start - c.client_start
        segments(c.node, out)
        out[f"{edge}.resp"] = c.client_end - c.node.end
        cursor[k] = c.client_end
    last = max((c.client_end for c in node.calls), default=node.start)
    out[f"{node.service}.self{len(node.calls)}"] = node.end - last
    return out


def load_level(path: Path, root_service: str):
    """Parse one trace file -> (DataFrame of segments + e2e + arrival, signatures)."""
    with open(path) as f:
        data = json.load(f)
    data = data["data"] if isinstance(data, dict) else data
    rows, sigs = [], []
    for trace in data:
        tree = build_tree(trace, root_service)
        if tree is None:
            continue
        sigs.append(call_signature(tree))
        row = segments(tree)
        if tree.caller_span is not None:
            # entry hop (ingress gateway -> root service), same convention
            # as the other hops
            row["ingress.req"] = tree.start - tree.caller_span[0]
            row["ingress.resp"] = tree.caller_span[1] - tree.end
        row["arrival_ms"] = tree.start
        row["e2e_ms"] = tree.duration
        rows.append(row)
    return pd.DataFrame(rows), sigs
