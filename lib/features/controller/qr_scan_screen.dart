import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/pairing_qr.dart';

/// Full-screen camera that reads the Player's pairing QR code. Pops with the
/// parsed [PairingQr], or with nothing if the user backs out.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;
  String? _problem;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      final qr = PairingQr.parse(raw);
      if (qr != null) {
        _done = true;
        Navigator.of(context).pop(qr);
        return;
      }
      if (_problem == null) {
        setState(() => _problem =
            "That QR code isn't from a RemoteTunes Player. Scan the code shown on the Player screen.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Player QR code')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ClipRect(
                child: MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  errorBuilder: (context, error) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.no_photography_rounded, size: 48),
                          const SizedBox(height: 12),
                          const Text(
                            "The camera isn't available. Allow camera access for "
                            'RemoteTunes in Android settings, or go back and '
                            'connect by typing.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Connect by typing instead'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    _problem ??
                        'On the Player phone, open RemoteTunes → Start as PLAYER '
                            'and point this camera at the QR code.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _problem != null
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Connect by typing instead'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
