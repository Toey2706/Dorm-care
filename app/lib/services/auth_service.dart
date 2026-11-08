import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api.dart';
import 'push_service.dart';

/// สถานะหลังล็อกอินด้วยรหัสผ่าน ใช้เลือกว่าจะพาไปหน้าไหน
class AuthStatus {
  AuthStatus.fromJson(Map<String, dynamic> j)
      : registered = j['registered'] == true,
        verified = j['verified'] == true,
        mustChangePassword = j['must_change_password'] == true,
        emailMasked = (j['email_masked'] as String?) ?? '';

  final bool registered;
  final bool verified;
  final bool mustChangePassword;
  final String emailMasked;
}

/// ล็อกอิน 2 ชั้น: รหัสผ่าน แล้ว OTP ทางอีเมล (หรือเครื่องที่เคยยืนยันภายใน 30 วัน)
/// ฐานข้อมูลไม่ให้ session ที่ยังไม่ยืนยันอ่านหรือแก้ข้อมูลใด ๆ หน้าจอจึงเป็นแค่ทางเดิน ไม่ใช่ตัวกั้น
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  SupabaseClient get _sb => Supabase.instance.client;
  final _secure = const FlutterSecureStorage();

  /// เปลี่ยนค่าเมื่อผ่านขั้นใดขั้นหนึ่ง ให้ AuthGate ตรวจสถานะใหม่
  final changes = ValueNotifier<int>(0);
  void _changed() => changes.value++;

  String _deviceKey(String userId) => 'device_token_$userId';

  Future<void> signIn(String email, String password) async {
    try {
      await _sb.auth.signInWithPassword(email: email.trim().toLowerCase(), password: password);
    } on AuthException catch (e) {
      if (e.statusCode == '429') throw ApiException('ลองเข้าสู่ระบบบ่อยเกินไป กรุณารอสักครู่');
      throw ApiException('อีเมลหรือรหัสผ่านไม่ถูกต้อง');
    }
  }

  Future<AuthStatus> status() async {
    final r = await _sb.rpc('auth_status');
    return AuthStatus.fromJson(Map<String, dynamic>.from(r as Map));
  }

  /// เครื่องนี้เคยยืนยัน OTP ภายใน 30 วัน: ผ่านได้โดยไม่ต้องขอรหัสใหม่
  Future<bool> tryTrustedDevice() async {
    final user = _sb.auth.currentUser;
    if (user == null) return false;
    final token = await _secure.read(key: _deviceKey(user.id));
    if (token == null) return false;
    final ok = await _sb.rpc('verify_trusted_device', params: {'p_device_token': token}) == true;
    // โทเคนหมดอายุหรือถูกล้างหลังเปลี่ยนรหัสผ่าน ลบทิ้งจะได้ไม่ลองซ้ำทุกครั้ง
    if (!ok) await _secure.delete(key: _deviceKey(user.id));
    return ok;
  }

  /// คืนจำนวนวินาทีที่ต้องรอก่อนขอรหัสใหม่ได้
  Future<int> sendOtp() async {
    try {
      await _sb.functions.invoke('login-otp-send', body: {'channel': 'EMAIL'});
      return 60;
    } on FunctionException catch (e) {
      final d = e.details is Map ? Map<String, dynamic>.from(e.details as Map) : <String, dynamic>{};
      if (e.status == 429) return (d['retry_in'] as num?)?.toInt() ?? 60;
      throw ApiException((d['message'] as String?) ?? 'ส่งรหัสไม่สำเร็จ กรุณาลองใหม่');
    }
  }

  Future<void> verifyOtp(String code) async {
    final r = Map<String, dynamic>.from(await _sb.rpc('verify_login_otp', params: {'p_code': code.trim()}) as Map);
    if (r['ok'] != true) {
      throw ApiException(switch (r['error']) {
        'EXPIRED' => 'รหัสหมดอายุ กรุณากดส่งรหัสใหม่',
        'TOO_MANY' => 'ใส่รหัสผิดหลายครั้งเกินไป กรุณากดส่งรหัสใหม่',
        _ => 'รหัสไม่ถูกต้อง',
      });
    }
    await _secure.write(key: _deviceKey(_sb.auth.currentUser!.id), value: r['device_token'] as String);
    _changed();
  }

  /// เปลี่ยนรหัสผ่านครั้งแรกที่เข้าใช้ (บัญชีที่ผู้ดูแลระบบสร้างให้มาพร้อมรหัสชั่วคราว)
  Future<void> changePassword(String newPassword) async {
    try {
      await _sb.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      throw ApiException(e.code == 'same_password' ? 'รหัสผ่านใหม่ต้องไม่ซ้ำกับรหัสเดิม' : 'เปลี่ยนรหัสผ่านไม่สำเร็จ: ${e.message}');
    }
    await _sb.rpc('password_changed');
    _changed();
  }

  Future<void> requestPasswordReset(String email) => _invoke('password-reset-request', {'email': email.trim()});

  Future<void> confirmPasswordReset(String email, String code, String newPassword) =>
      _invoke('password-reset-confirm', {'email': email.trim(), 'code': code.trim(), 'new_password': newPassword});

  Future<void> _invoke(String fn, Map<String, dynamic> body) async {
    try {
      await _sb.functions.invoke(fn, body: body);
    } on FunctionException catch (e) {
      final d = e.details is Map ? Map<String, dynamic>.from(e.details as Map) : <String, dynamic>{};
      throw ApiException((d['message'] as String?) ?? 'ทำรายการไม่สำเร็จ กรุณาลองใหม่');
    }
  }

  Future<void> signOut() async {
    await PushService.instance.unregister();
    try {
      await _sb.rpc('end_session');
    } catch (_) {
      // ออกจากระบบต่อแม้เน็ตหลุด session ฝั่งเซิร์ฟเวอร์ถูกยกเลิกด้วย signOut อยู่แล้ว
    }
    await _sb.auth.signOut();
  }
}
