import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class PredictionScreen extends StatefulWidget {
  const PredictionScreen({super.key});

  @override
  State<PredictionScreen> createState() => _PredictionScreenState();
}

class _PredictionScreenState extends State<PredictionScreen> {
  // Android emulator
  final String apiUrl = 'http://10.0.2.2:8000/predict';

  // For laptop/web use:
  // final String apiUrl = 'http://127.0.0.1:8000/predict';

  // For real phone use:
  // final String apiUrl = 'http://YOUR_PC_IP:8000/predict';

  bool isLoading = false;

  double sleepHours = 7;
  double sleepQuality = 3;
  double appSwitchesPerHour = 20;
  double socialAppRatio = 0.4;
  double productivityRatio = 0.6;
  double uniqueAppsPerDay = 12;
  double callCount = 5;
  double totalCallMin = 30;
  double missedCallRatio = 0.1;
  double smsCount = 20;
  double smsSentRatio = 0.5;
  double screenTimeHours = 6;
  double exerciseMinPerWeek = 120;
  double socialHoursPerWeek = 10;

  String predictedStress = '--';
  String stressLevel = '--';
  String selectedModel = 'Burnout Neural Model';

  Future<void> runPrediction() async {
    setState(() {
      isLoading = true;
    });

    final body = {
      "sleep_hours": sleepHours,
      "sleep_quality": sleepQuality,
      "app_switches_per_hour": appSwitchesPerHour,
      "social_app_ratio": socialAppRatio,
      "productivity_ratio": productivityRatio,
      "unique_apps_per_day": uniqueAppsPerDay,
      "call_count": callCount,
      "total_call_min": totalCallMin,
      "missed_call_ratio": missedCallRatio,
      "sms_count": smsCount,
      "sms_sent_ratio": smsSentRatio,
      "screen_time_hours": screenTimeHours,
      "exercise_min_per_week": exerciseMinPerWeek,
      "social_hours_per_week": socialHoursPerWeek,
    };

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          predictedStress =
              double.parse(data["prediction"].toString()).toStringAsFixed(2);
          stressLevel = data["stress_level"].toString();
        });
      } else {
        setState(() {
          predictedStress = 'Error';
          stressLevel = 'API failed: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        predictedStress = 'Error';
        stressLevel = e.toString();
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void resetFields() {
    setState(() {
      sleepHours = 7;
      sleepQuality = 3;
      appSwitchesPerHour = 20;
      socialAppRatio = 0.4;
      productivityRatio = 0.6;
      uniqueAppsPerDay = 12;
      callCount = 5;
      totalCallMin = 30;
      missedCallRatio = 0.1;
      smsCount = 20;
      smsSentRatio = 0.5;
      screenTimeHours = 6;
      exerciseMinPerWeek = 120;
      socialHoursPerWeek = 10;
      predictedStress = '--';
      stressLevel = '--';
    });
  }

  Color getStressColor() {
    if (stressLevel.contains('Low')) return Colors.green;
    if (stressLevel.contains('Moderate')) return Colors.orange;
    if (stressLevel.contains('High')) return Colors.red;
    return Colors.white;
  }

  Widget buildSliderCard({
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF232325),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 30,
                child: Text(
                  min % 1 == 0 ? min.toInt().toString() : min.toString(),
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              Expanded(
                child: Slider(
                  value: value,
                  min: min,
                  max: max,
                  divisions: divisions,
                  label: displayValue,
                  activeColor: Colors.orange,
                  inactiveColor: Colors.white24,
                  onChanged: onChanged,
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  max % 1 == 0 ? max.toInt().toString() : max.toString(),
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 78,
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1C),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  displayValue,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildLeftPanel() {
    return Column(
      children: [
        buildSliderCard(
          title: 'Sleep hours',
          value: sleepHours,
          min: 0,
          max: 12,
          divisions: 12,
          displayValue: sleepHours.toStringAsFixed(0),
          onChanged: (v) => setState(() => sleepHours = v),
        ),
        buildSliderCard(
          title: 'Sleep quality (1–5)',
          value: sleepQuality,
          min: 1,
          max: 5,
          divisions: 4,
          displayValue: sleepQuality.toStringAsFixed(0),
          onChanged: (v) => setState(() => sleepQuality = v),
        ),
        buildSliderCard(
          title: 'App switches per hour',
          value: appSwitchesPerHour,
          min: 0,
          max: 120,
          divisions: 120,
          displayValue: appSwitchesPerHour.toStringAsFixed(0),
          onChanged: (v) => setState(() => appSwitchesPerHour = v),
        ),
        buildSliderCard(
          title: 'Social app ratio (0–1)',
          value: socialAppRatio,
          min: 0,
          max: 1,
          divisions: 10,
          displayValue: socialAppRatio.toStringAsFixed(1),
          onChanged: (v) => setState(() => socialAppRatio = v),
        ),
        buildSliderCard(
          title: 'Productivity ratio (0–1)',
          value: productivityRatio,
          min: 0,
          max: 1,
          divisions: 10,
          displayValue: productivityRatio.toStringAsFixed(1),
          onChanged: (v) => setState(() => productivityRatio = v),
        ),
        buildSliderCard(
          title: 'Unique apps per day',
          value: uniqueAppsPerDay,
          min: 0,
          max: 150,
          divisions: 150,
          displayValue: uniqueAppsPerDay.toStringAsFixed(0),
          onChanged: (v) => setState(() => uniqueAppsPerDay = v),
        ),
        buildSliderCard(
          title: 'Call count',
          value: callCount,
          min: 0,
          max: 50,
          divisions: 50,
          displayValue: callCount.toStringAsFixed(0),
          onChanged: (v) => setState(() => callCount = v),
        ),
        buildSliderCard(
          title: 'Total call minutes',
          value: totalCallMin,
          min: 0,
          max: 300,
          divisions: 300,
          displayValue: totalCallMin.toStringAsFixed(0),
          onChanged: (v) => setState(() => totalCallMin = v),
        ),
        buildSliderCard(
          title: 'Missed call ratio (0–1)',
          value: missedCallRatio,
          min: 0,
          max: 1,
          divisions: 10,
          displayValue: missedCallRatio.toStringAsFixed(1),
          onChanged: (v) => setState(() => missedCallRatio = v),
        ),
        buildSliderCard(
          title: 'SMS count',
          value: smsCount,
          min: 0,
          max: 300,
          divisions: 300,
          displayValue: smsCount.toStringAsFixed(0),
          onChanged: (v) => setState(() => smsCount = v),
        ),
        buildSliderCard(
          title: 'SMS sent ratio (0–1)',
          value: smsSentRatio,
          min: 0,
          max: 1,
          divisions: 10,
          displayValue: smsSentRatio.toStringAsFixed(1),
          onChanged: (v) => setState(() => smsSentRatio = v),
        ),
        buildSliderCard(
          title: 'Screen time hours',
          value: screenTimeHours,
          min: 0,
          max: 18,
          divisions: 18,
          displayValue: screenTimeHours.toStringAsFixed(0),
          onChanged: (v) => setState(() => screenTimeHours = v),
        ),
        buildSliderCard(
          title: 'Exercise minutes per week',
          value: exerciseMinPerWeek,
          min: 0,
          max: 1000,
          divisions: 100,
          displayValue: exerciseMinPerWeek.toStringAsFixed(0),
          onChanged: (v) => setState(() => exerciseMinPerWeek = v),
        ),
        buildSliderCard(
          title: 'Social hours per week',
          value: socialHoursPerWeek,
          min: 0,
          max: 80,
          divisions: 80,
          displayValue: socialHoursPerWeek.toStringAsFixed(0),
          onChanged: (v) => setState(() => socialHoursPerWeek = v),
        ),
      ],
    );
  }

  Widget buildRightPanel() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF232325),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Selected model',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedModel,
                dropdownColor: const Color(0xFF232325),
                style: const TextStyle(color: Colors.white),
                iconEnabledColor: Colors.white,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF1A1A1C),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.white12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.orange),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Burnout Neural Model',
                    child: Text('Burnout Neural Model'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    selectedModel = value;
                  });
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF232325),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Predicted burnout score',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  predictedStress,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Burnout level',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  stressLevel,
                  style: TextStyle(
                    color: getStressColor(),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isLoading ? null : runPrediction,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF45199D),
                        disabledBackgroundColor: const Color(0xFF45199D),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Predict',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isLoading ? null : resetFields,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Reset',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final leftPanel = buildLeftPanel();
    final rightPanel = buildRightPanel();

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0F),
        elevation: 0,
        title: const Text(
          'Burnout Prediction',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 900) {
              return SingleChildScrollView(
                child: Column(
                  children: [
                    buildLeftPanel(),
                    const SizedBox(height: 16),
                    buildRightPanel(),
                  ],
                ),
              );
            } else {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: SingleChildScrollView(child: leftPanel),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: SingleChildScrollView(child: rightPanel),
                  ),
                ],
              );
            }
          },
        ),
      ),
    );
  }
}