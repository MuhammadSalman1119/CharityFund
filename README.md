# CharityFund — Transparent On-Chain Charity with Milestone Releases

[![Solidity](https://img.shields.io/badge/Solidity-0.8.20-blue)](https://soliditylang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Networks](https://img.shields.io/badge/Networks-Ethereum%20%7C%20Polygon%20%7C%20Arbitrum%20%7C%20Base-purple)]()

---

## Problem Statement

Charitable giving suffers from opacity — donors rarely know where their money goes or whether it achieves impact. High-profile scandals have eroded trust in NGOs. This contract solves that by:

1. **Locking all donations** in a smart contract — no one can move funds without following the rules.
2. **Requiring milestone proof** (IPFS-linked reports, photos, receipts) before any funds are released.
3. **Allowing proportional refunds** if a milestone deadline is missed — putting donors in control.

---

## How It Works

```
Campaign Manager                   Donors                   Blockchain
       │                              │                         │
       │── createCampaign() ─────────►│                         │
       │   (name, milestones,         │                         │
       │    deadlines, amounts)        │                         │
       │                              │── donate() ────────────►│
       │                              │   (ETH locked in        │
       │                              │    contract)            │
       │── submitMilestoneProof() ───────────────────────────►  │
       │   (IPFS CID of evidence)     │                         │
       │── releaseMilestoneFunds() ──────────────────────────►  │
       │   (funds sent to manager)    │                         │
       │                              │                         │
       │   [if deadline missed]       │                         │
       │                              │── markExpired() ───────►│
       │                              │── claimRefund() ───────►│
       │                              │   (proportional ETH     │
       │                              │    returned)            │
```

### Milestone States

```
Pending ──► ProofSubmitted ──► Released
  │
  └──► Expired  (deadline passed without proof)
```

---

## Real-World Use Cases

- **Disaster relief funds** — release tranches as shelters, food, medicine are delivered with photo proof
- **Community infrastructure** — release funds as construction phases are completed
- **Education programmes** — release per semester with attendance/grade reports
- **Environmental projects** — release per verified tree-planting batch

---

## Setup & Deployment

### Prerequisites

```bash
npm install -g hardhat
npm install --save-dev @nomicfoundation/hardhat-toolbox dotenv
```

### Configure `.env`

```
PRIVATE_KEY=your_wallet_private_key
RPC_URL=https://polygon-mainnet.g.alchemy.com/v2/YOUR_KEY
ETHERSCAN_API_KEY=your_etherscan_key
```

### Deploy

```bash
npx hardhat run scripts/deploy.js --network polygon
npx hardhat verify --network polygon DEPLOYED_ADDRESS
```

---

## Usage Examples

### 1 — Create a Campaign

```javascript
const oneMonth  = 30 * 24 * 3600;
const twoMonths = 60 * 24 * 3600;
const now       = Math.floor(Date.now() / 1000);

await charityFund.createCampaign(
  "Clean Water for Nairobi",
  "Install 50 water filtration units across informal settlements — QmXyz",
  ethers.parseEther("10"),                       // 10 ETH goal
  ["Purchase materials", "Installation complete", "3-month impact report"],
  [
    ethers.parseEther("3"),
    ethers.parseEther("5"),
    ethers.parseEther("2"),
  ],
  [now + oneMonth, now + twoMonths, now + twoMonths + oneMonth]
);
```

### 2 — Donate

```javascript
await charityFund.donate(campaignId, { value: ethers.parseEther("0.5") });
```

### 3 — Submit Proof & Release

```javascript
// Manager submits IPFS proof for milestone 0
await charityFund.submitMilestoneProof(
  campaignId, 0,
  "QmMilestone0EvidenceIPFSHash"
);

// Manager releases the funds
await charityFund.releaseMilestoneFunds(campaignId, 0);
```

### 4 — Claim Refund (if milestone expires)

```javascript
// Anyone can mark a milestone expired after deadline
await charityFund.markExpired(campaignId, 1);

// Donor claims proportional refund
await charityFund.claimRefund(campaignId);
```

---

## Uploading Proof to IPFS

Use [web3.storage](https://web3.storage) or [Pinata](https://pinata.cloud):

```bash
# Using IPFS CLI
ipfs add --recursive ./evidence-folder
# Returns: QmXyz...
```

Store the resulting CID in the contract via `submitMilestoneProof()`.

---

## Security Considerations

- **CEI pattern**: `donations` mapping zeroed before ETH transfer in `claimRefund` — prevents reentrancy.
- **Proportional refunds**: Refund = `(userDonation / totalRaised) × contractBalance` — fair even if partial releases occurred.
- **Deadline validation**: Milestones must have strictly increasing deadlines enforced at creation.
- **No admin backdoor**: The manager can only receive funds after submitting verifiable IPFS proof.
- **Production upgrade**: Replace single-manager approval with a donor vote (add `CommunityGovernance`) for fully trustless operation.

---

## Testing

```bash
npx hardhat test
npx hardhat coverage
```

Key test scenarios:

- Full happy path: create → donate → submit proof → release × N milestones
- Expired milestone → refund claim
- Double refund attempt → revert
- Manager cannot release without proof
- Donation after campaign closed → revert

---

## Bounty Platform Checklist

- [x] Full NatSpec on all public/external functions
- [x] SPDX licence identifier
- [x] Pinned pragma `^0.8.20`
- [x] Custom errors (gas-efficient)
- [x] Events on every state change
- [x] IPFS integration for transparent proof
- [x] Reentrancy safe (CEI)
- [x] No `tx.origin` usage
- [x] Deployment + test scripts

---

## License

MIT — see [LICENSE](LICENSE)
