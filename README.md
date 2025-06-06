| Section                            | Link                                                                     |
| ---------------------------------- | ------------------------------------------------------------------------ |
| Overview                           | [Overview](#overview)                                                    |
| Contracts & Modules                | [Contracts & Modules](#contracts--modules)                               |
| Stock Model Workflow               | [Stock Model Workflow](#stock-model-workflow)                            |
| Mainnet Deployment Addresses       | [Mainnet Deployment Addresses](#mainnet-deployment-addresses)            |
| Integration & Architecture Details | [Integration & Architecture Details](#integration--architecture-details) |
| Getting Started (Developer Setup)  | [Getting Started (Developer Setup)](#getting-started-developer-setup)    |
| License                            | [License](#license)                                                      |

---

## Overview

The Nex “Stock Model” is a smart-contract framework designed to tokenize and manage stock shares on-chain. Instead of tracking purely cryptocurrency tokens, this model integrates with Dinari’s order processing protocol to buy and sell tokenized shares (e.g., broad-market or single-stock tokens).

Key features:

* **Request-Based Issuance & Redemption:** Users submit mint (issuance) or burn (redemption) requests for “stock tokens” denominated in USDC.
* **Approval Flow:** Authorized operators or the protocol’s balancer contract review and execute (or cancel) those requests by interacting with Dinari’s order books.
* **Rebalancing:** Periodic portfolio reweighting to maintain target allocations, based on an off-chain oracle’s guidance.
* **Fractional & Divisible:** Shares (wrapped D‐share tokens) can be issued and burned in fractional units, with precise on‐chain accounting.
* **Vault Custody:** A dedicated Vault contract holds wrapped D‐shares on behalf of users; withdrawals only happen upon order fulfillment.

---

## Contracts & Modules

Below is a high‐level description of each component. Code specifics are omitted—only roles and interactions are noted.

1. ### `IndexFactory`

   * **Role:** Primary user‐facing entry point for minting and burning stock tokens.
   * **Responsibilities:**

     * **Issuance Requests:** Accepts user USDC, computes fee, splits USDC into per‐stock amounts based on current weights from `FunctionsOracle`. Submits buy orders via `OrderManager`.
     * **Cancellation:** Allows users to cancel pending issuance before all sub‐orders are filled (or cancel partially filled orders, rebuying if needed).
     * **Redemption Requests:** Burns a user’s index tokens, computes proportional wrapped‐D‐share amounts, and submits sell orders via `OrderManager`.
     * Emits `RequestIssuance`, `RequestCancelIssuance`, `RequestRedemption`, and `RequestCancelRedemption` events.

2. ### `IndexFactoryBalancer`

   * **Role:** Executes periodic rebalance operations to align the on‐chain portfolio to oracle‐provided target weights.
   * **Responsibilities:**

     * **First Rebalance (Sell Overweighted):** Pauses new issuance, fetches current vault D‐share values per token (via `FunctionsOracle`), identifies overweight tokens, submits sell orders for surplus wrapped D‐shares.
     * **Second Rebalance (Buy Underweighted):** Once all sell orders complete, collects USDC proceeds, identifies underweight tokens, submits buy orders to fill shortfall.
     * Emits `FirstRebalanceAction`, `SecondRebalanceAction`, and `CompleteRebalanceActions` events.
     * Pauses/unpauses the main `IndexFactory` during a rebalance.

3. ### `IndexFactoryProcessor`

   * **Role:** Finalizes issuance and redemption once all component orders are fulfilled.
   * **Responsibilities:**

     * **CompleteIssuance:** Verifies all buy orders succeeded, retrieves received stock tokens from `OrderManager`, deposits them into `NexVault` (wrapped D‐share), computes mint amount of the index token (based on before/after portfolio values), and mints to user.
     * **CompleteCancelIssuance:** Once cancellation orders finalize, refunds user USDC for any unfilled/cancelled sub‐orders.
     * **CompleteRedemption:** Verifies sell orders succeeded, collects USDC proceeds, deducts protocol fee, and transfers net USDC back to user.
     * **CompleteCancelRedemption:** If a redemption is cancelled after partial fills, returns wrapped D‐shares back to vault and mints the burned index tokens back to the user.
     * Exposes `multical(_requestId)` to let off‐chain keepers trigger the correct completion method based on action type.

4. ### `IndexFactoryStorage`

   * **Role:** Central storage for parameters, nonces, request IDs, and per‐nonce state.
   * **Responsibilities:**

     * Keeps track of issuanceNonce and redemptionNonce.
     * Maps each nonce + token to its corresponding Dinari order IDs (issuance, cancellation, redemption, cancellation of redemption).
     * Stores request metadata: requester addresses, input amounts, primary balances, and completion flags.
     * Tracks pending rebalance amounts per token & nonce.
     * Provides utility view functions:

       * `getVaultDshareBalance(token)`: current wrapped D‐share units in the vault plus pending rebalance.
       * `getVaultDshareValue(token)`: D‐share balance × price (on‐chain or via Chainlink feed).
       * `getPortfolioValue()`, `getIndexTokenPrice()`: aggregated on‐chain portfolio metrics.
       * Fee calculations for Dinari orders (flat fee + percentage).

5. ### `OrderManager`

   * **Role:** Simplified proxy that all factories call to interact with Dinari’s `IOrderProcessor`.
   * **Responsibilities:**

     * **`requestBuyOrder(...)` / `requestBuyOrderFromCurrentBalance`:** Creates a new buy order on Dinari using standard fees, transferring USDC to `IOrderProcessor`.
     * **`requestSellOrder(...)` / `requestSellOrderFromCurrentBalance`:** Creates a new sell order on Dinari, transferring the token to `IOrderProcessor`.
     * **`cancelOrder(requestId)`:** Cancels any active Dinari order.
     * **`withdrawFunds(token, to, amount)`:** Moves filled/unspent funds back to caller (either Vault or user).

6. ### `IndexToken`

   * **Role:** ERC20 representing the stock index basket.
   * **Key Features:**

     * **Mint & Burn:** Only allowed by designated minter(s) (the processor).
     * **Inflationary Fee:** Daily‐scaled fee accrues to `feeReceiver` (compounded via `_mintToFeeReceiver`).
     * **Supply Ceiling:** Hard cap on total supply.
     * **Restricted Addresses:** Blacklist certain addresses from transfers.
     * Emits events on fee settings, methodology updates, and minter toggles.

7. ### `NexVault`

   * **Role:** Custodial container for wrapped D‐shares.
   * **Responsibilities:**

     * Only permitted operators (factory, balancer, processor) can call `withdrawFunds(token, to, amount)`.
     * Emits `FundsWithdrawn` events on each withdrawal.

8. ### `FunctionsOracle`

   * **Role:** Off‐chain or on‐chain oracle storing the current list of stock tokens and their target weights (market share).
   * **Responsibilities:**

     * `currentList()`, `tokenCurrentMarketShare()`, and `totalCurrentList()` allow factories and processors to iterate over all constituent stocks.
     * `isOperator(address)` gatekeeps which addresses can trigger rebalances or modify the oracle.

9. ### Dinari Integrations (`IOrderProcessor`, `FeeLib`)

   * **Role:** Enables creation, cancellation, and querying of on‐chain orders for tokenized stock trades.
   * **Responsibilities:**

     * `getStandardFees`, `getReceivedAmount`, `getUnfilledAmount`, and `getOrderStatus` allow factories to track the lifecycle of each sub‐order.
     * `OrderType.MARKET` orders are used exclusively (no custom price).
     * `FeeLib.applyPercentageFee` calculates the marketplace percentage component on top of flat fees.

---

## Stock Model Workflow

1. **Issuance (Minting)**

   1. User calls `IndexFactory.issuanceIndexTokens(inputUSDC)`.
   2. Protocol computes:

      * Static fee = `(inputUSDC * feeRate) / 10000` (paid immediately to `feeReceiver`).
      * Dinari order fees per stock: for each token in `FunctionsOracle.currentList()`, compute `amount = inputUSDC × tokenShare`.
   3. Transfer `inputUSDC + DinariFees` from user → `OrderManager`.
   4. For each stock token:

      * Call `OrderManager.requestBuyOrder(tokenAddress, tokenAmount, OrderManager)`.
      * Store the returned `orderId` in `IndexFactoryStorage.issuanceRequestId[nonce][tokenAddress]`.
   5. Emit `RequestIssuance(nonce, user, USDC, inputUSDC, 0, timestamp)`.
   6. **Off‐Chain Keeper:** Monitor all `orderId`s. Once all are `FULFILLED`, call `IndexFactoryProcessor.completeIssuance(nonce)`.

      * The processor:

        * Withdraws actual filled stock tokens from `OrderManager`.
        * Wraps them into `WrappedDShare` and deposits to `NexVault`.
        * Computes new total supply vs. old portfolio value → mint delta index tokens to user.
        * Marks `issuanceIsCompleted[nonce] = true`.

2. **Cancel Issuance**

   1. User calls `IndexFactory.cancelIssuance(nonce)` before full fill.
   2. For each sub‐order:

      * If not yet filled: cancel via `OrderManager.cancelOrder(orderId)` and record `cancelIssuanceUnfilledAmount[nonce][token]`.
      * If partially/completely filled: mark for a sell‐back:

        * Redeem wrapped D‐share to underlying stock token.
        * Submit a sell order for that amount via `OrderManager.requestSellOrderFromCurrentBalance`.
        * Store new `cancelRequestId` in `cancelIssuanceRequestId[nonce][token]`.
   3. Emit `RequestCancelIssuance(nonce, user, USDC, inputUSDC, 0, timestamp)`.
   4. **Off‐Chain Keeper:** Once all cancellation/sell orders are `FULFILLED`, call `IndexFactoryProcessor.completeCancelIssuance(nonce)`:

      * Withdraw leftover USDC from `OrderManager` (filled sells minus fees) + any unfilled USDC.
      * Return full USDC refund to user. Mark `cancelIssuanceCompleted[nonce] = true`.

3. **Redemption (Burning)**

   1. User calls `IndexFactory.redemption(inputIndexTokens)`.
   2. Protocol:

      * Burns `inputIndexTokens` from user → compute `burnPercent = inputIndexTokens / totalSupply`.
      * For each stock token:

        * Compute `wrappedBalance = NexVault.getWrappedBalance(token)`.
        * Compute `burnAmount = burnPercent × wrappedBalance`.
        * Call `OrderManager.requestSellOrder(token, burnAmount, OrderManager)`.
        * Store `orderId` in `redemptionRequestId[nonce][token]`.
   3. Emit `RequestRedemption(nonce, user, USDC, inputIndexTokens, 0, timestamp)`.
   4. **Off‐Chain Keeper:** When all sell orders `FULFILLED`: call `IndexFactoryProcessor.completeRedemption(nonce)`:

      * Withdraw USDC proceeds from `OrderManager`, deduct protocol fee, and send net USDC to user. Mark `redemptionIsCompleted[nonce] = true`.

4. **Cancel Redemption**

   1. User calls `IndexFactory.cancelRedemption(nonce)` before full fill.
   2. For each sub‐order:

      * If not yet filled: cancel via `OrderManager.cancelOrder(orderId)` and record `cancelRedemptionUnfilledAmount[nonce][token]`.
      * If partially/completely filled: call `_cancelExecutedRedemption` to buy back stock tokens using USDC proceeds (via a secondary buy order), then re‐wrap into D‐shares and deposit into vault.
   3. Emit `RequestCancelRedemption(nonce, user, USDC, inputIndexTokens, 0, timestamp)`.
   4. **Off‐Chain Keeper:** Once all sub‐orders complete, call `IndexFactoryProcessor.completeCancelRedemption(nonce)`:

      * Withdraw newly acquired stock tokens from `OrderManager`, wrap & deposit to vault.
      * Mint burned `inputIndexTokens` back to user. Mark `cancelRedemptionCompleted[nonce] = true`.

5. **Rebalancing**

   1. **First Rebalance (Sell Overweight):**

      * Call `IndexFactoryBalancer.firstRebalanceAction()`.
      * For each token: fetch `getVaultDshareValue(token)` → build `portfolioValue`.
      * If `tokenValuePercent > targetShare`, compute `sellAmount` = surplus wrapped D‐share units.
      * Submit `OrderManager.requestSellOrder(token, sellAmount, OrderManager)` and record `rebalanceSellAssetAmountById`.
      * Emit `FirstRebalanceAction(nonce, timestamp)` and pause `IndexFactory`.
   2. **Off‐Chain Keeper:** Wait for all sell orders `FULFILLED`. Then call `IndexFactoryBalancer.secondRebalanceAction(nonce)`:

      * Collect total USDC proceeds after fees.
      * For each token where actual < target: compute `paymentAmount = shortagePercent × USDCbalance / totalShortagePercent`.
      * Submit `OrderManager.requestBuyOrder(token, paymentAmountAfterFees, OrderManager)`. Record `rebalanceBuyPaidAmountById`.
      * Emit `SecondRebalanceAction(nonce, timestamp)`.
   3. **Off‐Chain Keeper:** Wait for all buy orders `FULFILLED`. Then call `IndexFactoryBalancer.completeRebalanceActions(nonce)`:

      * Withdraw purchased tokenAmount from `OrderManager`, wrap into D‐shares, deposit to vault.
      * Update oracle’s current list via `FunctionsOracle.updateCurrentList()`, unpause `IndexFactory`, and emit `CompleteRebalanceActions(nonce, timestamp)`.

---

## Mainnet Deployment Addresses

All contracts are deployed on Ethereum mainnet under the “STOCK” product.

| Component                | Address                                    |
| ------------------------ | ------------------------------------------ |
| **IndexToken**           | 0xF04D96e9cFD651a55D439415598568512a49B72d |
| **IndexFactoryStorage**  | 0x76781906CE1A79F98980D88C245433c2897Ac909 |
| **IndexFactory**         | 0xa481B9357C150A206b74c815fF6bCEc3D0786Ce9 |
| **IndexFactoryBalancer** | 0xFD05fd8aC336006ddb6201Bf3798A0fC10D15088 |
| **Vault (NexVault)**     | 0xC9d9Ba338e31B1d3ce3110FF1DC07c0af6B6849B |
| **FunctionsOracle**      | 0x2dFA34630Dfc4619727B73166E27a770ED1121B0 |
| **FactoryProcessor**     | 0x24D193bA32E51d5a88b63fa0a754d365EAbf8051 |
| **OrderManager**         | 0xB79962F154cD86dFBa1EF8BA5Aa224771a1aB2f2 |

---

## Integration & Architecture Details

* **Tokenized Stock Shares (Wrapped D‐Share):** Each on‐chain “stock” is represented as a wrapped D‐share token. The underlying off‐chain asset is a real‐world stock share, but on‐chain it behaves like an ERC20.

* **Dinari Order Processing:**

  * All buy/sell requests for stocks flow through Dinari’s `IOrderProcessor` (standard fees apply).
  * `OrderManager` enforces that only authorized operators (factory, balancer, processor) can submit or cancel orders on behalf of the protocol.
  * The protocol pays a combination of flat and percentage fees per stock order.

* **Oracle & Target Weights:**

  * `FunctionsOracle` holds the list of stock tokens and their target “market share” percentages (in 1e18 units).
  * During issuance, each stock’s contribution is `inputUSDC × tokenMarketShare`.
  * During rebalance, deviations are detected by comparing on‐chain vault value vs. oracle share.

* **Fee Structure:**

  * **Protocol Fee:** A small basis‐point fee on either mint or redemption, set by `IndexFactoryStorage.feeRate` (0.01%–1%), collected in USDC.
  * **Dinari Order Fees:** Flat fee + percentage of order amount. Paid upfront or deducted at fill time.

* **Protected Vault (NexVault):**

  * Only operators (Factory, Balancer, Processor) can call `withdrawFunds`.
  * All wrapped D‐shares of constituent stocks reside in this single Vault per chain.

* **Upgradeability & Access Control:**

  * All core contracts (`IndexFactory`, `IndexFactoryBalancer`, `IndexFactoryProcessor`, `IndexFactoryStorage`, `OrderManager`, `IndexToken`, `NexVault`) use OpenZeppelin’s upgradeable proxies (`Initializable`, `OwnableUpgradeable`, etc.).
  * Only `owner()` or `FunctionsOracle.isOperator(...)` may perform protocol‐level actions (rebalance triggers, storage updates).

* **Rebalance Orchestration:**

  * Off‐chain keepers or a continuous integration service must monitor Dinari order statuses to know when to trigger “complete” calls.
  * Each sub‐order’s status is tracked in storage via `actionInfoById[requestId]` to know whether issuance, redemption, cancellation, or rebalance steps are finished.
  * The `multical(requestId)` helper can be called on any involved contract to proceed to the next stage automatically when all conditions are met.

---

## Getting Started (Developer Setup)

1. **Clone & Install**

   ```bash
   git clone git@github.com:nexlabs22/Nex-Stock-Index-Contracts.git
   cd Nex-Stock-Index-Contracts
   npm install
   forge install
   ```

2. **Environment Variables**
   Create a `.env` file with your RPC endpoints and private key:

   ```env
   MAINNET_RPC_URL="https://mainnet.infura.io/v3/YOUR_INFURA_KEY"
   PRIVATE_KEY="0xYOUR_PRIVATE_KEY"
   ```

3. **Compile & Test**

   ```bash
   forge compile
   forge build
   ```

4. **Deploy Contracts**

   * **IndexFactoryStorage:** Initialize with parameters: `(_issuer, _token, _vault, _usdc, _usdcDecimals, _functionsOracle, _isMainnet)`
   * **NexVault:** Call `initialize(operatorAddress)` then grant operator rights to `IndexFactory`, `IndexFactoryBalancer`, and `IndexFactoryProcessor`.
   * **OrderManager:** Deploy with `initialize(_usdc, _usdcDecimals, _issuer)`, set `isOperator` for factories.
   * **FunctionsOracle:** Deploy or point to the existing oracle that will supply stock token lists and weights.
   * **IndexToken:** Deploy with `initialize(name, symbol, feeRatePerDayScaled, feeReceiver, supplyCeiling)`. Grant `isMinter[processor] = true`.
   * **IndexFactory, IndexFactoryBalancer, IndexFactoryProcessor:** Deploy each, passing in the storage and oracle addresses. Register each as `factory*, factoryBalancer*, factoryProcessor*` in `IndexFactoryStorage`.
   * **OrderManager & Dinari Setup:** Ensure `OrderManager.issuer = DinariOrderProcessor`, and that `usdc` is funded to allow trade execution.

5. **Configure Oracle & Wrapped D-Shares**

   * Call `IndexFactoryStorage.setWrappedDshareAndPriceFeedAddresses([stockTokens],[wrappedAddresses],[chainlinkFeeds])`.
   * Ensure `FunctionsOracle` holds the correct `currentList()` of stock addresses and their `tokenCurrentMarketShare(token)` values (e.g., in 1e18 for 2.5% = 0.025 × 1e18).

6. **Run Issuance & Redemption**

   * **Issuance:**

     ```js
     const tx = await indexFactory.issuanceIndexTokens(USDC_AMOUNT);
     const nonce = await indexFactory.issuanceNonce();
     // Off‐chain: monitor Dinari order IDs via storage. Once all DONE, call:
     await indexFactoryProcessor.completeIssuance(nonce);
     ```
   * **Redemption:**

     ```js
     const tx = await indexFactory.redemption(INDEX_TOKEN_AMOUNT);
     const nonce = await indexFactory.redemptionNonce();
     // Off‐chain: monitor sell orders. When all FULFILLED:
     await indexFactoryProcessor.completeRedemption(nonce);
     ```

7. **Trigger Rebalance**

   * **First Sell:**

     ```js
     const nonce = await indexFactoryBalancer.firstRebalanceAction();
     // Monitor all sell orders (actionType = 5). Once all FULFILLED:
     await indexFactoryBalancer.secondRebalanceAction(nonce);
     // Monitor buy orders (actionType = 6). Once fulfilled:
     await indexFactoryBalancer.completeRebalanceActions(nonce);
     ```

8. **Cancel Flows**

   * **Cancel Issuance:**

     ```js
     await indexFactory.cancelIssuance(issuanceNonce);
     // Off‐chain: when cancellations and any sell‐backs finish, call:
     await indexFactoryProcessor.completeCancelIssuance(issuanceNonce);
     ```
   * **Cancel Redemption:**

     ```js
     await indexFactory.cancelRedemption(redemptionNonce);
     // Off‐chain: when all cancel orders finish, call:
     await indexFactoryProcessor.completeCancelRedemption(redemptionNonce);
     ```

---

## License

This project is released under the **MIT License**. See the [LICENSE](LICENSE) file for details.
