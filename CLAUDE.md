# Herkules — MSS (Military Sports System)

Polski system do prowadzenia zawodów wojskowych. Pure HTML/CSS/JS, jeden plik per aplikacja, sync przez Supabase.

## Konkurencje (3 rodzaje)
1. **Wielobój** (`type='wielobój'`, dawniej `'czworboj'`) — 4 konkurencje, M/K. Plik: `index.html`. Storage key `zawody_slot_<id>`. Migracja czworboj→wielobój w `start.html` (`resolveType`, `migrateSlotType`).
2. **OSF** (`type='osf'`) — tor przeszkód, 2 serie, tory L/P. Pliki: `osf.html` + `osf-projektor.html` + `osf-speaker.html`. Tabela Supabase: `osf_state`.
3. **Bieg patrolowy** (`type='patrol'`) — bieg 2km + OSF + strzelanie. Pliki: `patrol.html` + `patrol-start.html` + `patrol-speaker.html` + `patrol-projektor.html`. Tabela: `patrol_state`.

## Layout plików (rozmiary indykatywne — pomocne do oceny czy `Read` ma sens)

| Plik | Linie | Cel |
|---|---|---|
| `start.html` | 1054 | Panel główny (lista slotów, COMPETITION_TYPES, otwieranie konkurencji) |
| `index.html` | 6462 | Wielobój — panel sędziowski |
| `osf.html` | 11027 | OSF — panel sędziowski (S1, S2, drużynówka, klasyfikacja) |
| `osf-projektor.html` | 1480 | OSF projektor publiczny |
| `osf-speaker.html` | 1700 | OSF speaker (komentator) |
| `patrol.html` | ~7100 | Patrol — panel sędziowski (główny plik nad którym pracujemy) |
| `patrol-start.html` | 1677 | Patrol — apka sędziego startu (mobilna) |
| `patrol-speaker.html` | 818 | Patrol speaker |
| `patrol-projektor.html` | 876 | Patrol projektor |
| `projektor.html` | 1060 | Wielobój projektor |
| `start.html` | ~1200 | Panel start (wejściowy) — z panelem zarządzania sędziami |
| `wieloboj.html` | ~6500 | Wielobój (przemianowany z index.html) |
| `index.html` | ~20 | Redirect → start.html (zachowuje query+hash) |
| `t.html` | ~1500 | **TABLICA WYNIKÓW publiczna** dla uczestników (read-only, kafelkowy layout + hero + lupa + auto-refresh 10s) |
| `tablica.html` | ~30 | Redirect na t.html (legacy URL) |
| `qr.html` | ~280 | Plakat QR do druku A4 (czerno-biały, instrukcje dla zawodników) |
| `favicon.svg` | — | Żółty sześciokąt MSS dla wszystkich tabów |
| `auth.js` | ~600 | **Wspólny moduł autoryzacji** (Supabase Auth + login overlay + watchdog) |
| `supabase/` | — | Migracje SQL (001-004) + Edge Functions |
| `cloudflare/` | — | Worker proxy z cache 10s |

## Tabele Supabase
- `herkules_slots` — metadane slotów (`slot_id`, `slot_json`, `updated_at`). Slot.meta = `{athletes, teams, status, accentColor, updatedAt}` zapisywane po każdym save (throttle 5s przez `_syncSlotMetaThrottled`). `start.html` `getSlotStats()` czyta `slot.meta` najpierw, fallback do localStorage. **Po fazie 2: slot ma też pole `publicShare: bool`** — kontroluje czy uczestnicy widzą wyniki w t.html.
- `osf_state` — stan OSF (`slot_id`, `state_json`, `updated_at`). slot_id = `'osf_slot_' + herkulesId`
- `app_state` — stan wieloboju. slot_id = `'panel_' + herkulesId`
- `patrol_state` — stan patrolu. slot_id = herkulesId (direct)
- `mss_users` — **whitelist sędziów** (od fazy 1). Kolumny: `id` (linked do auth.users), `email`, `display_name`, `role` (admin/judge), `active`, `created_at`, `created_by`, `notes`. Funkcje pomocnicze: `is_active_judge()`, `is_active_admin()` (SECURITY DEFINER).
- `auth.users` — tabela systemowa Supabase Auth (emaile + hasła + UUID)

