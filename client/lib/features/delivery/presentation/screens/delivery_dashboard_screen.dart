import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/auth/auth_session.dart';
import '../../../../core/delivery/staff_location_sync.dart';
import '../../../../core/socket/delivery_tracking_socket.dart';
import '../../../../core/utils/color_utils.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/widgets/app_list_pager.dart';
import '../../../../core/utils/location_helper.dart';
import '../../../../core/routing/nominatim_geocode_service.dart';
import '../../../../core/utils/whatsapp_helper.dart';
import '../../../../core/widgets/notification_bell_icon.dart';
import '../../../../l10n/app_lang.dart';
import '../../data/delivery_api.dart';
import '../../../auth/data/auth_api.dart';
import '../../../orders/data/order_api.dart';
import '../../../orders/models/order_model.dart';
import '../../../orders/models/order_status.dart';
import 'delivery_map_screen.dart';
import '../models/delivery_map_session.dart';
import 'delivery_profile_screen.dart';

class DeliveryDashboardScreen extends StatefulWidget {
  const DeliveryDashboardScreen({super.key});

  @override
  State<DeliveryDashboardScreen> createState() =>
      _DeliveryDashboardScreenState();
}

class _DeliveryDashboardScreenState extends State<DeliveryDashboardScreen> {
  // Vendor dashboard palette
  static const _violet900 = Color(0xFF3B1578);
  static const _violet800 = Color(0xFF6B35C8);
  static const _violet700 = AppColors.primary;
  static const _violet600 = AppColors.primary;
  static const _violet500 = Color(0xFF9B6AF0);
  static const _violet200 = Color(0xFFDDD6FE);
  static const _violet100 = Color(0xFFEDE9FE);
  static const _violet50 = Color(0xFFF5F3FF);

  static const _amber700 = Color(0xFF92400E);
  static const _amber600 = Color(0xFFD97706);
  static const _amber400 = Color(0xFFFCD34D);
  static const _amber100 = Color(0xFFFFFBEB);
  static const _amber50 = Color(0xFFFFFBEB);

  static const _gradStart = AppColors.primary;
  static const _gradMid = Color(0xFF6B35C8);
  static const _gradEnd = Color(0xFF3B1578);

  static const _bg = Color(0xFFF8FAFC);
  static const _surface = Color(0xFFFFFFFF);
  static const _border = Color(0xFFE2E8F0);
  static const _divider = Color(0xFFF1F5F9);
  static const _textPrimary = Color(0xFF1F1535);
  static const _textSecondary = Color(0xFF6B7280);

  static const _success = Color(0xFF059669);
  static const _successSoft = Color(0xFFD1FAE5);
  static const _danger = Color(0xFFDC2626);
  static const _dangerSoft = Color(0xFFFEE2E2);

  // ── State ─────────────────────────────────────────────────────────────────
  List<OrderModel> _orders = [];
  bool _loading = true;
  String? _statusFilter;
  bool _updatingLocation = false;
  int _selectedTab = 0;
  Timer? _locationTimer;
  DeliveryMapSession? _mapSession;

  static const List<String?> _filterValues = [
    null,
    'pending',
    'processing',
    'out_for_delivery',
    'delivered',
  ];
  static const List<String> _filterKeys = [
    'all',
    'pending',
    'processing',
    'outForDelivery',
    'delivered',
  ];

