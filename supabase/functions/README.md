# MSS Edge Functions

## admin-users

Backend dla panelu "Sędziowie" w `start.html`. Operacje admin (create/update/delete użytkowników) wymagają `service_role` key, którego NIE WOLNO wystawiać w przeglądarce — stąd Edge Function.

### Deploy (UI Supabase Studio — najprościej)

1. Supabase Studio → lewe menu → **Edge Functions** (ikona błyskawicy ⚡)
2. **"Deploy a new function"** lub **"Create a new function"**
3. Nazwa: `admin-users`
4. Wklej zawartość pliku `index.ts` do edytora
5. Kliknij **"Deploy function"**
6. Czekaj ~30s na deploy
7. Status powinien zmienić się na **"Active"**

### Test (opcjonalny)

Wklej w terminalu (podmień `<TWÓJ_JWT>` na token z localStorage twojej sesji):
```bash
curl -X POST 'https://yrgkgzrpfemmthscrprf.supabase.co/functions/v1/admin-users' \
  -H 'Authorization: Bearer <TWÓJ_JWT>' \
  -H 'Content-Type: application/json' \
  -d '{"action":"list"}'
```

Powinno zwrócić JSON z listą sędziów.

### Akcje

| Action | Body params | Co robi |
|---|---|---|
| `list` | — | Lista wszystkich sędziów z `mss_users` |
| `create` | `email`, `password`, `display_name`, `role` | Tworzy konto w `auth.users` + wpisuje do `mss_users` |
| `setActive` | `id`, `active` (bool) | Aktywuje/dezaktywuje sędziego |
| `updatePassword` | `id`, `password` | Reset hasła sędziego |
| `updateRole` | `id`, `role` ('admin'/'judge') | Zmiana roli |
| `updateName` | `id`, `display_name` | Zmiana imienia |
| `delete` | `id` | Usuń konto na zawsze (ON DELETE CASCADE) |

### Bezpieczeństwo

- Authorization header z JWT zalogowanego usera (sprawdzany przed każdą akcją)
- Tylko `mss_users.role = 'admin'` + `active = true` może wywoływać
- Service role key NIE wyciekają do klienta
- Zabezpieczenia samosabotażowe:
  - Nie można dezaktywować swojego konta
  - Nie można usunąć swojego konta
  - Nie można odebrać sobie roli admin
