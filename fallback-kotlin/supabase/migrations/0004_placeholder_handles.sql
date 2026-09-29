-- 0004: a new account can always get a placeholder ID.
--
-- Found in the Stage 8 run (2026-09-29): 0002's trigger gives every new user
-- the handle 'g' + the first 10 hex digits of their id, and fails the whole
-- sign-up when that handle is taken. Two ids sharing a 10-digit prefix is
-- rare, but 0003 made handles editable, so anyone could pick a handle of that
-- exact shape and block a future stranger from ever signing up.
--
-- Two fixes:
--   1. The trigger tries longer prefixes of the id until one is free, so a
--      collision costs a longer placeholder, never a failed sign-up.
--   2. handle_available refuses the placeholder shape (g + hex only), so a
--      person cannot choose one on purpose. Their own current placeholder
--      still reads as available to them, as before.

create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  hex text := replace(new.id::text, '-', '');
  candidate text;
  n int;
begin
  -- 11, 15, 19 ... 29 characters: 'g' plus 10, 14 ... 28 hex digits. 30 is the
  -- handle limit (0001's check).
  foreach n in array array[10, 14, 18, 22, 26, 28] loop
    candidate := 'g' || substr(hex, 1, n);
    exit when not exists (select 1 from public.profiles where handle = candidate);
    candidate := null;
  end loop;
  if candidate is null then
    -- Every prefix taken, which needs someone to have squatted all of them.
    -- A random tail still gets the person in; onboarding replaces it anyway.
    candidate := 'u' || substr(md5(random()::text || hex), 1, 20);
  end if;

  insert into public.profiles (id, handle, display_name)
  values (
    new.id,
    candidate,
    left(coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''),
                  nullif(new.raw_user_meta_data ->> 'name', ''),
                  'Gardener'), 40)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

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
     -- The placeholder shape belongs to the sign-up trigger. Allowed only when
     -- it is already the caller's own handle.
     and (h.v !~ '^g[0-9a-f]{10,28}$'
          or exists (select 1 from public.profiles p
                     where p.handle = h.v and p.id = auth.uid()))
     and not exists (
       select 1 from public.profiles p
       where p.handle = h.v and p.id is distinct from auth.uid())
  from h
$$;

grant execute on function public.handle_available(text) to anon, authenticated;

-- The same rule where it cannot be skipped: an update to someone else's
-- placeholder shape is refused, whatever client sent it. Your own existing
-- placeholder may stay (every account starts with one).
create or replace function public.profiles_handle_guard()
returns trigger
language plpgsql
as $$
begin
  if new.handle is distinct from old.handle
     and new.handle ~ '^g[0-9a-f]{10,28}$' then
    raise exception 'that ID is kept for new accounts' using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_handle_guard on public.profiles;
create trigger profiles_handle_guard
  before update on public.profiles
  for each row execute function public.profiles_handle_guard();
