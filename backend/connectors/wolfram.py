"""Wolfram verification through the Wolfram Cloud MCP server.

The agent gets these as LangChain tools; deterministic code calls `evaluate` directly.
Every result is cached, so a slow or limited Wolfram does not break a replay.
"""

import re

from langchain_mcp_adapters.client import MultiServerMCPClient

from app.config import env
from connectors import cache

MCP_URL = "https://agenttools.wolfram.com/mcp"


def _client() -> MultiServerMCPClient:
    # The public endpoint answers without a key. WOLFRAM_API_KEY is unused until Wolfram
    # documents how a key is sent.
    return MultiServerMCPClient({"wolfram": {"transport": "streamable_http", "url": env("WOLFRAM_MCP_URL", MCP_URL)}})


async def tools(names: tuple[str, ...] = ("WolframLanguageEvaluator",)) -> list:
    """Wolfram MCP tools as LangChain tools, for agents."""
    return [t for t in await _client().get_tools() if t.name in names]


def _text(result) -> str:
    if isinstance(result, str):
        return result
    if isinstance(result, list):
        return "".join(part.get("text", "") if isinstance(part, dict) else str(part) for part in result)
    return str(result)


async def evaluate(code: str) -> str:
    """Evaluate Wolfram Language code and return the raw text output, e.g. 'Out[1]= 92.'."""
    key = cache.key_for(code)
    if (hit := cache.get("wolfram", key)) is not None:
        return hit
    (evaluator,) = await tools()
    result = await evaluator.ainvoke({"code": code})
    return cache.put("wolfram", key, _text(result))


def number(output: str) -> float | None:
    """The first number in a Wolfram output line, or None."""
    body = output.split("=", 1)[-1]
    match = re.search(r"-?\d+(?:\.\d+)?(?:\*\^-?\d+)?", body)
    if not match:
        return None
    return float(match.group().replace("*^", "e"))
