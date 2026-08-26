import 'dart:async';
import 'dart:convert';
import '../../../../core/utils/motion.dart';
import 'dart:io';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../../../../core/config/contact_support.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/montant.dart';
import '../../../../shared/widgets/country_pill_selector.dart';
import '../../domain/tarifs_premium.dart';
import '../providers/subscription_provider.dart';
import '../providers/iap_provider.dart';
import '../../../../core/config/distribution_channel.dart';
import '../../data/iap_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

// Aucun numéro n'est compilé dans ce fichier — et c'est délibéré.
//
// Il y en avait un (`_paymentPhone = '22645568158'`), présenté comme un repli.
// Il annulait en silence une protection du serveur : `payment_method.service`
// écarte volontairement les entrées sans téléphone, pour qu'une installation
// mal configurée n'affiche **aucun** moyen de paiement plutôt qu'un faux
// numéro. L'application recollait alors sa constante — et un utilisateur
// pouvait envoyer son argent à un numéro que le serveur avait refusé de
// publier. Le jour d'un changement de numéro, les anciennes versions
// continuaient d'envoyer vers l'ancien.
//
// Les numéros viennent désormais uniquement de `payment_methods`, géré depuis
// l'administration. Liste vide ⇒ l'écran le dit.

class ActiverPremiumPage extends ConsumerStatefulWidget {
  final Map<String, dynamic>? subData;
  const ActiverPremiumPage({super.key, this.subData});

  @override
  ConsumerState<ActiverPremiumPage> createState() => _ActiverPremiumPageState();
}

