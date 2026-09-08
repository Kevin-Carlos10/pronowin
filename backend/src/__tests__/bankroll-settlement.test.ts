import {
  _settlementBalanceDelta,
  _settlementCredit,
  _settlementProfit,
} from '../services/bankroll.service';

const bet = { stakedAmount: 5_100, potentialGain: 7_038 };

describe('bankroll settlement correction', () => {
  it('credits the full return when a loss is corrected to a win', () => {
    expect(_settlementProfit('LOSS', bet)).toBe(-5_100);
    expect(_settlementProfit('WIN', bet)).toBe(1_938);
    expect(_settlementBalanceDelta('LOSS', 'WIN', bet)).toBe(7_038);
  });

  it('does not move the balance when the same verdict is replayed', () => {
    expect(_settlementBalanceDelta('WIN', 'WIN', bet)).toBe(0);
  });

  it('reverses a prior settlement when a result is reopened', () => {
    expect(_settlementCredit('PUSH', bet)).toBe(5_100);
    expect(_settlementBalanceDelta('WIN', null, bet)).toBe(-7_038);
    expect(_settlementProfit(null, bet)).toBeNull();
  });
});
