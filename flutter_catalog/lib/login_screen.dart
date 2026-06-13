import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController otpController = TextEditingController();

  bool isLoading = false;
  bool obscurePassword = true;

  // 2FA state
  bool twoFAEnabled = false;
  bool otpSent = false;
  bool otpVerified = false;
  String? _generatedOtp; // In real app, backend generates & emails this
  User? _pendingUser;

  // ─── Helpers ────────────────────────────────────────────────────────────────

  String _generateOtp() {
    // In production: call your backend/Cloud Function to send OTP via email.
    // Here we generate a 6-digit code and show it in a SnackBar for demo.
    final otp = (100000 + (DateTime.now().millisecondsSinceEpoch % 900000))
        .toString();
    return otp;
  }

  void _sendOtp(User user) {
    _generatedOtp = _generateOtp();
    _pendingUser = user;
    setState(() => otpSent = true);

    // TODO: Replace this SnackBar with a real email send (Cloud Function / SendGrid).
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Demo OTP sent to ${user.email}: $_generatedOtp'),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  void _verifyOtp() {
    if (otpController.text.trim() == _generatedOtp) {
      setState(() => otpVerified = true);
      _navigateHome(_pendingUser!);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid OTP. Please try again.')),
      );
    }
  }

  void _navigateHome(User user) {
    final displayName = user.displayName?.trim();
    final homeName =
        (displayName != null && displayName.isNotEmpty) ? displayName : user.email!;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => HomeScreen(name: homeName)),
    );
  }

  // ─── Login ──────────────────────────────────────────────────────────────────

  Future<void> loginUser() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (!mounted) return;

      final user = credential.user!;

      if (twoFAEnabled) {
        // Trigger OTP flow instead of going home directly
        _sendOtp(user);
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Login successful')));
        _navigateHome(user);
      }
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message ?? 'Login failed')));
    } finally {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  // ─── Forgot Password ─────────────────────────────────────────────────────────

  Future<void> _showForgotPasswordDialog() async {
    final resetEmailController =
        TextEditingController(text: emailController.text.trim());

    await showDialog(
      context: context,
      builder: (ctx) {
        bool sending = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Text('Reset Password',
                style: TextStyle(fontWeight: FontWeight.w700)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter your registered email address. We\'ll send you a password reset link.',
                  style: TextStyle(color: Colors.black54, fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: resetEmailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: sending
                    ? null
                    : () async {
                        final email = resetEmailController.text.trim();
                        if (email.isEmpty) return;
                        setDialogState(() => sending = true);
                        try {
                          await FirebaseAuth.instance
                              .sendPasswordResetEmail(email: email);
                          if (!mounted) return;
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Password reset email sent! Check your inbox.')),
                          );
                        } on FirebaseAuthException catch (e) {
                          setDialogState(() => sending = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content:
                                    Text(e.message ?? 'Could not send email')),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF45199D),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Send Link',
                        style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── OTP Sheet ───────────────────────────────────────────────────────────────

  Widget _buildOtpSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 28),
        const Text(
          'Two-Step Verification',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: 6),
        Text(
          'An OTP has been sent to ${emailController.text.trim()}.',
          style: const TextStyle(color: Colors.black54, fontSize: 13),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: InputDecoration(
            labelText: 'Enter OTP',
            counterText: '',
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _verifyOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF45199D),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Verify OTP',
                style: TextStyle(color: Colors.white)),
          ),
        ),
        TextButton(
          onPressed: () {
            if (_pendingUser != null) _sendOtp(_pendingUser!);
          },
          child: const Text('Resend OTP',
              style: TextStyle(color: Color(0xFF45199D))),
        ),
      ],
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F3F3),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3F3F3),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text('Login', style: TextStyle(color: Colors.black)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(
                      blurRadius: 8,
                      color: Colors.black12,
                      offset: Offset(0, 3)),
                ],
              ),
              child: Column(
                children: [
                  Image.asset('assets/logo.png', width: 95, height: 95),
                  const SizedBox(height: 16),
                  const Text(
                    'Welcome Back',
                    style: TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 24),

                  // Email
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Password
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14)),
                      suffixIcon: IconButton(
                        icon: Icon(obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () =>
                            setState(() => obscurePassword = !obscurePassword),
                      ),
                    ),
                  ),

                  // Forgot Password
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _showForgotPasswordDialog,
                      child: const Text(
                        'Forgot Password?',
                        style: TextStyle(color: Color(0xFF45199D)),
                      ),
                    ),
                  ),

                  // 2FA Toggle
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F0FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.security_outlined,
                            color: Color(0xFF45199D), size: 20),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Two-Step Verification (OTP)',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                        Switch(
                          value: twoFAEnabled,
                          activeColor: const Color(0xFF45199D),
                          onChanged: (val) {
                            setState(() {
                              twoFAEnabled = val;
                              otpSent = false;
                              otpVerified = false;
                              otpController.clear();
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Login Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isLoading || otpSent ? null : loginUser,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF45199D),
                        disabledBackgroundColor: const Color(0xFF45199D),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5))
                          : const Text('Login',
                              style: TextStyle(color: Colors.white)),
                    ),
                  ),

                  // OTP section appears after successful login with 2FA on
                  if (otpSent) _buildOtpSection(),

                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const RegisterScreen()),
                    ),
                    child: const Text("Don't have an account? Register"),
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