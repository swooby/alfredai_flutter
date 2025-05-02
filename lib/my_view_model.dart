import 'dart:math';

import 'package:alfredai_flutter/push_to_talk_preferences.dart';
import 'package:alfredai_flutter/push_to_talk_widget.dart';
import 'package:alfredai_flutter/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logging/logging.dart';
import 'package:openai_realtime_dart/openai_realtime_dart.dart';
import 'package:permission_handler/permission_handler.dart';

final _log = Logger('my_view_model');

enum ViewModelError {
  /// error == "none" can be thought of as an alias for "success"
  none,
  isNotConfigured,
  missingRequiredPermissions,
}

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

enum ConversationItemType {
  local,
  remote,
  function,
}

class ConversationItem {
  final String? id;
  final String? responseId;
  final ConversationItemType type;
  final String initialText;
  final DateTime timestamp;
  bool incomplete;
  final String functionCallId;
  final String functionName;
  String functionArguments;
  String functionOutput;

  /// A mutable, listenable copy of the text.
  final ValueNotifier<String> text;

  ConversationItem({
    required this.id,
    this.responseId,
    required this.type,
    required this.initialText,
    DateTime? timestamp,
    this.incomplete = false,
    this.functionCallId = '',
    this.functionName = '',
    this.functionArguments = '',
    this.functionOutput = '',
  })  : timestamp = timestamp ?? DateTime.now(),
        text = ValueNotifier<String>(initialText);

  @override
  String toString() {
    return 'ConversationItem('
        'id: ${quote(id)}, '
        'type: $type, '
        'timestamp: $timestamp, '
        'incomplete: $incomplete, '
        'text: ${quote(text.value)}, '
        'functionCallId: ${quote(functionCallId)}, '
        'functionName: ${quote(functionName)}, '
        'functionArguments: ${quote(functionArguments)}, '
        'functionOutput: ${quote(functionOutput)}'
        ')';
  }
}

class ConversationListNotifier extends ValueNotifier<List<ConversationItem>> {
  ConversationListNotifier() : super([]);

  /// Adds an item and notifies listeners.
  void addItem(ConversationItem item) {
    value.add(item);
    notifyListeners();
  }

  /// Clears all items and notifies listeners.
  void clear() {
    value.clear();
    notifyListeners();
  }
}

class MyViewModel {
  //region constants
  static final bool _debugToastVerbose = kDebugMode && false;
  static final bool _debugForceNotConfigured = kDebugMode && false;
  static final bool _debugForceDoNotAutoConnect = kDebugMode && false;
  static final int _debugSimulateSessionExpiredMillis = (kDebugMode && false) ? 20_000 : 0;
  static final int _debugConnectDelayMillis = (kDebugMode && false) ? 10_000 : 0;
  static final bool _debugLogConversation = kDebugMode && true;
  static final int _debugFakeConversationCount = (kDebugMode && false) ? 20 : 0;
  //endregion constants

  final conversationItems = ConversationListNotifier();

  List<ConversationItem> generateRandomConversationItems({required int count}) {
    if (count <= 0) {
      throw ArgumentError('count must be greater than 0');
    }

    final random = Random();
    final items = <ConversationItem>[];

    String generateRandomSentence(int maxWords) {
      if (maxWords <= 0) {
        throw ArgumentError('maxWords must be greater than 0');
      }

      final wordCount = random.nextInt(maxWords) + 1; // [1..maxWords]
      final words = List<String>.generate(wordCount, (_) {
        final length = random.nextInt(10) + 1; // [1..10]
        return String.fromCharCodes(
          List<int>.generate(length, (_) => random.nextInt(26) + 97),
        );
      });

      final sentence = words.join(' ');
      return '${sentence[0].toUpperCase()}${sentence.substring(1)}.';
    }

    for (var i = 0; i < count; i++) {
      // pick a random maxWords in [5..30]
      final maxWords = random.nextInt(30 - 5 + 1) + 5;
      items.add(ConversationItem(
        id: '$i',
        type: ConversationItemType
            .values[random.nextInt(ConversationItemType.values.length)],
        initialText: generateRandomSentence(maxWords),
      ));
    }

    return items;
  }

  List<ConversationItem> conversationItemsInit() {
    return (_debugFakeConversationCount > 0) ?
    generateRandomConversationItems(count: _debugFakeConversationCount)
        : [];
  }

  void conversationItemsClear() {
    _log.info('conversationItemsClear()');
    conversationItems.clear();
  }

  void conversationItemsAdd(ConversationItem item) {
    _log.info('conversationItemsAdd($item)');
    conversationItems.addItem(item);
  }

