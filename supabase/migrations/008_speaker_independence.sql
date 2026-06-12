-- ═══════════════════════════════════════════════════════════════
-- 008 — Speaker niezalezny od publicShare (czytany przez wlasne cfg.speakerEnabled)
-- ═══════════════════════════════════════════════════════════════
--
-- Cel: aplikacja speakera (patrol-speaker.html, osf-speaker.html — anon key +
-- link z kluczem) ma dzialac NIEZALEZNIE od publicznej tablicy uczestnikow
-- (publicShare) oraz od projektora (projectorShare). Wczesniej speaker czytal
-- *_state tylko gdy publicShare LUB projectorShare = true -> wylaczenie
-- "Wynikow online" gasilo speakera.
--
-- Mechanizm: anon SELECT na *_state dozwolony dodatkowo gdy SAM REKORD ma
-- wlaczonego speakera (state_json.cfg.speakerEnabled = true). To pole ustawia
-- panel sedziego przy aktywacji linku speakera — wiec dostep dokladnie sledzi
-- "czy link speakera jest aktywny", bez osobnej flagi w herkules_slots i bez
-- ryzyka rozjazdu (jedno zrodlo prawdy).
--
-- Izolacja zachowana: herkules_slots NADAL gated tylko publicShare (t.html nie
-- rozwiaze short-kodu cudzych zawodow), a *_state czyta sie po dokladnym
-- slot_id (losowy UUID) — tak samo jak przy projectorShare (007).
--
-- app_state (wieloboj) NIE ma speakera -> bez zmian (zostaje wzorzec z 007).
-- Uruchomic w Supabase Studio -> SQL Editor (po 007). Idempotentna.
-- ═══════════════════════════════════════════════════════════════

-- ─── patrol_state ──────────────────────────────────────────────
DROP POLICY IF EXISTS "patrol_state_anon_public" ON public.patrol_state;
CREATE POLICY "patrol_state_anon_public" ON public.patrol_state
  FOR SELECT TO anon
  USING (
    (NULLIF(patrol_state.state_json::text, '')::jsonb -> 'cfg' ->> 'speakerEnabled') = 'true'
    OR EXISTS (
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
    (NULLIF(osf_state.state_json::text, '')::jsonb -> 'cfg' ->> 'speakerEnabled') = 'true'
    OR EXISTS (
      SELECT 1 FROM public.herkules_slots hs
      WHERE 'osf_slot_' || hs.slot_id = osf_state.slot_id
        AND ( (hs.slot_json::jsonb->>'publicShare') = 'true'
           OR (hs.slot_json::jsonb->>'projectorShare') = 'true' )
    )
  );

-- app_state (wieloboj) — bez speakera, polityka z 007 pozostaje bez zmian.
