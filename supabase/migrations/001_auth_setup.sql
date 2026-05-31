-- ═══════════════════════════════════════════════════════════════
-- MSS Auth — Migracja 001: Tabela userów + funkcja pomocnicza
-- ═══════════════════════════════════════════════════════════════
--
-- BEZPIECZEŃSTWO: Ta migracja JEST BEZPIECZNA do uruchomienia
-- na produkcji teraz — nie zmienia jeszcze RLS, nie blokuje
-- żadnych operacji. Tylko dodaje infrastrukturę.
--
-- Następne kroki:
--   002_seed_admin.sql   — utwórz pierwsze konto admina
--   003_tighten_rls.sql  — DOPIERO PO wdrożeniu frontendu z loginem!
-- ═══════════════════════════════════════════════════════════════

-- ─── Tabela whitelisty sędziów ─────────────────────────────────
-- Rekord powstaje przez Edge Function `admin-users` po utworzeniu
-- konta w auth.users. Linkowane 1:1 do auth.users.id.
CREATE TABLE IF NOT EXISTS public.mss_users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL UNIQUE,
  display_name TEXT,
  role TEXT NOT NULL DEFAULT 'judge' CHECK (role IN ('admin', 'judge')),
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  notes TEXT
);

COMMENT ON TABLE public.mss_users IS
  'Whitelista zaufanych sędziów MSS. Użytkownik auth.users który nie ma rekordu tutaj NIE może pisać do tabel stanu.';

-- ─── RLS na samej mss_users ────────────────────────────────────
-- Każdy zalogowany może odczytać swój rekord (do sprawdzenia roli).
-- Admin może odczytać wszystkich i modyfikować.
ALTER TABLE public.mss_users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "mss_users_self_read" ON public.mss_users;
CREATE POLICY "mss_users_self_read" ON public.mss_users
  FOR SELECT
  TO authenticated
  USING (id = auth.uid());

DROP POLICY IF EXISTS "mss_users_admin_read" ON public.mss_users;
CREATE POLICY "mss_users_admin_read" ON public.mss_users
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.mss_users
      WHERE id = auth.uid() AND role = 'admin' AND active = true
    )
  );

-- Insert/update/delete na mss_users tylko przez Edge Function
-- (service_role). Brak policy dla anon/authenticated = blok.

-- ─── Funkcja pomocnicza: czy bieżący user to aktywny sędzia? ───
-- Używana w politykach RLS na tabelach stanu.
-- SECURITY DEFINER — działa z uprawnieniami właściciela (postgres),
-- żeby ominąć RLS na mss_users przy sprawdzeniu.
CREATE OR REPLACE FUNCTION public.is_active_judge()
RETURNS BOOLEAN
LANGUAGE SQL
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.mss_users
    WHERE id = auth.uid() AND active = true
  );
$$;

COMMENT ON FUNCTION public.is_active_judge() IS
  'TRUE jeśli zalogowany user istnieje w mss_users i ma active=true. Używać w RLS dla operacji write.';

-- ─── Funkcja pomocnicza: czy bieżący user to aktywny admin? ────
CREATE OR REPLACE FUNCTION public.is_active_admin()
RETURNS BOOLEAN
LANGUAGE SQL
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.mss_users
    WHERE id = auth.uid() AND active = true AND role = 'admin'
  );
$$;

-- ─── Grant ─────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION public.is_active_judge() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.is_active_admin() TO authenticated, anon;

-- ─── Indeks na email dla szybkiego lookup w Edge Function ──────
CREATE INDEX IF NOT EXISTS mss_users_email_idx ON public.mss_users (email);
CREATE INDEX IF NOT EXISTS mss_users_active_idx ON public.mss_users (active) WHERE active = true;

-- ═══════════════════════════════════════════════════════════════
-- Po wykonaniu sprawdź:
--   SELECT * FROM public.mss_users;  -- (pusty, OK)
--   SELECT public.is_active_judge(); -- false (nikt nie zalogowany)
-- ═══════════════════════════════════════════════════════════════
