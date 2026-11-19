import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/widgets/app_list_pager.dart';
import '../../data/leave_api.dart';
import '../../models/leave_request_model.dart';

class VendorLeaveRequestsScreen extends StatefulWidget {
  final int initialTabIndex;
  const VendorLeaveRequestsScreen({super.key, this.initialTabIndex = 0});

  @override
  State<VendorLeaveRequestsScreen> createState() => _VendorLeaveRequestsScreenState();
}

class _VendorLeaveRequestsScreenState extends State<VendorLeaveRequestsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = false;
  List<LeaveRequestModel> _customerRequests = [];
  List<LeaveRequestModel> _vendorLeaves = [];
  List<LeaveRequestModel> _historyLeaves = [];

  @override
  void initState() {
    super.initState();
    final initialIndex = widget.initialTabIndex.clamp(0, 2);
    _tabController = TabController(length: 3, vsync: this, initialIndex: initialIndex);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      _loadDataForCurrentTab();
    });
    _loadDataForCurrentTab();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDataForCurrentTab() async {
    setState(() => _loading = true);
    try {
      if (_tabController.index == 0) {
        // Customer Requests (Pending)
        final res = await LeaveApi.getLeavesForVendor(
          status: 'pending',
          page: 1,
          limit: 100,
        );
        if (mounted) {
          setState(() {
            _customerRequests = List<LeaveRequestModel>.from(
              (res['leaves'] as Iterable).where((x) => x.requestedBy == 'Customer'),
            );
          });
        }
      } else if (_tabController.index == 1) {
        // Vendor Leaves (Declared vendor holidays)
        final resApproved = await LeaveApi.getLeavesForVendor(
          status: 'approved',
          page: 1,
          limit: 100,
        );
        final resPending = await LeaveApi.getLeavesForVendor(
          status: 'pending',
          page: 1,
          limit: 100,
        );
        if (mounted) {
          setState(() {
            _vendorLeaves = [
              ...List<LeaveRequestModel>.from(
                (resApproved['leaves'] as Iterable).where((x) => x.requestedBy == 'Vendor'),
              ),
              ...List<LeaveRequestModel>.from(
                (resPending['leaves'] as Iterable).where((x) => x.requestedBy == 'Vendor'),
              ),
            ];
          });
        }
      } else {
        // History (Approved / Rejected)
        final resApproved = await LeaveApi.getLeavesForVendor(
          status: 'approved',
          page: 1,
          limit: 50,
        );
        final resRejected = await LeaveApi.getLeavesForVendor(
          status: 'rejected',
          page: 1,
          limit: 50,
        );
        if (mounted) {
          setState(() {
            _historyLeaves = [
              ...List<LeaveRequestModel>.from(resApproved['leaves'] as Iterable),
              ...List<LeaveRequestModel>.from(resRejected['leaves'] as Iterable),
            ];
            _historyLeaves.sort((a, b) => b.date.compareTo(a.date));
          });
        }
      }
    } catch (e) {
      if (mounted) ErrorHandler.show(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleApprove(LeaveRequestModel leave) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await LeaveApi.updateLeaveStatus(leaveId: leave.id, status: 'approved');
      if (mounted) {
        AppSnackbar.success(context, 'Leave request approved successfully');
        _loadDataForCurrentTab();
      }
    } catch (e) {
      if (mounted) ErrorHandler.show(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleReject(LeaveRequestModel leave) async {
    final controller = TextEditingController();
    final cs = Theme.of(context).colorScheme;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Leave Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Are you sure you want to reject this request?'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Enter reason/notes (optional)',
                labelText: 'Notes',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: cs.onSurfaceVariant)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: cs.error),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _loading = true);
      try {
        await LeaveApi.updateLeaveStatus(
          leaveId: leave.id,
          status: 'rejected',
          rejectReason: controller.text.trim().isNotEmpty ? controller.text.trim() : null,
        );
        if (mounted) {
          AppSnackbar.success(context, 'Leave request rejected');
          _loadDataForCurrentTab();
        }
      } catch (e) {
        if (mounted) ErrorHandler.show(context, e);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  void _showAddVendorLeaveDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _VendorLeaveForm(
        onSuccess: () {
          _loadDataForCurrentTab();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leave Management'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: cs.onPrimary,
          labelColor: cs.onPrimary,
          unselectedLabelColor: cs.onPrimary.withValues(alpha: 0.6),
          tabs: const [
            Tab(text: 'Customer Requests'),
            Tab(text: 'Vendor Leave'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildCustomerRequestsList(cs),
                _buildVendorLeavesList(cs),
                _buildHistoryList(cs),
              ],
            ),
      floatingActionButton: _tabController.index == 1
          ? FloatingActionButton(
              onPressed: _showAddVendorLeaveDialog,
              tooltip: 'Add Leave / Holiday',
              child: const Icon(Icons.add_rounded),
            )
          : null,
    );
  }

  Widget _buildCustomerRequestsList(ColorScheme cs) {
    if (_customerRequests.isEmpty) {
      return _buildEmptyState(cs, 'No pending customer leave requests');
    }

    return RefreshIndicator(
      onRefresh: _loadDataForCurrentTab,
      child: PagedListView<LeaveRequestModel>(
        padding: const EdgeInsets.all(16),
        items: _customerRequests,
        itemBuilder: (context, leave, index) {
          final dateStr = DateFormat('EEEE, d MMM yyyy').format(leave.date);

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        leave.customerName ?? 'Customer',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.restaurant_rounded, size: 16, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Meal: ${leave.mealType.toUpperCase()}',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  if (leave.reason != null && leave.reason!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Reason: ${leave.reason}',
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (leave.notes != null && leave.notes!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 24),
                      child: Text(
                        'Notes: ${leave.notes}',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => _handleReject(leave),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cs.error,
                          side: BorderSide(color: cs.error),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          minimumSize: const Size(80, 36),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Reject'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () => _handleApprove(leave),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          minimumSize: const Size(80, 36),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Approve'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVendorLeavesList(ColorScheme cs) {
    if (_vendorLeaves.isEmpty) {
      return _buildEmptyState(cs, 'No declared vendor holidays / leaves');
    }

    return RefreshIndicator(
      onRefresh: _loadDataForCurrentTab,
      child: PagedListView<LeaveRequestModel>(
        padding: const EdgeInsets.all(16),
        items: _vendorLeaves,
        itemBuilder: (context, leave, index) {
          final dateStr = DateFormat('EEEE, d MMM yyyy').format(leave.date);

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        dateStr,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      _StatusChip(status: leave.status),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.restaurant_rounded, size: 16, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Meal: ${leave.mealType.toUpperCase()}',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  if (leave.reason != null && leave.reason!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Reason/Holiday: ${leave.reason}',
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (leave.notes != null && leave.notes!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 24),
                      child: Text(
                        'Notes: ${leave.notes}',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHistoryList(ColorScheme cs) {
    if (_historyLeaves.isEmpty) {
      return _buildEmptyState(cs, 'No historical leave records');
    }

    return RefreshIndicator(
      onRefresh: _loadDataForCurrentTab,
      child: PagedListView<LeaveRequestModel>(
        padding: const EdgeInsets.all(16),
        items: _historyLeaves,
        itemBuilder: (context, leave, index) {
          final dateStr = DateFormat('EEEE, d MMM yyyy').format(leave.date);
          final requesterStr = leave.requestedBy == 'Vendor' ? 'Vendor Holiday' : (leave.customerName ?? 'Customer');

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        requesterStr,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      _StatusChip(status: leave.status),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Divider(height: 16),
                  Row(
                    children: [
                      Icon(Icons.restaurant_rounded, size: 16, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Meal: ${leave.mealType.toUpperCase()}',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  if (leave.reason != null && leave.reason!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Reason: ${leave.reason}',
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs, String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_busy_rounded,
            size: 64,
            color: cs.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: cs.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    Color bg = Colors.grey.shade100;
    Color fg = Colors.grey.shade800;

    final s = status.toLowerCase();
    if (s == 'approved') {
      bg = const Color(0xFFE8FDF5);
      fg = const Color(0xFF059669);
    } else if (s == 'rejected') {
      bg = const Color(0xFFFCECEB);
      fg = const Color(0xFFD93025);
    } else if (s == 'pending') {
      bg = const Color(0xFFFAEEDA);
      fg = const Color(0xFFBA7517);
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

class _VendorLeaveForm extends StatefulWidget {
  const _VendorLeaveForm({required this.onSuccess});
  final VoidCallback onSuccess;

  @override
  State<_VendorLeaveForm> createState() => _VendorLeaveFormState();
}

class _VendorLeaveFormState extends State<_VendorLeaveForm> {
  final _formKey = GlobalKey<FormState>();
  DateTime? _selectedDate;
  String _selectedMeal = 'all';
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

  Future<void> _submit() async {
    if (_selectedDate == null) {
      AppSnackbar.error(context, 'Please select a date');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      final message = await LeaveApi.requestVendorLeave(
        leaveDate: _selectedDate!,
        mealType: _selectedMeal,
        reason: _reasonController.text.trim(),
        notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
      );
      if (mounted) {
        AppSnackbar.success(context, message);
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
                    'Declare Holiday / Leave',
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
                  labelText: 'Meal Type',
                  prefixIcon: Icon(Icons.restaurant_rounded),
                ),
                items: const [
                  DropdownMenuItem(value: 'breakfast', child: Text('Breakfast')),
                  DropdownMenuItem(value: 'lunch', child: Text('Lunch')),
                  DropdownMenuItem(value: 'dinner', child: Text('Dinner')),
                  DropdownMenuItem(value: 'both', child: Text('Both (Lunch & Dinner)')),
                  DropdownMenuItem(value: 'all', child: Text('All Meals (Full Holiday)')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedMeal = val);
                  }
                },
              ),
              const SizedBox(height: 16),
              // Reason TextField
              TextFormField(
                controller: _reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason / Holiday Title',
                  prefixIcon: Icon(Icons.info_outline_rounded),
                  hintText: 'e.g. Center closed for maintenance',
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a title or reason';
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
                    : const Text('Declare Holiday'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
