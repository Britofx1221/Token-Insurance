# DeFi Shield: Decentralized Insurance Staking Protocol

## Overview

DeFi Shield is a decentralized insurance platform built on the Stacks blockchain that enables users to stake tokens into a collective pool, earn proportional rewards, and benefit from coverage against specified risks. The protocol employs a democratic claim processing mechanism and features time-locked staking to ensure pool stability.

## Key Features

- **Collective Insurance Pool**: Users stake STX tokens to create a shared insurance fund
- **Staking Rewards**: Earn continuous rewards based on stake amount and duration
- **Time-Locked Staking**: 24-hour lockup period to ensure pool stability
- **Transparent Claim Processing**: Clear governance mechanism for processing insurance claims
- **Democratic Governance**: Adjustable approval threshold for claim validation

## Protocol Constants

| Parameter | Value | Description |
|-----------|-------|-------------|
| Minimum Stake | 1,000,000 μSTX (1 STX) | Minimum required deposit |
| Lockup Period | 144 blocks (~24 hours) | Time before withdrawals are permitted |
| Default Reward Rate | 1% (100 basis points) | Annual staking reward rate |
| Governance Threshold | 51% (5100 basis points) | Default approval requirement |

## Error Codes

| Code | Description |
|------|-------------|
| 100 | Unauthorized access |
| 101 | Insufficient balance |
| 102 | Stake not found |
| 103 | Claim already processed |
| 104 | Claim rejected |
| 105 | Minimum stake requirement not met |
| 106 | Lockup period still active |
| 107 | Threshold limit exceeded |

## User Functions

### Staking Operations

#### `deposit-stake`
Deposit tokens into the insurance pool.
```clarity
(deposit-stake <deposit-amount>)
```
- **Parameters**: 
  - `deposit-amount`: Amount of STX to stake (minimum 1 STX)
- **Returns**: OK with staked amount or ERROR

#### `withdraw-stake`
Withdraw tokens from the insurance pool.
```clarity
(withdraw-stake <withdrawal-amount>)
```
- **Parameters**: 
  - `withdrawal-amount`: Amount of STX to withdraw
- **Returns**: OK with withdrawn amount or ERROR
- **Note**: Can only be executed after the lockup period has passed

#### `harvest-rewards`
Claim accrued staking rewards.
```clarity
(harvest-rewards)
```
- **Returns**: OK with reward amount or ERROR

### Insurance Claim Operations

#### `file-insurance-claim`
Submit a new insurance claim.
```clarity
(file-insurance-claim <requested-amount> <claim-justification>)
```
- **Parameters**: 
  - `requested-amount`: Amount of STX requested as payout
  - `claim-justification`: String explaining the claim basis (max 256 UTF-8 characters)
- **Returns**: OK with claim ID or ERROR

## Read-Only Functions

#### `get-participant-details`
Get participant staking information.
```clarity
(get-participant-details <participant-address>)
```

#### `get-claim-details`
Get insurance claim details.
```clarity
(get-claim-details <claim-reference-id>)
```

#### `get-pool-liquidity`
Get total assets in pool.
```clarity
(get-pool-liquidity)
```

#### `get-historical-payouts`
Get historical insurance payouts.
```clarity
(get-historical-payouts)
```

#### `calculate-pending-rewards`
Calculate pending reward distribution for a participant.
```clarity
(calculate-pending-rewards <participant-address>)
```

## Administrative Functions

These functions are restricted to the contract administrator.

#### `evaluate-claim`
Evaluate and process an insurance claim.
```clarity
(evaluate-claim <claim-reference-id> <approve-claim>)
```

#### `configure-reward-rate`
Update protocol reward distribution rate.
```clarity
(configure-reward-rate <new-rate-basis-points>)
```

#### `configure-governance-threshold`
Adjust governance threshold for claim approvals.
```clarity
(configure-governance-threshold <new-threshold-basis-points>)
```

## Usage Example

### Staking Tokens
```clarity
;; Deposit 5 STX into the insurance pool
(contract-call? .defi-shield deposit-stake u5000000)

;; Harvest accrued rewards
(contract-call? .defi-shield harvest-rewards)

;; Withdraw 2 STX from the insurance pool (after lockup period)
(contract-call? .defi-shield withdraw-stake u2000000)
```

### Filing a Claim
```clarity
;; Submit an insurance claim for 1 STX
(contract-call? .defi-shield file-insurance-claim u1000000 "Account compromised due to contract vulnerability")
```

## Protocol Design Considerations

1. **Time-Locked Staking**: Implements a 24-hour lockup period to prevent "stake & run" exploits during claim events
2. **Reward Distribution**: Uses block-based calculation to determine rewards based on staking duration
3. **Claim Processing**: Claims require administrative approval with a configurable threshold
4. **Pool Management**: Automatically updates pool balance tracking for deposits, withdrawals, and claim payouts

## Security Considerations

- Admin privileges are required for claim evaluation - consider implementing community governance
- Consider adding event emission for improved transparency of protocol activity
- Protocol uses microSTX units (1 STX = 1,000,000 μSTX) for all calculations

## Future Enhancements

1. Decentralized claim evaluation via staker voting
2. Multi-token support for both staking and payouts
3. Risk-adjusted premiums based on coverage types
4. Integration with oracle services for automated claim triggers