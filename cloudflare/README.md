# MSS Cloudflare Worker

## Co to robi
Pośredniczy między tablicą wyników (`t.html`) a Supabase. Cache'uje odpowiedzi GET na 10 sekund — przy 300 viewerach jednoczesnych redukuje liczbę zapytań do Supabase ~300×.

## Deploy (Cloudflare Dashboard, bez CLI)

### KROK 1 — Otwórz panel Workers
1. https://dash.cloudflare.com → kliknij swoje konto
2. Lewe menu → **Workers & Pages**
3. Po prawej: **"Create application"** → wybierz **"Workers"** (nie Pages)
4. **"Create Worker"** (przycisk pomarańczowy)

### KROK 2 — Nazwa
- Nazwa: **`mss-api`** (lub inna którą wybierzesz, ale ta jest krótka)
- URL będzie: `mss-api.<twoj-account>.workers.dev`
- Kliknij **"Deploy"** (tworzy "Hello World" placeholder, za chwilę wymienimy)

### KROK 3 — Wklej kod
1. Po deploy → **"Edit code"** (po prawej)
2. Pojawia się edytor z "Hello World"
3. **Cmd+A** → **Delete** → wklej całą zawartość `cloudflare/worker.js`
4. Klik **"Save and Deploy"** (prawy górny)

### KROK 4 — Skopiuj URL
Po deploy zobaczysz URL Workera u góry, np:
```
https://mss-api.kozaq-q.workers.dev
```
**Skopiuj go** — będzie potrzebny w następnym kroku (update `t.html`).

### KROK 5 — Test (opcjonalny)
W przeglądarce wpisz:
```
https://mss-api.kozaq-q.workers.dev/rest/v1/?apikey=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlyZ2tnenJwZmVtbXRoc2NycHJmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM0MjYxMTUsImV4cCI6MjA4OTAwMjExNX0.CKuLNRCyolMf6nPiWgOcE8j76Isjwc12bwQmIY5E8Do
```
Powinno zwrócić listę endpointów Supabase (JSON).

W zakładce **Network** (DevTools) pierwsze żądanie ma header `X-MSS-Cache: MISS`, drugie identyczne `HIT`.

## Limit Free
- 100 000 wywołań / dzień
- 10 ms CPU / request

Wystarczy do ~150 viewerów × 8h zawody. Powyżej zalecane: Workers Paid ($5/mies, 10M wywołań).

## Zmiana w t.html
Po dostaniu URL Worker-a, zmień w `t.html`:

```javascript
// Stare:
const SUPABASE_URL = 'https://yrgkgzrpfemmthscrprf.supabase.co';

// Nowe:
const SUPABASE_URL = 'https://mss-api.kozaq-q.workers.dev';
```

(Tylko `t.html`, NIE inne pliki — sędziowie nadal łączą się bezpośrednio z Supabase żeby zapisy były natychmiastowe.)
