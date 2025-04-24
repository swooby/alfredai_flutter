import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logging/logging.dart';

import 'my_home_page.dart';
import 'my_view_model.dart';
import 'my_view_model_provider.dart';

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
  await dotenv.load();
  WidgetsFlutterBinding.ensureInitialized();
  final vm = await MyViewModel.create();
  runApp(
    MyViewModelProvider(
      viewModel: vm,
      child: MyApp(),
    ),
  );
  _log.info('-main()');
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
