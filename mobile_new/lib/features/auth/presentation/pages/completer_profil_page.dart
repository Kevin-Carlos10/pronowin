import 'package:country_picker/country_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/country_pill_selector.dart';
import '../../../../shared/widgets/pw_button.dart';
import '../../../compte/presentation/providers/compte_provider.dart';
import '../providers/auth_provider.dart';

/// Page de complétion de profil — affichée juste après la première
/// connexion (et avant l'accès au premium) si nom/prénom/date de
/// naissance/téléphone ne sont pas encore renseignés.
class CompleterProfilPage extends ConsumerStatefulWidget {
  /// Route vers laquelle continuer une fois le profil complété.
  final String? from;
  const CompleterProfilPage({super.key, this.from});

  @override
  ConsumerState<CompleterProfilPage> createState() => _CompleterProfilPageState();
}

class _CompleterProfilPageState extends ConsumerState<CompleterProfilPage> {
  final _formKey       = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl  = TextEditingController();
  final _phoneCtrl     = TextEditingController();
  final _refCodeCtrl   = TextEditingController();
  DateTime? _birthDate;
  bool _saving = false;
  Country _country = deviceDefaultCountry();

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _refCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 20),
      firstDate: DateTime(1940),
      lastDate: DateTime(now.year - 18),
      helpText: 'Date de naissance',
      cancelText: 'Annuler',
      confirmText: 'Confirmer',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            surface: context.cl.surface,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_birthDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sélectionne ta date de naissance.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.patch('/profile', data: {
        'first_name':   _firstNameCtrl.text.trim(),
        'last_name':    _lastNameCtrl.text.trim(),
        'birth_date':   _birthDate!.toIso8601String().substring(0, 10),
        'phone_number': '+${_country.phoneCode}${_phoneCtrl.text.trim()}',
        // Le pays suit l'indicatif choisi ici. Sans cet envoi, tout le monde
        // restait sur le défaut « BF » du schéma Prisma, y compris après
        // avoir sélectionné un autre indicatif.
        'country_code': _country.countryCode,
      });

      // Le code de parrainage est appliqué APRÈS le profil, et son échec ne
      // remet pas en cause l'inscription : un code mal recopié ne doit pas
      // retenir l'utilisateur dans le formulaire. On l'informe, et on avance.
      final refCode = _refCodeCtrl.text.trim().toUpperCase();
      String? refWarning;
      if (refCode.isNotEmpty) {
        try {
          await dio.post('/referral/apply-code', data: {'referral_code': refCode});
        } on DioException catch (e) {
          refWarning = e.response?.data?['message'] as String?
              ?? 'Code de parrainage non appliqué.';
        } catch (_) {
          refWarning = 'Code de parrainage non appliqué.';
        }
      }

      await ref.read(authProvider.notifier).refreshUser();
      ref.invalidate(profileProvider);
      if (!mounted) return;

      if (refWarning != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(refWarning),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ));
      } else if (refCode.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Code de parrainage appliqué !'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ));
      }
      context.go(widget.from ?? '/home');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final msg = e is DioException
          ? (e.response?.data?['message'] ?? 'Erreur réseau')
          : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cl.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        // Cet écran n'est plus un passage obligé de l'inscription : on n'y
        // arrive que depuis le Premium, qui a besoin de ces informations.
        // Il doit donc toujours offrir une sortie — `replace` depuis le
        // paywall peut laisser la pile vide, auquel cas `pop()` ne mène nulle
        // part et l'utilisateur se retrouvait enfermé.
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: context.cl.textS),
          tooltip: 'Retour',
          onPressed: () => context.canPop() ? context.pop() : context.go('/compte'),
        ),
        title: Text(
          'Compléter mon profil',
          style: TextStyle(color: context.cl.textP, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                icon: Icons.person_outline_rounded,
                title: 'Encore une étape !',
                subtitle: 'Ces informations nous permettent de personnaliser ton expérience.',
              ).animate().fadeIn(duration: 400.ms),

              const SizedBox(height: 24),

              _Label('Prénom'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _firstNameCtrl,
                textCapitalization: TextCapitalization.words,
                style: TextStyle(color: context.cl.textP, fontSize: 15),
                decoration: const InputDecoration(hintText: 'Ton prénom'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Prénom requis';
                  if (v.trim().length < 2) return 'Minimum 2 caractères';
                  return null;
                },
              ).animate().fadeIn(duration: 300.ms, delay: 60.ms),

              const SizedBox(height: 16),

              _Label('Nom de famille'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _lastNameCtrl,
                textCapitalization: TextCapitalization.words,
                style: TextStyle(color: context.cl.textP, fontSize: 15),
                decoration: const InputDecoration(hintText: 'Ton nom'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Nom requis';
                  if (v.trim().length < 2) return 'Minimum 2 caractères';
                  return null;
                },
              ).animate().fadeIn(duration: 300.ms, delay: 100.ms),

              const SizedBox(height: 16),

              _Label('Date de naissance'),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickBirthDate,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: context.cl.surfaceD,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _birthDate == null ? context.cl.borderS : AppColors.primary,
                      width: _birthDate == null ? 0.5 : 1.2,
                    ),
                  ),
                  child: Row(children: [
                    Icon(Icons.calendar_today_rounded,
                        color: _birthDate == null ? context.cl.textM : AppColors.primary, size: 18),
                    const SizedBox(width: 12),
                    Text(
                      _birthDate == null
                          ? 'Sélectionner la date'
                          : '${_birthDate!.day.toString().padLeft(2, '0')}/'
                            '${_birthDate!.month.toString().padLeft(2, '0')}/'
                            '${_birthDate!.year}',
                      style: TextStyle(
                        color: _birthDate == null ? context.cl.textM : context.cl.textP,
                        fontSize: 15,
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.keyboard_arrow_down_rounded, color: context.cl.textM, size: 20),
                  ]),
                ),
              ).animate().fadeIn(duration: 300.ms, delay: 140.ms),

              if (_birthDate == null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    'Tu dois avoir au moins 18 ans.',
                    style: TextStyle(color: context.cl.textM, fontSize: 11),
                  ),
                ),

              const SizedBox(height: 16),

              _Label('Numéro de téléphone'),
              const SizedBox(height: 8),
              Row(children: [
                CountryPillSelector(
                  country: _country,
                  onSelect: (c) => setState(() => _country = c),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(color: context.cl.textP, fontSize: 15),
                    decoration: const InputDecoration(hintText: 'XX XX XX XX'),
                    validator: (v) => (v == null || v.trim().length < 7) ? 'Numéro invalide' : null,
                  ),
                ),
              ]).animate().fadeIn(duration: 300.ms, delay: 180.ms),

              const SizedBox(height: 22),

              // Code de parrainage — placé ici parce que c'est le seul moment
              // où l'utilisateur a encore en tête le code qu'un ami vient de
              // lui envoyer. Auparavant, il fallait le saisir depuis
              // Compte → Parrainage → détail des filleuls, trois niveaux plus
              // loin : personne ne l'y trouvait.
              Row(children: [
                _Label('Code de parrainage'),
                const SizedBox(width: 6),
                Text('(facultatif)',
                  style: TextStyle(color: context.cl.textM, fontSize: 11.5)),
              ]),
              const SizedBox(height: 8),
              TextFormField(
                controller: _refCodeCtrl,
                textCapitalization: TextCapitalization.characters,
                maxLength: 12,
                style: TextStyle(
                  color: context.cl.textP, fontSize: 15, letterSpacing: 2),
                decoration: InputDecoration(
                  hintText: 'Ex. D52FA1',
                  counterText: '',
                  prefixIcon: Icon(Icons.card_giftcard_rounded,
                    color: context.cl.textM, size: 19),
                ),
                // Pas de validator : un code erroné ne doit pas empêcher de
                // terminer l'inscription. La vérification se fait à l'envoi,
                // et l'échec est signalé sans bloquer.
              ).animate().fadeIn(duration: 300.ms, delay: 200.ms),
              const SizedBox(height: 6),
              Text(
                'Un ami t\'a parrainé ? Saisis son code, tu ne pourras plus le '
                'faire après.',
                style: TextStyle(color: context.cl.textM, fontSize: 11.5, height: 1.35)),

              const SizedBox(height: 30),

              PwButton(
                label: 'Terminer',
                isLoading: _saving,
                onPressed: _submit,
                icon: Icons.check_rounded,
              ).animate().fadeIn(duration: 400.ms, delay: 220.ms),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── WIDGETS ─────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _SectionHeader({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [AppColors.primary.withValues(alpha: 0.10), AppColors.primary.withValues(alpha: 0.03)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
    ),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppColors.primary, size: 24),
      ),
      const SizedBox(width: 16),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: context.cl.textP, fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(color: context.cl.textS, fontSize: 12, height: 1.4)),
      ])),
    ]),
  );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
    style: TextStyle(color: context.cl.textS, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5));
}

