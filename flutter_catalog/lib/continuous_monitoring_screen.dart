import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class ContinuousMonitoringScreen extends StatelessWidget {
  const ContinuousMonitoringScreen({super.key});

  List<FlSpot> get screenTimeData => const [
        FlSpot(0, 4.5),
        FlSpot(1, 5.0),
        FlSpot(2, 5.8),
        FlSpot(3, 6.2),
        FlSpot(4, 6.8),
        FlSpot(5, 7.4),
        FlSpot(6, 6.9),
      ];

  List<FlSpot> get appSwitchData => const [
        FlSpot(0, 18),
        FlSpot(1, 22),
        FlSpot(2, 25),
        FlSpot(3, 28),
        FlSpot(4, 32),
        FlSpot(5, 30),
        FlSpot(6, 35),
      ];

  Widget buildInfoCard({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF232325),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF8A5CE6)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildChart({
    required String title,
    required List<FlSpot> data,
    required double maxY,
  }) {
    return Container(
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
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: 6,
                minY: 0,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) {
                    return const FlLine(
                      color: Colors.white12,
                      strokeWidth: 1,
                    );
                  },
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                          ),
                        );
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                        final index = value.toInt();
                        if (index < 0 || index >= labels.length) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          labels[index],
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    isCurved: true,
                    spots: data,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFF8A5CE6).withOpacity(0.18),
                    ),
                    color: const Color(0xFF8A5CE6),
                    barWidth: 3,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0F),
        title: const Text(
          'Continuous Monitoring',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            buildInfoCard(
              title: 'Current Burnout Risk',
              value: 'Moderate 🟠',
              icon: Icons.health_and_safety_outlined,
            ),
            const SizedBox(height: 12),
            buildInfoCard(
              title: 'Average Screen Time',
              value: '6.4 h/day',
              icon: Icons.phone_android_outlined,
            ),
            const SizedBox(height: 12),
            buildInfoCard(
              title: 'Average App Switches',
              value: '27/day',
              icon: Icons.swap_horiz_outlined,
            ),
            const SizedBox(height: 18),
            buildChart(
              title: 'Screen Time Trend',
              data: screenTimeData,
              maxY: 10,
            ),
            const SizedBox(height: 18),
            buildChart(
              title: 'App Switching Trend',
              data: appSwitchData,
              maxY: 40,
            ),
          ],
        ),
      ),
    );
  }
}