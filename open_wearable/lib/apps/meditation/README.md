# Biosignal-Adaptive Meditation System

A real-time, AI-powered meditation application that combines physiological sensing with personalized guidance. The system monitors heart rate (HR) and heart rate variability (HRV) from OpenEarable wearable devices, detects stress levels, and generates adaptive meditation content using large language models.

## 🎯 Features

- **Real-time Biosignal Processing**: Continuous HR/HRV monitoring from PPG sensors
- **Activity-Aware Stress Detection**: IMU-based activity classification prevents false positives during exercise
- **Personalized Baselines**: Demographic-informed stress thresholds (age, gender, fitness level)
- **AI-Generated Content**: Dynamic meditation segments using Gemini 2.5 Flash
- **Adaptive Session Control**: Automatic termination when relaxation targets are met
- **Multi-Modal Feedback**: Premium (Google Cloud TTS) and free (Flutter TTS) voice synthesis
- **Session Analytics**: Weekly progress tracking with mood ratings
- **Robust Fallback Mechanisms**: Offline operation with pre-defined scripts

## 📁 Project Structure

```
meditation/
├── model/                          # Core business logic
│   ├── activity_detector.dart      # IMU-based activity classification
│   ├── band_pass_filter_meditation.dart  # 0.5-4.0 Hz PPG filter
│   ├── earable_hr_sensor.dart      # Real OpenEarable sensor interface
│   ├── hr_sensor_interface.dart    # Sensor abstraction layer
│   ├── hrv_calculator.dart         # Time-domain HRV metrics (SDNN, RMSSD)
│   ├── improved_meditation_controller.dart  # Main session orchestration
│   ├── improved_meditation_llm_service.dart # Gemini API integration
│   ├── meditation_cache.dart       # TTS audio caching (7-day expiry)
│   ├── meditation_config.dart      # App configuration & API keys
│   ├── meditation_history.dart     # Session storage (JSON)
│   ├── meditation_voice_service.dart  # TTS with fallback chain
│   ├── mock_hr_sensor.dart         # Testing/demo sensor
│   ├── mood_entry.dart             # Post-session mood tracking
│   ├── personalized_stress_detector.dart  # Adaptive stress classification
│   ├── ppg_filter_meditation.dart  # Peak detection & RR interval extraction
│   ├── stress_detector.dart        # Basic stress detector (deprecated)
│   ├── user_account.dart           # User demographics & preferences
│   └── user_meditation_profile.dart # Meditation style preferences
│
├── view/                           # Main screens
│   ├── meditation_view.dart        # Primary app entry point
│   ├── snooze_dialog.dart          # Stress prompt snooze UI
│   ├── stress_prompt_dialog.dart   # Stress detection notification
│   └── success_dialog.dart         # Session completion feedback
│
├── widgets/                        # Reusable UI components
│   ├── api_debug_widget.dart       # API configuration testing
│   ├── breathing_animation.dart    # Apple Watch-style breathing circles
│   ├── cute_timer_widget.dart      # Session duration display
│   ├── hr_hrv_chart.dart           # Real-time biosignal charts
│   ├── hr_hrv_display_new.dart     # Current HR/HRV metrics display
│   ├── llm_meditation_widget.dart  # Main meditation session UI
│   ├── profile_settings_dialog.dart # User preferences editor
│   ├── user_onboarding_screen.dart # First-time setup wizard
│   └── weekly_analysis_screen.dart # Progress dashboard
│
└── assets/                         # Static resources
    └── image.png                   # App icon/branding
```

## 🔧 Core Components

### 1. Biosignal Processing Pipeline

**PPG → Bandpass Filter → Peak Detection → RR Intervals → HRV Calculation**

- **Input**: Raw PPG sensor stream from OpenEarable
- **Bandpass Filter**: 0.5-4.0 Hz (removes baseline drift & noise)
- **Peak Detection**: Identifies heartbeats with prominence threshold
- **Kalman Smoothing**: Stabilizes HR estimates (q=0.01, r=4.0)
- **HRV Metrics**: 
  - RMSSD (short-term, 10+ intervals)
  - SDNN (long-term, 30+ intervals)

**Key Files**: `ppg_filter_meditation.dart`, `band_pass_filter_meditation.dart`, `hrv_calculator.dart`

### 2. Activity Detection

Prevents false stress detection during exercise using IMU sensors:

- **Accelerometer**: Deviation from 1g (static gravity)
- **Gyroscope**: Angular velocity magnitude
- **Moving Average**: 30-sample window (~3 seconds)
- **Thresholds**: Calibrated for earable devices (higher than wrist-worn)

**Classification Levels**:
- Resting: Both accel <0.20g AND gyro <300°/s
- Light/Moderate/Vigorous/Intense: Based on normalized sensor fusion

**Key File**: `activity_detector.dart`

### 3. Personalized Stress Detection

Hybrid baseline approach combining research priors with live measurements:

**Research Baselines** (immediate usability):
- Age-adjusted (e.g., <25 years: HR=68, HRV=50ms)
- Gender-adjusted (males: -4 BPM, +6ms HRV)
- Fitness-adjusted (athletes: -12 BPM, +35ms HRV)

**Calibration Schedule** (first 30 seconds):
- t=0s: 100% research, 0% measured
- t=10s: 80% research, 20% measured
- t=20s: 60% research, 40% measured
- t=30s: 40% research, 60% measured

**Stress Thresholds**:
- HR_stress = baseline × 1.25 (if user-measured baseline exists)
- HRV_stress = baseline × 0.6

