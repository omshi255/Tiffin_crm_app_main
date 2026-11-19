import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/widgets/app_list_pager.dart';
import '../../data/leave_api.dart';
import '../../models/leave_request_model.dart';
import 'customer_monthly_bills_screen.dart';

class CustomerLeaveRequestsScreen extends StatefulWidget {
  const CustomerLeaveRequestsScreen({
    super.key,
    this.embedded = false,
    this.refreshToken = 0,
  });

  final bool embedded;
  final int refreshToken;

  @override
  State<CustomerLeaveRequestsScreen> createState() => _CustomerLeaveRequestsScreenState();
}

class _CustomerLeaveRequestsScreenState extends State<CustomerLeaveRequestsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = false;
  List<LeaveRequestModel> _leaves = [];
  int _approvedThisMonth = 0;
  int _pendingThisMonth = 0;
  double _waivedThisMonth = 0;

  static const _statusByTab = ['pending', 'approved', 'rejected'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadLeaves();
    _loadSummary();
  }

  @override
  void didUpdateWidget(CustomerLeaveRequestsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshToken != oldWidget.refreshToken) {
      _loadLeaves();
      _loadSummary();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<LeaveRequestModel> get _visibleLeaves {
    final status = _statusByTab[_tabController.index];
    return _leaves
        .where((leave) => leave.status.toLowerCase() == status)
        .toList();
  }

  Future<void> _loadLeaves() async {
    setState(() => _loading = true);
    try {
      final res = await LeaveApi.getLeavesForCustomer(limit: 100);
      if (mounted) {
        setState(() {
          _leaves = List<LeaveRequestModel>.from(res['leaves'] as Iterable);
        });
      }
    } catch (e) {
      if (mounted) ErrorHandler.show(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSummary() async {
    final month = DateFormat('yyyy-MM').format(DateTime.now());
    try {
      final summary = await LeaveApi.getMonthlySummary(month);
      if (!mounted) return;
      setState(() {
        _approvedThisMonth = (summary['approved'] as num?)?.toInt() ?? 0;
        _pendingThisMonth = (summary['pending'] as num?)?.toInt() ?? 0;
        _waivedThisMonth = (summary['waivedAmount'] as num?)?.toDouble() ?? 0;
      });
    } catch (_) {}
  }

  void _showRequestLeaveDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RequestLeaveForm(
        onSuccess: () {
          _loadLeaves();
          _loadSummary();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tone = _LeaveTone.of(context);
    final visible = _visibleLeaves;
    final tabLabel = _statusByTab[_tabController.index];

    return Scaffold(
      backgroundColor: widget.embedded ? Colors.transparent : tone.page,
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('My Leave Requests'),
            ),
      body: Column(
        children: [
          _monthSummary(tone),
          _statusTabs(tone),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: tone.accentSolid))
                : visible.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: tone.soft,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                Icons.event_busy_rounded,
                                size: 26,
                                color: tone.accent,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'No $tabLabel requests',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: tone.text1,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              tabLabel == 'pending'
                                  ? 'Tap + to request a meal leave.'
                                  : '${tabLabel[0].toUpperCase()}${tabLabel.substring(1)} requests will show here.',
                              style: TextStyle(fontSize: 13, color: tone.text2),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        color: tone.accentSolid,
                        onRefresh: () async {
                          await _loadLeaves();
                          await _loadSummary();
                        },
                        child: PagedListView<LeaveRequestModel>(
                          key: ValueKey(_tabController.index),
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                          items: visible,
                          itemBuilder: (context, leave, index) =>
                              _leaveCard(tone, leave),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showRequestLeaveDialog,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  Widget _statusTabs(_LeaveTone tone) {
    const labels = ['Pending', 'Approved', 'Rejected'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: List.generate(labels.length, (i) {
          final selected = _tabController.index == i;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
              child: Material(
                color: selected ? tone.accentSolid : tone.surface,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _tabController.animateTo(i),
                  child: Container(
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? tone.accentSolid : tone.border,
                      ),
                    ),
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : tone.text2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _leaveCard(_LeaveTone tone, LeaveRequestModel leave) {
    final dateStr = DateFormat('EEE, d MMM yyyy').format(leave.date);
    final reason = leave.reason?.trim() ?? '';
    final notes = leave.notes?.trim() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  dateStr,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: tone.text1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StatusChip(status: leave.status),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: tone.soft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              leave.requestedBy.toLowerCase() == 'vendor'
                  ? 'Vendor holiday · ${_mealLabel(leave.mealType)}'
                  : _mealLabel(leave.mealType),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: tone.accent,
              ),
            ),
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              reason,
              style: TextStyle(fontSize: 13, height: 1.35, color: tone.text1),
            ),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              notes,
              style: TextStyle(fontSize: 12, height: 1.35, color: tone.text2),
            ),
          ],
        ],
      ),
    );
  }

  String _mealLabel(String raw) {
    final text = raw.trim().toLowerCase().replaceAll('_', ' ');
    if (text.isEmpty) return 'Meal';
    return text[0].toUpperCase() + text.substring(1);
  }

  Widget _monthSummary(_LeaveTone tone) {
    final month = DateFormat('MMMM yyyy').format(DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tone.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tone.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'THIS MONTH',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
                color: tone.accent,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              month,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: tone.text1,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _summaryStat(tone, '$_approvedThisMonth', 'Approved'),
                const SizedBox(width: 8),
                _summaryStat(tone, '$_pendingThisMonth', 'Pending'),
                const SizedBox(width: 8),
                _summaryStat(
                  tone,
                  '₹${_waivedThisMonth.toStringAsFixed(0)}',
                  'Not charged',
                ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CustomerMonthlyBillsScreen(),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 18, color: tone.accent),
                    const SizedBox(width: 8),
                    Text(
                      'Monthly bills',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: tone.accent,
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, size: 20, color: tone.text2),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryStat(_LeaveTone tone, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: tone.soft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: tone.text1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: tone.text2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaveTone {
  const _LeaveTone._({required this.dark});

  factory _LeaveTone.of(BuildContext context) {
    return _LeaveTone._(dark: Theme.of(context).brightness == Brightness.dark);
  }

  final bool dark;

  Color get page => dark ? const Color(0xFF0E1020) : const Color(0xFFF6F4FF);
  Color get surface => dark ? const Color(0xFF141625) : const Color(0xFFFFFFFF);
  Color get soft => dark ? const Color(0xFF1E1B3A) : const Color(0xFFF4F0FF);
  Color get border => dark ? const Color(0xFF2F2A55) : const Color(0xFFE4DFF7);
  Color get text1 => dark ? const Color(0xFFF8FAFC) : const Color(0xFF1A0E45);
  Color get text2 => dark ? const Color(0xFF94A3B8) : const Color(0xFF6E628F);
  Color get accent => dark ? const Color(0xFFC4B5FD) : const Color(0xFF4C2DB8);
  Color get accentSolid => dark ? const Color(0xFF7B3FE4) : const Color(0xFF5B35D5);
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Color bg = dark ? const Color(0xFF2A2348) : const Color(0xFFF3F0FA);
    Color fg = dark ? const Color(0xFFC4B5FD) : const Color(0xFF5B5378);

    final s = status.toLowerCase();
    if (s == 'approved') {
      bg = dark ? const Color(0xFF12352C) : const Color(0xFFE7F8F0);
      fg = dark ? const Color(0xFF6EE7B7) : const Color(0xFF047857);
    } else if (s == 'rejected') {
      bg = dark ? const Color(0xFF3A1714) : const Color(0xFFFEECEC);
      fg = dark ? const Color(0xFFFCA5A5) : const Color(0xFFDC2626);
    } else if (s == 'pending') {
      bg = dark ? const Color(0xFF3A2A12) : const Color(0xFFFFF6E5);
      fg = dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: fg,
        ),
      ),
    );
  }
}

class _RequestLeaveForm extends StatefulWidget {
  const _RequestLeaveForm({required this.onSuccess});
  final VoidCallback onSuccess;

  @override
  State<_RequestLeaveForm> createState() => _RequestLeaveFormState();
}

class _RequestLeaveFormState extends State<_RequestLeaveForm> {
  final _formKey = GlobalKey<FormState>();
  DateTime? _selectedDate;
  String _selectedMeal = 'lunch';
  final _reasonController = TextEditingController();
  final _notesController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _reasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  String? _cutoffMessage() {
    final date = _selectedDate;
    if (date == null) return null;
    final now = DateTime.now();
    final day = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    if (day.isBefore(today)) return 'Cannot request leave for a past date';
    if (day.isAfter(today)) return null;
    final minutes = now.hour * 60 + now.minute;
    final meals = _selectedMeal == 'all' || _selectedMeal == 'both'
        ? const ['breakfast', 'lunch', 'dinner']
        : [_selectedMeal];
    for (final meal in meals) {
      final limit = switch (meal) {
        'breakfast' => 8 * 60,
        'lunch' => 10 * 60,
        'dinner' => 19 * 60,
        _ => 24 * 60,
      };
      if (minutes > limit) {
        final when = switch (meal) {
          'breakfast' => '8:00 AM',
          'lunch' => '10:00 AM',
          'dinner' => '7:00 PM',
          _ => '',
        };
        final label = meal[0].toUpperCase() + meal.substring(1);
        return '$label leave cannot be requested after $when.';
      }
    }
    return null;
  }

  Future<void> _submit() async {
    if (_selectedDate == null) {
      AppSnackbar.error(context, 'Please select a date');
      return;
    }
    final cutoff = _cutoffMessage();
    if (cutoff != null) {
      AppSnackbar.error(context, cutoff);
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      await LeaveApi.requestLeave(
        leaveDate: _selectedDate!,
        mealType: _selectedMeal,
        reason: _reasonController.text.trim(),
        notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
      );
      if (mounted) {
        AppSnackbar.success(context, 'Leave requested successfully');
        widget.onSuccess();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ErrorHandler.show(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 20, 16, viewInsets.bottom + 24),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Request Leave',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 12),
              // Date picker field
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outline),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_rounded, color: cs.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedDate == null
                              ? 'Select Date'
                              : DateFormat('EEEE, d MMM yyyy').format(_selectedDate!),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _selectedDate == null ? cs.onSurfaceVariant : cs.onSurface,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Meal Dropdown
              DropdownButtonFormField<String>(
                value: _selectedMeal,
                decoration: const InputDecoration(
                  labelText: 'Meal Slot',
                  prefixIcon: Icon(Icons.restaurant_rounded),
                ),
                items: const [
                  DropdownMenuItem(value: 'breakfast', child: Text('Breakfast')),
                  DropdownMenuItem(value: 'lunch', child: Text('Lunch')),
                  DropdownMenuItem(value: 'dinner', child: Text('Dinner')),
                  DropdownMenuItem(value: 'both', child: Text('Both (Lunch & Dinner)')),
                  DropdownMenuItem(value: 'all', child: Text('All Meals')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedMeal = val);
                  }
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Breakfast closes after 8:00 AM, lunch after 10:00 AM, and dinner after 7:00 PM, in your local time.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              // Reason TextField
              TextFormField(
                controller: _reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  prefixIcon: Icon(Icons.info_outline_rounded),
                  hintText: 'e.g. Going out of town',
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a reason';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Notes TextField
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (Optional)',
                  prefixIcon: Icon(Icons.note_add_outlined),
                  hintText: 'Any special instructions',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 24),
              // Submit button
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Submit Request'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
