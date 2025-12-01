import 'package:flutter/material.dart';

/// Modern widget to display current HR and HRV values
/// Inspired by Calm/Headspace design
class HrHrvDisplayNew extends StatelessWidget {
  final double hr;
  final double hrv;
  final String stressLevel;
  final bool isHrvStable; // New: indicates if HRV measurement is reliable
  
  const HrHrvDisplayNew({
    super.key,
    required this.hr,
    required this.hrv,
    required this.stressLevel,
    this.isHrvStable = true, // Default to true for backward compatibility
  });
  
  @override
  Widget build(BuildContext context) {
    final Map<String, Color> stressColors = {
      'relaxed': const Color(0xFF51CF66),
      'normal': const Color(0xFFFFA500),
      'stressed': const Color(0xFFFF6B6B),
    };
    
    final Map<String, String> stressLabels = {
      'relaxed': 'Relaxed',
      'normal': 'Normal',
      'stressed': 'Stressed',
    };
    
    final Map<String, IconData> stressIcons = {
      'relaxed': Icons.check_circle_rounded,
      'normal': Icons.info_rounded,
      'stressed': Icons.warning_rounded,
    };
    
    final stressColor = stressColors[stressLevel] ?? const Color(0xFFFFA500);
    final stressText = stressLabels[stressLevel] ?? 'Normal';
    final stressIcon = stressIcons[stressLevel] ?? Icons.info_rounded;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  icon: Icons.favorite,
                  iconColor: const Color(0xFFFF6B6B),
                  label: 'Heart Rate',
                  value: '${hr.toStringAsFixed(0)} BPM',
                  iconBackground: const Color(0xFFFFE5E5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  icon: Icons.show_chart,
                  iconColor: const Color(0xFF4ECDC4),
                  label: 'HRV (RMSSD)',
                  value: hrv < 0
                      ? 'Loading...'
                      : (isHrvStable 
                          ? '${hrv.toStringAsFixed(1)} ms' 
                          : 'Measuring...'),
                  iconBackground: const Color(0xFFE0F7F6),
                  isLoading: hrv < 0 || !isHrvStable,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: stressColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  stressIcon,
                  color: stressColor,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  stressText,
                  style: TextStyle(
                    color: stressColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String label;
  final String value;
  final bool isLoading; // New: shows loading indicator
  
  const _MetricCard({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.label,
    required this.value,
    this.isLoading = false,
  });
  
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: iconBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: iconColor,
            size: 24,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              isLoading
                  ? SizedBox(
                      height: 22,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            value,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[600],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Text(
                      value,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }
}
