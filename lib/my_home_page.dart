import 'package:alfredai_flutter/push_to_talk_preferences.dart';
import 'package:alfredai_flutter/push_to_talk_widget.dart';
import 'package:flutter/material.dart';

import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';

import 'combined_value_notifier.dart';
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

  bool get isConfigured => _viewModel.isConfigured.value;

  late CombinedValueNotifier _pushToTalkNotifier;

  void _navigateTo({
    required BuildContext context,
    required bool replace,
    required Widget Function(BuildContext prefsContext) buildWidget,
  }) {
    final navigator = Navigator.of(context);
    final route = MaterialPageRoute(builder: (context) => buildWidget(context));
    if (replace) {
      navigator.pushReplacement(route);
    } else {
      navigator.push(route);
    }
  }

  void _navigateToPreferences({
    required bool replace,
    required void Function(BuildContext prefsContext) onSave,
  }) {
    _navigateTo(
      context: context,
      replace: replace,
      buildWidget: (prefsContext) => PushToTalkPreferencesScreen(
        title: 'Preferences',
        onSaveSuccess: () => onSave(prefsContext),
      ),
    );
 }

  @override
  void didChangeDependencies() {
    _log.info('+didChangeDependencies()');
    super.didChangeDependencies();

    _viewModel = MyViewModelProvider.of(context);

    _pushToTalkNotifier = CombinedValueNotifier(
      [_viewModel.connectionState, _viewModel.pttState],
          () => (
      connectionState: _viewModel.connectionState.value,
      pttState: _viewModel.pttState.value,
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _log.info(' +postFrameCallback()');
      await _viewModel.initialize();
      if (!isConfigured) {
        _navigateToPreferences(
          replace: true,
          onSave: (prefsContext) {
            _navigateTo(
              context: prefsContext,
              replace: true,
              buildWidget: (_) => MyHomePage(title: widget.title),
            );
          },
        );
      }
      await _maybeShowMissingRequiredPermissionsDialog();
      _log.info(' -postFrameCallback()');
    });
    _log.info('-didChangeDependencies()');
  }

  Future<void> _maybeShowMissingRequiredPermissionsDialog() async {
    final missingRequiredPermissions = await _viewModel.missingRequiredPermissions;
    if (missingRequiredPermissions.isNotEmpty) {
      _showMissingRequiredPermissionsDialog(missingRequiredPermissions);
    }
  }

  void _showMissingRequiredPermissionsDialog(List<Permission> missingRequiredPermissions) {
    String text = 'Please grant these required permissions:\n';
    for (var permission in missingRequiredPermissions) {
      text += '\n- $permission';
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text('Missing Required Permission(s)'),
        content: Text(text),
        actions: [
          TextButton(
            child: Text('Exit'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            child: Text('OK'),
            onPressed: () async {
              Navigator.of(context).pop();
              await _viewModel.requestMissingRequiredPermissions();
            },
          ),
        ],
      ),
    );
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
              _navigateToPreferences(
                replace: false,
                onSave: (prefsContext) {
                  Navigator.of(prefsContext).pop();
                }
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: ConversationSection(
                  conversationItems: _viewModel.conversationItems,
                  isConnected: _viewModel.isConnected.value,
                  onClearAll: () {
                    _viewModel.conversationItems.clear();
                  },
                  onSendText: (text) async {
                    await _viewModel.sendText(text);
                  }
              ),
            ),
            ValueListenableBuilder(
              valueListenable: _pushToTalkNotifier,
              builder: (context, pushToTalkNotifier, child) {
                return PushToTalkWidget(
                  pttState: _viewModel.pttState.value,
                  isConnectingOrConnected:
                  _viewModel.isConnectingOrConnected.value,
                  isConnected: _viewModel.isConnected.value,
                  isCancelingResponse:
                  _viewModel.isCancelingResponse,
                  onPushToTalkStart: _viewModel.startPushToTalk,
                  onPushToTalkStop: _viewModel.stopPushToTalk,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class ConversationSection extends StatefulWidget {
  final List<myvm.ConversationItem> conversationItems;
  final bool isConnected;
  final VoidCallback onClearAll;
  final Future<void> Function(String) onSendText;

  const ConversationSection({
    super.key,
    required this.conversationItems,
    required this.isConnected,
    required this.onClearAll,
    required this.onSendText,
  });

  @override
  _ConversationSectionState createState() => _ConversationSectionState();
}

class _ConversationSectionState extends State<ConversationSection> {
  final _scrollController = ScrollController();
  String _inputText = '';

  @override
  void didUpdateWidget(covariant ConversationSection old) {
    super.didUpdateWidget(old);
    // auto‑scroll to bottom when new items arrive
    if (widget.conversationItems.length != old.conversationItems.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  void _sendInput() {
    if (_inputText.trim().isEmpty) return;
    widget.onSendText(_inputText.trim());
    setState(() => _inputText = '');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row with title and clear button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text("Conversation:"),
              ),
              IconButton(
                icon: const Icon(Icons.clear_all),
                onPressed: widget.onClearAll,
              ),
            ],
          ),

          // Empty state or list
          Flexible(
            fit: FlexFit.loose,
            child: widget.conversationItems.isEmpty
                ? Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: const Text(
                "No conversation items",
                textAlign: TextAlign.center,
              ),
            )
                : Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(8),
                itemCount: widget.conversationItems.length,
                itemBuilder: (context, index) {
                  final item = widget.conversationItems[index];
                  // determine alignment and icon
                  final isLocal = item.type == myvm.ConversationItemType.local;
                  final avatarIcon = isLocal
                      ? Icons.person
                      : Icons.memory;
                  final rowAlign = isLocal
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.end;
                  final textAlign =
                  isLocal ? TextAlign.start : TextAlign.end;
                  final bgColor = item.incomplete
                      ? Colors.yellow.shade100
                      : Colors.grey.shade200;
                  return Row(
                    mainAxisAlignment: rowAlign,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isLocal) ...[
                        Icon(avatarIcon),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: item.incomplete
                                ? Colors.yellow
                                : Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                            color: bgColor,
                          ),
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            item.text.value,
                            textAlign: textAlign,
                          ),
                        ),
                      ),
                      if (!isLocal) ...[
                        const SizedBox(width: 8),
                        Icon(avatarIcon),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),

          // Input row
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    enabled: widget.isConnected,
                    controller: TextEditingController(text: _inputText)
                      ..selection = TextSelection.collapsed(
                          offset: _inputText.length),
                    decoration: const InputDecoration(
                      labelText: 'Text Input',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) => setState(() => _inputText = val),
                    onSubmitted: (_) => _sendInput(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: widget.isConnected && _inputText.trim().isNotEmpty
                      ? _sendInput
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}