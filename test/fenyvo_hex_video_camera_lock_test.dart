import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/fenyvo_hex_video_camera.dart';

void main() {
  test('camera lock does not emit send or cancel', () {
    final control = FenyvoHexCameraControl();
    final commands = <FenyvoHexCameraCommand>[];
    void listener() {
      final command = control.command;
      if (command != null) commands.add(command);
    }

    control.addListener(listener);
    control.startRecording();
    control.lockRecording();

    expect(commands, [
      FenyvoHexCameraCommand.start,
      FenyvoHexCameraCommand.lock,
    ]);

    control.sendRecording();
    expect(commands.last, FenyvoHexCameraCommand.send);

    control.removeListener(listener);
    control.dispose();
  });
}
