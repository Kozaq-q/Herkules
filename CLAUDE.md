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
| `patrol.html` | 6836 | Patrol — panel sędziowski (główny plik nad którym pracujemy) |
| `patrol-start.html` | 1677 | Patrol — apka sędziego startu (mobilna) |
| `patrol-speaker.html` | 818 | Patrol speaker |
| `patrol-projektor.html` | 876 | Patrol projektor |
| `projektor.html` | 1060 | Wielobój projektor |

## Tabele Supabase
- `herkules_slots` — metadane slotów (`slot_id`, `slot_json`, `updated_at`). Slot.meta = `{athletes, teams, status, accentColor, updatedAt}` zapisywane po każdym save (throttle 5s przez `_syncSlotMetaThrottled`). `start.html` `getSlotStats()` czyta `slot.meta` najpierw, fallback do localStorage.
- `osf_state` — stan OSF (`slot_id`, `state_json`, `updated_at`)
- `app_state` — stan czwórbóju/wieloboju
- `patrol_state` — stan patrolu (utworzona ręcznie 2026-05-15, RLS + policy anon full access + publication supabase_realtime)

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

## TODO / znane braki
- patrol.html jest bardzo długi (6836 linii) — przyszły refactor: split na moduły? (na razie monolit dla prostoty deploymentu)
- klucz startowy: aktualnie shuffle losowe — można rozważyć Berger gdy więcej drużyn (powtarzalność)
