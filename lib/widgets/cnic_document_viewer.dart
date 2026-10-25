import 'package:get/get.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/cnic_document.dart';

class CnicDocumentViewer extends StatefulWidget {
  const CnicDocumentViewer({super.key, this.userId, this.backend});
  final String? userId;
  final CnicBackend? backend;
  @override
  State<CnicDocumentViewer> createState() => _CnicDocumentViewerState();
}

class _CnicDocumentViewerState extends State<CnicDocumentViewer> {
  String? _url;
  String? _error;
  bool _loading = false;
  Timer? _expiry;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    _expiry?.cancel();
    final previous = _url;
    if (previous != null) await NetworkImage(previous).evict();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _url = null;
      _error = null;
    });
    try {
      final url = await (widget.backend ?? SupabaseCnicBackend()).signedUrl(
        userId: widget.userId,
      );
      if (!mounted) return;
      setState(() => _url = url);
      _expiry = Timer(const Duration(seconds: 900), () {
        unawaited(NetworkImage(url).evict());
        if (mounted) {
          setState(() {
            _url = null;
            _error = 'The private viewing link expired. Tap Retry.';
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is FormatException
              ? e.message
              : 'Document could not be loaded. Retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    if (_url != null) unawaited(NetworkImage(_url!).evict());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return AlertDialog(
      title: Text("Private CNIC document".tr),
      content: SizedBox(
        width: 340,
        height: 360,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _url != null
            ? Image.network(
                _url!,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Center(
                  child: Text("Image unavailable. Close and retry.".tr),
                ),
              )
            : Center(child: Text((_error ?? 'Document unavailable.').tr)),
      ),
      actions: [
        TextButton(onPressed: _loading ? null : _load, child: Text("Retry".tr)),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text("Close".tr),
        ),
      ],
    );
  }
}
