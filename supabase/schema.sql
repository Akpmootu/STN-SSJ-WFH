-- SATUN SSJ WFH - Supabase schema (PostgreSQL)
-- Run this script in Supabase SQL Editor.

begin;

create extension if not exists pgcrypto;

-- ==========
-- ENUM TYPES
-- ==========
create type public.app_role as enum ('admin', 'officer', 'head', 'general', 'other');
create type public.task_status as enum (
  'draft',
  'assigned',
  'in_progress',
  'pending_approval',
  'revision_required',
  'completed',
  'cancelled'
);
create type public.priority_level as enum ('low', 'medium', 'high', 'urgent');
create type public.notification_type as enum (
  'task_assigned',
  'task_updated',
  'task_approved',
  'task_rejected',
  'task_overdue',
  'mention',
  'system'
);

-- ==========
-- CORE TABLES
-- ==========
create table if not exists public.departments (
  id bigserial primary key,
  code text unique not null,
  name_th text not null,
  name_en text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  first_name text not null,
  last_name text not null,
  phone text,
  job_title text,
  department_id bigint references public.departments(id) on delete set null,
  role public.app_role not null default 'general',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  task_no text unique not null,
  title text not null,
  description text,
  department_id bigint references public.departments(id) on delete set null,
  status public.task_status not null default 'draft',
  priority public.priority_level not null default 'medium',
  due_date date,
  start_date date,
  completed_at timestamptz,
  progress_percent numeric(5,2) not null default 0 check (progress_percent between 0 and 100),
  created_by uuid not null references auth.users(id),
  assigned_by uuid references auth.users(id),
  assigned_to uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  is_overdue boolean generated always as (
    due_date is not null
    and status not in ('completed', 'cancelled')
    and due_date < current_date
  ) stored,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.task_assignments (
  id bigserial primary key,
  task_id uuid not null references public.tasks(id) on delete cascade,
  assignee_id uuid not null references auth.users(id) on delete cascade,
  assigned_by uuid not null references auth.users(id) on delete set null,
  assigned_at timestamptz not null default now(),
  note text,
  is_current boolean not null default true
);

create table if not exists public.task_status_history (
  id bigserial primary key,
  task_id uuid not null references public.tasks(id) on delete cascade,
  from_status public.task_status,
  to_status public.task_status not null,
  changed_by uuid not null references auth.users(id),
  changed_at timestamptz not null default now(),
  remark text
);

create table if not exists public.task_comments (
  id bigserial primary key,
  task_id uuid not null references public.tasks(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  comment_text text not null,
  mention_user_ids uuid[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.task_attachments (
  id bigserial primary key,
  task_id uuid not null references public.tasks(id) on delete cascade,
  uploaded_by uuid not null references auth.users(id) on delete cascade,
  file_name text not null,
  file_path text not null,
  file_size bigint,
  mime_type text,
  version_no integer not null default 1,
  created_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  type public.notification_type not null,
  title text not null,
  message text,
  related_task_id uuid references public.tasks(id) on delete cascade,
  is_read boolean not null default false,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create table if not exists public.audit_logs (
  id bigserial primary key,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_name text not null,
  entity_id text not null,
  old_values jsonb,
  new_values jsonb,
  ip_address inet,
  user_agent text,
  created_at timestamptz not null default now()
);

-- ==========
-- INDEXES
-- ==========
create index if not exists idx_user_profiles_department_id on public.user_profiles(department_id);
create index if not exists idx_user_profiles_role on public.user_profiles(role);
create index if not exists idx_tasks_status on public.tasks(status);
create index if not exists idx_tasks_due_date on public.tasks(due_date);
create index if not exists idx_tasks_department_id on public.tasks(department_id);
create index if not exists idx_tasks_assigned_to on public.tasks(assigned_to);
create index if not exists idx_task_assignments_task_id on public.task_assignments(task_id);
create index if not exists idx_task_assignments_assignee_id on public.task_assignments(assignee_id);
create index if not exists idx_task_status_history_task_id on public.task_status_history(task_id);
create index if not exists idx_task_comments_task_id on public.task_comments(task_id);
create index if not exists idx_task_attachments_task_id on public.task_attachments(task_id);
create index if not exists idx_notifications_user_id_read on public.notifications(user_id, is_read);
create index if not exists idx_audit_logs_entity on public.audit_logs(entity_name, entity_id);

-- ==========
-- COMMON TRIGGER FUNCTION
-- ==========
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_departments_updated_at
before update on public.departments
for each row execute function public.set_updated_at();

create trigger trg_user_profiles_updated_at
before update on public.user_profiles
for each row execute function public.set_updated_at();

create trigger trg_tasks_updated_at
before update on public.tasks
for each row execute function public.set_updated_at();

create trigger trg_task_comments_updated_at
before update on public.task_comments
for each row execute function public.set_updated_at();

-- ==========
-- HELPERS (RBAC)
-- ==========
create or replace function public.current_user_role()
returns public.app_role
language sql
stable
as $$
  select role
  from public.user_profiles
  where id = auth.uid();
$$;

create or replace function public.has_any_role(roles public.app_role[])
returns boolean
language sql
stable
as $$
  select coalesce(public.current_user_role() = any(roles), false);
$$;

-- ==========
-- BUSINESS FUNCTIONS
-- ==========
create or replace function public.generate_task_no()
returns text
language plpgsql
as $$
declare
  yymm text;
  seq_num integer;
begin
  yymm := to_char(now(), 'YYMM');

  select coalesce(max(substring(task_no from 8 for 6)::integer), 0) + 1
  into seq_num
  from public.tasks
  where task_no like 'WFH-' || yymm || '-%';

  return 'WFH-' || yymm || '-' || lpad(seq_num::text, 6, '0');
end;
$$;

create or replace function public.log_task_status_change()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.task_status_history(task_id, from_status, to_status, changed_by, remark)
    values (new.id, null, new.status, coalesce(auth.uid(), new.created_by), 'Task created');
  elsif tg_op = 'UPDATE' and new.status is distinct from old.status then
    insert into public.task_status_history(task_id, from_status, to_status, changed_by, remark)
    values (new.id, old.status, new.status, coalesce(auth.uid(), old.created_by), null);
  end if;
  return new;
end;
$$;

create trigger trg_tasks_status_history
after insert or update on public.tasks
for each row execute function public.log_task_status_change();

create or replace function public.assign_task(
  p_task_id uuid,
  p_assignee_id uuid,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.task_assignments
  set is_current = false
  where task_id = p_task_id
    and is_current = true;

  insert into public.task_assignments(task_id, assignee_id, assigned_by, note)
  values (p_task_id, p_assignee_id, auth.uid(), p_note);

  update public.tasks
  set assigned_to = p_assignee_id,
      assigned_by = auth.uid(),
      status = case when status = 'draft' then 'assigned' else status end
  where id = p_task_id;

  insert into public.notifications(user_id, type, title, message, related_task_id)
  values (
    p_assignee_id,
    'task_assigned',
    'มีงานใหม่มอบหมาย',
    'คุณได้รับมอบหมายงานใหม่ในระบบ SATUN SSJ WFH',
    p_task_id
  );
end;
$$;

create or replace function public.approve_task(
  p_task_id uuid,
  p_is_approved boolean,
  p_remark text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status public.task_status;
  v_assigned_to uuid;
begin
  if p_is_approved then
    v_status := 'completed';
  else
    v_status := 'revision_required';
  end if;

  update public.tasks
  set status = v_status,
      approved_by = auth.uid(),
      approved_at = now(),
      completed_at = case when p_is_approved then now() else null end,
      progress_percent = case when p_is_approved then 100 else progress_percent end
  where id = p_task_id
  returning assigned_to into v_assigned_to;

  if v_assigned_to is not null then
    insert into public.notifications(user_id, type, title, message, related_task_id)
    values (
      v_assigned_to,
      case when p_is_approved then 'task_approved' else 'task_rejected' end,
      case when p_is_approved then 'งานได้รับการอนุมัติแล้ว' else 'งานต้องแก้ไขเพิ่มเติม' end,
      coalesce(p_remark, case when p_is_approved then 'งานเสร็จสมบูรณ์' else 'กรุณาตรวจสอบหมายเหตุและแก้ไขงาน' end),
      p_task_id
    );
  end if;
end;
$$;

-- ==========
-- VIEW: KPI SUMMARY
-- ==========
create or replace view public.v_task_kpi_summary as
select
  count(*)::int as total_tasks,
  count(*) filter (where status = 'completed')::int as completed_tasks,
  count(*) filter (where status in ('assigned', 'in_progress', 'pending_approval', 'revision_required'))::int as active_tasks,
  count(*) filter (where is_overdue = true)::int as overdue_tasks,
  round(
    (count(*) filter (where status = 'completed')::numeric / nullif(count(*), 0)) * 100,
    2
  ) as completion_rate_percent,
  round(
    avg(extract(epoch from (coalesce(completed_at, now()) - created_at)) / 3600)::numeric,
    2
  ) as avg_lead_time_hours
from public.tasks;

-- ==========
-- DEFAULT DATA
-- ==========
insert into public.departments(code, name_th, name_en)
values
  ('ADM', 'กลุ่มอำนวยการ', 'Administration'),
  ('HR', 'กลุ่มบริหารทรัพยากรบุคคล', 'Human Resources'),
  ('IT', 'กลุ่มเทคโนโลยีสารสนเทศ', 'Information Technology'),
  ('EPI', 'กลุ่มระบาดวิทยา', 'Epidemiology')
on conflict (code) do nothing;

-- ==========
-- RLS ENABLE
-- ==========
alter table public.departments enable row level security;
alter table public.user_profiles enable row level security;
alter table public.tasks enable row level security;
alter table public.task_assignments enable row level security;
alter table public.task_status_history enable row level security;
alter table public.task_comments enable row level security;
alter table public.task_attachments enable row level security;
alter table public.notifications enable row level security;
alter table public.audit_logs enable row level security;

-- ==========
-- RLS POLICIES
-- ==========
-- departments
create policy "departments read for all authenticated"
on public.departments
for select
to authenticated
using (true);

create policy "departments write admin only"
on public.departments
for all
to authenticated
using (public.has_any_role(array['admin'::public.app_role]))
with check (public.has_any_role(array['admin'::public.app_role]));

-- user_profiles
create policy "profiles select own or admin/officer"
on public.user_profiles
for select
to authenticated
using (
  auth.uid() = id
  or public.has_any_role(array['admin'::public.app_role, 'officer'::public.app_role])
);

create policy "profiles insert admin only"
on public.user_profiles
for insert
to authenticated
with check (public.has_any_role(array['admin'::public.app_role]));

create policy "profiles update own or admin"
on public.user_profiles
for update
to authenticated
using (
  auth.uid() = id
  or public.has_any_role(array['admin'::public.app_role])
)
with check (
  auth.uid() = id
  or public.has_any_role(array['admin'::public.app_role])
);

-- tasks
create policy "tasks select by visibility"
on public.tasks
for select
to authenticated
using (
  public.has_any_role(array['admin'::public.app_role, 'officer'::public.app_role])
  or created_by = auth.uid()
  or assigned_to = auth.uid()
  or exists (
    select 1 from public.task_assignments ta
    where ta.task_id = tasks.id and ta.assignee_id = auth.uid()
  )
);

create policy "tasks insert by admin officer head"
on public.tasks
for insert
to authenticated
with check (
  public.has_any_role(array['admin'::public.app_role, 'officer'::public.app_role, 'head'::public.app_role])
  and created_by = auth.uid()
);

create policy "tasks update admin head assignee"
on public.tasks
for update
to authenticated
using (
  public.has_any_role(array['admin'::public.app_role, 'head'::public.app_role])
  or assigned_to = auth.uid()
)
with check (
  public.has_any_role(array['admin'::public.app_role, 'head'::public.app_role])
  or assigned_to = auth.uid()
);

-- task_assignments
create policy "task_assignments select by task visibility"
on public.task_assignments
for select
to authenticated
using (
  public.has_any_role(array['admin'::public.app_role, 'officer'::public.app_role])
  or assignee_id = auth.uid()
  or exists (
    select 1
    from public.tasks t
    where t.id = task_assignments.task_id
      and (t.assigned_to = auth.uid() or t.created_by = auth.uid())
  )
);

create policy "task_assignments insert by admin officer head"
on public.task_assignments
for insert
to authenticated
with check (
  public.has_any_role(array['admin'::public.app_role, 'officer'::public.app_role, 'head'::public.app_role])
  and assigned_by = auth.uid()
);

create policy "task_assignments update admin officer head"
on public.task_assignments
for update
to authenticated
using (
  public.has_any_role(array['admin'::public.app_role, 'officer'::public.app_role, 'head'::public.app_role])
)
with check (
  public.has_any_role(array['admin'::public.app_role, 'officer'::public.app_role, 'head'::public.app_role])
);

-- task_status_history
create policy "task_status_history select by task visibility"
on public.task_status_history
for select
to authenticated
using (
  public.has_any_role(array['admin'::public.app_role, 'officer'::public.app_role])
  or exists (
    select 1
    from public.tasks t
    where t.id = task_status_history.task_id
      and (t.assigned_to = auth.uid() or t.created_by = auth.uid())
  )
);

create policy "task_status_history insert by system or permitted users"
on public.task_status_history
for insert
to authenticated
with check (
  changed_by = auth.uid()
  or public.has_any_role(array['admin'::public.app_role, 'head'::public.app_role])
);

-- task_comments
create policy "task_comments select by task visibility"
on public.task_comments
for select
to authenticated
using (
  public.has_any_role(array['admin'::public.app_role, 'officer'::public.app_role])
  or exists (
    select 1
    from public.tasks t
    where t.id = task_comments.task_id
      and (t.assigned_to = auth.uid() or t.created_by = auth.uid())
  )
);

create policy "task_comments insert by visible users"
on public.task_comments
for insert
to authenticated
with check (
  author_id = auth.uid()
  and (
    public.has_any_role(array['admin'::public.app_role, 'officer'::public.app_role])
    or exists (
      select 1
      from public.tasks t
      where t.id = task_comments.task_id
        and (t.assigned_to = auth.uid() or t.created_by = auth.uid())
    )
  )
);

create policy "task_comments update own"
on public.task_comments
for update
to authenticated
using (author_id = auth.uid())
with check (author_id = auth.uid());

-- task_attachments
create policy "task_attachments select by task visibility"
on public.task_attachments
for select
to authenticated
using (
  public.has_any_role(array['admin'::public.app_role, 'officer'::public.app_role])
  or exists (
    select 1
    from public.tasks t
    where t.id = task_attachments.task_id
      and (t.assigned_to = auth.uid() or t.created_by = auth.uid())
  )
);

create policy "task_attachments insert by visible users"
on public.task_attachments
for insert
to authenticated
with check (
  uploaded_by = auth.uid()
  and (
    public.has_any_role(array['admin'::public.app_role, 'officer'::public.app_role, 'head'::public.app_role])
    or exists (
      select 1
      from public.tasks t
      where t.id = task_attachments.task_id
        and t.assigned_to = auth.uid()
    )
  )
);

-- notifications
create policy "notifications own only"
on public.notifications
for select
to authenticated
using (user_id = auth.uid());

create policy "notifications own update read"
on public.notifications
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "notifications insert admin officer head"
on public.notifications
for insert
to authenticated
with check (
  public.has_any_role(array['admin'::public.app_role, 'officer'::public.app_role, 'head'::public.app_role])
);

-- audit_logs
create policy "audit_logs select admin only"
on public.audit_logs
for select
to authenticated
using (public.has_any_role(array['admin'::public.app_role]));

create policy "audit_logs insert service role only"
on public.audit_logs
for insert
to authenticated
with check (false);

commit;