### RLS (Row Level Security) — aktualny stan
**SELECT:**
- `mss_users`: anon=blok, authenticated=true (każdy zalogowany czyta listę)
- `herkules_slots`: anon=tylko gdy `slot_json->>'publicShare' = 'true'`, authenticated=wszystko
- `patrol_state/osf_state/app_state`: anon=tylko gdy powiązany slot ma `publicShare=true` (subquery do herkules_slots), authenticated=wszystko

**WRITE (INSERT/UPDATE/DELETE):**
- Wszystkie tabele stanu: tylko `is_active_judge() = true`
- `mss_users`: tylko service_role (Edge Function admin-users)

Migracje SQL w `supabase/migrations/`:
- `001_auth_setup.sql` — tabela mss_users, funkcje, RLS na mss_users
- `002_seed_admin.sql` — szablon do utworzenia pierwszego admina (Pawla)
- `003_tighten_rls.sql` — zaostrzenie RLS na tabelach stanu
- `004_public_share_isolation.sql` — anon SELECT tylko publicShare=true

## Architektura sync (wzorzec wspólny we wszystkich panelach)
1. **Realtime channel** Supabase (`postgres_changes` na tabeli `<typ>_state`)
2. **Polling fallback** (adaptive: 2s gdy RT healthy, 1s gdy padł)
3. **Save**: debounced (300ms), `localStorage` od razu + `saveToSupabase` w tle
4. **Merge per-field** dla state.times i state.disq (timestamp wygrywa) — patrz `mergeTimesPerField`, `mergeDisqPerId` w patrol.html
5. **Tombstones**: usunięte pola zachowują `_At` timestamp do mergowania

## Role sędziowskie (patrol.html — `PTR_ROLES`)
- **STARTER** — START pary, RESET (falstart), ustawianie godzin auto-startu
- **OSF** — wpisuje czas OSF z fotokomórki
- **META** — STOP zawodnika, ręczne wpisywanie czasu mety, trafienia, DSQ
- **ADMIN** — wszystko + dostęp do Konfiguracji i Zawodników (inne role mają te zakładki ukryte)

Aktualna rola w `localStorage['ptr_role_' + SLOT_ID]`. UI ogranicza możliwości edycji pól per rola (`canEditOsf`, `canEditTotal`, `canEditHits`, `canEditDsq`).

## Zakładki w `patrol.html` (kolejność w pasku nav)
1. ⚙ **Konfiguracja** (`page-setup`) — tylko ADMIN
2. 👥 **Zawodnicy** (`page-athletes`) — tylko ADMIN
3. 🎲 **Pary / wpisywanie** (`page-pairs`) — wpisywanie wyników indywidualnych (offline-friendly)
4. ⏱ **Stoper** (`page-timer`) — stoper synchronizowany dla indywidualnych (online-only, ukryty w offline)
5. 🏃 **Pary drużyn** (`page-team-run`) — wpisywanie wyników drużynowych (offline-friendly)
6. ⏱ **Stoper drużyn** (`page-team-timer`) — stoper synchronizowany dla drużynowych (online-only, ukryty w offline)
7. 🏆 **Wyniki** (`page-results`) — klasyfikacje + drukowanie PDF

## State model — `patrol.html` (kluczowe pola w `state`)
```js
state = {
  setup:      { name, city, date, org, notes, accentColor },
  athletes:   [{id, bib, name, gender, team, rank, _manualBib}],
  pairs:      [{pairNum, gender, aId, aLane, bId, bLane}],  // 2-osobowe ind.
  times:      { [id]: { total, osf, hits (legacy 0-5), shotPoints (0-50), tens, *At } },
  disq:       { [id]: true },
  disqAt:     { [id]: ms },
  runs:       { [gender_pairNum]: { startedAt, finishedAt: {id: ms}, scheduledStartAt } },
  cfg:        { offlineMode, startEnabled, startKey, startKeyExpiresAt,
                speakerEnabled, speakerKey, speakerKeyExpiresAt,
                starterPulse: {starterMs, t} },
  lockedPairs: { all: ['M_3', 'K_1', ...] },
  teamRun:     { [teamName]: { biegSec (FLOAT z setnymi), osfSec, shotPoints (0-150),
                               eliminated (0-3), tens (0-15), dsq, *At } },
  teamRuns:    { [pairNum]: { startedAt, finishedAt: {teamName: ms}, scheduledStartAt } },
  teamRunPairs: [{pairNum, aTeam, aLane, bTeam, bLane}]
};
```

