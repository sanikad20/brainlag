import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F3F3),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          child: Column(
            children: [
              const SizedBox(height: 20),

              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F8F8),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 70),

                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 0),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 0),
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F8F8),
                              borderRadius: BorderRadius.circular(32),
                              border: Border.all(
                                color: const Color(0xFF45199D),
                                width: 2.2,
                              ),
                            ),
                            child: Stack(
                              children: [
                                Positioned(
                                  left: 22,
                                  top: 85,
                                  child: Container(
                                    width: 68,
                                    height: 155,
                                    color: const Color(0xFFEFF2F5),
                                  ),
                                ),
                                Positioned(
                                  right: 22,
                                  top: 85,
                                  child: Container(
                                    width: 68,
                                    height: 155,
                                    color: const Color(0xFFEFF2F5),
                                  ),
                                ),
                                Center(
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                        color: const Color(0xFF2F56B0),
                                        width: 2,
                                      ),
                                    ),
                                    child: Image.asset(
                                      'assets/logo.png',
                                      width: 115,
                                      height: 115,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 18),
                        child: Text(
                          'Reset Your Focus, Reclaim Your Balance.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                      ),

                      const SizedBox(height: 26),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF45199D),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 15),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const LoginScreen(),
                                    ),
                                  );
                                },
                                child: const Text(
                                  'Login',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: Color(0xFF45199D),
                                    width: 1.5,
                                  ),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 15),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const RegisterScreen(),
                                    ),
                                  );
                                },
                                child: const Text(
                                  'Register',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Color(0xFF45199D),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 26),

                      SizedBox(
                        height: 120,
                        width: double.infinity,
                        child: Stack(
                          children: [
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 28,
                              child: Container(
                                height: 58,
                                color: const Color(0xFF8A5CE6),
                              ),
                            ),
                            Positioned(
                              left: 18,
                              bottom: 0,
                              child: Container(
                                width: 155,
                                height: 62,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF5C21CC),
                                  borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(120),
                                    topRight: Radius.circular(120),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 18,
                              bottom: 0,
                              child: Container(
                                width: 155,
                                height: 62,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF5C21CC),
                                  borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(120),
                                    topRight: Radius.circular(120),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}