# การใช้น้ำใน Dorm-care

ผู้ดูแลที่เข้าสู่ระบบและยืนยันตัวตนแล้วเปิดแท็บ **การใช้น้ำ** เพื่อเลือกห้องและดูอัตราการไหล ปริมาณสะสมตั้งแต่บอร์ดเปิดเครื่อง และเวลาที่ ThingsBoard รับข้อมูลล่าสุด ระบบใช้สิทธิ์ผู้ดูแลและห้องที่เปิดใช้งานของ Dorm-care

Supabase Edge Function `water-usage` อ่านค่าล่าสุดของอุปกรณ์ที่ผูกกับห้องจาก ThingsBoard ผ่าน HTTPS แอปรับเฉพาะค่าที่แสดง ข้อมูลมิเตอร์อยู่ใน ThingsBoard และการตั้งค่าห้องอยู่ใน Edge Function Secrets

## ตั้งค่าห้องทดสอบ

1. ใน ThingsBoard เลือก Device ที่แสดง `flow_lpm` และ `total_liters_since_boot` ใน **Latest telemetry** จด Device ID จากรายละเอียดอุปกรณ์
2. ใช้ REST API key ของบัญชี ThingsBoard ที่อ่านอุปกรณ์ได้เท่าที่จำเป็น วิธีเชื่อมต่อนี้ใช้การยืนยันตัวตนแบบ API key ซึ่งรองรับใน ThingsBoard 4.3 ขึ้นไป คีย์นี้แยกจาก Device access token ที่ใช้ส่ง MQTT
3. ใน Supabase Dashboard ของโปรเจกต์ทดสอบ เปิด **Edge Functions → Secrets** แล้วใส่ค่าดังนี้

   | ชื่อ | ค่า |
   | --- | --- |
   | `THINGSBOARD_BASE_URL` | HTTPS origin ของ ThingsBoard เช่น `https://your-thingsboard.example.com` |
   | `THINGSBOARD_READ_API_KEY` | REST API key จากขั้นที่ 2 |
   | `THINGSBOARD_ROOM_DEVICES` | JSON ที่ใช้เลขห้องจริงเป็นคีย์และ Device ID เป็นค่า เช่น `{"301":"c38690c8-75f6-4229-b6da-05abb918079c"}` |
   | `THINGSBOARD_STALE_AFTER_SECONDS` | ระยะเวลาที่ถือว่าข้อมูลเก่าเป็นวินาที ค่าเริ่มต้น `180` |

4. จากโฟลเดอร์หลักของโปรเจกต์ ให้รันคำสั่งด้านล่างโดยใช้ Project ref ของ Supabase ที่ต้องการทดสอบ

   ```powershell
   supabase functions deploy water-usage --project-ref <project-ref>
   ```

   ฟังก์ชันนี้ตรวจ Bearer token เอง แล้วตรวจ `is_admin()` และสถานะห้องในฐานข้อมูล ฟังก์ชันอ่านข้อมูลห้องด้วยสิทธิ์ของผู้เรียกตามกฎเดิม

5. สำหรับทดสอบเว็บจากสาขานี้ ใช้ไฟล์กำหนดค่าแอปที่ชี้ไปยังโปรเจกต์เดียวกัน แล้วรันจากโฟลเดอร์ `app`

   ```powershell
   flutter pub get
   flutter run -d chrome --dart-define-from-file=config.json
   ```

## ตรวจผลก่อนเผยแพร่

- เปิดน้ำ แล้วเทียบ **Latest telemetry** กับแท็บ **การใช้น้ำ** ของห้องทดสอบ ค่าทั้งสองและเวลาอัปเดตควรตรงกันตามรอบส่งของอุปกรณ์
- เลือกห้องที่ยังไม่มีการผูกมิเตอร์ ควรเห็นสถานะรอตั้งค่า ลองด้วยบัญชีช่างและบัญชีที่ยังไม่ยืนยันตัวตน ผลที่คาดคือเข้าถึงข้อมูลค่าน้ำไม่ได้
- หยุดส่งข้อมูลจากบอร์ดเกินเกณฑ์ข้อมูลเก่า แล้วกดรีเฟรช ค่าล่าสุดควรแสดงพร้อมสถานะ **ข้อมูลเก่า**
- เปิดรายการใบแจ้งซ่อมและหน้าผูกห้องแบบเดิมเพื่อทดสอบถดถอย การปรับใช้ฝั่ง Supabase ใช้เฉพาะฟังก์ชันใหม่ ส่วนสาขา `main` ของ GitHub จะเผยแพร่เว็บและ APK ตามเวิร์กโฟลว์เดิมเมื่อรวมโค้ด

[การตั้ง Secret ของ Supabase](https://supabase.com/docs/guides/functions/secrets) · [ThingsBoard REST API](https://thingsboard.io/docs/reference/rest-api/)
