import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../../widgets/ui/ui.dart';

/// Shows a "Take a photo / Choose from gallery" sheet and returns the picked
/// file, or null if the user cancelled at either step.
Future<File?> pickAvatarImage(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page, 0, AppSpacing.page, AppSpacing.md),
        child: TerraCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('Update photo'),
              const SizedBox(height: AppSpacing.sm),
              TerraListRow(
                title: 'Take a photo',
                icon: Icons.photo_camera_rounded,
                iconColor: AppColors.primary,
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: AppColors.onSurfaceVariant),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              const SizedBox(height: 10),
              TerraListRow(
                title: 'Choose from gallery',
                icon: Icons.photo_library_rounded,
                iconColor: AppColors.secondary,
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: AppColors.onSurfaceVariant),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (source == null) return null;

  final picked = await ImagePicker()
      .pickImage(source: source, imageQuality: 90, maxWidth: 1024);
  if (picked == null) return null;
  return File(picked.path);
}
