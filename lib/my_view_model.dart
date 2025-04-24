import 'package:alfredai_flutter/push_to_talk_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:openai_realtime_dart/openai_realtime_dart.dart';
import 'package:permission_handler/permission_handler.dart';

final _log = Logger('my_view_model');

enum ConnectionState {
  connecting,
  connected,
  disconnecting,
  disconnected,
}

class ConnectionStateProvider {
  final ValueNotifier<ConnectionState> _state;
  final ValueNotifier<bool> _isConnecting = ValueNotifier(false);
  final ValueNotifier<bool> _isConnected = ValueNotifier(false);
  final ValueNotifier<bool> _isConnectingOrConnected = ValueNotifier(false);
  final ValueNotifier<bool> _isDisconnecting = ValueNotifier(false);
  final ValueNotifier<bool> _isDisconnected = ValueNotifier(true);
  final ValueNotifier<bool> _isDisconnectingOrDisconnected = ValueNotifier(true);

  ConnectionStateProvider({
    ValueNotifier<ConnectionState>? connectionStateNotifier,
  }) : _state = connectionStateNotifier ??
      ValueNotifier(ConnectionState.disconnected) {
    _state.addListener(_syncDerived);
    _syncDerived();
  }

  void _syncDerived() {
    final s = _state.value;
    _isConnecting.value                  = (s == ConnectionState.connecting);
    _isConnected.value                   = (s == ConnectionState.connected);
    _isConnectingOrConnected.value       = (_isConnecting.value || _isConnected.value);
    _isDisconnecting.value               = (s == ConnectionState.disconnecting);
    _isDisconnected.value                = (s == ConnectionState.disconnected);
    _isDisconnectingOrDisconnected.value = (_isDisconnecting.value || _isDisconnected.value);
  }

  ValueListenable<ConnectionState> get connectionState    => _state;
  ValueListenable<bool> get isConnecting                  => _isConnecting;
  ValueListenable<bool> get isConnected                   => _isConnected;
  ValueListenable<bool> get isConnectingOrConnected       => _isConnectingOrConnected;
  ValueListenable<bool> get isDisconnecting               => _isDisconnecting;
  ValueListenable<bool> get isDisconnected                => _isDisconnected;
  ValueListenable<bool> get isDisconnectingOrDisconnected => _isDisconnectingOrDisconnected;

  void dispose() {
    _state.removeListener(_syncDerived);
    _state.dispose();
    _isConnecting.dispose();
    _isConnected.dispose();
    _isConnectingOrConnected.dispose();
    _isDisconnecting.dispose();
    _isDisconnected.dispose();
    _isDisconnectingOrDisconnected.dispose();
  }
}

class MyViewModel {
  //region constants
  static final bool debugToastVerbose = kDebugMode && false;
  static final bool debugForceNotConfigured = kDebugMode && false;
  static final bool debugForceDoNotAutoConnect = kDebugMode && false;
  static final int debugSimulateSessionExpiredMillis = (kDebugMode && false) ? 20_000 : 0;
  static final int debugConnectDelayMillis = (kDebugMode && false) ? 10_000 : 0;
  static final bool debugLogConversation = kDebugMode && true;
  static final int debugFakeConversationCount = (kDebugMode && false) ? 20 : 0;
  //endregion constants

  final PushToTalkPreferences _prefs;
  final ValueNotifier<ConnectionState> _connectionState;
  final ConnectionStateProvider _connectionStateProvider;

  MyViewModel._(
      this._prefs,
      this._connectionState,
      this._connectionStateProvider,
      );

  static Future<MyViewModel> create() async {
    final prefs = await PushToTalkPreferences.init();
    final connectionState = ValueNotifier(ConnectionState.disconnected);
    final provider = ConnectionStateProvider(
      connectionStateNotifier: connectionState,
    );
    return MyViewModel._(prefs, connectionState, provider);
  }

  //region permissions

  //endregion permissions

  //region preferences

  bool get autoConnect => _prefs.autoConnect;
  set autoConnect(bool value) => _prefs.autoConnect = value;

