import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

enum PoseLandmarkType {
  nose,
  leftEyeInner,
  leftEye,
  leftEyeOuter,
  rightEyeInner,
  rightEye,
  rightEyeOuter,
  leftEar,
  rightEar,
  mouthLeft,
  mouthRight,
  leftShoulder,
  rightShoulder,
  leftElbow,
  rightElbow,
  leftWrist,
  rightWrist,
  leftPinky,
  rightPinky,
  leftIndex,
  rightIndex,
  leftThumb,
  rightThumb,
  leftHip,
  rightHip,
  leftKnee,
  rightKnee,
  leftAnkle,
  rightAnkle,
  leftHeel,
  rightHeel,
  leftFootIndex,
  rightFootIndex,
}

class PoseDetector {
  static const String MODEL_FILE = 'pose_landmarker_full.task';
  bool _isInitialized = false;
  late String _modelPath;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final tempDir = await getTemporaryDirectory();
      _modelPath = path.join(tempDir.path, MODEL_FILE);

      // Copy model file from assets to temporary directory if it doesn't exist
      if (!File(_modelPath).existsSync()) {
        final ByteData data = await rootBundle.load('assets/$MODEL_FILE');
        final bytes = data.buffer.asUint8List();
        await File(_modelPath).writeAsBytes(bytes);
      }

      _isInitialized = true;
    } catch (e) {
      throw Exception('Failed to initialize pose detector: $e');
    }
  }

  Future<List<Map<String, dynamic>>> detectPose(String imagePath) async {
    if (!_isInitialized) {
      throw Exception('Pose detector not initialized');
    }

    try {
      // Here we would normally call the MediaPipe pose detection
      // For now, we'll return a mock result with all landmarks
      final landmarks = <Map<String, dynamic>>[];

      for (var type in PoseLandmarkType.values) {
        landmarks.add({
          'type': type.index,
          'x': 0.5,
          'y': 0.5,
          'z': 0.0,
          'visibility': 0.9,
        });
      }

      return [
        {'landmarks': landmarks, 'score': 0.95},
      ];
    } catch (e) {
      throw Exception('Failed to detect pose: $e');
    }
  }

  void close() {
    _isInitialized = false;
  }
}

class PoseLandmark {
  final PoseLandmarkType type;
  final double x;
  final double y;
  final double z;
  final double visibility;

  PoseLandmark({
    required this.type,
    required this.x,
    required this.y,
    required this.z,
    required this.visibility,
  });

  factory PoseLandmark.fromJson(Map<String, dynamic> json) {
    return PoseLandmark(
      type: PoseLandmarkType.values[json['type'] as int],
      x: json['x'] as double,
      y: json['y'] as double,
      z: json['z'] as double,
      visibility: json['visibility'] as double,
    );
  }
}

class Pose {
  final List<PoseLandmark> landmarks;
  final double score;

  Pose({required this.landmarks, required this.score});

  factory Pose.fromJson(Map<String, dynamic> json) {
    return Pose(
      landmarks:
          (json['landmarks'] as List)
              .map((l) => PoseLandmark.fromJson(l))
              .toList(),
      score: json['score'] as double,
    );
  }

  PoseLandmark? getLandmark(PoseLandmarkType type) {
    try {
      return landmarks.firstWhere((l) => l.type == type);
    } catch (e) {
      return null;
    }
  }
}
