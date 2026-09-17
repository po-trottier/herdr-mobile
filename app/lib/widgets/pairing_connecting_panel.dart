import 'package:flutter/widgets.dart';

import 'app_text_button.dart';
import 'eyebrow.dart';
import 'theme/app_color.dart';
import 'theme/app_space.dart';
import 'theme/app_type.dart';
import 'theme/chrome_activity_indicator.dart';

/// The shared pairing state keeps cancellation available during the handshake.
class PairingConnectingPanel extends StatelessWidget {
  const PairingConnectingPanel({
    super.key,
    required this.host,
    required this.onCancel,
    this.framed = false,
  });

  final String host;
  final VoidCallback onCancel;

  /// The QR landscape sidebar is an inset card rather than an edge-to-edge footer.
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final color = AppColor.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.bgRaised,
        border: framed
            ? Border.all(color: color.borderStrong, width: 1)
            : Border(top: BorderSide(color: color.borderStrong, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.space4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Eyebrow(text: 'CONNECTING'),
              const SizedBox(height: AppSpace.space4),
              const Align(
                alignment: Alignment.centerLeft,
                child: ChromeActivityIndicator(),
              ),
              const SizedBox(height: AppSpace.space4),
              Text(
                'Connecting to $host...',
                softWrap: true,
                overflow: TextOverflow.visible,
                style: AppType.body.copyWith(color: color.fgPrimary),
              ),
              const SizedBox(height: AppSpace.space4),
              AppTextButton(label: 'Cancel', onPressed: onCancel),
            ],
          ),
        ),
      ),
    );
  }
}
