import 'package:flutter/material.dart';

enum PttState { idle, pressed, disabled }

class PushToTalkWidget extends StatelessWidget {
  final PttState pttState;
  final bool isConnectingOrConnected;
  final bool isConnected;
  final bool isCancelingResponse;
  final VoidCallback onPushToTalkStart;
  final VoidCallback onPushToTalkStop;
  final double size;

  const PushToTalkWidget({
    super.key,
    required this.pttState,
    required this.isConnectingOrConnected,
    required this.isConnected,
    required this.isCancelingResponse,
    required this.onPushToTalkStart,
    required this.onPushToTalkStop,
    this.size = 150.0,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = isConnected && !isCancelingResponse;
    final opacity = enabled ? 1.0 : 0.38;
    return Opacity(
        opacity: opacity,
        child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: _buildProgressIndicator(context),
            ),
            GestureDetector(
              onTapDown: enabled ? (_) => onPushToTalkStart() : null,
              onTapUp: enabled ? (_) => onPushToTalkStop() : null,
              onTapCancel: enabled ? onPushToTalkStop : null,
              child: _buildPushToTalkButton(context, enabled),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator(BuildContext context) {
    if (isConnected) {
      return CircularProgressIndicator(
        value: 1.0,
        color: Colors.green,
        strokeWidth: 6,
      );
    } else if (isConnectingOrConnected) {
      return CircularProgressIndicator(
        value: null,
        color: Theme.of(context).colorScheme.primary,
        strokeWidth: 6,
      );
    } else {
      return CircularProgressIndicator(
        value: 0.0,
        color: Theme.of(context).disabledColor,
        strokeWidth: 6,
      );
    }
  }

  Widget _buildPushToTalkButton(BuildContext context, bool enabled) {
    final colorBorder = enabled
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).disabledColor;
    final colorBackground = pttState == PttState.pressed
        ? Colors.green
        : Colors.transparent;
    final iconData = enabled ? Icons.mic : Icons.mic_off;
    final colorIcon = enabled
        ? Theme.of(context).colorScheme.onPrimaryContainer // iconTheme.color
        : Theme.of(context).disabledColor;
    return Container(
      width: size * 0.9,
      height: size * 0.9,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: colorBorder, width: 4),
        color: colorBackground,
      ),
      child: Icon(
        iconData,
        size: size * 0.75,
        color: colorIcon,
      ),
    );
  }
}
