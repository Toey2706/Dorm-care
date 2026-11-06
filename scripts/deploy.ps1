# Deploy ฐานข้อมูลและ Edge Functions ขึ้น Supabase
# ต้องมี Node.js 20 ขึ้นไป (ใช้ npx เรียก Supabase CLI ไม่ต้องติดตั้งแยก) ไม่ต้องมี Docker เพราะ deploy ฟังก์ชันด้วย --use-api
# วิธีใช้: เปิด PowerShell ที่โฟลเดอร์ dorm-system แล้วพิมพ์
#   powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1 -ProjectRef <รหัสโปรเจกต์ 20 ตัวอักษรจาก URL ของ Dashboard>
# ใส่ -SkipSecrets ถ้าเคยตั้งค่า LINE และ Gmail ไปแล้ว
# สคริปต์นี้ยังไม่เคยรันบน Windows จริง ถ้าหยุดที่ขั้นไหน ให้ส่งข้อความ error ทั้งหมดกลับมา

param(
  [Parameter(Mandatory = $true)][string]$ProjectRef,
  [switch]$SkipSecrets
)

function Check($step) {
  if ($LASTEXITCODE -ne 0) { Write-Host "หยุดที่ขั้น: $step (exit code $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
}
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Host 'ไม่พบ Node.js: ติดตั้งจาก https://nodejs.org (เลือก LTS) แล้วเปิด PowerShell ใหม่' -ForegroundColor Red; exit 1
}

Write-Host '1/5 รันเทสต์ของ Edge Functions'
Push-Location supabase\functions
node --test; $code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { Write-Host 'เทสต์ไม่ผ่าน หยุดก่อน deploy' -ForegroundColor Red; exit 1 }

Write-Host '2/5 ล็อกอิน Supabase (เปิดเบราว์เซอร์ให้กดยืนยัน) และเชื่อมกับโปรเจกต์'
npx --yes supabase login; Check 'supabase login'
npx --yes supabase link --project-ref $ProjectRef; Check 'supabase link (ถ้าถามรหัสผ่านฐานข้อมูล ใช้รหัสที่ตั้งตอนสร้างโปรเจกต์)'

Write-Host '3/5 สร้างตารางและฟังก์ชันในฐานข้อมูล'
# CLI รุ่นใหม่ชี้ไปที่ฐานข้อมูลในเครื่อง (Docker) โดยปริยาย ต้องบอกให้ใช้โปรเจกต์บนคลาวด์
npx --yes supabase db push --remote; Check 'supabase db push --remote'

if (-not $SkipSecrets) {
  Write-Host '4/5 ใส่ค่าลับ (พิมพ์แล้วจะไม่แสดงบนจอ)'
  $names = @(
    @('LINE_CHANNEL_SECRET', 'LINE Channel secret'),
    @('LINE_CHANNEL_ACCESS_TOKEN', 'LINE Channel access token (long-lived)'),
    @('GMAIL_USER', 'อีเมล Gmail ของทีมที่ใช้ส่ง OTP'),
    @('GMAIL_APP_PASSWORD', 'App Password 16 ตัวของ Gmail (ไม่ใช่รหัสผ่านปกติ)')
  )
  $pairs = @()
  foreach ($n in $names) {
    $secure = Read-Host -AsSecureString $n[1]
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
    if (-not $plain) { Write-Host "ยังไม่ได้ใส่ $($n[0])" -ForegroundColor Red; exit 1 }
    $pairs += "$($n[0])=$($plain -replace '\s', '')"
  }
  # ส่งผ่านไฟล์ชั่วคราวแทน argument เพื่อไม่ให้ค่าลับไปค้างในประวัติคำสั่ง แล้วลบทิ้งทันที
  $tmp = New-TemporaryFile
  Set-Content -Path $tmp -Value $pairs -Encoding ascii
  npx --yes supabase secrets set --env-file $tmp --project-ref $ProjectRef; $code = $LASTEXITCODE
  Remove-Item $tmp
  if ($code -ne 0) { Write-Host 'หยุดที่ขั้น: supabase secrets set' -ForegroundColor Red; exit 1 }
} else {
  Write-Host '4/5 ข้ามการใส่ค่าลับ'
}

Write-Host '5/5 Deploy Edge Functions (ใช้ --use-api จึงไม่ต้องมี Docker)'
foreach ($fn in @('line-webhook', 'login-otp-send', 'password-reset-request', 'password-reset-confirm', 'notify-resident')) {
  npx --yes supabase functions deploy $fn --use-api --project-ref $ProjectRef; Check "deploy $fn"
}

Write-Host ''
Write-Host 'เสร็จแล้ว นำ URL นี้ไปใส่เป็น Webhook URL ใน LINE Developers Console:' -ForegroundColor Green
Write-Host "https://$ProjectRef.supabase.co/functions/v1/line-webhook"
