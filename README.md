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
  seed.sql              Starter catalog (100 parts across 7 brands)
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
5. Verify: `select count(*) from parts_with_details;` should return 100, each row
   with a `supplier` and a `models` array.

### 2. Lock down auth (admins only)

1. **Authentication -> Providers -> Email**: keep enabled.
2. **Authentication -> Sign In / Providers** (Auth settings): turn **OFF**
   "Allow new users to sign up". With the anon key public, an open signup lets
   anyone register and reach `authenticated`; closing it is the front-door lock.
3. **Authentication -> Users -> Add user**: create your staff login(s) with an
   email + password. This is what you log into `/admin/` with.
4. **Authorize that login as an admin.** Writing is gated by the `admins`
   allowlist (defense-in-depth: a self-registered user is NOT an admin even if
   signups are left on). In the SQL editor run, for each admin:

   ```sql
   insert into admins (user_id, email)
   select id, email from auth.users where email = 'you@company.com'
   on conflict (user_id) do nothing;
   ```

   A logged-in user who is not in `admins` is signed out by the panel and cannot
   write (RLS blocks it regardless).
5. **Project Settings -> API -> Max rows**: set a cap (e.g. `1000`). This bounds
   any single response so nobody can pull the whole table in one request by
   crafting a huge range - protects egress and prevents bulk scraping.

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
`file://`). Use the helper script:

```
bin/dev          # serves on http://localhost:8000
bin/dev 4000     # or a custom port
```

It prints the finder (`/`) and admin (`/admin/`) URLs. (`bin/dev` uses `python3`,
falling back to `php` or `npx serve`.)

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

## Search & pagination (scales to large catalogs)

Both the public finder and the admin table are **search-first and paginated
server-side**, so the browser never downloads the whole catalog:

- The public finder fetches **nothing** on load (zero egress) - just the small
  `part_categories` list for the chips. It shows a search prompt until the visitor
  searches or picks a category.
- Searching/paging calls the `search_parts(query, filter_category)` RPC with
  `.range()` + `{ count: 'exact' }`, returning one page (12 on the finder, 20 in
  admin) per request. Ranking (exact part number first, then name) is done in
  Postgres; result highlighting is applied client-side on the returned page.
- This avoids PostgREST's max-rows truncation, keeps payloads at kilobytes, and
  renders only a page of cards/rows at a time - comfortable at 10k+ parts.

Search itself is index-backed so it does not sequentially scan as the catalog
grows:

- A stored generated `tsvector` column (`parts.search_doc`) over each part's own
  text, with a **GIN** index, powers the full-text branch
  (`websearch_to_tsquery`) - stemming and multi-word phrases.
- **`pg_trgm`** trigram GIN indexes on `parts.part_number`, `parts.name`,
  `suppliers.name` and `boiler_models.name` power substring (`ilike '%fragment%'`)
  search, so a partial term like `ven` matches `Air Vent` without a scan.
- `search_parts` gathers matching ids from the base tables as a `UNION` (so each
  branch can use its index) and joins back to `parts_with_details` for the
  returned shape; supplier and model names are matched via their own tables since
  a generated column can only see same-row data.

If you change `schema.sql` (e.g. the RPC), re-run it in the Supabase SQL editor so
PostgREST picks up the new definition.

## Security model

All code (including the anon key) is public, so security lives entirely in the
database and project config -- never in the client. The two threats that matter
for a public static site + Supabase are **data corruption** and **egress abuse**.

### Preventing data corruption (unauthorized writes)

Two independent locks; either alone stops it:

1. **RLS allowlist.** Writes require `to authenticated` AND `is_admin()` -- i.e.
   membership in the `admins` table. A self-registered user is authenticated but
   not an admin, so they cannot write. The `admins` table has RLS with no
   policies, so it is unreachable via the API (managed only from the SQL editor /
   service role) -- an attacker cannot add themselves.
2. **Signups disabled** in the dashboard, so the public cannot create accounts at
   all.

Reads are intentionally public (it's a public catalog). The `service_role` key
(which bypasses RLS) is never shipped to the frontend.

### Preventing egress draining

- **Search-first + server pagination**: zero rows fetched on load; each request
  returns one small page.
- **Max rows cap** (dashboard, e.g. 1000): bounds *any* single response, so a
  crafted `.range(0, 9999999)` still can't pull the whole table - this is the
  key server-side guard, since a direct API caller ignores the frontend.
- For a hard guarantee against a determined attacker looping requests, put
  **Cloudflare (free)** in front for per-IP rate limiting + caching, or serve the
  public catalog as a cached static JSON snapshot from the Pages CDN (Supabase
  egress then ~0). On the free tier, exceeding limits pauses/throttles the project
  rather than billing you; on Pro, set a spend cap.

### Other

- The `parts_with_details` view uses `security_invoker = on` so it honors the
  base tables' RLS; `is_admin()` is `security definer` only to read the allowlist
  and return a boolean.

### SQL injection / browser console

The anon key is visible in the browser by design - protection comes from RLS, not
from hiding the key. The database is structurally safe against injection:

- The client never sends raw SQL. `supabase-js` calls go through the PostgREST
  API, which binds every value as a parameter. Pasting `'; DROP TABLE parts; --`
  into a search field is treated as a literal string, not executable SQL.
- A console attacker using the anon key can only `SELECT` the public catalog
  (RLS `public read`); they cannot insert/update/delete (those policies require
  `is_admin()`).
- The `service_role` key (which bypasses RLS) is never shipped to the frontend.
- The function taking free text, `search_parts(query, filter_category)`, receives
  its arguments as bound parameters; `websearch_to_tsquery` parses them safely and
  the `ilike` pattern is built as a string value, not SQL. Functions pin
  `search_path` to block search_path hijacking.

## Follow-ups (out of scope for v1)

- Part image uploads (Supabase Storage).
- Per-user admin roles / audit log.
- Server-side paginated search (RPC is stubbed and ready).