  Future<String?> getApiKey() async => await _prefs.getApiKey();
  Future<void> setApiKey(String? value) async => await _prefs.setApiKey(value);

  RealtimeModel get model => _prefs.model;
  set model(RealtimeModel value) => _prefs.model = value;

  String get instructions => _prefs.instructions;
  set instructions(String value) => _prefs.instructions = value;

  Voice get voice => _prefs.voice;
  set voice(Voice value) => _prefs.voice = value;

  InputAudioTranscriptionConfig? get inputAudioTranscription => _prefs.inputAudioTranscription;
  set inputAudioTranscription(InputAudioTranscriptionConfig? value) => _prefs.inputAudioTranscription = value;

  double get temperature => _prefs.temperature;
  set temperature(double value) => _prefs.temperature = value;

  int? get maxResponseOutputTokens => _prefs.maxResponseOutputTokens;
  set maxResponseOutputTokens(int? value) => _prefs.maxResponseOutputTokens = value;

  Future<bool> checkIsConfigured() async {
    return !debugForceNotConfigured && await getApiKey() != null;
  }

  final ValueNotifier<bool> _isConfigured = ValueNotifier(false);
  ValueListenable<bool> get isConfigured => _isConfigured;
  void updateIsConfigured() async {
    _isConfigured.value = await checkIsConfigured();
  }

  //endregion preferences

  //region connection state

  ValueListenable<ConnectionState> get connectionState =>
      _connectionStateProvider.connectionState;
  ValueListenable<bool> get isConnected =>
      _connectionStateProvider.isConnected;
  ValueListenable<bool> get isConnectingOrConnected =>
      _connectionStateProvider.isConnectingOrConnected;
  ValueListenable<bool> get isDisconnecting =>
      _connectionStateProvider.isDisconnecting;
  ValueListenable<bool> get isDisconnected =>
      _connectionStateProvider.isDisconnected;
  ValueListenable<bool> get isDisconnectingOrDisconnected =>
      _connectionStateProvider.isDisconnectingOrDisconnected;

  bool _isDisconnectManual = false;

  RealtimeClient? realtimeClient;

  Future<bool> _tryInitClient() async {
    _log.info('tryInitClient()');
    if (!isConfigured.value) {
      _log.warning('tryInitClient: Not configured; not initializing realtimeClient');
      return false;
    }
    _log.info('tryInitClient: realtimeClient initialized successfully');
    return true;
  }

  void maybeAutoConnect() async {
    _log.info('maybeAutoConnect()');
    if (debugForceDoNotAutoConnect) {
      _log.warning('maybeAutoConnect: Auto-connect is [debug] forced disabled');
      return;
    }
    if (!autoConnect) {
      _log.info('maybeAutoConnect: Auto-connect is disabled');
      return;
    }
    if (_isDisconnectManual) {
      _log.info('maybeAutoConnect: Manually disconnected; Ignore auto-connect');
    }
    await connect();
  }

  void disconnect({bool isManual = false}) {
    _disconnect(isManual: isManual, isClient: false);
  }

  void _disconnect({bool isManual = false, bool isClient = false }) {
    try {
      _log.info('+disconnect(isManual: $isManual, isClient: $isClient)');

      if (_connectionState.value == ConnectionState.disconnected) {
        _log.info('disconnect: Already disconnected');
        return;
      }

      if (isManual) {
        _isDisconnectManual = true;
      }

      disconnectInternal(isClient: isClient);
    } finally {
      _log.info('-disconnect(isManual: $isManual, isClient: $isClient)');
    }
  }

  void disconnectInternal({bool isClient = false}) {
    try {
      _log.info('+disconnectInternal(isClient: $isClient)');
      _connectionState.value = ConnectionState.disconnecting;
      if (isClient) {
        _log.info('disconnectInternal: Disconnect request **FROM RealtimeClient**; Intentionally **NOT** calling `realtimeClient.disconnect()`');
      } else {
      }
      _connectionState.value = ConnectionState.disconnected;
    } finally {
      _log.info('-disconnectInternal(isClient: $isClient)');
    }
  }

  //endregion connection state
}
