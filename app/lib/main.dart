import 'dart:async';

import 'package:flutter/material.dart';

import 'theme.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'models.dart';
import 'screens/admin_home.dart';
import 'screens/change_password_screen.dart';
import 'screens/login_screen.dart';
import 'screens/otp_screen.dart';
import 'screens/tech_home.dart';
import 'services/api.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('ยังไม่ได้ตั้งค่า SUPABASE_URL / SUPABASE_ANON_KEY')))));
    return;
  }
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  await initializeDateFormatting('th');
  runApp(const DormCareApp());
}

class DormCareApp extends StatelessWidget {
  const DormCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ระบบแจ้งซ่อมหอพัก',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      builder: constrainWidth,
      home: const AuthGate(),
    );
  }
}

/// ลำดับ: รหัสผ่าน -> OTP (หรือเครื่องที่จำไว้) -> เปลี่ยนรหัสชั่วคราว (ครั้งแรก) -> หน้าตามบทบาท
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _auth = AuthService.instance;
  Future<Widget>? _page;
  String? _sessionUser;
  StreamSubscription<AuthState>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      // ต่ออายุโทเคนไม่ต้องตรวจใหม่ ตรวจเฉพาะตอนเข้าหรือออกจากระบบ
      final uid = data.session?.user.id;
      if (uid != _sessionUser) {
        _sessionUser = uid;
        _recheck();
      }
    });
    _auth.changes.addListener(_recheck);
    _sessionUser = Supabase.instance.client.auth.currentUser?.id;
    _recheck();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _auth.changes.removeListener(_recheck);
    super.dispose();
  }

  void _recheck() {
    if (mounted) setState(() => _page = _resolve());
  }

  Future<Widget> _resolve() async {
    if (Supabase.instance.client.auth.currentSession == null) return const LoginScreen();
    var status = await _auth.status();
    if (!status.registered) return const NotRegisteredScreen();
    if (!status.verified && await _auth.tryTrustedDevice()) status = await _auth.status();
    if (!status.verified) return OtpScreen(emailMasked: status.emailMasked);
    if (status.mustChangePassword) return const ChangePasswordScreen();
    final Staff? me = await Api.instance.me();
    if (me == null) return const NotRegisteredScreen();
    return me.isAdmin ? AdminHome(me: me) : TechHome(me: me);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _page,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('เชื่อมต่อระบบไม่สำเร็จ'),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _recheck, child: const Text('ลองใหม่')),
                  TextButton(onPressed: _auth.signOut, child: const Text('ออกจากระบบ')),
                ],
              ),
            ),
          );
        }
        if (snap.connectionState != ConnectionState.done || snap.data == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return snap.data!;
      },
    );
  }
}

class NotRegisteredScreen extends StatelessWidget {
  const NotRegisteredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 12),
              const Text('บัญชีนี้ไม่ได้ลงทะเบียนเป็นผู้ดูแลหรือช่าง หรือถูกปิดการใช้งาน', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: AuthService.instance.signOut, child: const Text('ออกจากระบบ')),
            ],
          ),
        ),
      ),
    );
  }
}
