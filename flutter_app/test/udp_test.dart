import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/services/udp_io.dart';

void main() {
  test(
    'native Dart receiver receives a local UDP datagram and stops',
    () async {
      final probe = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = probe.port;
      probe.close();
      final receiver = UdpReceiver(), received = Completer<Uint8List>();
      RawDatagramSocket? sender;
      try {
        await receiver.start(
          port,
          (bytes) {
            if (!received.isCompleted) received.complete(bytes);
          },
          (error) {
            if (!received.isCompleted) received.completeError(error);
          },
        );
        sender = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
        sender.send([10, 20, 30, 40], InternetAddress.loopbackIPv4, port);
        expect(await received.future.timeout(const Duration(seconds: 3)), [
          10,
          20,
          30,
          40,
        ]);
      } finally {
        receiver.stop();
        sender?.close();
      }
    },
  );
}
