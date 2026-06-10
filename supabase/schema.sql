-- ============================================================================
-- Parts Finder - database schema (Supabase / PostgreSQL 15+)
--
-- Run this ONCE in the Supabase SQL editor (Dashboard -> SQL Editor -> New query).
-- Then run seed.sql to load the starter catalog.
--
-- Model is normalized:
--   suppliers       1 --- *  boiler_models
--   suppliers       1 --- *  parts
--   parts           * --- *  boiler_models   (via part_models join table)
--
-- The public finder reads from the parts_with_details VIEW, which flattens the
-- joins back into the shape the original demo JSON used (a `supplier` string and
-- a `models` text array), so the client search code needs almost no changes.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Extensions
-- ----------------------------------------------------------------------------

-- pg_trgm powers fast substring (ilike '%fragment%') search via GIN trigram
-- indexes -- e.g. 'ven' -> 'Air Vent' without a sequential scan at scale.
create extension if not exists pg_trgm;

-- ----------------------------------------------------------------------------
-- Tables
-- ----------------------------------------------------------------------------

create table if not exists suppliers (
  id          bigint generated always as identity primary key,
  name        text not null unique,
  created_at  timestamptz not null default now()
);

create table if not exists boiler_models (
  id          bigint generated always as identity primary key,
  name        text not null unique,
  supplier_id bigint references suppliers(id) on delete set null,
  created_at  timestamptz not null default now()
);

create table if not exists parts (
  id           bigint generated always as identity primary key,
  part_number  text not null unique,
  name         text not null,
  category     text not null,
  supplier_id  bigint references suppliers(id) on delete set null,
  price        numeric(10,2),
  stock        text not null default 'in' check (stock in ('in', 'low', 'out')),
  replacement  boolean not null default false,   -- true = free of charge under warranty
  description  text,
  keywords     text[] not null default '{}',     -- search-only metadata
  supersedes   text,                             -- old / superseded part number(s)
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- Many-to-many: one part fits many boiler models; one model has many parts.
create table if not exists part_models (
  part_id  bigint not null references parts(id) on delete cascade,
  model_id bigint not null references boiler_models(id) on delete cascade,
  primary key (part_id, model_id)
);

-- ----------------------------------------------------------------------------
-- Full-text search column
--
-- A STORED generated tsvector over a part's own text (kept in sync automatically
-- by Postgres -- no trigger needed). Indexed with GIN below so full-text queries
-- never scan the table. Generated columns can only reference same-row columns, so
-- supplier and model names are NOT here; search_parts matches those by joining the
-- (small) suppliers / boiler_models tables instead. to_tsvector must use the
-- 2-arg 'english' form -- it is IMMUTABLE, which a generated column requires.
-- ----------------------------------------------------------------------------

-- array_to_string is only STABLE (its volatility is the worst case across all
-- element types), so it cannot be used directly in a generated column. For text[]
-- the result is fully deterministic, so wrap it in an IMMUTABLE function we can
-- use below. (This keeps english stemming on keywords, vs array_to_tsvector which
-- would store them as raw un-stemmed lexemes.)
create or replace function text_array_to_string(arr text[], sep text)
returns text
language sql
immutable
set search_path = public
as $$
  select array_to_string(arr, sep);
$$;

alter table parts
  add column if not exists search_doc tsvector
  generated always as (
    to_tsvector(
      'english',
      coalesce(part_number, '') || ' ' ||
      coalesce(name, '')        || ' ' ||
      coalesce(category, '')    || ' ' ||
      coalesce(description, '') || ' ' ||
      coalesce(text_array_to_string(keywords, ' '), '')
    )
  ) stored;

-- ----------------------------------------------------------------------------
-- Indexes (foreign keys + common filters + search)
-- ----------------------------------------------------------------------------

create index if not exists parts_category_idx     on parts (category);
create index if not exists parts_supplier_id_idx   on parts (supplier_id);
create index if not exists boiler_models_supplier_idx on boiler_models (supplier_id);
create index if not exists part_models_model_id_idx on part_models (model_id);

