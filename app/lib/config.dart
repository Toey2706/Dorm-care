/// ใส่ตอนรันหรือ build เช่น
/// flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJ...
/// (scripts/app.ps1 อ่านจากไฟล์ app/.env ให้) anon key เปิดเผยได้ สิทธิ์จริงคุมด้วย RLS ในฐานข้อมูล
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// ค่าจาก google-services.json ของ Firebase ใช้เฉพาะแจ้งเตือนบน Android ค่าเหล่านี้เปิดเผยได้ (Google ออกแบบให้ฝังในแอป)
/// ว่างไว้ได้ แอปทำงานปกติแค่ไม่มีแจ้งเตือน
const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
const firebaseSenderId = String.fromEnvironment('FIREBASE_SENDER_ID');
const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
