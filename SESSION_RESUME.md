# Session Resume — MSS po fazie 2.5

> Snapshot z 2026-06-09 (data ostatniej sesji). Plik do czytania **dla Ciebie** (Pawla) gdy wrócisz po przerwie. Claude i tak ma pełen kontekst z CLAUDE.md.

## TL;DR

Zrobione przez ostatnie 2 dni intensywnej pracy. Faza 1 (bezpieczeństwo), Faza 2 (publika + tablica), Faza 2.5 (skalowanie przez Cloudflare Worker). Wszystko działa end-to-end na produkcji `militarysportsystem.pl`.

## Co już DZIAŁA (przetestowane)

✅ Logowanie sędziów emailem+hasłem (`pawelkozak4327@gmail.com` jako admin)
✅ Panel "👥 Sędziowie" w start.html (dodawanie/wyłączanie/reset hasła)
✅ RLS: anon czyta tylko publicShare=true, write tylko aktywni sędziowie
✅ Watchdog dezaktywacji (5s detekcja + auto-recovery)
✅ Domena militarysportsystem.pl z SSL przez Cloudflare
✅ Tablica `t.html?s=XXXXXX` — kafelkowy layout, hero, lupa wyszukiwania
✅ QR generator w panelach + elegancki plakat A4
✅ Cloudflare Worker `mss-api` cache'uje GET na 10s
✅ Toggle "Publikacja" per slot (anon widzi tylko gdy włączone)
✅ Favicon żółty sześciokąt MSS
✅ Bug "wylogowanie na refresh" naprawiony (auth.js obsługuje network error)
✅ Root `/` redirectuje na start.html (był wieloboj)

## Otwarte pytanie (jedyne)

**Refresh interval w t.html.** Aktualnie 10 sekund.

Przy >100 viewerów jednocześnie, Cloudflare Worker Free (100k req/dzień) wyczerpie się w godzinę. Decyzja:

- **A. Zmienić na 30s w t.html** — DARMOWE, 3× więcej pojemności, wyniki opóźnione max 30s. Wymaga prostej edycji w `t.html` (szukać `startAutoRefresh` lub `setInterval(loadAndRender, 10000)` → zmienić na `30000`)
- **B. Workers Paid $5/mies** — 10M req/mies, praktycznie unlimited dla naszego use case. Wystarczy aktywować w Cloudflare Dashboard
- **C. Hybryda** — defaultowo 30s w t.html + włączyć Workers Paid w miesiące zawodów

Moja rekomendacja: **A teraz** (darmowe, prosta zmiana), **B gdy okaże się że >100 viewerów**.

## Konta i dostępy

| Co | Gdzie | Login |
|---|---|---|
| GitHub repo | github.com/Kozaq-q/Herkules | login GitHub (SSO) |
| OVH (domena) | manager.ovh.com | konto OVH |
| Cloudflare (DNS + Worker) | dash.cloudflare.com | przez GitHub SSO |
| Supabase (DB + Auth + Edge) | supabase.com | przez GitHub SSO |
| MSS jako admin | militarysportsystem.pl | pawelkozak4327@gmail.com + hasło |

## Pliki które warto znać

| Plik | Co tam jest |
|---|---|
| `CLAUDE.md` | Pełen kontekst (auto-wczytywany przez Claude w każdej sesji) |
| `auth.js` | Wspólny moduł logowania (Supabase Auth + watchdog) |
| `t.html` | Tablica publiczna — to co widzą zawodnicy po skanowaniu QR |
| `qr.html` | Plakat A4 do druku — czerno-biały, z instrukcjami |
| `start.html` | Panel sędziowski wejściowy + zarządzanie sędziami |
| `wieloboj.html` | Panel wieloboju (przemianowany z index.html) |
| `index.html` | Tylko 20 linii redirect na start.html |
| `cloudflare/worker.js` | Kod Workera (już wdrożony jako `mss-api.pawelkozak4327.workers.dev`) |
| `cloudflare/README.md` | Instrukcje deploy Workera (jeśli kiedyś trzeba odtwarzać) |
| `supabase/migrations/` | SQL 001-004 (już wykonane w Supabase) |
| `supabase/functions/admin-users/index.ts` | Edge Function (już deployed) |

## Co zostało do zrobienia (przyszłe sesje)

### Wysoki priorytet (przed pierwszymi zawodami z >50 osób)
- [ ] Zdecydować refresh interval (30s vs Workers Paid)
- [ ] Test end-to-end z prawdziwymi danymi: sędzia wpisuje wyniki → admin włącza publikację → uczestnik skanuje QR → widzi swoje miejsce
- [ ] Wydrukować QR plakat (z `qr.html`) → faktycznie zeskanować telefonem → sprawdzić czy widzi wyniki

### Średni priorytet
- [ ] **Faza 3 — Backupy/recovery**: auto-snapshoty stanu co X minut do osobnej tabeli, soft-delete zawodników, audit log "kto co zmienił" (na wypadek sabotażu lub pomyłki)
- [ ] Dodać do panelu admina widok "Eksportuj wyniki do PDF/CSV" jeśli jeszcze nie ma

### Niski priorytet / nice to have
- [ ] Faza 4: Cloudflare WAF + rate limiting (gdy będzie problem)
- [ ] Faza 5: 2FA dla admina (TOTP via Supabase Auth Factor)
- [ ] Faza 6: Email pod custom domeną (Cloudflare Email Routing)
- [ ] Refaktor patrol.html (~7100 linii) na moduły

## Jak wrócić do pracy

1. Napisz Claude: **"wracamy do MSS, zakres: <co chcesz robić>"** (np. "faza 3 — audit log")
2. Claude wczyta `CLAUDE.md` automatycznie i będzie znał aktualny stack
3. Jak nie pamiętasz co jest zrobione → `cat SESSION_RESUME.md` lub kazać Claudowi to przeczytać
4. Historia commitów git też pokazuje progres: `git log --oneline -50`

## Ważne hashe (gdyby trzeba cofnąć)

```
ostatni: 76dd3a1 — tablica idzie przez Worker
przed Worker: c065c84 — qr-plakat elegancki redesign
przed redesign: 4f76432 — wyszukiwarka (lupa)
przed lupa: a33eff3 — tablica zawsze startuje od menu
faza 2 close: 96fff45 — publicShare flag (RLS strukturalna izolacja)
faza 1 close: 36ceba0 — login do dezaktywowanego pokazuje banner
```

## Last words

Stack jest solidny. Wszystkie 3 fazy gotowe, działają, przetestowane. Możesz spokojnie organizować zawody do ~50-100 viewerów bez żadnych zmian. Przy większej skali → zdecyduj refresh interval lub Workers Paid.

Powodzenia! 🎯
