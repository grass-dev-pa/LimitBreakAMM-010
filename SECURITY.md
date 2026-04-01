# Universal Out-of-Scope Issues (DLT / Smart Contracts / Protocols)

Last updated: March 31, 2026

This is a reusable out-of-scope list for distributed ledger protocols, smart contracts, backend services, APIs, and protocol frontends.

## Interpretation Rules

- Any item below is out of scope unless a live program explicitly marks it in scope.
- Intended, documented, or accepted-by-design behavior is out of scope.
- No reproducible exploit path plus no measurable impact means out of scope.
- Self-only impact is out of scope unless the report proves forced third-party or protocol-level impact.
- If this file conflicts with a live bounty page, the live bounty page wins.

## Universal Out-of-Scope Findings

### 1. Informational / No Security Impact

- Theoretical findings with no practical exploit.
- Non-reproducible findings.
- Findings without concrete impact.
- Missing exploit path from attacker entry to damage.
- Code style, readability, naming, or refactor suggestions.
- Architecture preferences and opinion-only reviews.
- Best-practice guidance without exploitability.
- Missing comments or missing docs.
- Missing NatSpec / docstring quality issues.
- Gas optimization with no security impact.
- Build speed, test speed, or CI performance comments.
- Missing events or event index quality with no security impact.
- Warning-level lint output without vulnerability.

### 2. Duplicate / Known / Previously Disclosed

- Duplicate reports.
- Already known issues.
- Previously disclosed public issues.
- Findings already accepted from another report.
- Findings already patched internally before intake.
- Findings listed as known limitations.

### 3. Intended Design / Product Decisions

- Permissionless access where permissionless behavior is intended.
- Centralization concerns where governance model is documented.
- Business logic disagreements with intended economics.
- Token emission schedule complaints without exploit.
- Reward model complaints without exploit.
- Expected slippage behavior in AMM-like systems.
- No-KYC / no-fraud-check complaints when intentionally permissionless.
- No-circuit-breaker complaint when design intentionally avoids one.
- “No timelock” complaint where policy intentionally has none.
- “No pause” complaint where protocol is intentionally immutable.

### 4. Trusted Admin / Operator / Governance Assumptions

- Admin can upgrade contracts by design.
- Admin can pause/unpause by design.
- Admin can blacklist/whitelist by design.
- Admin can set fees/limits/parameters by design.
- Operator can rebalance/reconfigure by design.
- Governance can pass proposals with valid voting power.
- Multisig signers colluding within defined trust assumptions.
- Compromise of privileged keys not caused by protocol code vulnerability.
- Compromise of governance process by external bribery, coercion, or vote buying.
- “Admin is trusted” findings where trust is explicitly part of the model.

### 5. User Error / User-Side Compromise

- User signs malicious transactions due to phishing.
- User approves malicious spender contracts.
- User sets unlimited allowance and gets drained by third-party dApp.
- Self-harm / self-griefing actions that only damage the reporter's own account or funds.
- User sends funds to wrong address.
- User uses wrong chain, wrong token, wrong decimals, wrong memo/tag.
- User loses private key, mnemonic, or keystore.
- User device/browser malware compromises wallet actions.
- SIM swap, account takeover, credential stuffing on user-owned accounts.
- Clipboard malware replacing destination addresses.
- User misconfigures slippage/gas and takes loss.

### 6. Economic / Market Risk Without Protocol Bug

- Losses from normal market volatility.
- Impermanent loss.
- Arbitrage against pools.
- Normal frontrun/backrun/sandwich behavior not caused by protocol flaw.
- Oracle changes due to real external market moves.
- Depeg or peg drift caused by market conditions.
- Liquidity drought, spread widening, or temporary insolvency from market stress.
- Liquidation under documented collateral rules.
- Borrow rate spikes due to utilization model.
- High gas or congestion causing delayed transaction inclusion.
- Profit opportunities that depend on taking normal market risk.

### 7. Unsupported or Non-Standard Asset Behavior

- Fee-on-transfer token side effects where unsupported.
- Rebasing token side effects where unsupported.
- Reflection/deflation token behavior where unsupported.
- ERC-777 callback behavior where unsupported.
- Token blacklist/pause/admin-hook behavior that token itself defines.
- Non-standard ERC-20 return behavior outside supported token list.
- Exotic token decimal behavior not declared supported.
- Upgradeable token implementation changes by token issuer.
- Tokens with transfer restrictions not compatible with protocol assumptions.
- Malicious token logic where protocol does not claim hostile-token compatibility.

### 8. Oracle / Price Feed Categories (No Integration Bug)

- Oracle provider outage.
- Oracle stale/lagging update during provider issues.
- Price movement from legitimate market data.
- Temporary oracle divergence across venues with no protocol bypass.
- Data source maintenance windows or pauses.
- Governance-approved oracle source updates.
- Feed heartbeat behavior operating as configured.
- Oracle manipulation scenarios requiring unrealistic capital with no net exploit.

