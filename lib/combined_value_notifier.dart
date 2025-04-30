import 'package:flutter/foundation.dart';

/// From https://stackoverflow.com/a/79557033/252308
class CombinedValueNotifier<T> extends ChangeNotifier
    implements ValueListenable<T> {
  final List<Listenable> _sources;
  final T Function() _combine;

  CombinedValueNotifier(this._sources, this._combine) {
    for (final s in _sources) {
      s.addListener(notifyListeners);
    }
  }

  @override
  T get value => _combine();

  @override
  void dispose() {
    for (final s in _sources) {
      s.removeListener(notifyListeners);
    }
    super.dispose();
  }
}