**Key File**: `personalized_stress_detector.dart`

### 4. AI Content Generation

**LLM Configuration**:
- Model: `gemini-2.5-flash`
- Temperature: 0.9 (high creativity)
- Max tokens: 600 (~280 word target)

**Prompt Engineering**:
- Segment-specific techniques (breath focus → body scan → visualization)
- User personalization (name, age, environment preference)
- Style adaptation (calm/gentle/warm/mindful)
- Safety constraints (no numbers, no greetings, meditation vocabulary only)

**Fallback Text** (API failure):
> "Take a deep breath in... hold gently for a moment... and slowly release..."

**Key File**: `improved_meditation_llm_service.dart`

### 5. Session Orchestration

**Adaptive Loop**:
1. Measure baseline (30s calibration)
2. Generate welcome message
3. **Iteration** (max 10 segments):
   - Wait 3s for fresh biosignals
   - Check termination criteria
   - Generate segment via LLM
   - Speak with TTS (audio ducking enabled)
   - Check termination again (after iteration 3)
4. Generate completion message
5. Save session history

**Automatic Termination Criteria** (minimum 2 segments):
- HRV ≥30% AND stress <40%
- HRV ≥25% AND stress <30%
- HRV ≥20% AND relaxed state
- HR ≥10% AND HRV ≥20%
- Relaxed AND stress <20% AND HRV ≥10%

**Key File**: `improved_meditation_controller.dart`

## 🛡️ Robustness Features

### Fallback Mechanisms

1. **LLM Failure**: Pre-defined meditation script
2. **Premium TTS Failure**: Flutter TTS (offline)
3. **Sensor Timeout**: 45-second timeout → graceful termination
4. **Connection Loss**: Automatic session end with notification

### Audio Caching

- **Storage**: Hash-based filenames (separate premium/free caches)
- **Expiry**: 7 days
- **Corruption Detection**: Reject files <1KB
- **Cost Savings**: Bypass API for repeated phrases

### Error Handling

- Physiological validity checks (HR: 30-220 BPM)
- Artifact filtering (RR intervals: 300-2000ms, ±25% median)
- Minimum data requirements (10 RR for RMSSD, 30 for SDNN)
- Comprehensive logging (sensor packets, API calls, fallback triggers)

## 📊 Data Storage

### Session History (`meditation_history.dart`)
```dart
{
  sessionId: String,
  userId: String,
  timestamp: DateTime,
  startHr: double,
  startHrv: double,
  endHr: double,
  endHrv: double,
  durationSeconds: int,
  iterationCount: int,
  peakStressLevel: double
}
```

### Mood Tracking (`mood_entry.dart`)
```dart
{
  timestamp: DateTime,
  mood: MoodRating,  // veryRelaxed, relaxed, neutral, stressed
  stressReduction: double,  // (HR% + HRV%) / 2
  sessionDuration: Duration
}
```

## 🔑 Configuration

### API Keys (`.env` file)
```bash
GEMINI_API_KEY=AIza...
GOOGLE_CLOUD_TTS_API_KEY=AIza...
```

### User Preferences (`user_account.dart`)
- Demographics: age, gender, fitness level
- Meditation style: calm/gentle/warm/mindful
- Environment: nature/ocean/mountain/forest
- Voice: premium (paid) or free (offline)

## 🧪 Testing

### Mock Sensor (`mock_hr_sensor.dart`)
Simulates realistic biosignal patterns for development:
- Baseline: HR=75, HRV=45
- Stress simulation: HR↑ to 95, HRV↓ to 25
- Gradual relaxation during meditation

### Debug Tools (`api_debug_widget.dart`)
- API key validation
- Test LLM generation
- Test TTS synthesis
- Cache management

## 📈 Performance Metrics

- **Latency**: <3s segment generation (LLM)
- **Memory**: Bounded buffers (50 RR intervals, 3600 HR/HRV history)
- **Battery**: Optimized Bluetooth packet handling
- **Cache Hit Rate**: ~60% for repeated phrases

## 🔬 Scientific References

- **HRV Baselines**: Nunan et al. (2010), Tegegne et al. (2018)
- **Activity Detection**: Stuchbury-Wass et al. (WalkEar, 2025)
- **Stress Classification**: Schroeder et al. (2004)

## 🚀 Usage Example

```dart
// Initialize sensor
final sensor = EarableHrSensor(
  ppgSensor: ppgSensor,
  wearable: wearable,
  sensorManager: sensorManager,
  sampleFreq: 30.0,
);

// Create controller
final controller = ImprovedMeditationController(
  sensor: sensor,
  llmService: ImprovedMeditationLLMService(),
  voiceService: MeditationVoiceService(),
  userAccount: userAccount,
);

// Start session
await controller.startSession();
```

## 📝 Code Quality

- **Documentation**: All classes have docstring headers
- **Type Safety**: Strict null safety enabled
- **Error Handling**: Try-catch blocks with logging
- **Separation of Concerns**: Model-View-Widget architecture
- **Testing**: Mock sensor for offline development

## 🐛 Known Limitations

- Post-exercise HR elevation may persist (5-10 min recovery)
- HRV requires 30-60s for stable SDNN measurement
- Premium TTS requires network connectivity
- Earable-specific thresholds (not validated for wrist-worn devices)

## 📄 License

See main repository LICENSE file.

## 👥 Contributors

Developed as part of the EarStream research project at TUM.

---

**Last Updated**: March 2026  
**Flutter Version**: 3.x  
**Dart Version**: 3.x
