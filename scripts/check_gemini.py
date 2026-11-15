"""Check that the Gemini key in backend/.env works through LangChain.

Run from the repo root:
    backend/.venv/bin/python scripts/check_gemini.py

Prints the model used and its reply. Never prints the key.
"""

import os
import sys
from pathlib import Path

from dotenv import load_dotenv

ENV_PATH = Path(__file__).resolve().parent.parent / "backend" / ".env"
DEFAULT_MODEL = "gemini-4-hydrogen"


def main() -> int:
    load_dotenv(ENV_PATH)
    if not (os.getenv("GOOGLE_API_KEY") or os.getenv("GEMINI_API_KEY")):
        print(f"No GOOGLE_API_KEY or GEMINI_API_KEY in {ENV_PATH}")
        print("Create one at https://aistudio.google.com/apikey and paste it there.")
        return 1

    from langchain_google_genai import ChatGoogleGenerativeAI

    model = os.getenv("MODEL_NAME") or DEFAULT_MODEL
    llm = ChatGoogleGenerativeAI(model=model)
    reply = llm.invoke("Reply with exactly: VitalLine backend connected.")
    print(f"model: {model}")
    print(f"reply: {reply.text}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
