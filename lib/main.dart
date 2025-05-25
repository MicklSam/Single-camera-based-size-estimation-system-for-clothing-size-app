import 'dart:io';

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
      title: 'Pose Detection Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
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

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    poseDetector.close();
    super.dispose();
  }

  Future<void> _processImage(XFile imageFile) async {
    if (isProcessing) return;
    isProcessing = true;

    final inputImage = InputImage.fromFilePath(imageFile.path);
    poses = await poseDetector.processImage(inputImage);

    setState(() {
      isProcessing = false;
    });
  }

  Widget _buildPosesInfo() {
    if (poses == null || poses!.isEmpty) {
      return const Text('لم يتم الكشف عن وضعية');
    }
    final pose = poses!.first;
    final landmarks = pose.landmarks;

    return Column(
      children:
          landmarks.entries.map((entry) {
            final point = entry.value;
            return Text(
              '${entry.key}: (${point.x.toStringAsFixed(1)}, ${point.y.toStringAsFixed(1)})',
            );
          }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('كشف وضعية الجسم')),
      body: SafeArea(
        child: Column(
          children: [
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
                            child: CameraPreview(_controller),
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
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton(
                onPressed: () async {
                  try {
                    await _initializeControllerFuture;
                    final image = await _controller.takePicture();
                    await _processImage(image);
                  } catch (e) {
                    debugPrint('Error: $e');
                  }
                },
                child: const Text('التقط صورة وحلل'),
              ),
            ),
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(8.0),
                child: SingleChildScrollView(child: _buildPosesInfo()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
