-- SATUN SSJ WFH - Query cookbook for Supabase
-- Replace :params with your values in SQL editor or app layer.

-- 1) สร้าง user profile หลังสมัครสมาชิก (โดยปกติทำผ่าน trigger ได้)
insert into public.user_profiles (
  id,
  first_name,
  last_name,
  phone,
  job_title,
  department_id,
  role
)
values (
  '00000000-0000-0000-0000-000000000000',
  'สมชาย',
  'ใจดี',
  '0812345678',
  'เจ้าหน้าที่',
  1,
  'general'
)
on conflict (id) do update
set
  first_name = excluded.first_name,
  last_name = excluded.last_name,
  phone = excluded.phone,
  job_title = excluded.job_title,
  department_id = excluded.department_id,
  role = excluded.role,
  updated_at = now();

-- 2) สร้าง task ใหม่ (ใช้ generate_task_no)
insert into public.tasks (
  task_no,
  title,
  description,
  department_id,
  status,
  priority,
  due_date,
  created_by
)
values (
  public.generate_task_no(),
  'ติดตามแผนปฏิบัติการรายเดือน',
  'รวบรวมความคืบหน้าจากทุกกลุ่มงาน',
  1,
  'draft',
  'high',
  current_date + interval '7 day',
  auth.uid()
)
returning id, task_no;

-- 3) มอบหมายงานให้ผู้ปฏิบัติ
select public.assign_task(
  p_task_id => '11111111-1111-1111-1111-111111111111',
  p_assignee_id => '22222222-2222-2222-2222-222222222222',
  p_note => 'โปรดส่งก่อนวันศุกร์'
);

-- 4) ผู้ปฏิบัติงานอัปเดตสถานะ + progress
update public.tasks
set
  status = 'in_progress',
  progress_percent = 45
where id = '11111111-1111-1111-1111-111111111111';

-- 5) ส่งงานรออนุมัติ
update public.tasks
set
  status = 'pending_approval',
  progress_percent = 100
where id = '11111111-1111-1111-1111-111111111111';

-- 6) อนุมัติ / ส่งกลับแก้ไข
select public.approve_task(
  p_task_id => '11111111-1111-1111-1111-111111111111',
  p_is_approved => true,
  p_remark => 'เอกสารครบถ้วน'
);

-- 7) Dashboard KPI รวมทั้งระบบ
select * from public.v_task_kpi_summary;

-- 8) งานค้าง/เกินกำหนด แยกตามหน่วยงาน
select
  d.name_th as department,
  count(*) filter (where t.status in ('assigned','in_progress','pending_approval','revision_required')) as active_tasks,
  count(*) filter (where t.is_overdue) as overdue_tasks
from public.tasks t
left join public.departments d on d.id = t.department_id
group by d.name_th
order by overdue_tasks desc, active_tasks desc;

-- 9) productivity รายบุคคล
select
  up.id,
  up.first_name || ' ' || up.last_name as full_name,
  count(*) filter (where t.status = 'completed') as completed_count,
  count(*) filter (where t.status <> 'completed') as pending_count,
  round(avg(extract(epoch from (coalesce(t.completed_at, now()) - t.created_at))/3600)::numeric, 2) as avg_lead_time_hours
from public.tasks t
join public.user_profiles up on up.id = t.assigned_to
group by up.id, full_name
order by completed_count desc;

-- 10) timeline สถานะงาน
select
  tsh.task_id,
  tsh.from_status,
  tsh.to_status,
  tsh.changed_at,
  up.first_name || ' ' || up.last_name as changed_by_name,
  tsh.remark
from public.task_status_history tsh
left join public.user_profiles up on up.id = tsh.changed_by
where tsh.task_id = '11111111-1111-1111-1111-111111111111'
order by tsh.changed_at asc;

-- 11) รายงานงานรายเดือน
select
  to_char(created_at, 'YYYY-MM') as month,
  count(*) as total_tasks,
  count(*) filter (where status = 'completed') as completed_tasks,
  round((count(*) filter (where status = 'completed')::numeric / nullif(count(*),0))*100, 2) as completion_rate
from public.tasks
group by to_char(created_at, 'YYYY-MM')
order by month desc;
