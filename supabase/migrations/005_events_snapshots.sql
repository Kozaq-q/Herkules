-- ═══════════════════════════════════════════════════════════════
-- 005 — Dziennik zdarzeń (append-only) + auto-migawki stanu
-- Faza 3 (częściowo): audyt akcji sędziów + odzyskiwanie po błędzie/sabotażu.
-- Uruchomić w Supabase Studio → SQL Editor.
-- ═══════════════════════════════════════════════════════════════

-- ── 1. mss_events — dziennik zdarzeń (wspólny dla wszystkich konkurencji) ──
create table if not exists public.mss_events (
  id          bigint generated always as identity primary key,
  slot_id     text not null,
  user_email  text,
  user_name   text,
  role        text,
  action      text not null,
  details     jsonb,
  client_at   timestamptz,          -- czas zdarzenia wg urządzenia (kolejność wpisów = id)
  created_at  timestamptz not null default now()
);

create index if not exists mss_events_slot_idx on public.mss_events (slot_id, id desc);

alter table public.mss_events enable row level security;

-- INSERT: tylko aktywny sędzia. Brak polityk UPDATE/DELETE = append-only
-- (nawet sędzia nie może zatrzeć śladów; czyszczenie tylko przez service_role/Studio).
drop policy if exists mss_events_insert_judges on public.mss_events;
create policy mss_events_insert_judges on public.mss_events
  for insert to authenticated
  with check (public.is_active_judge());

-- SELECT: każdy zalogowany sędzia może przeglądać dziennik
drop policy if exists mss_events_select_auth on public.mss_events;
create policy mss_events_select_auth on public.mss_events
  for select to authenticated
  using (true);

-- ── 2. patrol_snapshots — migawki stanu (ring buffer 20 per slot) ──
create table if not exists public.patrol_snapshots (
  id          bigint generated always as identity primary key,
  slot_id     text not null,
  state_json  text not null,
  kind        text not null default 'auto',   -- 'auto' | 'manual' | 'pre-restore'
  meta        jsonb,                          -- {athletes, times, teams} — do listingu bez parsowania state_json
  created_by  text,
  created_at  timestamptz not null default now()
);

create index if not exists patrol_snapshots_slot_idx on public.patrol_snapshots (slot_id, id desc);

alter table public.patrol_snapshots enable row level security;

drop policy if exists patrol_snapshots_insert_judges on public.patrol_snapshots;
create policy patrol_snapshots_insert_judges on public.patrol_snapshots
  for insert to authenticated
  with check (public.is_active_judge());

drop policy if exists patrol_snapshots_select_auth on public.patrol_snapshots;
create policy patrol_snapshots_select_auth on public.patrol_snapshots
  for select to authenticated
  using (true);

-- Brak polityki DELETE dla klientów — przycinaniem zajmuje się trigger (security definer).

-- Ring buffer: po INSERT zostaw 20 najnowszych migawek danego slotu
create or replace function public.prune_patrol_snapshots()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.patrol_snapshots
  where slot_id = new.slot_id
    and id not in (
      select id from public.patrol_snapshots
      where slot_id = new.slot_id
      order by id desc
      limit 20
    );
  return new;
end;
$$;

drop trigger if exists patrol_snapshots_prune on public.patrol_snapshots;
create trigger patrol_snapshots_prune
  after insert on public.patrol_snapshots
  for each row execute function public.prune_patrol_snapshots();
