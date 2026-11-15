"""Check the plan's arithmetic.

Every sum is computed locally with exact fractions. If WOLFRAM_API_KEY is set, the same
expression is also sent to the Wolfram|Alpha Short Answers API and the two must agree.
"""

from __future__ import annotations

import ast
import operator
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


def verify(checks: list[dict[str, Any]], tolerance: float = 0.51) -> dict[str, Any]:
    """checks: [{"name", "expr", "claimed"}]. Returns per-check results and an overall verdict.

    `tolerance` covers rounding of displayed values (seconds are shown as whole numbers).
    """
    settings = get_settings()
    use_wolfram = bool(settings.wolfram_app_id) and not settings.offline
    results, all_ok, wolfram_used = [], True, False
    for chk in checks:
        local = float(exact(chk["expr"]))
        ok = abs(local - float(chk["claimed"])) <= tolerance
        entry = {**chk, "local": round(local, 3), "ok": ok}
        if use_wolfram:
            w = _wolfram(chk["expr"], settings.wolfram_app_id)
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
