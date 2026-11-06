# เตรียมและรันแอป Flutter บนมือถือ Android ที่เสียบสาย USB (เปิด USB debugging แล้ว)
# ต้องมี Flutter 3.27 ขึ้นไป และ Android Studio (สำหรับ Android SDK)
# วิธีใช้: powershell -ExecutionPolicy Bypass -File scripts\app.ps1
# สคริปต์นี้ยังไม่เคยรันบน Windows จริง ถ้าหยุดที่ขั้นไหน ให้ส่งข้อความ error ทั้งหมดกลับมา

function Check($step) {
  if ($LASTEXITCODE -ne 0) { Write-Host "หยุดที่ขั้น: $step (exit code $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Write-Host 'ไม่พบ flutter: ติดตั้งตาม https://docs.flutter.dev/get-started/install/windows แล้วเปิด PowerShell ใหม่' -ForegroundColor Red; exit 1
}

Push-Location app
if (-not (Test-Path 'android')) {
  Write-Host '1/3 สร้างโฟลเดอร์ android (ไม่ทับไฟล์ใน lib)'
  flutter create --project-name dorm_care_staff --platforms android .; Check 'flutter create'
}

if (-not (Test-Path 'supabase.json')) {
  Write-Host 'ใส่ค่าจาก Supabase Dashboard > Project Settings > API'
  $url = Read-Host 'Project URL (https://xxxx.supabase.co)'
  $key = Read-Host 'anon public key'
  # anon key เปิดเผยได้ สิทธิ์จริงคุมด้วย RLS ในฐานข้อมูล แต่ไฟล์นี้ก็ไม่ต้องเข้า Git (อยู่ใน .gitignore)
  @{ SUPABASE_URL = $url.Trim(); SUPABASE_ANON_KEY = $key.Trim() } | ConvertTo-Json | Set-Content -Path 'supabase.json' -Encoding utf8
}

Write-Host '2/3 ติดตั้งแพ็กเกจ'
flutter pub get; Check 'flutter pub get'

Write-Host '3/3 รันแอปบนมือถือ'
flutter run --dart-define-from-file=supabase.json
Pop-Location