-- Full-text (websearch_to_tsquery) over each part's own text.
create index if not exists parts_search_doc_idx on parts using gin (search_doc);

-- Trigram indexes for substring (ilike '%fragment%') search. part_number and
-- name are matched directly; supplier and model names are matched through their
-- own tables, so they get trigram indexes too.
create index if not exists parts_part_number_trgm_idx
  on parts using gin (part_number gin_trgm_ops);
create index if not exists parts_name_trgm_idx
  on parts using gin (name gin_trgm_ops);
create index if not exists suppliers_name_trgm_idx
  on suppliers using gin (name gin_trgm_ops);
create index if not exists boiler_models_name_trgm_idx
  on boiler_models using gin (name gin_trgm_ops);

-- ----------------------------------------------------------------------------
-- updated_at maintenance
-- ----------------------------------------------------------------------------

create or replace function set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists parts_set_updated_at on parts;
create trigger parts_set_updated_at
  before update on parts
  for each row execute function set_updated_at();

-- ----------------------------------------------------------------------------
-- Flattened read view for the public finder
--
-- security_invoker = on  => the view runs with the querying user's permissions,
-- so the RLS policies on the base tables apply (PostgreSQL 15+ / Supabase).
-- ----------------------------------------------------------------------------

create or replace view parts_with_details
with (security_invoker = on) as
select
  p.id,
  p.part_number,
  p.name,
  p.category,
  p.price,
  p.stock,
  p.replacement,
  p.description,
  p.keywords,
  p.supersedes,
  p.created_at,
  p.updated_at,
  s.name as supplier,
  coalesce(
    array_agg(bm.name order by bm.name) filter (where bm.name is not null),
    '{}'
  ) as models
from parts p
left join suppliers     s  on s.id = p.supplier_id
left join part_models   pm on pm.part_id = p.id
left join boiler_models bm on bm.id = pm.model_id
group by p.id, s.name;

-- ----------------------------------------------------------------------------
-- Row Level Security
--
-- Public (anon) can READ everything. Only authenticated users may write.
-- Access model is "any authenticated user is an admin" -- this is safe because
-- public sign-ups are DISABLED in the Supabase dashboard and admin accounts are
-- created manually (see README).
-- ----------------------------------------------------------------------------

-- Admin allowlist: ONLY users listed in `admins` may write. Defense-in-depth --
-- even if public sign-ups are accidentally left enabled, a self-registered user
-- is not in this table and cannot modify any data (the worst they get is the
-- read access the public already has). Add an admin from the SQL editor (which
-- bypasses RLS):
--   insert into admins (user_id, email)
--   select id, email from auth.users where email = 'you@company.com';
create table if not exists admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  email      text,
  created_at timestamptz not null default now()
);

-- SECURITY DEFINER so it can read `admins` regardless of that table's RLS and
-- return just a boolean. Used by every write policy and by the admin UI guard.
create or replace function is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from admins where user_id = auth.uid());
$$;

grant execute on function is_admin() to anon, authenticated;

alter table suppliers     enable row level security;
alter table boiler_models enable row level security;
alter table parts         enable row level security;
alter table part_models   enable row level security;
-- `admins` has RLS on with NO policies on purpose: it is unreachable through the
-- anon/authenticated API and is managed only from the SQL editor / service role.
alter table admins        enable row level security;

-- Public read
drop policy if exists "public read" on suppliers;
create policy "public read" on suppliers     for select using (true);

drop policy if exists "public read" on boiler_models;
create policy "public read" on boiler_models for select using (true);

drop policy if exists "public read" on parts;
create policy "public read" on parts         for select using (true);

drop policy if exists "public read" on part_models;
create policy "public read" on part_models   for select using (true);