  MyViewModel._(
      this._prefs,
      this._connectionState,
      this._connectionStateProvider,
      )
      : _autoConnectNotifier = ValueNotifier<bool>(_prefs.autoConnect),
        _apiKeyNotifier = ValueNotifier<String>(_prefs.apiKey),
        _modelNotifier = ValueNotifier<RealtimeModel>(_prefs.model),
        _instructionsNotifier = ValueNotifier<String>(_prefs.instructions),
        _voiceNotifier = ValueNotifier<Voice>(_prefs.voice),
        _inputAudioTranscriptionNotifier = ValueNotifier<InputAudioTranscriptionConfig?>(_prefs.inputAudioTranscription),
        _temperatureNotifier = ValueNotifier<double>(_prefs.temperature),
        _maxResponseOutputTokensNotifier = ValueNotifier<int?>(_prefs.maxResponseOutputTokens) {
    conversationItems.value = conversationItemsInit();
  }

  static Future<MyViewModel> create() async {
    final prefs = await PushToTalkPreferences.init();
    final connectionState = ValueNotifier(ConnectionState.disconnected);
    final provider = ConnectionStateProvider(
      connectionStateNotifier: connectionState,
    );
    final viewModel = MyViewModel._(prefs, connectionState, provider);
    //await viewModel.initialize();
    return viewModel;
  }

  Future<void> initialize() async {
    _log.info('+initialize()');

    await _initMic();

    _updateIsConfiguredState();

    await _updatePermissionsState();

    _log.info('-initialize()');
  }

  void dispose() {
    _log.info('+dispose()');

    _connectionState.dispose();
    disconnect();
    onDisconnecting();
    onDisconnected();

    _connectionStateProvider.dispose();
    _autoConnectNotifier.dispose();
    _apiKeyNotifier.dispose();
    _modelNotifier.dispose();
    _instructionsNotifier.dispose();
    _voiceNotifier.dispose();
    _inputAudioTranscriptionNotifier.dispose();
    _temperatureNotifier.dispose();
    _maxResponseOutputTokensNotifier.dispose();

    _log.info('-dispose()');
  }

  //region permissions

  final _requiredPermissions = List<Permission>.unmodifiable([
    Permission.microphone,
  ]);

  Future<List<Permission>> get missingRequiredPermissions async {
    _log.info('+get missingRequiredPermissions');
    List<Permission> missingPermissions = [];
    for (final permission in _requiredPermissions) {
      if (!await permission.isGranted) {
        missingPermissions.add(permission);
      }
    }
    _log.info('get missingRequiredPermissions: missingPermissions=$missingPermissions');
    _log.info('-get missingRequiredPermissions');
    return List.unmodifiable(missingPermissions);
  }

  Future<void> requestMissingRequiredPermissions() async {
    try {
      _log.info('+requestMissingRequiredPermissions()');
      for (final permission in await missingRequiredPermissions) {
        _log.info('requestMissingRequiredPermissions: Requesting missing required permission: $permission');
        await permission.request();
      }
      await _updatePermissionsState();
    } finally {
      _log.info('-requestMissingRequiredPermissions()');
    }
  }

  final ValueNotifier<bool> _hasAllRequiredPermissions = ValueNotifier(false);
  ValueListenable<bool> get hasAllRequiredPermissions => _hasAllRequiredPermissions;

  Future<void> _updatePermissionsState() async {
    try {
      _log.info('+_updatePermissionsState()');
      _hasAllRequiredPermissions.value = (await missingRequiredPermissions).isEmpty;
      _maybeAutoConnect();
    } finally {
      _log.info('-_updatePermissionsState()');
    }
  }

  //endregion permissions

  //region preferences

  final PushToTalkPreferences _prefs;

  final ValueNotifier<bool> _autoConnectNotifier;
  ValueListenable<bool> get autoConnect => _autoConnectNotifier;
  void _setAutoConnect(bool value) {
    _prefs.autoConnect = value;
    _autoConnectNotifier.value = value;
  }

  final ValueNotifier<String> _apiKeyNotifier;
  ValueListenable<String> get apiKey => _apiKeyNotifier;
  void _setApiKey(String value) {
    _prefs.apiKey = value;
    _apiKeyNotifier.value = value;
  }

  final ValueNotifier<RealtimeModel> _modelNotifier;
  ValueListenable<RealtimeModel> get model => _modelNotifier;
  void _setModel(RealtimeModel value) {
    _prefs.model = value;
    _modelNotifier.value = value;
  }

