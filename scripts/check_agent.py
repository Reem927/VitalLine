"""Smoke test for the agent stack: deepagents + Gemini + a subagent + Wolfram MCP + LangSmith.

Run from the repo root:
    backend/.venv/bin/python scripts/check_agent.py

Uses made-up test segment lengths only. No sponsor data. Never prints keys.
"""

import asyncio
import os
import sys
from pathlib import Path

from dotenv import load_dotenv

ENV_PATH = Path(__file__).resolve().parent.parent / "backend" / ".env"
DEFAULT_MODEL = "gemini-4-hydrogen"
WOLFRAM_MCP_URL = "https://agenttools.wolfram.com/mcp"

TEST_SEGMENTS_M = [12.5, 30.0, 8.2, 41.3]  # test values, not a real building


def sum_segments() -> dict:
    """Return the test path segments in metres and their total, computed in Python."""
    return {"segments_m": TEST_SEGMENTS_M, "total_m": sum(TEST_SEGMENTS_M)}


async def main() -> int:
    load_dotenv(ENV_PATH)
    if not (os.getenv("GOOGLE_API_KEY") or os.getenv("GEMINI_API_KEY")):
        print(f"No Gemini key in {ENV_PATH}")
        return 1

    from deepagents import create_deep_agent
    from langchain_google_genai import ChatGoogleGenerativeAI
    from langchain_mcp_adapters.client import MultiServerMCPClient

    model_name = os.getenv("MODEL_NAME") or DEFAULT_MODEL
    model = ChatGoogleGenerativeAI(model=model_name)

    mcp = MultiServerMCPClient(
        {"wolfram": {"transport": "streamable_http", "url": WOLFRAM_MCP_URL}}
    )
    wolfram_tools = [t for t in await mcp.get_tools() if t.name == "WolframLanguageEvaluator"]

    verifier = {
        "name": "verifier",
        "description": "Recomputes a number with Wolfram and reports whether it matches.",
        "system_prompt": (
            "Recompute the requested total with the WolframLanguageEvaluator tool. "
            "Report the Wolfram result exactly as returned and say whether it matches "
            "the given value. Never state a number the tool did not return."
        ),
        "tools": wolfram_tools,
    }

    agent = create_deep_agent(
        model=model,
        tools=[sum_segments],
        subagents=[verifier],
        system_prompt=(
            "You are a smoke test. Call sum_segments, then delegate to the verifier "
            "subagent to recompute the total with Wolfram. Answer in two lines: the "
            "Python total and the Wolfram total, each copied from a tool result, and "
            "MATCH or MISMATCH. Never state a number a tool did not return."
        ),
        name="vitalline-smoke-test",
    )

    result = await agent.ainvoke(
        {"messages": [{"role": "user", "content": "Run the smoke test."}]}
    )
    print(f"model: {model_name}")
    print(f"tracing: {os.getenv('LANGSMITH_TRACING') == 'true'}")
    print("answer:")
    print(result["messages"][-1].text)
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