### 9. Third-Party / External Systems Not Controlled by Protocol

- Wallet software vulnerabilities.
- Browser extension vulnerabilities.
- Custodian or CEX compromise.
- Bridge provider compromise not caused by protocol code.
- RPC node provider outages.
- Indexer/subgraph outages.
- CDN/DNS/hosting provider incidents.
- Cloud region outages.
- Registrar/email provider compromise.
- Third-party API abuse unrelated to protocol-owned auth boundaries.
- Library CVEs without demonstrated reachable exploit in deployed system.

### 10. Chain / Consensus / Network-Level Assumptions

- 51% attacks or validator cartel attacks on base chain.
- Base-chain censorship not caused by protocol logic.
- Base-chain reorg/finality delays.
- Mempool privacy leakage inherent to public chains.
- Validator timestamp drift within chain tolerance rules.
- L1/L2 downtime.
- Bridge finality delay due to chain behavior.
- Chain halt events.
- Gas market spikes from global network demand.

### 11. Generic DDoS / Availability Without Security Boundary Break

- Volumetric DDoS against public endpoints.
- Generic HTTP flood without auth bypass or data integrity impact.
- P2P flood attacks not exploiting protocol-specific logic.
- “Endpoint slows down under heavy load” without exploit.
- Spam traffic that increases infra costs only.
- Transaction spam requiring attacker to pay normal chain fees.
- DoS claims that rely on unrealistic attacker budget.
- Throughput degradation with no corruption, theft, or privilege bypass.

### 12. Frontend / Web Low-Impact Findings

- Missing security headers without proven exploit impact.
- Clickjacking without sensitive state change.
- Open redirect without token theft/credential theft impact.
- Self-XSS requiring victim console paste.
- Tabnabbing without account compromise path.
- CSRF claims where wallet signature is required for state changes.
- CORS misconfiguration with no sensitive data/action exposure.
- Error message disclosure of non-sensitive info.
- Missing captcha/rate limits without practical abuse impact.
- UI text/label confusion without security impact.
- Missing autocomplete attributes without exploit impact.

### 13. API / Backend Low-Impact or Intended Exposure

- Public read-only endpoints exposed intentionally.
- GraphQL introspection enabled by design.
- Enumeration of already public resources.
- Lack of authentication on public data endpoints.
- Missing pagination limits when no security impact is demonstrated.
- Lack of strict schema validation without exploit path.
- Missing cache headers without exploit path.
- Non-sensitive stack/version disclosure.

### 14. Privacy Claims on Public-By-Design Data

- Exposure of public wallet addresses.
- Exposure of on-chain transaction history.
- Exposure of token balances and transfers already on-chain.
- Exposure of public governance votes.
- Metadata inference from public mempool/chain data.
- Username/address linkage where both are intentionally public.

### 15. Testnet / Staging / Dev / Local Artifacts

- Testnet-only vulnerabilities not reproducible in production scope.
- Dev, sandbox, staging, QA environments not listed in scope.
- Mock contracts and fixture scripts.
- Local-only scripts and example configs.
- Example keys or fake secrets in test fixtures.
- Build artifacts and generated files.
- Deprecated versions not listed as supported targets.

### 16. Physical / Social / Legal Attack Classes

- Phishing campaigns.
- Fake support impersonation.
- Social engineering employees or moderators.
- Physical theft of devices or hardware wallets.
- Office/network physical intrusion scenarios.
- Coercion, blackmail, extortion, threats.
- Legal/regulatory compliance concerns without exploit.
- Insider abuse assumptions with no software bug.

### 17. Unrealistic or Invalid Attack Preconditions

- Requires impossible timing guarantees.
- Requires full control of base chain validators.
- Requires compromise of multiple independent trusted parties.
- Requires unlimited capital or unbounded credit.
- Requires cryptographic primitive breaks.
- Requires user collusion outside protocol threat model.
- Requires attacker ability to rewrite finalized blocks.
- Requires direct database/root access not achievable through product surface.

### 18. Report Quality Failures (Automatically Non-Actionable)

- No vulnerable component identified.
- No exact affected version/commit/deployment.
- No reproducible steps.
- No proof of concept, trace, or transaction evidence.
- No stated attacker assumptions.
- No impact statement tied to confidentiality, integrity, availability, or funds.
- Scanner output only, no manual validation.
- Broken PoC or unverifiable private environment claims.

### 19. Known Standard Quirks Often Misreported

- ERC-20 approval race pattern without protocol-specific exploit.
- Rounding dust at minimal unit precision without material impact.
- Precision truncation expected from integer math where documented.
- Minor view function inconsistency with no state corruption.
- Event ordering differences with no state impact.
- Revert reason text quality issues.
- Different behavior for non-standard token contracts outside support matrix.

