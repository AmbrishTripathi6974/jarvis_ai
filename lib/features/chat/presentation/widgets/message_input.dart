import 'dart:ui';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class MessageInput extends StatefulWidget {
  const MessageInput({
    required this.isStreaming,
    required this.rateLimitRemaining,
    required this.onSend,
    super.key,
  });

  final bool isStreaming;
  final Duration? rateLimitRemaining;
  final void Function(
    String text,
    Uint8List? imageBytes,
    String? imageMimeType,
  ) onSend;

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final TextEditingController _controller = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  Uint8List? _selectedImageBytes;
  String? _selectedImageMimeType;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rateLimit = widget.rateLimitRemaining;
    final isRateLimited = rateLimit != null && rateLimit > Duration.zero;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isRateLimited)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Text(
                        'Too many requests. Try again in ${rateLimit.inSeconds + 1}s',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_selectedImageBytes != null)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(
                        _selectedImageBytes!,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Image attached',
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: _clearSelectedImage,
                      icon: const Icon(Icons.close),
                      tooltip: 'Remove image',
                    ),
                  ],
                ),
              ),
            ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.38),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 34,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _ComposerIconButton(
                          icon: Icons.add,
                          tooltip: 'Add',
                          onPressed:
                              (widget.isStreaming || isRateLimited)
                                  ? null
                                  : _openAttachmentSheet,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 44),
                            child: TextField(
                              controller: _controller,
                              minLines: 1,
                              maxLines: 6,
                              textInputAction: TextInputAction.newline,
                              enabled: !widget.isStreaming && !isRateLimited,
                              style:
                                  theme.textTheme.bodyLarge?.copyWith(height: 1.35),
                              decoration: InputDecoration(
                                hintText: 'Message JARVIS',
                                hintStyle: theme.textTheme.bodyLarge?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                                isCollapsed: true,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _SendButton(
                          isEnabled: !widget.isStreaming && !isRateLimited,
                          onPressed: _handleSend,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAttachmentSheet() async {
    final action = await showModalBottomSheet<_ComposerAction>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Camera'),
                onTap: () => Navigator.of(context).pop(_ComposerAction.camera),
              ),
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Gallery'),
                onTap: () => Navigator.of(context).pop(_ComposerAction.gallery),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _ComposerAction.camera:
        await _pickImageFromCamera();
      case _ComposerAction.gallery:
        await _pickImageFromGallery();
    }
  }

  Future<void> _pickImageFromGallery() async {
    final canReadPhotos = await _ensurePhotoPermission();
    if (!canReadPhotos) {
      return;
    }

    final file = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (file == null) {
      return;
    }

    final bytes = await file.readAsBytes();
    setState(() {
      _selectedImageBytes = bytes;
      _selectedImageMimeType = _mimeTypeFromPath(file.path);
    });
  }

  Future<void> _pickImageFromCamera() async {
    final canUseCamera = await _ensureCameraPermission();
    if (!canUseCamera) {
      return;
    }

    final file = await _imagePicker.pickImage(source: ImageSource.camera);
    if (file == null) {
      return;
    }

    final bytes = await file.readAsBytes();
    setState(() {
      _selectedImageBytes = bytes;
      _selectedImageMimeType = _mimeTypeFromPath(file.path);
    });
  }

  Future<bool> _ensurePhotoPermission() async {
    final photosStatus = await Permission.photos.status;
    if (photosStatus.isGranted || photosStatus.isLimited) {
      return true;
    }

    final storageStatus = await Permission.storage.status;
    if (storageStatus.isGranted) {
      return true;
    }

    PermissionStatus nextStatus;
    if (photosStatus.isDenied || photosStatus.isRestricted) {
      nextStatus = await Permission.photos.request();
      if (nextStatus.isGranted || nextStatus.isLimited) {
        return true;
      }
    } else {
      nextStatus = photosStatus;
    }

    if (nextStatus.isPermanentlyDenied || nextStatus.isRestricted) {
      await _showPermissionSettingsDialog(
        resourceName: 'photo',
        message: 'Allow photo access in app settings to pick an image.',
      );
      return false;
    }

    final requestedStorage = await Permission.storage.request();
    if (requestedStorage.isGranted) {
      return true;
    }

    if (requestedStorage.isPermanentlyDenied && mounted) {
      await _showPermissionSettingsDialog(
        resourceName: 'photo',
        message: 'Allow photo access in app settings to pick an image.',
      );
    } else if (mounted) {
      _showPermissionDeniedSnackBar();
    }

    return false;
  }

  Future<void> _showPermissionSettingsDialog({
    required String resourceName,
    required String message,
  }) async {
    if (!mounted) {
      return;
    }

    final shouldOpenSettings = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Permission required'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Open settings'),
            ),
          ],
        );
      },
    );

    if (shouldOpenSettings == true) {
      await openAppSettings();
    } else {
      _showPermissionDeniedSnackBar(
        message: '$resourceName permission is needed for this action.',
      );
    }
  }

  Future<bool> _ensureCameraPermission() async {
    final cameraStatus = await Permission.camera.status;
    if (cameraStatus.isGranted) {
      return true;
    }

    final nextStatus = await Permission.camera.request();
    if (nextStatus.isGranted) {
      return true;
    }

    if (nextStatus.isPermanentlyDenied || nextStatus.isRestricted) {
      await _showPermissionSettingsDialog(
        resourceName: 'Camera',
        message: 'Allow camera access in app settings to take a photo.',
      );
      return false;
    }

    _showPermissionDeniedSnackBar(
      message: 'Camera permission is needed to take photos.',
    );
    return false;
  }

  void _showPermissionDeniedSnackBar({String? message}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message ?? 'Photo permission is needed to attach images.'),
        ),
      );
  }

  void _handleSend() {
    final text = _controller.text;
    if (text.trim().isEmpty && _selectedImageBytes == null) {
      return;
    }

    widget.onSend(text, _selectedImageBytes, _selectedImageMimeType);
    _controller.clear();
    _clearSelectedImage();
  }

  void _clearSelectedImage() {
    if (!mounted) {
      return;
    }

    setState(() {
      _selectedImageBytes = null;
      _selectedImageMimeType = null;
    });
  }

  String _mimeTypeFromPath(String path) {
    final lowerPath = path.toLowerCase();
    if (lowerPath.endsWith('.png')) {
      return 'image/png';
    }
    if (lowerPath.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }
}

enum _ComposerAction { camera, gallery }

class _ComposerIconButton extends StatelessWidget {
  const _ComposerIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: SizedBox(
        width: 42,
        height: 42,
        child: IconButton(
          onPressed: onPressed,
          tooltip: tooltip,
          icon: Icon(
            icon,
            color: onPressed == null ? scheme.onSurfaceVariant : null,
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.isEnabled,
    required this.onPressed,
  });

  final bool isEnabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: isEnabled ? Colors.white : scheme.surfaceContainer,
      shape: const CircleBorder(),
      elevation: isEnabled ? 1 : 0,
      child: InkWell(
        onTap: isEnabled ? onPressed : null,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(
            Icons.arrow_upward_rounded,
            color: isEnabled ? Colors.black : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