  final ValueNotifier<String> _instructionsNotifier;
  ValueListenable<String> get instructions => _instructionsNotifier;
  void _setInstructions(String value) {
    _prefs.instructions = value;
    _instructionsNotifier.value = value;
  }

  final ValueNotifier<Voice> _voiceNotifier;
  ValueListenable<Voice> get voice => _voiceNotifier;
  void _setVoice(Voice value) {
    _prefs.voice = value;
    _voiceNotifier.value = value;
  }

  final ValueNotifier<InputAudioTranscriptionConfig?> _inputAudioTranscriptionNotifier;
  ValueListenable<InputAudioTranscriptionConfig?> get inputAudioTranscription => _inputAudioTranscriptionNotifier;
  void _setInputAudioTranscription(InputAudioTranscriptionConfig? value) {
    _prefs.inputAudioTranscription = value;
    _inputAudioTranscriptionNotifier.value = value;
  }

  final ValueNotifier<double> _temperatureNotifier;
  ValueListenable<double> get temperature => _temperatureNotifier;
  void _setTemperature(double value) {
    _prefs.temperature = value;
    _temperatureNotifier.value = value;
  }

  final ValueNotifier<int?> _maxResponseOutputTokensNotifier;
  ValueListenable<int?> get maxResponseOutputTokens => _maxResponseOutputTokensNotifier;
  void _setMaxResponseOutputTokens(int? value) {
    _prefs.maxResponseOutputTokens = value;
    _maxResponseOutputTokensNotifier.value = value;
  }

  final ValueNotifier<bool> _isConfigured = ValueNotifier(false);
  ValueListenable<bool> get isConfigured => _isConfigured;
  void _updateIsConfiguredState() {
    _log.info('+_updateIsConfiguredState()');
    final isConfigured = !_debugForceNotConfigured && apiKey.value.isNotEmpty;
    _log.info('_updateIsConfiguredState: isConfigured=$isConfigured');
    _isConfigured.value = isConfigured;
    _log.info('-_updateIsConfiguredState()');
  }

  /*
  SessionConfig get sessionConfig {
    return SessionConfig(
      instructions: instructions,
      voice: voice,
      inputAudioTranscription: inputAudioTranscription,
      temperature: temperature,
      turnDetection: PushToTalkPreferences.turnDetectionDefault,
      maxResponseOutputTokens: PushToTalkPreferences.getMaxResponseOutputTokens(maxResponseOutputTokens),
    );
  }
  */

  void updatePreferences(
      bool autoConnect,
      String apiKey,
      RealtimeModel model,
      String instructions,
      Voice voice,
      InputAudioTranscriptionConfig? inputAudioTranscription,
      double temperature,
      int maxResponseOutputTokens
      ) async {
    try {
      _log.info('+updatePreferences()');

      _setAutoConnect(autoConnect);

      bool reinitialize = _realtimeClient == null;
      bool updateSession = false;
      bool reconnectSession = false;

      if (apiKey != this.apiKey.value) {
        reinitialize = true;
        _setApiKey(apiKey);
      }

      if (model != this.model.value) {
        reinitialize = true;
        _setModel(model);
      }

      if (instructions != this.instructions.value) {
        updateSession = true;
        _setInstructions(instructions);
      }

      /**
       * https://platform.openai.com/docs/api-reference/realtime-client-events/session
       * "session.update
       * ... The client may send this event at any time to update the session configuration,
       * and any field may be updated at any time, except for "voice"."
       */
      if (voice != this.voice.value) {
        reconnectSession = true;
        _setVoice(voice);
      }

      if (inputAudioTranscription != this.inputAudioTranscription.value) {
        updateSession = true;
        _setInputAudioTranscription(inputAudioTranscription);
      }

      if (temperature != this.temperature.value) {
        updateSession = true;
        _setTemperature(temperature);
      }

      if (maxResponseOutputTokens != this.maxResponseOutputTokens.value) {
        updateSession = true;
        _setMaxResponseOutputTokens(maxResponseOutputTokens);
      }

      _updateIsConfiguredState();

      if (reinitialize) {
        _tryInitRealtimeClient();
      } else {
        if (isConnectingOrConnected.value) {
          if (isConnecting.value || reconnectSession) {
            await reconnect();
          } else {
            if (isConnected.value && updateSession) {
              _realtimeClient?.updateSession(
                instructions: instructions,
                voice: voice,
                inputAudioTranscription: inputAudioTranscription,
                temperature: temperature,
                turnDetection: PushToTalkPreferences.turnDetectionDefault,
                maxResponseOutputTokens: PushToTalkPreferences
                    .getMaxResponseOutputTokens(maxResponseOutputTokens),
              );
            }
          }
        }
      }
    } finally {
      _log.info('-updatePreferences()');
    }
  }

