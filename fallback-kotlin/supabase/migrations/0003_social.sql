-- 0003: the social layer. Editable ID, profile fields, privacy, follow
-- requests, hypes, recommendations, a quiet activity list, notifications,
-- blocking and reporting.
--
-- Direction B from the 2026-09-29 design pass ("quiet feed"):
--   * friends' activity is a finite list of real events, readable only by
--     people allowed to see that tree;
--   * a hype is private between the person who gave it and the owner. There is
--     no public count anywhere in this file, so DECISIONS.md's "no counts"
--     still holds even though a feed now exists.
--
-- PRIVACY -- invariant 10 still applies. Activity and recommendations carry a
-- game's TITLE, COVER, STATUS and RATING only. No notes, no channel, no
-- recommended_by of third parties. A recommendation's sender is the signed-in
-- user themselves, which is the one person whose name they chose to share.
--
-- Every table enables RLS in the block that creates it (see 0001's header).

-- ---------------------------------------------------------------------------
-- profiles: the fields onboarding and Settings edit.
-- The handle IS the user's ID. It was already unique and self-editable in
-- 0001; 0002 seeds it as 'g' + uuid digits, and onboarding replaces it.
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists bio        text not null default ''
    check (char_length(bio) <= 160),
  add column if not exists platforms  text[] not null default '{}'
    check (platforms <@ array['pc','switch','ps5','ps4','xbox','mobile','steamdeck','other']),
  add column if not exists is_private boolean not null default false,
  add column if not exists onboarded  boolean not null default false,
  add column if not exists updated_at timestamptz not null default now();

-- Handles that would read as the app speaking.
create or replace function public.handle_is_reserved(h text)
returns boolean
language sql
immutable
as $$
  select lower(h) = any (array[
    'admin','ludeck','support','help','official','moderator','mod',
    'system','root','me','you','settings','friends','orchard','null'])
$$;

alter table public.profiles
  drop constraint if exists profiles_handle_not_reserved;
alter table public.profiles
  add constraint profiles_handle_not_reserved
  check (not public.handle_is_reserved(handle));

create index if not exists profiles_handle_prefix
  on public.profiles (handle text_pattern_ops);
create index if not exists profiles_name_lower
  on public.profiles (lower(display_name) text_pattern_ops);

-- ---------------------------------------------------------------------------
-- blocks: either direction hides both people from each other.
-- ---------------------------------------------------------------------------
create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

alter table public.blocks enable row level security;

-- You see only your own block list. Nobody learns they were blocked.
create policy blocks_self_read   on public.blocks for select using (auth.uid() = blocker_id);
create policy blocks_self_insert on public.blocks for insert with check (auth.uid() = blocker_id);
create policy blocks_self_delete on public.blocks for delete using (auth.uid() = blocker_id);

-- SECURITY DEFINER because "did they block me" is a row the caller cannot read.
create or replace function public.is_blocked_between(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.blocks
    where (blocker_id = a and blocked_id = b)
       or (blocker_id = b and blocked_id = a))
$$;

-- ---------------------------------------------------------------------------
-- follows: now targets a PROFILE, not a published tree, so you can follow a
-- friend before they publish. Private profiles turn a follow into a request.
-- Column names are kept so the existing client keeps working, and the FK keeps
-- its name so `profiles!follows_tree_owner_id_fkey` embeds resolve.
-- ---------------------------------------------------------------------------
alter table public.follows
  drop constraint if exists follows_tree_owner_id_fkey;
alter table public.follows
  add constraint follows_tree_owner_id_fkey
  foreign key (tree_owner_id) references public.profiles (id) on delete cascade;

alter table public.follows
  add column if not exists status text not null default 'accepted'
    check (status in ('pending', 'accepted'));

create index if not exists follows_by_followee on public.follows (tree_owner_id, status);

-- The status is decided by the server, never by the client: a follow of a
-- public profile is accepted, of a private one is pending. Blocks refuse.
create or replace function public.follows_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.is_blocked_between(new.follower_id, new.tree_owner_id) then
    raise exception 'cannot follow' using errcode = '42501';
  end if;
  new.status := case
    when (select is_private from public.profiles where id = new.tree_owner_id)
      then 'pending' else 'accepted' end;
  new.created_at := now();
  return new;
end;
$$;

drop trigger if exists follows_status on public.follows;
create trigger follows_status
  before insert on public.follows
  for each row execute function public.follows_before_insert();

-- Re-running an upsert must not let a client flip pending to accepted.
create or replace function public.follows_before_update()
returns trigger
language plpgsql
as $$
begin
  if current_setting('ludeck.accepting', true) = 'yes' then
    return new;
  end if;
  new.status := old.status;
  new.created_at := old.created_at;
  return new;
end;
$$;

drop trigger if exists follows_status_locked on public.follows;
create trigger follows_status_locked
  before update on public.follows
  for each row execute function public.follows_before_update();

-- Both ends of a follow can see it: that is how "follows you" and mutual
-- friends work. 0001's self-only read is replaced.
drop policy if exists follows_self_read on public.follows;
create policy follows_either_end_read
  on public.follows for select
  using (auth.uid() = follower_id or auth.uid() = tree_owner_id);

-- Upsert needs UPDATE; the trigger above keeps status out of the client's hands.
drop policy if exists follows_self_update on public.follows;
create policy follows_self_update
  on public.follows for update
  using (auth.uid() = follower_id)
  with check (auth.uid() = follower_id);

-- Unfollow (follower) or remove a follower / decline a request (followee).
drop policy if exists follows_self_delete on public.follows;
create policy follows_either_end_delete
  on public.follows for delete
  using (auth.uid() = follower_id or auth.uid() = tree_owner_id);

-- Accept or decline a follow request addressed to the caller.
create or replace function public.respond_follow_request(follower uuid, accept boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'not signed in' using errcode = '28000';
  end if;
  if accept then
    perform set_config('ludeck.accepting', 'yes', true);
    update public.follows set status = 'accepted'
      where follower_id = follower and tree_owner_id = me and status = 'pending';
    perform set_config('ludeck.accepting', '', true);
  else
    delete from public.follows
      where follower_id = follower and tree_owner_id = me and status = 'pending';
  end if;
end;
$$;

revoke all on function public.respond_follow_request(uuid, boolean) from public, anon;
grant execute on function public.respond_follow_request(uuid, boolean) to authenticated;

-- Blocking someone ends any follow in either direction.
create or replace function public.blocks_after_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.follows
   where (follower_id = new.blocker_id and tree_owner_id = new.blocked_id)
      or (follower_id = new.blocked_id and tree_owner_id = new.blocker_id);
  return new;
end;
$$;

drop trigger if exists blocks_cut_follows on public.blocks;
create trigger blocks_cut_follows
  after insert on public.blocks
  for each row execute function public.blocks_after_insert();

-- ---------------------------------------------------------------------------
-- Visibility, one place. May the caller see OWNER's tree and activity?
-- Yes if it is yours; otherwise never across a block; otherwise if the owner
-- is public, or you are an accepted follower.
-- ---------------------------------------------------------------------------
create or replace function public.can_view(owner uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when owner = auth.uid() then true
    when auth.uid() is not null and public.is_blocked_between(owner, auth.uid()) then false
    when not coalesce((select is_private from public.profiles where id = owner), false) then true
    else exists (
      select 1 from public.follows
      where follower_id = auth.uid() and tree_owner_id = owner and status = 'accepted')
  end
$$;

-- Published trees, their games and their reactions now respect privacy and
-- blocks. The profile row itself stays public so search can find a private
-- person and send a request.
drop policy if exists trees_public_read on public.published_trees;
create policy trees_visible_read
  on public.published_trees for select using (public.can_view(owner_id));

drop policy if exists games_public_read on public.published_games;
create policy games_visible_read
  on public.published_games for select using (public.can_view(owner_id));

drop policy if exists reactions_public_read on public.reactions;
create policy reactions_visible_read
  on public.reactions for select using (public.can_view(tree_owner_id));

-- ---------------------------------------------------------------------------
-- reports: write-only for users. Read by the project owner in the dashboard.
-- ---------------------------------------------------------------------------
create table if not exists public.reports (
  id          bigint generated always as identity primary key,
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  target_id   uuid not null references public.profiles (id) on delete cascade,
  reason      text not null check (reason in ('spam','harassment','impersonation','inappropriate','other')),
  details     text not null default '' check (char_length(details) <= 500),
  created_at  timestamptz not null default now(),
  check (reporter_id <> target_id)
);

alter table public.reports enable row level security;

create policy reports_self_insert
  on public.reports for insert with check (auth.uid() = reporter_id);

-- ---------------------------------------------------------------------------
-- hypes: "I love this one" on a game in someone's tree. Seen by the giver and
-- the owner only. Deliberately no aggregate view.
-- ---------------------------------------------------------------------------
create table if not exists public.hypes (
  from_id    uuid not null references public.profiles (id) on delete cascade,
  owner_id   uuid not null references public.profiles (id) on delete cascade,
  igdb_id    int  not null,
  created_at timestamptz not null default now(),
  primary key (from_id, owner_id, igdb_id),
  check (from_id <> owner_id)
);

alter table public.hypes enable row level security;

create policy hypes_two_party_read
  on public.hypes for select
  using (auth.uid() = from_id or auth.uid() = owner_id);
create policy hypes_self_insert
  on public.hypes for insert
  with check (auth.uid() = from_id and public.can_view(owner_id));
create policy hypes_self_delete
  on public.hypes for delete using (auth.uid() = from_id);

-- ---------------------------------------------------------------------------
-- recommendations: a seed sent to a friend. Arrives in their soil strip.
-- To stop strangers spamming seeds, the RECIPIENT must already follow the
-- sender (accepted). That means friends and people who chose to follow you.
-- ---------------------------------------------------------------------------
create table if not exists public.recommendations (
  id         bigint generated always as identity primary key,
  from_id    uuid not null references public.profiles (id) on delete cascade,
  to_id      uuid not null references public.profiles (id) on delete cascade,
  igdb_id    int  not null,
  title      text not null check (char_length(title) between 1 and 200),
  cover_url  text,
  message    text not null default '' check (char_length(message) <= 140),
  status     text not null default 'sent' check (status in ('sent','planted','dismissed')),
  created_at timestamptz not null default now(),
  check (from_id <> to_id)
);

create index if not exists recommendations_inbox on public.recommendations (to_id, created_at desc);

alter table public.recommendations enable row level security;

create or replace function public.may_recommend_to(recipient uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
     and not public.is_blocked_between(auth.uid(), recipient)
     and exists (
       select 1 from public.follows
       where follower_id = recipient and tree_owner_id = auth.uid() and status = 'accepted')
$$;

create policy recs_two_party_read
  on public.recommendations for select
  using (auth.uid() = from_id or auth.uid() = to_id);
create policy recs_sender_insert
  on public.recommendations for insert
  with check (auth.uid() = from_id and status = 'sent' and public.may_recommend_to(to_id));
-- Only the recipient changes the status (plant or dismiss).
create policy recs_recipient_update
  on public.recommendations for update
  using (auth.uid() = to_id)
  with check (auth.uid() = to_id);
create policy recs_either_delete
  on public.recommendations for delete
  using (auth.uid() = from_id or auth.uid() = to_id);

-- The recipient may change only the status; the rest is the sender's words.
create or replace function public.recommendations_before_update()
returns trigger
language plpgsql
as $$
begin
  if (new.from_id, new.to_id, new.igdb_id, new.title, new.cover_url, new.message, new.created_at)
     is distinct from
     (old.from_id, old.to_id, old.igdb_id, old.title, old.cover_url, old.message, old.created_at) then
    raise exception 'only status may change' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists recommendations_lock on public.recommendations;
create trigger recommendations_lock
  before update on public.recommendations
  for each row execute function public.recommendations_before_update();

-- ---------------------------------------------------------------------------
-- activity: the quiet feed. Real events the actor chose to publish.
-- Readable by whoever can_view the actor, newest first, and it ends.
-- ---------------------------------------------------------------------------
create table if not exists public.activity (
  id         bigint generated always as identity primary key,
  actor_id   uuid not null references public.profiles (id) on delete cascade,
  kind       text not null check (kind in ('planted','harvested','rated')),
  igdb_id    int  not null,
  title      text not null check (char_length(title) between 1 and 200),
  cover_url  text,
  rating     int  check (rating between 1 and 5),
  created_at timestamptz not null default now()
);

create index if not exists activity_by_actor on public.activity (actor_id, created_at desc);

alter table public.activity enable row level security;

create policy activity_visible_read
  on public.activity for select using (public.can_view(actor_id));
create policy activity_self_insert
  on public.activity for insert with check (auth.uid() = actor_id);
create policy activity_self_delete
  on public.activity for delete using (auth.uid() = actor_id);

-- The feed: accepted follows' activity since a cutoff. A function rather than
-- a client join so the "ends" rule (window + limit) is server-side.
create or replace function public.friends_activity(since timestamptz default now() - interval '14 days')
returns setof public.activity
language sql
stable
security invoker
set search_path = public
as $$
  select a.* from public.activity a
  join public.follows f
    on f.tree_owner_id = a.actor_id
   and f.follower_id = auth.uid()
   and f.status = 'accepted'
  where a.created_at >= since
  order by a.created_at desc
  limit 100
$$;

revoke all on function public.friends_activity(timestamptz) from public, anon;
grant execute on function public.friends_activity(timestamptz) to authenticated;

-- ---------------------------------------------------------------------------
-- notifications: the inbox. Written ONLY by the triggers below (security
-- definer); a client can read, mark read and delete its own, never forge one.
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  actor_id   uuid not null references public.profiles (id) on delete cascade,
  kind       text not null check (kind in ('follow','follow_request','follow_accepted','recommendation','hype')),
  igdb_id    int,
  ref_id     bigint,
  read_at    timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists notifications_inbox on public.notifications (user_id, created_at desc);

alter table public.notifications enable row level security;

create policy notifications_self_read
  on public.notifications for select using (auth.uid() = user_id);
create policy notifications_self_update
  on public.notifications for update
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy notifications_self_delete
  on public.notifications for delete using (auth.uid() = user_id);

create or replace function public.notify_follow()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.notifications (user_id, actor_id, kind)
    values (new.tree_owner_id, new.follower_id,
            case when new.status = 'pending' then 'follow_request' else 'follow' end);
  elsif tg_op = 'UPDATE' and old.status = 'pending' and new.status = 'accepted' then
    insert into public.notifications (user_id, actor_id, kind)
    values (new.follower_id, new.tree_owner_id, 'follow_accepted');
    -- The request card is answered; drop it.
    delete from public.notifications
     where user_id = new.tree_owner_id and actor_id = new.follower_id and kind = 'follow_request';
  end if;
  return new;
end;
$$;

drop trigger if exists follows_notify on public.follows;
create trigger follows_notify
  after insert or update on public.follows
  for each row execute function public.notify_follow();

create or replace function public.notify_recommendation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notifications (user_id, actor_id, kind, igdb_id, ref_id)
  values (new.to_id, new.from_id, 'recommendation', new.igdb_id, new.id);
  return new;
end;
$$;

drop trigger if exists recommendations_notify on public.recommendations;
create trigger recommendations_notify
  after insert on public.recommendations
  for each row execute function public.notify_recommendation();

create or replace function public.notify_hype()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notifications (user_id, actor_id, kind, igdb_id)
  values (new.owner_id, new.from_id, 'hype', new.igdb_id);
  return new;
end;
$$;

drop trigger if exists hypes_notify on public.hypes;
create trigger hypes_notify
  after insert on public.hypes
  for each row execute function public.notify_hype();

-- ---------------------------------------------------------------------------
-- RPCs for onboarding and search.
-- ---------------------------------------------------------------------------

-- Is this ID free for the caller? True for your own current handle, so the
-- field does not flash "taken" at you. Normalises case and a leading '@'.
create or replace function public.handle_available(candidate text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  with h as (select lower(regexp_replace(trim(candidate), '^@', '')) as v)
  select h.v ~ '^[a-z0-9_]{3,30}$'
     and not public.handle_is_reserved(h.v)
     and not exists (
       select 1 from public.profiles p
       where p.handle = h.v and p.id is distinct from auth.uid())
  from h
$$;

grant execute on function public.handle_available(text) to anon, authenticated;

-- Find people by ID prefix or name. Hides the caller, and anyone on either
-- side of a block. Returns the relationship so the row can show the right
-- button without a second query.
create or replace function public.search_profiles(q text)
returns table (
  id uuid,
  handle text,
  display_name text,
  avatar_seed text,
  is_private boolean,
  i_follow text,       -- null | 'pending' | 'accepted'
  follows_me boolean
)
language sql
stable
security definer
set search_path = public
as $$
  with term as (select lower(regexp_replace(trim(q), '^@', '')) as v)
  select p.id, p.handle, p.display_name, p.avatar_seed, p.is_private,
         (select f.status from public.follows f
           where f.follower_id = auth.uid() and f.tree_owner_id = p.id),
         exists (select 1 from public.follows f
           where f.follower_id = p.id and f.tree_owner_id = auth.uid()
             and f.status = 'accepted')
  from public.profiles p, term
  where char_length(term.v) >= 2
    and (p.handle like term.v || '%' or lower(p.display_name) like term.v || '%')
    and p.id is distinct from auth.uid()
    and (auth.uid() is null or not public.is_blocked_between(p.id, auth.uid()))
  order by (p.handle = term.v) desc, (p.handle like term.v || '%') desc, p.handle
  limit 20
$$;

grant execute on function public.search_profiles(text) to anon, authenticated;

-- Keep updated_at honest.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch
  before update on public.profiles
  for each row execute function public.touch_updated_at();
