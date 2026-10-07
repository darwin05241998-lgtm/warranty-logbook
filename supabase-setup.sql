create table if not exists public.warranty_branches (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 40),
  next_slip_number integer not null default 1 check (next_slip_number > 0),
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

alter table public.warranty_branches
  add column if not exists next_slip_number integer not null default 1;

update public.warranty_branches branch
set next_slip_number = greatest(
  branch.next_slip_number,
  coalesce((
    select max(substring(warranty_record.slip_no from 4)::integer) + 1
    from public.warranty_records warranty_record
    where warranty_record.branch_id = branch.id
      and warranty_record.slip_no ~ '^WR-[0-9]+$'
  ), 1)
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
grant select, update on public.warranty_records to authenticated;
revoke insert on public.warranty_records from authenticated;
revoke delete on public.warranty_records from public, anon, authenticated;

create or replace function public.delete_warranty_record(
  p_record_id uuid,
  p_password text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  password_hash text;
  record_attachment_path text;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to delete a service slip.';
  end if;

  if p_password is null or p_password = '' then
    raise exception 'Enter your account password to confirm deletion.';
  end if;

  select users.encrypted_password
  into password_hash
  from auth.users users
  where users.id = auth.uid();

  if password_hash is null
    or extensions.crypt(p_password, password_hash) is distinct from password_hash then
    raise exception 'The account password is incorrect.' using errcode = '28000';
  end if;

  delete from public.warranty_records warranty_record
  using public.warranty_branch_members member
  where warranty_record.id = p_record_id
    and member.branch_id = warranty_record.branch_id
    and member.user_id = auth.uid()
  returning warranty_record.attachment_path into record_attachment_path;

  if not found then
    raise exception 'The service slip was not found or you do not have access to it.'
      using errcode = 'P0002';
  end if;

  return record_attachment_path;
end;
$$;

revoke all on function public.delete_warranty_record(uuid, text) from public, anon;
grant execute on function public.delete_warranty_record(uuid, text) to authenticated;

create or replace function public.create_warranty_record(
  p_branch_id uuid,
  p_customer_name text,
  p_item_name text,
  p_status text,
  p_received_on date
)
returns public.warranty_records
language plpgsql
security definer
set search_path = ''
as $$
declare
  allocated_number integer;
  new_record public.warranty_records;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to add a service slip.';
  end if;

  if not exists (
    select 1 from public.warranty_branch_members member
    where member.branch_id = p_branch_id and member.user_id = auth.uid()
  ) then
    raise exception 'You are not a member of this branch.';
  end if;

  if p_customer_name is null or char_length(trim(p_customer_name)) not between 1 and 120 then
    raise exception 'Customer name must be between 1 and 120 characters.';
  end if;
  if p_item_name is null or char_length(trim(p_item_name)) not between 1 and 120 then
    raise exception 'Item name must be between 1 and 120 characters.';
  end if;
  if p_status is null or p_status not in ('ongoing', 'claimed', 'pending', 'pickup') then
    raise exception 'Invalid service status.';
  end if;
  if p_received_on is null then
    raise exception 'Date received is required.';
  end if;

  update public.warranty_branches
  set next_slip_number = next_slip_number + 1
  where id = p_branch_id
  returning next_slip_number - 1 into allocated_number;

  if allocated_number is null then
    raise exception 'Branch was not found.';
  end if;

  insert into public.warranty_records (
    branch_id, slip_no, customer_name, item_name, status, received_on
  )
  values (
    p_branch_id,
    'WR-' || lpad(allocated_number::text, 3, '0'),
    trim(p_customer_name),
    trim(p_item_name),
    p_status,
    p_received_on
  )
  returning * into new_record;

  return new_record;
end;
$$;

revoke all on function public.create_warranty_record(uuid, text, text, text, date) from public;
grant execute on function public.create_warranty_record(uuid, text, text, text, date) to authenticated;

insert into storage.buckets (id, name, public)
values ('warranty-slips', 'warranty-slips', false)
on conflict (id) do update
set public = false,
    file_size_limit = 10485760,
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'application/pdf'];

drop policy if exists "Members can read branch slip files" on storage.objects;
create policy "Members can read branch slip files"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'warranty-slips'
    and exists (
      select 1 from public.warranty_branch_members member
      where member.branch_id::text = (storage.foldername(name))[1]
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
      where member.branch_id::text = (storage.foldername(name))[1]
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
      where member.branch_id::text = (storage.foldername(name))[1]
        and member.user_id = (select auth.uid())
    )
  );

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'warranty_records'
  ) then
    alter publication supabase_realtime add table public.warranty_records;
  end if;
end;
$$;
