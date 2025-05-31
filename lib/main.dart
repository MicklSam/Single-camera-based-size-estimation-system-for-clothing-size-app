import 'dart:math';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'pose_detector.dart';
import 'pose_painter.dart';

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
      home: UserDataScreen(camera: camera),
    );
  }
}

class UserDataScreen extends StatefulWidget {
  final CameraDescription camera;
  const UserDataScreen({super.key, required this.camera});

  @override
  State<UserDataScreen> createState() => _UserDataScreenState();
}

class _UserDataScreenState extends State<UserDataScreen> {
  final TextEditingController heightController = TextEditingController(
    text: '170',
  );
  final TextEditingController weightController = TextEditingController(
    text: '70',
  );
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    heightController.dispose();
    weightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('قياس الملابس الذكي')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.person_outline, size: 120, color: Colors.blue),
                const SizedBox(height: 32),
                const Text(
                  'أدخل بياناتك للحصول على مقاسات دقيقة',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: heightController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'الطول (سم)',
                    prefixIcon: Icon(Icons.height),
                    suffixText: 'سم',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'من فضلك أدخل طولك';
                    }
                    final height = double.tryParse(value);
                    if (height == null || height < 100 || height > 250) {
                      return 'من فضلك أدخل طول صحيح (100-250 سم)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: weightController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'الوزن (كجم)',
                    prefixIcon: Icon(Icons.monitor_weight),
                    suffixText: 'كجم',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'من فضلك أدخل وزنك';
                    }
                    final weight = double.tryParse(value);
                    if (weight == null || weight < 30 || weight > 200) {
                      return 'من فضلك أدخل وزن صحيح (30-200 كجم)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder:
                              (context) => CameraScreen(
                                camera: widget.camera,
                                userHeight: double.parse(heightController.text),
                                userWeight: double.parse(weightController.text),
                              ),
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('متابعة', style: TextStyle(fontSize: 18)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CameraScreen extends StatefulWidget {
  final CameraDescription camera;
  final double userHeight;
  final double userWeight;

  const CameraScreen({
    super.key,
    required this.camera,
    required this.userHeight,
    required this.userWeight,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  final _poseDetector = PoseDetector();
  Pose? detectedPose;
  bool isProcessing = false;
  Map<String, Map<String, String>> clothingSizes = {};
  double conversionFactor = 0.0;
  String? errorMessage;
  Size? imageSize;

  @override
  void initState() {
    super.initState();
    _initializeDetector();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _initializeControllerFuture = _controller.initialize().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _initializeDetector() async {
    try {
      await _poseDetector.initialize();
    } catch (e) {
      setState(() {
        errorMessage = 'خطأ في تهيئة نظام كشف الأشخاص: $e';
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _poseDetector.close();
    super.dispose();
  }

  Future<void> _processImage(XFile imageFile) async {
    if (isProcessing) return;
    setState(() {
      isProcessing = true;
      errorMessage = null;
    });

    try {
      final poseResults = await _poseDetector.detectPose(imageFile.path);
      if (poseResults.isEmpty) {
        setState(() {
          errorMessage =
              'لم يتم العثور على شخص في الصورة. يرجى التأكد من ظهور كامل جسمك في الإطار.';
          detectedPose = null;
        });
        return;
      }

      final pose = Pose.fromJson(poseResults[0]);
      setState(() {
        detectedPose = pose;
      });

      try {
        final measurements = _calculateBodyMeasurements(pose);
        _determineClothingSizes(measurements);
      } catch (e) {
        setState(() {
          errorMessage =
              'لم نتمكن من تحديد جميع نقاط الجسم. يرجى المحاولة مرة أخرى في وضع مختلف.';
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'حدث خطأ أثناء معالجة الصورة. يرجى المحاولة مرة أخرى.';
      });
    } finally {
      setState(() {
        isProcessing = false;
      });
    }
  }

  void _resetMeasurements() {
    setState(() {
      detectedPose = null;
      clothingSizes.clear();
      errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    // Make camera preview square
    final previewSize = screenSize.width;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('قياس الملابس الذكي'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => UserDataScreen(camera: widget.camera),
              ),
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetMeasurements,
            tooltip: 'قياس جديد',
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (!_controller.value.isInitialized) {
              return const Center(child: CircularProgressIndicator());
            }

            return Stack(
              children: [
                Column(
                  children: [
                    Container(
                      width: screenSize.width,
                      height: previewSize,
                      color: Colors.black,
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.center,
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: previewSize,
                              height: previewSize,
                              child: Stack(
                                children: [
                                  Transform.scale(
                                    scale: 1.0,
                                    child: Center(
                                      child: CameraPreview(_controller),
                                    ),
                                  ),
                                  if (detectedPose != null && imageSize != null)
                                    CustomPaint(
                                      painter: PosePainter(
                                        pose: detectedPose!,
                                        imageSize: imageSize!,
                                        widgetSize: Size(
                                          previewSize,
                                          previewSize,
                                        ),
                                      ),
                                    ),
                                  if (errorMessage != null)
                                    Container(
                                      color: Colors.black54,
                                      padding: const EdgeInsets.all(16),
                                      child: Center(
                                        child: Text(
                                          errorMessage!,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (!clothingSizes.isEmpty)
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          color: Colors.white,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'المقاسات المقترحة:',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close),
                                      onPressed: _resetMeasurements,
                                      color: Colors.grey[600],
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  itemCount: clothingSizes.length,
                                  itemBuilder: (context, index) {
                                    final entry = clothingSizes.entries
                                        .elementAt(index);
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[50],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                _getClothingIcon(entry.key),
                                                size: 24,
                                                color: Colors.blue,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                entry.key,
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              Text(
                                                'المقاس: ',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  color: Colors.grey[700],
                                                ),
                                              ),
                                              Text(
                                                '${entry.value['size']}',
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  color: Colors.blue,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (entry.value['fit'] != null)
                                            Row(
                                              children: [
                                                Text(
                                                  'الفيت: ',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.grey[700],
                                                  ),
                                                ),
                                                Text(
                                                  '${entry.value['fit']}',
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.blue,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          try {
            await _initializeControllerFuture;
            final image = await _controller.takePicture();
            imageSize = await _getImageSize(image.path);
            await _processImage(image);
          } catch (e) {
            setState(() {
              errorMessage =
                  'حدث خطأ في التقاط الصورة. يرجى المحاولة مرة أخرى.';
            });
          }
        },
        child: const Icon(Icons.camera_alt),
      ),
    );
  }

  IconData _getClothingIcon(String type) {
    switch (type) {
      case 'تيشيرت':
        return Icons.dry_cleaning;
      case 'قميص':
        return Icons.checkroom;
      case 'جاكيت':
        return Icons.style;
      case 'بنطلون':
        return Icons.accessibility_new;
      default:
        return Icons.checkroom;
    }
  }

  Future<Size> _getImageSize(String imagePath) async {
    final file = File(imagePath);
    final bytes = await file.readAsBytes();
    final image = await decodeImageFromList(bytes);
    return Size(image.width.toDouble(), image.height.toDouble());
  }

  Map<String, double> _calculateBodyMeasurements(Pose pose) {
    // Basic landmarks
    final leftShoulder = pose.getLandmark(PoseLandmarkType.leftShoulder);
    final rightShoulder = pose.getLandmark(PoseLandmarkType.rightShoulder);
    final leftHip = pose.getLandmark(PoseLandmarkType.leftHip);
    final rightHip = pose.getLandmark(PoseLandmarkType.rightHip);
    final leftElbow = pose.getLandmark(PoseLandmarkType.leftElbow);
    final rightElbow = pose.getLandmark(PoseLandmarkType.rightElbow);
    final leftWrist = pose.getLandmark(PoseLandmarkType.leftWrist);
    final rightWrist = pose.getLandmark(PoseLandmarkType.rightWrist);
    final leftKnee = pose.getLandmark(PoseLandmarkType.leftKnee);
    final rightKnee = pose.getLandmark(PoseLandmarkType.rightKnee);
    final leftAnkle = pose.getLandmark(PoseLandmarkType.leftAnkle);
    final rightAnkle = pose.getLandmark(PoseLandmarkType.rightAnkle);
    final nose = pose.getLandmark(PoseLandmarkType.nose);
    final leftHeel = pose.getLandmark(PoseLandmarkType.leftHeel);
    final rightHeel = pose.getLandmark(PoseLandmarkType.rightHeel);

    // Additional landmarks for better accuracy
    final leftEar = pose.getLandmark(PoseLandmarkType.leftEar);
    final rightEar = pose.getLandmark(PoseLandmarkType.rightEar);
    final leftEye = pose.getLandmark(PoseLandmarkType.leftEye);
    final rightEye = pose.getLandmark(PoseLandmarkType.rightEye);
    final leftPinky = pose.getLandmark(PoseLandmarkType.leftPinky);
    final rightPinky = pose.getLandmark(PoseLandmarkType.rightPinky);
    final leftIndex = pose.getLandmark(PoseLandmarkType.leftIndex);
    final rightIndex = pose.getLandmark(PoseLandmarkType.rightIndex);

    // Null checks for all landmarks
    if (leftShoulder == null ||
        rightShoulder == null ||
        leftHip == null ||
        rightHip == null ||
        leftElbow == null ||
        rightElbow == null ||
        leftWrist == null ||
        rightWrist == null ||
        leftKnee == null ||
        rightKnee == null ||
        leftAnkle == null ||
        rightAnkle == null ||
        nose == null ||
        leftHeel == null ||
        rightHeel == null ||
        leftEar == null ||
        rightEar == null ||
        leftEye == null ||
        rightEye == null ||
        leftPinky == null ||
        rightPinky == null ||
        leftIndex == null ||
        rightIndex == null) {
      throw Exception('Missing required landmarks');
    }

    // New waist-specific landmarks (after null checks)
    final leftWaistPoint = _interpolatePoint(
      leftShoulder,
      leftHip,
      0.6,
      PoseLandmarkType.leftHip,
    );
    final rightWaistPoint = _interpolatePoint(
      rightShoulder,
      rightHip,
      0.6,
      PoseLandmarkType.rightHip,
    );
    final frontWaistPoint = _interpolatePoint(
      leftWaistPoint,
      rightWaistPoint,
      0.5,
      PoseLandmarkType.nose, // Using nose type as a generic center point
    );

    // Calculate mid-points for better waist estimation
    final midLeftTorso = _interpolatePoint(
      leftShoulder,
      leftHip,
      0.5,
      PoseLandmarkType.leftHip,
    );
    final midRightTorso = _interpolatePoint(
      rightShoulder,
      rightHip,
      0.5,
      PoseLandmarkType.rightHip,
    );

    // Calculate total height more accurately using multiple points
    double heightPixels = _calculateEnhancedHeight(
      nose,
      leftEye,
      rightEye,
      leftEar,
      rightEar,
      leftHeel,
      rightHeel,
    );
    conversionFactor = widget.userHeight / heightPixels;

    // Enhanced measurements using additional points
    double shoulderWidth = _calculateEnhancedShoulderWidth(
      leftShoulder,
      rightShoulder,
      leftElbow,
      rightElbow,
    );

    double armLength = _calculateArmLength(
      leftShoulder,
      leftElbow,
      leftWrist,
      leftPinky,
      rightShoulder,
      rightElbow,
      rightWrist,
      rightPinky,
    );

    double chestWidth = _calculateEnhancedChestWidth(
      leftShoulder,
      rightShoulder,
      leftHip,
      rightHip,
    );

    double chestDepth = _calculateEnhancedChestDepth(
      chestWidth,
      widget.userWeight,
      widget.userHeight,
      shoulderWidth,
    );

    double chestCircumference = _calculateEnhancedEllipticalCircumference(
      chestWidth,
      chestDepth,
    );

    double waistWidth = _calculateEnhancedWaistWidth(
      leftHip,
      rightHip,
      leftWaistPoint,
      rightWaistPoint,
      midLeftTorso,
      midRightTorso,
      leftElbow,
      rightElbow,
    );

    double waistDepth = _calculateEnhancedWaistDepth(
      waistWidth,
      widget.userWeight,
      widget.userHeight,
      chestWidth,
      frontWaistPoint.z,
    );

    double waistCircumference = _calculateEnhancedEllipticalCircumference(
      waistWidth,
      waistDepth,
    );

    double hipWidth = _calculateEnhancedHipWidth(leftHip, rightHip);
    double hipDepth = _calculateEnhancedHipDepth(
      hipWidth,
      widget.userWeight,
      widget.userHeight,
      waistWidth,
    );

    double inseam = _calculateInseam(leftHip, leftKnee, leftAnkle);
    double outseam = _calculateOutseam(leftHip, leftKnee, leftAnkle, leftHeel);

    return {
      'shoulderWidth': shoulderWidth * conversionFactor,
      'armLength': armLength * conversionFactor,
      'chestCircumference': chestCircumference * conversionFactor,
      'waistCircumference': waistCircumference * conversionFactor,
      'hipCircumference':
          _calculateEnhancedEllipticalCircumference(hipWidth, hipDepth) *
          conversionFactor,
      'inseam': inseam * conversionFactor,
      'outseam': outseam * conversionFactor,
    };
  }

  // New enhanced calculation methods
  double _calculateEnhancedHeight(
    PoseLandmark nose,
    PoseLandmark leftEye,
    PoseLandmark rightEye,
    PoseLandmark leftEar,
    PoseLandmark rightEar,
    PoseLandmark leftHeel,
    PoseLandmark rightHeel,
  ) {
    // Use the highest point among head landmarks
    double topY = min(
      min(nose.y, min(leftEye.y, rightEye.y)),
      min(leftEar.y, rightEar.y),
    );
    // Use the lowest point among heel landmarks
    double bottomY = max(leftHeel.y, rightHeel.y);
    return bottomY - topY;
  }

  double _calculateEnhancedShoulderWidth(
    PoseLandmark leftShoulder,
    PoseLandmark rightShoulder,
    PoseLandmark leftElbow,
    PoseLandmark rightElbow,
  ) {
    double directWidth = (rightShoulder.x - leftShoulder.x).abs();
    double elbowWidth = (rightElbow.x - leftElbow.x).abs();
    // Use weighted average favoring direct shoulder measurement
    return (directWidth * 0.7) + (elbowWidth * 0.3);
  }

  double _calculateArmLength(
    PoseLandmark leftShoulder,
    PoseLandmark leftElbow,
    PoseLandmark leftWrist,
    PoseLandmark leftPinky,
    PoseLandmark rightShoulder,
    PoseLandmark rightElbow,
    PoseLandmark rightWrist,
    PoseLandmark rightPinky,
  ) {
    double leftArmLength = _calculateLimbLength(
      leftShoulder,
      leftElbow,
      leftWrist,
      leftPinky,
    );
    double rightArmLength = _calculateLimbLength(
      rightShoulder,
      rightElbow,
      rightWrist,
      rightPinky,
    );
    return (leftArmLength + rightArmLength) / 2;
  }

  double _calculateLimbLength(
    PoseLandmark point1,
    PoseLandmark point2,
    PoseLandmark point3,
    PoseLandmark point4,
  ) {
    double length1 = _calculateDistance(point1, point2);
    double length2 = _calculateDistance(point2, point3);
    double length3 = _calculateDistance(point3, point4);
    return length1 + length2 + length3;
  }

  double _calculateDistance(PoseLandmark point1, PoseLandmark point2) {
    double dx = point2.x - point1.x;
    double dy = point2.y - point1.y;
    double dz = point2.z - point1.z;
    return sqrt(dx * dx + dy * dy + dz * dz);
  }

  double _calculateInseam(
    PoseLandmark hip,
    PoseLandmark knee,
    PoseLandmark ankle,
  ) {
    return _calculateLimbLength(hip, knee, ankle, ankle);
  }

  double _calculateOutseam(
    PoseLandmark hip,
    PoseLandmark knee,
    PoseLandmark ankle,
    PoseLandmark heel,
  ) {
    return _calculateLimbLength(hip, knee, ankle, heel);
  }

  double _calculateEnhancedEllipticalCircumference(double width, double depth) {
    // Using Ramanujan's approximation for ellipse circumference
    double a = width / 2;
    double b = depth / 2;
    double h = pow(a - b, 2) / pow(a + b, 2);
    return pi * (a + b) * (1 + (3 * h) / (10 + sqrt(4 - 3 * h)));
  }

  double _calculateEnhancedChestWidth(
    PoseLandmark leftShoulder,
    PoseLandmark rightShoulder,
    PoseLandmark leftHip,
    PoseLandmark rightHip,
  ) {
    final shoulderWidth = _distanceBetween(leftShoulder, rightShoulder);
    final hipWidth = _distanceBetween(leftHip, rightHip);
    return max(shoulderWidth, hipWidth) * conversionFactor;
  }

  double _calculateEnhancedChestDepth(
    double width,
    double weight,
    double height,
    double shoulderWidth,
  ) {
    final bmi = weight / pow(height / 100, 2);
    return width * (0.5 + (bmi - 21.75) * 0.01);
  }

  double _calculateEnhancedWaistWidth(
    PoseLandmark leftHip,
    PoseLandmark rightHip,
    PoseLandmark leftWaistPoint,
    PoseLandmark rightWaistPoint,
    PoseLandmark midLeftTorso,
    PoseLandmark midRightTorso,
    PoseLandmark leftElbow,
    PoseLandmark rightElbow,
  ) {
    // Calculate different width measurements
    double hipWidth = _distanceBetween(leftHip, rightHip);
    double waistPointWidth = _distanceBetween(leftWaistPoint, rightWaistPoint);
    double midTorsoWidth = _distanceBetween(midLeftTorso, midRightTorso);
    double elbowWidth = _distanceBetween(leftElbow, rightElbow);

    // Use weighted average of different measurements
    // Give more weight to waist-specific measurements
    return (hipWidth * 0.3 +
            waistPointWidth * 0.4 +
            midTorsoWidth * 0.2 +
            elbowWidth * 0.1) *
        conversionFactor;
  }

  double _calculateEnhancedWaistDepth(
    double width,
    double weight,
    double height,
    double chestWidth,
    double frontZ,
  ) {
    final bmi = weight / pow(height / 100, 2);

    // Base depth calculation
    double baseDepth = width * (0.4 + (bmi - 21.75) * 0.015);

    // Adjust depth based on BMI categories
    if (bmi < 18.5) {
      // Underweight - slimmer profile
      baseDepth *= 0.9;
    } else if (bmi >= 25 && bmi < 30) {
      // Overweight - fuller profile
      baseDepth *= 1.1;
    } else if (bmi >= 30) {
      // Obese - fullest profile
      baseDepth *= 1.2;
    }

    // Consider the Z-coordinate for depth adjustment
    double zAdjustment = frontZ * 0.1;
    baseDepth += zAdjustment;

    // Ensure depth is proportional to chest
    double maxDepth = chestWidth * 0.8;
    return min(baseDepth, maxDepth);
  }

  double _calculateEnhancedHipWidth(
    PoseLandmark leftHip,
    PoseLandmark rightHip,
  ) {
    return _distanceBetween(leftHip, rightHip) * conversionFactor;
  }

  double _calculateEnhancedHipDepth(
    double width,
    double weight,
    double height,
    double waistWidth,
  ) {
    final bmi = weight / pow(height / 100, 2);
    return width * (0.45 + (bmi - 21.75) * 0.0125);
  }

  double _distanceBetween(PoseLandmark p1, PoseLandmark p2) {
    return sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2));
  }

  String _determineFit(double bmi, double ratio) {
    if (bmi < 18.5 || ratio < 0.8) return 'سليم فت';
    if (bmi < 25 || ratio < 0.9) return 'ريجيولار فت';
    return 'ريلاكسد فت';
  }

  void _determineClothingSizes(Map<String, double> measurements) {
    final chest = measurements['chestCircumference'] ?? 0;
    final waist = measurements['waistCircumference'] ?? 0;
    final hip = measurements['hipCircumference'] ?? 0;
    final inseam = measurements['inseam'] ?? 0;
    final shoulder = measurements['shoulderWidth'] ?? 0;

    final bmi = widget.userWeight / pow(widget.userHeight / 100, 2);
    final chestToHeightRatio = chest / widget.userHeight;
    final waistToHipRatio = waist / hip;

    setState(() {
      clothingSizes = {
        'تيشيرت': {
          'size': _getTshirtSize(chest),
          'fit': _determineFit(bmi, chestToHeightRatio),
        },
        'قميص': {
          'size': _getShirtSize(chest, shoulder),
          'fit': _determineFit(bmi, chestToHeightRatio),
        },
        'جاكيت': {
          'size': _getJacketSize(chest, shoulder),
          'fit': _determineFit(bmi, chestToHeightRatio),
        },
        'بنطلون': {
          'size': _getPantsSize(waist, hip, inseam),
          'fit': _determineFit(bmi, waistToHipRatio),
        },
      };
    });
  }

  String _getTshirtSize(double chest) {
    if (chest < 89) return 'XS';
    if (chest < 97) return 'S';
    if (chest < 105) return 'M';
    if (chest < 113) return 'L';
    if (chest < 121) return 'XL';
    return '2XL';
  }

  String _getShirtSize(double chest, double shoulder) {
    if (chest < 89) return 'XS (14)';
    if (chest < 97) return 'S (15)';
    if (chest < 105) return 'M (15.5)';
    if (chest < 113) return 'L (16)';
    if (chest < 121) return 'XL (17)';
    return '2XL (18)';
  }

  String _getPantsSize(double waist, double hip, double inseam) {
    // Enhanced pants sizing with more granular measurements
    if (waist < 71) return '26';
    if (waist < 73) return '28';
    if (waist < 76) return '29';
    if (waist < 78) return '30';
    if (waist < 81) return '31';
    if (waist < 83) return '32';
    if (waist < 86) return '33';
    if (waist < 88) return '34';
    if (waist < 91) return '35';
    if (waist < 93) return '36';
    if (waist < 96) return '37';
    if (waist < 98) return '38';
    if (waist < 101) return '39';
    if (waist < 103) return '40';
    return '42';
  }

  String _getJacketSize(double chest, double shoulder) {
    if (chest < 89) return '44 (XS)';
    if (chest < 97) return '46 (S)';
    if (chest < 105) return '48 (M)';
    if (chest < 113) return '50 (L)';
    if (chest < 121) return '52 (XL)';
    return '54 (2XL)';
  }

  // New helper method to interpolate between two points
  PoseLandmark _interpolatePoint(
    PoseLandmark p1,
    PoseLandmark p2,
    double t,
    PoseLandmarkType type,
  ) {
    return PoseLandmark(
      type: type,
      x: p1.x + (p2.x - p1.x) * t,
      y: p1.y + (p2.y - p1.y) * t,
      z: p1.z + (p2.z - p1.z) * t,
      visibility: min(p1.visibility, p2.visibility),
    );
  }
}
