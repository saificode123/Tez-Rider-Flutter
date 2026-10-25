import 'package:get/get.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/private_photo_service.dart';
import 'private_photo.dart';

/// A photo submission never changes order state or replaces OTP verification.
class PrivatePhotoEditor extends StatefulWidget {
  const PrivatePhotoEditor({
    super.key,
    this.reference,
    this.orderId,
    this.canUpload = true,
    this.onSaved,
    this.service,
    this.pick,
    this.accountChanges,
  });
  final String? reference;
  final int? orderId;
  final bool canUpload;
  final ValueChanged<String>? onSaved;
  final PrivatePhotoService? service;
  final Future<Uint8List?> Function(ImageSource source)? pick;
  final Stream<void>? accountChanges;
  @override
  State<PrivatePhotoEditor> createState() => _PrivatePhotoEditorState();
}

class _PrivatePhotoEditorState extends State<PrivatePhotoEditor> {
  late final service =
      widget.service ??
      PrivatePhotoService(
        kind: widget.orderId == null ? 'avatar' : 'delivery',
        orderId: widget.orderId,
      );
  late String? reference = widget.reference;
  Uint8List? pending;
  bool busy = false, changed = false;
  String? error, notice;
  int generation = 0;
  StreamSubscription<void>? auth;
  @override
  void initState() {
    super.initState();
    final owner = service.identity();
    auth =
        (widget.accountChanges ??
                (widget.service != null
                    ? const Stream<void>.empty()
                    : Supabase.instance.client.auth.onAuthStateChange.map(
                        (_) {},
                      )))
            .listen((_) {
              if (!mounted || service.identity() == owner) return;
              generation++;
              setState(() {
                changed = true;
                reference = null;
                pending = null;
                notice = null;
                error = 'Account changed. Open this photo again.';
              });
            });
  }

  @override
  void didUpdateWidget(PrivatePhotoEditor old) {
    super.didUpdateWidget(old);
    if (old.reference != widget.reference && !busy && pending == null) {
      reference = widget.reference;
    }
  }

  @override
  void dispose() {
    generation++;
    pending = null;
    unawaited(auth?.cancel());
    super.dispose();
  }

  Future<void> submit([ImageSource? source]) async {
    if (busy || changed || !widget.canUpload) return;
    final request = generation;
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      if (pending == null) {
        if (source == null) return;
        if (widget.pick != null) {
          pending = await widget.pick!(source);
        } else {
          final file = await ImagePicker().pickImage(
            source: source,
            maxWidth: 2048,
            maxHeight: 2048,
            imageQuality: 90,
          );
          if (file != null) {
            if (await file.length() > 5242880) {
              throw StateError('Select a JPEG or PNG up to 5 MB.');
            }
            pending = await file.readAsBytes();
          }
        }
      }
      if (!mounted || generation != request || pending == null) return;
      final saved = await service.upload(pending!);
      if (!mounted || generation != request) return;
      setState(() {
        reference = saved;
        pending = null;
        notice = 'Photo saved.';
      });
      widget.onSaved?.call(saved);
    } catch (_) {
      if (!mounted || generation != request) return;
      if (!service.hasPendingUpload) pending = null;
      setState(() => error = 'Photo was not confirmed. Retry.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (reference != null)
          PrivatePhoto(
            key: ValueKey(reference),
            imageUrl: reference!,
            width: 100,
            height: 100,
            fit: BoxFit.cover,
            service: service,
            accountChanges: widget.accountChanges,
          ),
        if (notice != null)
          Semantics(liveRegion: true, child: Text(notice!.tr)),
        if (error != null) Text(error!.tr),
        if (busy) const LinearProgressIndicator(),
        if (widget.canUpload && !changed)
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton.icon(
                onPressed: busy || pending != null
                    ? null
                    : () => submit(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: Text(
                  widget.orderId == null
                      ? "Choose profile photo".tr
                      : "Choose delivery photo".tr,
                ),
              ),
              TextButton.icon(
                onPressed: busy || pending != null
                    ? null
                    : () => submit(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: Text("Camera".tr),
              ),
              if (pending != null)
                TextButton(
                  onPressed: busy ? null : submit,
                  child: Text("Retry original photo".tr),
                ),
            ],
          ),
        if (widget.orderId != null)
          Text(
            "A photo does not complete delivery. Checklist and OTP verification still apply."
                .tr,
          ),
      ],
    );
  }
}
