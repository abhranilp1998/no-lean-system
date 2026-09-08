import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/app_notice.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/glow_button.dart';
import '../services/trusted_contact_service.dart';

Future<void> showTrustedContactDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final service = ref.read(trustedContactServiceProvider);
  TrustedContact? current;
  try {
    current = await service.getContact();
  } catch (_) {
    if (context.mounted) {
      AppNotice.show(
        context,
        'CONTACT STORE UNAVAILABLE // TRY AGAIN.',
        type: AppNoticeType.error,
      );
    }
    return;
  }

  if (!context.mounted) return;

  await showDialog(
    context: context,
    builder: (ctx) => _TrustedContactDialog(
      service: service,
      initialName: current?.name ?? '',
      initialPhone: current?.phone ?? '',
    ),
  );
}

class _TrustedContactDialog extends StatefulWidget {
  const _TrustedContactDialog({
    required this.service,
    required this.initialName,
    required this.initialPhone,
  });

  final TrustedContactService service;
  final String initialName;
  final String initialPhone;

  @override
  State<_TrustedContactDialog> createState() => _TrustedContactDialogState();
}

class _TrustedContactDialogState extends State<_TrustedContactDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _phoneController = TextEditingController(text: widget.initialPhone);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    try {
      if (name.isEmpty && phone.isEmpty) {
        await widget.service.clearContact();
      } else {
        await widget.service.saveContact(name, phone);
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
      return;
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not securely save this contact.');
      }
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'TRUSTED CONTACT',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'This contact can be called directly from the SOS screen. Clear both fields to disable.',
            style: TextStyle(color: muted, fontSize: 11, height: 1.45),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Sponsor or Partner',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Phone Number',
              hintText: '+1 555 123 4567',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 24),
          GlowButton(
            label: 'SAVE CONTACT',
            icon: Icons.save,
            color: cyan,
            onTap: _save,
          ),
        ],
      ),
    );
  }
}
