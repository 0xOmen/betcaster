# Betcaster - Wager with Confidence

Bespoke bets for refined degenerates

## Game Frontend URL

[]()

# Roles

Maker - Bet creator. Defines initial terms of the bet including Taker (if included), Arbiter, bet token and size, and initial terms of the bet.

Taker - The address that accepts the terms of the bet as laid out by the Maker.

Arbiter - Address that determines the outcome of the bet.

## Bet Creation

Maker defines initial terms: Taker (can be "anyone" if set to ethereum 0 address), Arbiter, Bet token and size, end time, Arbiter fee, and initial terms. Maker can cancel bet any time before Taker accepts the bet for a full token refund. Maker can also change the terms of the bet any time before Taker accepts the bet.

## Taker Actions

Taker can accept the terms as laid out by the Maker. Accepting the bet simultaneously deposits the taker's tokens. If the Maker sets the Taker address as the Ethereum zero address then any address can take the bet.

## Arbiter

The arbiter decides the outcome of the bet once the End Time is reached. The Arbiter address must be different than the Maker and Taker Addresses. The Arbiter recieves the Arbiter Fee upon deciding the outcome of the bet. If the Maker sets the Arbiter address as the Ethereum zero address then any address (excluding the Maker or Taker) can arbitrate the bet. Setting Arbiter as address(0) is high risk.

## Changing Bet Paramenters

The Maker may change certain terms of a bet (Taker, Arbiter, end time, and the betAgreement text) up until the Taker accepts the terms. This is to allow the specific terms of a bet to be negotiated without cancelling the bet. Bet token address and amounts may not be changed, to change these the bet will need to be canceled and re-made.

## Cancelling bets

If the Arbiter does not accept it's role, the Maker and Taker can cancel the bet and have their tokens returned at any time.

## Forfeiting bets

The Maker or Taker may forfeit a bet at any time after the Arbiter has accepted its role but before the arbiter has settled the bet. The entity that forfeits loses their tokens. No Arbiter fee is applied in this situation but the protcol fee is applied.

## Emergency Withdraw

If the Arbiter does not arbitrate the bet in a timely manner, either the Maker or Taker can trigger an emergency withdrawal after a pre-defined cool down period (initially 30 days).

## Arbitration

Any Ethereum account that can make smart contract function calls can act as an Arbiter. The betAgreement string variable is meant to store the terms of the bet. Individual users or Agents are the intended bet arbiters. Arbiters get paid when they call the selectWinner function after the bet end time.