  //endregion preferences

  //region connection state

  void setConnectionState(ConnectionState state) {
    _log.info('setConnectionState($state)');
    _connectionState.value = state;
  }

  final ValueNotifier<ConnectionState> _connectionState;
  final ConnectionStateProvider _connectionStateProvider;

  ValueListenable<ConnectionState> get connectionState =>
      _connectionStateProvider.connectionState;
  ValueListenable<bool> get isConnecting =>
      _connectionStateProvider.isConnecting;
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

  RealtimeClient? _realtimeClient;

  Future<ViewModelError> _tryInitRealtimeClient() async {
    try {
      _log.info('+_tryInitRealtimeClient()');

      if (!isConfigured.value) {
        _log.warning(
            '_tryInitRealtimeClient: Not configured; not initializing realtimeClient');
        return ViewModelError.isNotConfigured;
      }

      if (!hasAllRequiredPermissions.value) {
        _log.warning(
            '_tryInitRealtimeClient: Not all permissions granted; not initializing realtimeClient');
        return ViewModelError.missingRequiredPermissions;
      }

      _disconnectInternal();

      _realtimeClient = RealtimeClient(
        transportType: RealtimeTransportType.webrtc,
        apiKey: apiKey.value,
        debug: true,
      );
      await _realtimeClient?.updateSession(
      );
      _realtimeClient?.on(RealtimeEventType.all, (event) async {
        switch (event.type) {
          case RealtimeEventType.sessionCreated:
            _log.fine('sessionCreated: $event');
            // Whether it is intentional or a bug, some settings like...
            // * `input_audio_transcription`
            // * `turn_detection`
            // ...don't take affect when creating a session:
            // https://platform.openai.com/docs/api-reference/realtime-sessions/create
            // https://platform.openai.com/docs/api-reference/realtime-sessions/create#realtime-sessions-create-input_audio_transcription
            // Proof is to enable okhttp logging and see a non-default value getting sent
            // in the Request but the default value coming back in the Response. :/
            // Forum post explaining:
            // https://community.openai.com/t/issues-with-transcription-in-realtime-model-using-webrtc/1068762/4
            //
            // So, this code re-applies the sessionConfig after the session and data channel are open.
            // There is a mention that specifying `model` during a session.update causes issues.
            //
            // https://platform.openai.com/docs/api-reference/realtime-client-events/session/update
            //
            await _realtimeClient?.updateSession();
            break;
          case RealtimeEventType.sessionUpdated:
            _log.fine('sessionUpdated: $event');
            if (_connectionState.value == ConnectionState.connecting) {
              _log.info('_connectionState: CONNECTING -> CONNECTED!');
              setConnectionState(ConnectionState.connected);
            }
            break;
          default:
          // ignore
            break;
        }
      });

      _log.info(
          '_tryInitRealtimeClient: realtimeClient initialized successfully');
      return ViewModelError.none;
    } finally {
      _log.info('-_tryInitRealtimeClient()');
    }
  }

  void _maybeAutoConnect() async {
    try {
      _log.info('+_maybeAutoConnect()');
      if (!hasAllRequiredPermissions.value) {
        _log.warning(
            '_maybeAutoConnect: Not all permissions granted; not auto-connecting');
        return;
      }
      if (_debugForceDoNotAutoConnect) {
        _log.warning(
            '_maybeAutoConnect: Auto-connect is [debug] forced disabled');
        return;
      }
      if (!autoConnect.value) {
        _log.info('_maybeAutoConnect: Auto-connect is disabled');
        return;
      }
      if (_isDisconnectManual) {
        _log.info(
            '_maybeAutoConnect: Manually disconnected; Ignore auto-connect');
      }
      await connect();
    } finally {
      _log.info('-_maybeAutoConnect()');
    }
  }

