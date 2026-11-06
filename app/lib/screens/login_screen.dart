import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'forgot_password_screen.dart';

/// ขั้นที่ 1: อีเมลและรหัสผ่าน ผ่านแล้ว AuthGate พาไปหน้า OTP (หรือเข้าเลยถ้าเครื่องนี้เคยยืนยันภายใน 30 วัน)
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_email.text.contains('@') || _password.text.isEmpty) {
      setState(() => _error = 'กรุณากรอกอีเมลและรหัสผ่าน');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.signIn(_email.text, _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('ระบบแจ้งซ่อมหอพัก', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  const Text('สำหรับผู้ดูแลหอพักและช่างซ่อมบำรุง', textAlign: TextAlign.center),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'อีเมล', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: !_show,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'รหัสผ่าน',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _show = !_show),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(_busy ? 'กำลังตรวจสอบ...' : 'เข้าสู่ระบบ'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ForgotPasswordScreen(initialEmail: _email.text.trim())),
                    ),
                    child: const Text('ลืมรหัสผ่าน?'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
