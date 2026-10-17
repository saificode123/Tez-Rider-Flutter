import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/invoice_service.dart';

class InvoiceButton extends StatefulWidget {
  const InvoiceButton({super.key, required this.orderId, this.load, this.open});
  final int orderId;
  final Future<Uri> Function(int)? load;
  final Future<bool> Function(Uri)? open;

  @override
  State<InvoiceButton> createState() => _InvoiceButtonState();
}

class _InvoiceButtonState extends State<InvoiceButton> {
  bool _loading = false;

  Future<void> _show() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final uri = await (widget.load ?? InvoiceService().signedUrl)(
        widget.orderId,
      );
      if (!mounted) return;
      final opened =
          await (widget.open?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
      if (!opened) {
        throw const FormatException('Unable to open the invoice. Retry.');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException
                  ? error.message
                  : 'Invoice access was not confirmed. Retry.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: _loading ? null : _show,
    icon: _loading
        ? const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.receipt_long_outlined, size: 16),
    label: Text(_loading ? 'Opening…' : 'Invoice'),
  );
}
