-- ═══════════════════════════════════════════════════════════════
-- MSS Auth — Migracja 002: Utworzenie pierwszego admina
-- ═══════════════════════════════════════════════════════════════
--
-- KROK 1 (RĘCZNIE w panelu Supabase):
--   1. Otwórz Supabase Studio → Authentication → Users
--   2. Kliknij "Add user" → "Create new user"
--   3. Email: pawelkozak4327@gmail.com  (lub inny dla admina)
--      Password: <wymyśl mocne hasło, zapisz w menedżerze haseł>
--      ☑ Auto Confirm User  (BARDZO WAŻNE — bez tego user nie zaloguje się)
--   4. Skopiuj nowo utworzony UUID usera (kolumna "ID")
--
-- KROK 2 (TEN PLIK):
--   Podmień UUID poniżej na ten skopiowany w kroku 1, potem uruchom.
-- ═══════════════════════════════════════════════════════════════

-- ⚠ PODMIEŃ UUID NA RZECZYWISTY z auth.users:
DO $$
DECLARE
  admin_uuid UUID := '00000000-0000-0000-0000-000000000000';  -- ⬅ PODMIEŃ
  admin_email TEXT := 'pawelkozak4327@gmail.com';              -- ⬅ PODMIEŃ jeśli inny
  admin_name TEXT := 'Paweł Kozak';                            -- ⬅ PODMIEŃ
BEGIN
  -- Sanity check: czy taki user istnieje w auth.users?
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = admin_uuid) THEN
    RAISE EXCEPTION 'User z UUID % nie istnieje w auth.users. Utwórz najpierw konto w panelu Auth.', admin_uuid;
  END IF;

  -- Sanity check: zgodność emaila
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = admin_uuid AND email = admin_email) THEN
    RAISE WARNING 'Email % nie zgadza się z auth.users dla UUID %. Sprawdź dane.', admin_email, admin_uuid;
  END IF;

  -- Upsert do mss_users
  INSERT INTO public.mss_users (id, email, display_name, role, active, created_by, notes)
  VALUES (admin_uuid, admin_email, admin_name, 'admin', true, admin_uuid, 'Pierwszy admin — seed migracja 002')
  ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email,
        display_name = EXCLUDED.display_name,
        role = 'admin',
        active = true;

  RAISE NOTICE 'Admin % (UUID=%) utworzony lub zaktualizowany.', admin_email, admin_uuid;
END $$;

-- ═══════════════════════════════════════════════════════════════
-- Po wykonaniu sprawdź:
--   SELECT * FROM public.mss_users WHERE role = 'admin';
-- Powinien być 1 wiersz z Twoim adminem.
--
-- Teraz spróbuj się zalogować (po wdrożeniu frontendu z auth.js):
--   Email + hasło ustawione w kroku 1 → powinno wpuścić.
-- ═══════════════════════════════════════════════════════════════
