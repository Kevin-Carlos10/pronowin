import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/transaction_entity.dart';

class MethodSelectorWidget extends StatelessWidget {
  final PaymentMethod selected;
  final String selectedProvider;
  final void Function(PaymentMethod method, String provider) onSelect;

  const MethodSelectorWidget({
    super.key,
    required this.selected,
    required this.selectedProvider,
    required this.onSelect,
  });

  static const _methods = [
    _MethodGroup(
      method: PaymentMethod.mobileMoney,
      icon: Icons.smartphone_rounded,
      iconColor: Color(0xFFF5A623),
      bgColor: Color(0x26F5A623),
      label: 'Mobile Money',
      providers: [
        _Provider('Orange Money', '🟠'),
        _Provider('Moov Money',   '🔵'),
        _Provider('MTN MoMo',     '🟡'),
      ],
    ),
    _MethodGroup(
      method: PaymentMethod.card,
      icon: Icons.credit_card_rounded,
      iconColor: Color(0xFF3B82F6),
      bgColor: Color(0x263B82F6),
      label: 'Carte bancaire',
      providers: [
        _Provider('Visa',       '💳'),
        _Provider('Mastercard', '💳'),
      ],
    ),
    _MethodGroup(
      method: PaymentMethod.crypto,
      icon: Icons.currency_bitcoin_rounded,
      iconColor: Color(0xFFA78BFA),
      bgColor: Color(0x26A78BFA),
      label: 'Crypto',
      providers: [
        _Provider('Bitcoin (BTC)',  '₿'),
        _Provider('USDT TRC20',    '💵'),
        _Provider('USDT ERC20',    '💵'),
      ],
    ),
    _MethodGroup(
      method: PaymentMethod.bankTransfer,
      icon: Icons.account_balance_rounded,
      iconColor: Color(0xFF14B8A6),
      bgColor: Color(0x2614B8A6),
      label: 'Virement bancaire',
      providers: [
        _Provider('CORIS Bank',       '🏦'),
        _Provider('Banque Atlantique','🏦'),
        _Provider('UBA',              '🏦'),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _methods.map((group) {
        final isSelected = selected == group.method;
        return GestureDetector(
          onTap: () => onSelect(group.method, group.providers.first.name),
          child: AnimatedContainer(
            duration: Duration(milliseconds: 200),
            margin: EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary.withValues(alpha: 0.06) : context.cl.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? AppColors.primary : context.cl.border,
                width: isSelected ? 1.5 : 0.5,
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: group.bgColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(group.icon, color: group.iconColor, size: 20),
                      ),
                      SizedBox(width: 14),
                      Text(group.label, style: TextStyle(
                        color: context.cl.textP, fontSize: 14, fontWeight: FontWeight.w500,
                      )),
                      Spacer(),
                      Icon(
                        isSelected ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        color: context.cl.textM, size: 20,
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Container(
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: context.cl.border, width: 0.5)),
                    ),
                    child: Column(
                      children: group.providers.map((p) {
                        final providerSelected = selectedProvider == p.name;
                        return GestureDetector(
                          onTap: () => onSelect(group.method, p.name),
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: providerSelected ? AppColors.primary.withValues(alpha: 0.08) : Colors.transparent,
                              border: p != group.providers.last
                                  ? Border(bottom: BorderSide(color: context.cl.border, width: 0.5))
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Text(p.emoji, style: TextStyle(fontSize: 18)),
                                SizedBox(width: 12),
                                Text(p.name, style: TextStyle(
                                  color: providerSelected ? AppColors.primary : context.cl.textS,
                                  fontSize: 13,
                                  fontWeight: providerSelected ? FontWeight.w600 : FontWeight.w400,
                                )),
                                const Spacer(),
                                if (providerSelected)
                                  const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 18),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _MethodGroup {
  final PaymentMethod method;
  final IconData icon;
  final Color iconColor, bgColor;
  final String label;
  final List<_Provider> providers;
  const _MethodGroup({
    required this.method, required this.icon, required this.iconColor,
    required this.bgColor, required this.label, required this.providers,
  });
}

class _Provider {
  final String name, emoji;
  const _Provider(this.name, this.emoji);
}
