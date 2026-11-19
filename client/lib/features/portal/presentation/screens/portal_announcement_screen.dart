import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/utils/error_handler.dart';
import '../../data/portal_announcement_api.dart';

/// Vendor message shown at the top of the customer home screen.
class PortalAnnouncementScreen extends StatefulWidget {
  const PortalAnnouncementScreen({super.key});

  @override
  State<PortalAnnouncementScreen> createState() =>
      _PortalAnnouncementScreenState();
}

class _PortalAnnouncementScreenState extends State<PortalAnnouncementScreen> {
  static final _dateFmt = DateFormat('EEE, d MMM yyyy · h:mm a');

  final _controller = TextEditingController();
  DateTime? _updatedAt;
  bool _loading = true;
  bool _saving = false;
  String _savedText = '';

  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  Color get _bg => _dark ? const Color(0xFF0E1020) : const Color(0xFFF6F4FF);
  Color get _surface => _dark ? const Color(0xFF141625) : Colors.white;
  Color get _border => _dark ? const Color(0xFF2F2A55) : const Color(0xFFE4DFF7);
  Color get _text1 => _dark ? const Color(0xFFF8FAFC) : const Color(0xFF1A0E45);
  Color get _text2 => _dark ? const Color(0xFF94A3B8) : const Color(0xFF6E628F);
  Color get _accent => _dark ? const Color(0xFFB794F6) : const Color(0xFF4C2DB8);
  Color get _solid => const Color(0xFF5B35D5);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dto = await PortalAnnouncementApi.get();
      if (!mounted) return;
      setState(() {
        _savedText = dto.text;
        _controller.text = dto.text;
        _updatedAt = dto.updatedAt;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ErrorHandler.show(context, e);
    }
  }

  Future<void> _save({required bool clear}) async {
    final text = clear ? '' : _controller.text.trim();
    if (!clear && text.isEmpty) {
      AppSnackbar.info(context, 'Write the announcement first.');
      return;
    }
    setState(() => _saving = true);
    try {
      final dto = await PortalAnnouncementApi.put(
        text: text,
        notifyAllCustomers: text.isNotEmpty,
      );
      if (!mounted) return;
      setState(() {
        _savedText = dto.text;
        _controller.text = dto.text;
        _updatedAt = dto.updatedAt;
      });
      AppSnackbar.success(
        context,
        text.isEmpty
            ? 'Announcement removed from the customer home screen.'
            : 'Announcement is now on your customers\' home screen.',
      );
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.show(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
        title: const Text('Customer announcement'),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: _solid))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.campaign_rounded, color: _accent),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Shows on the customer home screen',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: _text1,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Use this for a short update, for example “Raita and papad are free today.” Holidays and cancelled meals stay in Leave Requests.',
                        style: TextStyle(fontSize: 13, height: 1.4, color: _text2),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _controller,
                        maxLines: 5,
                        maxLength: 280,
                        style: TextStyle(color: _text1, fontSize: 15, height: 1.4),
                        decoration: InputDecoration(
                          hintText: 'Raita and papad are free today',
                          hintStyle: TextStyle(color: _text2),
                          filled: true,
                          fillColor: _dark
                              ? const Color(0xFF1E1B3A)
                              : const Color(0xFFF6F4FF),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: _border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: _border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: _accent, width: 1.4),
                          ),
                        ),
                      ),
                      if (_updatedAt != null && _savedText.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Live since ${_dateFmt.format(_updatedAt!.toLocal())}',
                          style: TextStyle(fontSize: 12, color: _text2),
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _saving ? null : () => _save(clear: false),
                        style: FilledButton.styleFrom(
                          backgroundColor: _solid,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Post to customers'),
                      ),
                      if (_savedText.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _saving ? null : () => _save(clear: true),
                          child: Text(
                            'Remove announcement',
                            style: TextStyle(color: _text2),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