class _ActiverPremiumPageState extends ConsumerState<ActiverPremiumPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _picker = ImagePicker();

  // Paywall state — deux axes indépendants : durée × méthode de paiement
  bool   _showPaywall = true;
  String _duration    = 'mensuel'; // 'mensuel' | 'annuel'
  String _method      = 'direct';  // 'direct' | 'code'

  // Achat intégré : verrou pendant qu'une transaction est en cours.
  bool _iapBusy = false;
  StreamSubscription<IapResult>? _iapSub;

  // Champs partagés (preuve de paiement Mobile Money) — utilisés par les 2 onglets
  final _amountCtrl = TextEditingController();
  final _phoneCtrl  = TextEditingController();
  File?   _imagePayment;
  Country _selectedCountry = deviceDefaultCountry();

  // Onglet "Code Promo" — spécifique au compte partenaire
  final _accountIdCtrl = TextEditingController();
  File?  _imageAccount;
  String _platform = '1xbet';

  /// Tarifs, délais et moyens de paiement — une seule lecture de `subData`.
  ///
  /// Les quatre prix étaient relus ici avec leurs propres replis (`?? 6000`…),
  /// en double du fournisseur, et ni l'un ni l'autre ne contrôlait le
  /// « 5 000 FCFA » écrit en dur dans la feuille d'accroche.
  TarifsPremium get _tarifs => TarifsPremium.depuis(widget.subData);

  // Prix FCFA à collecter selon durée × méthode — c'est le SEUL endroit de
  // l'app où le FCFA est affiché à l'utilisateur.
  int get _fcfaAmountForSelectedPlan =>
      _tarifs.prix(annuel: _duration == 'annuel');

  /// Montant saisi s'il diffère de l'attendu, `null` sinon.
  ///
  /// Un champ vide n'est pas un écart : l'utilisateur n'a simplement pas encore
  /// répondu, et l'alerter à ce moment-là serait du bruit.
  int? get _ecartMontant {
    final saisi = int.tryParse(_amountCtrl.text.trim());
    if (saisi == null) return null;
    return saisi == _fcfaAmountForSelectedPlan ? null : saisi;
  }

  String get _planIdForSelectedPlan =>
    _duration == 'annuel' ? 'premium_annual' : 'premium_monthly';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(_onTabChanged);
    if (ref.read(isStoreBuildProvider)) {
      _iapSub = ref.read(iapServiceProvider).results.listen(_onIapResult);
    }
    // Rediriger si le profil est incomplet (filet de sécurité)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authState = ref.read(authProvider);
      if (authState is AuthAuthenticated && !authState.user.isProfileComplete) {
        context.replace('/compte/completer-profil', extra: '/compte/activer-premium');
      }
    });
  }

  // Garde `_method` synchronisé quand l'utilisateur change d'onglet (tap ou swipe)
  void _onTabChanged() {
    if (_tab.indexIsChanging) return;
    final newMethod = _tab.index == 1 ? 'code' : 'direct';
    if (newMethod != _method) {
      setState(() {
        _method = newMethod;
          });
    }
  }

  @override
  void dispose() {
    _iapSub?.cancel();
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    _amountCtrl.dispose(); _phoneCtrl.dispose();
    _accountIdCtrl.dispose();
    super.dispose();
  }

  void _goToForm() {
    setState(() {
      _showPaywall      = false;
      _tab.index        = _method == 'code' ? 1 : 0;
    });
  }

  // ─── Sélectionner image ───────────────────────────────────────────────────
  Future<void> _showImagePicker(ValueChanged<File> onPicked) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cl.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, margin: EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: context.cl.borderSoft, borderRadius: BorderRadius.circular(2))),
          Text('Ajouter une image', style: TextStyle(
            color: context.cl.textP, fontSize: 16, fontWeight: FontWeight.w600)),
          SizedBox(height: 6),
          Text('Choisis ta capture d\'écran', style: TextStyle(color: context.cl.textM, fontSize: 12)),
          const SizedBox(height: 12),
          _PickerOption(
            icon: Icons.photo_library_rounded, color: AppColors.primary,
            title: 'Galerie photo', subtitle: 'Choisir depuis tes photos',
            onTap: () async {
              Navigator.pop(context);
              final f = await _pickFrom(ImageSource.gallery);
              if (f != null) setState(() => onPicked(f));
            },
          ),
          _PickerOption(
            icon: Icons.camera_alt_rounded, color: AppColors.info,
            title: 'Appareil photo', subtitle: 'Prendre une nouvelle photo',
            onTap: () async {
              Navigator.pop(context);
              final f = await _pickFrom(ImageSource.camera);
              if (f != null) setState(() => onPicked(f));
            },
          ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  Future<File?> _pickFrom(ImageSource src) async {
    try {
      final p = await _picker.pickImage(
        source:       src,
        imageQuality: 75,
        maxWidth:     1280,
        maxHeight:    1280,
      );
      return p != null ? File(p.path) : null;
    } catch (_) { return null; }
  }

  @override
  Widget build(BuildContext context) {
    final submitState = ref.watch(submitProofProvider);

    ref.listen<SubmitProofState>(submitProofProvider, (_, state) {
      if (state is ProofSubmitted) _showSuccessDialog(state.estimatedTime);
      if (state is ProofError)     _showSnack(state.message, isError: true);
    });

    if (_showPaywall) return _buildPaywallPage();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => setState(() => _showPaywall = true),
        ),
        title: Text(_method == 'code' ? 'Activation Code Promo' : 'Paiement Mobile'),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: context.cl.textS,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(icon: Icon(Icons.phone_android_rounded, size: 16), text: 'Paiement Direct'),
            Tab(icon: Icon(Icons.confirmation_number_rounded, size: 16), text: 'Code Promo'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildPaymentTab(submitState),
          _buildXbetTab(submitState),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════
  // PAGE PAYWALL (landing d'activation premium)
  // ══════════════════════════════════════════════════════
  Widget _buildPaywallPage() {
    final monthlyUsd     = (widget.subData?['premium_price_monthly_usd']      as num?)?.toDouble() ?? 10;
    final annualUsd      = (widget.subData?['premium_price_annual_usd']       as num?)?.toDouble() ?? 90;
    final monthlyCodeUsd = (widget.subData?['premium_price_monthly_code_usd'] as num?)?.toDouble() ?? 7;
    final annualCodeUsd  = (widget.subData?['premium_price_annual_code_usd']  as num?)?.toDouble() ?? 63;

    // Sur un build store, Apple (3.1.1) et Google imposent l'achat intégré
    // pour déverrouiller du contenu numérique — et interdisent d'afficher un
    // moyen de paiement externe à côté. Les deux chemins ne coexistent donc
    // jamais sur le même écran.
    final isStore = ref.watch(isStoreBuildProvider);
    final iapReady = isStore ? (ref.watch(iapReadyProvider).value ?? false) : false;

    return _PaywallPage(
      monthlyPrice:     monthlyUsd,
      annualPrice:      annualUsd,
      monthlyCodePrice: monthlyCodeUsd,
      annualCodePrice:  annualCodeUsd,
      promoCode:        _tarifs.promoCode,
      tarifs:           _tarifs,
      duration:         _duration,
      method:           _method,
      onSelectDuration: (d) => setState(() => _duration = d),
      onSelectMethod:   (m) => setState(() => _method = m),
      onConfirm:        _goToForm,
      onClose:          () => context.pop(),
      iapMode:          isStore,
      iapLoading:       isStore && ref.watch(iapReadyProvider).isLoading,
      iapUnavailable:   isStore && !iapReady,
      iapProduct:       iapReady ? _iapProductForDuration() : null,
      iapBusy:          _iapBusy,
      onIapBuy:         _startIapPurchase,
      onIapRestore:     _restoreIap,
    );
  }

  // ─── Achat intégré ────────────────────────────────────────────────────────
  ProductDetails? _iapProductForDuration() {
    final id = _duration == 'annuel'
      ? 'com.pronowin.premium.annual'
      : 'com.pronowin.premium.monthly';
    return ref.read(iapServiceProvider).productFor(id);
  }

  Future<void> _startIapPurchase() async {
    final product = _iapProductForDuration();
    if (product == null) {
      _showSnack('Ce forfait n\'est pas disponible sur le store.', isError: true);
      return;
    }
    setState(() => _iapBusy = true);
    try {
      await ref.read(iapServiceProvider).buy(product);
    } catch (e) {
      if (mounted) {
        setState(() => _iapBusy = false);
        _showSnack('Achat impossible : $e', isError: true);
      }
    }
  }

  Future<void> _restoreIap() async {
    setState(() => _iapBusy = true);
    try {
      await ref.read(iapServiceProvider).restore();
    } catch (e) {
      if (mounted) _showSnack('Restauration impossible : $e', isError: true);
    }
    // Le résultat arrive par le flux ; si rien ne vient, on relâche le verrou.
    await Future<void>.delayed(const Duration(seconds: 4));
    if (mounted && _iapBusy) {
      setState(() => _iapBusy = false);
      _showSnack('Aucun achat à restaurer sur ce compte.');
    }
  }

  void _onIapResult(IapResult r) {
    if (!mounted) return;
    setState(() => _iapBusy = false);
    switch (r) {
      case IapSuccess():
        // Rafraîchir le profil : c'est lui qui porte subscriptionExpiresAt et
        // qui déverrouille le reste de l'app.
        ref.read(authProvider.notifier).refreshUser();
        ref.invalidate(currentSubscriptionProvider);
        _showSuccessDialog('immédiate');
      case IapCancelled():
        break; // L'utilisateur a annulé : pas de message d'erreur.
      case IapFailure(:final message):
        _showSnack(message, isError: true);
    }
  }

  // ══════════════════════════════════════════════════════'
  // CHAMPS PARTAGÉS — preuve de paiement Mobile Money (utilisés par les 2 onglets)
  // ══════════════════════════════════════════════════════'
  /// Méthodes de paiement servies par l'API, filtrées de tout ce qui serait
  /// inexploitable (numéro vide) plutôt que d'afficher une ligne creuse.
  List<Map<String, dynamic>> get _methodesPaiement {
    final brut = widget.subData?['payment_methods'];
    if (brut is! List) return const [];
    return brut
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .where((m) => (m['phone'] ?? '').toString().trim().isNotEmpty)
        .toList();
  }

  /// [etapeTransfert] : numéro de l'étape « envoie l'argent ».
  ///
  /// La numérotation démarrait à « 1. Montant envoyé » alors que la première
  /// action réelle — le transfert — figurait au-dessus, sans numéro. L'écran
  /// comptait donc à partir de sa deuxième étape.
  List<Widget> _buildPaymentFieldsSection({required bool isCode, required int etapeTransfert}) {
    final price = _fcfaAmountForSelectedPlan;
    final planLabel = (_duration == 'annuel' ? 'Plan Annuel' : 'Plan Mensuel') +
      (isCode ? ' · Tarif réduit' : '');
    return [
      _PaymentRecipientCard(
        price: price, planLabel: planLabel, methodes: _methodesPaiement,
        etape: etapeTransfert),
      const SizedBox(height: 20),

      _FieldLabel('${etapeTransfert + 1}. Montant envoyé (FCFA)'),
      // Champ volontairement vide.
      //
      // Il était pré-rempli avec le montant attendu, sous une étiquette qui
      // demandait « le montant exact que vous avez envoyé ». Personne ne le
      // modifiait : le montant déclaré était donc toujours égal à l'attendu,
      // par construction, et la comparaison faite en administration ne pouvait
      // rien détecter. Un envoi de 50 000 au lieu de 54 000, ou des frais
      // transfrontaliers, passaient inaperçus.
      //
      // Vide, avec l'attendu en indication grise, l'écart redevient visible.
      TextField(
        controller: _amountCtrl,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: Theme.of(context).textTheme.bodyLarge,
        onChanged: (_) => setState(() {}),   // rafraîchit l'alerte d'écart
        decoration: InputDecoration(
          hintText: '$price',
          prefixIcon: Icon(Icons.payments_rounded, size: 20, color: context.cl.textM),
          helperText: 'Attendu : ${montantExact(price)} FCFA',
          helperStyle: TextStyle(color: context.cl.textM, fontSize: 11),
        ),
      ),

      // Écart signalé tout de suite, pas découvert par l'administrateur deux
      // heures plus tard. L'utilisateur peut encore compléter son envoi.
      if (_ecartMontant != null) ...[
        const SizedBox(height: 8),
        _AlerteEcartMontant(saisi: _ecartMontant!, attendu: price),
      ],
      const SizedBox(height: 20),

      _FieldLabel('${etapeTransfert + 2}. Numéro Mobile Money utilisé pour le transfert'),
      Text(
        'Entrez le numéro depuis lequel vous avez envoyé l\'argent',
        style: TextStyle(color: context.cl.textM, fontSize: 11),
      ),
      const SizedBox(height: 8),
      Row(children: [
        // Sélecteur pays — liste exhaustive avec recherche
        CountryPillSelector(
          country: _selectedCountry,
          onSelect: (c) => setState(() {
            _selectedCountry = c;
            _phoneCtrl.clear();
          }),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(15), // max E.164
            ],
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: '70 00 00 00',
              helperText: 'Sans l\'indicatif',
              helperStyle: TextStyle(color: context.cl.textM, fontSize: 11),
            ),
          ),
        ),
      ]),

      // Aperçu du numéro complet
      ValueListenableBuilder(
        valueListenable: _phoneCtrl,
        builder: (_, val, _) {
          if (val.text.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              const Icon(Icons.check_circle_outline_rounded, color: AppColors.success, size: 14),
              const SizedBox(width: 6),
              Text(
                'Numéro complet : +${_selectedCountry.phoneCode}${val.text}',
                style: const TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ]),
          );
        },
      ),
      const SizedBox(height: 20),

      _FieldLabel('${etapeTransfert + 3}. Capture d\'écran de la confirmation de paiement'),
      _ImagePickerWidget(image: _imagePayment, onTap: () => _showImagePicker((f) => _imagePayment = f)),
    ];
  }

  // ══════════════════════════════════════════════════════'
  // ONGLET PAIEMENT DIRECT
  // ══════════════════════════════════════════════════════'
  Widget _buildPaymentTab(SubmitProofState submitState) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ..._buildPaymentFieldsSection(isCode: false, etapeTransfert: 1),
        const SizedBox(height: 16),

        // Récapitulatif avant envoi
        if (_imagePayment != null && _phoneCtrl.text.isNotEmpty)
          _RecapCard(
            amount:  double.tryParse(_amountCtrl.text) ?? 0,
            phone:   '+${_selectedCountry.phoneCode}${_phoneCtrl.text}',
            xbetId:  '',
          ),
        const SizedBox(height: 20),

        // Bouton
        _SubmitButton(
          label:     'Envoyer la preuve',
          icon:      Icons.upload_rounded,
          isLoading: submitState is ProofLoading,
          // Le montant fait désormais partie des conditions : il n'est plus
          // pré-rempli, donc son absence est un vrai manque.
          enabled:   _imagePayment != null &&
                     _phoneCtrl.text.length >= 7 &&
                     _montantSaisi,
          onTap:     _submitPayment,
        ),
        if (_raisonBlocagePaiement != null) ...[
          const SizedBox(height: 8),
          Text(_raisonBlocagePaiement!,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.cl.textM, fontSize: 12)),
        ],

        const SizedBox(height: 18),
        const _SortieDeSecours(),
      ],
    );
  }

  bool get _montantSaisi => (int.tryParse(_amountCtrl.text.trim()) ?? 0) > 0;

  /// Ce qui manque encore, dans l'ordre où l'utilisateur remplit l'écran.
  ///
  /// Un bouton désactivé sans raison affichée oblige à deviner ; l'énoncer
  /// coûte une ligne.
  String? get _raisonBlocagePaiement {
    if (!_montantSaisi) return 'Indique le montant que tu as envoyé pour continuer';
    if (_phoneCtrl.text.length < 7) return 'Entrez un numéro de téléphone valide pour continuer';
    if (_imagePayment == null) return 'Ajoutez une capture d\'écran pour continuer';
    return null;
  }

  // ══════════════════════════════════════════════════════
  // ONGLET CODE PROMO
  // ══════════════════════════════════════════════════════
  Widget _buildXbetTab(SubmitProofState submitState) {
    final promoCode = _tarifs.promoCode;
    final platforms = _tarifs.plateformes;
    const purple    = Color(0xFFA78BFA);
    const purpleDark = Color(0xFF7C3AED);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [

        // ── Header ────────────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [purpleDark.withValues(alpha: 0.18), purple.withValues(alpha: 0.06)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: purple.withValues(alpha: 0.25), width: 0.8)),
          child: Column(children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: purple.withValues(alpha: 0.15),
                shape: BoxShape.circle),
              child: const Icon(Icons.diversity_3_rounded, color: purple, size: 28)),
            const SizedBox(height: 12),
            Text('Rejoins un partenaire', style: TextStyle(
              color: context.cl.textP, fontSize: 17,
              fontWeight: FontWeight.w800, letterSpacing: -0.3)),
            const SizedBox(height: 6),
            Text(
              'Crée un compte sur 1xBet, Melbet ou Betwinner avec notre code, '
              'fais ton premier dépôt, et ton premier mois de Premium est '
              'offert.',
              style: TextStyle(color: context.cl.textS, fontSize: 12, height: 1.5),
              textAlign: TextAlign.center),
          ]),
        ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05, end: 0),

        const SizedBox(height: 20),

        // ── Sélecteur de plateforme ─────────────────────────────
        _FieldLabel('Plateforme partenaire'),
        _PlatformSelector(
          platforms: platforms,
          selected: _platform,
          onSelect: (p) => setState(() => _platform = p),
        ).animate(delay: 60.ms).fadeIn(duration: 300.ms),

        const SizedBox(height: 20),

        // ── Code promo ────────────────────────────────────────────
        _PromoCodeCard(promoCode: promoCode)
          .animate(delay: 80.ms).fadeIn(duration: 300.ms).slideY(begin: 0.04, end: 0),

        const SizedBox(height: 20),

        // ── Timeline des étapes ───────────────────────────────────
        _XbetSteps(tarifs: _tarifs)
          .animate(delay: 140.ms).fadeIn(duration: 300.ms),

        const SizedBox(height: 24),

        // ── Séparateur "Ta soumission" ─────────────────────────
        Row(children: [
          Expanded(child: Divider(color: context.cl.border, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('VOTRE SOUMISSION', style: TextStyle(
              color: context.cl.textM, fontSize: 10,
              fontWeight: FontWeight.w700, letterSpacing: 1))),
          Expanded(child: Divider(color: context.cl.border, height: 1)),
        ]).animate(delay: 180.ms).fadeIn(duration: 250.ms),

        const SizedBox(height: 20),

        // ── Champ ID de compte stylisé ────────────────────────────
        _FieldLabel('1. ID de ton compte'),
        Container(
          decoration: BoxDecoration(
            color: context.cl.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _accountIdCtrl.text.isNotEmpty
                ? purple.withValues(alpha: 0.5)
                : context.cl.border,
              width: _accountIdCtrl.text.isNotEmpty ? 1.5 : 0.5)),
          child: Row(children: [
            Container(
              width: 48, height: 56,
              decoration: BoxDecoration(
                color: purple.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(13),
                  bottomLeft: Radius.circular(13))),
              child: const Icon(Icons.badge_rounded, color: purple, size: 22)),
            Expanded(
              child: TextField(
                controller: _accountIdCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                  color: context.cl.textP, fontSize: 16,
                  fontWeight: FontWeight.w600, letterSpacing: 1),
                decoration: InputDecoration(
                  hintText: 'Ton ID de compte',
                  hintStyle: TextStyle(color: context.cl.textM,
                    fontSize: 14, fontWeight: FontWeight.w400, letterSpacing: 0),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16)),
              ),
            ),
            if (_accountIdCtrl.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: const Icon(Icons.check_circle_rounded,
                  color: purple, size: 20))
                  .animate().scale(
                    begin: const Offset(0, 0), end: const Offset(1, 1),
                    duration: 200.ms, curve: Curves.easeOutBack),
          ]),
        ).animate(delay: 200.ms).fadeIn(duration: 280.ms),

        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text('Visible dans Profil → Mon compte sur la plateforme choisie',
            style: TextStyle(color: context.cl.textM, fontSize: 11))),

        const SizedBox(height: 20),

        // ── Zone upload capture du compte ───────────────────────────
        //
        // Une seule capture désormais. La seconde prouvait un versement Mobile
        // Money vers nous ; ce parcours n'en comporte plus. Ce qu'il faut voir
        // sur l'image, c'est l'identifiant **et** le dépôt : c'est le dépôt qui
        // ouvre droit au mois offert, pas l'inscription seule.
        _FieldLabel('2. Capture de ton compte (ID et dépôt visibles)'),
        _ImagePickerWidget(image: _imageAccount, onTap: () => _showImagePicker((f) => _imageAccount = f)),

        const SizedBox(height: 20),

        // ── Bouton soumettre ──────────────────────────────────────
        _XbetSubmitButton(
          isLoading: submitState is ProofLoading,
          enabled:   _imageAccount != null && _accountIdCtrl.text.isNotEmpty,
          onTap:     _submitCode,
        ).animate(delay: 240.ms).fadeIn(duration: 300.ms).slideY(begin: 0.06, end: 0),
        if (_raisonBlocageCode != null) ...[
          const SizedBox(height: 8),
          Text(_raisonBlocageCode!,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.cl.textM, fontSize: 12)),
        ],

        const SizedBox(height: 18),
        const _SortieDeSecours(),
      ],
    );
  }

  String? get _raisonBlocageCode {
    if (_accountIdCtrl.text.isEmpty) return 'Entrez l\'ID de ton compte partenaire pour continuer';
    if (_imageAccount == null)       return 'Ajoutez la capture de ton compte pour continuer';
    return null;
  }

  // ─── Actions ─────────────────────────────────────────────────────────────
  Future<void> _submitPayment() async {
    // Le champ n'est plus pre-rempli : une soumission sans montant
    // repartirait silencieusement sur l'attendu, ce qui reconstituerait
    // exactement le defaut corrige.
    final montant = double.tryParse(_amountCtrl.text.trim());
    if (montant == null || montant <= 0) {
      _showSnack('Indique le montant que tu as envoye.', isError: true); return;
    }
    final phone = '+${_selectedCountry.phoneCode}${_phoneCtrl.text.trim()}';
    if (_phoneCtrl.text.trim().length < 7) {
      _showSnack('Numéro de téléphone trop court.', isError: true); return;
    }
    final base64 = await _toBase64(_imagePayment!);
    if (base64 == null) return;
    ref.read(submitProofProvider.notifier).submit(
      type:        'payment_screenshot',
      imageBase64: base64,
      xbetId:      '',
      amount:      montant,
      senderPhone: phone,
      planId:      _planIdForSelectedPlan,
    );
  }

  /// Parcours « code promo » : rien à payer, donc rien à saisir sur l'argent.
  ///
  /// Ce formulaire réclamait un montant, un numéro Mobile Money et une seconde
  /// capture prouvant le versement. L'offre ne comporte plus de versement : ne
  /// restent que ce qui la justifie — l'identifiant du compte partenaire, la
  /// plateforme, et une capture où le premier dépôt apparaît.
  Future<void> _submitCode() async {
    if (_accountIdCtrl.text.trim().isEmpty) {
      _showSnack('ID de compte requis.', isError: true); return;
    }
    if (_imageAccount == null) {
      _showSnack('Ajoute la capture de ton compte partenaire.', isError: true);
      return;
    }
    final accountBase64 = await _toBase64(_imageAccount!);
    if (accountBase64 == null) return;

    ref.read(submitProofProvider.notifier).submit(
      type:        'xbet_account_screenshot',
      imageBase64: accountBase64,
      xbetId:      _accountIdCtrl.text.trim(),
      platform:    _platform,
      // Ni `amount`, ni `senderPhone`, ni `planId` : l'offre porte sur une
      // durée fixe décidée par le serveur, pas sur une formule choisie ici.
    );
  }

  Future<String?> _toBase64(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final ext   = file.path.split('.').last.toLowerCase();
      final mime  = ext == 'png' ? 'image/png' : 'image/jpeg';
      return 'data:$mime;base64,${base64Encode(bytes)}';
    } catch (e) {
      _showSnack('Erreur lecture image: $e', isError: true);
      return null;
    }
  }

  void _showSuccessDialog(String estimatedTime) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: context.cl.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(24, 12, 24,
          MediaQuery.of(context).viewInsets.bottom + 36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(
              color: context.cl.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 28),
          // Icône animée
          Container(
            width: 88, height: 88,
            decoration: BoxDecoration(
              gradient: RadialGradient(colors: [
                AppColors.primary.withValues(alpha: 0.2),
                AppColors.primary.withValues(alpha: 0.0),
              ]),
              shape: BoxShape.circle,
            ),
            child: Center(child: Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.4),
                  blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: const Icon(Icons.workspace_premium_rounded,
                color: Colors.white, size: 36),
            )),
          ).animate()
           .scale(begin: const Offset(0.55, 0.55), end: const Offset(1, 1),
               duration: 500.ms, curve: Curves.easeOutBack)
           .fadeIn(duration: 400.ms),
          const SizedBox(height: 20),
          Text('Preuve soumise !', style: TextStyle(
            color: context.cl.textP, fontSize: 22, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(
            'Ta demande est en cours de vérification.',
            style: TextStyle(color: context.cl.textS, fontSize: 14),
            textAlign: TextAlign.center),
          const SizedBox(height: 16),
          // Délai estimé
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.2))),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.schedule_rounded, color: AppColors.warning, size: 18),
              const SizedBox(width: 8),
              Text('Activation sous $estimatedTime',
                style: const TextStyle(
                  color: AppColors.warning, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.15))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.notifications_rounded, color: AppColors.info, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'Vous recevrez une notification push dès que ton Premium est activé.',
                style: TextStyle(color: context.cl.textS, fontSize: 12, height: 1.4))),
            ]),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton.icon(
              onPressed: () {
                ref.read(submitProofProvider.notifier).reset();
                ref.invalidate(currentSubscriptionProvider);
                context.pop();
                context.pop();
              },
              icon: const Icon(Icons.check_rounded, size: 20),
              label: const Text('Compris, j\'attends la validation',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false}) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
}

