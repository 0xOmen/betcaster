# Betcaster - Wager with Confidence

Bespoke bets for refined degenerates

## Game Frontend URL

[]()

# Roles

Maker - Bet creator. Defines initial terms of the bet including Taker (if included), Arbiter, bet token and size, and initial terms of the bet.

Taker - The address that accepts the terms of the bet as laid out by the Maker.

Arbiter - Address that determines the outcome of the bet.

## Bet Creation

Maker defines initial terms: Taker (can be open), Arbiter, Bet token and size, end time, Arbiter fee, and initial terms. Maker can cancel bet any time before Taker accepts the bet and get their tokens back. Maker can also change the terms of the bet text any time before Taker accepts the bet.

## Taker Actions

Taker can accept the terms as laid out by the Maker.

## Arbiter

The arbiter decides the outcome of the bet once the End Time is reached. The Arbiter address must be different than the Maker and Taker Addresses. The Arbiter recieves the Arbiter Fee upon deciding the outcome of the bet.

## Cancelling bets

If the Arbiter does not accept it's role, the Maker and Taker can cancel the bet and have their tokens returned.

## Emergency Withdraw
