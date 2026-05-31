// ═══════════════════════════════════════════════════════════════
// MSS Auth — wspólny moduł autoryzacji dla wszystkich paneli
// ═══════════════════════════════════════════════════════════════
//
// Użycie w pliku HTML:
//   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
//   <script src="auth.js"></script>
//   <script>
//     MSS_AUTH.init().then(ok => {
//       if (ok) showApp();   // user zalogowany i aktywny w mss_users
//       // jeśli !ok → overlay logowania widoczny, czekamy na user input
//     });
//   </script>
//
// Po zalogowaniu auth.js sam pokaże/ukryje overlay i zawoła Twoje
// `showApp` przez resolved promise (lub event 'mss-auth-signed-in').
//
// Sprawdzenie roli: MSS_AUTH.isAdmin() / MSS_AUTH.isLoggedIn()
// Wylogowanie:      MSS_AUTH.signOut()
// Klient Supabase:  MSS_AUTH.getSupabase()  (use TEN client, nie twórz drugiego!)
//
// ═══════════════════════════════════════════════════════════════

window.MSS_AUTH = (function() {
  'use strict';

  const SUPABASE_URL = 'https://yrgkgzrpfemmthscrprf.supabase.co';
  const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlyZ2tnenJwZmVtbXRoc2NycHJmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM0MjYxMTUsImV4cCI6MjA4OTAwMjExNX0.CKuLNRCyolMf6nPiWgOcE8j76Isjwc12bwQmIY5E8Do';

  let _sb = null;
  let _user = null;
  let _profile = null;     // mss_users row
  let _initialized = false;
  let _initPromise = null;

  // ─── Klient Supabase (singleton) ─────────────────────────────
  function getSupabase() {
    if (!_sb) {
      if (typeof supabase === 'undefined' || !supabase.createClient) {
        throw new Error('MSS_AUTH: brak @supabase/supabase-js — zaladuj CDN przed auth.js');
      }
      _sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
        auth: {
          persistSession: true,
          autoRefreshToken: true,
          detectSessionInUrl: false,
          storageKey: 'mss-auth-token',  // wspólny klucz dla wszystkich plików MSS
        },
      });
    }
    return _sb;
  }

  // ─── CSS overlay (wstrzykiwane raz) ──────────────────────────
  const CSS = `
    #mss-auth-overlay {
      position: fixed; inset: 0; z-index: 99999;
      background: #0d0f0f;
      display: flex; flex-direction: column;
      align-items: center; justify-content: center;
      padding: 24px;
      font-family: 'Barlow', sans-serif;
      color: #f0f2f2;
    }
    #mss-auth-overlay .mss-auth-logo {
      font-family: 'Barlow Condensed', sans-serif;
      font-size: 52px; font-weight: 800; letter-spacing: 4px;
      text-transform: uppercase; color: #e8d44d;
      line-height: 1; margin-bottom: 6px;
    }
    #mss-auth-overlay .mss-auth-sub {
      font-family: 'JetBrains Mono', monospace;
      font-size: 11px; color: #8a9898; letter-spacing: 2px;
      text-transform: uppercase; margin-bottom: 44px;
    }
    #mss-auth-overlay .mss-auth-box {
      background: #141717; border: 1px solid #3d4646;
      border-radius: 8px; padding: 32px;
      width: 100%; max-width: 380px;
    }
    #mss-auth-overlay .mss-auth-title {
      font-family: 'Barlow Condensed', sans-serif;
      font-size: 13px; font-weight: 700; letter-spacing: 2px;
      text-transform: uppercase; color: #8a9898;
      margin-bottom: 18px; text-align: center;
    }
    #mss-auth-overlay .mss-auth-field { margin-bottom: 10px; }
    #mss-auth-overlay .mss-auth-label {
      display: block;
      font-family: 'Barlow Condensed', sans-serif;
      font-size: 11px; font-weight: 700; letter-spacing: 1.5px;
      text-transform: uppercase; color: #8a9898;
      margin-bottom: 4px;
    }
    #mss-auth-overlay .mss-auth-input {
      width: 100%; background: #1c2020; border: 1px solid #3d4646;
      border-radius: 4px; color: #f0f2f2;
      padding: 11px 14px; font-family: 'JetBrains Mono', monospace;
      font-size: 14px; transition: border-color .12s, background .12s;
    }
    #mss-auth-overlay .mss-auth-input:focus {
      outline: none; border-color: #e8d44d; background: #232828;
    }
    #mss-auth-overlay .mss-auth-input.error {
      border-color: #e05555 !important; animation: mssAuthShake .3s;
    }
    #mss-auth-overlay .mss-auth-btn {
      width: 100%; margin-top: 14px; padding: 12px;
      font-family: 'Barlow Condensed', sans-serif;
      font-size: 14px; font-weight: 800; letter-spacing: 2px;
      text-transform: uppercase; background: #e8d44d; color: #111;
      border: none; border-radius: 4px; cursor: pointer;
      transition: background .12s, opacity .12s;
    }
    #mss-auth-overlay .mss-auth-btn:hover { background: #b5a33a; }
    #mss-auth-overlay .mss-auth-btn:disabled {
      opacity: .55; cursor: wait;
    }
    #mss-auth-overlay .mss-auth-err {
      font-size: 12px; color: #e05555; margin-top: 10px;
      text-align: center; min-height: 16px;
      font-family: 'JetBrains Mono', monospace;
    }
    #mss-auth-overlay .mss-auth-hint {
      font-size: 11px; color: #8a9898; margin-top: 20px;
      text-align: center; font-family: 'JetBrains Mono', monospace;
      line-height: 1.6;
    }
    @keyframes mssAuthShake {
      0%,100% { transform: translateX(0); }
      25% { transform: translateX(-7px); }
      75% { transform: translateX(7px); }
    }

    /* Forbidden banner — gdy session aktywna ale save odmawia (RLS) */
    #mss-auth-forbidden {
      position: fixed; top: 0; left: 0; right: 0; z-index: 99998;
      background: #e05555; color: #fff;
      padding: 10px 18px; text-align: center;
      font-family: 'Barlow Condensed', sans-serif;
      font-size: 13px; font-weight: 700; letter-spacing: 1px;
      text-transform: uppercase;
      box-shadow: 0 2px 8px rgba(0,0,0,.3);
    }
    #mss-auth-forbidden a {
      color: #fff; text-decoration: underline; margin-left: 12px;
    }
  `;

  function _injectCSS() {
    if (document.getElementById('mss-auth-css')) return;
    const style = document.createElement('style');
    style.id = 'mss-auth-css';
    style.textContent = CSS;
    document.head.appendChild(style);
  }

  // ─── Overlay HTML ────────────────────────────────────────────
  function _injectOverlay() {
    if (document.getElementById('mss-auth-overlay')) return;
    const div = document.createElement('div');
    div.id = 'mss-auth-overlay';
    div.style.display = 'none';
    div.innerHTML = `
      <div class="mss-auth-logo">⬡ MSS</div>
      <div class="mss-auth-sub">Military Sports System</div>
      <div class="mss-auth-box">
        <div class="mss-auth-title">Logowanie sędziego</div>
        <div class="mss-auth-field">
          <label class="mss-auth-label" for="mss-auth-email">Email / login</label>
          <input class="mss-auth-input" type="email" id="mss-auth-email"
                 autocomplete="username" placeholder="np. jan@mss.local" />
        </div>
        <div class="mss-auth-field">
          <label class="mss-auth-label" for="mss-auth-pw">Hasło</label>
          <input class="mss-auth-input" type="password" id="mss-auth-pw"
                 autocomplete="current-password" placeholder="••••••••" />
        </div>
        <div class="mss-auth-err" id="mss-auth-err"></div>
        <button class="mss-auth-btn" id="mss-auth-btn" type="button">Zaloguj →</button>
        <div class="mss-auth-hint">
          Brak konta? Skontaktuj się z głównym sędzią /<br>administratorem zawodów.
        </div>
      </div>
    `;
    document.body.appendChild(div);

    const emailEl = document.getElementById('mss-auth-email');
    const pwEl    = document.getElementById('mss-auth-pw');
    const btnEl   = document.getElementById('mss-auth-btn');
    const errEl   = document.getElementById('mss-auth-err');

    btnEl.addEventListener('click', _handleLogin);
    emailEl.addEventListener('keydown', e => { if (e.key === 'Enter') pwEl.focus(); });
    pwEl.addEventListener('keydown', e => { if (e.key === 'Enter') _handleLogin(); });
  }

  function _showOverlay() {
    const el = document.getElementById('mss-auth-overlay');
    if (el) {
      el.style.display = 'flex';
      setTimeout(() => {
        const emailEl = document.getElementById('mss-auth-email');
        if (emailEl && !emailEl.value) emailEl.focus();
        else {
          const pwEl = document.getElementById('mss-auth-pw');
          if (pwEl) pwEl.focus();
        }
      }, 80);
    }
  }

  function _hideOverlay() {
    const el = document.getElementById('mss-auth-overlay');
    if (el) el.style.display = 'none';
  }

  function _setError(msg) {
    const errEl = document.getElementById('mss-auth-err');
    const emailEl = document.getElementById('mss-auth-email');
    const pwEl = document.getElementById('mss-auth-pw');
    if (errEl) errEl.textContent = msg || '';
    if (msg) {
      if (pwEl) { pwEl.classList.add('error'); }
      setTimeout(() => {
        if (pwEl) pwEl.classList.remove('error');
      }, 800);
    }
  }

  async function _handleLogin() {
    const emailEl = document.getElementById('mss-auth-email');
    const pwEl = document.getElementById('mss-auth-pw');
    const btnEl = document.getElementById('mss-auth-btn');
    const email = (emailEl.value || '').trim().toLowerCase();
    const password = pwEl.value || '';

    if (!email) { _setError('Podaj email / login'); emailEl.focus(); return; }
    if (!password) { _setError('Podaj hasło'); pwEl.focus(); return; }

    btnEl.disabled = true;
    btnEl.textContent = 'Loguję...';
    _setError('');

    try {
      await signIn(email, password);
      // success — signIn już wczytuje profil i resetuje stany
      _hideOverlay();
      pwEl.value = '';
      // emit event żeby strona mogła zareagować (np. showApp)
      window.dispatchEvent(new CustomEvent('mss-auth-signed-in', {
        detail: { user: _user, profile: _profile }
      }));
    } catch (e) {
      const msg = (e && e.message) || 'Błąd logowania';
      // przyjazne komunikaty
      if (/invalid login|invalid_credentials|invalid_grant/i.test(msg)) {
        _setError('Nieprawidłowy email lub hasło');
      } else if (/network|fetch|failed to fetch/i.test(msg)) {
        _setError('Brak połączenia z serwerem');
      } else if (/uprawnie|active|whitelist/i.test(msg)) {
        _setError(msg);
      } else {
        _setError(msg);
      }
    } finally {
      btnEl.disabled = false;
      btnEl.textContent = 'Zaloguj →';
    }
  }

  // ─── Profile loader (z cache offline) ────────────────────────
  const PROFILE_CACHE_KEY = 'mss-auth-profile-cache';

  function _restoreCachedProfile() {
    try {
      const raw = localStorage.getItem(PROFILE_CACHE_KEY);
      if (!raw) return null;
      const obj = JSON.parse(raw);
      if (_user && obj && obj.id === _user.id) {
        _profile = obj;
        return obj;
      }
    } catch (_) {}
    return null;
  }

  function _cacheProfile(p) {
    try {
      if (p) localStorage.setItem(PROFILE_CACHE_KEY, JSON.stringify(p));
      else localStorage.removeItem(PROFILE_CACHE_KEY);
    } catch (_) {}
  }

  async function _loadProfile() {
    if (!_user) { _profile = null; _cacheProfile(null); return null; }
    try {
      const sb = getSupabase();
      const { data, error } = await sb
        .from('mss_users')
        .select('id, email, display_name, role, active')
        .eq('id', _user.id)
        .maybeSingle();
      if (error) {
        console.warn('[MSS_AUTH] loadProfile error', error);
        // Sieciowy blad/timeout: nie kasuj cache, zostaw stale (offline)
        return _profile;
      }
      _profile = data || null;
      _cacheProfile(_profile);
      return _profile;
    } catch (e) {
      console.warn('[MSS_AUTH] loadProfile exception (sieciowy?)', e);
      // Tez nie kasuj cache
      return _profile;
    }
  }

  // ─── Public API ──────────────────────────────────────────────
  async function signIn(email, password) {
    const sb = getSupabase();
    const { data, error } = await sb.auth.signInWithPassword({ email, password });
    if (error) throw error;
    _user = data.user;
    await _loadProfile();
    if (!_profile) {
      await sb.auth.signOut();
      _user = null;
      throw new Error('Konto nie ma uprawnień do MSS. Skontaktuj się z adminem.');
    }
    if (!_profile.active) {
      await sb.auth.signOut();
      _user = null;
      _profile = null;
      throw new Error('Konto zostało dezaktywowane.');
    }
    return _profile;
  }

  async function signOut() {
    try {
      const sb = getSupabase();
      await sb.auth.signOut();
    } catch (e) {
      console.warn('[MSS_AUTH] signOut error', e);
    }
    _user = null;
    _profile = null;
    _cacheProfile(null);
    location.reload();
  }

  async function init() {
    if (_initPromise) return _initPromise;
    _initPromise = (async () => {
      _injectCSS();
      _injectOverlay();
      const sb = getSupabase();

      // Reakcja na auto-wylogowanie (token rewoke, manual logout w drugiej karcie, etc.)
      sb.auth.onAuthStateChange((event, session) => {
        if (event === 'SIGNED_OUT') {
          _user = null;
          _profile = null;
          _showOverlay();
          window.dispatchEvent(new CustomEvent('mss-auth-signed-out'));
        } else if (event === 'TOKEN_REFRESHED' && session) {
          _user = session.user;
        }
      });

      // Sprawdź czy mamy sesję
      const { data: { session } } = await sb.auth.getSession();
      if (session) {
        _user = session.user;
        // Najpierw probuj cache (dla offline) — i tak _loadProfile go odswiezy
        _restoreCachedProfile();
        await _loadProfile();
        if (_profile && _profile.active) {
          _hideOverlay();
          _initialized = true;
          return true;
        }
        // Sesja jest, ale user dezaktywowany lub brak rekordu — wyloguj
        // (tylko jak udalo sie pobrac profil; offline z _profile=null zostaw)
        if (_profile && !_profile.active) {
          await sb.auth.signOut();
          _user = null;
          _profile = null;
          _cacheProfile(null);
        } else if (!_profile) {
          // Profil nieznany (online + brak rekordu LUB offline+brak cache)
          // — bezpieczniej wylogowac
          await sb.auth.signOut();
          _user = null;
        }
      }

      _showOverlay();
      _initialized = true;
      return false;
    })();
    return _initPromise;
  }

  function isLoggedIn() {
    return !!_user && !!_profile && _profile.active === true;
  }

  function isAdmin() {
    return isLoggedIn() && _profile.role === 'admin';
  }

  function getUser()    { return _user; }
  function getProfile() { return _profile; }

  // ─── Forbidden banner (gdy save odmawia mimo zalogowania) ────
  function showForbiddenBanner(msg) {
    let el = document.getElementById('mss-auth-forbidden');
    if (!el) {
      el = document.createElement('div');
      el.id = 'mss-auth-forbidden';
      document.body.appendChild(el);
    }
    el.innerHTML = (msg || 'Brak uprawnień do zapisu') +
      '<a href="#" id="mss-auth-forbidden-logout">Wyloguj i zaloguj ponownie</a>';
    const link = document.getElementById('mss-auth-forbidden-logout');
    if (link) link.onclick = (e) => { e.preventDefault(); signOut(); };
  }

  function hideForbiddenBanner() {
    const el = document.getElementById('mss-auth-forbidden');
    if (el) el.remove();
  }

  return {
    init,
    getSupabase,
    signIn,
    signOut,
    isLoggedIn,
    isAdmin,
    getUser,
    getProfile,
    showForbiddenBanner,
    hideForbiddenBanner,
  };
})();