## Punktacja patrolu (regulamin 11DKPanc 2025)
**Indywidualnie:**
```
WYNIK = czas_biegu_sek − pkt_OSF − pkt_strzelanie
  pkt_OSF        = 450 − 2 × czas_osf_sek    (baza 75s = 300pkt)
  pkt_strzelanie = pkt_na_tarczy × 2          (max 50 × 2 = 100)
```
Najniższy wynik wygrywa (może być ujemny). Tie-break: lepsze strzelanie → lepszy OSF → więcej dziesiątek.

**Drużynowo (klasyfikacja zespołowa):** suma punktów 3 najlepszych mężczyzn z drużyny. Kobiety NIE liczą. Drużyna potrzebuje min. 3 sklasyfikowanych M.

**Bieg drużynowy 3-osobowy:**
```
WYNIK = czas_biegu_sek − (480 − 2×czas_osf) − strzelanie×2 + eliminowani×100
```
Baza OSF zespół = 90s daje 300pkt. Eliminacja zawodnika z patrolu: +100pkt karne za każdego (regulamin).

**Klasyfikacja generalna:** ind. (top 3 M) + bieg drużynowy. Drużyna bez biegu drużynowego: +1200pkt karnych ("600 wyjściowych podwojonych" wg regulaminu).

## Klucz startowy patrolu — algorytm
Dla każdej warstwy Y (Y=1, Y=2, ...): bierze wszystkich zawodników z pozycją Y w zespołach, **losowo miesza** kolejność zespołów (shuffle Fisher-Yates), paruje sąsiadująco. Pierwszy z pary → tor L, drugi → tor P. Jeśli w parze są zespół z X nieparzystym i parzystym, NIEPARZYSTY trafia na L (preferencja). Nieparzysta liczba zespołów → ostatni SOLO.

Implementacja: `drawPairsByKey()` w patrol.html ~3823.

## Klucz startowy biegu drużynowego
Sortuje drużyny po sumie ind. (3 najlepszych M) — **najsłabsi pierwsi** (regulamin: "w pierwszej dwójce startują z najsłabszymi czasami"). Paruje sąsiadująco. Lewy → L, prawy → P. Implementacja: `generateTeamRunPairs()`.

## Sync zegara — 2 warstwy
1. **Server clock sync** (HTTP Date header z Supabase, refresh co 60s) — fallback
2. **Starter pulse** (autorytatywny zegar) — starter wysyła broadcast `{starterMs}` co 10s na kanale `patrol_pulse_<slot>`. Inne urządzenia liczą `_starterOffset` (MAX z 8 ostatnich próbek). `nowMs()` używa `_starterOffset` gdy puls świeży (<4h), inaczej fallback do server clock.

Wskaźnik w nagłówku `patrol.html`: 🟢 LIVE (<30s) / 🟡 starter Xs/min temu / 🔴 brak kalibracji.

**WAŻNE rozróżnienie domen czasu:**
- `nowMs()` = czas startera (do pomiarów elapsed START→STOP)
- `Date.now()` = wall-clock urządzenia (do wpisywanych godzin auto-startu)
- Mieszanie domen w `scheduledStartAt` powodowało wcześniej bug "godzina off by 10 min" — naprawione, NIE mieszać.

