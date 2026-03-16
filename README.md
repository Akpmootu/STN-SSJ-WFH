# STN-SSJ-WFH

SATUN SSJ WFH (Work From Home) คือระบบติดตามงานสำหรับสำนักงานสาธารณสุขจังหวัดสตูล โดยโครงสร้างข้อมูลและสิทธิ์การเข้าถึงถูกออกแบบให้ใช้กับ **Supabase (PostgreSQL + Auth + RLS)**

## สิ่งที่เพิ่มในรอบนี้

- โครงสร้างฐานข้อมูลครบระบบใน `supabase/schema.sql`
- ชุด Query พร้อมใช้งานใน `supabase/queries.sql`
- รองรับ role หลัก: `admin`, `officer`, `head`, `general`, `other`
- รองรับ workflow งาน: `draft -> assigned -> in_progress -> pending_approval -> completed/revision_required/cancelled`
- มีระบบแจ้งเตือน, ประวัติสถานะ, คอมเมนต์, ไฟล์แนบ และ audit log

## วิธีเริ่มใช้งานกับ Supabase

1. เปิด Supabase SQL Editor
2. วางและรันไฟล์ `supabase/schema.sql`
3. ทดสอบข้อมูลและ flow ด้วย `supabase/queries.sql`

> แนะนำให้รันในโปรเจกต์ว่างก่อน หรือใช้ migration แยกเป็นไฟล์ย่อยใน production

## โครงสร้างตารางหลัก (MVP+)

- `departments`
- `user_profiles` (ผูกกับ `auth.users`)
- `tasks`
- `task_assignments`
- `task_status_history`
- `task_comments`
- `task_attachments`
- `notifications`
- `audit_logs`

## ฟังก์ชันสำคัญ

- `generate_task_no()` สร้างเลขงานอัตโนมัติ
- `assign_task(task_id, assignee_id, note)` มอบหมายงานและสร้าง notification
- `approve_task(task_id, is_approved, remark)` อนุมัติ/ส่งกลับแก้ไข
- `v_task_kpi_summary` view สำหรับ dashboard ผู้บริหาร

## หมายเหตุด้านความปลอดภัย

- ใช้ Row Level Security (RLS) ทุกตารางสำคัญ
- Policy แยกตามบทบาทและความเป็นเจ้าของข้อมูล
- ควรเก็บ `service_role` key ไว้ฝั่ง server เท่านั้น

## Next Step (React App)

- React + TypeScript + React Router
- Supabase JS สำหรับ auth/database/storage/realtime
- Dashboard ตามบทบาท (Admin / Officer / Head / General)
- เชื่อม query จาก `supabase/queries.sql` ไปยัง API layer หรือ hooks โดยตรง
