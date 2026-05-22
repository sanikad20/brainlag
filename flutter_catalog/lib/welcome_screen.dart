import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F3F3),
      body: Stack(
        clipBehavior: Clip.none, // Allows the wave to extend outside the screen
        children: [
          /// ---------------- Main Content ----------------
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              child: Column(
                children: [
                  const SizedBox(height: 20),

                  /// Main Rounded Card
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F8F8),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Column(
                        children: [
                          const SizedBox(height: 60),

                          /// ---------------- Logo Section ----------------
                          Expanded(
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                /// Left Decorative Panel
                                Positioned(
                                  left: 30,
                                  child: Container(
                                    width: 80,
                                    height: 180,
                                    color: const Color(0xFFEFF2F5),
                                  ),
                                ),

                                /// Right Decorative Panel
                                Positioned(
                                  right: 30,
                                  child: Container(
                                    width: 80,
                                    height: 180,
                                    color: const Color(0xFFEFF2F5),
                                  ),
                                ),

                                /// Large Logo (No Container)
                                Image.asset(
                                  'assets/logo.png',
                                  width: screenWidth * 0.85,
                                  fit: BoxFit.contain,
                                ),
                              ],
                            ),
                          ),

                          /// ---------------- Tagline ----------------
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              'Reset Your Focus, Reclaim Your Balance.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.black87,
                              ),
                            ),
                          ),

                          const SizedBox(height: 30),

                          /// ---------------- Buttons ----------------
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              children: [
                                /// Login Button
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF5C21CC),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14),
                                      ),
                                      elevation: 4,
                                    ),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const LoginScreen(),
                                        ),
                                      );
                                    },
                                    child: const Text(
                                      'Login',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),

                                /// Register Button
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                        color: Color(0xFF5C21CC),
                                        width: 1.5,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14),
                                      ),
                                    ),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const RegisterScreen(),
                                        ),
                                      );
                                    },
                                    child: const Text(
                                      'Register',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Color(0xFF5C21CC),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 120), // Space for wave
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

          /// ---------------- Bottom Waves ----------------
          Positioned(
            bottom: -10,
            left: -40,
            right: -40,
            child: SizedBox(
              width: screenWidth + 80, // Extend beyond screen edges
              height: 180,
              child: Stack(
                children: const [
                  CustomPaint(
                    size: Size(double.infinity, 180),
                    painter: LightWavePainter(),
                  ),
                  CustomPaint(
                    size: Size(double.infinity, 180),
                    painter: DarkWavePainter(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------- Light Purple Wave ----------------
class LightWavePainter extends CustomPainter {
  const LightWavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF8A5CE6)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, size.height * 0.4)
      ..quadraticBezierTo(
        size.width * 0.25,
        size.height * 0.15,
        size.width * 0.5,
        size.height * 0.4,
      )
      ..quadraticBezierTo(
        size.width * 0.75,
        size.height * 0.6,
        size.width,
        size.height * 0.4,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

/// ---------------- Dark Purple Wave ----------------
class DarkWavePainter extends CustomPainter {
  const DarkWavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF5C21CC)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, size.height * 0.6)
      ..quadraticBezierTo(
        size.width * 0.3,
        size.height * 0.85,
        size.width * 0.6,
        size.height * 0.6,
      )
      ..quadraticBezierTo(
        size.width * 0.9,
        size.height * 0.4,
        size.width,
        size.height * 0.7,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}