## Konwencje w kodzie patrolu
- **`getRun(gender, pairNum)`** dla indywidualnego, **`getTeamRunPair(pairNum)`** dla drużynowego
- **`getPtrRole()`** zwraca aktualną rolę z localStorage
- **`save()`** = debounced (300ms upload), **`saveImmediate()`** = natychmiast
- **`renderTimerView()`** indywidualny stoper, **`renderTeamTimerView()`** drużynowy
- **`_renderTeamRunActive()`** auto-wybiera renderer drużynowy wg aktywnej zakładki — używaj po lokalnej zmianie state.teamRun/teamRuns
- **`tickTimers()`** co 100ms aktualizuje wszystkie zegary; wywołuje `_tickTeamRunTimers()` i `_tickPtrRunningBannerTimers()`
- **`formatRunTime(ms)`** → "m:ss.SS" (z setnymi), **`_formatTeamSec(sec)`** dla drużynówki (float sec → "m:ss.SS")
- **`_parseTeamSec(str)`** parsuje "m:ss.SS" / "ss.SS" → float seconds (do biegu drużynowego)
- **`isTimeMarker(v)`** zwraca true dla 'DNF'/'DNS'

## Pułapki / Anti-patterns (lekcje z poprzednich bugów)
1. **Selektory tickerów**: `.timer-athlete-time[data-running="1"]` matchuje też team-timery. Trzeba SKIP team-timery (`if (el.dataset.teamTimer || !el.dataset.pair) return;`) w pętli indywidualnej.
2. **pairNum**: dla par drużynowych może być **stringiem** (`'solo:TeamName'` dla virtualnych) lub liczbą — używaj `_parsePairKey()` zamiast `parseInt()`.
3. **biegSec drużynowy**: float (z setnymi), NIE int. parsowanie przez `parseFloat`.
4. **Klucz parowania** nie wspomina o OSF (regulamin to NIE OSF). Pierwszy z pary → L (z preferencją nieparzystego X), drugi → P.
5. **DSQ w pairs view**: klasa `.dsq` na `.ptr-time-tile` jest używana podwójnie (DSQ + "zablokowane przez rolę"). Do faktycznego DSQ używaj `.is-dsq` na `.pair-athlete`.
6. **calcPatrolPoints/calcTeamRunPoints** zwracają `null` dla niesklasyfikowanego — nie traktuj jako 0.

## Konwencja commitów
Polish-language commit messages (bez polskich znaków w heredoc, bo bash). Format:
```
<obszar>: <krótki opis>

[Szczegóły co i dlaczego]

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```
Obszary: `patrol`, `patrol-team-run`, `patrol-team-timer`, `patrol-start`, `patrol-speaker`, `patrol-projektor`, `osf`, `osf-speaker`, `osf-projektor`, `print`.

