-- ═══════════════════════════════════════════════════════════════
-- MSS Auth — Migracja 004: Strukturalna izolacja per slot
-- ═══════════════════════════════════════════════════════════════
--
-- Cel: tablica wynikow publiczna (t.html, anon key) ma dostep TYLKO
-- do slotow z flaga publicShare = true. Bez tej flagi anon nie moze
-- nawet odczytac slot_json (RLS odrzuca).
--
-- Sedziowie (authenticated) widza WSZYSTKO niezaleznie od flagi.
--
-- Mechanizm:
-- - slot_json zawiera pole "publicShare": true/false (default false)
-- - Anon SELECT na herkules_slots filtrowany przez to pole
-- - Anon SELECT na patrol_state/osf_state/app_state wymaga ze
--   powiazany slot ma publicShare=true (subquery do herkules_slots)
--
-- BEZPIECZENSTWO:
-- - Po wykonaniu: anon ktory zna slot_id (lub krotki kod) i tak
--   nie zobaczy danych dopoki admin nie wlaczy publikacji
-- - Existing sloty maja publicShare=undefined w slot_json -> NIE
--   spelnia warunku 'true' -> niedostepne dla anon (default secure)
-- - Sedziowie zalogowani: widza wszystko (uzywaja start.html ktore
--   jest authenticated)
--
-- ROLLBACK na koncu pliku.
-- ═══════════════════════════════════════════════════════════════

-- ─── herkules_slots ────────────────────────────────────────────
DROP POLICY IF EXISTS "herkules_slots_read_all" ON public.herkules_slots;
DROP POLICY IF EXISTS "herkules_slots_read_authenticated" ON public.herkules_slots;
DROP POLICY IF EXISTS "herkules_slots_anon_public" ON public.herkules_slots;
DROP POLICY IF EXISTS "herkules_slots_auth_all" ON public.herkules_slots;

-- Anon: SELECT tylko slotow z publicShare=true
CREATE POLICY "herkules_slots_anon_public" ON public.herkules_slots
  FOR SELECT TO anon
  USING ((slot_json::jsonb->>'publicShare') = 'true');

-- Authenticated (sedziowie): SELECT wszystkich slotow
CREATE POLICY "herkules_slots_auth_all" ON public.herkules_slots
  FOR SELECT TO authenticated USING (true);

-- ─── patrol_state ──────────────────────────────────────────────
DROP POLICY IF EXISTS "patrol_state_read_all" ON public.patrol_state;
DROP POLICY IF EXISTS "patrol_state_auth_all" ON public.patrol_state;
DROP POLICY IF EXISTS "patrol_state_anon_public" ON public.patrol_state;

-- Anon: SELECT tylko dla slotow z publicShare=true
CREATE POLICY "patrol_state_anon_public" ON public.patrol_state
  FOR SELECT TO anon
  USING (
    EXISTS (
      SELECT 1 FROM public.herkules_slots hs
      WHERE hs.slot_id = patrol_state.slot_id
        AND (hs.slot_json::jsonb->>'publicShare') = 'true'
    )
  );

-- Authenticated: SELECT wszystko
CREATE POLICY "patrol_state_auth_all" ON public.patrol_state
  FOR SELECT TO authenticated USING (true);

-- ─── osf_state ─────────────────────────────────────────────────
DROP POLICY IF EXISTS "osf_state_read_all" ON public.osf_state;
DROP POLICY IF EXISTS "osf_state_auth_all" ON public.osf_state;
DROP POLICY IF EXISTS "osf_state_anon_public" ON public.osf_state;

-- Anon: osf_state.slot_id = 'osf_slot_' + herkules slot_id
CREATE POLICY "osf_state_anon_public" ON public.osf_state
  FOR SELECT TO anon
  USING (
    EXISTS (
      SELECT 1 FROM public.herkules_slots hs
      WHERE 'osf_slot_' || hs.slot_id = osf_state.slot_id
        AND (hs.slot_json::jsonb->>'publicShare') = 'true'
    )
  );

CREATE POLICY "osf_state_auth_all" ON public.osf_state
  FOR SELECT TO authenticated USING (true);

-- ─── app_state (wieloboj) ──────────────────────────────────────
DROP POLICY IF EXISTS "app_state_read_all" ON public.app_state;
DROP POLICY IF EXISTS "app_state_auth_all" ON public.app_state;
DROP POLICY IF EXISTS "app_state_anon_public" ON public.app_state;

-- Anon: app_state.slot_id = 'panel_' + herkules slot_id
CREATE POLICY "app_state_anon_public" ON public.app_state
  FOR SELECT TO anon
  USING (
    EXISTS (
      SELECT 1 FROM public.herkules_slots hs
      WHERE 'panel_' || hs.slot_id = app_state.slot_id
        AND (hs.slot_json::jsonb->>'publicShare') = 'true'
    )
  );

CREATE POLICY "app_state_auth_all" ON public.app_state
  FOR SELECT TO authenticated USING (true);

-- ═══════════════════════════════════════════════════════════════
-- WERYFIKACJA:
--   SELECT tablename, policyname, roles, cmd FROM pg_policies
--   WHERE tablename IN ('herkules_slots','patrol_state','osf_state','app_state')
--   ORDER BY tablename, policyname;
--
-- Powinno byc 2 polityki SELECT per tabela: jedna dla anon (z
-- warunkiem publicShare), druga dla authenticated (bez warunku).
-- Plus zachowane polityki WRITE (FOR ALL TO authenticated USING ...
-- is_active_judge()).
-- ═══════════════════════════════════════════════════════════════

-- ─── ROLLBACK ──────────────────────────────────────────────────
-- W razie problemu, przywroc otwarte SELECT dla wszystkich:
--
-- DROP POLICY IF EXISTS "herkules_slots_anon_public" ON public.herkules_slots;
-- DROP POLICY IF EXISTS "herkules_slots_auth_all" ON public.herkules_slots;
-- CREATE POLICY "herkules_slots_read_all" ON public.herkules_slots FOR SELECT TO anon, authenticated USING (true);
--
-- DROP POLICY IF EXISTS "patrol_state_anon_public" ON public.patrol_state;
-- DROP POLICY IF EXISTS "patrol_state_auth_all" ON public.patrol_state;
-- CREATE POLICY "patrol_state_read_all" ON public.patrol_state FOR SELECT TO anon, authenticated USING (true);
--
-- DROP POLICY IF EXISTS "osf_state_anon_public" ON public.osf_state;
-- DROP POLICY IF EXISTS "osf_state_auth_all" ON public.osf_state;
-- CREATE POLICY "osf_state_read_all" ON public.osf_state FOR SELECT TO anon, authenticated USING (true);
--
-- DROP POLICY IF EXISTS "app_state_anon_public" ON public.app_state;
-- DROP POLICY IF EXISTS "app_state_auth_all" ON public.app_state;
-- CREATE POLICY "app_state_read_all" ON public.app_state FOR SELECT TO anon, authenticated USING (true);
