-- 0002: a profile for every account, and deleting your own account.
--
-- Two gaps 0001 left, both found before the first deploy (2026-09-28):
--
-- 1. Nothing created a `profiles` row. `published_trees.owner_id` references
--    profiles, so the very first publish would have failed its foreign key.
--    A trigger now creates the row the moment Google sign-in creates the
--    auth user.
--
-- 2. Google Play requires in-app account deletion for any app that creates
--    accounts. `delete_my_account()` deletes the CALLER's auth user; the 0001
--    foreign keys already cascade profiles -> published trees -> games,
--    reactions and follows, so one delete removes everything.

-- The handle is derived from the user id so the app can compute it without a
-- round trip (supabase_social_backend.dart `handleFor`, which MUST match):
-- 'g' + the first 10 hex digits of the uuid. Matches 0001's handle check.
create or replace function public.handle_for(uid uuid)
returns text
language sql
immutable
as $$
  select 'g' || substr(replace(uid::text, '-', ''), 1, 10)
$$;

create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, handle, display_name)
  values (
    new.id,
    public.handle_for(new.id),
    -- Google puts the person's name in full_name/name. 40 chars is 0001's cap.
    left(coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''),
                  nullif(new.raw_user_meta_data ->> 'name', ''),
                  'Gardener'), 40)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.create_profile_for_new_user();

-- Accounts created before this migration (there should be none) get one too.
insert into public.profiles (id, handle, display_name)
select u.id, public.handle_for(u.id),
       left(coalesce(nullif(u.raw_user_meta_data ->> 'full_name', ''), 'Gardener'), 40)
from auth.users u
on conflict (id) do nothing;

-- Deletes the caller and nobody else: the only id it ever touches is
-- auth.uid(), which is the verified JWT subject. Anonymous callers get null
-- and nothing happens.
create or replace function public.delete_my_account()
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
  delete from auth.users where id = me;
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
