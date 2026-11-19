import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/widgets/language_picker.dart';
import '../../../../l10n/app_lang.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/storefront_logo_icon.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  static const _roles = [
    _RoleDef(
      key: 'customer',
      title: 'loginCustomer',
      subtitle: 'loginCustomerSub',
      lottiePath: 'assets/lottie/managecustomers.json',
      color: Color(0xFF1D9E75),
      bgColor: Color(0xFFE8F8F2),
    ),
    _RoleDef(
      key: 'vendor',
      title: 'loginVendor',
      subtitle: 'loginVendorSub',
      lottiePath: 'assets/lottie/prepare.json',
      color: Color(0xFF7B3FE4),
      bgColor: Color(0xFFEDE9FE),
    ),
    _RoleDef(
      key: 'delivery_staff',
      title: 'loginDelivery',
      subtitle: 'loginDeliverySub',
      lottiePath: 'assets/lottie/delivery.json',
      color: Color(0xFFBA7517),
      bgColor: Color(0xFFFEF5E7),
    ),
  ];

  String? _selectedRoleKey;

  @override
  void initState() {
    super.initState();
    DioClient.warmUp();
  }

  void _onRoleTap(String roleKey) async {
    if (_selectedRoleKey != null) return; // Prevent double taps
    HapticFeedback.lightImpact();
    setState(() {
      _selectedRoleKey = roleKey;
    });
    // Wait for the animation to play
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    await context.push(
      AppRoutes.login,
      extra: <String, String>{'selectedRole': roleKey},
    );
    if (!mounted) return;
    setState(() {
      _selectedRoleKey = null; // Reset selection state when pop back
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 24, 20, bottomInset + 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Logo (tiffin_logo.png) clipped to circle ──
              SizedBox(
                width: 84,
                height: 84,
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/tiffin_logo.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => showLanguagePicker(context),
                  icon: const Icon(Icons.translate_rounded, size: 18),
                  label: Text(tr('language')),
                ),
              ),
              Text(
                tr('chooseLogin'),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tr('selectContinue'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),

              const SizedBox(height: 32),

              // ── Role Cards ──
              ..._roles.map(
                (role) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _RoleCard(
                    role: role,
                    isSelected: _selectedRoleKey == role.key,
                    onTap: () => _onRoleTap(role.key),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.isSelected,
    required this.onTap,
  });

  final _RoleDef role;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: isSelected ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? role.color : AppColors.outlineVariant,
              width: isSelected ? 2.2 : 1.2,
            ),
            boxShadow: [
              if (isSelected)
                BoxShadow(
                  color: role.color.withValues(alpha: 0.28),
                  blurRadius: 18,
                  spreadRadius: 3,
                  offset: const Offset(0, 4),
                )
              else
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(role.title),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tr(role.subtitle),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: role.bgColor,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(6),
                child: Lottie.asset(
                  role.lottiePath,
                  fit: BoxFit.contain,
                  repeat: true,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      _fallbackIcon(role.key),
                      size: 32,
                      color: role.color,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _fallbackIcon(String key) {
    switch (key) {
      case 'customer':
        return Icons.person_outline_rounded;
      case 'vendor':
        return Icons.storefront_outlined;
      case 'delivery_staff':
        return Icons.delivery_dining_rounded;
      default:
        return Icons.circle_outlined;
    }
  }
}

class _RoleDef {
  const _RoleDef({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.lottiePath,
    required this.color,
    required this.bgColor,
  });

  final String key;
  final String title;
  final String subtitle;
  final String lottiePath;
  final Color color;
  final Color bgColor;
}