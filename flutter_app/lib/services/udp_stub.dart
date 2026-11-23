import 'dart:typed_data';

class UdpReceiver {
  Future<List<String>> start(
    int port,
    void Function(Uint8List) onPacket,
    void Function(String) onError,
  ) async => throw UnsupportedError('浏览器不能直接接收 UDP，请在手机安装版中连接。');
  void stop() {}
}
