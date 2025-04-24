import 'package:flutter/material.dart';

import 'package:logging/logging.dart';

import 'my_view_model.dart' as myvm;
import 'my_view_model_provider.dart';

final _log = Logger('my_home_page');

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late myvm.MyViewModel _viewModel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewModel = MyViewModelProvider.of(context);
  }

  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          ValueListenableBuilder<myvm.ConnectionState>(
            valueListenable: _viewModel.connectionState,
            builder: (context, connectionState, child) {
              return Switch(
                value: _viewModel.isConnectingOrConnected.value,
                onChanged: (bool newValue) async {
                  if (newValue) {
                    await _viewModel.connect();
                  } else {
                    _viewModel.disconnect();
                  }
                },
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () {
              // TODO: handle settings press
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
