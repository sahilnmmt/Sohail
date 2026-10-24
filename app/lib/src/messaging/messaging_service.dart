// MQTT connection to the family's message server: the group feed, robot
// presence and sending nudges, emoji reactions and texts.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../settings.dart';
import 'message.dart';

enum LinkState { disconnected, connecting, connected, failed }

class FeedItem {
  final SohailMessage message;
  final DateTime received;
  final bool mine;
  FeedItem(this.message, this.received, {required this.mine});

  DateTime get time =>
      message.ts > 0 ? DateTime.fromMillisecondsSinceEpoch(message.ts * 1000) : received;
}

class MessagingService extends ChangeNotifier {
  static const maxFeed = 200;

  LinkState state = LinkState.disconnected;
  String? error;
  final List<FeedItem> feed = [];

  /// Robot id -> online, from retained status messages.
  final Map<String, bool> robots = {};

  AppSettings? _settings;
  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updates;
  final Set<String> _seen = {};
  bool _disposed = false;

  bool get isConnected => state == LinkState.connected;
  AppSettings? get settings => _settings;

  Future<void> connect(AppSettings settings) async {
    await disconnect();
    _settings = settings;
    if (!settings.isComplete) {
      state = LinkState.disconnected;
      error = null;
      _notify();
      return;
    }
    state = LinkState.connecting;
    error = null;
    _notify();

    final client = MqttServerClient.withPort(settings.host, settings.clientId, settings.port)
      ..keepAlivePeriod = 30
      ..autoReconnect = true
      ..resubscribeOnAutoReconnect = true
      ..logging(on: false)
      ..setProtocolV311()
      ..secure = settings.tls
      ..connectTimeoutPeriod = 8000
      ..onAutoReconnect = () {
        state = LinkState.connecting;
        _notify();
      }
      ..onAutoReconnected = () {
        state = LinkState.connected;
        _notify();
      };
    client.connectionMessage = MqttConnectMessage().withClientIdentifier(settings.clientId).startClean();
    _client = client;

    try {
      final user = settings.username.isEmpty ? null : settings.username;
      final status = await client.connect(user, user == null ? null : settings.password);
      if (status?.state != MqttConnectionState.connected) {
        throw Exception(status?.returnCode?.toString() ?? 'no answer');
      }
    } catch (e) {
      client.disconnect();
      _client = null;
      state = LinkState.failed;
      error = _describe(e);
      _notify();
      return;
    }

    client.subscribe(groupInboxTopic(settings.group), MqttQos.atLeastOnce);
    client.subscribe(statusTopicFilter, MqttQos.atLeastOnce);
    _updates = client.updates?.listen(_onMessages);
    state = LinkState.connected;
    _notify();
  }

  String _describe(Object e) {
    final s = e.toString();
    if (s.contains('notAuthorized') || s.contains('badUsernameOrPassword')) {
      return 'The server refused the username or password.';
    }
    if (s.contains('SocketException') || s.contains('NoConnectionException') || s.contains('no answer')) {
      return 'Could not reach ${_settings!.host}:${_settings!.port}. Check the address and that your phone is on the same network.';
    }
    return 'Could not connect: $s';
  }

  void _onMessages(List<MqttReceivedMessage<MqttMessage>> batch) {
    var changed = false;
    for (final m in batch) {
      final pub = m.payload as MqttPublishMessage;
      final payload = utf8.decode(pub.payload.message, allowMalformed: true);
      final device = deviceFromStatusTopic(m.topic);
      if (device != null) {
        if (device != _settings?.clientId) {
          robots[device] = payload == 'online';
          changed = true;
        }
        continue;
      }
      final msg = SohailMessage.tryDecode(payload);
      if (msg == null || !_seen.add(msg.id)) continue;
      _addToFeed(FeedItem(msg, DateTime.now(), mine: msg.from == _settings?.clientId));
      changed = true;
    }
    if (changed) _notify();
  }

  void _addToFeed(FeedItem item) {
    feed.add(item);
    if (feed.length > maxFeed) feed.removeRange(0, feed.length - maxFeed);
  }

  /// Sends to the group. Returns an error to show, or null on success.
  String? send(MessageType type, {Emoji? emoji, String? text}) {
    final s = _settings;
    final client = _client;
    if (s == null || client == null || state != LinkState.connected) return 'Not connected to the message server.';
    final SohailMessage msg;
    try {
      msg = SohailMessage(
        id: randomMessageId(),
        from: s.clientId,
        name: s.displayName,
        type: type,
        emoji: emoji,
        text: text,
        ts: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
    } on ArgumentError catch (e) {
      return 'Message not sent: ${e.message}';
    }
    final builder = MqttClientPayloadBuilder()..addUTF8String(msg.encode());
    client.publishMessage(groupInboxTopic(s.group), MqttQos.atLeastOnce, builder.payload!);
    // Show it straight away; the broker's echo is de-duplicated by id.
    _seen.add(msg.id);
    _addToFeed(FeedItem(msg, DateTime.now(), mine: true));
    _notify();
    return null;
  }

  Future<void> disconnect() async {
    await _updates?.cancel();
    _updates = null;
    _client?.autoReconnect = false;
    _client?.disconnect();
    _client = null;
    robots.clear();
    if (state != LinkState.disconnected) {
      state = LinkState.disconnected;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    disconnect();
    super.dispose();
  }
}
