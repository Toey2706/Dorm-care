-- ข้อมูลตั้งต้น: คัดลอกไปวางใน Supabase Dashboard > SQL Editor แล้วแก้ค่าให้เป็นของจริงก่อนกด Run
--
-- ก่อนรัน ให้สร้างบัญชีพนักงานทุกคนที่ Authentication > Users > Add user > Create new user
--   ใส่อีเมลและรหัสผ่านชั่วคราว ติ๊ก Auto Confirm User
--   (ผู้ใช้จะถูกบังคับให้เปลี่ยนรหัสผ่านตอนเข้าใช้ครั้งแรก)

insert into public.rooms (room_no) values
  ('101'), ('102'), ('103')            -- แก้เป็นเลขห้องจริง
on conflict do nothing;

insert into public.settings (key, value) values
  ('contact_text', 'ติดต่อสำนักงานหอพัก โทร 0XX-XXX-XXXX')   -- ข้อความที่ผู้พักเห็นเมื่อกด "ติดต่อผู้ดูแล"
on conflict (key) do update set value = excluded.value;

-- ผูกบัญชีที่สร้างไว้กับชื่อและบทบาท (ADMIN = ผู้ดูแลหอพัก, TECHNICIAN = ช่างซ่อมบำรุง)
insert into public.staff (user_id, email, name, phone, role)
select u.id, u.email, s.name, s.phone, s.role
from (values
  ('admin@example.com', 'ชื่อผู้ดูแล', null, 'ADMIN'),
  ('tech1@example.com', 'ชื่อช่าง', null, 'TECHNICIAN')
) as s(email, name, phone, role)
join auth.users u on u.email = s.email
on conflict (user_id) do update set name = excluded.name, phone = excluded.phone, role = excluded.role;

-- ตรวจว่าครบทุกคน: ถ้าอีเมลไหนไม่ขึ้น แปลว่ายังไม่ได้สร้างบัญชีใน Authentication หรือพิมพ์อีเมลไม่ตรง
select email, name, role from public.staff order by role, name;