// ─── WIDGETS ─────────────────────────────────────────────────────────────────

// ─── Sélecteur de plateforme partenaire ────────────────────────────────────────
class _PlatformSelector extends StatelessWidget {
  final List<String> platforms;
  final String selected;
  final ValueChanged<String> onSelect;
  const _PlatformSelector({required this.platforms, required this.selected, required this.onSelect});

  static const _labels = {'1xbet': '1xBet', 'melbet': 'Melbet', 'betwinner': 'Betwinner'};

  static String _labelFor(String id) =>
    _labels[id] ?? (id.isEmpty ? id : '${id[0].toUpperCase()}${id.substring(1)}');

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFFA78BFA);
    return Row(children: platforms.map((id) {
      final label = _labelFor(id);
      final isSelected = selected == id;
      final isLast = id == platforms.last;
      return Expanded(
        child: Padding(
          padding: EdgeInsets.only(right: isLast ? 0 : 8),
          child: GestureDetector(
            onTap: () { HapticFeedback.selectionClick(); onSelect(id); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? purple.withValues(alpha: 0.15) : context.cl.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? purple : context.cl.border,
                  width: isSelected ? 1.5 : 0.5)),
              child: Text(label, textAlign: TextAlign.center, style: TextStyle(
                color: isSelected ? purple : context.cl.textS,
                fontSize: 13, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500)),
            ),
          ),
        ),
      );
    }).toList());
  }
}

