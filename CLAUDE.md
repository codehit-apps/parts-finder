# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A boiler-parts catalog: a public search "finder" plus a login-gated admin CRUD
panel. Frontend is **plain HTML/CSS/vanilla JS with no build step**, hosted on
GitHub Pages; backend is **Supabase** (Postgres + Auth + the auto-generated
PostgREST API). The Supabase client is imported from a CDN as an ES module, so the
whole app deploys as static files. Repo: `codehit-apps/parts-finder` (public, so
GitHub Pages works on the free plan).

## Architecture (the big picture)

- **Two frontends, one backend.** `index.html` + `assets/js/finder.js` is the
  public read-only finder; `admin/index.html` + `assets/js/admin.js` is the admin
  panel. Both import the single configured client from
  `assets/js/supabase-client.js` (which reads `assets/js/config.js`) and share the
  design tokens / component CSS in `assets/css/finder.css`.

- **Security lives entirely in the database, never the client.** The anon key in
  `config.js` is public by design (it is committed and shipped to every visitor);
  all enforcement is Row Level Security in `supabase/schema.sql`. Treat the
  frontend as untrusted: any guard that matters must be an RLS policy or Supabase
  setting, not client code. Never add the `service_role` key to the frontend.

- **Write access = the `admins` allowlist.** RLS gives `public read` to everyone
  and write only to authenticated users who pass `is_admin()` (membership in the
  `admins` table). This is defense-in-depth on top of Supabase having sign-ups
  disabled. `admins` has RLS enabled with **no policies**, so it is unreachable
  via the API and is managed only from the SQL editor. The admin UI calls the
  `is_admin` RPC after login and signs out non-admins.

- **Search-first + server-side pagination (do not regress this).** The finder
  fetches **nothing** on load (zero egress) beyond the tiny `part_categories`
  list for the chips, and shows a prompt. Searching/paging calls the
  `search_parts(query, filter_category)` RPC with `.range()` + `{ count: 'exact' }`,
  returning one page (12 finder / 20 admin). Ranking (exact part number first) is
  done in Postgres; highlighting is applied client-side on the returned page. Do
  not reintroduce "fetch the whole catalog and filter in JS" - it breaks egress
  and PostgREST's max-rows cap at scale.

- **Normalized data, flattened for reads.** Base tables: `suppliers`,
  `boiler_models`, `parts`, and the `part_models` many-to-many join. The
  `parts_with_details` view flattens these back to a `supplier` string + `models`
  name array per part; both the finder and admin list read through it (via the
  RPC), so no client-side joins are needed. The admin edit form fetches the base
  `parts` row + that part's `part_models` on demand to get the raw foreign keys.

## Commands & local dev

- **Run locally:** `bin/dev` (serves on :8000; `bin/dev 4000` for another port).
  Pages use `fetch`/ES modules, so they must be served over HTTP, not opened as
  `file://`. The script falls back python3 -> php -> npx serve.
- **No build, lint, or test framework.** To sanity-check a JS module's syntax
  (the `import` requires module context), copy it to `.mjs` and run
  `node --check`, e.g. `cp assets/js/finder.js /tmp/f.mjs && node --check /tmp/f.mjs`.
- **Deploy:** push to `main`; GitHub Pages rebuilds automatically. Verify with
  `gh api repos/codehit-apps/parts-finder/pages/builds/latest --jq .status`.

## Working with the database

- The schema/seed live in `supabase/schema.sql` and `supabase/seed.sql`. They are
  applied by **pasting into the Supabase SQL editor** - there is no migration
  runner here. Both are written to be re-runnable (idempotent / `create or replace`).
- **After editing `schema.sql` you must re-run it in the SQL editor** for PostgREST
  to pick up the change; the deployed frontend talks to whatever is live in the
  project, not to the file.
- **`create or replace view` cannot drop or reorder columns** (Postgres error
  42P16). To change `parts_with_details`'s shape, `drop view ... cascade` first
  (which also drops `search_parts`, recreated later in the file) - or only append
  columns.
- You can probe the live project read-only with the public anon key from
  `config.js` against `https://<ref>.supabase.co/rest/v1/...` to verify RLS
  behavior (e.g. confirm anon writes return `401 / 42501`).

### Creating an admin user

A login alone grants nothing - the account must also be in the `admins` table.
Two steps:

1. **Create the auth account:** Supabase dashboard -> Authentication -> Users ->
   Add user (email + password). (Public sign-up is disabled, so accounts are made
   here, not via the app.)
2. **Authorize it** in the SQL editor (this is the only way in - the `admins`
   table is not writable through the API):

   ```sql
   insert into admins (user_id, email)
   select id, email from auth.users where email = 'you@company.com'
   on conflict (user_id) do nothing;
   ```

Then log in at `/admin/`. A user who is authenticated but not in `admins` is
signed out by the panel with "not authorized", and RLS blocks their writes
regardless. To revoke an admin, delete their row from `admins` (and optionally the
auth user).

## Conventions specific to this repo

- Match the existing **vanilla, framework-free** JS style in `finder.js` /
  `admin.js` (`var`, function expressions, manual DOM string-building, event
  delegation). Do not introduce React/Vue/Svelte, a bundler, or npm dependencies -
  the no-build static-deploy model is intentional.
- The industrial theme is driven by CSS custom properties in `:root` in
  `finder.css`; admin styles build on those tokens in `admin.css`. Reuse them
  rather than hard-coding colors/fonts.
- Prices are display-labeled `USD` in the UI; the DB stores plain numbers.

See `README.md` for the full Supabase setup, deploy, and security/egress writeup.
