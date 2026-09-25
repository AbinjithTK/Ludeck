-- Community schema for Ludeck: profiles, published trees, reactions, follows.
--
-- Nothing here is deployed by the chat agent. Apply it with the Supabase CLI
-- yourself (see docs/DEPLOY-PROXY.md for the login flow); this file is the
-- source of truth for what that migration contains.
--
-- PRIVACY -- docs/DECISIONS.md invariant 10. A published tree is world
-- readable. Its per-game payload is TITLE, COVER, STATUS and RATING only, plus
-- the owner's own branch NAME. There is deliberately NO column here for
-- `recommended_by` (who suggested a game) or a source `channel` (whose video it
-- came from): both are real third parties' names and never leave the device.
-- The schema cannot store what it has no column for, which is the invariant
-- enforced one layer below the app's own `PublishedGame` type.
--
-- Row-level security is written INLINE with each table, not bolted on later,
-- because a public table with RLS added "soon" is a public table that leaked in
-- the meantime. Every table below enables RLS in the same statement block that
-- creates it.

-- ---------------------------------------------------------------------------
-- profiles: one public identity per auth user.
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  handle       text not null unique
                 check (handle ~ '^[a-z0-9_]{3,30}$'),
  display_name text not null check (char_length(display_name) between 1 and 40),
  avatar_seed  text,
  created_at   timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Anyone may READ a profile: a public tree link shows its owner's handle and
-- level, so the profile row behind a shared tree must be world readable.
create policy profiles_public_read
  on public.profiles for select
  using (true);

-- You may only create/edit YOUR OWN profile row (id must equal your auth uid).
create policy profiles_self_insert
  on public.profiles for insert
  with check (auth.uid() = id);
create policy profiles_self_update
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- ---------------------------------------------------------------------------
-- published_trees: one row per owner. Existence == currently public.
-- Taking a tree private DELETES the row (and cascades its games/reactions), so
-- an unpublished link 404s rather than lingering as a hidden-but-present tree.
-- ---------------------------------------------------------------------------
create table if not exists public.published_trees (
  owner_id     uuid primary key references public.profiles (id) on delete cascade,
  level        int  not null check (level >= 1),
  published_at timestamptz not null default now()
);

alter table public.published_trees enable row level security;

create policy trees_public_read
  on public.published_trees for select
  using (true);

-- Only the owner may publish/update/unpublish their own tree.
create policy trees_owner_write
  on public.published_trees for all
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

-- ---------------------------------------------------------------------------
-- published_games: the games ON a published tree. THE privacy-critical table.
-- Columns are exactly the invariant-10 payload. No recommended_by. No channel.
-- No note. If you are ever tempted to add one of those here, that is the bug.
-- ---------------------------------------------------------------------------
create table if not exists public.published_games (
  id          bigint generated always as identity primary key,
  owner_id    uuid not null references public.published_trees (owner_id)
                on delete cascade,
  igdb_id     int  not null,
  title       text not null,
  cover_url   text,
  -- Progress enum, stored as its name (untouched|installed|playing|finished|
  -- abandoned). A status is the owner's own fact about their play.
  status      text not null,
  -- The owner's own 1-5 rating, or null.
  rating      int check (rating between 1 and 5),
  -- The owner's own category label, never a person.
  branch_name text not null,
  unique (owner_id, igdb_id, branch_name)
);

alter table public.published_games enable row level security;

create policy games_public_read
  on public.published_games for select
  using (true);

-- A game row may only be written by the owner of the tree it belongs to.
create policy games_owner_write
  on public.published_games for all
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

-- ---------------------------------------------------------------------------
-- reactions: an audience verb. One (visitor, tree, kind) at most -- reacting
-- again CHANGES rather than stacks, enforced by the unique constraint.
-- ---------------------------------------------------------------------------
create table if not exists public.reactions (
  tree_owner_id uuid not null references public.published_trees (owner_id)
                  on delete cascade,
  from_id       uuid not null references public.profiles (id) on delete cascade,
  kind          text not null check (kind in ('admire', 'wishlist', 'played')),
  created_at    timestamptz not null default now(),
  primary key (tree_owner_id, from_id, kind)
);

alter table public.reactions enable row level security;

-- Reaction COUNTS are public (a tree shows how many admired it), so read is open.
create policy reactions_public_read
  on public.reactions for select
  using (true);

-- You may only insert/delete a reaction attributed to YOURSELF -- no reacting
-- as someone else, no removing another visitor's reaction.
create policy reactions_self_write
  on public.reactions for insert
  with check (auth.uid() = from_id);
create policy reactions_self_delete
  on public.reactions for delete
  using (auth.uid() = from_id);

-- ---------------------------------------------------------------------------
-- follows: who follows whose tree.
-- ---------------------------------------------------------------------------
create table if not exists public.follows (
  follower_id uuid not null references public.profiles (id) on delete cascade,
  tree_owner_id uuid not null references public.published_trees (owner_id)
                  on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (follower_id, tree_owner_id),
  -- Following your own tree is meaningless; forbid it rather than filter it in
  -- the client, where a filter can be forgotten.
  check (follower_id <> tree_owner_id)
);

alter table public.follows enable row level security;

-- You may read only your OWN follow rows: a follow list is private to the
-- follower, unlike a public reaction count.
create policy follows_self_read
  on public.follows for select
  using (auth.uid() = follower_id);
create policy follows_self_write
  on public.follows for insert
  with check (auth.uid() = follower_id);
create policy follows_self_delete
  on public.follows for delete
  using (auth.uid() = follower_id);