## Workflow z użytkownikiem
- **Po każdej skończonej zmianie**: zapytać o commit+push (user nie chce ręcznych uploadów). Nie commitować bez zgody (chyba że user wcześniej w sesji powiedział „commit wszystko").
- **Plik widoczny w preview panelu**: user nie chce komunikatów "plik widoczny w panelu Launch preview" po każdej edycji (mimo że hook to wymusza — ignorować szum, iść dalej).

## ═══════════════════════════════════════════════════════════
## FAZY ROZWOJU (status wdrożenia)
## ═══════════════════════════════════════════════════════════

### ✅ Faza 1 — Bezpieczeństwo (wdrożona)

**Cel:** Zastąpić wspólne hasło panelu logowaniem per-sędzia + zabezpieczyć zapisy strukturalnie.

**Komponenty:**
- `auth.js` — wspólny moduł autoryzacji, Supabase Auth (email+hasło, sesje 30+ dni)
- Login overlay z fade+blur, generowany dynamicznie przez auth.js
- Storage key sesji: `mss-auth-token` (wspólny dla wszystkich plików MSS)
- Cache profilu w `localStorage[mss-auth-profile-cache]` (offline-friendly)
- Watchdog co 5s: jeśli `mss_users.active = false` → blokujący banner pełnoekranowy + auto-recovery (gdy admin włączy ponownie)
- Edge Function `admin-users` (TypeScript w Deno, deployed via Supabase Studio) — CRUD na sędziach, używa service_role
- Panel "👥 Sędziowie" w start.html (admin-only) — wywołuje Edge Function

**Pliki sędziowskie z MSS_AUTH:** `start.html`, `wieloboj.html`, `osf.html`, `patrol.html`, `patrol-start.html`. Każdy ma `<script src="auth.js">` + boot czeka na `MSS_AUTH.init()`. Niezalogowani widzą overlay.

**WAŻNE:** Sędziowie idą **bezpośrednio** do Supabase (NIE przez Worker) — zapisy natychmiastowe, RLS chroni przed niezalogowanymi.

### ✅ Faza 2 — Publika + tablica (wdrożona)

**Cel:** Udostępnić wyniki publicznie przez QR kod, ale strukturalnie odizolować różne zawody (uczestnik jednych zawodów NIE może zobaczyć innych).

**Komponenty:**
- Custom domena: **`militarysportsystem.pl`** (OVH, ~30 PLN/rok)
- Cloudflare DNS proxy (free): SSL, DDoS protection, CDN
- DNS nameservers: `ivy.ns.cloudflare.com`, `sean.ns.cloudflare.com`
- GitHub Pages serwuje HTML/CSS/JS (przez Cloudflare cache)
- Plik `CNAME` w repo → custom domain w Settings → Pages

**Routing:**
- `militarysportsystem.pl/` → `index.html` (redirect na start.html)
- `militarysportsystem.pl/start.html` → panel sędziowski
- `militarysportsystem.pl/t.html?s=XXXXXX` → **tablica publiczna** (QR target)
- `militarysportsystem.pl/qr.html?u=...&n=...` → plakat QR A4 do druku

**Short URL:** `?s=XXXXXX` = ostatnie 6 znaków UUID slotu (lowercase). `t.html` resolwuje przez `ILIKE '%XXXXXX'` w herkules_slots. Backward compat: stary `?slot=UUID` też działa.

**publicShare toggle** w Konfiguracji każdej konkurencji (patrol/osf/wieloboj):
- Storage: `slot.publicShare: bool` w herkules_slots.slot_json
- Default `false` dla nowych slotów (`createSlot` w start.html)
- Toggle UI w karcie "📺 Tablica wyników publiczna" w setup
- RLS sprawdza tę flagę dla anon SELECT

**Tablica `t.html` — features:**
- Kafelkowy layout (jak patrol-speaker) — kategorie jako tile grid
- Klik kafelek → detail view z back button "← Kategorie"
- Hero section: chip typu (BIEG PATROLOWY/OSF/WIELOBÓJ) + duży tytuł zawodów + miasto/data
- Subtelny header z `mss-api` URL i 🔍 lupą + ● LIVE indicator
- **Lupa wyszukiwania** (Cmd+K też): szuka zawodników i drużyn forgiving (ignoruje polskie znaki, case)
- Auto-refresh co 10s (state.runs via PostgREST)
- Zawsze startuje od menu kafelkowego (nie z localStorage tab)
- Pełna funkcjonalność dla 3 typów: patrol (M/K/Drużynowa/Bieg dr./Generalna), OSF (M/K/Drużynowa), wieloboj (M/K/Drużynowa)
- Mobile responsive + projector-friendly (CSS breakpointy)

**`qr.html` — plakat A4 do druku:**
- Standalone, parametry przez URL: `?u=share_url&n=name&c=city&d=date`
- Elegancki czarno-biały design: Georgia serif headline, geometryczny divider, instrukcje 3-kroki w okrągłych obwódkach
- "Bez potrzeby aplikacji" + "Otwórz aparat w telefonie"
- Auto-print (param `?print=0` wyłącza)

**QR generator w panelach:** każdy panel (patrol/osf/wieloboj) ma kartę z QR + link + przyciski "Otwórz/Kopiuj/PNG/Drukuj plakat". Lib: `qrious@4.0.2`.

### ✅ Faza 2.5 — Skalowanie (wdrożona)

**Cel:** Wytrzymać dużo viewerów tablicy bez wyczerpania Supabase Free tier.

**Cloudflare Worker** (`cloudflare/worker.js`):
- URL: `https://mss-api.pawelkozak4327.workers.dev`
- Cache GET na `/rest/v1/*` przez 10 sekund (`caches.default`)
- POST/PATCH/DELETE i inne ścieżki — bypass cache
- Header diagnostyczny: `X-MSS-Cache: HIT/MISS/BYPASS`

**Tylko `t.html`** używa Workera (`SUPABASE_URL = 'https://mss-api.pawelkozak4327.workers.dev'`). Sędziowscy panele dalej direct do `yrgkgzrpfemmthscrprf.supabase.co`.

**Efekt:** 300 viewerów polling co 10s = 1 req/10s do Supabase (zamiast 30 RPS), ~18 MB/h egress (zamiast 5.4 GB/h).

**Cloudflare Workers Free limit:** 100k requestów/dzień. Realnie:
- 25 viewerów × 8h dziennie: mieści się
- 50 viewerów × 4h: mieści się
- 100+ viewerów: ryzyko przekroczenia — wtedy tablica padnie (Worker 1027 error), sędziowie NIEAFEKTOWANI
- 400+ viewerów: padnie po ~30 min → upgrade Workers Paid $5/mc (10M req/mc) lub zwiększyć refresh interval z 10s

## ═══════════════════════════════════════════════════════════
## ARCHITEKTURA — pełny stack
## ═══════════════════════════════════════════════════════════

```
UCZESTNICY (telefony) — przez QR kod:
  ↓
militarysportsystem.pl (Cloudflare DNS)
  ↓
GitHub Pages (HTML/CSS/JS) — wymusza redirect z `/` na start.html
  ↓
Cloudflare Worker `mss-api` (cache 10s) — TYLKO dla t.html
  ↓
Supabase REST API (RLS: anon SELECT tylko publicShare=true)

SĘDZIOWIE (laptop/telefon):
  ↓
militarysportsystem.pl → start.html (login overlay z auth.js)
  ↓
auth.js: Supabase Auth → JWT → sesja w localStorage[mss-auth-token]
  ↓
panele (patrol/osf/wieloboj/...) — BEZPOŚREDNIO do Supabase REST
  ↓
RLS: write tylko gdy is_active_judge() = true
```

## ═══════════════════════════════════════════════════════════
## SUPABASE — konfiguracja konta
## ═══════════════════════════════════════════════════════════

- Project URL: `https://yrgkgzrpfemmthscrprf.supabase.co`
- Anon key: w pliku `auth.js` (linia 26)
- Auth → Providers → Email → signup DISABLED, password auth ENABLED, auto-confirm dla nowych userów (przez Edge Function)
- Auth → Sessions: Time-box=0 (never), Inactivity=0 (never) — sesje persistują
- Auth → Refresh Tokens: Detect compromised ON, reuse interval 10s
- Edge Function `admin-users` deployed (kod w `supabase/functions/admin-users/index.ts`)
- Pierwszy admin: `pawelkozak4327@gmail.com` (rola `admin` w mss_users)

## ═══════════════════════════════════════════════════════════
## TODO / znane braki
## ═══════════════════════════════════════════════════════════

**Otwarte pytanie (faza 2.5 niedokończona):**
- Refresh interval w t.html: aktualnie 10s. Przy 100+ viewerów Worker Free się wyczerpie. Decyzja niepodjęta:
  - Zmienić na 30s (DARMOWE, daje 3× pojemność)
  - Workers Paid $5/mies (10M req/mies, praktycznie unlimited)
  - Hybrid: dynamiczny refresh

**Przyszłe fazy (nie wdrożone):**
- **Faza 3** — audit log + auto-snapshoty stanu + soft-delete zawodników (recovery po sabotażu, ważne po pierwszych prawdziwych zawodach)
- **Faza 4** — Cloudflare WAF + rate limiting (anty-spam/DDoS)
- **Faza 5** — 2FA dla admina (TOTP)
- **Faza 6** — Cloudflare Email Routing (email pod custom domeną)

**Małe TODO:**
- patrol.html jest bardzo długi (~7100 linii) — przyszły refactor: split na moduły? (na razie monolit dla prostoty deploymentu)
- klucz startowy: aktualnie shuffle losowe — można rozważyć Berger gdy więcej drużyn (powtarzalność)
- Realtime subscriptions w t.html zamiast polling (wymaga Supabase Pro $25/mc, 500 concurrent connections)
