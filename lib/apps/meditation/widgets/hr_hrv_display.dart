import 'package:flutter/material.dart';

/// Widget that displays current HR and HRV values
/// 
/// Shows color-coded indicators for stress level
class HrHrvDisplay extends StatelessWidget {
  final double hr;
  final double hrv;
  final bool isStressed;
  
  const HrHrvDisplay({
    super.key,
    required this.hr,
    required this.hrv,
    required this.isStressed,
  });
  
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  Icons.favorite,
                  color: isStressed ? Colors.red : Colors.green,
                  size: 32,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Heart Rate',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        '${hr.toStringAsFixed(0)} BPM',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: hr > 90 ? Colors.red : Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Icon(
                  Icons.show_chart,
                  color: isStressed ? Colors.red : Colors.green,
                  size: 32,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HRV (RMSSD)',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        '${hrv.toStringAsFixed(1)} ms',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: hrv < 25 ? Colors.red : Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              decoration: BoxDecoration(
                color: isStressed ? Colors.red.shade50 : Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isStressed ? Icons.warning : Icons.check_circle,
                    color: isStressed ? Colors.red : Colors.green,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isStressed ? 'Elevated Stress' : 'Normal',
                    style: TextStyle(
                      color: isStressed ? Colors.red : Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
