import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// ขั้นที่ 2: เลือกช่องทางรับรหัส แล้วกรอกรหัส 6 หลัก ผ่านแล้วเครื่องนี้ไม่ต้องใช้ OTP อีก 30 วัน
/// ตอนนี้มีช่องทางเดียวคืออีเมล เพราะ SMS ต้องใช้ผู้ให้บริการที่เสียเงิน
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.emailMasked});
  final String emailMasked;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _code = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _error;
  int _wait = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _countdown(int seconds) {
    _timer?.cancel();
    setState(() => _wait = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _wait <= 1) {
        t.cancel();
        if (mounted) setState(() => _wait = 0);
        return;
      }
      setState(() => _wait--);
    });
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final wait = await AuthService.instance.sendOtp();
      if (!mounted) return;
      setState(() => _sent = true);
      _countdown(wait);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) {
      setState(() => _error = 'กรุณากรอกรหัส 6 หลัก');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.verifyOtp(_code.text);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('ยืนยันตัวตน'),
        actions: [TextButton(onPressed: AuthService.instance.signOut, child: const Text('ยกเลิก'))],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('เลือกช่องทางรับรหัสยืนยัน'),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.email_outlined),
                      title: const Text('อีเมล'),
                      subtitle: Text(widget.emailMasked),
                      trailing: const Icon(Icons.check_circle),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _busy || _wait > 0 ? null : _send,
                    child: Text(_wait > 0 ? 'ส่งรหัสใหม่ได้ใน $_wait วินาที' : (_sent ? 'ส่งรหัสอีกครั้ง' : 'ส่งรหัส')),
                  ),
                  if (_sent) ...[
                    const SizedBox(height: 24),
                    Text('ส่งรหัสไปที่ ${widget.emailMasked} แล้ว รหัสใช้ได้ 10 นาที', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      onSubmitted: (_) => _verify(),
                      decoration: const InputDecoration(labelText: 'รหัส 6 หลัก', border: OutlineInputBorder(), counterText: ''),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _busy ? null : _verify, child: const Text('ยืนยัน')),
                    const SizedBox(height: 8),
                    Text('ยืนยันแล้ว เครื่องนี้ไม่ต้องใส่รหัสอีก 30 วัน', style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
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
