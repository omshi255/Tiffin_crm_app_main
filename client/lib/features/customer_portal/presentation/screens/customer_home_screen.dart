import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tiffin_crm/features/orders/models/order_model.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/auth/auth_session.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/socket/delivery_tracking_socket.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../../core/theme/theme_mode_provider.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/utils/location_helper.dart';
// ignore: unused_import
import '../../../../core/widgets/app_list_pager.dart';
import '../../../../core/widgets/language_picker.dart';
import '../../../../core/widgets/notification_bell_icon.dart';
import '../../../../l10n/app_lang.dart';
import '../../../../models/customer_model.dart';
import '../../../../models/notification_model.dart';
import '../../data/customer_portal_api.dart';
import '../../../auth/data/auth_api.dart';
import '../../../orders/data/order_api.dart';
import '../../../orders/models/order_status.dart';
import '../../../leave/data/leave_api.dart';
import '../../../leave/models/leave_request_model.dart';
import '../../../leave/presentation/screens/customer_leave_requests_screen.dart';
import '../../../leave/presentation/screens/customer_monthly_bills_screen.dart';
import '../../../subscriptions/models/subscription_model.dart';

// Vendor violet palette. The customer shell sets CustomerChrome.brightness.
abstract final class CustomerChrome {
  static Brightness brightness = Brightness.light;
  static bool get isDark => brightness == Brightness.dark;
}

bool get _custDark => CustomerChrome.isDark;

Color get _green900 =>
    _custDark ? const Color(0xFFDDD6FE) : const Color(0xFF2D1B69);
Color get _green700 =>
    _custDark ? const Color(0xFF9B6AF0) : const Color(0xFF4C2DB8);
Color get _green600 =>
    _custDark ? const Color(0xFFB794F6) : const Color(0xFF5B35D5);
Color get _green200 =>
    _custDark ? const Color(0xFF3B2F6B) : const Color(0xFFD4C4F8);
Color get _green100 =>
    _custDark ? const Color(0xFF2A2348) : const Color(0xFFEDE8FD);
Color get _green50 =>
    _custDark ? const Color(0xFF1E1B3A) : const Color(0xFFF5F2FF);
Color get _violet700 =>
    _custDark ? const Color(0xFF9B6AF0) : const Color(0xFF4C2DB8);
Color get _violet600 =>
    _custDark ? const Color(0xFFB794F6) : const Color(0xFF5B35D5);
Color get _violet100 =>
    _custDark ? const Color(0xFF2A2348) : const Color(0xFFEDE8FD);
Color get _violet50 =>
    _custDark ? const Color(0xFF1E1B3A) : const Color(0xFFF5F2FF);
Color get _bg => _custDark ? const Color(0xFF0E1020) : const Color(0xFFF6F4FF);
Color get _surface =>
    _custDark ? const Color(0xFF141625) : const Color(0xFFFFFFFF);
Color get _border =>
    _custDark ? const Color(0xFF2F2A55) : const Color(0xFFE4DFF7);
Color get _divider =>
    _custDark ? const Color(0xFF1E1B3A) : const Color(0xFFEEEBFA);
Color get _text1 =>
    _custDark ? const Color(0xFFF8FAFC) : const Color(0xFF1A0E45);
Color get _text2 =>
    _custDark ? const Color(0xFF94A3B8) : const Color(0xFF7B6DAB);
Color get _warning => const Color(0xFFBA7517);
Color get _warnSoft =>
    _custDark ? const Color(0xFF2A2110) : const Color(0xFFFAEEDA);
Color get _danger => const Color(0xFFD93025);
Color get _dangerSoft =>
    _custDark ? const Color(0xFF2A1210) : const Color(0xFFFCECEB);

class CustomerHomeScreen extends ConsumerStatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  ConsumerState<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends ConsumerState<CustomerHomeScreen> {
  int _selectedIndex = 0;
  int _leaveRefresh = 0;
  int _unreadCount = 0;
  Timer? _unreadTimer;
  String? _vendorUpiId;
  String _vendorPayLabel = 'vendor';

