import 'package:flutter/material.dart';

/// สีหลักของระบบ (น้ำเงินเข้ม) ใช้ค่าตรงตัวแทนสีที่ fromSeed คำนวณ เพื่อให้ตรงกับ mockup ที่ทีมเลือก
const brand = Color(0xFF1E4E8C);
const pageBackground = Color(0xFFF4F6FA);
const mutedText = Color(0xFF5B6577);

/// ฟอนต์ฝังในแอป ไม่โหลดจากเน็ต เพราะบน Flutter web ถ้ารอโหลดฟอนต์จะเห็นกล่องสี่เหลี่ยมแทนตัวอักษรไทยช่วงแรก
const fontFamily = 'IBMPlexSansThai';

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: brand).copyWith(primary: brand, onPrimary: Colors.white);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: fontFamily);
  // ตัวอักษรไทยมีสระบนล่าง ขนาดเริ่มต้นของ Material อ่านยากบนมือถือ จึงขยายข้อความเนื้อหาเป็น 16 และข้อความรองเป็น 14
  final text = base.textTheme.copyWith(
    bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 17),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 16),
    bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 14, color: mutedText),
    labelMedium: base.textTheme.labelMedium?.copyWith(fontSize: 14, color: mutedText),
    titleSmall: base.textTheme.titleSmall?.copyWith(fontSize: 16, fontWeight: FontWeight.w500),
  );
  final roundedButton = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: pageBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Color(0xFF1B2333),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      titleTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF1B2333)),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: roundedButton,
        textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: roundedButton,
        textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    // ปุ่มตัวอักษรที่เหลือ (ออกจากระบบ ส่งรหัสอีกครั้ง) ให้พื้นที่กดอย่างน้อย 48 ตามขนาดนิ้ว
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w500),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFC9D1DE)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      labelStyle: const TextStyle(fontFamily: fontFamily, fontSize: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    navigationBarTheme: const NavigationBarThemeData(backgroundColor: Colors.white, surfaceTintColor: Colors.transparent),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// สีของสถานะ เก็บไว้ที่เดียวให้ทุกหน้าใช้ตรงกัน คู่สีพื้นกับตัวอักษรผ่านเกณฑ์ contrast 4.5:1
class StageStyle {
  const StageStyle(this.background, this.foreground, this.icon);
  final Color background;
  final Color foreground;
  final IconData icon;

  static const pending = StageStyle(Color(0xFFFEF3C7), Color(0xFF8A3B07), Icons.schedule);
  static const repairing = StageStyle(Color(0xFFDBEAFE), Color(0xFF1E3A8A), Icons.build_outlined);
  static const awaitingLine = StageStyle(Color(0xFFEDE9FE), Color(0xFF4C1D95), Icons.send_outlined);
  static const done = StageStyle(Color(0xFFDCFCE7), Color(0xFF14532D), Icons.check_circle_outline);
}

const categoryIcons = <String, IconData>{
  'PLUMBING': Icons.water_drop_outlined,
  'ELECTRICAL': Icons.bolt_outlined,
  'AIRCON': Icons.ac_unit,
  'FURNITURE': Icons.chair_outlined,
  'OTHER': Icons.handyman_outlined,
};

/// จอคอมพิวเตอร์: ให้เนื้อหาอยู่กลางจอกว้างไม่เกิน 720 การ์ดจะได้ไม่ยืดเต็มจอ
Widget constrainWidth(BuildContext context, Widget? child) {
  return ColoredBox(
    color: const Color(0xFFE9EDF3),
    child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: child)),
  );
}
