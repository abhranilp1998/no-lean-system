import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/app_notice.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/glow_button.dart';
import '../../emergency/application/sos_text_service.dart';
import '../../emergency/domain/sos_text.dart';
import '../services/trusted_contact_service.dart';

import 'package:shared_preferences/shared_preferences.dart';

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

  final prefs = await SharedPreferences.getInstance();
  final initialTemplate = prefs.getString(sosTextTemplateKey) ?? '';
  if (!context.mounted) return;

  await showDialog(
    context: context,
    builder: (ctx) => _TrustedContactDialog(
      service: service,
      initialName: current?.name ?? '',
      initialPhone: current?.phone ?? '',
      initialTemplate: initialTemplate,
      onSaveTemplate: (value) =>
          ref.read(sosTextTemplateProvider.notifier).set(value),
    ),
  );
}

class _TrustedContactDialog extends StatefulWidget {
  const _TrustedContactDialog({
    required this.service,
    required this.initialName,
    required this.initialPhone,
    required this.initialTemplate,
    required this.onSaveTemplate,
  });

  final TrustedContactService service;
  final String initialName;
  final String initialPhone;
  final String initialTemplate;
  final Future<void> Function(String value) onSaveTemplate;

  @override
  State<_TrustedContactDialog> createState() => _TrustedContactDialogState();
}

class _TrustedContactDialogState extends State<_TrustedContactDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _templateController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _phoneController = TextEditingController(text: widget.initialPhone);
    _templateController = TextEditingController(text: widget.initialTemplate);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _templateController.dispose();
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
    await widget.onSaveTemplate(_templateController.text);
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
            'This contact can be called or texted from SOS. Hold the SOS button to open a prefilled message (you press Send). Clear name and phone to disable.',
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
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('sos-text-template'),
            controller: _templateController,
            maxLength: sosTextTemplateMaxLength,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'SOS text message (optional)',
              hintText: defaultSosTextTemplate,
              helperText:
                  'Used when you hold the SOS button. Leave blank for the '
                  'default. Add {location} where you want the maps link, or '
                  "we'll add it at the end. You press Send in your SMS app.",
              helperMaxLines: 5,
            ),
          ),
          const SizedBox(height: 16),
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