// ─── Carte numéro de réception ────────────────────────────────────────────────
/// Carte « envoie l'argent à ce numéro ».
///
/// Affichait un numéro compilé dans le binaire. Elle reçoit désormais la liste
/// servie par l'API : un seul opérateur se comporte comme avant, plusieurs font
/// apparaître un sélecteur, aucun retombe sur la constante de repli.
class _PaymentRecipientCard extends StatefulWidget {
  final dynamic price;
  final String  planLabel;
  final List<Map<String, dynamic>> methodes;
  /// Numéro de cette étape dans le parcours — c'est la **première** action que
  /// l'utilisateur accomplit, et elle n'en portait aucun.
  final int etape;
  const _PaymentRecipientCard({
    required this.price, required this.planLabel, required this.methodes,
    required this.etape});

  @override
  State<_PaymentRecipientCard> createState() => _PaymentRecipientCardState();
}

class _PaymentRecipientCardState extends State<_PaymentRecipientCard> {
  int _choix = 0;

  @override
  void didUpdateWidget(covariant _PaymentRecipientCard old) {
    super.didUpdateWidget(old);
    // La liste peut rétrécir entre deux chargements : garder un index périmé
    // ferait planter l'accès.
    if (_choix >= widget.methodes.length) _choix = 0;
  }

  /// Numéro courant, ou `null` si le serveur n'en publie aucun.
  ///
  /// Volontairement nullable : le type oblige tout appelant à traiter le cas
  /// « pas de numéro », là où un repli en dur le faisait disparaître.
  String? get _numero {
    if (widget.methodes.isEmpty) return null;
    final n = (widget.methodes[_choix]['phone'] ?? '').toString().trim();
    return n.isEmpty ? null : n;
  }

  String get _operateur => widget.methodes.isEmpty
      ? ''
      : (widget.methodes[_choix]['label'] ?? '').toString();

  /// `22645568158` → `+226 45 56 81 58`.
  ///
  /// Onze chiffres d'affilée se recopient mal et se vérifient encore plus mal
  /// — or c'est le seul écran où une erreur de chiffre envoie l'argent à
  /// quelqu'un d'autre.
  static String formaterNumero(String brut) {
    final chiffres = brut.replaceAll(RegExp(r'\D'), '');
    if (chiffres.length < 8) return brut;
    // Indicatif UEMOA à trois chiffres (226, 225, 221…) suivi de l'abonné.
    final indicatif = chiffres.length > 8
        ? chiffres.substring(0, chiffres.length - 8)
        : '';
    final abonne = chiffres.substring(chiffres.length - 8);
    final paires = <String>[];
    for (var i = 0; i < abonne.length; i += 2) {
      paires.add(abonne.substring(i, i + 2));
    }
    final corps = paires.join(' ');
    return indicatif.isEmpty ? corps : '+$indicatif $corps';
  }

  void _copier() {
    final n = _numero;
    if (n == null) return;
    // Le presse-papiers reçoit les chiffres bruts — c'est ce que le clavier de
    // l'application Mobile Money attend ; l'écran, lui, montre la forme
    // groupée pour que l'œil puisse vérifier.
    Clipboard.setData(ClipboardData(text: n));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Numéro $_operateur copié !'),
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          AppColors.primary.withValues(alpha: 0.12),
          AppColors.primary.withValues(alpha: 0.04),
        ],
        begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.send_to_mobile_rounded, color: AppColors.primary, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(
          // `montantExact` : « 54 000 », pas « 54000 ». C'est le seul écran de
          // l'app où l'utilisateur doit recopier un montant.
          '${widget.etape}. Envoie ${montantExact(widget.price)} FCFA '
          'à ce numéro (${widget.planLabel})',
          style: const TextStyle(
            color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w700))),
      ]),

      // Sélecteur affiché seulement s'il y a un choix à faire.
      if (widget.methodes.length > 1) ...[
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < widget.methodes.length; i++)
            GestureDetector(
              onTap: () => setState(() => _choix = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: i == _choix
                    ? AppColors.primary
                    : AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: i == _choix
                      ? AppColors.primary
                      : AppColors.primary.withValues(alpha: 0.25)),
                ),
                child: Text(
                  (widget.methodes[i]['label'] ?? '').toString(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: i == _choix ? Colors.white : context.cl.textP),
                ),
              ),
            ),
        ]),
      ],

      const SizedBox(height: 10),

      // Aucun numéro publié : le dire, plutôt que d'en afficher un compilé.
      //
      // Ce cas n'était pas atteignable auparavant — la constante le masquait —
      // et c'est précisément ce qui le rendait dangereux : un serveur mal
      // configuré envoyait l'argent vers un numéro qu'il refusait de publier.
      if (_numero == null)
        _AucunMoyenPaiement()
      else
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(formaterNumero(_numero!), style: const TextStyle(
                fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              const SizedBox(height: 2),
              Text(_operateur, style: TextStyle(
                fontSize: 11, color: context.cl.textS)),
            ])),
            GestureDetector(
              onTap: _copier,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.copy_rounded, color: Colors.white, size: 14),
                  SizedBox(width: 6),
                  Text('Copier', style: TextStyle(
                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ]),
        ),

      if (_numero != null) ...[
        const SizedBox(height: 8),
        Text("Puis remplissez le formulaire ci-dessous et joignez la capture d'écran.",
          style: TextStyle(color: context.cl.textS, fontSize: 11, height: 1.4)),
      ],
    ]),
  );
}

