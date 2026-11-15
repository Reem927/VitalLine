import sqlite3

import pytest

from connectors.store import verify_chain


def _dispatch(store):
    return store.create_dispatch({"incident_type": "Test", "address": "1 Test St"})


def test_events_are_sequenced_and_chained(store):
    d = _dispatch(store)
    for i in range(3):
        store.append_event(d["id"], "note", f"n{i}", payload={"i": i})
    events = store.list_events(d["id"])
    assert [e["seq"] for e in events] == [1, 2, 3]
    assert events[0]["prev_hash"] is None
    assert events[1]["prev_hash"] == events[0]["hash"]
    assert verify_chain(events)
    assert [e["seq"] for e in store.list_events(d["id"], after_seq=2)] == [3]


def test_tampering_breaks_chain(store):
    d = _dispatch(store)
    store.append_event(d["id"], "note", "a")
    store.append_event(d["id"], "note", "b")
    events = store.list_events(d["id"])
    events[0]["summary"] = "edited"
    assert not verify_chain(events)


def test_log_is_append_only(store):
    d = _dispatch(store)
    store.append_event(d["id"], "note", "a")
    with pytest.raises(sqlite3.IntegrityError):
        store._db.execute("update dispatch_events set summary = 'x'")
    with pytest.raises(sqlite3.IntegrityError):
        store._db.execute("delete from dispatch_events")


def test_plan_versions(store):
    d = _dispatch(store)
    assert store.save_plan(d["id"], {"a": 1}) == 1
    assert store.save_plan(d["id"], {"a": 2}) == 2
    assert store.latest_plan(d["id"]) == {"a": 2, "version": 2}
