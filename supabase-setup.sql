create table if not exists public.warranty_branches (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 40),
  created_by uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.warranty_branch_members (
  branch_id uuid not null references public.warranty_branches (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (branch_id, user_id)
);

create table if not exists public.warranty_records (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.warranty_branches (id) on delete cascade,
  slip_no text not null,
  customer_name text not null,
  item_name text not null,
  status text not null check (status in ('ongoing', 'claimed', 'pending', 'pickup')),
  received_on date not null,
  attachment_path text,
  created_at timestamptz not null default now(),
  unique (branch_id, slip_no)
);

alter table public.warranty_records
  add column if not exists attachment_path text;

create index if not exists warranty_records_branch_created_idx
  on public.warranty_records (branch_id, created_at desc);

alter table public.warranty_branches enable row level security;
alter table public.warranty_branch_members enable row level security;
alter table public.warranty_records enable row level security;

drop policy if exists "Members can read their branches" on public.warranty_branches;
create policy "Members can read their branches"
  on public.warranty_branches for select to authenticated
  using (
    exists (
      select 1 from public.warranty_branch_members member
      where member.branch_id = id and member.user_id = (select auth.uid())
    )
  );

drop policy if exists "Users can read their memberships" on public.warranty_branch_members;
create policy "Users can read their memberships"
  on public.warranty_branch_members for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "Members can read branch records" on public.warranty_records;
create policy "Members can read branch records"
  on public.warranty_records for select to authenticated
  using (
    exists (
      select 1 from public.warranty_branch_members member
      where member.branch_id = warranty_records.branch_id and member.user_id = (select auth.uid())
    )
  );

drop policy if exists "Members can add branch records" on public.warranty_records;
create policy "Members can add branch records"
  on public.warranty_records for insert to authenticated
  with check (
    exists (
      select 1 from public.warranty_branch_members member
      where member.branch_id = warranty_records.branch_id and member.user_id = (select auth.uid())
    )
  );

drop policy if exists "Members can update branch records" on public.warranty_records;
create policy "Members can update branch records"
  on public.warranty_records for update to authenticated
  using (
    exists (
      select 1 from public.warranty_branch_members member
      where member.branch_id = warranty_records.branch_id and member.user_id = (select auth.uid())
    )
  )
  with check (
    exists (
      select 1 from public.warranty_branch_members member
      where member.branch_id = warranty_records.branch_id and member.user_id = (select auth.uid())
    )
  );

create or replace function public.create_warranty_branch(branch_name text)
returns public.warranty_branches
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_branch public.warranty_branches;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to create a branch.';
  end if;

  if char_length(trim(branch_name)) not between 1 and 40 then
    raise exception 'Branch name must be between 1 and 40 characters.';
  end if;

  insert into public.warranty_branches (name, created_by)
  values (trim(branch_name), auth.uid())
  returning * into new_branch;

  insert into public.warranty_branch_members (branch_id, user_id)
  values (new_branch.id, auth.uid());

  return new_branch;
end;
$$;

revoke all on function public.create_warranty_branch(text) from public;
grant execute on function public.create_warranty_branch(text) to authenticated;

grant select on public.warranty_branches to authenticated;
grant select on public.warranty_branch_members to authenticated;
grant select, insert, update on public.warranty_records to authenticated;

insert into storage.buckets (id, name, public)
values ('warranty-slips', 'warranty-slips', false)
on conflict (id) do update set public = false;

drop policy if exists "Members can read branch slip files" on storage.objects;
create policy "Members can read branch slip files"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'warranty-slips'
    and exists (
      select 1 from public.warranty_branch_members member
      where member.branch_id = ((storage.foldername(name))[1])::uuid
        and member.user_id = (select auth.uid())
    )
  );

drop policy if exists "Members can upload branch slip files" on storage.objects;
create policy "Members can upload branch slip files"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'warranty-slips'
    and exists (
      select 1 from public.warranty_branch_members member
      where member.branch_id = ((storage.foldername(name))[1])::uuid
        and member.user_id = (select auth.uid())
    )
  );

drop policy if exists "Members can delete branch slip files" on storage.objects;
create policy "Members can delete branch slip files"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'warranty-slips'
    and exists (
      select 1 from public.warranty_branch_members member
      where member.branch_id = ((storage.foldername(name))[1])::uuid
        and member.user_id = (select auth.uid())
    )
  );