/// Sortie de secours pour qui a déjà payé.
///
/// L'écran n'en offrait aucune. Celui qui avait envoyé son argent puis perdu
/// sa capture — galerie vidée, téléphone changé, capture jamais prise — se
/// retrouvait devant un bouton définitivement désactivé, sans personne à qui
/// s'adresser. C'est le pire moment possible pour un cul-de-sac : l'argent est
/// déjà parti.
class _SortieDeSecours extends StatelessWidget {
  const _SortieDeSecours();

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton.icon(
      onPressed: () => ContactSupport.ouvrirEmail(
        sujet: 'Paiement envoyé — capture manquante',
        // Pré-remplir la demande évite un aller-retour : sans ces éléments,
        // le support doit les réclamer avant de pouvoir chercher quoi que ce
        // soit.
        corps: "Bonjour,\n\nJ'ai envoyé mon paiement mais je n'ai pas la "
               "capture d'écran.\n\n"
               "Numéro utilisé pour l'envoi : \n"
               "Montant envoyé : \n"
               "Date et heure approximatives : \n"
               "Identifiant de la transaction (si connu) : \n\n"
               "Merci d'activer mon compte Premium.",
      ),
      icon: Icon(Icons.help_outline_rounded, size: 17, color: context.cl.textS),
      label: Text("J'ai payé mais je n'ai pas la capture",
        style: TextStyle(
          color: context.cl.textS, fontSize: 12.5, fontWeight: FontWeight.w600)),
    ),
  );
}

/// Signale un montant saisi différent de celui attendu.
///
/// Ni bloquant ni accusateur : un envoi partiel se complète, un envoi
/// supérieur se rembourse. Ce qui compte, c'est que l'écart soit dit **avant**
/// la soumission plutôt que découvert par l'administrateur.
class _AlerteEcartMontant extends StatelessWidget {
  final int saisi;
  final int attendu;
  const _AlerteEcartMontant({required this.saisi, required this.attendu});

  @override
  Widget build(BuildContext context) {
    final manque = attendu - saisi;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.30)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.error_outline_rounded, color: AppColors.warning, size: 17),
        const SizedBox(width: 9),
        Expanded(child: Text(
          manque > 0
            ? 'Il manque ${montantExact(manque)} FCFA pour activer ce plan. '
              'Complète ton envoi avant de soumettre, sinon la validation sera refusée.'
            : 'Tu as envoyé ${montantExact(-manque)} FCFA de plus que le tarif. '
              'Soumets quand même : nous régularisons à la validation.',
          style: TextStyle(color: context.cl.textP, fontSize: 11.5, height: 1.4)),
        ),
      ]),
    );
  }
}

/// Ce que voit l'utilisateur quand le serveur ne publie aucun numéro.
///
/// Un message franc vaut mieux qu'un numéro de repli : il n'expose personne à
/// envoyer de l'argent vers une destination périmée, et il dit quoi faire.
class _AucunMoyenPaiement extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.warning.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Paiement mobile momentanément indisponible',
          style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.warning)),
        const SizedBox(height: 4),
        Text("Aucun numéro de réception n'est publié pour le moment. "
             "Réessaie dans quelques minutes, ou contacte le support.",
          style: TextStyle(color: context.cl.textS, fontSize: 11.5, height: 1.4)),
      ])),
    ]),
  );
}

class _RecapCard extends StatelessWidget {
  final double amount; final String phone, xbetId;
  const _RecapCard({required this.amount, required this.phone, required this.xbetId});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.success.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.success.withValues(alpha: 0.25), width: 1)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.fact_check_rounded, color: AppColors.success, size: 16),
        SizedBox(width: 8),
        Text('Récapitulatif de ta demande', style: TextStyle(
          color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 10),
      _RecapRow('Montant',      '${montantExact(amount)} FCFA'),
      _RecapRow('N° envoyeur',  phone),
      if (xbetId.isNotEmpty) _RecapRow('ID 1xBet', xbetId),
    ]),
  );
}

class _RecapRow extends StatelessWidget {
  final String label, value;
  const _RecapRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 4),
    child: Row(children: [
      Text('$label : ', style: TextStyle(color: context.cl.textM, fontSize: 12)),
      Text(value, style: TextStyle(color: context.cl.textP, fontSize: 12, fontWeight: FontWeight.w600)),
    ]),
  );
}

class _PickerOption extends StatelessWidget {
  final IconData icon; final Color color;
  final String title, subtitle; final VoidCallback onTap;
  const _PickerOption({required this.icon, required this.color,
    required this.title, required this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Container(width: 40, height: 40,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: color, size: 22)),
    title: Text(title, style: TextStyle(color: context.cl.textP, fontSize: 14)),
    subtitle: Text(subtitle, style: TextStyle(color: context.cl.textM, fontSize: 11)),
    onTap: onTap,
  );
}

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel(this.label);
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 8),
    child: Text(label, style: TextStyle(
      color: context.cl.textS, fontSize: 12, fontWeight: FontWeight.w600)),
  );
}

class _ImagePickerWidget extends StatefulWidget {
  final File? image; final VoidCallback onTap;
  const _ImagePickerWidget({required this.image, required this.onTap});
  @override State<_ImagePickerWidget> createState() => _ImagePickerWidgetState();
}
class _ImagePickerWidgetState extends State<_ImagePickerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _scale;
  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 85),
      reverseDuration: const Duration(milliseconds: 150));
    _scale = Tween<double>(begin: 1.0, end: 0.97)
      .animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }
  @override void dispose() { _pressCtrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => _pressCtrl.forward(),
    onTapUp: (_) { _pressCtrl.reverse(); widget.onTap(); },
    onTapCancel: () => _pressCtrl.reverse(),
    child: ScaleTransition(scale: _scale, child: Container(
      height: 150,
      decoration: BoxDecoration(
        color: widget.image != null ? AppColors.success.withValues(alpha: 0.04) : context.cl.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.image != null ? AppColors.success.withValues(alpha: 0.4) : context.cl.borderSoft,
          width: widget.image != null ? 1.5 : 0.5)),
      child: widget.image != null
        ? Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Image.file(widget.image!, width: double.infinity, height: 150, fit: BoxFit.cover)),
            Positioned(top: 8, right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(20)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_rounded, color: Colors.white, size: 13),
                  SizedBox(width: 4),
                  Text('Ajoutée', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                ]))),
            Positioned(bottom: 8, right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                child: const Text('Changer', style: TextStyle(color: Colors.white, fontSize: 11)))),
          ])
        : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(width: 48, height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.add_photo_alternate_rounded, color: AppColors.primary, size: 26)),
            SizedBox(height: 8),
            Text('Appuyez pour ajouter', style: TextStyle(color: context.cl.textS, fontSize: 13)),
            SizedBox(height: 3),
            Text('Galerie ou appareil photo', style: TextStyle(color: context.cl.textM, fontSize: 11)),
          ]),
    )),
  );
}

class _SubmitButton extends StatelessWidget {
  final String label; final IconData icon;
  final bool isLoading, enabled; final VoidCallback onTap;
  const _SubmitButton({required this.label, required this.icon,
    required this.isLoading, required this.enabled, required this.onTap});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity, height: 52,
    child: ElevatedButton.icon(
      onPressed: (!isLoading && enabled) ? onTap : null,
      icon: isLoading
          ? const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Icon(icon, size: 20),
      label: Text(label),
    ),
  );
}

// ─── PROMO CODE CARD ──────────────────────────────────────────────────────────
class _PromoCodeCard extends StatefulWidget {
  final String promoCode;
  const _PromoCodeCard({required this.promoCode});
  @override State<_PromoCodeCard> createState() => _PromoCodeCardState();
}
class _PromoCodeCardState extends State<_PromoCodeCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 85),
      reverseDuration: const Duration(milliseconds: 150));
    _scale = Tween<double>(begin: 1.0, end: 0.97)
      .animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }
  @override void dispose() { _pressCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => _pressCtrl.forward(),
    onTapUp: (_) {
      _pressCtrl.reverse();
      HapticFeedback.lightImpact();
      Clipboard.setData(ClipboardData(text: widget.promoCode));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Code copié !'), behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2)));
    },
    onTapCancel: () => _pressCtrl.reverse(),
    child: ScaleTransition(
      scale: _scale,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4C1D95), Color(0xFF7C3AED), Color(0xFFA78BFA)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.35),
            blurRadius: 20, offset: const Offset(0, 8))]),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20)),
              child: const Text('CODE PROMO PARTENAIRE', style: TextStyle(
                color: Colors.white70, fontSize: 10,
                letterSpacing: 1.5, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 14),
          Text(widget.promoCode, style: const TextStyle(
            color: Colors.white, fontSize: 32,
            fontWeight: FontWeight.w900, letterSpacing: 5)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 0.5)),
            child: Row(mainAxisSize: MainAxisSize.min, children: const [
              Icon(Icons.copy_rounded, color: Colors.white, size: 14),
              SizedBox(width: 6),
              Text('Appuyer pour copier',
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      ),
    ),
  );
}

// ─── ÉTAPES CODE PROMO ────────────────────────────────────────────────────────
class _XbetSteps extends StatelessWidget {
  final TarifsPremium tarifs;
  const _XbetSteps({required this.tarifs});

