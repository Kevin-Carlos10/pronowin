import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/network/dio_client.dart';
import '../providers/compte_provider.dart';

class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key});
  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  final _pseudoCtrl    = TextEditingController();
  final _emailCtrl     = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl  = TextEditingController();
  DateTime? _birthDate;
  bool _loading       = false;
  bool _avatarLoading = false;
  String? _localAvatarPath; // chemin local après sélection

  @override
  void initState() {
    super.initState();
    final profile = ref.read(profileProvider).valueOrNull;
    if (profile != null) {
      _pseudoCtrl.text    = profile['pseudo']     as String? ?? '';
      _emailCtrl.text     = profile['email']      as String? ?? '';
      _firstNameCtrl.text = profile['first_name'] as String? ?? '';
      _lastNameCtrl.text  = profile['last_name']  as String? ?? '';
      final bd = profile['birth_date'] as String?;
      if (bd != null) _birthDate = DateTime.tryParse(bd);
    }
  }

  @override
  void dispose() {
    _pseudoCtrl.dispose(); _emailCtrl.dispose();
    _firstNameCtrl.dispose(); _lastNameCtrl.dispose();
    super.dispose();
  }

  // ── Avatar ────────────────────────────────────────────────────────────────
  Future<void> _pickAvatar(ImageSource source) async {
    Navigator.pop(context); // ferme le bottom sheet
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source, imageQuality: 80, maxWidth: 512, maxHeight: 512);
    if (picked == null) return;

    setState(() { _localAvatarPath = picked.path; _avatarLoading = true; });

    try {
      final formData = FormData.fromMap({
        'avatar': await MultipartFile.fromFile(picked.path,
          filename: 'avatar.jpg'),
      });
      await ref.read(dioProvider).patch('/profile/avatar', data: formData);
      ref.invalidate(profileProvider);
      if (mounted) _showSnack('Photo de profil mise à jour ✅');
    } on DioException catch (e) {
      if (mounted) {
        setState(() => _localAvatarPath = null);
        _showSnack(
          e.response?.data?['message'] as String? ?? 'Erreur lors de l\'upload.',
          isError: true);
      }
    } finally {
      if (mounted) setState(() => _avatarLoading = false);
    }
  }

  void _showAvatarSheet() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(
          color: context.cl.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.cl.border, width: 0.5)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
            decoration: BoxDecoration(
              color: context.cl.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text('Changer la photo de profil',
            style: TextStyle(color: context.cl.textP,
              fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 18),
          _AvatarOption(
            icon: Icons.camera_alt_rounded,
            label: 'Prendre une photo',
            color: AppColors.primary,
            onTap: () => _pickAvatar(ImageSource.camera)),
          const SizedBox(height: 10),
          _AvatarOption(
            icon: Icons.photo_library_rounded,
            label: 'Choisir depuis la galerie',
            color: AppColors.info,
            onTap: () => _pickAvatar(ImageSource.gallery)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Annuler',
              style: TextStyle(color: context.cl.textS, fontSize: 14))),
        ]),
      ),
    );
  }

  // ── Formulaire ────────────────────────────────────────────────────────────
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context:     context,
      initialDate: _birthDate ?? DateTime(now.year - 20),
      firstDate:   DateTime(1940),
      lastDate:    DateTime(now.year - 18, now.month, now.day),
      helpText:    'Date de naissance',
      cancelText:  'Annuler',
      confirmText: 'Confirmer',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.dark(
            primary:   AppColors.primary,
            onPrimary: Colors.white,
            surface:   context.cl.surface,
            onSurface: context.cl.textP,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _save() async {
    if (_pseudoCtrl.text.trim().length < 3) {
      _showSnack('Pseudo trop court (minimum 3 caractères).', isError: true); return;
    }
    if (_firstNameCtrl.text.trim().isNotEmpty &&
        _firstNameCtrl.text.trim().length < 2) {
      _showSnack('Prénom trop court (minimum 2 caractères).', isError: true); return;
    }
    if (_lastNameCtrl.text.trim().isNotEmpty &&
        _lastNameCtrl.text.trim().length < 2) {
      _showSnack('Nom trop court (minimum 2 caractères).', isError: true); return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(dioProvider).patch('/profile', data: {
        'pseudo': _pseudoCtrl.text.trim(),
        if (_emailCtrl.text.trim().isNotEmpty)
          'email': _emailCtrl.text.trim(),
        if (_firstNameCtrl.text.trim().isNotEmpty)
          'first_name': _firstNameCtrl.text.trim(),
        if (_lastNameCtrl.text.trim().isNotEmpty)
          'last_name': _lastNameCtrl.text.trim(),
        if (_birthDate != null)
          'birth_date': _birthDate!.toIso8601String().split('T')[0],
      });
      ref.invalidate(profileProvider);
      if (mounted) {
        _showSnack('Profil mis à jour ✅');
        context.pop();
      }
    } on DioException catch (e) {
      _showSnack(
        e.response?.data?['message'] as String? ?? 'Erreur de mise à jour.',
        isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile    = ref.watch(profileProvider).valueOrNull;
    final avatarUrl  = profile?['avatar_url'] as String?;
    final initiale   = _pseudoCtrl.text.isNotEmpty
      ? _pseudoCtrl.text[0].toUpperCase() : 'P';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text('Modifier le profil'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: _loading
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.primary))
              : const Text('Enregistrer', style: TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [

          // ─── Avatar ───────────────────────────────────────────────────
          Center(child: GestureDetector(
            onTap: _showAvatarSheet,
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 88, height: 88,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryLight]),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 12, offset: const Offset(0, 4))]),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: _avatarLoading
                    ? const Center(child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                    : _localAvatarPath != null
                      ? Image.file(File(_localAvatarPath!), fit: BoxFit.cover)
                      : avatarUrl != null && avatarUrl.isNotEmpty
                        ? Image.network(avatarUrl, fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Center(child: Text(initiale,
                              style: const TextStyle(color: Colors.white,
                                fontSize: 32, fontWeight: FontWeight.w800))))
                        : Center(child: Text(initiale,
                            style: const TextStyle(color: Colors.white,
                              fontSize: 32, fontWeight: FontWeight.w800))),
                ),
              ),
              Positioned(
                bottom: -4, right: -4,
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.primary, shape: BoxShape.circle,
                    border: Border.all(color: context.cl.bg, width: 2)),
                  child: const Icon(Icons.camera_alt_rounded,
                    color: Colors.white, size: 14)),
              ),
            ]),
          )),
          const SizedBox(height: 8),
          Center(child: Text('Appuyer pour changer la photo',
            style: TextStyle(color: context.cl.textM, fontSize: 11))),
          const SizedBox(height: 28),

          // ─── Identité ─────────────────────────────────────────────────
          _SectionLabel('IDENTITÉ'),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _FieldLabel('Prénom'),
              TextField(
                controller: _firstNameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'Votre prénom',
                  prefixIcon: Icon(Icons.badge_rounded,
                    size: 20, color: context.cl.textM)),
              ),
            ])),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _FieldLabel('Nom'),
              TextField(
                controller: _lastNameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'Votre nom',
                  prefixIcon: Icon(Icons.badge_outlined,
                    size: 20, color: context.cl.textM)),
              ),
            ])),
          ]),
          const SizedBox(height: 16),

          _FieldLabel('Date de naissance'),
          GestureDetector(
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              decoration: BoxDecoration(
                color: context.cl.surfaceDeep,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.cl.borderSoft, width: 0.5)),
              child: Row(children: [
                Icon(Icons.cake_rounded, size: 20, color: context.cl.textM),
                const SizedBox(width: 10),
                Text(
                  _birthDate != null
                    ? '${_birthDate!.day.toString().padLeft(2,'0')}/'
                      '${_birthDate!.month.toString().padLeft(2,'0')}/'
                      '${_birthDate!.year}'
                    : 'Sélectionner votre date de naissance',
                  style: TextStyle(
                    color: _birthDate != null
                      ? context.cl.textP : context.cl.textM,
                    fontSize: 14)),
                const Spacer(),
                Icon(Icons.calendar_today_rounded, size: 16, color: context.cl.textM),
              ]),
            ),
          ),
          if (_birthDate != null) Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              const Icon(Icons.check_circle_outline_rounded,
                size: 13, color: AppColors.success),
              const SizedBox(width: 4),
              Text('${_getAge(_birthDate!)} ans',
                style: const TextStyle(color: AppColors.success, fontSize: 11)),
            ]),
          ),
          const SizedBox(height: 20),

          // ─── Compte ───────────────────────────────────────────────────
          _SectionLabel('COMPTE'),
          _FieldLabel('Pseudo'),
          TextField(
            controller: _pseudoCtrl,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'Votre pseudo',
              prefixIcon: Icon(Icons.person_rounded,
                size: 20, color: context.cl.textM),
              helperText: 'Minimum 3 caractères',
              helperStyle: TextStyle(color: context.cl.textM, fontSize: 11)),
          ),
          const SizedBox(height: 16),

          _FieldLabel('Email (optionnel)'),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: 'votre@email.com',
              prefixIcon: Icon(Icons.email_rounded,
                size: 20, color: context.cl.textM)),
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.2))),
            child: const Row(children: [
              Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 16),
              SizedBox(width: 8),
              Expanded(child: Text(
                'PronoWin est réservé aux personnes de 18 ans et plus.',
                style: TextStyle(color: AppColors.warning, fontSize: 12))),
            ]),
          ),
          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: _loading ? null : _save,
              child: _loading
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
                : const Text('Enregistrer les modifications'),
            ),
          ),
        ],
      ),
    );
  }

  int _getAge(DateTime dob) =>
    ((DateTime.now().difference(dob).inDays) / 365.25).floor();

  void _showSnack(String msg, {bool isError = false}) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
}

// ─── Option avatar dans le bottom sheet ──────────────────────────────────────
class _AvatarOption extends StatelessWidget {
  final IconData    icon;
  final String      label;
  final Color       color;
  final VoidCallback onTap;
  const _AvatarOption({required this.icon, required this.label,
    required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Row(children: [
        Container(width: 38, height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 20)),
        const SizedBox(width: 14),
        Text(label, style: TextStyle(
          color: context.cl.textP, fontSize: 14, fontWeight: FontWeight.w600)),
        const Spacer(),
        Icon(Icons.arrow_forward_ios_rounded, color: context.cl.textM, size: 14),
      ]),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(label, style: TextStyle(
      color: context.cl.textS, fontSize: 11,
      fontWeight: FontWeight.w600, letterSpacing: 1)));
}

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel(this.label);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(label, style: TextStyle(
      color: context.cl.textS, fontSize: 12, fontWeight: FontWeight.w600)));
}
