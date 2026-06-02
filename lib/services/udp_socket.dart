import 'dart:io';

/// Thin wrapper around [RawDatagramSocket] for fire-and-forget UDP sends.
///
/// Mirrors the socket setup pattern used in fpp_view's discovery_transport_io.
class UdpSocket {
  final RawDatagramSocket _socket;

  UdpSocket._(this._socket);

  static Future<UdpSocket> create() async {
    final socket =
        await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    return UdpSocket._(socket);
  }

  /// Sends [data] to [dest]:[port]. Returns the number of bytes sent (0 if the
  /// OS send buffer was momentarily full).
  int send(List<int> data, InternetAddress dest, int port) {
    return _socket.send(data, dest, port);
  }

  void close() => _socket.close();
}
