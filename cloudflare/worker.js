// ═══════════════════════════════════════════════════════════════
// MSS API Proxy + Cache (Cloudflare Worker)
// ═══════════════════════════════════════════════════════════════
//
// Cel: zmniejszyc obciazenie Supabase Free tier gdy duzo viewerow
// otwiera tablice wynikow jednoczesnie. Worker cache'uje GET na
// /rest/v1/* przez 10 sekund. Inne metody (POST/PATCH/DELETE) i
// inne endpointy (auth, functions, realtime) przekierowane bez
// cache.
//
// Deploy: Cloudflare Dashboard -> Workers -> Create -> wklej ten
// kod -> Deploy. Otrzymasz URL typu mss-api.<nazwa>.workers.dev.
// Potem w t.html podmieniasz SUPABASE_URL na ten Worker URL.
//
// CORS: Supabase REST sam dodaje Access-Control-Allow-Origin: *,
// wiec po prostu przekazujemy headers. OPTIONS preflight handled
// przez "preflightu nie ma" - pass-through dziala.
// ═══════════════════════════════════════════════════════════════

const SUPABASE_HOST = 'yrgkgzrpfemmthscrprf.supabase.co';
const CACHE_SECONDS = 10;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // Buduj URL docelowy w Supabase
    const target = 'https://' + SUPABASE_HOST + url.pathname + url.search;

    // Czy cachowalne?
    // - tylko GET
    // - tylko /rest/v1/* (PostgREST data API)
    // - nie /rest/v1/rpc/* (RPC calls, moga zwrocic rozne wartosci per call)
    const isData = url.pathname.startsWith('/rest/v1/') && !url.pathname.startsWith('/rest/v1/rpc/');
    const cacheable = request.method === 'GET' && isData;
    // Tabele stanu z lista zawodnikow — redagujemy stopnie (rank) gdy showRanks != true
    const isStateTable = /\/rest\/v1\/(patrol_state|osf_state|app_state)\b/.test(url.pathname);

    if (cacheable) {
      // Spróbuj z cache
      const cache = caches.default;
      const cacheKey = new Request(target, { method: 'GET' });
      let cached = await cache.match(cacheKey);
      if (cached) {
        // Dodaj naglowek ze cache hit (do diagnostyki)
        const resp = new Response(cached.body, cached);
        resp.headers.set('X-MSS-Cache', 'HIT');
        return resp;
      }

      // Cache miss → pobierz ze Supabase
      // Przekazujemy headers (apikey, Authorization, itd)
      const upstreamReq = new Request(target, {
        method: 'GET',
        headers: filterRequestHeaders(request.headers),
      });
      const upstream = await fetch(upstreamReq);

      // Tabele stanu: zredaguj stopnie (rank) gdy showRanks != true, ZANIM trafi do cache.
      // Dzieki temu uczestnicy (t.html -> Worker) nie dostaja stopni nawet w surowym JSON.
      // Sedziowie ida bezposrednio do Supabase (z pominieciem Workera), wiec widza stopnie.
      if (isStateTable && (upstream.headers.get('content-type') || '').includes('application/json')) {
        const text = redactRanksIfHidden(await upstream.text());
        const headers = new Headers(upstream.headers);
        headers.delete('content-encoding');
        headers.delete('content-length');
        headers.set('Cache-Control', 'public, max-age=' + CACHE_SECONDS);
        headers.set('X-MSS-Cache', 'MISS');
        const resp = new Response(text, { status: upstream.status, statusText: upstream.statusText, headers });
        ctx.waitUntil(cache.put(cacheKey, resp.clone()));
        return resp;
      }

      // Klonuj odpowiedź zeby modyfikowac headers
      const cloned = new Response(upstream.body, upstream);
      cloned.headers.set('Cache-Control', 'public, max-age=' + CACHE_SECONDS);
      cloned.headers.set('X-MSS-Cache', 'MISS');

      // Zapisz w cache (klonuje ponownie bo cloned.body sie konsumuje)
      const toCache = cloned.clone();
      ctx.waitUntil(cache.put(cacheKey, toCache));

      return cloned;
    }

    // Niecachowalne → po prostu proxy
    // Przekierowuje pelne headers + body
    const upstreamReq = new Request(target, {
      method: request.method,
      headers: filterRequestHeaders(request.headers),
      body: ['GET', 'HEAD'].includes(request.method) ? undefined : request.body,
    });
    const upstream = await fetch(upstreamReq);
    const passthru = new Response(upstream.body, upstream);
    passthru.headers.set('X-MSS-Cache', 'BYPASS');
    return passthru;
  }
};

// Zeruje pole `rank` zawodnikow w odpowiedzi *_state, chyba ze showRanks=true.
// showRanks: patrol/osf -> state_json.cfg.showRanks, wieloboj -> state_json.setup.showRanks.
// Bezpieczna domyslnosc: brak flagi = ukryte (redagujemy). Bledy nie psuja API (zwroc oryginal).
function redactRanksIfHidden(text) {
  try {
    const data = JSON.parse(text);
    const rows = Array.isArray(data) ? data : [data];
    for (const row of rows) {
      if (!row || typeof row !== 'object') continue;
      let sj = row.state_json;
      const wasString = (typeof sj === 'string');
      if (wasString) { try { sj = JSON.parse(sj); } catch (e) { continue; } }
      if (!sj || typeof sj !== 'object') continue;
      const show = (sj.cfg && sj.cfg.showRanks === true) || (sj.setup && sj.setup.showRanks === true);
      if (show) continue;
      if (Array.isArray(sj.athletes)) {
        for (const a of sj.athletes) { if (a && typeof a === 'object' && a.rank) a.rank = ''; }
      }
      row.state_json = wasString ? JSON.stringify(sj) : sj;
    }
    return JSON.stringify(data);
  } catch (e) {
    return text;
  }
}

// Usun niektore problematyczne headers Cloudflare/HTTP/2 przed forward
function filterRequestHeaders(headers) {
  const skip = new Set(['host', 'cf-connecting-ip', 'cf-ipcountry', 'cf-ray', 'cf-visitor', 'x-forwarded-for', 'x-forwarded-proto', 'x-real-ip']);
  const out = new Headers();
  for (const [k, v] of headers.entries()) {
    if (!skip.has(k.toLowerCase())) out.set(k, v);
  }
  return out;
}