  Future<void> connect() async {
    try {
      _log.info('+connect()');
      if (isConnectingOrConnected.value) {
        _log.info('connect: Already connecting or connected');
        return;
      }

      if (_realtimeClient == null && (await _tryInitRealtimeClient() != ViewModelError.none)) {
        _log.info('connect: _tryInitRealtimeClient() return false; not connecting');
        return;
      }

      _isDisconnectManual = false;

      _log.info('connect: Attempting to connect...');
      if (await _realtimeClient!.connect(
        getMicrophoneCallback: () async {
          if (!_micReady) await _initMic();
          return _micStream;
        },
      )) {
        setConnectionState(ConnectionState.connecting);
      }
    } finally {
      _log.info('-connect()');
    }
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

      _disconnectInternal(isClient: isClient);
    } finally {
      _log.info('-disconnect(isManual: $isManual, isClient: $isClient)');
    }
  }

  void _disconnectInternal({bool isClient = false}) {
    try {
      _log.info('+_disconnectInternal(isClient: $isClient)');
      setConnectionState(ConnectionState.disconnecting);
      if (isClient) {
        _log.info('_disconnectInternal: Disconnect request **FROM RealtimeClient**; Intentionally **NOT** calling `realtimeClient.disconnect()`');
      } else {
        final realtimeClient = _realtimeClient;
        if (realtimeClient != null) {
          _log.info('_disconnectInternal: Disconnecting RealtimeClient...');
          realtimeClient.disconnect();
          _realtimeClient = null;
          _log.info('_disconnectInternal: ...RealtimeClient disconnected');
        }
      }
      setConnectionState(ConnectionState.disconnected);
    } finally {
      _log.info('-_disconnectInternal(isClient: $isClient)');
    }
  }

  Future<void> reconnect() async {
    _log.info('+reconnect()');
    disconnect();
    await connect();
    _log.info('-reconnect()');
  }

  void onDisconnecting() {
    _log.info('+onDisconnecting()');
    _log.info('-onDisconnecting()');
  }

  void onDisconnected() {
    _log.info('+onDisconnected()');
    _log.info('-onDisconnected()');
  }

  //endregion connection state

  //region PushToTalk

  final pttState = ValueNotifier<PttState>(PttState.disabled);

  bool isCancelingResponse = false;

  void startPushToTalk() async {
    _log.info('startPushToTalk()');
    await pushToTalk(true);
    pttState.value = PttState.pressed;
  }

  void stopPushToTalk() async {
    _log.info('stopPushToTalk()');
    await pushToTalk(false);
    pttState.value = PttState.idle;
  }

  Future<void> pushToTalk(bool enable) async {
    _log.info('pushToTalk($enable)');
    if (enable) {
      await _realtimeClient?.send(
        RealtimeEvent.inputAudioBufferClear(
          eventId: RealtimeUtils.generateId(),
        ),
      );
      _enableMic(true);
    } else {
      _enableMic(false);
      await _realtimeClient?.send(
        RealtimeEvent.inputAudioBufferCommit(
          eventId: RealtimeUtils.generateId(),
        ),
      );
      await _realtimeClient?.send(
        RealtimeEvent.responseCreate(eventId: RealtimeUtils.generateId()),
      );
    }
  }

  void _enableMic(bool enable) {
    _log.info('_enableMic($enable)');
    _micStream.getAudioTracks().forEach((track) {
      //_log.info('track: $track');
      final settings = track.getSettings();
      //_log.info('track settings: $settings');
      if (settings['kind'] == 'audioinput') {
        _log.info('_enableMic: Setting track $track enabled=$enable');
        track.enabled = enable;
      }
    });
  }

  late MediaStream _micStream;
  bool _micReady = false;

  // 2. One-shot initialization
  Future<void> _initMic() async {
    if (_micReady) return;

    final constraints = <String, dynamic>{
      'audio': true,
      'video': false,
      'mandatory': {
        'minSampleRate': 16000, // Minimum sample rate (Hz)
        'maxSampleRate': 48000, // Maximum sample rate (Hz)
        'minBitrate': 32000, // Minimum bitrate (bps)
        'maxBitrate': 128000, // Maximum bitrate (bps)
      },
      'optional': [
        {
          // Enhances voice quality
          'googHighpassFilter': true,
          'googNoiseSuppression': true,
          'googEchoCancellation': true,
          'googAutoGainControl': true,
        },
      ],
    };
    _micStream = await navigator.mediaDevices.getUserMedia(constraints);
    _enableMic(false);
    _micReady = true;
  }

  //endregion PushToTalk

  Future<void> sendText(String text) async {
    _log.info('sendText(${quote(text)})');
    _realtimeClient?.send(
      RealtimeEvent.conversationItemCreate(
          eventId: RealtimeUtils.generateId(),
          item: Item.message(
              id: RealtimeUtils.generateId(),
              type: ItemType.message,
              role: ItemRole.user,
              content: List.unmodifiable([
                ContentPart.inputText(text: text)
              ]))
      )
    );
    _realtimeClient?.send(
      RealtimeEvent.responseCreate(eventId: RealtimeUtils.generateId())
    );
  }
}
