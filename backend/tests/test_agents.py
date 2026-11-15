"""Exercise the real deepagents planner + subagents with a scripted model (no API key)."""

from typing import Any

from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.messages import AIMessage, BaseMessage, SystemMessage, ToolMessage
from langchain_core.outputs import ChatGeneration, ChatResult

from agents import planner as planner_mod
from agents.run import STEP_ORDER
from app.synthetic import make_dispatch

SUBAGENT_ORDER = ["location-resolver", "outdoor-route", "access-checker", "indoor-planner",
                  "verifier", "briefer"]


class ScriptedModel(BaseChatModel):
    """Planner: one `task` call per subagent, in order. Subagent: call its only tool, then reply."""

    tool_names: list[str] = []  # noqa: RUF012 - pydantic field, copied per bind_tools

    @property
    def _llm_type(self) -> str:
        return "scripted"

    def bind_tools(self, tools: Any, **kwargs: Any):
        names = []
        for t in tools:
            names.append(t["name"] if isinstance(t, dict) else getattr(t, "name", None)
                         or t.get("function", {}).get("name"))
        return self.model_copy(update={"tool_names": names})

    def _generate(self, messages: list[BaseMessage], stop=None, run_manager=None, **kw):
        system = next((m.content for m in messages if isinstance(m, SystemMessage)), "")
        system = system if isinstance(system, str) else str(system)
        tool_results = [m for m in messages if isinstance(m, ToolMessage)]
        if "access planner" in system:
            if len(tool_results) < len(SUBAGENT_ORDER):
                name = SUBAGENT_ORDER[len(tool_results)]
                msg = AIMessage(content="", tool_calls=[{
                    "name": "task", "id": f"call_{name}",
                    "args": {"description": f"Do the {name} step.", "subagent_type": name}}])
            else:
                msg = AIMessage(content="Plan complete")
        else:
            names = set(self.tool_names)
            called = [m.name for m in tool_results]
            if "submit_brief" in names:          # briefer: facts, then a brief
                if "get_plan_facts" not in called:
                    call = {"name": "get_plan_facts", "id": "f1", "args": {}}
                elif "submit_brief" not in called:
                    call = {"name": "submit_brief", "id": "b1", "args": {"lines": [
                        "Park at Garage A.", "Elevator 2 with stretcher.",
                        "Door to patient 2.6–3.8 min."]}}
                else:
                    call = None
            else:
                # deepagents adds its file tools first; the subagent's own tool is last.
                call = None if tool_results else {
                    "name": self.tool_names[-1], "id": "c1", "args": {}}
            msg = AIMessage(content="", tool_calls=[call]) if call else AIMessage(content="done")
        return ChatResult(generations=[ChatGeneration(message=msg)])


def test_planner_agents_fill_every_step(store, monkeypatch):
    d = store.create_dispatch(make_dispatch("houston-demo", {"lat": 29.757, "lon": -95.364}))
    monkeypatch.setattr(planner_mod, "get_settings", lambda: _settings(use_agents=True))
    real_build = planner_mod.build_planner
    monkeypatch.setattr(planner_mod, "_run_agents", _run_with(real_build, ScriptedModel()))

    job = planner_mod.start_job(store, d["id"], elevator_out=False, background=False)
    assert job.status == "done", job.error
    plan = job.plan

    assert plan["meta"]["mode"] == "agents"
    assert plan["meta"]["filled_by_rules"] == []      # every step came through a subagent
    assert plan["meta"]["brief_source"] == "agent"
    assert plan["brief"][0] == "Park at Garage A."
    assert plan["time"] == {"min_seconds": 157, "max_seconds": 228}
    steps = [e for e in store.list_events(d["id"]) if e["type"] == "plan_step"]
    done = [e for e in steps if e["payload"]["status"] == "done"]
    assert [e["payload"]["step"] for e in done] == STEP_ORDER
    assert {e["actor"] for e in done} == {f"agent:{n}" for n in SUBAGENT_ORDER}


def test_agent_failure_falls_back_to_rules(store, monkeypatch):
    d = store.create_dispatch(make_dispatch("houston-demo", None))
    monkeypatch.setattr(planner_mod, "get_settings", lambda: _settings(use_agents=True))

    def boom(run):
        raise RuntimeError("model down")

    monkeypatch.setattr(planner_mod, "_run_agents", boom)
    job = planner_mod.start_job(store, d["id"], elevator_out=False, background=False)
    assert job.plan["meta"]["mode"] == "deterministic_fallback"
    assert job.plan["meta"]["filled_by_rules"] == STEP_ORDER
    assert any(e["type"] == "agent_error" for e in store.list_events(d["id"]))


# helpers ---------------------------------------------------------------------


def _settings(use_agents: bool):
    class S:
        pass

    s = S()
    s.use_agents = use_agents
    s.model_name = "scripted"
    return s


def _run_with(build, model):
    def run(plan_run):
        build(model).invoke(
            {"messages": [{"role": "user", "content": "plan"}]},
            config={"configurable": {"run_id": plan_run.run_id}, "recursion_limit": 100})
    return run


def test_brief_rejects_invented_numbers(store):
    from agents.run import PlanRun
    from tools.building import load_building

    d = store.create_dispatch(make_dispatch("houston-demo", None))
    run = PlanRun(store=store, dispatch=d, building=load_building())
    for step in ("location", "outdoor", "access", "indoor"):
        run.run_step(step)
    assert not run.submit_brief(["Door to patient 2–3 min."])["ok"]
    assert run.submit_brief(["Door to patient 2.6–3.8 min."])["ok"]