  /// Le parcours ne comporte plus d'étape de paiement.
  ///
  /// Il en comptait six, dont « Envoie ton paiement — tarif réduit à partir de
  /// 7 $/mois ». L'offre remplace le versement : le dépôt chez le partenaire
  /// *est* la contrepartie, et l'étape suivante n'a plus lieu d'être.
  List<(IconData, String, String)> get _steps => [
    (Icons.language_rounded,   'Choisis une plateforme',
     'Rendez-vous sur 1xBet, Melbet ou Betwinner'),
    (Icons.person_add_rounded, 'Crée ton compte',
     "Entrez le code promo lors de l'inscription"),
    (Icons.account_balance_wallet_rounded, 'Effectue ton premier dépôt',
     "C'est lui qui ouvre droit au mois offert"),
    (Icons.photo_camera_rounded, 'Capture ton compte',
     'Ton ID et le dépôt doivent être visibles'),
    // Quatrième et dernière copie manuelle du délai — elle annonçait « 2h »
    // sans lien avec la valeur du serveur.
    (Icons.card_giftcard_rounded, 'Soumets ci-dessous',
     'Validation sous ${tarifs.delaiCode}, puis ${tarifs.libelleOffreCode}'),
  ];

  @override
  Widget build(BuildContext context) {
    const purple     = Color(0xFFA78BFA);
    const purpleDark = Color(0xFF7C3AED);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cl.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cl.border, width: 0.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('COMMENT ÇA MARCHE', style: TextStyle(
            color: context.cl.textM, fontSize: 10,
            fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 14),
          ...List.generate(_steps.length, (i) {
            final (icon, title, sub) = _steps[i];
            final isLast = i == _steps.length - 1;
            return IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Column(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [purpleDark, purple],
                        begin: Alignment.topLeft, end: Alignment.bottomRight),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(
                        color: purple.withValues(alpha: 0.3),
                        blurRadius: 8, offset: const Offset(0, 3))]),
                    child: Icon(icon, color: Colors.white, size: 18)),
                  if (!isLast)
                    Expanded(child: Container(
                      width: 2, margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [purple.withValues(alpha: 0.4), purple.withValues(alpha: 0.05)],
                          begin: Alignment.topCenter, end: Alignment.bottomCenter)))),
                ]),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const SizedBox(height: 8),
                      Text(title, style: TextStyle(
                        color: context.cl.textP, fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(sub, style: TextStyle(
                        color: context.cl.textS, fontSize: 12, height: 1.4)),
                    ]),
                  ),
                ),
              ]),
            );
          }),
        ],
      ),
    );
  }
}

// ─── BOUTON SOUMETTRE 1xBET ────────────────────────────────────────────────────
class _XbetSubmitButton extends StatelessWidget {
  final bool isLoading, enabled;
  final VoidCallback onTap;
  const _XbetSubmitButton({
    required this.isLoading, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF7C3AED);
    return GestureDetector(
      onTap: (!isLoading && enabled) ? () {
        HapticFeedback.mediumImpact();
        onTap();
      } : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.45,
        duration: const Duration(milliseconds: 200),
        child: Container(
          width: double.infinity, height: 54,
          decoration: BoxDecoration(
            gradient: enabled
              ? const LinearGradient(
                  colors: [Color(0xFF4C1D95), purple, Color(0xFFA78BFA)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight)
              : null,
            color: enabled ? null : context.cl.surface,
            borderRadius: BorderRadius.circular(16),
            border: enabled ? null : Border.all(color: context.cl.border, width: 0.5),
            boxShadow: enabled ? [BoxShadow(
              color: purple.withValues(alpha: 0.4),
              blurRadius: 16, offset: const Offset(0, 6))] : null),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (isLoading)
              const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            else
              const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(isLoading ? 'Envoi en cours…' : 'Soumettre la preuve',
              style: TextStyle(
                color: enabled ? Colors.white : context.cl.textM,
                fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PAYWALL PAGE
// ══════════════════════════════════════════════════════════════════════════════
class _PaywallPage extends StatelessWidget {
  final double monthlyPrice;
  final double annualPrice;
  final double monthlyCodePrice;
  final double annualCodePrice;
  final String promoCode;

  /// Ce que le serveur publie réellement : opérateurs disponibles, délais de
  /// validation, remise du code promo. Trois choses qui étaient écrites en dur
  /// ici et qui contredisaient la page suivante.
  final TarifsPremium tarifs;

  final String duration; // 'mensuel' | 'annuel'
  final String method;   // 'direct' | 'code'
  final void Function(String) onSelectDuration;
  final void Function(String) onSelectMethod;
  final VoidCallback onConfirm;
  final VoidCallback onClose;

  // ── Achat intégré ──────────────────────────────────────────────────────────
  /// Build publié sur un store : l'achat intégré remplace intégralement le
  /// Mobile Money. Les deux ne s'affichent jamais ensemble (Apple 3.1.1).
  final bool iapMode;
  final bool iapLoading;
  final bool iapUnavailable;
  final ProductDetails? iapProduct;
  final bool iapBusy;
  final VoidCallback onIapBuy;
  final VoidCallback onIapRestore;

  const _PaywallPage({
    required this.monthlyPrice,
    required this.annualPrice,
    required this.monthlyCodePrice,
    required this.annualCodePrice,
    required this.promoCode,
    required this.tarifs,
    required this.duration,
    this.iapMode        = false,
    this.iapLoading     = false,
    this.iapUnavailable = false,
    this.iapProduct,
    this.iapBusy        = false,
    required this.onIapBuy,
    required this.onIapRestore,
    required this.method,
    required this.onSelectDuration,
    required this.onSelectMethod,
    required this.onConfirm,
    required this.onClose,
  });

  static const _features = [
    (Icons.star_rounded,          'Pronostics VIP illimités'),
    (Icons.query_stats_rounded,    'Analyse statistique par match'),
    (Icons.leaderboard_rounded,   'Classement & statistiques'),
    (Icons.account_balance_wallet_rounded, 'Suivi bankroll avancé'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _StadiumBgPainter())),
        SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _buildHero(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                child: Column(children: [
                  _buildFeatures(context),
                  const SizedBox(height: 24),
                  _buildPlanLabel(),
                  const SizedBox(height: 12),
                  _DurationToggle(duration: duration, onChanged: onSelectDuration),
                  const SizedBox(height: 14),
                  if (iapMode)
                    _IapSection(
                      duration:    duration,
                      loading:     iapLoading,
                      unavailable: iapUnavailable,
                      product:     iapProduct,
                      busy:        iapBusy,
                      onBuy:       onIapBuy,
                      onRestore:   onIapRestore,
                    )
                  else ...[
                    _MethodCard(
                      title:      'Paiement Direct',
                      // Les opérateurs réellement publiés, pas une liste figée.
                      //
                      // « Orange Money · Wave · MTN · Moov » était écrit ici
                      // pendant que le serveur n'en publiait qu'un : cet écran
                      // promettait quatre choix, le suivant en offrait un. Et
                      // MTN n'opère même pas au Burkina Faso.
                      subtitle:   tarifs.paiementDisponible
                        ? tarifs.libelleOperateurs
                        : 'Momentanément indisponible',
                      price:      duration == 'annuel' ? annualPrice : monthlyPrice,
                      period:     duration == 'annuel' ? '/an' : '/mois',
                      badge:      duration == 'annuel' ? '2 MOIS OFFERTS' : null,
                      color:      const Color(0xFFF59E0B),
                      isSelected: method == 'direct',
                      onTap:      () => onSelectMethod('direct'),
                    ),
                    const SizedBox(height: 10),
                    _MethodCard(
                      title:      'Avec Code Promo',
                      subtitle:   'Compte partenaire + premier dépôt — rien à payer',
                      // Ce parcours ne facture plus rien : afficher un prix
                      // barré, un « /mois » ou une remise décrirait une offre
                      // qui n'existe plus.
                      price:      0,
                      period:     '',
                      badge:      tarifs.libelleOffreCode,
                      color:      const Color(0xFF7C3AED),
                      isSelected: method == 'code',
                      onTap:      () => onSelectMethod('code'),
                    ),
                    const SizedBox(height: 24),
                    _PaywallCTA(duration: duration, method: method, onTap: onConfirm),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    // Délai annoncé par le serveur (`review_delay_*`).
                    //
                    // Il était recopié à la main ici et à trois autres endroits
                    // de ce fichier. Le raccourcir côté serveur laissait quatre
                    // écrans promettre l'ancien délai — sans qu'aucune erreur
                    // ne le signale. En achat intégré il n'y a aucune
                    // validation manuelle : c'est immédiat.
                    iapMode
                      ? 'Accès Premium activé immédiatement après le paiement.'
                      : 'Activation vérifiée par notre équipe sous '
                        '${method == 'code' ? tarifs.delaiCode : tarifs.delaiDirect}.',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                    textAlign: TextAlign.center),
                  const SizedBox(height: 26),
                  _PaywallFaq(promoCode: promoCode, tarifs: tarifs, iapMode: iapMode),
                  const SizedBox(height: 18),
                  // Trois mentions qui ressemblaient à des liens sans en être :
                  // de simples `Text`, sans aucune zone tactile. Toucher
                  // « Confidentialité » ne faisait rien, et rien ne le disait.
                  //
                  // Les deux pages existaient pourtant, et étaient routées. Il
                  // manquait le geste — sur l'écran précisément où Apple exige
                  // des liens *fonctionnels* vers les conditions d'utilisation
                  // et la politique de confidentialité (3.1.2).
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _LienLegal(
                      libelle: 'CGU',
                      onTap: () => context.push('/parametres/cgu')),
                    const _PointSeparateur(),
                    _LienLegal(
                      libelle: 'Confidentialité',
                      onTap: () => context.push('/parametres/confidentialite')),
                    const _PointSeparateur(),
                    _LienLegal(
                      libelle: 'Contact',
                      onTap: () => ContactSupport.ouvrirEmail(
                        sujet: 'Question sur l\'abonnement Premium')),
                  ]),
                ]),
              ),
            ],
          ),
        ),
        // Bouton fermer
        Positioned(top: 52, right: 12,
          child: GestureDetector(
            onTap: onClose,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle),
              child: const Icon(Icons.close_rounded, color: Colors.white70, size: 18)))),
      ]),
    );
  }

  Widget _buildHero(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFD97706), Color(0xFFF59E0B)]),
            borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: const [
            Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 14),
            SizedBox(width: 6),
            Text('PRONOSTICS PREMIUM', style: TextStyle(
              color: Colors.white, fontSize: 10,
              fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          ]),
        ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0),
        const SizedBox(height: 16),
        RichText(
          textAlign: TextAlign.center,
          text: const TextSpan(
            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, height: 1.1),
            children: [
              TextSpan(text: 'PronoWin ', style: TextStyle(color: Colors.white)),
              TextSpan(text: 'PRO', style: TextStyle(
                color: Color(0xFFF59E0B),
                shadows: [Shadow(color: Color(0x80F59E0B), blurRadius: 12)])),
            ],
          ),
        ).animate(delay: 80.ms).fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0),
        const SizedBox(height: 10),
        const Text(
          'Gérez tes pronostics avec les analyses\nVIP et le suivi bankroll professionnel.',
          style: TextStyle(color: Colors.white60, fontSize: 14, height: 1.5),
          textAlign: TextAlign.center,
        ).animate(delay: 140.ms).fadeIn(duration: 350.ms),
        // La preuve sociale a été retirée, faute d'être vraie.
        //
        // Il y avait ici « 2K+ Utilisateurs Actifs » écrit en dur, précédé de
        // trois pastilles colorées portant les lettres M, A et S — dessinées
        // pour ressembler à des photos de profil d'abonnés réels. Ni le
        // nombre ni les visages ne venaient de quoi que ce soit.
        //
        // Même famille que le « N°1 en Afrique de l'Ouest » et le « +68 % de
        // réussite » déjà retirés, et même règle : sur l'écran qui demande de
        // payer, ce qu'on affirme doit être mesuré. Le taux de réussite réel
        // est déjà affiché par `_TauxReussiteReel` dans la feuille d'accroche,
        // et il se tait quand l'échantillon ne permet rien d'affirmer.
        //
        // À rebrancher le jour où un compteur d'abonnés existe côté serveur.
      ]),
    );
  }

  Widget _buildFeatures(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10, mainAxisSpacing: 10,
      childAspectRatio: 2.6,
      children: _features.asMap().entries.map((e) {
        final (icon, label) = e.value;
        return Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 0.5)),
          child: Row(children: [
            const SizedBox(width: 10),
            Container(
              width: 24, height: 24,
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: Color(0xFFF59E0B), size: 14)),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: const TextStyle(
              color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600), maxLines: 2)),
          ]),
        ).animate(delay: Duration(milliseconds: 300 + e.key * 60))
          .fadeIn(duration: 300.ms).slideY(begin: 0.08, end: 0);
      }).toList(),
    );
  }

  Widget _buildPlanLabel() {
    return Row(children: [
      Expanded(child: Divider(color: Colors.white12, height: 1)),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Text('CHOISISSEZ VOTRE OPTION', style: TextStyle(
          color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1))),
      Expanded(child: Divider(color: Colors.white12, height: 1)),
    ]);
  }
}

