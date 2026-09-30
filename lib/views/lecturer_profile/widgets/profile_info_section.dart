import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

class ProfileInfoItem {
  const ProfileInfoItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

/// Card thông tin dùng chung cho các nhóm cá nhân, công tác và tài khoản.
class ProfileInfoSection extends StatelessWidget {
  const ProfileInfoSection({
    super.key,
    required this.title,
    required this.items,
    required this.colors,
  });

  final String title;
  final List<ProfileInfoItem> items;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(AppColors.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Text(
              title,
              style: AppTextStyles.displaySm(colors.foreground),
            ),
          ),
          Divider(height: 1, color: colors.border),
          ...items.asMap().entries.map(
            (entry) => _ProfileInfoRow(
              item: entry.value,
              colors: colors,
              showDivider: entry.key < items.length - 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({
    required this.item,
    required this.colors,
    required this.showDivider,
  });

  final ProfileInfoItem item;
  final AppColors colors;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: colors.border))
            : null,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackValue = constraints.maxWidth < 360;
          final label = Row(
            children: [
              Icon(item.icon, size: 20, color: colors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  style: AppTextStyles.bodySm(colors.mutedForeground),
                ),
              ),
            ],
          );
          final value = Text(
            item.value,
            textAlign: stackValue ? TextAlign.left : TextAlign.right,
            overflow: TextOverflow.visible,
            style: AppTextStyles.bodySm(colors.foreground)
                .copyWith(fontWeight: FontWeight.w600),
          );

          if (stackValue) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                label,
                const SizedBox(height: 8),
                Padding(padding: const EdgeInsets.only(left: 32), child: value),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: label),
              const SizedBox(width: 16),
              Expanded(flex: 6, child: value),
            ],
          );
        },
      ),
    );
  }
}