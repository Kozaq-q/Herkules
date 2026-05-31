// ═══════════════════════════════════════════════════════════════
// MSS — Edge Function: admin-users
// ═══════════════════════════════════════════════════════════════
//
// Backend dla panelu "Sędziowie" w start.html.
// Wymaga roli admin w mss_users.
//
// Actions (POST JSON body { action, ...params }):
//   list                    → lista wszystkich sędziów
//   create  {email, password, display_name, role}  → utworz konto
//   setActive {id, active}  → aktywuj/dezaktywuj
//   updatePassword {id, password}  → reset hasła sędzia
//   updateRole {id, role}   → zmiana admin↔judge
//   delete {id}             → usuń konto na zawsze
//
// ENV (ustawiane automatycznie przez Supabase):
//   SUPABASE_URL
//   SUPABASE_ANON_KEY
//   SUPABASE_SERVICE_ROLE_KEY
// ═══════════════════════════════════════════════════════════════

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Max-Age': '86400',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function errorResponse(err: unknown, status = 400): Response {
  const msg = err instanceof Error ? err.message : String(err);
  console.error('[admin-users]', msg, err);
  return json({ ok: false, error: msg }, status);
}

serve(async (req) => {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return json({ ok: false, error: 'Tylko POST' }, 405);
  }

  // ─── 1. Verify caller is logged in + admin ────────────────────
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return json({ ok: false, error: 'Brak Authorization header' }, 401);
  }

  const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
  const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
  const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  // Klient z tokenem usera — do sprawdzenia kim jest dzwoniacy
  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: { user }, error: userErr } = await userClient.auth.getUser();
  if (userErr || !user) {
    return json({ ok: false, error: 'Sesja nieważna' }, 401);
  }

  // Klient admin — service_role, omija RLS
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Sprawdz czy uzytkownik jest aktywnym adminem w mss_users
  const { data: profile, error: profErr } = await admin
    .from('mss_users')
    .select('id, role, active')
    .eq('id', user.id)
    .maybeSingle();

  if (profErr || !profile) {
    return json({ ok: false, error: 'Brak rekordu w mss_users' }, 403);
  }
  if (!profile.active) {
    return json({ ok: false, error: 'Konto dezaktywowane' }, 403);
  }
  if (profile.role !== 'admin') {
    return json({ ok: false, error: 'Wymagana rola admin' }, 403);
  }

  // ─── 2. Parse action ──────────────────────────────────────────
  let body: any;
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: 'Niepoprawny JSON' }, 400);
  }

  const action = body.action as string;

  try {
    // ─── LIST ──────────────────────────────────────────────────
    if (action === 'list') {
      const { data, error } = await admin
        .from('mss_users')
        .select('id, email, display_name, role, active, created_at, created_by, notes')
        .order('created_at', { ascending: true });
      if (error) throw error;
      return json({ ok: true, users: data || [] });
    }

    // ─── CREATE ────────────────────────────────────────────────
    if (action === 'create') {
      const email = String(body.email || '').trim().toLowerCase();
      const password = String(body.password || '');
      const display_name = String(body.display_name || '').trim();
      const role = body.role === 'admin' ? 'admin' : 'judge';

      if (!email) return json({ ok: false, error: 'Brak emaila' }, 400);
      if (password.length < 8) return json({ ok: false, error: 'Haslo min. 8 znakow' }, 400);

      // Create auth user (auto-confirmed, no email verification)
      const { data: created, error: createErr } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { display_name },
      });

      if (createErr || !created.user) {
        return errorResponse(createErr || new Error('Brak created.user'));
      }

      // Insert into mss_users
      const { error: insertErr } = await admin.from('mss_users').insert({
        id: created.user.id,
        email,
        display_name: display_name || null,
        role,
        active: true,
        created_by: user.id,
      });

      if (insertErr) {
        // Rollback auth user
        try { await admin.auth.admin.deleteUser(created.user.id); } catch (_) {}
        return errorResponse(insertErr);
      }

      return json({ ok: true, id: created.user.id, email });
    }

    // ─── SET ACTIVE ────────────────────────────────────────────
    if (action === 'setActive') {
      const id = String(body.id || '');
      const active = Boolean(body.active);
      if (!id) return json({ ok: false, error: 'Brak id' }, 400);
      // Zabroń dezaktywacji samego siebie
      if (id === user.id && !active) {
        return json({ ok: false, error: 'Nie mozesz dezaktywowac swojego konta' }, 400);
      }
      const { error } = await admin.from('mss_users').update({ active }).eq('id', id);
      if (error) throw error;
      return json({ ok: true });
    }

    // ─── UPDATE PASSWORD ───────────────────────────────────────
    if (action === 'updatePassword') {
      const id = String(body.id || '');
      const password = String(body.password || '');
      if (!id) return json({ ok: false, error: 'Brak id' }, 400);
      if (password.length < 8) return json({ ok: false, error: 'Haslo min. 8 znakow' }, 400);
      const { error } = await admin.auth.admin.updateUserById(id, { password });
      if (error) throw error;
      return json({ ok: true });
    }

    // ─── UPDATE ROLE ───────────────────────────────────────────
    if (action === 'updateRole') {
      const id = String(body.id || '');
      const role = body.role === 'admin' ? 'admin' : 'judge';
      if (!id) return json({ ok: false, error: 'Brak id' }, 400);
      // Zabron zmiany swojej roli (zostaw sobie admin)
      if (id === user.id && role !== 'admin') {
        return json({ ok: false, error: 'Nie mozesz odebrac sobie roli admin' }, 400);
      }
      const { error } = await admin.from('mss_users').update({ role }).eq('id', id);
      if (error) throw error;
      return json({ ok: true });
    }

    // ─── UPDATE NAME ───────────────────────────────────────────
    if (action === 'updateName') {
      const id = String(body.id || '');
      const display_name = String(body.display_name || '').trim() || null;
      if (!id) return json({ ok: false, error: 'Brak id' }, 400);
      const { error } = await admin.from('mss_users').update({ display_name }).eq('id', id);
      if (error) throw error;
      return json({ ok: true });
    }

    // ─── DELETE ────────────────────────────────────────────────
    if (action === 'delete') {
      const id = String(body.id || '');
      if (!id) return json({ ok: false, error: 'Brak id' }, 400);
      if (id === user.id) {
        return json({ ok: false, error: 'Nie mozesz usunac swojego konta' }, 400);
      }
      // ON DELETE CASCADE w mss_users.id -> auth.users.id usunie tez mss_users
      const { error } = await admin.auth.admin.deleteUser(id);
      if (error) throw error;
      return json({ ok: true });
    }

    return json({ ok: false, error: 'Nieznana akcja: ' + action }, 400);
  } catch (e) {
    return errorResponse(e, 500);
  }
});
