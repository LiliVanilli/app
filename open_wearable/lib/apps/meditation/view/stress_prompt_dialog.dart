import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';

/// Dialog that prompts user when stress is detected
/// 
/// Shows: "You seem stressed. Would you like to start a meditation?"
class StressPromptDialog extends StatelessWidget {
  final VoidCallback onYes;
  final VoidCallback onNo;
  final double currentHr;
  final double currentHrv;
  
  const StressPromptDialog({
    super.key,
    required this.onYes,
    required this.onNo,
    required this.currentHr,
    required this.currentHrv,
  });
  
  @override
  Widget build(BuildContext context) {
    return PlatformAlertDialog(
      title: const Text('Stress Detected'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'You seem stressed. Would you like to start a meditation session?',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          Text(
            'Current HR: ${currentHr.toStringAsFixed(0)} BPM',
            style: TextStyle(
              fontSize: 14,
              color: currentHr > 90 ? Colors.red : Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Current HRV: ${currentHrv.toStringAsFixed(1)} ms',
            style: TextStyle(
              fontSize: 14,
              color: currentHrv < 25 ? Colors.red : Colors.grey,
            ),
          ),
        ],
      ),
      actions: [
        PlatformDialogAction(
          child: const Text('No'),
          onPressed: onNo,
        ),
        PlatformDialogAction(
          child: const Text('Yes'),
          onPressed: onYes,
        ),
      ],
    );
  }
}
