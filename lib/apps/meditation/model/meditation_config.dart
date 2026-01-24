import 'api_keys.dart';

/// Configuration for meditation LLM and settings
class MeditationConfig {
  // API Configuration - imported from api_keys.dart (not committed)
  static String get geminiApiKey => ApiKeys.geminiApiKey;
  static String get googleCloudTtsApiKey => ApiKeys.googleCloudTtsApiKey;
  
  // Meditation Settings
  static const int targetWordCount = 280;
  static const double stressThresholdPercentage = 0.15; // 15% increase for stress detection
  
  // Audio Settings
  static const String backgroundMusicPath = 'meditation_sound.mp3'; // Asset path from assets/
  static const double backgroundMusicVolume = 0.04; // Lowered for better TTS clarity
  static const double speechVolume = 1.0;
  static const double speechRate = 0.35; // Slow and calming speed
  static const double speechPitch = 0.8; // Slightly lower pitch for soothing voice
  
  // Baseline Measurement
  static const int baselineDurationSeconds = 60; // 1 minute baseline
  
  // Stress Detection
  static const double relaxationThreshold = 0.10; // 10% improvement to end session (OR condition)
  
  // Meditation Texts
  static const String stressAlertText = 
      "You seem pretty stressed. Please pause your current task and take a moment for yourself.";
  
  static const String welcomeText = 
      "Welcome to your stress-adaptive and personalized meditation. Let's begin by finding a comfortable position and focusing on your breath.";
  
  static const String completionText = 
      "Your body has calmed down. Well done. The session is now complete.";
  
  // User Preferences (can be extended)
  static String meditationStyle = 'calm and empathetic';
  static String preferredEnvironment = 'nature sounds';
  static String voiceGender = 'female'; // 'male' or 'female'
  static String personalNotes = '';
}
