-- ═══════════════════════════════════════════════════════════════
-- 007 — Niezalezny projektor (projectorShare) odpiety od tablicy uczestnikow
-- ═══════════════════════════════════════════════════════════════
--
-- Cel: ekran/projektor na sali (patrol-projektor.html, osf-projektor.html,
-- projektor.html — anon key) ma dzialac NIEZALEZNIE od publicznej tablicy
-- uczestnikow (t.html). Dwa osobne przelaczniki:
--
--   slot_json.publicShare   = true -> t.html (telefony uczestnikow) widzi wyniki
--   slot_json.projectorShare = true -> projektor na sali widzi wyniki
--
-- Mechanizm: anon SELECT na *_state dozwolony gdy powiazany slot ma
-- publicShare=true LUB projectorShare=true. herkules_slots NADAL gated
-- tylko publicShare (wiec wlaczenie samego projectorShare NIE odslania
-- danych w t.html — t.html resolwuje slot przez herkules_slots).
--
-- Domyslnie projectorShare=undefined -> NIE spelnia 'true' -> bezpieczne.
-- Uruchomic w Supabase Studio -> SQL Editor (po 004).
-- ═══════════════════════════════════════════════════════════════

-- ─── patrol_state ──────────────────────────────────────────────
DROP POLICY IF EXISTS "patrol_state_anon_public" ON public.patrol_state;
CREATE POLICY "patrol_state_anon_public" ON public.patrol_state
  FOR SELECT TO anon
  USING (
    EXISTS (
      SELECT 1 FROM public.herkules_slots hs
      WHERE hs.slot_id = patrol_state.slot_id
        AND ( (hs.slot_json::jsonb->>'publicShare') = 'true'
           OR (hs.slot_json::jsonb->>'projectorShare') = 'true' )
    )
  );

-- ─── osf_state ─────────────────────────────────────────────────
DROP POLICY IF EXISTS "osf_state_anon_public" ON public.osf_state;
CREATE POLICY "osf_state_anon_public" ON public.osf_state
  FOR SELECT TO anon
  USING (
    EXISTS (
      SELECT 1 FROM public.herkules_slots hs
      WHERE 'osf_slot_' || hs.slot_id = osf_state.slot_id
        AND ( (hs.slot_json::jsonb->>'publicShare') = 'true'
           OR (hs.slot_json::jsonb->>'projectorShare') = 'true' )
    )
  );

-- ─── app_state (wieloboj) ──────────────────────────────────────
-- UWAGA: app_state.slot_id = czworId (mapowany), niekoniecznie 'panel_'+slot.
-- Zachowujemy istniejacy wzorzec 'panel_' z 004 dla zgodnosci.
DROP POLICY IF EXISTS "app_state_anon_public" ON public.app_state;
CREATE POLICY "app_state_anon_public" ON public.app_state
  FOR SELECT TO anon
  USING (
    EXISTS (
      SELECT 1 FROM public.herkules_slots hs
      WHERE 'panel_' || hs.slot_id = app_state.slot_id
        AND ( (hs.slot_json::jsonb->>'publicShare') = 'true'
           OR (hs.slot_json::jsonb->>'projectorShare') = 'true' )
    )
  );

-- ═══════════════════════════════════════════════════════════════
-- WERYFIKACJA: anon czyta *_state gdy publicShare LUB projectorShare = true.
-- t.html (herkules_slots) dalej tylko przy publicShare = true.
-- ROLLBACK: przywroc polityki z 004 (warunek tylko publicShare).
-- ═══════════════════════════════════════════════════════════════
