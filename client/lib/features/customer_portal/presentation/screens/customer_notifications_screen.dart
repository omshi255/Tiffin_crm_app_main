import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/widgets/app_list_pager.dart';
import '../../../../models/notification_model.dart';
import '../../data/customer_portal_api.dart';
import '../../../../core/notifications/notification_badge_service.dart';
import '../../../../l10n/app_lang.dart';

class CustomerNotificationsScreen extends StatefulWidget {
  const CustomerNotificationsScreen({super.key});

  @override
  State<CustomerNotificationsScreen> createState() =>
      _CustomerNotificationsScreenState();
}

class _CustomerNotificationsScreenState
    extends State<CustomerNotificationsScreen> {
  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  Color get _green900 => _dark ? const Color(0xFFDDD6FE) : const Color(0xFF2D1B69);
  Color get _green700 => _dark ? const Color(0xFF9B6AF0) : const Color(0xFF4C2DB8);
  Color get _green600 => _dark ? const Color(0xFFB794F6) : const Color(0xFF5B35D5);
  Color get _green100 => _dark ? const Color(0xFF2A2348) : const Color(0xFFEDE8FD);
  Color get _green50 => _dark ? const Color(0xFF1E1B3A) : const Color(0xFFF5F2FF);
  Color get _violet600 => _dark ? const Color(0xFFB794F6) : const Color(0xFF5B35D5);
  Color get _violet100 => _dark ? const Color(0xFF2A2348) : const Color(0xFFEDE8FD);
  Color get _bg => _dark ? const Color(0xFF0E1020) : const Color(0xFFF6F4FF);
  Color get _surface => _dark ? const Color(0xFF141625) : const Color(0xFFFFFFFF);
  Color get _border => _dark ? const Color(0xFF2F2A55) : const Color(0xFFE4DFF7);
  Color get _text1 => _dark ? const Color(0xFFF8FAFC) : const Color(0xFF1A0E45);
  Color get _text2 => _dark ? const Color(0xFF94A3B8) : const Color(0xFF7B6DAB);
  Color get _warning => const Color(0xFFBA7517);
  Color get _dangerBg => _dark ? const Color(0xFF2A1210) : const Color(0xFFFCEBEB);
  Color get _dangerText => _dark ? const Color(0xFFF3B4B4) : const Color(0xFF8C2020);
  Color get _dangerIcon => _dark ? const Color(0xFFF09595) : const Color(0xFFC0392B);
  Color get _warnSoft => _dark ? const Color(0xFF2A2110) : const Color(0xFFFAEEDA);

  // ── State ──────────────────────────────────────────────────────────────────
  List<NotificationModel> _notifications = [];
  bool _loading = true;
  int _page = 1;
  int _total = 0;

  // ── API (unchanged) ────────────────────────────────────────────────────────
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await CustomerPortalApi.getMyNotifications(
        page: _page,
        limit: kListPageSize,
      );
      if (mounted) {
        setState(() {
          final raw =
              (res['notifications'] as List<NotificationModel>?) ?? [];
          _notifications = _dedupeVendorAnnouncements(raw);
          _total = (res['total'] as num?)?.toInt() ?? _notifications.length;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) { setState(() => _loading = false); ErrorHandler.show(context, e); }
    }
  }

  /// Collapses duplicate vendor broadcast rows (same title+body), keeps first (newest from API order).
  static List<NotificationModel> _dedupeVendorAnnouncements(
    List<NotificationModel> list,
  ) {
    final seen = <String>{};
    final out = <NotificationModel>[];
    for (final n in list) {
      final t = (n.type ?? '').toLowerCase();
      if (t == 'vendor_announcement') {
        final key = '${n.title}|${n.body}';
        if (seen.contains(key)) continue;
        seen.add(key);
      }
      out.add(n);
    }
    return out;
  }

  Future<void> _markAllRead() async {
    try {
      await CustomerPortalApi.markAllNotificationsRead();
      await NotificationBadgeService.refreshNow();
    } catch (_) {}
  }

  Future<void> _delete(NotificationModel n) async {
    try {
      await CustomerPortalApi.deleteNotification(n.id);
      // ignore: curly_braces_in_flow_control_structures
      if (mounted) setState(() =>
          _notifications = _notifications.where((e) => e.id != n.id).toList());
      await NotificationBadgeService.refreshNow();
    } catch (e) {
      if (mounted) ErrorHandler.show(context, e);
    }
  }

  Future<void> _clearRead() async {
    try {
      await CustomerPortalApi.clearReadNotifications();
      await _load();
      await NotificationBadgeService.refreshNow();
    } catch (e) {
      if (mounted) ErrorHandler.show(context, e);
    }
  }

  Future<void> _markRead(NotificationModel n) async {
    if (n.read) return;
    try {
      await CustomerPortalApi.markNotificationRead(n.id);
      if (mounted) {
        setState(() {
          _notifications = _notifications.map((e) => e.id == n.id
              ? NotificationModel(id: e.id, title: e.title, body: e.body,
                  time: e.time, read: true, type: e.type)
              : e).toList();
        });
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _markAllRead();
    _load();
  }

  String? _leaveDateLabel(NotificationModel n) {
    final raw = n.data?['leaveDate']?.toString();
    if (raw == null || raw.length < 10) return null;
    final parts = raw.substring(0, 10).split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateFormat('EEE, d MMM yyyy').format(DateTime(year, month, day));
  }

  String _formatTime(DateTime t) {
    final now  = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    if (diff.inDays < 7)     return '${diff.inDays}d ago';
    return '${t.day}/${t.month}/${t.year}';
  }

  String _stripEmojis(String text) => text.replaceAll(RegExp(
    r'[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}'
    r'\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{FE00}-\u{FE0F}'
    r'\u{1F900}-\u{1F9FF}\u{200D}\u{20E3}]',
    unicode: true), '').trim();

  // ── Type styling ───────────────────────────────────────────────────────────
  _NotifStyle _styleForType(String? type) {
    switch ((type ?? '').toLowerCase()) {
      case 'out_for_delivery':
        return _NotifStyle(label: 'Out for Delivery',
          pillBg: _warnSoft, pillText: _warning,
          iconBg: _warnSoft, iconColor: _warning,
          dotColor: _warning, icon: Icons.delivery_dining_rounded);
      case 'delivered':
        return _NotifStyle(label: 'Delivered',
          pillBg: _violet100, pillText: _violet600,
          iconBg: _violet100, iconColor: _violet600,
          dotColor: _violet600, icon: Icons.check_circle_outline_rounded);
      case 'order_processing':
        return _NotifStyle(label: 'Preparing',
          pillBg: _dark ? const Color(0xFF2A2110) : const Color(0xFFFFF8E1),
          pillText: _dark ? const Color(0xFFF3D48A) : const Color(0xFF6B4C00),
          iconBg: _dark ? const Color(0xFF2A2110) : const Color(0xFFFFF8E1),
          iconColor: const Color(0xFFD4A017),
          dotColor: const Color(0xFFD4A017), icon: Icons.restaurant_outlined);
      case 'order_placed':
        return _NotifStyle(label: 'Order Placed',
          pillBg: _green100, pillText: _green700,
          iconBg: _green100, iconColor: _green700,
          dotColor: _green600, icon: Icons.shopping_bag_outlined);
      case 'payment': case 'wallet':
        return _NotifStyle(label: 'Payment',
          pillBg: _green100, pillText: _green700,
          iconBg: _green100, iconColor: _green700,
          dotColor: _green600, icon: Icons.account_balance_wallet_outlined);
      case 'cancelled':
        return _NotifStyle(label: 'Cancelled',
          pillBg: _dangerBg, pillText: _dangerText,
          iconBg: _dangerBg, iconColor: _dangerIcon,
          dotColor: _dangerIcon, icon: Icons.cancel_outlined);
      case 'system': case 'alert':
        return _NotifStyle(label: 'Alert',
          pillBg: _dangerBg, pillText: _dangerText,
          iconBg: _dangerBg, iconColor: _dangerIcon,
          dotColor: _dangerIcon, icon: Icons.warning_amber_rounded);
      case 'leave_approved':
        return _NotifStyle(
          label: 'Leave approved',
          pillBg: _green100,
          pillText: _green700,
          iconBg: _green100,
          iconColor: _green700,
          dotColor: _green600,
          icon: Icons.event_available_rounded,
        );
      case 'leave_rejected':
        return _NotifStyle(
          label: 'Leave rejected',
          pillBg: _dangerBg,
          pillText: _dangerText,
          iconBg: _dangerBg,
          iconColor: _dangerIcon,
          dotColor: _dangerIcon,
          icon: Icons.event_busy_rounded,
        );
      case 'vendor_holiday':
        return _NotifStyle(
          label: 'Vendor holiday',
          pillBg: _violet100,
          pillText: _violet600,
          iconBg: _violet100,
          iconColor: _violet600,
          dotColor: _violet600,
          icon: Icons.beach_access_rounded,
        );
      case 'vendor_announcement':
        return _NotifStyle(
          label: 'Announcement',
          pillBg: _violet100,
          pillText: _violet600,
          iconBg: _violet100,
          iconColor: _violet600,
          dotColor: _violet600,
          icon: Icons.campaign_rounded,
        );
      default:
        return _NotifStyle(label: 'Notification',
          pillBg: _green50, pillText: _green700,
          iconBg: _green50, iconColor: _green700,
          dotColor: _green600, icon: Icons.notifications_outlined);
    }
  }

  // ── Group helpers ──────────────────────────────────────────────────────────
  String _groupLabel(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 60) return 'Just Now';
    if (diff.inHours < 24)   return 'Today';
    if (diff.inDays == 1)    return 'Yesterday';
    if (diff.inDays < 7)     return '${diff.inDays} Days Ago';
    return '${t.day}/${t.month}/${t.year}';
  }

  List<_NotifGroup> _buildGroups() {
    final map   = <String, List<NotificationModel>>{};
    final order = <String>[];
    for (final n in _notifications) {
      final label = _groupLabel(n.time);
      if (!map.containsKey(label)) { map[label] = []; order.add(label); }
      map[label]!.add(n);
    }
    return order.map((l) => _NotifGroup(label: l, items: map[l]!)).toList();
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications.where((n) => !n.read).length;
    final hasRead     = _notifications.any((n) => n.read);

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
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop()),
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('notifications'),
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                color: Colors.white, letterSpacing: 0.2)),
          if (unreadCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(20)),
              child: Text('$unreadCount',
                style: const TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w700, color: Colors.white))),
          ],
        ]),
        actions: [
          if (hasRead)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded,
                  color: Colors.white70, size: 24),
              tooltip: 'Clear all read',
              onPressed: _clearRead),
        ],
      ),
      body: _loading && _notifications.isEmpty
          ? Center(child: CircularProgressIndicator(
              color: _green600, strokeWidth: 2.5))
          : RefreshIndicator(
              color: _green600,
              onRefresh: _load,
              child: _notifications.isEmpty
                  ? _buildEmpty()
                  : _buildList(),
            ),
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────
  Widget _buildEmpty() => ListView(
    padding: EdgeInsets.fromLTRB(
      24,
      24,
      24,
      MediaQuery.of(context).padding.bottom + 24,
    ),
    children: [
      const SizedBox(height: 80),
      Center(child: Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          color: _green100, borderRadius: BorderRadius.circular(20)),
        child: Icon(Icons.notifications_none_rounded,
            size: 36, color: _green700))),
      const SizedBox(height: 16),
      Text(tr('noNotifications'),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
            color: _text1)),
      const SizedBox(height: 6),
      Text(tr('mealUpdatesAppear'),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: _text2)),
    ],
  );

  // ── List ───────────────────────────────────────────────────────────────────
  Widget _buildList() {
    final groups = _buildGroups();
    return ListView.builder(
      padding: EdgeInsets.only(
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      itemCount: groups.length + (_total > kListPageSize ? 1 : 0),
      itemBuilder: (context, gi) {
        if (gi >= groups.length) {
          return AppListPager(
            page: _page,
            total: _total,
            onPage: (p) {
              setState(() => _page = p);
              _load();
            },
          );
        }
        final group = groups[gi];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(left: 46, top: 14, bottom: 6),
            child: Text(group.label.toUpperCase(),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  color: _text2, letterSpacing: 1.0))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: List.generate(group.items.length, (ii) =>
              _buildRow(group.items[ii], ii == group.items.length - 1)))),
        ]);
      },
    );
  }

  // ── Notification row ───────────────────────────────────────────────────────
  Widget _buildRow(NotificationModel n, bool isLast) {
    final style      = _styleForType(n.type);
    final isRead     = n.read;
    final cleanTitle = _stripEmojis(n.title);
    final cleanBody  = _stripEmojis(n.body);
    final dateLabel  = _leaveDateLabel(n);

    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Timeline
        SizedBox(width: 22, child: Stack(children: [
          if (!isLast)
            Positioned(top: 20, bottom: 0, left: 10,
              child: Container(width: 1.5,
                  color: _border)),
          Positioned(top: 10, left: 6,
            child: Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: style.dotColor,
                border: Border.all(color: _bg, width: 2)))),
        ])),
        const SizedBox(width: 8),

        // Card
        Expanded(
          child: GestureDetector(
            onTap: () => _markRead(n),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 12),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isRead ? _border : style.dotColor.withValues(alpha: 0.55),
                  width: isRead ? 1.0 : 1.5),
                boxShadow: [BoxShadow(
                  color: _green900.withValues(alpha: 0.04),
                  blurRadius: 6, offset: const Offset(0, 2))]),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Icon
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: style.iconBg,
                    borderRadius: BorderRadius.circular(12)),
                  child: Icon(style.icon, size: 20, color: style.iconColor)),
                const SizedBox(width: 10),

                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Type pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: style.pillBg,
                        borderRadius: BorderRadius.circular(10)),
                      child: Text(style.label,
                        style: TextStyle(fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: style.pillText))),
                    const SizedBox(height: 5),
                    // Title
                    Text(cleanTitle, style: TextStyle(
                      fontSize: 13,
                      fontWeight: isRead ? FontWeight.w600 : FontWeight.w700,
                      color: _text1)),
                    if (dateLabel != null) ...[
                      const SizedBox(height: 3),
                      Text(dateLabel, style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _green700)),
                    ],
                    const SizedBox(height: 3),
                    // Body
                    Text(cleanBody, style: TextStyle(
                      fontSize: 12, color: _text2, height: 1.4)),
                  ])),

                const SizedBox(width: 6),
                // Time + delete
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatTime(n.time),
                      style: TextStyle(fontSize: 10, color: _text2)),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => _delete(n),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.delete_outline_rounded,
                          size: 15, color: _text2.withValues(alpha: 0.5)))),
                  ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Data classes ───────────────────────────────────────────────────────────────

class _NotifGroup {
  final String label;
  final List<NotificationModel> items;
  const _NotifGroup({required this.label, required this.items});
}

class _NotifStyle {
  final String   label;
  final Color    pillBg, pillText, iconBg, iconColor, dotColor;
  final IconData icon;
  const _NotifStyle({
    required this.label, required this.pillBg, required this.pillText,
    required this.iconBg, required this.iconColor, required this.dotColor,
    required this.icon,
  });
}