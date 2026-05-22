import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'continuous_monitoring_screen.dart';

class UsageAccessSetupScreen extends StatefulWidget {
  const UsageAccessSetupScreen({super.key});

  @override
  State<UsageAccessSetupScreen> createState() => _UsageAccessSetupScreenState();
}

class _UsageAccessSetupScreenState extends State<UsageAccessSetupScreen>
    with WidgetsBindingObserver {
  static const MethodChannel _channel =
      MethodChannel('brainlag/usage_access');

  bool accessGranted = false;
  bool isChecking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    checkUsageAccessPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      checkUsageAccessPermission();
    }
  }

  Future<void> openUsageSettings() async {
    try {
      await _channel.invokeMethod('openUsageAccessSettings');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open settings: $e')),
      );
    }
  }

  Future<void> checkUsageAccessPermission() async {
    setState(() {
      isChecking = true;
    });

    try {
      final bool granted =
          await _channel.invokeMethod('checkUsageAccessPermission');

      if (!mounted) return;
      setState(() {
        accessGranted = granted;
        isChecking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        accessGranted = false;
        isChecking = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Permission check failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0F),
        title: const Text(
          'Settings Access',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF232325),
                borderRadius: BorderRadius.circular(16),
              ),
              child: isChecking
                  ? const Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Checking usage access permission...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Text(
                      accessGranted
                          ? 'Usage access granted. You can now start continuous monitoring.'
                          : 'Grant usage access from Android settings to begin continuous monitoring.',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: openUsageSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF45199D),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Open Settings',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: checkUsageAccessPermission,
                child: const Text('Check Again'),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: accessGranted
                    ? () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ContinuousMonitoringScreen(),
                          ),
                        );
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Start Continuous Monitoring',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}