import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'my_home_page.dart';
import 'my_view_model.dart';

final _debug = kDebugMode || true;
final _log = Logger('main');

void _loggingInit() {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    if (_debug && record.level >= Logger.root.level) {
      // ignore: avoid_print
      print('${record.loggerName}: ${record.message} ${record.error ?? ""}');
    }
  });
}

void main() async {
  _loggingInit();
  _log.info('+main()');
  final vm = await MyViewModel.create();
  runApp(MyApp(viewModel: vm));
  _log.info('-main()');
}

class MyApp extends StatelessWidget {
  final MyViewModel viewModel;
  const MyApp({super.key, required this.viewModel});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PushToTalk Flutter',
      theme: ThemeData.dark(),
      home: const MyHomePage(title: 'PushToTalk'),
    );
  }
}
