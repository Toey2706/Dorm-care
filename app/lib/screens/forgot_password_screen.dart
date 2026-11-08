import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/auth_service.dart';

/// ลืมรหัสผ่าน: กรอกอีเมล รับรหัสทางอีเมล แล้วตั้งรหัสผ่านใหม่ในหน้าเดียวกัน
/// ตั้งเสร็จแล้วทุกเครื่องถูกออกจากระบบ และต้องยืนยัน OTP ใหม่ทุกเครื่อง
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});
  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final _email = TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_email, _code, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _request() => _run(() async {
        if (!_email.text.contains('@')) throw ApiException('กรุณากรอกอีเมล');
        await AuthService.instance.requestPasswordReset(_email.text);
        setState(() => _codeSent = true);
      });

  void _confirmReset() => _run(() async {
        if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) throw ApiException('กรุณากรอกรหัส 6 หลักจากอีเมล');
        if (_password.text.length < 8) throw ApiException('รหัสผ่านต้องยาวอย่างน้อย 8 ตัวอักษร');
        if (_password.text != _confirm.text) throw ApiException('รหัสผ่านทั้งสองช่องไม่ตรงกัน');
        await AuthService.instance.confirmPasswordReset(_email.text, _code.text, _password.text);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ตั้งรหัสผ่านใหม่แล้ว กรุณาเข้าสู่ระบบ')));
        Navigator.pop(context);
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ลืมรหัสผ่าน')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('กรอกอีเมลที่ใช้เข้าสู่ระบบ ระบบจะส่งรหัสสำหรับตั้งรหัสผ่านใหม่ไปให้'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _email,
                    enabled: !_codeSent,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'อีเมล'),
                  ),
                  const SizedBox(height: 12),
                  if (!_codeSent)
                    FilledButton(onPressed: _busy ? null : _request, child: const Text('ส่งรหัส'))
                  else ...[
                    const Text('ถ้าอีเมลนี้มีบัญชีในระบบ จะได้รับรหัสภายในไม่กี่นาที (ดูในโฟลเดอร์สแปมด้วย)'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(labelText: 'รหัส 6 หลัก', counterText: ''),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'รหัสผ่านใหม่ (อย่างน้อย 8 ตัว)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirm,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'ยืนยันรหัสผ่านใหม่'),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _busy ? null : _confirmReset, child: const Text('ตั้งรหัสผ่านใหม่')),
                    TextButton(onPressed: _busy ? null : _request, child: const Text('ไม่ได้รับรหัส ส่งอีกครั้ง')),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
