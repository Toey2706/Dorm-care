/// ใส่ตอนรันหรือ build เช่น
/// flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJ...
/// (scripts/app.ps1 อ่านจากไฟล์ app/.env ให้) anon key เปิดเผยได้ สิทธิ์จริงคุมด้วย RLS ในฐานข้อมูล
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
