-- VitalLine tables for Supabase. Run once in the SQL editor (or as a migration).
-- The backend writes with the service key; the iOS app never talks to these tables directly.

create table if not exists dispatches (
  id            uuid primary key default gen_random_uuid(),
  created_at    timestamptz not null default now(),
  incident_type text not null,
  address       text not null,
  floor         int,
  unit          text,
  building_id   text,
  location      jsonb,          -- {"lat":..,"lon":..}
  geocode       jsonb,          -- request URL + matched address from the Census geocoder
  rig_location  jsonb,
  source        jsonb,          -- {"kind":"synthetic"} or {"kind":"seattle_fire_911","row_id":..}
  responder     text,
  synthetic     boolean not null default true,
  status        text not null default 'open',
  saved         boolean
);

create table if not exists dispatch_events (
  id           bigint generated always as identity primary key,
  dispatch_id  uuid not null references dispatches(id),
  seq          int not null,
  occurred_at  timestamptz not null,
  recorded_at  timestamptz not null default now(),
  actor        text not null,
  type         text not null,
  summary      text not null,
  payload      jsonb not null default '{}',
  trace_id     text,
  prev_hash    text,
  hash         text not null,
  unique (dispatch_id, seq)
);

create table if not exists plans (
  dispatch_id uuid not null references dispatches(id),
  version     int not null,
  created_at  timestamptz not null default now(),
  plan        jsonb not null,
  primary key (dispatch_id, version)
);

-- Append-only: block updates and deletes on the event log.
create or replace function dispatch_events_append_only() returns trigger
language plpgsql as $$
begin
  raise exception 'dispatch_events is append-only';
end $$;

drop trigger if exists dispatch_events_no_change on dispatch_events;
create trigger dispatch_events_no_change
  before update or delete on dispatch_events
  for each row execute function dispatch_events_append_only();

-- Only the service role (backend) reads and writes.
alter table dispatches enable row level security;
alter table dispatch_events enable row level security;
alter table plans enable row level security;