// ─── MENTIONS LÉGALES DU BAS DE PAYWALL ───────────────────────────────────────
/// Mention légale réellement cliquable.
///
/// La zone tactile fait 44 px de haut alors que le libellé en fait 11 : un lien
/// correctement câblé mais trop petit pour un pouce se comporte, pour celui qui
/// l'utilise, exactement comme un lien mort.
///
/// Le soulignement n'est pas décoratif — c'est ce qui distingue un lien d'une
/// mention grise. L'ancienne version, `Colors.white30` sans soulignement, ne
/// ressemblait ni à l'un ni à l'autre.
class _LienLegal extends StatelessWidget {
  final String libelle;
  final VoidCallback onTap;
  const _LienLegal({required this.libelle, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    link: true,
    child: InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
        child: Text(libelle,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            decoration: TextDecoration.underline,
            decorationColor: Colors.white38)),
      ),
    ),
  );
}

class _PointSeparateur extends StatelessWidget {
  const _PointSeparateur();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 2),
    child: Text('·', style: TextStyle(color: Colors.white24)),
  );
}

// ─── TOGGLE DURÉE (MENSUEL / ANNUEL) ──────────────────────────────────────────
// ── Achat intégré ─────────────────────────────────────────────────────────────
/// Bloc d'achat pour les builds store.
///
/// Le prix affiché vient du store, jamais de notre backend : il est déjà
/// converti dans la devise du compte et inclut les taxes locales. Afficher
/// notre prix en dollars ici mentirait à l'utilisateur au moment de payer.
class _IapSection extends StatelessWidget {
  final String duration;
  final bool loading, unavailable, busy;
  final ProductDetails? product;
  final VoidCallback onBuy, onRestore;

  const _IapSection({
    required this.duration, required this.loading, required this.unavailable,
    required this.product, required this.busy,
    required this.onBuy, required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    if (unavailable || product == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.25))),
        child: Row(children: [
          const Icon(Icons.storefront_outlined, color: AppColors.warning, size: 20),
          const SizedBox(width: 12),
          const Expanded(child: Text(
            'Les achats ne sont pas disponibles sur cet appareil pour le moment. '
            'Vérifie ta connexion et que ton compte store est bien configuré.',
            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5))),
        ]),
      );
    }

    final p = product!;
    final isAnnual = duration == 'annuel';

    return Column(children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1206), Color(0xFF2D1F0A)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.45), width: 1.2)),
        child: Column(children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(isAnnual ? 'Premium Annuel' : 'Premium Mensuel',
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(isAnnual ? 'Facturé une fois par an' : 'Facturé chaque mois',
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ])),
            if (isAnnual) Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(6)),
              child: const Text('2 MOIS OFFERTS', style: TextStyle(
                color: AppColors.success, fontSize: 9, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 14),
          // `p.price` est déjà formaté et localisé par le store.
          Text(p.price, style: const TextStyle(
            color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, height: 1)),
        ]),
      ),
      const SizedBox(height: 18),

      SizedBox(
        width: double.infinity, height: 54,
        child: ElevatedButton(
          onPressed: busy ? null : onBuy,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          child: busy
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text('S\'abonner — ${p.price}', style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
      const SizedBox(height: 10),

      // Apple exige un moyen explicite de restaurer un achat déjà effectué.
      TextButton(
        onPressed: busy ? null : onRestore,
        style: TextButton.styleFrom(foregroundColor: Colors.white60),
        child: const Text('Restaurer mes achats', style: TextStyle(fontSize: 13)),
      ),

      const SizedBox(height: 4),
      const Text(
        'Renouvellement automatique. Résiliable à tout moment depuis les '
        'réglages de ton compte store, au moins 24 h avant la fin de la période.',
        style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
        textAlign: TextAlign.center),
    ]);
  }
}

// ── FAQ du paywall ────────────────────────────────────────────────────────────
/// Le tunnel d'achat n'expliquait nulle part comment on paie, ce qu'implique
/// l'option code promo, ni ce qui se passe à l'expiration. Ces quatre questions
/// sont exactement les objections qui arrêtent l'utilisateur devant le CTA.
class _PaywallFaq extends StatelessWidget {
  final String promoCode;
  /// En achat intégré, la FAQ Mobile Money serait fausse — et mentionner un
  /// moyen de paiement externe dans une app store est précisément ce qu'Apple
  /// interdit (3.1.1).
  final bool iapMode;
  /// Délais et opérateurs publiés par le serveur : la FAQ les recopiait à la
  /// main, et devenait fausse dès qu'ils changeaient.
  final TarifsPremium tarifs;
  const _PaywallFaq({
    required this.promoCode, required this.tarifs, this.iapMode = false});

