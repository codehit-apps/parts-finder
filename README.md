# Parts Finder

A boiler spares catalog with public search and an admin CRUD panel.

- **Frontend**: static HTML/CSS/vanilla JS (no build step), hosted on GitHub Pages.
- **Backend**: Supabase (PostgreSQL + Auth + auto REST API).
- **Public site**: read-only parts finder (search by part number, name, keyword,
  fault code).
- **Admin panel** (`/admin/`): login-gated create / edit / delete of parts,
  suppliers and boiler models.

The Supabase client is loaded from a CDN as an ES module, so the whole thing
deploys as plain files - just push to GitHub.

## Repository layout

```
index.html              Public parts finder
admin/index.html        Admin panel (login + CRUD)
assets/
  css/finder.css        Shared industrial theme + finder styles
  css/admin.css         Admin panel styles
  js/config.js          Supabase URL + anon key  <-- you edit this
  js/supabase-client.js Shared Supabase client
  js/finder.js          Public search engine + rendering
  js/admin.js           Auth guard + CRUD logic
supabase/
  schema.sql            Tables, view, RLS policies, indexes, optional search RPC
  seed.sql              Starter catalog (the 16 demo parts)
```

## Data model (normalized)

```
suppliers  1 --- *  boiler_models
suppliers  1 --- *  parts
parts      * --- *  boiler_models   (via the part_models join table)
```

`category` and `stock` are kept as simple columns on `parts` (small fixed
vocabularies). `keywords` is a `text[]` used only for search.

The public finder reads from the `parts_with_details` view, which flattens the
joins back into a `supplier` string + `models` array per part.

## Setup

### 1. Create the Supabase project

1. Sign in at https://supabase.com and create a new project. Pick a region close
   to your users. The free tier (500 MB database) is plenty - this catalog is a
   few MB even at tens of thousands of parts.
2. When the project is ready, open **SQL Editor -> New query**.
3. Paste the contents of `supabase/schema.sql`, run it.
4. New query again, paste `supabase/seed.sql`, run it. (Re-runnable - it skips
   rows that already exist.)
5. Verify: `select * from parts_with_details;` should return 16 rows, each with a
   `supplier` and a `models` array.

### 2. Lock down auth (admins only)

1. **Authentication -> Providers -> Email**: keep enabled.
2. **Authentication -> Sign In / Providers** (Auth settings): turn **OFF**
   "Allow new users to sign up". This stops the public from self-registering -
   the admin panel grants write access to any authenticated user, so sign-ups
   must be closed.
3. **Authentication -> Users -> Add user**: create your staff login(s) with an
   email + password. This is what you log into `/admin/` with.

### 3. Wire up the frontend

Edit `assets/js/config.js` with your project's values from
**Project Settings -> API**:

```js
window.SUPABASE_URL = "https://YOUR-PROJECT.supabase.co";
window.SUPABASE_ANON_KEY = "YOUR-ANON-PUBLIC-KEY";   // the "anon / public" key
```

Both values are public and safe to commit. **Never** put the `service_role` key
here - it bypasses Row Level Security.

### 4. Run locally

The pages use `fetch`/modules, so they must be served over HTTP (not opened as
`file://`):

```
python3 -m http.server 8000
```

Then open http://localhost:8000/ (finder) and http://localhost:8000/admin/
(admin).

## Deploy to GitHub Pages

Repo: `git@github.com:codehit-apps/parts-finder.git`

```bash
cd boilers
git init
git remote add origin git@github.com:codehit-apps/parts-finder.git
git add .
git commit -m "Parts Finder: Supabase backend + admin CRUD"
git branch -M main
git push -u origin main
```

Then on GitHub: **Settings -> Pages**:
- **Source**: Deploy from a branch
- **Branch**: `main` / `/ (root)` -> Save

Without a custom domain the site will be at:
`https://codehit-apps.github.io/parts-finder/`
(all asset paths are relative, so the project subpath works as-is.)

### Custom domain

1. In **Settings -> Pages -> Custom domain**, enter your domain (e.g.
   `parts.yourcompany.com`) and Save. GitHub creates/updates the `CNAME` file in
   the repo automatically.
2. At your DNS provider:
   - **Subdomain** (e.g. `parts.yourcompany.com`): add a `CNAME` record pointing
     to `codehit-apps.github.io`.
   - **Apex/root** (e.g. `yourcompany.com`): add `A` records to the GitHub Pages
     IPs (`185.199.108.153`, `.109.153`, `.110.153`, `.111.153`) and an `AAAA`
     set if you want IPv6.
3. Wait for DNS to propagate, then tick **Enforce HTTPS**.

No `CNAME` file is committed - setting the custom domain in the Pages settings
creates and manages it for you. (Avoid hand-committing a `CNAME`: GitHub will
auto-assign whatever domain it contains and then fail HTTPS verification until
DNS matches.)

## Scaling the search

v1 fetches the whole catalog once and scores/searches it in the browser -
instant, with highlighting, and fine up to a couple thousand parts. When the
catalog grows larger, switch `loadCatalog()` in `assets/js/finder.js` to the
server-side `search_parts(query)` RPC (already defined in `schema.sql`) and add
pagination, so the browser no longer downloads the entire catalog.

## Security model

- Public visitors use the anon key and can only **read** (RLS `public read`
  policies + `select` grants).
- Writes (insert/update/delete) require an authenticated session (RLS
  `admin write` policies, `to authenticated`).
- "Any authenticated user is an admin." This is safe because public sign-ups are
  disabled and accounts are created manually.
- The `parts_with_details` view uses `security_invoker = on` so it honors the
  base tables' RLS.

### SQL injection / browser console

The anon key is visible in the browser by design - protection comes from RLS, not
from hiding the key. The database is structurally safe against injection:

- The client never sends raw SQL. `supabase-js` calls go through the PostgREST
  API, which binds every value as a parameter. Pasting `'; DROP TABLE parts; --`
  into a search field is treated as a literal string, not executable SQL.
- A console attacker using the anon key can only `SELECT` the public catalog
  (RLS `public read`); they cannot insert/update/delete (those policies are
  `to authenticated`).
- The `service_role` key (which bypasses RLS) is never shipped to the frontend.
- The only function taking free text, `search_parts(query text)`, receives it as
  a bound parameter; `websearch_to_tsquery` parses it safely and the `ilike`
  pattern is built as a string value, not SQL. Functions pin `search_path` to
  block search_path hijacking.

## Follow-ups (out of scope for v1)

- Part image uploads (Supabase Storage).
- Per-user admin roles / audit log.
- Server-side paginated search (RPC is stubbed and ready).
