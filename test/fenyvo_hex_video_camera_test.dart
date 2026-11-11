import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/widgets/fenyvo_hex_video_camera.dart';

void main() {
  test('camera control sends sequential commands', () {
    final control = FenyvoHexCameraControl();
    final commands = <FenyvoHexCameraCommand?>[];

    void listener() => commands.add(control.command);
    control.addListener(listener);

    control.startRecording();
    control.sendRecording();
    control.startRecording();
    control.cancelRecording();
    control.switchCamera();

    expect(commands, [
      FenyvoHexCameraCommand.start,
      FenyvoHexCameraCommand.send,
      FenyvoHexCameraCommand.start,
      FenyvoHexCameraCommand.cancel,
      FenyvoHexCameraCommand.switchCamera,
    ]);

    control.removeListener(listener);
    control.dispose();
  });
  CameraDescription camera(String name, CameraLensDirection direction) {
    return CameraDescription(
      name: name,
      lensDirection: direction,
      sensorOrientation: 90,
    );
  }

  test('front camera is preferred', () {
    final cameras = [
      camera('back', CameraLensDirection.back),
      camera('front', CameraLensDirection.front),
    ];
    expect(FenyvoHexVideoCamera.preferredCamera(cameras)?.name, 'front');
  });

  test('uses back camera when front is absent', () {
    expect(
      FenyvoHexVideoCamera.preferredCamera([
        camera('back', CameraLensDirection.back),
      ])?.name,
      'back',
    );
  });

  test('handles no cameras safely', () {
    expect(FenyvoHexVideoCamera.preferredCamera([]), isNull);
  });
}
