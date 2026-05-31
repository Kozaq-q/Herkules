-- ═══════════════════════════════════════════════════════════════
-- MSS Auth — Migracja 003: Zaostrzenie RLS na tabelach stanu
-- ═══════════════════════════════════════════════════════════════
--
-- ⚠⚠⚠ NIE URUCHAMIAJ DOPÓKI NIE WDROŻYSZ FRONTENDU Z LOGINEM ⚠⚠⚠
--
-- Po wykonaniu tej migracji:
--   • Anon (bez logowania) — może tylko CZYTAĆ
--   • Zalogowany sędzia (w mss_users z active=true) — pełny dostęp
--   • Zalogowany ale BEZ rekordu w mss_users — może tylko czytać
--
-- Skutki uboczne:
--   • Wszystkie publiczne strony (projektor, speaker, viewer) DZIAŁAJĄ
--     dalej (tylko SELECT + realtime)
--   • Panele sędziowskie (start, index, osf, patrol, patrol-start)
--     przestają zapisywać dopóki user się nie zaloguje
--
-- Migracja jest IDEMPOTENTNA — można uruchomić kilka razy bez szkody.
-- Można też odwrócić: ROLLBACK na końcu pliku (zakomentowane).
-- ═══════════════════════════════════════════════════════════════

-- ─── herkules_slots ────────────────────────────────────────────
ALTER TABLE public.herkules_slots ENABLE ROW LEVEL SECURITY;

-- Drop wszystkich starych polityk (różne nazwy które mogły być użyte)
DROP POLICY IF EXISTS "anon full access" ON public.herkules_slots;
DROP POLICY IF EXISTS "Enable all access for anon" ON public.herkules_slots;
DROP POLICY IF EXISTS "allow all anon" ON public.herkules_slots;
DROP POLICY IF EXISTS "Enable read access for all users" ON public.herkules_slots;
DROP POLICY IF EXISTS "herkules_slots_anon_all" ON public.herkules_slots;
-- Wcześniej zdefiniowane przez tę migrację (dla idempotencji):
DROP POLICY IF EXISTS "herkules_slots_read_all" ON public.herkules_slots;
DROP POLICY IF EXISTS "herkules_slots_write_judges" ON public.herkules_slots;

CREATE POLICY "herkules_slots_read_all" ON public.herkules_slots
  FOR SELECT
  TO anon, authenticated
  USING (true);

CREATE POLICY "herkules_slots_write_judges" ON public.herkules_slots
  FOR ALL
  TO authenticated
  USING (public.is_active_judge())
  WITH CHECK (public.is_active_judge());

-- ─── app_state (wielobój) ──────────────────────────────────────
ALTER TABLE public.app_state ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon full access" ON public.app_state;
DROP POLICY IF EXISTS "Enable all access for anon" ON public.app_state;
DROP POLICY IF EXISTS "allow all anon" ON public.app_state;
DROP POLICY IF EXISTS "Enable read access for all users" ON public.app_state;
DROP POLICY IF EXISTS "app_state_anon_all" ON public.app_state;
DROP POLICY IF EXISTS "app_state_read_all" ON public.app_state;
DROP POLICY IF EXISTS "app_state_write_judges" ON public.app_state;

CREATE POLICY "app_state_read_all" ON public.app_state
  FOR SELECT
  TO anon, authenticated
  USING (true);

CREATE POLICY "app_state_write_judges" ON public.app_state
  FOR ALL
  TO authenticated
  USING (public.is_active_judge())
  WITH CHECK (public.is_active_judge());

-- ─── osf_state ─────────────────────────────────────────────────
ALTER TABLE public.osf_state ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon full access" ON public.osf_state;
DROP POLICY IF EXISTS "Enable all access for anon" ON public.osf_state;
DROP POLICY IF EXISTS "allow all anon" ON public.osf_state;
DROP POLICY IF EXISTS "Enable read access for all users" ON public.osf_state;
DROP POLICY IF EXISTS "osf_state_anon_all" ON public.osf_state;
DROP POLICY IF EXISTS "osf_state_read_all" ON public.osf_state;
DROP POLICY IF EXISTS "osf_state_write_judges" ON public.osf_state;

CREATE POLICY "osf_state_read_all" ON public.osf_state
  FOR SELECT
  TO anon, authenticated
  USING (true);

CREATE POLICY "osf_state_write_judges" ON public.osf_state
  FOR ALL
  TO authenticated
  USING (public.is_active_judge())
  WITH CHECK (public.is_active_judge());

-- ─── patrol_state ──────────────────────────────────────────────
ALTER TABLE public.patrol_state ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon full access" ON public.patrol_state;
DROP POLICY IF EXISTS "Enable all access for anon" ON public.patrol_state;
DROP POLICY IF EXISTS "allow all anon" ON public.patrol_state;
DROP POLICY IF EXISTS "Enable read access for all users" ON public.patrol_state;
DROP POLICY IF EXISTS "patrol_state_anon_all" ON public.patrol_state;
DROP POLICY IF EXISTS "patrol_state_read_all" ON public.patrol_state;
DROP POLICY IF EXISTS "patrol_state_write_judges" ON public.patrol_state;

CREATE POLICY "patrol_state_read_all" ON public.patrol_state
  FOR SELECT
  TO anon, authenticated
  USING (true);

CREATE POLICY "patrol_state_write_judges" ON public.patrol_state
  FOR ALL
  TO authenticated
  USING (public.is_active_judge())
  WITH CHECK (public.is_active_judge());

-- ═══════════════════════════════════════════════════════════════
-- Po wykonaniu sprawdź w SQL Editor jako anon (bez logowania):
--   SELECT slot_id FROM patrol_state LIMIT 1;           -- ✓ działa
--   UPDATE patrol_state SET updated_at = now();         -- ✗ blokada
--
-- Sprawdź też z zalogowanym sędzią (test w przeglądarce):
--   Otwórz patrol.html, zaloguj się → save powinien działać
--   Wyloguj → save nie działa (UI powinien pokazać banner)
-- ═══════════════════════════════════════════════════════════════

-- ─── ROLLBACK (w razie problemów) ──────────────────────────────
-- Odkomentuj i uruchom żeby przywrócić anon-full-access:
--
-- DROP POLICY IF EXISTS "herkules_slots_read_all" ON public.herkules_slots;
-- DROP POLICY IF EXISTS "herkules_slots_write_judges" ON public.herkules_slots;
-- CREATE POLICY "anon full access" ON public.herkules_slots FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
--
-- DROP POLICY IF EXISTS "app_state_read_all" ON public.app_state;
-- DROP POLICY IF EXISTS "app_state_write_judges" ON public.app_state;
-- CREATE POLICY "anon full access" ON public.app_state FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
--
-- DROP POLICY IF EXISTS "osf_state_read_all" ON public.osf_state;
-- DROP POLICY IF EXISTS "osf_state_write_judges" ON public.osf_state;
-- CREATE POLICY "anon full access" ON public.osf_state FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
--
-- DROP POLICY IF EXISTS "patrol_state_read_all" ON public.patrol_state;
-- DROP POLICY IF EXISTS "patrol_state_write_judges" ON public.patrol_state;
-- CREATE POLICY "anon full access" ON public.patrol_state FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
