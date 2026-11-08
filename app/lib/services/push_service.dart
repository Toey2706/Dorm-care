import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// แจ้งเตือนงานเข้าแอป Android ผ่าน Firebase Cloud Messaging
/// บนเว็บ (iPhone ผ่าน Safari) ยังไม่รองรับ ทุกเมธอดจึงไม่ทำอะไรถ้าไม่ใช่ Android หรือยังไม่ได้ตั้งค่า Firebase
class PushService {
  PushService._();
  static final instance = PushService._();

  /// ให้หน้าไหนก็แสดงแจ้งเตือนที่มาตอนเปิดแอปอยู่ได้ (ตอนแอปอยู่เบื้องหลัง ระบบ Android แสดงให้เอง)
  final messengerKey = GlobalKey<ScaffoldMessengerState>();

  bool _ready = false;
  String? _token;
  StreamSubscription<String>? _refreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;

  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android && firebaseAppId.isNotEmpty;

  Future<void> init() async {
    if (!supported || _ready) return;
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: firebaseApiKey,
          appId: firebaseAppId,
          messagingSenderId: firebaseSenderId,
          projectId: firebaseProjectId,
        ),
      );
      _ready = true;
      _foregroundSub = FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n == null) return;
        messengerKey.currentState?.showSnackBar(SnackBar(
          content: Text('${n.title ?? ''}\n${n.body ?? ''}'),
          duration: const Duration(seconds: 6),
        ));
      });
    } catch (e) {
      // แจ้งเตือนเป็นส่วนเสริม เปิด Firebase ไม่สำเร็จแอปต้องใช้งานต่อได้
      debugPrint('push init failed: $e');
    }
  }

  /// เรียกหลังยืนยันตัวตนครบแล้ว (ฐานข้อมูลรับรหัสเครื่องเฉพาะ session ที่ผ่าน OTP)
  Future<void> register() async {
    if (!_ready) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final perm = await messaging.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await messaging.getToken();
      if (token == null) return;
      await _save(token);
      _refreshSub ??= messaging.onTokenRefresh.listen(_save);
    } catch (e) {
      debugPrint('push register failed: $e');
    }
  }

  Future<void> _save(String token) async {
    _token = token;
    try {
      await Supabase.instance.client.rpc('register_device', params: {'p_token': token});
    } catch (e) {
      debugPrint('register_device failed: $e');
    }
  }

  /// เรียกก่อนออกจากระบบ ตอนที่ session ยังใช้ได้ เครื่องนี้จะไม่ได้แจ้งเตือนของบัญชีเดิมอีก
  Future<void> unregister() async {
    final token = _token;
    if (!_ready || token == null) return;
    try {
      await Supabase.instance.client.rpc('unregister_device', params: {'p_token': token});
    } catch (_) {
      // เน็ตหลุดตอนออกจากระบบ รหัสค้างในฐานข้อมูล ถ้ามีคนอื่นล็อกอินเครื่องนี้ รหัสจะถูกย้ายไปเป็นของคนนั้นเอง
    }
  }

  void dispose() {
    _refreshSub?.cancel();
    _foregroundSub?.cancel();
  }
}
