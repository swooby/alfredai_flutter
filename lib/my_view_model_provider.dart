import 'package:flutter/widgets.dart';

import 'my_view_model.dart';

class MyViewModelProvider extends InheritedWidget {
  final MyViewModel viewModel;

  const MyViewModelProvider({
    super.key,
    required this.viewModel,
    required super.child,
  });

  static MyViewModel of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<MyViewModelProvider>();
    assert(provider != null, 'MyViewModelProvider not found in widget tree');
    return provider!.viewModel;
  }

  @override
  bool updateShouldNotify(MyViewModelProvider oldWidget) =>
      viewModel != oldWidget.viewModel;
}
