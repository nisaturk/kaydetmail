part of '../compose_screen.dart';

mixin _AttachmentsMixin on _ComposeStateBase {
  String? _attachmentLimitError(List<Attachment> attachments) =>
      _limits?.violationFor(attachments);

  /// Blocks send/schedule/save-draft while any attachment is still
  /// downloading or failed to download — an attachment must never be
  /// silently dropped from the request (docs-dev spec §5/§6, Kural 4).
  bool _validateAttachmentsReady() {
    if (_attachmentsReady) return true;
    final failed = _attachmentIssues.values.any(
      (issue) => issue.status == AttachmentIssue.failed,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed
              ? 'Bir ek indirilemedi. Tekrar deneyin veya kaldırın.'
              : 'Ekler hazırlanıyor, lütfen bekleyin.',
        ),
      ),
    );
    return false;
  }

  bool _validateAttachmentLimits() {
    final error = _attachmentLimitError(_attachments);
    if (error == null) return true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    return false;
  }

  Future<List<Attachment>?> _osPickAttachments() async {
    final source = await showModalBottomSheet<AttachmentSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('attach-source-file'),
              leading: const Icon(LucideIcons.file),
              title: const Text('Dosya seç'),
              onTap: () => Navigator.pop(ctx, AttachmentSource.file),
            ),
            ListTile(
              key: const Key('attach-source-gallery'),
              leading: const Icon(LucideIcons.image),
              title: const Text('Fotoğraf seç'),
              onTap: () => Navigator.pop(ctx, AttachmentSource.gallery),
            ),
            ListTile(
              key: const Key('attach-source-camera'),
              leading: const Icon(LucideIcons.camera),
              title: const Text('Kamera'),
              onTap: () => Navigator.pop(ctx, AttachmentSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    if (source == AttachmentSource.file) return _pickFiles();
    try {
      final picker = ImagePicker();
      final images = source == AttachmentSource.camera
          ? [?await picker.pickImage(source: ImageSource.camera)]
          : await picker.pickMultiImage();
      if (images.isEmpty) return null;
      return [
        for (final image in images)
          await _attachmentFromXFile(
            image,
            fromCamera: source == AttachmentSource.camera,
          ),
      ];
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              source == AttachmentSource.camera
                  ? 'Kameraya erişilemedi. İzinleri kontrol edin veya dosya seçin.'
                  : 'Fotoğraflara erişilemedi. İzinleri kontrol edin veya dosya seçin.',
            ),
          ),
        );
      }
      return null;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${source == AttachmentSource.camera ? 'Fotoğraf eklenemedi' : 'Fotoğraflar eklenemedi'}: '
              '${friendlyErrorMessage(error)}',
            ),
          ),
        );
      }
      return null;
    }
  }

  Future<Attachment> _attachmentFromXFile(
    XFile file, {
    required bool fromCamera,
  }) async {
    final bytes = await file.readAsBytes();
    final name = fromCamera || file.name.isEmpty
        ? cameraPhotoName(DateTime.now(), file.name)
        : file.name;
    return Attachment(
      name: name,
      sizeBytes: bytes.length,
      mimeType: attachmentContentType(name, file.mimeType),
      bytes: bytes,
    );
  }

  Future<List<Attachment>?> _pickFiles() async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty) return null;
    final attachments = <Attachment>[];
    for (final file in files) {
      if (file.name.isEmpty) continue;
      final bytes = await file.readAsBytes();
      attachments.add(
        Attachment(
          name: file.name,
          sizeBytes: bytes.length,
          mimeType: attachmentContentType(file.name, null),
          bytes: bytes,
        ),
      );
    }
    return attachments;
  }

  Future<ImageResizeChoice?> _chooseResize() => showDialog<ImageResizeChoice>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Görsel boyutu'),
      children: [
        for (final choice in ImageResizeChoice.values)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, choice),
            child: Text(switch (choice) {
              ImageResizeChoice.original => 'Orijinal',
              ImageResizeChoice.large => 'Büyük (2048 px)',
              ImageResizeChoice.medium => 'Orta (1280 px)',
              ImageResizeChoice.small => 'Küçük (640 px)',
            }),
          ),
      ],
    ),
  );

  Future<void> _attach() async {
    if (_sending || _resizingImages) return;
    final picked = await (widget.pickAttachments ?? _osPickAttachments)();
    if (picked == null || picked.isEmpty || !mounted) return;
    final limits = _limits;
    if (limits != null) {
      final oversized = picked.where(
        (file) => file.sizeBytes > limits.maxAttachmentBytes,
      );
      if (oversized.isNotEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(limits.fileTooLargeMessage)));
        return;
      }
      if (_attachments.length + picked.length > limits.maxAttachmentCount) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(limits.tooManyMessage)));
        return;
      }
    }
    var result = picked;
    final images = picked.where(isResizableImage).toList();
    if (images.isNotEmpty) {
      final choice = await _chooseResize();
      if (choice == null || !mounted) return;
      if (choice != ImageResizeChoice.original) {
        setState(() => _resizingImages = true);
        var completed = 0;
        try {
          final resized = <Attachment, Attachment>{};
          for (final attachment in images) {
            completed++;
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Görseller hazırlanıyor… ($completed/${images.length})',
                  ),
                  duration: const Duration(minutes: 1),
                ),
              );
            }
            final replacement = await resizeAttachment(attachment, choice);
            if (replacement == null && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${attachment.name}: Görsel küçültülemedi; özgün dosya kullanılacak.',
                  ),
                ),
              );
            }
            if (replacement != null) resized[attachment] = replacement;
          }
          result = [
            for (final attachment in picked) resized[attachment] ?? attachment,
          ];
        } finally {
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            setState(() => _resizingImages = false);
          }
        }
      }
    }
    if (!mounted) return;
    if (limits != null &&
        _attachments.length + result.length > limits.maxAttachmentCount) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(limits.tooManyMessage)));
      return;
    }
    setState(() => _attachments.addAll(result));
    final totalError = _attachmentLimitError(_attachments);
    if (totalError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(totalError)));
    }
  }

  void _removeAttachment(Attachment attachment) {
    setState(() {
      _attachments.remove(attachment);
      _attachmentIssues.remove(attachment);
    });
  }

  /// Downloads (or re-downloads) [attachment]'s content from
  /// [ComposeScreen.attachmentSourceMailId]. Success replaces the
  /// placeholder in [_attachments] with a byte-carrying copy and clears
  /// its entry from [_attachmentIssues]; failure records the reason so the
  /// row can offer retry/remove instead of silently dropping it.
  Future<void> _downloadRemoteAttachment(Attachment attachment) async {
    final sourceMailId = widget.attachmentSourceMailId;
    if (sourceMailId == null) {
      if (mounted) {
        setState(() {
          _attachmentIssues[attachment] = (
            status: AttachmentIssue.failed,
            error: 'Ek indirilemedi.',
          );
        });
      }
      return;
    }
    try {
      final bytes = await _repo.downloadAttachment(sourceMailId, attachment);
      if (!mounted) return;
      final index = _attachments.indexOf(attachment);
      if (index == -1) return; // Removed while the download was in flight.
      setState(() {
        _attachments[index] = Attachment(
          id: attachment.id,
          name: attachment.name,
          sizeBytes: attachment.sizeBytes,
          mimeType: attachment.mimeType,
          bytes: bytes,
        );
        _attachmentIssues.remove(attachment);
      });
    } catch (error) {
      if (!mounted) return;
      if (!_attachments.contains(attachment)) return;
      setState(() {
        _attachmentIssues[attachment] = (
          status: AttachmentIssue.failed,
          error: friendlyErrorMessage(error),
        );
      });
    }
  }

  void _retryAttachment(Attachment attachment) {
    setState(() {
      _attachmentIssues[attachment] = (
        status: AttachmentIssue.downloading,
        error: null,
      );
    });
    unawaited(_downloadRemoteAttachment(attachment));
  }
}