-- Admin-only write (insert / update / delete). Requires both an authenticated
-- session AND membership in the admins table (is_admin()).
drop policy if exists "admin write" on suppliers;
create policy "admin write" on suppliers     for all to authenticated using (is_admin()) with check (is_admin());

drop policy if exists "admin write" on boiler_models;
create policy "admin write" on boiler_models for all to authenticated using (is_admin()) with check (is_admin());

drop policy if exists "admin write" on parts;
create policy "admin write" on parts         for all to authenticated using (is_admin()) with check (is_admin());

drop policy if exists "admin write" on part_models;
create policy "admin write" on part_models   for all to authenticated using (is_admin()) with check (is_admin());

-- ----------------------------------------------------------------------------
-- Server-side search RPC (used by BOTH the public finder and the admin table).
--
-- Returns rows from parts_with_details, optionally filtered by category, ranked
-- exact-part-number-first then by name. The frontend paginates the result with
-- .range() + { count: 'exact' }, so only one page is ever transferred:
--     supabase.rpc('search_parts', { query, filter_category }, { count: 'exact' })
--             .range(from, to)
-- An empty/null query returns the whole (optionally category-filtered) catalog
-- in name order -- still paginated, so it never downloads everything at once.
-- ----------------------------------------------------------------------------

-- Drop any stale single-argument signature from earlier iterations. A
-- create-or-replace only updates the matching signature, so an old
-- search_parts(text) would linger and make PostgREST calls ambiguous (PGRST203).
drop function if exists search_parts(text);

create or replace function search_parts(query text, filter_category text default null)
returns setof parts_with_details
language sql
stable
security invoker
set search_path = public
as $$
  -- Collect matching part ids from the BASE tables so every predicate can use an
  -- index, then join back to the flattened view for the returned shape. Writing
  -- the OR-branches as a UNION (rather than one big OR over the view) is what lets
  -- the planner use the GIN / trigram indexes instead of a sequential scan.
  with matches as (
    -- Same-row matches on parts: substring on part_number/name (trigram indexes)
    -- and full-text on the stored search_doc (GIN index). An empty/null query
    -- falls through here and returns every (optionally category-filtered) part.
    select p.id
    from parts p
    where (filter_category is null or filter_category = '' or p.category = filter_category)
      and (
        query is null
        or query = ''
        or p.part_number ilike '%' || query || '%'
        or p.name ilike '%' || query || '%'
        or p.search_doc @@ websearch_to_tsquery('english', query)
      )
    union
    -- Supplier-name matches (trigram index on suppliers.name).
    select p.id
    from parts p
    join suppliers s on s.id = p.supplier_id
    where query is not null and query <> ''
      and (filter_category is null or filter_category = '' or p.category = filter_category)
      and s.name ilike '%' || query || '%'
    union
    -- Model-name matches (trigram index on boiler_models.name).
    select pm.part_id as id
    from part_models pm
    join boiler_models bm on bm.id = pm.model_id
    join parts p on p.id = pm.part_id
    where query is not null and query <> ''
      and (filter_category is null or filter_category = '' or p.category = filter_category)
      and bm.name ilike '%' || query || '%'
  )
  select pwd.*
  from parts_with_details pwd
  join matches m on m.id = pwd.id
  order by
    case
      when query is null or query = '' then 0
      when lower(pwd.part_number) = lower(query) then 3       -- exact part number
      when pwd.part_number ilike query || '%' then 2          -- part number prefix
      when pwd.part_number ilike '%' || query || '%' then 1   -- part number fragment
      else 0
    end desc,
    pwd.name asc;
$$;

-- ----------------------------------------------------------------------------
-- Tiny lookup view for the category chips / admin filter.
-- A handful of rows (one per category) with a count -- negligible egress.
-- security_invoker so anon reads through the base table's public-read policy.
-- ----------------------------------------------------------------------------

create or replace view part_categories
with (security_invoker = on) as
select category, count(*)::int as n
from parts
group by category
order by category;
