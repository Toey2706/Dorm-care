import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

const networkErrorMessage = 'การเชื่อมต่อขัดข้อง กรุณาตรวจสอบสัญญาณอินเทอร์เน็ตแล้วลองใหม่อีกครั้ง';
const sessionExpiredMessage = 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่อีกครั้ง';
bool isNetworkError(Object e) {
  if (e is TimeoutException || e is AuthRetryableFetchException) return true;
  final text = '${e.runtimeType} $e'.toLowerCase();
  return text.contains('clientexception') ||
      text.contains('socketexception') ||
      text.contains('failed to fetch') ||
      text.contains('xmlhttprequest') ||
      text.contains('networkerror') ||
      text.contains('failed host lookup') ||
      text.contains('connection closed') ||
      text.contains('connection refused');
}
bool isSessionError(Object e) {
  if (e is AuthRetryableFetchException) return false;
  if (e is AuthSessionMissingException) return true;
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    return m.contains('refresh token') || m.contains('jwt') || m.contains('session');
  }
  if (e is PostgrestException) {
    return e.code == 'PGRST301' || e.code == 'PGRST302' || e.code == 'PGRST303' || e.message.toLowerCase().contains('jwt expired');
  }
  return '$e'.toLowerCase().contains('jwt expired');
}
String friendlyError(Object e) {
  if (isNetworkError(e)) return networkErrorMessage;
  if (isSessionError(e)) return sessionExpiredMessage;
  final text = e.toString();
  if (RegExp(r'[ก-๙]').hasMatch(text)) return text;
  return 'ทำรายการไม่สำเร็จ กรุณาลองใหม่';
}
