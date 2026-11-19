import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/widgets/app_list_pager.dart';
import '../../../../services/pdf_download_service.dart';
import '../../data/leave_api.dart';

class CustomerMonthlyBillsScreen extends StatefulWidget {
  const CustomerMonthlyBillsScreen({super.key});

  @override
  State<CustomerMonthlyBillsScreen> createState() =>
      _CustomerMonthlyBillsScreenState();
}

class _CustomerMonthlyBillsScreenState extends State<CustomerMonthlyBillsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic>? _bill;
  bool _loading = true;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _monthKey => DateFormat('yyyy-MM').format(_month);

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final bill = await LeaveApi.getMonthlyBill(_monthKey);
      if (mounted) setState(() => _bill = bill);
    } catch (e) {
      if (mounted) ErrorHandler.show(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download() async {
    setState(() => _downloading = true);
    try {
      final bytes = await LeaveApi.downloadMonthlyBill(_monthKey);
      if (!mounted) return;
      await PdfDownloadService.saveBytesAndOpen(
        context: context,
        bytes: bytes,
        fileName: 'meal-bill-$_monthKey.pdf',
      );
    } catch (e) {
      if (mounted) AppSnackbar.error(context, 'Could not download the bill');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lines = (_bill?['lines'] as List?) ?? const [];
    final net = (_bill?['netAmount'] as num?)?.toDouble() ?? 0;
    final credit = (_bill?['leaveCredit'] as num?)?.toDouble() ?? 0;
    final charged = (_bill?['chargedAmount'] as num?)?.toDouble() ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Monthly bills')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => _shiftMonth(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    DateFormat('MMMM yyyy').format(_month),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: () => _shiftMonth(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Amount due  ₹${net.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Meals ₹${charged.toStringAsFixed(0)} · Leave credit ₹${credit.toStringAsFixed(0)}',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _downloading ? null : _download,
                    icon: _downloading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_rounded),
                    label: const Text('Download receipt'),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : lines.isEmpty
                    ? Center(
                        child: Text(
                          'No meals recorded for this month.',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      )
                    : PagedListView<dynamic>(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        items: lines,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, lineRaw, index) {
                          final line = Map<String, dynamic>.from(lineRaw as Map);
                          final kind = line['kind']?.toString() ?? 'meal';
                          final amount = (line['amount'] as num?)?.toDouble() ?? 0;
                          final dateRaw = line['date']?.toString();
                          final dateLabel = dateRaw == null
                              ? ''
                              : DateFormat('d MMM').format(DateTime.parse(dateRaw).toLocal());
                          return ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: cs.outlineVariant),
                            ),
                            title: Text(line['description']?.toString() ?? 'Meal'),
                            subtitle: Text(dateLabel),
                            trailing: Text(
                              kind == 'leave'
                                  ? '₹0'
                                  : '₹${amount.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: kind == 'leave' ? cs.primary : cs.onSurface,
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