  @override
  void initState() {
    super.initState();
    _load();
    DeliveryTrackingSocket.instance.ensureConnected();
    _locationTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      _updateLocationSilent();
    });
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<void> _updateLocationSilent() async {
    try {
      final position = await LocationHelper.getCurrentPosition();
      if (position == null || !mounted) return;
      await StaffLocationSync.pushFromPosition(position, _orders);
    } catch (_) {}
  }

  Future<void> _openCustomerRouteOnMap(
    BuildContext sheetContext,
    OrderModel order,
  ) async {
    final address = order.customerAddress?.trim();
    if (address == null || address.isEmpty) {
      if (sheetContext.mounted) {
        AppSnackbar.error(sheetContext, 'Could not find customer location');
      }
      return;
    }
    try {
      final pt = await NominatimGeocodeService.searchFirst(address);
      if (!sheetContext.mounted) return;
      if (pt == null) {
        AppSnackbar.error(sheetContext, 'Could not find customer location');
        return;
      }
      Navigator.pop(sheetContext);
      setState(() {
        _mapSession = DeliveryMapSession.singleRoute(
          customerPoint: pt,
          customerName: order.customerName ?? order.customerId,
        );
        _selectedTab = 1;
      });
    } catch (_) {
      if (sheetContext.mounted) {
        AppSnackbar.error(sheetContext, 'Could not find customer location');
      }
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await DeliveryApi.getMyDeliveries();
      if (mounted) setState(() => _orders = list);
    } catch (e) {
      if (mounted) ErrorHandler.show(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<OrderModel> get _filteredOrders {
    if (_statusFilter == null) return _orders;
    return _orders.where((o) => o.status == _statusFilter).toList();
  }

  Future<void> _shareMyLocation() async {
    setState(() => _updatingLocation = true);
    try {
      final position = await LocationHelper.getCurrentPosition();
      if (position == null || !mounted) return;
      await StaffLocationSync.pushFromPosition(position, _orders);
      if (mounted) AppSnackbar.success(context, 'Location shared');
    } catch (e) {
      if (mounted) ErrorHandler.show(context, e);
    } finally {
      if (mounted) setState(() => _updatingLocation = false);
    }
  }

  Future<void> _logout() async {
    final router = GoRouter.of(context);
    await AuthApi.logout();
    await AuthSession.clearLocalSession();
    if (!mounted) return;
    router.go(AppRoutes.roleSelection);
  }

  void _showOrderSheet(OrderModel order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _OrderActionSheet(
        order: order,
        onAccept: () async {
          try {
            await OrderApi.accept(order.id);
            await OrderApi.updateStatus(order.id, 'out_for_delivery');
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          } catch (e) {
            if (ctx.mounted) ErrorHandler.show(ctx, e);
          }
        },
        onReject: () async {
          final reason = await showDialog<String>(
            context: ctx,
            builder: (c) {
              final controller = TextEditingController();
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                title: Text(
                  tr('rejectDelivery'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                content: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: tr('reasonOptional'),
                    hintText: tr('reasonHint'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  maxLines: 2,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: Text(tr('cancel')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(c, controller.text.trim()),
                    style: FilledButton.styleFrom(backgroundColor: _danger),
                    child: Text(tr('reject')),
                  ),
                ],
              );
            },
          );
          if (reason == null) return;
          try {
            await OrderApi.reject(
              order.id,
              reason: reason.isEmpty ? 'Rejected' : reason,
            );
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          } catch (e) {
            if (ctx.mounted) ErrorHandler.show(ctx, e);
          }
        },
        onStartDelivery: () async {
          try {
            await OrderApi.updateStatus(order.id, 'out_for_delivery');
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          } catch (e) {
            if (ctx.mounted) ErrorHandler.show(ctx, e);
          }
        },
        onMarkDelivered: () async {
          try {
            await OrderApi.updateStatus(order.id, 'delivered');
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          } catch (e) {
            if (ctx.mounted) ErrorHandler.show(ctx, e);
          }
        },
        onWhatsApp: () {
          final phone = order.customerPhone;
          if (phone != null && phone.isNotEmpty) WhatsAppHelper.openChat(phone);
        },
        onCall: () {
          final phone = order.customerPhone;
          if (phone != null && phone.isNotEmpty) {
            WhatsAppHelper.callPhone(phone);
          }
        },
        onOpenMaps: () => _openCustomerRouteOnMap(ctx, order),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final filtered = _filteredOrders;
    final tabTitles = [tr('myTasks'), tr('mapView'), tr('profile')];

    final dark = Theme.of(context).brightness == Brightness.dark;
    final pageBg = dark ? const Color(0xFF0E1020) : _bg;
    final navBg = dark ? const Color(0xFF141625) : _surface;
    final navLine = dark ? const Color(0xFF1E1B3A) : _border;

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_gradStart, _gradMid, _gradEnd],
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          tabTitles[_selectedTab],
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.12),
          ),
        ),
        actions: [
          NotificationBellIcon(
            iconColor: Colors.white,
            onPressed: () => context.push(AppRoutes.notifications),
          ),
          if (_selectedTab == 0) ...[
            IconButton(
              icon: _updatingLocation
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const PhosphorIcon(
                      PhosphorIconsRegular.mapPin,
                      size: 20,
                      color: Colors.white,
                    ),
              tooltip: 'Share my location',
              onPressed: _updatingLocation ? null : _shareMyLocation,
            ),
            IconButton(
              icon: const PhosphorIcon(
                PhosphorIconsRegular.arrowsClockwise,
                size: 20,
                color: Colors.white,
              ),
              onPressed: _loading ? null : _load,
            ),
            PopupMenuButton<void>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              itemBuilder: (_) => [
                PopupMenuItem(
                  onTap: _logout,
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _dangerSoft,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.logout_rounded,
                          size: 16,
                          color: _danger,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Logout',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _danger,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (_selectedTab == 0) _tasksToolbar(dark),
          Expanded(
            child: IndexedStack(
        index: _selectedTab,
        children: [
          RepaintBoundary(child: _buildTasksBody(filtered)),
          RepaintBoundary(
            child: DeliveryMapScreen(
              showAppBar: false,
              orders: _orders,
              session: _mapSession,
            ),
          ),
          const RepaintBoundary(
            child: DeliveryProfileScreen(),
          ),
        ],
            ),
          ),
        ],
      ),

      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: navBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: navLine),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: dark ? 0.16 : 0.08),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavTab(
                  icon: PhosphorIconsRegular.clipboardText,
                  iconFill: PhosphorIconsFill.clipboardText,
                  label: tr('tasks'),
                  selected: _selectedTab == 0,
                  badge: _orders
                      .where(
                        (o) => o.status == 'pending' || o.status == 'assigned',
                      )
                      .length,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _selectedTab = 0;
                      _mapSession = null;
                    });
                  },
                ),
                _NavTab(
                  icon: PhosphorIconsRegular.mapTrifold,
                  iconFill: PhosphorIconsFill.mapTrifold,
                  label: tr('map'),
                  selected: _selectedTab == 1,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedTab = 1);
                  },
                ),
                _NavTab(
                  icon: PhosphorIconsRegular.user,
                  iconFill: PhosphorIconsFill.user,
                  label: tr('profile'),
                  selected: _selectedTab == 2,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedTab = 2);
                  },
                ),
              ],
            ),
          ),
        ),
      ),

      floatingActionButton: _selectedTab == 0
          ? FloatingActionButton.extended(
              heroTag: 'delivery_staff_fab_view_map',
              onPressed: () {
                HapticFeedback.lightImpact();
                setState(() {
                  _mapSession = const DeliveryMapSession.multiOnWay();
                  _selectedTab = 1;
                });
              },
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              icon: const PhosphorIcon(
                PhosphorIconsRegular.mapTrifold,
                size: 18,
              ),
              label: Text(
                tr('viewOnMap'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            )
          : null,
    );
  }

  int _countFor(String? status) {
    if (status == null) return _orders.length;
    if (status == 'pending') {
      return _orders
          .where((o) => o.status == 'pending' || o.status == 'assigned')
          .length;
    }
    return _orders.where((o) => o.status == status).length;
  }

  Widget _tasksToolbar(bool dark) {
    final bar = dark ? const Color(0xFF141625) : _surface;
    final line = dark ? const Color(0xFF2F3347) : _border;
    final muted = dark ? const Color(0xFF94A3B8) : _textSecondary;
    return Container(
      color: bar,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_orders.length} ${tr('assignedToday')}',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(_filterKeys.length, (i) {
                final selected = _statusFilter == _filterValues[i];
                final count = _countFor(_filterValues[i]);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _statusFilter = _filterValues[i]);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary
                            : (dark ? const Color(0xFF1B1F2E) : _violet50),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected ? AppColors.primary : line,
                        ),
                      ),
                      child: Text(
                        '${tr(_filterKeys[i])}  $count',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : muted,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tasks body ────────────────────────────────────────────────────────────
  Widget _buildTasksBody(List<OrderModel> filtered) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: _violet600, strokeWidth: 2.5),
            const SizedBox(height: 12),
            Text(
              tr('loadingDeliveries'),
              style: TextStyle(color: _textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: _violet600,
      onRefresh: _load,
      child: filtered.isEmpty
          ? ListView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 24,
              ),
              children: [
                const SizedBox(height: 80),
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_violet100, _amber100],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: _violet200),
                        ),
                        child: const Icon(
                          Icons.inbox_outlined,
                          size: 36,
                          color: _violet600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        tr('noDeliveries'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tr('pullToRefresh'),
                        style: TextStyle(fontSize: 13, color: _textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : PagedListView<OrderModel>(
              padding: EdgeInsets.fromLTRB(
                0,
                12,
                0,
                MediaQuery.of(context).padding.bottom + 88,
              ),
              items: filtered,
              itemBuilder: (context, order, index) => RepaintBoundary(
                    child: _buildOrderCard(order),
                  ),
            ),
    );
  }

  // ── Order card ────────────────────────────────────────────────────────────
  Widget _buildOrderCard(OrderModel order) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final card = dark ? const Color(0xFF1B1F2E) : _surface;
    final line = dark ? const Color(0xFF2F3347) : _border;
    final ink = dark ? const Color(0xFFF8FAFC) : _textPrimary;
    final muted = dark ? const Color(0xFF94A3B8) : _textSecondary;
    final name = order.customerName ?? order.customerId;
    final initials = _getInitials(name);
    final statusMeta = _statusMeta(order.status);
    final slot = (order.slot?.trim().isNotEmpty == true)
        ? order.slot!.trim()
        : (order.mealTime?.trim().isNotEmpty == true ? order.mealTime!.trim() : '');
    final zone = order.zoneName?.trim() ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: card,
        elevation: 0,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            _showOrderSheet(order);
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: line),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: dark ? 0.08 : 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: dark ? const Color(0xFF2A2348) : _violet100,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: dark ? const Color(0xFFC4B5FD) : AppColors.primary,
                    ),
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
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusMeta.$2,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              statusMeta.$3,
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: statusMeta.$1,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (order.customerAddress != null &&
                          order.customerAddress!.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined, size: 14, color: muted),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                order.customerAddress!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(fontSize: 12, color: muted),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (slot.isNotEmpty || zone.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (slot.isNotEmpty)
                              _metaChip(Icons.schedule_rounded, slot, dark),
                            if (zone.isNotEmpty)
                              _metaChip(Icons.alt_route_rounded, zone, dark),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String label, bool dark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF241B42) : _violet50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: dark ? const Color(0xFFC4B5FD) : AppColors.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: dark ? const Color(0xFFDDD6FE) : const Color(0xFF5B35D5),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name[0].toUpperCase();
  }

  (Color, Color, String) _statusMeta(String status) {
    final o = OrderStatus.fromApi(status);
    switch (o) {
      case OrderStatus.pending:
        return (_amber600, _amber100, o.label);
      case OrderStatus.processing:
        return (_amber700, _amber50, o.label);
      case OrderStatus.outForDelivery:
        return (_violet600, _violet100, o.label);
      case OrderStatus.delivered:
        return (_success, _successSoft, o.label);
      case OrderStatus.cancelled:
        return (_danger, _dangerSoft, o.label);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom bottom nav tab
// ─────────────────────────────────────────────────────────────────────────────

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.icon,
    required this.iconFill,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final IconData iconFill;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  static const _violet600 = AppColors.primary;
  static const _violet100 = Color(0xFFEDE9FE);
  static const _textSecondary = Color(0xFF9CA3AF);

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: SizedBox(
      width: 80,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? (Theme.of(context).brightness == Brightness.dark
                          ? AppColors.primary.withValues(alpha: 0.18)
                          : _violet100)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: PhosphorIcon(
                  selected ? iconFill : icon,
                  size: 22,
                  color: selected ? _violet600 : _textSecondary,
                ),
              ),
              if (badge > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFD97706), Color(0xFFDC2626)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        badge > 9 ? '9+' : '$badge',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? _violet600 : _textSecondary,
            ),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Order action bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _OrderActionSheet extends StatelessWidget {
  const _OrderActionSheet({
    required this.order,
    required this.onAccept,
    required this.onReject,
    required this.onStartDelivery,
    required this.onMarkDelivered,
    required this.onWhatsApp,
    required this.onCall,
    required this.onOpenMaps,
  });

  final OrderModel order;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onStartDelivery;
  final VoidCallback onMarkDelivered;
  final VoidCallback onWhatsApp;
  final VoidCallback onCall;
  final VoidCallback onOpenMaps;

  static const _violet900 = Color(0xFF1E0A4A);
  static const _violet700 = Color(0xFF5B21B6);
  static const _violet600 = Color(0xFF7C3AED);
  static const _violet100 = Color(0xFFEDE9FE);
  static const _violet50 = Color(0xFFF5F3FF);
  static const _amber700 = Color(0xFFB45309);
  static const _amber600 = Color(0xFFD97706);
  static const _amber400 = Color(0xFFFBBF24);
  static const _amber100 = Color(0xFFFEF3C7);
  static const _amber50 = Color(0xFFFFFBEB);
  static const _surface = Color(0xFFFFFFFF);
  static const _border = Color(0xFFEDE9FE);
  static const _divider = Color(0xFFF0EBFF);
  static const _textPrimary = Color(0xFF1A0E45);
  static const _textSecondary = Color(0xFF7C6DAB);
  static const _success = Color(0xFF059669);
  static const _successSoft = Color(0xFFD1FAE5);
  static const _danger = Color(0xFFDC2626);
  static const _dangerSoft = Color(0xFFFEE2E2);

  @override
  Widget build(BuildContext context) {
    final status = order.status.toLowerCase();
    final needsAcceptReject =
        status == 'pending' || status == 'to_process' || status == 'assigned';
    final canStart =
        status != 'in_transit' &&
        status != 'delivered' &&
        status != 'out_for_delivery';
    final canDeliver = status == 'in_transit' || status == 'out_for_delivery';

    final dark = Theme.of(context).brightness == Brightness.dark;
    final sheet = dark ? const Color(0xFF1B1F2E) : _surface;
    final ink = dark ? const Color(0xFFF8FAFC) : _textPrimary;
    final muted = dark ? const Color(0xFF94A3B8) : _textSecondary;
    return Container(
      decoration: BoxDecoration(
        color: sheet,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle bar — amber tinted
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF3F3A5C) : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Customer info — violet/amber gradient header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF241B42) : _violet50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: dark ? const Color(0xFF3B2F66) : const Color(0xFFDDD6FE),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      _getInitials(order.customerName ?? order.customerId),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.customerName ?? order.customerId,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      if (order.customerAddress != null)
                        Text(
                          order.customerAddress!,
                          style: TextStyle(
                            fontSize: 12,
                            color: muted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_violet100, _amber100],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _violet600.withOpacity(0.2)),
                  ),
                  child: Text(
                    order.status.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: _violet700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Slot chip
          if (order.slot != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF241B42) : _violet50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: dark ? const Color(0xFF3B2F66) : const Color(0xFFDDD6FE),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.access_time_rounded,
                    size: 14,
                    color: dark ? const Color(0xFFC4B5FD) : AppColors.primary,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    '${tr('slot')}: ${order.slot}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: dark ? const Color(0xFFDDD6FE) : const Color(0xFF5B35D5),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),
          Divider(color: _divider, height: 1),
          const SizedBox(height: 16),

          // Accept / Reject
          if (needsAcceptReject) ...[
            Row(
              children: [
                Expanded(
                  child: _SheetButton(
                    label: tr('accept'),
                    icon: Icons.check_circle_outline_rounded,
                    bg: _successSoft,
                    fg: _success,
                    border: _success,
                    onTap: onAccept,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SheetButton(
                    label: tr('reject'),
                    icon: Icons.cancel_outlined,
                    bg: _dangerSoft,
                    fg: _danger,
                    border: _danger,
                    onTap: onReject,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],

          // Start delivery
          if (canStart && !needsAcceptReject) ...[
            _SheetButton(
              label: tr('startDelivery'),
              icon: Icons.delivery_dining_rounded,
              bg: _violet100,
              fg: _violet700,
              border: _violet600,
              onTap: onStartDelivery,
              filled: true,
            ),
            const SizedBox(height: 10),
          ],

          // Mark delivered
          if (canDeliver) ...[
            _SheetButton(
              label: tr('markDelivered'),
              icon: Icons.task_alt_rounded,
              bg: _successSoft,
              fg: _success,
              border: _success,
              onTap: onMarkDelivered,
              filled: true,
            ),
            const SizedBox(height: 10),
          ],

          // Contact row
          Row(
            children: [
              Expanded(
                child: _SheetButton(
                  label: tr('whatsapp'),
                  icon: Icons.chat_outlined,
                  bg: const Color(0xFFD1FAE5),
                  fg: const Color(0xFF065F46),
                  border: const Color(0xFF059669),
                  onTap: onWhatsApp,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SheetButton(
                  label: tr('call'),
                  icon: Icons.phone_outlined,
                  bg: _violet50,
                  fg: _violet600,
                  border: _violet600,
                  onTap: onCall,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SheetButton(
                  label: tr('maps'),
                  icon: Icons.map_outlined,
                  bg: _violet100,
                  fg: _violet700,
                  border: _violet600,
                  onTap: onOpenMaps,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: _textSecondary),
            child: Text(
              tr('close'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name[0].toUpperCase();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet action button
// ─────────────────────────────────────────────────────────────────────────────

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.icon,
    required this.bg,
    required this.fg,
    required this.border,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final Color bg, fg, border;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border.withOpacity(0.4)),
        boxShadow: filled
            ? [
                BoxShadow(
                  color: fg.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    ),
  );
}