  @override
  Widget build(BuildContext context) {
    final items = iapMode
      ? const <(String, String)>[
          (
            'Comment se passe le paiement ?',
            "Le paiement est traité par ton compte App Store ou Google Play, "
            "avec le moyen de paiement qui y est déjà enregistré. Nous ne "
            "voyons jamais tes coordonnées bancaires.",
          ),
          (
            "Quand mon accès est-il activé ?",
            "Immédiatement. Il n'y a aucune validation manuelle : dès que le "
            "store confirme le paiement, le Premium est débloqué.",
          ),
          (
            "Comment résilier ?",
            "Depuis les réglages de ton compte store, au moins 24 h avant la "
            "fin de la période en cours. Ton accès reste actif jusqu'à cette "
            "échéance, et rien n'est prélevé ensuite.",
          ),
          (
            "J'ai déjà payé mais je n'ai pas l'accès",
            "Touche « Restaurer mes achats » ci-dessus. Si ton abonnement est "
            "actif sur ce compte store, il sera réappliqué aussitôt.",
          ),
        ]
      : <(String, String)>[
      (
        'Comment se passe le paiement ?',
        "Choisis ta formule, envoie le montant sur le numéro Mobile Money "
        "affiché à l'étape suivante"
        "${tarifs.paiementDisponible ? ' (${tarifs.libelleOperateurs})' : ''}, "
        "puis soumets la capture d'écran de la transaction.",
      ),
      (
        "C'est quoi l'option « Code Promo » ?",
        "Tu crées un compte sur une plateforme partenaire (1xBet, Melbet, "
        "Betwinner) avec le code $promoCode, tu fais ton premier dépôt, et tu "
        "envoies une capture de ton compte où le dépôt apparaît. Ton premier "
        "mois de Premium est alors offert — tu n'as rien à nous verser.",
      ),
      (
        "Le mois offert, c'est valable à chaque fois ?",
        "Non. Il débloque le premier mois, une seule fois. Ensuite, le "
        "renouvellement se fait au tarif normal, comme pour tout le monde.",
      ),
      (
        "En combien de temps mon compte est activé ?",
        "Paiement direct : ${tarifs.delaiDirect}. Avec code promo : "
        "${tarifs.delaiCode}, le temps de vérifier le compte partenaire.",
      ),
      (
        "Suis-je prélevé automatiquement ensuite ?",
        "Non. Il n'y a aucune reconduction : à la fin de la période ton compte "
        "repasse simplement en Gratuit. Tu renouvelles quand tu veux depuis "
        "Compte › Abonnement.",
      ),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('QUESTIONS FRÉQUENTES', style: TextStyle(
        color: Colors.white38, fontSize: 10,
        fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      const SizedBox(height: 12),
      for (final (q, a) in items) _PaywallFaqItem(question: q, answer: a),
    ]);
  }
}

class _PaywallFaqItem extends StatefulWidget {
  final String question, answer;
  const _PaywallFaqItem({required this.question, required this.answer});
  @override State<_PaywallFaqItem> createState() => _PaywallFaqItemState();
}

class _PaywallFaqItemState extends State<_PaywallFaqItem> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button:   true,
      expanded: _open,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _open = !_open);
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08))),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
                child: Row(children: [
                  Expanded(child: Text(widget.question, style: const TextStyle(
                    color: Colors.white70, fontSize: 13,
                    fontWeight: FontWeight.w600, height: 1.3))),
                  const SizedBox(width: 8),
                  Icon(
                    _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: Colors.white38, size: 20),
                ]),
              ),
              if (_open) Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 13),
                child: Text(widget.answer, style: const TextStyle(
                  color: Colors.white54, fontSize: 12, height: 1.55)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _DurationToggle extends StatelessWidget {
  final String duration;
  final ValueChanged<String> onChanged;
  const _DurationToggle({required this.duration, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white12, width: 0.5)),
    child: Row(children: [
      _DurationTab(label: 'Mensuel', selected: duration == 'mensuel',
        onTap: () => onChanged('mensuel')),
      _DurationTab(label: 'Annuel · 2 mois offerts', selected: duration == 'annuel',
        onTap: () => onChanged('annuel')),
    ]),
  );
}

class _DurationTab extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap;
  const _DurationTab({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF59E0B) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected ? [BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
            blurRadius: 8, offset: const Offset(0, 3))] : null),
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(
          color: selected ? Colors.white : Colors.white54,
          fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
      ),
    ),
  );
}

// ─── CARTE MÉTHODE DE PAIEMENT (direct ou code promo) ─────────────────────────
class _MethodCard extends StatelessWidget {
  final String title, subtitle;
  final double price;
  final String period;
  final String? badge;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;
  const _MethodCard({
    required this.title, required this.subtitle, required this.price,
    required this.period, this.badge, required this.color,
    required this.isSelected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.white12,
            width: isSelected ? 2 : 0.5),
          boxShadow: isSelected ? [BoxShadow(
            color: color.withValues(alpha: 0.15),
            blurRadius: 16, offset: const Offset(0, 4))] : null),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(title, style: const TextStyle(
                  color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                if (badge != null) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(6)),
                    child: Text(badge!, style: const TextStyle(
                      color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8))),
                ],
              ]),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('\$${price.toStringAsFixed(0)}', style: TextStyle(
                color: color, fontSize: 22, fontWeight: FontWeight.w900)),
              Text(period, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ]),
          ]),
          const SizedBox(height: 10),
          Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
          const SizedBox(height: 10),
          Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 20, height: 20,
              decoration: BoxDecoration(
                color: isSelected ? color : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? color : Colors.white24,
                  width: 1.5)),
              child: isSelected
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 13)
                : null),
            const SizedBox(width: 10),
            Expanded(child: Text(
              isSelected ? 'Sélectionné' : 'Appuyer pour sélectionner',
              style: const TextStyle(color: Colors.white54, fontSize: 11))),
          ]),
        ]),
      ),
    );
  }
}

// ─── TESTIMONIAL CAROUSEL ─────────────────────────────────────────────────────
// ─── CTA PAYWALL ──────────────────────────────────────────────────────────────
class _PaywallCTA extends StatelessWidget {
  final String duration;
  final String method;
  final VoidCallback onTap;
  const _PaywallCTA({required this.duration, required this.method, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isCode   = method == 'code';
    final isAnnuel = duration == 'annuel';
    final color    = isCode ? const Color(0xFF7C3AED) : const Color(0xFFF59E0B);
    final label    = isCode
      ? 'Continuer avec le code (${isAnnuel ? 'annuel' : 'mensuel'})'
      : (isAnnuel ? 'Passer à l\'annuel' : 'Passer au mensuel');
    return GestureDetector(
      onTap: () { HapticFeedback.mediumImpact(); onTap(); },
      child: Container(
        width: double.infinity, height: 58,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isCode
              ? [const Color(0xFF4C1D95), const Color(0xFF7C3AED)]
              : [const Color(0xFFB45309), const Color(0xFFF59E0B)],
            begin: Alignment.centerLeft, end: Alignment.centerRight),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 20, offset: const Offset(0, 6))]),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
        ]),
      ),
    ).animate(onPlay: (c) { if (!context.animationsReduites) c.repeat(reverse: true); })
      .shimmer(duration: 2200.ms, color: Colors.white10, delay: 1200.ms);
  }
}

// ─── FOND GEOMETRIQUE ─────────────────────────────────────────────────────────
class _StadiumBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF0A0E1A), Color(0xFF111827), Color(0xFF0D1117)],
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final glowOrange = Paint()
      ..shader = RadialGradient(colors: [
        const Color(0xFFF59E0B).withValues(alpha: 0.18), Colors.transparent,
      ]).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.1, size.height * 0.08), radius: size.width * 0.55));
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.08), size.width * 0.55, glowOrange);

    final glowPurple = Paint()
      ..shader = RadialGradient(colors: [
        const Color(0xFF7C3AED).withValues(alpha: 0.12), Colors.transparent,
      ]).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.9, size.height * 0.3), radius: size.width * 0.5));
    canvas.drawCircle(Offset(size.width * 0.9, size.height * 0.3), size.width * 0.5, glowPurple);

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.025)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * 0.12),
        width: size.width * 1.4, height: size.width * 0.8),
      0, 3.14, false, linePaint);
    for (int i = 1; i <= 4; i++) {
      canvas.drawLine(
        Offset(size.width * i / 5, 0),
        Offset(size.width * i / 5, size.height * 0.25), linePaint);
    }
  }

  @override bool shouldRepaint(_) => false;
}
