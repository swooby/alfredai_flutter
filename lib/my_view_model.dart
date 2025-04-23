import 'package:alfredai_flutter/push_to_talk_preferences.dart';
import 'package:flutter/foundation.dart';

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
  final PushToTalkPreferences _prefs;

  MyViewModel._(this._prefs);

  static Future<MyViewModel> create() async {
    final prefs = await PushToTalkPreferences.init();
    return MyViewModel._(prefs);
  }
}