### 20. MEV / Transaction Ordering Claims Without Logic Flaw

- General frontrunning from public mempool visibility.
- Backrunning profitable state transitions.
- Sandwiching of user trades where protocol does not promise MEV resistance.
- Priority gas auction effects.
- Reordering by block builders/validators without protocol exploit.
- Copy-trading public pending transactions.
- Liquidation races where winner is first valid transaction.

### 21. Cross-Chain / Bridge Edge Cases Without Protocol Bug

- Delay or failure due to bridge relayer downtime.
- Message delivery delay due to source/destination chain congestion.
- External bridge guardian pause events.
- Destination chain reorg impacts.
- Token representation mismatch caused by third-party bridge wrappers.
- Replay protections functioning as configured across chain IDs.

### 22. Release / Lifecycle / Versioning Boundaries

- Findings on archived or unsupported releases.
- Findings on forks not maintained by core team.
- Findings on unofficial mirrors or cloned frontends.
- Findings on contracts not published as part of supported deployment list.
- Findings requiring undocumented manual migrations not used in production.

### 23. Low-Impact Hardening / Misconfiguration Only

- Missing SPF/DKIM/DMARC hardening without takeover impact.
- Missing HSTS or weak TLS preference without demonstrated exploit path.
- Cookie flags on non-sensitive cookies only.
- Presence of OPTIONS/TRACE methods without practical abuse.
- Non-sensitive debug endpoints with no state-changing capabilities.
- Robots.txt or sitemap disclosures with no sensitive data.
- Missing security.txt or policy metadata.
- Banner/version disclosure without exploit chain.
- Missing CSP nonce/strict-dynamic without exploit impact.
- Click-through legal pages that can be framed but have no sensitive actions.

### 24. Contract-Level False Positives

- Reentrancy warning with no reentrant path to harmful state change.
- Integer underflow/overflow claims on checked arithmetic versions.
- "Unbounded loop" claims that are user-funded and non-critical.
- Read-only reentrancy with no state impact.
- "Anyone can call function" where function is intended to be public.
- "Funds can be stuck" claims that rely on unsupported token behavior.
- "Unsafe external call" with no controllable target and no impact.
- "Front-run vulnerability" with no invariant break or value extraction path.
- "Timestamp manipulation" within accepted block tolerance and no exploit.
- "Randomness weakness" in non-security-critical randomness usage.

### 25. Authentication / Authorization False Positives

- Missing auth on endpoints intentionally public.
- Missing role check on read-only code paths.
- Privilege escalation claims requiring direct database/admin shell access.
- Account takeover claims requiring prior user credential compromise.
- Session fixation claims where wallet signature is required per action.
- Weak-password policy claims for systems that do not use password auth.
- MFA bypass claims on systems with no MFA feature in scope.

### 26. Submission and Process Abuse

- Reports containing only generic checklists without target validation.
- Bulk "spray" reports across many projects with no protocol-specific proof.
- "Potential issue" reports with no minimal proof.
- Social pressure, extortion, or ransom-style disclosure demands.
- Public disclosure before reasonable coordinated disclosure timeline.
- Requests for reward after violating testing rules or causing service harm.

### 27. Self-Impact / Self-DoS (Not Bounty-Eligible by Default)

- Self-harm scenarios where the reporter can only damage their own account, funds, or rewards.
- Self-DoS where only the caller can block their own withdrawals, claims, staking, or position updates.
- Self-liquidation or self-bad-debt caused only by reporter-controlled parameters.
- Self-burn/self-transfer to unrecoverable address when no unauthorized actor is involved.
- User-induced lockup by choosing unsafe optional parameters (pool, referrer, slippage, memo, route) with no third-party coercion.
- Reverts or stuck flow caused by invalid inputs that the same caller freely supplied.
- DoS paths that require the victim to sign and submit the exact harmful transaction themselves.
- Griefing that cannot force loss, theft, freezing, or auth bypass for other users.
- "Can brick my own wallet/account/position" findings without cross-account impact.
- Findings that need prior compromise of the victim key/wallet to trigger the impact.
- Reports that do not demonstrate involuntary impact on another user or on shared protocol solvency.

## Explicitly Rejected Examples (Common)

- "Fee-on-transfer token breaks accounting" when fee-on-transfer tokens are unsupported.
- "DDoS makes API unavailable" with no protocol-specific vulnerability.
- "Admin can change critical parameters" when admin authority is intentional.
- "Governance can pass harmful proposal" when valid governance process is followed.
- "Oracle changed too fast" when data feed operated as configured.
- "User lost funds after signing malicious tx" due to phishing or wallet compromise.
- "Low-impact frontend header issue" without asset theft or privilege escalation.
- "Chain congestion blocked liquidations" without exploitable protocol bug.
