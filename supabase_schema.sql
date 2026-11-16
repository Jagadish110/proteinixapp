-- =====================================================
-- Proteinix Supabase Schema + RLS Policies
-- Run this in Supabase SQL Editor (full file, one go)
-- =====================================================

create extension if not exists "uuid-ossp";

-- ----------------------------------------
-- profiles
-- ----------------------------------------
create table if not exists profiles (
  id uuid references auth.users on delete cascade primary key,
  name text,
  age int,
  gender text,
  height_cm float,
  weight_kg float,
  goal text,
  activity_level text,
  calorie_goal int default 2000,
  protein_goal_g float default 100,
  carbs_goal_g float default 250,
  fat_goal_g float default 65,
  fiber_goal_g float default 30,
  water_goal_ml int default 2500,
  steps_goal int default 10000,
  sleep_goal_hrs float default 8,
  language text default 'en',
  theme text default 'light',
  avatar_url text,
  onboarding_complete boolean default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ----------------------------------------
-- daily_logs (per-day aggregates)
-- ----------------------------------------
create table if not exists daily_logs (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references auth.users on delete cascade,
  date date not null,
  calories_consumed int default 0,
  protein_g float default 0,
  carbs_g float default 0,
  fat_g float default 0,
  fiber_g float default 0,
  water_ml int default 0,
  steps int default 0,
  calories_burned int default 0,
  sleep_hrs float default 0,
  sleep_quality int default 0,
  sleep_interruptions int default 0,
  weight_kg float,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique(user_id, date)
);

-- ----------------------------------------
-- meals (individual meal log entries)
-- ----------------------------------------
create table if not exists meals (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references auth.users on delete cascade,
  date date not null,
  meal_type text not null,
  food_name text not null,
  quantity float,
  unit text,
  calories int,
  protein_g float,
  carbs_g float,
  fat_g float,
  fiber_g float,
  log_method text default 'manual',
  scan_confidence text,
  logged_at timestamptz default now()
);

-- ----------------------------------------
-- food_scans
-- ----------------------------------------
create table if not exists food_scans (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references auth.users on delete cascade,
  food_items jsonb,
  total_calories int,
  total_protein_g float,
  total_carbs_g float,
  total_fat_g float,
  confidence text,
  meal_type text,
  gemini_response jsonb,
  was_logged boolean default false,
  created_at timestamptz default now()
);

-- ----------------------------------------
-- sleep_schedule
-- ----------------------------------------
create table if not exists sleep_schedule (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references auth.users on delete cascade,
  sleep_time time not null,
  wake_time time not null,
  days text[] default array['all'],
  is_active boolean default true,
  created_at timestamptz default now()
);

-- ----------------------------------------
-- blocked_apps
-- ----------------------------------------
create table if not exists blocked_apps (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references auth.users on delete cascade,
  package_name text not null,
  app_name text not null,
  created_at timestamptz default now()
);

-- ----------------------------------------
-- sleep_guard_logs
-- ----------------------------------------
create table if not exists sleep_guard_logs (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references auth.users on delete cascade,
  date date not null,
  override_count int default 0,
  blocked_attempts int default 0,
  sleep_streak int default 0,
  created_at timestamptz default now()
);

-- ----------------------------------------
-- weight_logs
-- ----------------------------------------
create table if not exists weight_logs (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references auth.users on delete cascade,
  weight_kg float not null,
  date date not null,
  created_at timestamptz default now()
);

-- ----------------------------------------
-- meal_routines
-- ----------------------------------------
-- Saved meal routines ("Quick Picks") — previously stored only in
-- SharedPreferences on-device, so signing out, reinstalling, or switching
-- devices lost every one of them. This is the server copy the local-first
-- sync layer keeps in step with.
create table if not exists meal_routines (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users on delete cascade,
  name text not null,
  -- Structurally identical to RoutineItem.toJson() on the client. One jsonb
  -- column rather than a child table: a routine is always read and written
  -- whole, never queried by its items.
  items jsonb not null default '[]'::jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ----------------------------------------
-- ai_messages (coach chat history)
-- ----------------------------------------
create table if not exists ai_messages (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references auth.users on delete cascade,
  role text not null,
  content text not null,
  created_at timestamptz default now()
);

-- ----------------------------------------
-- achievements
-- ----------------------------------------
create table if not exists achievements (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references auth.users on delete cascade,
  achievement_type text not null,
  achieved_at timestamptz default now()
);

-- =====================================================
-- ROW LEVEL SECURITY — every table is user-isolated
-- =====================================================

alter table profiles enable row level security;
alter table daily_logs enable row level security;
alter table meals enable row level security;
alter table food_scans enable row level security;
alter table sleep_schedule enable row level security;
alter table blocked_apps enable row level security;
alter table sleep_guard_logs enable row level security;
alter table weight_logs enable row level security;
alter table ai_messages enable row level security;
alter table achievements enable row level security;
alter table meal_routines enable row level security;

-- helper macro: same 4 policies (select/insert/update/delete) for the owner
-- Each policy ensures user_id (or id for profiles) = auth.uid()

-- profiles
create policy "profiles_select_own" on profiles for select using (auth.uid() = id);
create policy "profiles_insert_own" on profiles for insert with check (auth.uid() = id);
create policy "profiles_update_own" on profiles for update using (auth.uid() = id);
create policy "profiles_delete_own" on profiles for delete using (auth.uid() = id);

-- generic helper to create owner-policies for user_id-keyed tables
do $$
declare
  t text;
  tables text[] := array[
    'daily_logs','meals','food_scans','sleep_schedule','blocked_apps',
    'sleep_guard_logs','weight_logs','ai_messages','achievements','meal_routines'
  ];
begin
  foreach t in array tables loop
    execute format('create policy "%I_select_own" on %I for select using (auth.uid() = user_id);', t, t);
    execute format('create policy "%I_insert_own" on %I for insert with check (auth.uid() = user_id);', t, t);
    execute format('create policy "%I_update_own" on %I for update using (auth.uid() = user_id);', t, t);
    execute format('create policy "%I_delete_own" on %I for delete using (auth.uid() = user_id);', t, t);
  end loop;
end$$;

-- =====================================================
-- AUTO PROFILE on signup
-- =====================================================
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- =====================================================
-- AVATAR STORAGE
-- =====================================================
-- Public bucket, but writes are restricted to a user's own folder
-- (avatars/{uid}/...), enforced via the storage.foldername() path check.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy "Avatar images are publicly accessible"
on storage.objects for select
using (bucket_id = 'avatars');

create policy "Users can upload their own avatar"
on storage.objects for insert
with check (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);

create policy "Users can update their own avatar"
on storage.objects for update
using (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);

create policy "Users can delete their own avatar"
on storage.objects for delete
using (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);

-- =====================================================
-- MIGRATIONS
-- =====================================================
-- The table definitions above use `create table if not exists`, so a database
-- that already exists never picks up a new column from them. Additive changes
-- go here as well, written to be safe to re-run.

-- Wake-ups counted by the sleep sampler, alongside the sleep_hrs it derives
-- from the same screen readings.
alter table daily_logs add column if not exists sleep_interruptions int default 0;

-- The rest of the sleep record.
--
-- phone_pickups is a floor, not a count: the sampler reads the screen every 15
-- minutes, so a phone picked up and put down between two checks is invisible
-- to it. sleep_score is derived from sleep_hrs and sleep_interruptions and is
-- stored rather than computed on read so history stays queryable.
--
-- sleep_start/sleep_end are what was *observed*, not the window the user set —
-- a 23:30 bedtime with sleep_start at 00:40 is an hour spent awake in bed, and
-- storing the schedule here instead would hide exactly that.
alter table daily_logs add column if not exists phone_pickups int default 0;
alter table daily_logs add column if not exists sleep_score int default 0;
alter table daily_logs add column if not exists sleep_start timestamptz;
alter table daily_logs add column if not exists sleep_end timestamptz;
