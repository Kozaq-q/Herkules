# MSS Supabase — Auth & RLS

Migracje do wprowadzenia zabezpieczeń (auth + RLS) na backendzie Supabase.

## Status wdrożenia

| Krok | Plik | Uruchomić? | Kiedy |
|---|---|---|---|
| 1 | `migrations/001_auth_setup.sql` | TAK, bezpiecznie | Teraz |
| 2 | (panel Supabase) Utwórz konto admina w Auth → Users | TAK | Po kroku 1 |
| 3 | `migrations/002_seed_admin.sql` | TAK po podmianie UUID | Po kroku 2 |
| 4 | (panel Supabase) Auth → Providers → Email → wyłącz "Enable Signup" | TAK | Po kroku 3 |
| 5 | (panel Supabase) Auth → Settings → JWT refresh token = 2592000 (30 dni) | TAK | Po kroku 3 |
| 6 | Frontend: wdroż `auth.js` + zmiany w panelach sędziowskich | TAK | Następna faza implementacji |
| 7 | Frontend: deploy Edge Function `admin-users` | TAK | Po kroku 6 |
| 8 | Frontend: panel zarządzania userami w `start.html` | TAK | Po kroku 7 |
| 9 | `migrations/003_tighten_rls.sql` | **DOPIERO** po pełnym wdrożeniu frontendu | Ostatni krok |

## Cel architektoniczny

```
┌─────────────────────────────────────────────────────────┐
│ PUBLIC (anon key, brak logowania)                       │
│   • projektor.html, osf-projektor.html, ...             │
│   • tablica.html (przyszły QR target)                   │
│   • Może: SELECT, realtime subscribe                    │
│   • Nie może: INSERT/UPDATE/DELETE                      │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ SUPABASE (RLS broni dostępu)                            │
│   ┌─────────────────────────────────────────────────┐   │
│   │ herkules_slots, app_state, osf_state,           │   │
│   │ patrol_state                                    │   │
│   │   SELECT: anon + authenticated                  │   │
│   │   WRITE:  is_active_judge() = TRUE              │   │
│   └─────────────────────────────────────────────────┘   │
│   ┌─────────────────────────────────────────────────┐   │
│   │ mss_users (whitelist sędziów)                   │   │
│   │   SELECT: self lub admin                        │   │
│   │   WRITE:  tylko Edge Function (service_role)    │   │
│   └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                          ▲
                          │
┌─────────────────────────────────────────────────────────┐
│ JUDGES (zalogowani przez email+hasło)                   │
│   • start.html, index.html, osf.html, patrol.html,      │
│     patrol-start.html                                   │
│   • Login overlay zasłania UI dopóki nie zalogowani     │
│   • Sesja 30 dni — działa offline po pierwszym logowaniu│
│   • Może: pełen dostęp do tabel stanu                   │
└─────────────────────────────────────────────────────────┘
                          ▲
                          │
┌─────────────────────────────────────────────────────────┐
│ ADMIN (rola='admin' w mss_users)                        │
│   • Wszystko co sędzia                                  │
│   • + zakładka "Sędziowie" w start.html                 │
│   • + Edge Function admin-users (dodawanie/usuwanie)    │
└─────────────────────────────────────────────────────────┘
```

## Co po wdrożeniu zabezpieczone

Po kroku 9 (zaostrzenie RLS) ktoś kto wyciągnie `SUPABASE_ANON_KEY` z kodu JS:

✓ Nie może nadpisać wyników zawodników
✓ Nie może usunąć ani zmienić slotu
✓ Nie może wstrzykiwać śmieci do `patrol_state` / `osf_state` / `app_state`
✓ Nie zobaczy listy sędziów (`mss_users` chronione)

Nadal może:
✗ Czytać aktualny stan zawodów (publiczne — tak ma być, projektor/viewer tego potrzebują)
✗ Spamować requestami (mitygacja: Cloudflare WAF — opcjonalna faza 4)

## Co NIE jest pokryte

- Brute-force na hasła sędziów → Supabase ma wbudowany rate limit. Hasła silne!
- Wyciek tokena zalogowanego sędziego (np. ktoś przejmie telefon) → odsubskrybować/zdezaktywować usera w panelu admin → 1h max do końca sesji.
- Atak DDoS → Cloudflare faza 4.
- Audit log "kto co zmienił" → faza 3 (snapshoty + per-edit metadata).

## Następne fazy (kolejność)

1. **Faza 1 (ta migracja)**: auth + RLS — _w trakcie_
2. **Faza 2**: custom domena (`mss.pl` lub podobna) + `tablica.html` (read-only viewer dla QR)
3. **Faza 3**: audit log, soft-delete zawodników, auto-snapshoty stanu
4. **Faza 4** (opcjonalna): Cloudflare WAF, rate limiting
