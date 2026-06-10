// ============================================================================
// Shared Supabase client.
//
// Loaded as an ES module (no build step). Imports supabase-js straight from a
// CDN and exports a single configured client used by both the public finder and
// the admin panel.
//
// Requires window.SUPABASE_URL and window.SUPABASE_ANON_KEY to be set first
// (see config.js, which must be included BEFORE any module that imports this).
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

if (!window.SUPABASE_URL || !window.SUPABASE_ANON_KEY ||
    window.SUPABASE_URL.indexOf("YOUR-PROJECT") !== -1) {
  console.error(
    "Supabase is not configured. Edit assets/js/config.js with your project " +
    "URL and anon key (Supabase Dashboard -> Project Settings -> API)."
  );
}

export const supabase = createClient(window.SUPABASE_URL, window.SUPABASE_ANON_KEY);

// True when config.js still holds the placeholder values, so the UI can show a
// friendly "not configured yet" message instead of a raw network error.
export const isConfigured =
  !!window.SUPABASE_URL &&
  !!window.SUPABASE_ANON_KEY &&
  window.SUPABASE_URL.indexOf("YOUR-PROJECT") === -1 &&
  window.SUPABASE_ANON_KEY.indexOf("YOUR-ANON") === -1;
