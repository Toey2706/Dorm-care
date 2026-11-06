const TZ = 'Asia/Bangkok';

/** ปี พ.ศ. ตามเวลาประเทศไทย */
export function buddhistYear(date) {
  const year = Number(new Intl.DateTimeFormat('en-US', { timeZone: TZ, year: 'numeric' }).format(date));
  return year + 543;
}

/** เลขที่ใบแจ้งซ่อมรูปแบบเดียวกับ Prototype เช่น R2569-0041 */
export function ticketNumber(year, sequence) {
  return `R${year}-${String(sequence).padStart(4, '0')}`;
}

/** วันที่แบบไทยสั้น เช่น 26 ต.ค. 2569 08:40 */
export function thaiDateTime(date) {
  const parts = new Intl.DateTimeFormat('th-TH-u-ca-buddhist', {
    timeZone: TZ,
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).formatToParts(date);
  const get = (type) => (parts.find((p) => p.type === type) || {}).value || '';
  return `${get('day')} ${get('month')} ${get('year')} ${get('hour')}:${get('minute')}`;
}

/** ข้อความแสดงสถานะภาษาไทย ใช้ร่วมกันใน LINE และแอป */
export function statusLabel(status, assigned) {
  if (status === 'PENDING') return assigned ? 'รอดำเนินการ (มอบหมายแล้ว)' : 'รอดำเนินการ';
  if (status === 'REPAIRING') return 'กำลังซ่อม';
  if (status === 'COMPLETED') return 'ซ่อมเสร็จแล้ว';
  return status;
}
