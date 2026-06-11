-- ═══════════════════════════════════════════════════════════════
-- 006 — Generyczne migawki stanu dla OSF i wieloboju (mss_snapshots)
-- Odpowiednik patrol_snapshots (005), ale wspólny dla wszystkich konkurencji
-- (kolumna comp_type: 'osf' | 'wieloboj'). mss_events z 005 jest już generyczne
-- i używane przez OSF/wielobój bez zmian.
-- Uruchomić w Supabase Studio → SQL Editor (po 005).
-- ═══════════════════════════════════════════════════════════════

create table if not exists public.mss_snapshots (
  id          bigint generated always as identity primary key,
  slot_id     text not null,                  -- osf_slot_<id> / czworId / 'panel_<id>'
  comp_type   text not null,                  -- 'osf' | 'wieloboj'
  state_json  text not null,
  kind        text not null default 'auto',   -- 'auto' | 'manual' | 'pre-restore'
  meta        jsonb,                          -- {athletes, times/results, teams} — do listingu bez parsowania
  created_by  text,
  created_at  timestamptz not null default now()
);

create index if not exists mss_snapshots_slot_idx on public.mss_snapshots (slot_id, id desc);

alter table public.mss_snapshots enable row level security;

-- INSERT: tylko aktywny sędzia
drop policy if exists mss_snapshots_insert_judges on public.mss_snapshots;
create policy mss_snapshots_insert_judges on public.mss_snapshots
  for insert to authenticated
  with check (public.is_active_judge());

-- SELECT: każdy zalogowany sędzia
drop policy if exists mss_snapshots_select_auth on public.mss_snapshots;
create policy mss_snapshots_select_auth on public.mss_snapshots
  for select to authenticated
  using (true);

-- Brak DELETE dla klientów — przycina trigger (security definer).

-- Ring buffer: po INSERT zostaw 20 najnowszych migawek danego slotu
create or replace function public.prune_mss_snapshots()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.mss_snapshots
  where slot_id = new.slot_id
    and id not in (
      select id from public.mss_snapshots
      where slot_id = new.slot_id
      order by id desc
      limit 20
    );
  return new;
end;
$$;

drop trigger if exists mss_snapshots_prune on public.mss_snapshots;
create trigger mss_snapshots_prune
  after insert on public.mss_snapshots
  for each row execute function public.prune_mss_snapshots();
