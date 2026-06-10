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
-- Indexes (foreign keys + common filters)
-- ----------------------------------------------------------------------------

create index if not exists parts_category_idx     on parts (category);
create index if not exists parts_supplier_id_idx   on parts (supplier_id);
create index if not exists boiler_models_supplier_idx on boiler_models (supplier_id);
create index if not exists part_models_model_id_idx on part_models (model_id);

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

alter table suppliers     enable row level security;
alter table boiler_models enable row level security;
alter table parts         enable row level security;
alter table part_models   enable row level security;

-- Public read
drop policy if exists "public read" on suppliers;
create policy "public read" on suppliers     for select using (true);

drop policy if exists "public read" on boiler_models;
create policy "public read" on boiler_models for select using (true);

drop policy if exists "public read" on parts;
create policy "public read" on parts         for select using (true);

drop policy if exists "public read" on part_models;
create policy "public read" on part_models   for select using (true);

-- Authenticated write (insert / update / delete)
drop policy if exists "admin write" on suppliers;
create policy "admin write" on suppliers     for all to authenticated using (true) with check (true);

drop policy if exists "admin write" on boiler_models;
create policy "admin write" on boiler_models for all to authenticated using (true) with check (true);

drop policy if exists "admin write" on parts;
create policy "admin write" on parts         for all to authenticated using (true) with check (true);

drop policy if exists "admin write" on part_models;
create policy "admin write" on part_models   for all to authenticated using (true) with check (true);

-- ----------------------------------------------------------------------------
-- OPTIONAL: server-side full-text search RPC.
--
-- Not used by the v1 frontend (which fetches the catalog once and scores results
-- client-side -- instant, with highlighting, fine up to a couple thousand parts).
-- When the catalog grows large, switch finder.js to:
--     supabase.rpc('search_parts', { query: '...' })
-- and add pagination. Kept here so the upgrade path is in place.
-- ----------------------------------------------------------------------------

create or replace function search_parts(query text)
returns setof parts_with_details
language sql
stable
security invoker
set search_path = public
as $$
  select *
  from parts_with_details
  where query is null
     or query = ''
     or to_tsvector(
          'english',
          coalesce(part_number, '') || ' ' ||
          coalesce(name, '')        || ' ' ||
          coalesce(category, '')    || ' ' ||
          coalesce(supplier, '')    || ' ' ||
          coalesce(description, '') || ' ' ||
          coalesce(array_to_string(keywords, ' '), '') || ' ' ||
          coalesce(array_to_string(models, ' '), '')
        ) @@ websearch_to_tsquery('english', query)
     or part_number ilike '%' || query || '%';
$$;
