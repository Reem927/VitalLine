"""Check the plan's arithmetic.

Every sum is computed locally with exact fractions, then recomputed by Wolfram and the two
must agree. With WOLFRAM_API_KEY set we use the Wolfram|Alpha Short Answers API; without it,
all checks go to the Wolfram Cloud MCP server in one batched call (no key needed).
"""

from __future__ import annotations

import ast
import asyncio
import concurrent.futures
import operator
import re
from fractions import Fraction
from typing import Any

import httpx

from app.settings import get_settings
from tools.http import client

WOLFRAM_URL = "https://api.wolframalpha.com/v1/result"

_OPS = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul,
        ast.Div: operator.truediv}


def exact(expr: str) -> Fraction:
    """Evaluate + - * / on numbers only. Anything else is rejected."""
    def ev(node: ast.AST) -> Fraction:
        if isinstance(node, ast.Expression):
            return ev(node.body)
        if isinstance(node, ast.Constant) and isinstance(node.value, int | float):
            return Fraction(str(node.value))
        if isinstance(node, ast.BinOp) and type(node.op) in _OPS:
            return _OPS[type(node.op)](ev(node.left), ev(node.right))
        raise ValueError(f"unsupported expression: {expr}")
    return ev(ast.parse(expr, mode="eval"))


def _wolfram(expr: str, app_id: str) -> float | None:
    try:
        with client() as c:
            resp = c.get(WOLFRAM_URL, params={"appid": app_id, "i": expr})
        if resp.status_code != 200:
            return None
        return float(resp.text.split()[0].replace(",", ""))
    except (httpx.HTTPError, ValueError, IndexError):
        return None


def _run(coro):
    """Run a coroutine from sync code, even if this thread already has an event loop."""
    try:
        asyncio.get_running_loop()
    except RuntimeError:
        return asyncio.run(coro)
    with concurrent.futures.ThreadPoolExecutor(1) as pool:
        return pool.submit(asyncio.run, coro).result()


def _wolfram_mcp_batch(exprs: list[str]) -> list[float | None]:
    """All expressions in one Wolfram Language call: N[{e1, e2, ...}]."""
    from connectors import wolfram as wolfram_mcp

    try:
        out = _run(wolfram_mcp.evaluate("N[{" + ", ".join(exprs) + "}]"))
    except Exception:  # noqa: BLE001 - Wolfram is optional; the local check still runs
        return [None] * len(exprs)
    body = re.split(r"Out\[\d+\]=", out)[-1]
    nums = re.findall(r"-?\d+(?:\.\d+)?(?:\*\^-?\d+)?", body)
    if len(nums) != len(exprs):
        return [None] * len(exprs)
    return [float(n.replace("*^", "e")) for n in nums]


def verify(checks: list[dict[str, Any]], tolerance: float = 0.51) -> dict[str, Any]:
    """checks: [{"name", "expr", "claimed"}]. Returns per-check results and an overall verdict.

    `tolerance` covers rounding of displayed values (seconds are shown as whole numbers).
    """
    settings = get_settings()
    use_alpha = bool(settings.wolfram_app_id) and not settings.offline
    batch = (_wolfram_mcp_batch([c["expr"] for c in checks])
             if not use_alpha and not settings.offline else [None] * len(checks))
    results, all_ok, wolfram_used = [], True, False
    for chk, mcp_value in zip(checks, batch, strict=True):
        local = float(exact(chk["expr"]))
        ok = abs(local - float(chk["claimed"])) <= tolerance
        entry = {**chk, "local": round(local, 3), "ok": ok}
        w = _wolfram(chk["expr"], settings.wolfram_app_id) if use_alpha else mcp_value
        if w is not None or use_alpha:
            entry["wolfram"] = w
            if w is not None:
                wolfram_used = True
                entry["ok"] = ok = ok and abs(w - local) <= 0.01
        all_ok = all_ok and ok
        results.append(entry)
    return {
        "verified": all_ok,
        "verified_by": "wolfram" if wolfram_used else "local_exact_arithmetic",
        "checks": results,
    }
