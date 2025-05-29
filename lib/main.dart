import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final firstCamera = cameras.first;
  runApp(MyApp(camera: firstCamera));
}

class MyApp extends StatelessWidget {
  final CameraDescription camera;
  const MyApp({super.key, required this.camera});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'قياس الملابس الذكي',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.grey[100],
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.blueAccent,
          foregroundColor: Colors.white,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        ),
      ),
      home: CameraScreen(camera: camera),
    );
  }
}

class CameraScreen extends StatefulWidget {
  final CameraDescription camera;
  const CameraScreen({super.key, required this.camera});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;

  final poseDetector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.single),
  );

  List<Pose>? poses;
  bool isProcessing = false;
  Map<String, String> clothingSizes = {};
  double conversionFactor = 0.0;

  double userHeight = 170.0;
  double userWeight = 70.0;
  final TextEditingController heightController = TextEditingController();
  final TextEditingController weightController = TextEditingController();
  bool showInputFields = true;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
    _initializeControllerFuture = _controller.initialize();

    heightController.text = userHeight.toString();
    weightController.text = userWeight.toString();
  }

  @override
  void dispose() {
    _controller.dispose();
    poseDetector.close();
    heightController.dispose();
    weightController.dispose();
    super.dispose();
  }

  Future<void> _processImage(XFile imageFile) async {
    if (isProcessing) return;
    setState(() {
      isProcessing = true;
      showInputFields = false;
    });

    try {
      final inputImage = InputImage.fromFilePath(imageFile.path);
      poses = await poseDetector.processImage(inputImage);

      if (poses != null && poses!.isNotEmpty) {
        final measurements = _calculateBodyMeasurements(poses!.first);
        _determineClothingSizes(measurements);
      }
    } catch (e) {
      debugPrint('Error processing image: $e');
    } finally {
      setState(() {
        isProcessing = false;
      });
    }
  }

  double _distanceBetween(PoseLandmark p1, PoseLandmark p2) {
    return sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2));
  }

  Map<String, double> _calculateBodyMeasurements(Pose pose) {
    final landmarks = pose.landmarks;

    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder]!;
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder]!;
    final leftHip = landmarks[PoseLandmarkType.leftHip]!;
    final rightHip = landmarks[PoseLandmarkType.rightHip]!;
    final leftElbow = landmarks[PoseLandmarkType.leftElbow]!;
    final rightElbow = landmarks[PoseLandmarkType.rightElbow]!;
    final leftWrist = landmarks[PoseLandmarkType.leftWrist]!;
    final rightWrist = landmarks[PoseLandmarkType.rightWrist]!;
    final leftKnee = landmarks[PoseLandmarkType.leftKnee]!;
    final rightKnee = landmarks[PoseLandmarkType.rightKnee]!;
    final leftAnkle = landmarks[PoseLandmarkType.leftAnkle]!;
    final rightAnkle = landmarks[PoseLandmarkType.rightAnkle]!;
    final nose = landmarks[PoseLandmarkType.nose]!;
    final leftHeel = landmarks[PoseLandmarkType.leftHeel]!;
    final rightHeel = landmarks[PoseLandmarkType.rightHeel]!;

    // تحسين حساب الطول الكلي باستخدام جميع النقاط المتاحة
    double heightPixels = _calculateTotalHeight(nose, leftHeel, rightHeel);
    conversionFactor = userHeight / heightPixels;

    // حساب عرض الكتفين بدقة أكبر
    double shoulderWidth = _calculateShoulderWidth(leftShoulder, rightShoulder);

    // حساب محيط الصدر باستخدام نموذج متقدم
    double chestWidth = _calculateChestWidth(
      leftShoulder,
      rightShoulder,
      leftHip,
      rightHip,
    );
    double chestDepth = _calculateChestDepth(
      chestWidth,
      userWeight,
      userHeight,
    );
    double chestCircumference = _calculateEllipticalCircumference(
      chestWidth,
      chestDepth,
    );

    // حساب محيط الخصر بدقة
    double waistWidth = _calculateWaistWidth(leftHip, rightHip);
    double waistDepth = _calculateWaistDepth(
      waistWidth,
      userWeight,
      userHeight,
    );
    double waistCircumference = _calculateEllipticalCircumference(
      waistWidth,
      waistDepth,
    );

    // حساب أطوال الأطراف بدقة
    double armLength = _calculateArmLength(
      leftShoulder,
      leftElbow,
      leftWrist,
      rightShoulder,
      rightElbow,
      rightWrist,
    );
    double legLength = _calculateLegLength(
      leftHip,
      leftKnee,
      leftAnkle,
      rightHip,
      rightKnee,
      rightAnkle,
    );

    // حساب محيط الرقبة
    double neckCircumference = _calculateNeckCircumference(
      leftShoulder,
      rightShoulder,
      nose,
    );

    // تطبيق التصحيحات والمعايرة
    Map<String, double> measurements = {
      'shoulderWidth': shoulderWidth * conversionFactor,
      'chestCircumference': chestCircumference * conversionFactor,
      'waistCircumference': waistCircumference * conversionFactor,
      'armLength': armLength * conversionFactor,
      'legLength': legLength * conversionFactor,
      'hipWidth': waistWidth * 1.4 * conversionFactor, // تقدير محيط الورك
      'neckCircumference': neckCircumference * conversionFactor,
      'inseam': legLength * 0.67 * conversionFactor, // تقدير طول الساق الداخلي
    };

    _applyBodyTypeCorrections(measurements);
    return measurements;
  }

  double _calculateTotalHeight(
    PoseLandmark nose,
    PoseLandmark leftHeel,
    PoseLandmark rightHeel,
  ) {
    double leftHeight = _distanceBetween(nose, leftHeel);
    double rightHeight = _distanceBetween(nose, rightHeel);
    return (leftHeight + rightHeight) / 2;
  }

  double _calculateShoulderWidth(
    PoseLandmark leftShoulder,
    PoseLandmark rightShoulder,
  ) {
    return _distanceBetween(leftShoulder, rightShoulder) *
        1.15; // تصحيح للانحناء
  }

  double _calculateChestWidth(
    PoseLandmark leftShoulder,
    PoseLandmark rightShoulder,
    PoseLandmark leftHip,
    PoseLandmark rightHip,
  ) {
    double shoulderWidth = _distanceBetween(leftShoulder, rightShoulder);
    double hipWidth = _distanceBetween(leftHip, rightHip);
    return (shoulderWidth + hipWidth) /
        2 *
        1.2; // تعديل للحصول على محيط الصدر الحقيقي
  }

  double _calculateWaistWidth(PoseLandmark leftHip, PoseLandmark rightHip) {
    return _distanceBetween(leftHip, rightHip) * 1.1; // تصحيح للانحناء
  }

  double _calculateArmLength(
    PoseLandmark leftShoulder,
    PoseLandmark leftElbow,
    PoseLandmark leftWrist,
    PoseLandmark rightShoulder,
    PoseLandmark rightElbow,
    PoseLandmark rightWrist,
  ) {
    double leftArm =
        _distanceBetween(leftShoulder, leftElbow) +
        _distanceBetween(leftElbow, leftWrist);
    double rightArm =
        _distanceBetween(rightShoulder, rightElbow) +
        _distanceBetween(rightElbow, rightWrist);
    return (leftArm + rightArm) / 2 * 1.05; // تصحيح للانحناء
  }

  double _calculateLegLength(
    PoseLandmark leftHip,
    PoseLandmark leftKnee,
    PoseLandmark leftAnkle,
    PoseLandmark rightHip,
    PoseLandmark rightKnee,
    PoseLandmark rightAnkle,
  ) {
    double leftLeg =
        _distanceBetween(leftHip, leftKnee) +
        _distanceBetween(leftKnee, leftAnkle);
    double rightLeg =
        _distanceBetween(rightHip, rightKnee) +
        _distanceBetween(rightKnee, rightAnkle);
    return (leftLeg + rightLeg) / 2 * 1.08; // تصحيح للانحناء
  }

  double _calculateNeckCircumference(
    PoseLandmark leftShoulder,
    PoseLandmark rightShoulder,
    PoseLandmark nose,
  ) {
    double neckWidth = _distanceBetween(leftShoulder, rightShoulder) * 0.2;
    double neckHeight = _distanceBetween(nose, leftShoulder) * 0.15;
    return _calculateEllipticalCircumference(neckWidth, neckHeight);
  }

  void _applyBodyTypeCorrections(Map<String, double> measurements) {
    double bmi = userWeight / pow(userHeight / 100, 2);
    double bodyTypeCorrection = _calculateBodyTypeCorrection(bmi);
    double muscleFactorCorrection = _calculateMuscleFactorCorrection(
      measurements,
    );

    measurements.forEach((key, value) {
      switch (key) {
        case 'chestCircumference':
          measurements[key] =
              value *
              (1 + bodyTypeCorrection * 0.1 + muscleFactorCorrection * 0.15);
          break;
        case 'waistCircumference':
          measurements[key] = value * (1 + bodyTypeCorrection * 0.12);
          break;
        case 'hipWidth':
          measurements[key] = value * (1 + bodyTypeCorrection * 0.08);
          break;
        case 'shoulderWidth':
          measurements[key] = value * (1 + muscleFactorCorrection * 0.1);
          break;
      }
    });
  }

  double _calculateBodyTypeCorrection(double bmi) {
    if (bmi < 18.5) return -0.05;
    if (bmi < 25) return 0;
    if (bmi < 30) return 0.05;
    return 0.1;
  }

  double _calculateMuscleFactorCorrection(Map<String, double> measurements) {
    double shoulderToWaistRatio =
        measurements['shoulderWidth']! / measurements['waistCircumference']!;
    if (shoulderToWaistRatio > 0.5) return 0.05;
    if (shoulderToWaistRatio > 0.45) return 0;
    return -0.05;
  }

  double _calculateEllipticalCircumference(double width, double depth) {
    // استخدام صيغة رامانوجان لحساب محيط القطع الناقص بدقة أعلى
    double a = width / 2;
    double b = depth / 2;
    double h = pow(a - b, 2) / pow(a + b, 2);
    return pi * (a + b) * (1 + (3 * h) / (10 + sqrt(4 - 3 * h)));
  }

  double _calculateChestDepth(double width, double weight, double height) {
    double bmi = weight / pow(height / 100, 2);
    double baseDepth = width * 0.75;
    double bmiAdjustment = (bmi - 22) * 0.025;
    return baseDepth * (1 + bmiAdjustment);
  }

  double _calculateWaistDepth(double width, double weight, double height) {
    double bmi = weight / pow(height / 100, 2);
    double baseDepth = width * 0.75;
    double bmiAdjustment = (bmi - 22) * 0.025;
    return baseDepth * (1 + bmiAdjustment);
  }

  void _determineClothingSizes(Map<String, double> measurements) {
    double chest = measurements['chestCircumference']!;
    double waist = measurements['waistCircumference']!;
    double shoulders = measurements['shoulderWidth']!;
    double armLength = measurements['armLength']!;
    double legLength = measurements['legLength']!;
    double hipWidth = measurements['hipWidth']!;
    double neck = measurements['neckCircumference']!;

    clothingSizes['tshirt'] = _getTshirtSize(chest, shoulders);
    clothingSizes['shirt'] = _getShirtSize(chest, armLength, neck);
    clothingSizes['pants'] = _getPantsSize(waist, hipWidth, legLength);
    clothingSizes['jacket'] = _getJacketSize(chest, shoulders, armLength);
  }

  String _getTshirtSize(double chest, double shoulders) {
    // جدول مقاسات التيشيرت المحسن
    Map<String, Map<String, double>> sizeChart = {
      'XS': {'chest': 86, 'shoulders': 38, 'length': 66},
      'S': {'chest': 94, 'shoulders': 40, 'length': 68},
      'M': {'chest': 102, 'shoulders': 42, 'length': 70},
      'L': {'chest': 110, 'shoulders': 44, 'length': 72},
      'XL': {'chest': 118, 'shoulders': 46, 'length': 74},
      'XXL': {'chest': 126, 'shoulders': 48, 'length': 76},
      '3XL': {'chest': 134, 'shoulders': 50, 'length': 78},
    };

    // حساب المقاس الأقرب مع مراعاة الطول والوزن
    String bestSize = 'L';
    double minScore = double.infinity;
    double idealLength =
        userHeight * 0.4; // طول مثالي للتيشيرت حوالي 40% من طول الجسم

    for (var entry in sizeChart.entries) {
      double chestDiff = (chest - entry.value['chest']!).abs() * 1.5;
      double shoulderDiff = (shoulders - entry.value['shoulders']!).abs() * 1.2;
      double lengthDiff = (idealLength - entry.value['length']!).abs();

      // تعديل النتيجة بناءً على مؤشر كتلة الجسم
      double bmi = userWeight / pow(userHeight / 100, 2);
      double bmiAdjustment = (bmi - 22).abs() * 0.5;

      double score = chestDiff + shoulderDiff + lengthDiff + bmiAdjustment;

      if (score < minScore) {
        minScore = score;
        bestSize = entry.key;
      }
    }

    // تحديد نوع الملاءمة
    String fit;
    double chestToHeightRatio = chest / userHeight;
    if (chestToHeightRatio < 0.5) {
      fit = 'سليم فيت';
    } else if (chestToHeightRatio < 0.55) {
      fit = 'ريجيولار فيت';
    } else {
      fit = 'ريلاكسد فيت';
    }

    return 'مقاس $bestSize ($fit)';
  }

  String _getShirtSize(double chest, double armLength, double neck) {
    // جدول مقاسات القميص المحسن
    Map<String, Map<String, double>> shirtSizes = {
      '14': {'neck': 35.5, 'chest': 88, 'sleeve': 58, 'length': 68},
      '14.5': {'neck': 37, 'chest': 92, 'sleeve': 59, 'length': 69},
      '15': {'neck': 38, 'chest': 96, 'sleeve': 60, 'length': 70},
      '15.5': {'neck': 39.5, 'chest': 100, 'sleeve': 61, 'length': 71},
      '16': {'neck': 40.5, 'chest': 104, 'sleeve': 62, 'length': 72},
      '16.5': {'neck': 42, 'chest': 108, 'sleeve': 63, 'length': 73},
      '17': {'neck': 43, 'chest': 112, 'sleeve': 64, 'length': 74},
      '17.5': {'neck': 44.5, 'chest': 116, 'sleeve': 65, 'length': 75},
    };

    String bestSize = '16';
    double minScore = double.infinity;
    double idealLength = userHeight * 0.45; // طول مثالي للقميص

    for (var entry in shirtSizes.entries) {
      double neckDiff = (neck - entry.value['neck']!).abs() * 2.0;
      double chestDiff = (chest - entry.value['chest']!).abs() * 1.5;
      double sleeveDiff = (armLength - entry.value['sleeve']!).abs() * 1.2;
      double lengthDiff = (idealLength - entry.value['length']!).abs();

      // تعديل حسب الوزن
      double weightAdjustment = (userWeight - 70) * 0.1;

      double score =
          neckDiff +
          chestDiff +
          sleeveDiff +
          lengthDiff +
          weightAdjustment.abs();

      if (score < minScore) {
        minScore = score;
        bestSize = entry.key;
      }
    }

    // تحديد نوع الملاءمة والطول
    String fit = _determineShirtFit(chest, neck, userWeight, userHeight);
    String length = _determineShirtLength(armLength, userHeight);

    return 'مقاس $bestSize ($fit - $length)';
  }

  String _determineShirtFit(
    double chest,
    double neck,
    double weight,
    double height,
  ) {
    double bmi = weight / pow(height / 100, 2);
    double chestToNeckRatio = chest / neck;

    if (bmi < 18.5 || chestToNeckRatio < 2.5) {
      return 'سليم فيت';
    } else if (bmi < 25 || chestToNeckRatio < 2.7) {
      return 'ريجيولار فيت';
    } else {
      return 'ريلاكسد فيت';
    }
  }

  String _determineShirtLength(double armLength, double height) {
    double armToHeightRatio = armLength / height;
    if (armToHeightRatio < 0.31) {
      return 'قصير';
    } else if (armToHeightRatio < 0.33) {
      return 'عادي';
    } else {
      return 'طويل';
    }
  }

  String _getPantsSize(double waist, double hipWidth, double legLength) {
    // جدول مقاسات البنطلون المحسن
    Map<String, Map<String, double>> pantsSizes = {
      '28': {'waist': 71, 'hip': 89, 'inseam': 76, 'thigh': 54},
      '30': {'waist': 76, 'hip': 94, 'inseam': 77, 'thigh': 56},
      '32': {'waist': 81, 'hip': 99, 'inseam': 78, 'thigh': 58},
      '34': {'waist': 86, 'hip': 104, 'inseam': 79, 'thigh': 60},
      '36': {'waist': 91, 'hip': 109, 'inseam': 80, 'thigh': 62},
      '38': {'waist': 96, 'hip': 114, 'inseam': 81, 'thigh': 64},
      '40': {'waist': 101, 'hip': 119, 'inseam': 82, 'thigh': 66},
      '42': {'waist': 106, 'hip': 124, 'inseam': 83, 'thigh': 68},
    };

    String bestSize = '34';
    double minScore = double.infinity;
    double idealInseam = userHeight * 0.45; // طول مثالي للبنطلون

    for (var entry in pantsSizes.entries) {
      double waistDiff = (waist - entry.value['waist']!).abs() * 2.0;
      double hipDiff = (hipWidth - entry.value['hip']!).abs() * 1.5;
      double inseamDiff = (idealInseam - entry.value['inseam']!).abs() * 1.2;

      // تعديل حسب مؤشر كتلة الجسم
      double bmi = userWeight / pow(userHeight / 100, 2);
      double bmiAdjustment = (bmi - 22).abs() * 0.8;

      double score = waistDiff + hipDiff + inseamDiff + bmiAdjustment;

      if (score < minScore) {
        minScore = score;
        bestSize = entry.key;
      }
    }

    // تحديد نوع الملاءمة والطول
    String fit = _determinePantsFit(waist, hipWidth, userWeight, userHeight);
    String length = _determinePantsLength(legLength, userHeight);

    return 'مقاس $bestSize ($fit - $length)';
  }

  String _determinePantsFit(
    double waist,
    double hip,
    double weight,
    double height,
  ) {
    double bmi = weight / pow(height / 100, 2);
    double hipToWaistRatio = hip / waist;

    if (bmi < 18.5 || hipToWaistRatio < 1.15) {
      return 'سليم فيت';
    } else if (bmi < 25 || hipToWaistRatio < 1.25) {
      return 'ريجيولار فيت';
    } else {
      return 'ريلاكسد فيت';
    }
  }

  String _determinePantsLength(double legLength, double height) {
    double legToHeightRatio = legLength / height;
    if (legToHeightRatio < 0.43) {
      return 'قصير';
    } else if (legToHeightRatio < 0.45) {
      return 'عادي';
    } else {
      return 'طويل';
    }
  }

  String _getJacketSize(double chest, double shoulders, double armLength) {
    // جدول مقاسات الجاكيت المحسن
    Map<String, Map<String, double>> jacketSizes = {
      'S': {'chest': 94, 'shoulders': 42, 'sleeve': 59, 'length': 68},
      'M': {'chest': 102, 'shoulders': 44, 'sleeve': 61, 'length': 70},
      'L': {'chest': 110, 'shoulders': 46, 'sleeve': 63, 'length': 72},
      'XL': {'chest': 118, 'shoulders': 48, 'sleeve': 65, 'length': 74},
      'XXL': {'chest': 126, 'shoulders': 50, 'sleeve': 67, 'length': 76},
      '3XL': {'chest': 134, 'shoulders': 52, 'sleeve': 69, 'length': 78},
    };

    String bestSize = 'L';
    double minScore = double.infinity;
    double idealLength = userHeight * 0.42; // طول مثالي للجاكيت

    for (var entry in jacketSizes.entries) {
      double chestDiff = (chest - entry.value['chest']!).abs() * 1.5;
      double shoulderDiff = (shoulders - entry.value['shoulders']!).abs() * 1.3;
      double sleeveDiff = (armLength - entry.value['sleeve']!).abs() * 1.2;
      double lengthDiff = (idealLength - entry.value['length']!).abs();

      // تعديل حسب الوزن ومؤشر كتلة الجسم
      double bmi = userWeight / pow(userHeight / 100, 2);
      double weightAdjustment = (userWeight - 70) * 0.15;
      double bmiAdjustment = (bmi - 22).abs() * 0.7;

      double score =
          chestDiff +
          shoulderDiff +
          sleeveDiff +
          lengthDiff +
          weightAdjustment.abs() +
          bmiAdjustment;

      if (score < minScore) {
        minScore = score;
        bestSize = entry.key;
      }
    }

    // تحديد نوع الملاءمة
    String fit = _determineJacketFit(chest, shoulders, userWeight, userHeight);

    return 'مقاس $bestSize ($fit)';
  }

  String _determineJacketFit(
    double chest,
    double shoulders,
    double weight,
    double height,
  ) {
    double bmi = weight / pow(height / 100, 2);
    double chestToShoulderRatio = chest / shoulders;

    if (bmi < 18.5 || chestToShoulderRatio < 2.3) {
      return 'سليم فيت';
    } else if (bmi < 25 || chestToShoulderRatio < 2.5) {
      return 'ريجيولار فيت';
    } else {
      return 'ريلاكسد فيت';
    }
  }

  Widget _buildSizeInfo() {
    if (clothingSizes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person, size: 60, color: Colors.blue),
            SizedBox(height: 16),
            Text(
              'التقط صورة لمعرفة مقاساتك',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'قف بوضعية واضحة أمام الكاميرا',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'مقاسات ملابسك:',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 8),
            children: [
              _buildSizeCard('التيشيرت', clothingSizes['tshirt']!, Icons.flag),
              _buildSizeCard('القميص', clothingSizes['shirt']!, Icons.work),
              _buildSizeCard(
                'البنطلون',
                clothingSizes['pants']!,
                Icons.straighten,
              ),
              _buildSizeCard(
                'الجاكيت',
                clothingSizes['jacket']!,
                Icons.checkroom,
              ),
            ],
          ),
        ),
        Center(
          child: TextButton.icon(
            onPressed: () {
              setState(() {
                showInputFields = true;
              });
            },
            icon: const Icon(Icons.edit, color: Colors.blue),
            label: const Text(
              'تعديل الطول والوزن',
              style: TextStyle(color: Colors.blue, fontSize: 16),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '* هذه المقاسات تقديرية وقد تختلف حسب الماركة',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _buildSizeCard(String title, String size, IconData icon) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: Colors.blue, size: 30),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16)),
                Text(
                  size,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputFields() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'أدخل بياناتك للحصول على مقاسات أدق',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: heightController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'الطول (سم)',
                suffixText: 'سم',
                icon: Icon(Icons.height, color: Colors.blue),
              ),
              onChanged: (value) {
                setState(() {
                  userHeight = double.tryParse(value) ?? 170.0;
                });
              },
            ),
            const SizedBox(height: 20),
            TextField(
              controller: weightController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'الوزن (كجم)',
                suffixText: 'كجم',
                icon: Icon(Icons.monitor_weight, color: Colors.blue),
              ),
              onChanged: (value) {
                setState(() {
                  userWeight = double.tryParse(value) ?? 70.0;
                });
              },
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'الطول: ${userHeight.toStringAsFixed(1)} سم - الوزن: ${userWeight.toStringAsFixed(1)} كجم',
                style: const TextStyle(fontSize: 16, color: Colors.blue),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('قياس الملابس الذكي'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder:
                    (context) => AlertDialog(
                      title: const Text('نصائح الاستخدام'),
                      content: const SingleChildScrollView(
                        child: Text(
                          '1. قف بوضعية واضحة أمام الكاميرا\n'
                          '2. تأكد من إضاءة جيدة\n'
                          '3. ارتدِ ملابس ضيقة لتسهيل القياس\n'
                          '4. أدخل طولك ووزنك بدقة\n'
                          '5. حافظ على مسافة 2-3 متر من الكاميرا\n\n'
                          '6. تجنب الخلفيات المزدحمة\n'
                          '7. حافظ على استقامة ظهرك\n'
                          '8. تأكد من ظهور كامل جسمك في الإطار',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('حسناً'),
                        ),
                      ],
                    ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (showInputFields) ...[
              Expanded(child: _buildInputFields()),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      showInputFields = false;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'حفظ البيانات والمتابعة',
                    style: TextStyle(fontSize: 18, color: Colors.white),
                  ),
                ),
              ),
            ] else ...[
              Expanded(
                flex: 3,
                child: FutureBuilder<void>(
                  future: _initializeControllerFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.done) {
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          double width = constraints.maxWidth;
                          double height = width * 4 / 3;

                          if (height > constraints.maxHeight) {
                            height = constraints.maxHeight;
                            width = height * 3 / 4;
                          }

                          return Center(
                            child: SizedBox(
                              width: width,
                              height: height,
                              child: Stack(
                                children: [
                                  CameraPreview(_controller),
                                  if (poses != null && poses!.isNotEmpty)
                                    CustomPaint(
                                      painter: PosePainter(poses!.first),
                                      size: Size(width, height),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    } else {
                      return const Center(child: CircularProgressIndicator());
                    }
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: ElevatedButton.icon(
                  onPressed:
                      isProcessing
                          ? null
                          : () async {
                            try {
                              await _initializeControllerFuture;
                              final image = await _controller.takePicture();
                              await _processImage(image);
                            } catch (e) {
                              debugPrint('Error: $e');
                            }
                          },
                  icon: const Icon(Icons.camera_alt),
                  label: Text(
                    isProcessing
                        ? 'جاري المعالجة...'
                        : 'التقط صورة لقياس المقاسات',
                    style: const TextStyle(fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: _buildSizeInfo(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PosePainter extends CustomPainter {
  final Pose pose;

  PosePainter(this.pose);

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.green
          ..strokeWidth = 4.0
          ..style = PaintingStyle.stroke;

    for (final landmark in pose.landmarks.values) {
      canvas.drawCircle(
        Offset(landmark.x * size.width, landmark.y * size.height),
        4.0,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