  // New instances each build so theme changes rebuild the tabs.
  // State is kept because the widget type and position stay the same.
  List<Widget> get _tabs => [
    RepaintBoundary(child: _CustomerHomeTab()),
    RepaintBoundary(child: _CustomerOrdersTab()),
    RepaintBoundary(
      child: CustomerLeaveRequestsScreen(
        embedded: true,
        refreshToken: _leaveRefresh,
      ),
    ),
    RepaintBoundary(child: _CustomerWalletTab()),
    RepaintBoundary(child: _CustomerProfileTab()),
  ];

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
    _unreadTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) _loadUnreadCount();
    });
    _loadVendorUpiBanner();
  }

  @override
  void dispose() {
    _unreadTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadVendorUpiBanner() async {
    try {
      final profile = await CustomerPortalApi.getMyProfile();
      final v = profile.vendor;
      final upi = v?.upiId?.trim() ?? '';
      if (!mounted) return;
      if (upi.isEmpty) {
        setState(() => _vendorUpiId = null);
      } else {
        final biz = v?.businessName?.trim() ?? '';
        final owner = v?.ownerName?.trim() ?? '';
        final label =
            biz.isNotEmpty ? biz : (owner.isNotEmpty ? owner : 'vendor');
        setState(() {
          _vendorUpiId = upi;
          _vendorPayLabel = label;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _vendorUpiId = null);
    }
  }

  Future<void> _loadUnreadCount() async {
    try {
      final res = await CustomerPortalApi.getMyNotifications(limit: 50);
      final list = (res['notifications'] as List?) ?? [];
      final unread = list.where((n) {
        if (n is NotificationModel) return !n.read;
        return false;
      }).length;
      if (mounted) setState(() => _unreadCount = unread);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    CustomerChrome.brightness = Theme.of(context).brightness;
    final dark = ref.watch(themeModeProvider) == ThemeMode.dark;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        flexibleSpace: const Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF7B3FE4),
                    Color(0xFF6B35C8),
                    Color(0xFF3B1578),
                  ],
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 16,
        title: Text(
          tr('myMeals'),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            tooltip: dark ? tr('lightMode') : tr('darkMode'),
            onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
            icon: Icon(
              dark ? Icons.light_mode_rounded : Icons.dark_mode_outlined,
              color: Colors.white,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () async {
                await context.push(AppRoutes.customerNotifications);
                if (mounted) _loadUnreadCount();
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.notifications_outlined,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                  if (_unreadCount > 0)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD93025),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Text(
                          _unreadCount > 9 ? '9+' : '$_unreadCount',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_vendorUpiId != null && _vendorUpiId!.isNotEmpty)
            _CustomerVendorUpiBanner(
              vendorLabel: _vendorPayLabel,
              upiId: _vendorUpiId!,
            ),
          Expanded(
            child: IndexedStack(index: _selectedIndex, children: _tabs),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: _surface,
          border: Border(top: BorderSide(color: _border, width: 1)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                _NavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: tr('home'),
                  index: 0,
                  selected: _selectedIndex == 0,
                  onTap: () => setState(() => _selectedIndex = 0),
                ),
                _NavItem(
                  icon: Icons.receipt_long_outlined,
                  activeIcon: Icons.receipt_long_rounded,
                  label: tr('orders'),
                  index: 1,
                  selected: _selectedIndex == 1,
                  onTap: () => setState(() => _selectedIndex = 1),
                ),
                _NavItem(
                  icon: Icons.event_busy_outlined,
                  activeIcon: Icons.event_busy_rounded,
                  label: tr('leave'),
                  index: 2,
                  selected: _selectedIndex == 2,
                  onTap: () => setState(() {
                    _selectedIndex = 2;
                    _leaveRefresh++;
                  }),
                ),
                _NavItem(
                  icon: Icons.account_balance_wallet_outlined,
                  activeIcon: Icons.account_balance_wallet_rounded,
                  label: tr('wallet'),
                  index: 3,
                  selected: _selectedIndex == 3,
                  onTap: () => setState(() => _selectedIndex = 3),
                ),
                _NavItem(
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                  label: tr('profile'),
                  index: 4,
                  selected: _selectedIndex == 4,
                  onTap: () => setState(() => _selectedIndex = 4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom Nav Item
// ─────────────────────────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.index,
    required this.selected,
    required this.onTap,
  });
  final IconData icon, activeIcon;
  final String label;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 36,
            height: 30,
            decoration: BoxDecoration(
              color: selected ? _violet100 : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              selected ? activeIcon : icon,
              size: 19,
              color: selected ? _violet600 : _text2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? _violet600 : _text2,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Shown under the app bar on every customer tab when the vendor set a UPI ID.
class _CustomerVendorUpiBanner extends StatelessWidget {
  const _CustomerVendorUpiBanner({
    required this.vendorLabel,
    required this.upiId,
  });

  final String vendorLabel;
  final String upiId;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: upiId));
    if (!context.mounted) return;
    AppSnackbar.success(context, 'UPI ID copied');
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _green50,
      child: InkWell(
        onTap: () => _copy(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.qr_code_2_rounded, color: _green700, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Pay $vendorLabel (UPI)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _text2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      upiId,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _text1,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.copy_rounded, size: 20, color: _green600),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Home Tab
// ─────────────────────────────────────────────────────────────────────────────

class _HomeNotice {
  const _HomeNotice({
    required this.title,
    required this.body,
    required this.unread,
    this.dateLabel,
  });

  final String title;
  final String body;
  final bool unread;
  final String? dateLabel;
}

class _CustomerHomeTab extends StatefulWidget {
  const _CustomerHomeTab();
  @override
  State<_CustomerHomeTab> createState() => _CustomerHomeTabState();
}

class _CustomerHomeTabState extends State<_CustomerHomeTab> {
  OrderModel? _todayOrder;
  CustomerModel? _profile;
  CustomerBalanceModel? _balance;
  PublicPortalAnnouncement? _portalAnnouncement;
  /// Banner hidden until text changes (same session).
  String? _dismissedAnnouncementText;
  _HomeNotice? _leaveNotice;
  bool _loading = true;
  Timer? _refreshTimer;

  static final _announcementDateFmt = DateFormat('MMM d, h:mm a');

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        CustomerPortalApi.getTodayOrder(),
        CustomerPortalApi.getMyProfile(),
        CustomerPortalApi.getMyBalance(),
      ]);
      final order = results[0] as OrderModel?;
      final profile = results[1] as CustomerModel;
      final balance = results[2] as CustomerBalanceModel;
      final oid = profile.ownerId?.trim();
      final PublicPortalAnnouncement? announcement =
          (oid != null && oid.isNotEmpty)
              ? await CustomerPortalApi.getPublicPortalAnnouncement(oid)
              : null;
      final notice = await _latestLeaveNotice();
      if (mounted) {
        setState(() {
          _todayOrder = order;
          _profile = profile;
          _balance = balance;
          _portalAnnouncement = announcement;
          _leaveNotice = notice;
        });
      }
    } catch (e) {
      if (mounted) ErrorHandler.show(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<_HomeNotice?> _latestLeaveNotice() async {
    try {
      final res = await CustomerPortalApi.getMyNotifications(limit: 30);
      final list = (res['notifications'] as List?)
              ?.whereType<NotificationModel>()
              .toList() ??
          [];
      for (final n in list) {
        final type = (n.type ?? '').toLowerCase();
        if (type == 'leave_approved' ||
            type == 'leave_rejected' ||
            type == 'vendor_holiday') {
          return _HomeNotice(
            title: n.title.isEmpty ? tr('leaveUpdate') : n.title,
            body: n.body,
            unread: !n.read,
            dateLabel: _noticeDateLabel(n.data?['leaveDate']?.toString()),
          );
        }
      }
    } catch (_) {}

    try {
      final res = await LeaveApi.getLeavesForCustomer(limit: 20);
      final leaves =
          (res['leaves'] as List?)?.whereType<LeaveRequestModel>().toList() ??
              [];
      for (final leave in leaves) {
        final status = leave.status.toLowerCase();
        final vendorHoliday = leave.requestedBy.toLowerCase() == 'vendor';
        final when = DateFormat('EEE, d MMM').format(leave.date.toLocal());
        final meal = leave.mealType.isEmpty
            ? tr('mealWord')
            : '${leave.mealType[0].toUpperCase()}${leave.mealType.substring(1)}';
        if (vendorHoliday && status == 'approved') {
          return _HomeNotice(
            title: tr('vendorHoliday'),
            body: trf('vendorHolidayBody', {'when': when}),
            unread: true,
            dateLabel: when,
          );
        }
        if (!vendorHoliday && status == 'approved') {
          return _HomeNotice(
            title: tr('leaveApproved'),
            body: trf('leaveApprovedBody', {'meal': meal, 'when': when}),
            unread: true,
            dateLabel: when,
          );
        }
        if (!vendorHoliday && status == 'rejected') {
          return _HomeNotice(
            title: tr('leaveRejected'),
            body: trf('leaveRejectedBody', {'meal': meal, 'when': when}),
            unread: true,
            dateLabel: when,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  static String _statusLabel(String status) =>
      OrderStatus.fromApi(status).label;

  static (Color, Color) _statusColors(String status) {
    final s = status.toLowerCase();
    if (s == 'delivered') return (_violet600, _violet50);
    if (s == 'out_for_delivery' || s == 'in_transit') {
      return (_violet600, _violet50);
    }
    if (s == 'processing' || s == 'cooking') return (_warning, _warnSoft);
    return (_text2, _divider);
  }

  bool get _showAnnouncementBanner {
    final ann = _portalAnnouncement;
    if (ann == null) return false;
    final t = ann.text.trim();
    if (t.isEmpty) return false;
    return _dismissedAnnouncementText != t;
  }

  String? _noticeDateLabel(String? raw) {
    if (raw == null || raw.length < 10) return null;
    final parts = raw.substring(0, 10).split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateFormat('EEE, d MMM yyyy').format(DateTime(year, month, day));
  }

  Widget _leaveNoticeCard(_HomeNotice notice) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push(AppRoutes.customerNotifications),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _violet50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _violet100),
                ),
                child: Icon(
                  Icons.notifications_active_outlined,
                  color: _violet600,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notice.title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _text1,
                            ),
                          ),
                        ),
                        if (notice.unread)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _violet100,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'New',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _violet700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (notice.dateLabel != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        notice.dateLabel!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _violet700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      notice.body,
                      style: TextStyle(fontSize: 13, height: 1.35, color: _text2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _portalAnnouncementHeading(PublicPortalAnnouncement a) {
    final biz = a.businessName.trim();
    if (biz.isNotEmpty) return 'Announcement from $biz';
    final owner = a.ownerName.trim();
    if (owner.isNotEmpty) return 'Announcement from $owner';
    return 'Announcement from your vendor';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _todayOrder == null && _profile == null && _balance == null) {
      return Center(child: CircularProgressIndicator(color: _green600));
    }
    final walletBalance = _balance?.walletBalance ?? _profile?.balance ?? 0.0;
    final subscriptionBalance = _balance?.subscriptionBalance ?? 0.0;
    final lowBalance = walletBalance < 100;
    final firstName = (_profile?.name ?? 'there').split(' ').first;

    return RefreshIndicator(
      color: _green600,
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          20,
          16,
          MediaQuery.of(context).padding.bottom + 32,
        ),
        children: [
          if (_showAnnouncementBanner && _portalAnnouncement != null) ...[
            _portalAnnouncementBanner(_portalAnnouncement!),
            const SizedBox(height: 14),
          ],
          // ── Greeting ──────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hello, $firstName!',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _text1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Here's your tiffin update",
                      style: TextStyle(fontSize: 13, color: _text2),
                    ),
                  ],
                ),
              ),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _green100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: Center(
                  child: Text(
                    (_profile?.name ?? '?')[0].toUpperCase(),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _green700,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          if (_leaveNotice != null) ...[
            _leaveNoticeCard(_leaveNotice!),
            const SizedBox(height: 18),
          ],

          // ── Today's meal card ─────────────────────────────────────────────
          _sectionLabel(tr('todaysMeal')),
          const SizedBox(height: 8),
          _todayOrder == null ? _emptyMealCard() : _mealCard(_todayOrder!),

          const SizedBox(height: 20),

          // ── Wallet card ───────────────────────────────────────────────────
          _sectionLabel(tr('wallet')),
          const SizedBox(height: 8),
          _walletCard(walletBalance, subscriptionBalance),

          const SizedBox(height: 20),
          _sectionLabel(tr('quickActions')),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border),
              boxShadow: [
                BoxShadow(
                  color: _green900.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (ctx) => const CustomerLeaveRequestsScreen(),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _violet50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _violet100),
                        ),
                        child: Icon(
                          Icons.event_busy_rounded,
                          color: _violet600,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr('myLeaveRequests'),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: _text1,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Submit or track your vacation/leave requests',
                              style: TextStyle(fontSize: 12, color: _text2),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: _text2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (ctx) => const CustomerMonthlyBillsScreen(),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _violet50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _violet100),
                        ),
                        child: Icon(
                          Icons.receipt_long_rounded,
                          color: _violet600,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr('monthlyBills'),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: _text1,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'View and download receipts. Approved leave is not charged.',
                              style: TextStyle(fontSize: 12, color: _text2),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: _text2),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Low balance warning ───────────────────────────────────────────
          if (lowBalance && walletBalance >= 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _warnSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: _warning,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Low balance. Top up to avoid service interruption.',
                      style: TextStyle(
                        fontSize: 12,
                        color: _warning,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _mealCard(OrderModel order) {
    final (statusColor, statusBg) = _statusColors(order.status);
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _green900.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: _green600,
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _green100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.lunch_dining_rounded,
                    size: 22,
                    color: _green700,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.slot ?? "Today's meal",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _text1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: statusBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          _statusLabel(order.status),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyMealCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _border),
    ),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _green50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _border),
          ),
          child: Icon(
            Icons.lunch_dining_outlined,
            size: 22,
            color: _text2,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No order for today',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _text1,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Your tiffin will appear here once generated.',
                style: TextStyle(fontSize: 12, color: _text2),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _portalAnnouncementBanner(PublicPortalAnnouncement a) {
    final updated = a.updatedAt;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _violet600.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _violet100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.campaign_rounded,
                  color: _violet600,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _portalAnnouncementHeading(a),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _violet700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      a.text.trim(),
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: _text1,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (updated != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Updated: ${_announcementDateFmt.format(updated.toLocal())}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _text2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _dismissedAnnouncementText = a.text.trim();
                  });
                },
                icon: Icon(Icons.close_rounded, size: 20, color: _text2),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                tooltip: 'Dismiss',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _walletCard(double walletBalance, double subscriptionBalance) =>
      Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _violet100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.account_balance_wallet_rounded,
            size: 22,
            color: _violet600,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Rs.${walletBalance.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _violet700,
                ),
              ),
              Text(
                'Available balance',
                style: TextStyle(fontSize: 12, color: _text2),
              ),
              const SizedBox(height: 4),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  Text(
                    'Subscription: Rs.${subscriptionBalance.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _text2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _sectionLabel(String text) => Row(
    children: [
      Container(
        width: 3,
        height: 13,
        decoration: BoxDecoration(
          color: _green600,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 7),
      Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: _text2,
          letterSpacing: 1.1,
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// My Plan Tab — HIDDEN (not in bottom nav / _tabs). Uncomment block + restore tab
// in _tabs and _NavItem "My Plan" (index 1) to show again.
// ─────────────────────────────────────────────────────────────────────────────
/*
class _CustomerMyPlanTab extends StatefulWidget {
  const _CustomerMyPlanTab();
  @override
  State<_CustomerMyPlanTab> createState() => _CustomerMyPlanTabState();
}

class _CustomerMyPlanTabState extends State<_CustomerMyPlanTab> {
  OrderModel? _todayOrder;
  List<_PlanItemRow> _items = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final order = await CustomerPortalApi.getTodayOrder();
      if (!mounted) return;
      _todayOrder = order;
      _items = _parseItems(order);
      setState(() => _loading = false);
    } catch (e) {
      if (mounted) ErrorHandler.show(context, e);
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_PlanItemRow> _parseItems(OrderModel? order) {
    if (order == null) return [];
    final list = <_PlanItemRow>[];
    final slots = order.mealSlots;
    if (slots == null) return [];
    for (final e in slots) {
      if (e is! Map<String, dynamic>) continue;
      final itemId = e['itemId']?.toString() ?? e['_id']?.toString() ?? '';
      final name = e['name']?.toString() ?? e['itemName']?.toString() ?? 'Item';
      final q = (e['quantity'] is num) ? (e['quantity'] as num).toInt() : 1;
      list.add(
        _PlanItemRow(itemId: itemId, name: name, quantity: q.clamp(1, 999)),
      );
    }
    return list;
  }

  Future<void> _save() async {
    if (_todayOrder == null || _items.isEmpty) return;
    setState(() => _saving = true);
    try {
      final quantities = _items
          .map((e) => {'itemId': e.itemId, 'quantity': e.quantity})
          .toList();
      await OrderApi.updateQuantities(_todayOrder!.id, quantities);
      if (mounted) AppSnackbar.success(context, 'Changes saved');
    } catch (e) {
      if (mounted) ErrorHandler.show(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: _green600));
    }
    if (_todayOrder == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _green100,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                Icons.restaurant_menu_outlined,
                size: 32,
                color: _green700,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'No order for today',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _text1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Your plan will appear here',
              style: TextStyle(fontSize: 13, color: _text2),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              20,
              16,
              MediaQuery.of(context).padding.bottom + 8,
            ),
            children: [
              _sectionLabel('Your Plan'),
              const SizedBox(height: 4),
              Text(
                'Adjust quantities (min 1). Tap Save to apply.',
                style: TextStyle(fontSize: 12, color: _text2),
              ),
              const SizedBox(height: 14),
              ..._items.map(
                (item) => _PlanItemStepper(
                  item: item,
                  onChanged: () => setState(() {}),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            MediaQuery.of(context).padding.bottom + 20,
          ),
          child: SizedBox(
            height: 50,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_violet700, _violet600],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(13),
                boxShadow: [
                  BoxShadow(
                    color: _violet600.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Save Changes',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Row(
    children: [
      Container(
        width: 3,
        height: 13,
        decoration: BoxDecoration(
          color: _green600,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 7),
      Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: _text2,
          letterSpacing: 1.1,
        ),
      ),
    ],
  );
}

class _PlanItemRow {
  _PlanItemRow({
    required this.itemId,
    required this.name,
    required this.quantity,
  });
  final String itemId;
  final String name;
  int quantity;
}

class _PlanItemStepper extends StatelessWidget {
  const _PlanItemStepper({required this.item, required this.onChanged});
  final _PlanItemRow item;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _border),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            item.name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _text1,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: _green50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: item.quantity <= 1
                    ? null
                    : () {
                        item.quantity--;
                        onChanged();
                      },
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: item.quantity <= 1 ? Colors.transparent : _green100,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    Icons.remove_rounded,
                    size: 16,
                    color: item.quantity <= 1 ? _text2 : _green700,
                  ),
                ),
              ),
              SizedBox(
                width: 28,
                child: Center(
                  child: Text(
                    '${item.quantity}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _text1,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  item.quantity++;
                  onChanged();
                },
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _violet100,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    Icons.add_rounded,
                    size: 16,
                    color: _violet600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
*/

// ─────────────────────────────────────────────────────────────────────────────
// Orders Tab
// ─────────────────────────────────────────────────────────────────────────────

class _CustomerOrdersTab extends StatefulWidget {
  const _CustomerOrdersTab();
  @override
  State<_CustomerOrdersTab> createState() => _CustomerOrdersTabState();
}

class _PlanMeal {
  const _PlanMeal({
    required this.date,
    required this.title,
    required this.status,
    required this.cancelled,
    this.order,
  });

  final DateTime date;
  final String title;
  final String status;
  final bool cancelled;
  final OrderModel? order;

  String get statusLabel => cancelled ? tr('orderCancelled') : status;
}

class _CustomerOrdersTabState extends State<_CustomerOrdersTab> {
  List<_PlanMeal> _meals = [];
  String? _rangeLabel;
  bool _loading = true;
  String? _statusFilter;
  int _ordersPage = 1;
  Timer? _refreshTimer;

  static const List<String?> _statusValues = [
    null,
    'pending',
    'processing',
    'out_for_delivery',
    'delivered',
    'cancelled',
  ];
  static const List<String> _statusKeys = [
    'all',
    'pending',
    'processing',
    'outForDelivery',
    'delivered',
    'cancelled',
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _initLiveTrackingSocket();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _load();
    });
  }

  Future<void> _initLiveTrackingSocket() async {
    final role = await SecureStorage.getUserRole();
    if (role == 'customer') {
      await DeliveryTrackingSocket.instance.ensureConnected();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  List<_PlanMeal> get _visibleMeals {
    final filter = _statusFilter;
    if (filter == null) return _meals;
    if (filter == 'cancelled') {
      return _meals.where((meal) => meal.cancelled).toList();
    }
    return _meals
        .where((meal) => !meal.cancelled && meal.status == filter)
        .toList();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final orders = <OrderModel>[];
      var page = 1;
      var totalPages = 1;
      do {
        final res = await CustomerPortalApi.getMyOrders(page: page, limit: 50);
        orders.addAll(res['orders'] as List<OrderModel>? ?? []);
        totalPages = (res['totalPages'] as int?) ?? 1;
        page++;
      } while (page <= totalPages && page <= 8);

      SubscriptionModel? plan;
      try {
        plan = await CustomerPortalApi.getMyActivePlan();
      } catch (_) {}

      var leaves = <LeaveRequestModel>[];
      try {
        final res = await LeaveApi.getLeavesForCustomer(limit: 100);
        leaves = List<LeaveRequestModel>.from(res['leaves'] as Iterable);
      } catch (_) {}

      final built = _buildMealCalendar(orders, plan, leaves);
      if (mounted) {
        setState(() {
          _meals = built.meals;
          _rangeLabel = built.rangeLabel;
        });
      }
    } catch (e) {
      if (mounted) ErrorHandler.show(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static DateTime _utcDay(DateTime value) {
    final utc = value.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }

  static String _dayKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  static String _prettyMeal(String raw) {
    final text = raw.trim().replaceAll('_', ' ');
    if (text.isEmpty) return 'Daily tiffin';
    return text[0].toUpperCase() + text.substring(1);
  }

  static bool _isCancelledStatus(String status) {
    switch (status.toLowerCase()) {
      case 'skipped':
      case 'cancelled':
      case 'failed':
        return true;
      default:
        return false;
    }
  }

  static bool _leaveCoversMeal(LeaveRequestModel leave, String meal) {
    if (leave.status.toLowerCase() != 'approved') return false;
    final type = leave.mealType.toLowerCase();
    return type == 'all' || type == 'both' || type == meal;
  }

  static bool _isVendorHolidayLeave(LeaveRequestModel leave, String meal) {
    return leave.requestedBy.toLowerCase() == 'vendor' &&
        _leaveCoversMeal(leave, meal);
  }

  static bool _isVendorHolidayOrder(OrderModel order) {
    return (order.cancellationReason ?? '').toLowerCase().contains('holiday');
  }

  static String _displayStatus(String status) {
    if (_isCancelledStatus(status)) return tr('orderCancelled');
    return OrderStatus.fromApi(status).label;
  }

  ({List<_PlanMeal> meals, String? rangeLabel}) _buildMealCalendar(
    List<OrderModel> orders,
    SubscriptionModel? plan,
    List<LeaveRequestModel> leaves,
  ) {
    final meals = plan?.mealTypes ?? const <String>[];
    if (plan == null || meals.isEmpty) {
      final rows = orders
          .where((order) => !_isVendorHolidayOrder(order))
          .map((order) {
        final cancelled = _isCancelledStatus(order.status);
        final mealName = (order.mealTime ?? '').trim().isNotEmpty
            ? order.mealTime!
            : (order.slot ?? 'Daily tiffin');
        return _PlanMeal(
          date: _utcDay(order.date),
          title: _prettyMeal(mealName),
          status: cancelled
              ? 'cancelled'
              : OrderStatus.fromApi(order.status).apiValue,
          cancelled: cancelled,
          order: order,
        );
      }).toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      return (meals: rows, rangeLabel: null);
    }

    final start = _utcDay(plan.startDate);
    var end = _utcDay(plan.endDate);
    if (end.isBefore(start)) end = start;
    if (end.difference(start).inDays > 120) {
      end = start.add(const Duration(days: 120));
    }

    final deliveryDays = (plan.deliveryDays == null || plan.deliveryDays!.isEmpty)
        ? <int>{0, 1, 2, 3, 4, 5, 6}
        : plan.deliveryDays!.toSet();

    final ordersByDay = <String, List<OrderModel>>{};
    for (final order in orders) {
      ordersByDay.putIfAbsent(_dayKey(_utcDay(order.date)), () => []).add(order);
    }
    final leavesByDay = <String, List<LeaveRequestModel>>{};
    for (final leave in leaves) {
      leavesByDay.putIfAbsent(_dayKey(_utcDay(leave.date)), () => []).add(leave);
    }

    final rows = <_PlanMeal>[];
    for (var day = start; !day.isAfter(end); day = day.add(const Duration(days: 1))) {
      if (!deliveryDays.contains(day.weekday % 7)) continue;
      final paused = plan.status == 'paused' &&
          plan.pausedFrom != null &&
          plan.pausedUntil != null &&
          !day.isBefore(_utcDay(plan.pausedFrom!)) &&
          !day.isAfter(_utcDay(plan.pausedUntil!));
      final dayOrders = ordersByDay[_dayKey(day)] ?? const <OrderModel>[];
      final dayLeaves = leavesByDay[_dayKey(day)] ?? const <LeaveRequestModel>[];

      for (final meal in meals) {
        OrderModel? match;
        for (final order in dayOrders) {
          final orderMeal = (order.mealTime ?? '').toLowerCase();
          if (orderMeal.isEmpty || orderMeal == meal) {
            match = order;
            if (orderMeal == meal) break;
          }
        }
        final vendorClosed = dayLeaves.any(
          (leave) => _isVendorHolidayLeave(leave, meal),
        );
        if (vendorClosed) continue;
        final covered = dayLeaves.any((leave) => _leaveCoversMeal(leave, meal));
        if (match != null && _isVendorHolidayOrder(match)) continue;
        final cancelled = paused
            ? false
            : covered || (match != null && _isCancelledStatus(match.status));
        final status = paused
            ? 'paused'
            : cancelled
                ? 'cancelled'
                : match == null
                    ? 'pending'
                    : OrderStatus.fromApi(match.status).apiValue;
        rows.add(
          _PlanMeal(
            date: day,
            title: _prettyMeal(meal),
            status: status,
            cancelled: cancelled,
            order: match,
          ),
        );
      }
    }

    final label =
        '${DateFormat('d MMM').format(DateTime(start.year, start.month, start.day))}'
        ' – ${DateFormat('d MMM yyyy').format(DateTime(end.year, end.month, end.day))}'
        ' · ${rows.length} meal days';
    return (meals: rows, rangeLabel: label);
  }

  void _showOrderStatusSheet(OrderModel o) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _OrderStatusSheet(order: o),
    );
  }

  static (Color, Color, String) _statusMeta(_PlanMeal meal) {
    if (meal.cancelled || meal.status == 'paused') {
      final label = meal.cancelled ? tr('orderCancelled') : tr('paused');
      return (_danger, _dangerSoft, label);
    }
    final o = OrderStatus.fromApi(meal.status);
    if (o == OrderStatus.delivered) {
      return (_violet600, _violet50, o.label);
    }
    if (o == OrderStatus.outForDelivery) {
      return (_violet600, _violet50, o.label);
    }
    if (o == OrderStatus.processing) {
      return (_warning, _warnSoft, o.label);
    }
    return (_text2, _divider, _displayStatus(meal.status));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filter chips
        Container(
          color: _surface,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(
              16,
              10,
              16,
              MediaQuery.of(context).padding.bottom + 10,
            ),
            child: Row(
              children: List.generate(_statusKeys.length, (i) {
                final sel = _statusFilter == _statusValues[i];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _statusFilter = _statusValues[i];
                        _ordersPage = 1;
                      });
                      _load();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: sel ? _green700 : _green50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: sel ? _green700 : _border),
                      ),
                      child: Text(
                        tr(_statusKeys[i]),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: sel ? Colors.white : _text2,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        if (_rangeLabel != null)
          Container(
            width: double.infinity,
            color: _surface,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              _rangeLabel!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _text2,
              ),
            ),
          ),
        Expanded(
          child: _loading && _meals.isEmpty
              ? Center(child: CircularProgressIndicator(color: _green600))
              : RefreshIndicator(
                  color: _green600,
                  onRefresh: _load,
                  child: _visibleMeals.isEmpty
                      ? ListView(
                          padding: EdgeInsets.only(
                            bottom:
                                MediaQuery.of(context).padding.bottom + 24,
                          ),
                          children: [
                            const SizedBox(height: 80),
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: _green100,
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Icon(
                                      Icons.receipt_long_outlined,
                                      size: 32,
                                      color: _green700,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    'No meals in this view',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: _text1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Builder(builder: (context) {
                          final window = PageWindow.slice(
                            _visibleMeals,
                            _ordersPage,
                          );
                          return ListView.builder(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            12,
                            16,
                            MediaQuery.of(context).padding.bottom + 32,
                          ),
                          itemCount: window.items.length +
                              (window.total > kListPageSize ? 1 : 0),
                          itemBuilder: (ctx, i) {
                            if (i >= window.items.length) {
                              return AppListPager(
                                page: window.page,
                                total: window.total,
                                onPage: (p) => setState(() => _ordersPage = p),
                              );
                            }
                            final meal = window.items[i];
                            final (sc, sb, sl) = _statusMeta(meal);
                            final day = DateTime(
                              meal.date.year,
                              meal.date.month,
                              meal.date.day,
                            );
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: InkWell(
                                onTap: meal.order == null
                                    ? null
                                    : () => _showOrderStatusSheet(meal.order!),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: _surface,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: _border),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: meal.cancelled
                                              ? _dangerSoft
                                              : _green100,
                                          borderRadius: BorderRadius.circular(
                                            11,
                                          ),
                                        ),
                                        child: Icon(
                                          meal.cancelled
                                              ? Icons.event_busy_rounded
                                              : Icons.lunch_dining_outlined,
                                          size: 20,
                                          color: meal.cancelled
                                              ? _danger
                                              : _green700,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              meal.title,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: _text1,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              DateFormat('EEE, d MMM yyyy')
                                                  .format(day),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: _text2,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: sb,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: sc.withValues(alpha: 0.3),
                                          ),
                                        ),
                                        child: Text(
                                          sl,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: sc,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                        }),
                ),
        ),
      ],
    );
  }
}

class _OrderStatusSheet extends StatefulWidget {
  const _OrderStatusSheet({required this.order});
  final OrderModel order;

  @override
  State<_OrderStatusSheet> createState() => _OrderStatusSheetState();
}

class _OrderStatusSheetState extends State<_OrderStatusSheet> {
  StreamSubscription<DeliveryLocationUpdate>? _sub;
  DeliveryLocationUpdate? _live;
  DateTime? _liveAt;

  static const List<String> _steps = [
    'Order placed',
    'Processing',
    'Out for delivery',
    'Delivered',
  ];
  static const List<IconData> _icons = [
    Icons.shopping_bag_outlined,
    Icons.restaurant_outlined,
    Icons.delivery_dining_rounded,
    Icons.check_circle_outline_rounded,
  ];

  @override
  void initState() {
    super.initState();
    _listen();
  }

  Future<void> _listen() async {
    await DeliveryTrackingSocket.instance.ensureConnected();
    _sub = DeliveryTrackingSocket.instance.updates.listen((u) {
      if (!_matches(u) || !mounted) return;
      setState(() {
        _live = u;
        _liveAt = DateTime.now();
      });
    });
  }

  bool _matches(DeliveryLocationUpdate u) {
    final o = widget.order;
    if (u.orderId != null && u.orderId!.isNotEmpty) {
      return u.orderId == o.id;
    }
    if (u.customerIdForOrder != null && u.customerIdForOrder!.isNotEmpty) {
      return u.customerIdForOrder == o.customerId;
    }
    return false;
  }

  String _formatLiveAgo(DateTime t) {
    final sec = DateTime.now().difference(t).inSeconds;
    if (sec < 10) return 'just now';
    if (sec < 60) return '${sec}s ago';
    final m = sec ~/ 60;
    if (m < 60) return '${m}m ago';
    return '${m ~/ 60}h ago';
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final status = order.status.toLowerCase();
    int currentStep = 1;
    if (status == 'pending' || status == 'assigned') {
      currentStep = 1;
    } else if (status == 'processing' ||
        status == 'cooking' ||
        status == 'to_process')
      // ignore: curly_braces_in_flow_control_structures
      currentStep = 2;
    else if (status == 'out_for_delivery' || status == 'in_transit')
      // ignore: curly_braces_in_flow_control_structures
      currentStep = 3;
    else if (status == 'delivered')
      // ignore: curly_braces_in_flow_control_structures
      currentStep = 4;

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _green100,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  size: 20,
                  color: _green700,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                tr('orderStatus'),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: _text1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (status == 'skipped' ||
              status == 'cancelled' ||
              status == 'failed')
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                trf('orderCancelledOn', {
                  'date': DateFormat('EEE, d MMM yyyy').format(DateTime(order.date.toUtc().year, order.date.toUtc().month, order.date.toUtc().day)),
                }),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _danger,
                ),
              ),
            )
          else
            ...List.generate(4, (i) {
            final done = (i + 1) <= currentStep;
            final active = (i + 1) == currentStep;
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: done ? _green600 : _green50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: done ? _green600 : _border,
                        width: active ? 2 : 1,
                      ),
                    ),
                    child: Icon(
                      done ? Icons.check_rounded : _icons[i],
                      size: 17,
                      color: done ? Colors.white : _text2,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _steps[i],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: done ? FontWeight.w700 : FontWeight.w400,
                      color: done ? _text1 : _text2,
                    ),
                  ),
                  if (active) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _violet100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Now',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _violet600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
          if (status == 'out_for_delivery' || status == 'in_transit') ...[
            const SizedBox(height: 4),
            if (order.deliveryStaffName != null ||
                order.deliveryStaffPhone != null)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _green50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: _green100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.delivery_dining_rounded,
                        size: 20,
                        color: _green700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.deliveryStaffName ?? 'Delivery partner',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _text1,
                            ),
                          ),
                          if (order.deliveryStaffPhone != null)
                            Text(
                              order.deliveryStaffPhone!,
                              style: TextStyle(
                                fontSize: 11,
                                color: _text2,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (order.deliveryStaffPhone?.isNotEmpty == true)
                      GestureDetector(
                        onTap: () => launchUrl(
                          Uri.parse(
                            'tel:${order.deliveryStaffPhone!.replaceAll(RegExp(r'\D'), '')}',
                          ),
                        ),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: _violet100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.call_rounded,
                            size: 17,
                            color: _violet600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (_live != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _violet50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.radar_rounded, size: 20, color: _violet600),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Live rider location',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _text1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_liveAt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, left: 30),
                        child: Text(
                          'Updated ${_formatLiveAgo(_liveAt!)}',
                          style: TextStyle(fontSize: 11, color: _text2),
                        ),
                      ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => LocationHelper.openInMaps(
                        _live!.lat,
                        _live!.lng,
                      ),
                      icon: const Icon(Icons.map_rounded, size: 18),
                      label: Text(
                        'Open rider on map',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _violet600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _violet600,
                        side: BorderSide(
                          color: _violet600.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: _text2),
            child: const Text(
              'Close',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Wallet Tab
// ─────────────────────────────────────────────────────────────────────────────

class _CustomerWalletTab extends StatefulWidget {
  const _CustomerWalletTab();
  @override
  State<_CustomerWalletTab> createState() => _CustomerWalletTabState();
}

class _CustomerWalletTabState extends State<_CustomerWalletTab> {
  CustomerBalanceModel? _balance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final balance = await CustomerPortalApi.getMyBalance();
      if (mounted) setState(() => _balance = balance);
    } catch (e) {
      if (mounted) ErrorHandler.show(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: _green600));
    }
    final walletBalance = _balance?.walletBalance ?? 0.0;
    final subscriptionBalance = _balance?.subscriptionBalance ?? 0.0;
    final lowBalance = walletBalance < 100;

    return RefreshIndicator(
      color: _green600,
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          20,
          16,
          MediaQuery.of(context).padding.bottom + 32,
        ),
        children: [
          _sectionLabel('Current Balance'),
          const SizedBox(height: 10),
          // Balance hero
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border),
              boxShadow: [
                BoxShadow(
                  color: _green900.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _violet100,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.account_balance_wallet_rounded,
                    size: 26,
                    color: _violet600,
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rs.${walletBalance.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: _violet700,
                      ),
                    ),
                    Text(
                      'Available balance',
                      style: TextStyle(fontSize: 12, color: _text2),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (lowBalance && walletBalance >= 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _warnSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: _warning,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Low balance. Please top up to continue service.',
                      style: TextStyle(
                        fontSize: 12,
                        color: _warning,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          _sectionLabel('Subscription Balance'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _green50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _border),
                  ),
                  child: Icon(
                    Icons.subscriptions_rounded,
                    size: 18,
                    color: _green700,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Rs.${subscriptionBalance.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _text1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _sectionLabel('Transaction History'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _green50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _border),
                  ),
                  child: Icon(
                    Icons.receipt_outlined,
                    size: 18,
                    color: _text2,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'No transactions yet.',
                  style: TextStyle(fontSize: 13, color: _text2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Row(
    children: [
      Container(
        width: 3,
        height: 13,
        decoration: BoxDecoration(
          color: _green600,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 7),
      Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: _text2,
          letterSpacing: 1.1,
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile Tab
// ─────────────────────────────────────────────────────────────────────────────

class _CustomerProfileTab extends StatefulWidget {
  const _CustomerProfileTab();
  @override
  State<_CustomerProfileTab> createState() => _CustomerProfileTabState();
}

class _CustomerProfileTabState extends State<_CustomerProfileTab> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  CustomerModel? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final profile = await CustomerPortalApi.getMyProfile();
      if (mounted) {
        _profile = profile;
        _nameCtrl.text = profile.name;
        _addressCtrl.text = profile.address ?? '';
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.show(context, e);
        setState(() => _loading = false);
      }
    }
  }

  // ignore: unused_element
  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    try {
      await CustomerPortalApi.updateMyProfile({
        'name': _nameCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
      });
      if (mounted) AppSnackbar.success(context, 'Profile updated');
    } catch (e) {
      if (mounted) ErrorHandler.show(context, e);
    } finally {
      // ignore: empty_statements
      if (mounted) ;
    }
  }

  Future<void> _shareLocation() async {
    final position = await LocationHelper.getCurrentPosition();
    if (position == null || !mounted) return;
    try {
      await CustomerPortalApi.updateMyProfile({
        'location': {
          'type': 'Point',
          'coordinates': [position.longitude, position.latitude],
        },
      });
      if (mounted) AppSnackbar.success(context, 'Location shared with vendor');
    } catch (e) {
      if (mounted) ErrorHandler.show(context, e);
    }
  }

  Future<void> _logout() async {
    try {
      await AuthApi.logout();
    } catch (_) {}
    await AuthSession.clearLocalSession();
    if (!mounted) return;
    context.go(AppRoutes.roleSelection);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: _green600));
    }
    final initial = (_profile?.name ?? '?')[0].toUpperCase();

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        20,
        16,
        MediaQuery.of(context).padding.bottom + 40,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Identity card ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border),
              boxShadow: [
                BoxShadow(
                  color: _green900.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _green100,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _border),
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _green700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _profile?.name ?? '',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _text1,
                        ),
                      ),
                      if (_profile?.phone != null)
                        Text(
                          _profile!.phone,
                          style: TextStyle(fontSize: 12, color: _text2),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Share location ─────────────────────────────────────────────────
          InkWell(
            onTap: _shareLocation,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: _green50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _green100,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _green200),
                    ),
                    child: Icon(
                      Icons.my_location_rounded,
                      size: 18,
                      color: _green700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('shareLocation'),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _green900,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          tr('shareLocationSub'),
                          style: TextStyle(fontSize: 11, color: _text2),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: _text2,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          Consumer(
            builder: (context, ref, _) {
              final dark = ref.watch(themeModeProvider) == ThemeMode.dark;
              return InkWell(
                onTap: () => ref.read(themeModeProvider.notifier).toggle(),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _violet100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          dark ? Icons.light_mode_rounded : Icons.dark_mode_outlined,
                          size: 18,
                          color: _violet700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr('darkMode'),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: _text1,
                              ),
                            ),
                            Text(
                              dark ? tr('on') : tr('off'),
                              style: TextStyle(fontSize: 11, color: _text2),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: dark,
                        activeThumbColor: Colors.white,
                        activeTrackColor: _violet600,
                        onChanged: (_) =>
                            ref.read(themeModeProvider.notifier).toggle(),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 12),
          const LanguagePickerTile(),
          const SizedBox(height: 12),

          // ── Logout ─────────────────────────────────────────────────────────
          InkWell(
            onTap: _logout,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: _dangerSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _danger.withValues(alpha: 0.22)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout_rounded, size: 16, color: _danger),
                  const SizedBox(width: 8),
                  Text(
                    tr('logout'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _danger,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _greenField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    String? Function(String?)? validator,
    int maxLines = 1,
  }) => TextFormField(
    controller: ctrl,
    validator: validator,
    maxLines: maxLines,
    style: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: _text1,
    ),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: 13, color: _text2),
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 14, right: 10),
        child: Icon(icon, size: 18, color: _green700),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      filled: true,
      fillColor: _green50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide(color: _green600, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide(color: _danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide(color: _danger, width: 1.5),
      ),
    ),
  );

  // ignore: unused_element
  Widget _sectionLabel(String text) => Row(
    children: [
      Container(
        width: 3,
        height: 13,
        decoration: BoxDecoration(
          color: _green600,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 7),
      Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: _text2,
          letterSpacing: 1.1,
        ),
      ),
    ],
  );
}
