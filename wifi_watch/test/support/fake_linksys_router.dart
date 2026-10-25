// A pretend Linksys Smart Wi-Fi router: the JNAP actions the app uses, with
// the login checked the way the router checks it.
import 'dart:convert';
import 'dart:io';

class FakeLinksysRouter {
  final String password;
  int unauthorized = 0;
  late HttpServer _server;

  FakeLinksysRouter({this.password = 'secret'});

  String get address => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    final body = await utf8.decoder.bind(req).join();
    if (req.uri.path != '/JNAP/' || req.method != 'POST' || req.headers.contentLength < 0) {
      res.statusCode = 404;
      await res.close();
      return;
    }
    jsonDecode(body); // must be JSON
    final action = req.headers.value('X-JNAP-Action') ?? '';
    final auth = req.headers.value('X-JNAP-Authorization');
    Object reply;
    if (auth != 'Basic ${base64.encode(utf8.encode('admin:$password'))}') {
      unauthorized++;
      reply = {'result': '_ErrorUnauthorized'};
    } else {
      reply = switch (action) {
        'http://linksys.com/jnap/core/GetDeviceInfo' => {
            'result': 'OK',
            'output': {'modelNumber': 'EA6350', 'firmwareVersion': '3.1.10'},
          },
        'http://linksys.com/jnap/devicelist/GetDevices' => {
            'result': 'OK',
            'output': {
              'devices': [
                {'deviceID': 'r', 'isAuthority': true, 'connections': [{'macAddress': '00:11:22:33:44:55'}]},
                {
                  'deviceID': 'a',
                  'friendlyName': 'Galaxy-Tab',
                  'model': {'manufacturer': 'Samsung'},
                  'connections': [{'macAddress': 'aa:bb:cc:00:00:01', 'ipAddress': '192.168.1.101'}],
                  'properties': [{'name': 'userDeviceName', 'value': 'Kids tablet'}],
                },
                {
                  'deviceID': 'b',
                  'friendlyName': 'Smart-TV',
                  'connections': [{'macAddress': 'aa:bb:cc:00:00:02', 'ipAddress': '192.168.1.102'}],
                },
                {'deviceID': 'c', 'friendlyName': 'Old phone', 'connections': []},
              ],
            },
          },
        'http://linksys.com/jnap/networkconnections/GetNetworkConnections' => {
            'result': 'OK',
            'output': {
              'connections': [
                {'macAddress': 'AA:BB:CC:00:00:01', 'wireless': {'band': '5GHz', 'signalDecibels': -55}},
                {'macAddress': 'AA:BB:CC:00:00:02'},
              ],
            },
          },
        _ => {'result': '_ErrorUnknownAction'},
      };
    }
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(reply));
    await res.close();
  }
}
