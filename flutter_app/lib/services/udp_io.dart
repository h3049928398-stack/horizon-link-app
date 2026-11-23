import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class UdpReceiver {
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  int _generation = 0;
  Future<List<String>> start(
    int port,
    void Function(Uint8List) onPacket,
    void Function(String) onError,
  ) async {
    if (port < 1024 || port > 65535 || (port >= 5200 && port <= 5300)) {
      throw ArgumentError('端口须在 1024–65535 之间，并避开 5200–5300');
    }
    stop();
    final generation = _generation;
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: false,
    );
    if (generation != _generation) {
      socket.close();
      return [];
    }
    _socket = socket;
    _subscription = _socket!.listen((event) {
      if (event == RawSocketEvent.read) {
        Datagram? packet;
        while ((packet = _socket?.receive()) != null) {
          onPacket(packet!.data);
        }
      }
    }, onError: (Object error) => onError(error.toString()));
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    if (generation != _generation) return [];
    return interfaces.expand((i) => i.addresses).map((a) => a.address).toList();
  }

  void stop() {
    _generation++;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _socket?.close();
    _socket = null;
  }
}
