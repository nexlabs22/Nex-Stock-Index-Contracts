// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../../../contracts/test/MockERC20.sol";
import "../../../contracts/test/MockV3Aggregator.sol";
import "../../../contracts/test/MockApiOracle.sol";
import "../../../contracts/test/LinkToken.sol";
import "../../../contracts/test/Token.sol";
import "../../../contracts/token/IndexToken.sol";
import "../../../contracts/vault/NexVault.sol";
import "../../../contracts/factory/IndexFactory.sol";
import "../../../contracts/factory/IndexFactoryProcessor.sol";
import "../../../contracts/factory/IndexFactoryStorage.sol";
import "../../../contracts/factory/IndexFactoryBalancer.sol";
import {MockToken} from "../utils/mocks/MockToken.sol";
import "../utils/mocks/GetMockDShareFactory.sol";
import "../utils/SigUtils.sol";
import "../../../contracts/dinary/orders/OrderProcessor.sol";
import "../../../contracts/dinary/orders/IOrderProcessor.sol";
import {TransferRestrictor} from "../../../contracts/dinary/TransferRestrictor.sol";
import {OrderManager} from "../../../contracts/factory/OrderManager.sol";
import {NumberUtils} from "../../../contracts/dinary/common/NumberUtils.sol";
import {FeeLib} from "../../../contracts/dinary/common/FeeLib.sol";
import {DShare} from "../../../contracts/dinary/DShare.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {WrappedDShare} from "../../../contracts/dinary/WrappedDShare.sol";
import {MockV3Aggregator} from "../../../contracts/test/MockV3Aggregator.sol";
import {FunctionsOracle} from "../../../contracts/factory/FunctionsOracle.sol";


contract IndexTokenFactoryFuzzTests is Test {
    using GetMockDShareFactory for DShareFactory;
    uint256 internal constant TOKEN_LIQUIDITY_LIMIT = 1000000e18;
    bytes32 jobId = "6b88e0402e5d415eb946e528b8e0c7ba";

    event TreasurySet(address indexed treasury);
    event VaultSet(address indexed vault);
    event PaymentTokenSet(
        address indexed paymentToken,
        bytes4 blacklistCallSelector,
        uint64 perOrderFeeBuy,
        uint24 percentageFeeRateBuy,
        uint64 perOrderFeeSell,
        uint24 percentageFeeRateSell
    );
    event PaymentTokenRemoved(address indexed paymentToken);
    event OrdersPaused(bool paused);
    event OrderDecimalReductionSet(
        address indexed assetToken,
        uint8 decimalReduction
    );
    event OperatorSet(address indexed account, bool set);

    event OrderCreated(
        uint256 indexed id,
        address indexed requester,
        IOrderProcessor.Order order,
        uint256 feesEscrowed
    );
    event OrderFill(
        uint256 indexed id,
        address indexed paymentToken,
        address indexed assetToken,
        address requester,
        uint256 assetAmount,
        uint256 paymentAmount,
        uint256 fees,
        bool sell
    );
    event OrderFulfilled(uint256 indexed id, address indexed recipient);
    event CancelRequested(uint256 indexed id, address indexed requester);
    event OrderCancelled(
        uint256 indexed id,
        address indexed recipient,
        string reason
    );

    struct FeeRates {
        uint64 perOrderFeeBuy;
        uint24 percentageFeeRateBuy;
        uint64 perOrderFeeSell;
        uint24 percentageFeeRateSell;
    }

    DShareFactory tokenFactory;
    DShare token;
    OrderProcessor issuer;
    MockToken paymentToken;
    SigUtils sigUtils;
    TransferRestrictor restrictor;

    OrderManager orderManager;
    IndexToken public indexToken;
    MockApiOracle public oracle;
    LinkToken link;
    IndexFactory public factory;
    IndexFactoryProcessor public factoryProcessor;
    MockV3Aggregator public ethPriceOracle;
    NexVault public vault;
    FunctionsOracle public functionsOracle;
    IndexFactoryStorage public factoryStorage;
    IndexFactoryBalancer public factoryBalancer;

    uint256 userPrivateKey;
    uint256 adminPrivateKey;
    address user;
    address admin;

    address constant operator = address(3);
    address constant treasury = address(4);
    address public restrictor_role = address(1);

    uint256 dummyOrderFees;

    address feeReceiver = vm.addr(1);

    DShare token0;
    DShare token1;
    DShare token2;
    DShare token3;
    DShare token4;
    DShare token5;
    DShare token6;
    DShare token7;
    DShare token8;
    DShare token9;

    WrappedDShare wrappedToken0;
    WrappedDShare wrappedToken1;
    WrappedDShare wrappedToken2;
    WrappedDShare wrappedToken3;
    WrappedDShare wrappedToken4;
    WrappedDShare wrappedToken5;
    WrappedDShare wrappedToken6;
    WrappedDShare wrappedToken7;
    WrappedDShare wrappedToken8;
    WrappedDShare wrappedToken9;

    MockV3Aggregator priceFeed0;
    MockV3Aggregator priceFeed1;
    MockV3Aggregator priceFeed2;
    MockV3Aggregator priceFeed3;
    MockV3Aggregator priceFeed4;
    MockV3Aggregator priceFeed5;
    MockV3Aggregator priceFeed6;
    MockV3Aggregator priceFeed7;
    MockV3Aggregator priceFeed8;
    MockV3Aggregator priceFeed9;

    function setUp() public {
        userPrivateKey = 0x01;
        adminPrivateKey = 0x02;
        user = vm.addr(userPrivateKey);
        admin = vm.addr(adminPrivateKey);

        vm.startPrank(admin);
        (tokenFactory, , ) = GetMockDShareFactory.getMockDShareFactory(admin);
        token = tokenFactory.deployDShare(admin, "Dinari Token", "dTKN");
        paymentToken = new MockToken("Money", "$");
        sigUtils = new SigUtils(paymentToken.DOMAIN_SEPARATOR());

        OrderProcessor issuerImpl = new OrderProcessor();
        issuer = OrderProcessor(
            address(
                new ERC1967Proxy(
                    address(issuerImpl),
                    abi.encodeCall(
                        OrderProcessor.initialize,
                        (admin, treasury, operator, tokenFactory)
                    )
                )
            )
        );

        token.grantRole(token.MINTER_ROLE(), admin);
        token.grantRole(token.MINTER_ROLE(), address(issuer));
        token.grantRole(token.BURNER_ROLE(), address(issuer));

        issuer.setPaymentToken(
            address(paymentToken),
            paymentToken.isBlacklisted.selector,
            1e8,
            5_000,
            1e8,
            5_000
        );
        issuer.setOperator(operator, true);

        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(
            false,
            address(paymentToken)
        );
        dummyOrderFees =
            flatFee +
            FeeLib.applyPercentageFee(percentageFeeRate, 100 ether);

        restrictor = TransferRestrictor(address(token.transferRestrictor()));
        restrictor.grantRole(restrictor.RESTRICTOR_ROLE(), restrictor_role);

        //nex contracts
        OrderManager orderManagerImpl = new OrderManager();
        orderManager = OrderManager(
            address(
                new ERC1967Proxy(
                    address(orderManagerImpl),
                    abi.encodeCall(
                        OrderManager.initialize,
                        (address(paymentToken), paymentToken.decimals(), address(issuer))
                    )
                )
            )
        );

        link = new LinkToken();
        oracle = new MockApiOracle();

        ethPriceOracle = new MockV3Aggregator(
            18, //decimals
            2000e18 //initial data
        );

        IndexToken indexTokenImpl = new IndexToken();
        indexToken = IndexToken(
            address(
                new ERC1967Proxy(
                    address(indexTokenImpl),
                    abi.encodeCall(
                        IndexToken.initialize,
                        (
                            "Magnificent 7",
                            "MAG7",
                            1e18,
                            feeReceiver,
                            1000000e18
                        )
                    )
                )
            )
        );

        NexVault vaultImpl = new NexVault();
        vault = NexVault(
            address(
                new ERC1967Proxy(
                    address(vaultImpl),
                    abi.encodeCall(
                        NexVault.initialize,
                        (address(0))
                    )
                )
            )
        );

        FunctionsOracle functionsOracleImpl = new FunctionsOracle();
        functionsOracle = FunctionsOracle(
            address(
                new ERC1967Proxy(
                    address(functionsOracleImpl),
                    abi.encodeCall(
                        functionsOracleImpl.initialize,
                        (
                            address(oracle),
                            jobId
                        )
                    )
                )
            )
        );

        IndexFactoryStorage factoryStorageImpl = new IndexFactoryStorage();
        factoryStorage = IndexFactoryStorage(
            address(
                new ERC1967Proxy(
                    address(factoryStorageImpl),
                    abi.encodeCall(
                        IndexFactoryStorage.initialize,
                            (
                                address(issuer),
                                address(indexToken),
                                address(vault),
                                address(paymentToken),
                                paymentToken.decimals(),
                                address(functionsOracle),
                                true
                            )
                    )
                )
            )
        );

        IndexFactoryBalancer factoryBalancerImpl = new IndexFactoryBalancer();
        factoryBalancer = IndexFactoryBalancer(
            address(
                new ERC1967Proxy(
                    address(factoryBalancerImpl),
                    abi.encodeCall(
                        IndexFactoryBalancer.initialize,
                        (
                            address(factoryStorage), 
                            address(functionsOracle)
                        )
                )
            )
            )
        );

        IndexFactory factoryImpl = new IndexFactory();
        factory = IndexFactory(
            address(
                new ERC1967Proxy(
                    address(factoryImpl),
                    abi.encodeCall(
                        IndexFactory.initialize,
                        (address(factoryStorage), address(functionsOracle))
                    )
                )
            )
        );

        IndexFactoryProcessor factoryProcessorImpl = new IndexFactoryProcessor();
        factoryProcessor = IndexFactoryProcessor(
            address(
                new ERC1967Proxy(
                    address(factoryProcessorImpl),
                    abi.encodeCall(
                        IndexFactoryProcessor.initialize,
                        (address(factoryStorage), address(functionsOracle)
                    )
                )
            )
            )
        );

        indexToken.setMinter(address(factory), true);
        indexToken.setMinter(address(factoryProcessor), true);
        vault.setOperator(address(factory), true);
        vault.setOperator(address(factoryProcessor), true);
        vault.setOperator(address(factoryBalancer), true);
        factoryStorage.setOrderManager(address(orderManager));
        factoryStorage.setFactory(address(factory));
        factoryStorage.setFactoryProcessor(address(factoryProcessor));
        factoryStorage.setFactoryBalancer(address(factoryBalancer));
        orderManager.setOperator(address(factory), true);
        orderManager.setOperator(address(factoryProcessor), true);
        orderManager.setOperator(address(factoryBalancer), true);

        DShare[10] memory tokens;
        WrappedDShare[10] memory wrappedTokens;
        TransferRestrictor[10] memory restrictors;
        MockV3Aggregator[10] memory priceFeeds;

        for (uint i = 0; i < 10; i++) {
            tokens[i] = tokenFactory.deployDShare(
                admin,
                "Dinari Token",
                "dTKN"
            );

            tokens[i].grantRole(tokens[i].MINTER_ROLE(), admin);
            tokens[i].grantRole(tokens[i].MINTER_ROLE(), address(issuer));
            tokens[i].grantRole(tokens[i].BURNER_ROLE(), address(issuer));

            restrictors[i] = TransferRestrictor(
                address(tokens[i].transferRestrictor())
            );
            restrictors[i].grantRole(
                restrictors[i].RESTRICTOR_ROLE(),
                restrictor_role
            );

            //set decimal reduction
            uint8 tokenDecimals = token.decimals();
            issuer.setOrderDecimalReduction(address(tokens[i]), tokenDecimals);
            //deploy wrapped dshare
            WrappedDShare wrappedTokensImp = new WrappedDShare();
            wrappedTokens[i] = WrappedDShare(
                address(
                    new ERC1967Proxy(
                        address(wrappedTokensImp),
                        abi.encodeCall(
                            wrappedTokensImp.initialize,
                            (
                                address(admin),
                                tokens[i],
                                "Wrapped Dinari Token",
                                "wDTKN"
                            )
                        )
                    )
                )
            );
            //mint token to dshare
            tokens[i].mint(address(admin), TOKEN_LIQUIDITY_LIMIT);
            tokens[i].approve(address(wrappedTokens[i]), TOKEN_LIQUIDITY_LIMIT);
            wrappedTokens[i].deposit(TOKEN_LIQUIDITY_LIMIT, address(admin));
            //deploy price feed
            priceFeeds[i] = new MockV3Aggregator(
                18, //decimals
                10e18 //initial data
            );
        }
        token0 = tokens[0];
        token1 = tokens[1];
        token2 = tokens[2];
        token3 = tokens[3];
        token4 = tokens[4];
        token5 = tokens[5];
        token6 = tokens[6];
        token7 = tokens[7];
        token8 = tokens[8];
        token9 = tokens[9];

        wrappedToken0 = wrappedTokens[0];
        wrappedToken1 = wrappedTokens[1];
        wrappedToken2 = wrappedTokens[2];
        wrappedToken3 = wrappedTokens[3];
        wrappedToken4 = wrappedTokens[4];
        wrappedToken5 = wrappedTokens[5];
        wrappedToken6 = wrappedTokens[6];
        wrappedToken7 = wrappedTokens[7];
        wrappedToken8 = wrappedTokens[8];
        wrappedToken9 = wrappedTokens[9];

        priceFeed0 = priceFeeds[0];
        priceFeed1 = priceFeeds[1];
        priceFeed2 = priceFeeds[2];
        priceFeed3 = priceFeeds[3];
        priceFeed4 = priceFeeds[4];
        priceFeed5 = priceFeeds[5];
        priceFeed6 = priceFeeds[6];
        priceFeed7 = priceFeeds[7];
        priceFeed8 = priceFeeds[8];
        priceFeed9 = priceFeeds[9];

        vm.stopPrank();

        _initData();
    }

    function getDummyOrder(
        bool sell
    ) internal view returns (IOrderProcessor.Order memory) {
        return
            IOrderProcessor.Order({
                requestTimestamp: uint64(block.timestamp),
                recipient: user,
                assetToken: address(token),
                paymentToken: address(paymentToken),
                sell: sell,
                orderType: IOrderProcessor.OrderType.MARKET,
                assetTokenQuantity: sell ? 100 ether : 0,
                paymentTokenQuantity: sell ? 0 : 100 ether,
                price: 0,
                tif: IOrderProcessor.TIF.GTC
            });
    }

    function _fillAllBuyOrders(
        uint _nonce,
        uint _receivedAmount,
        uint _feeAmount
    ) public {
        for (uint i = 0; i < 10; i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint id = factoryStorage.issuanceRequestId(_nonce, tokenAddress);
            uint orderAmount = factoryStorage.buyRequestPayedAmountById(id);
            IOrderProcessor.Order memory order = factoryStorage
                .getOrderInstanceById(id);
            // balances before
            vm.startPrank(operator);
            uint256 userAssetBefore = IERC20(tokenAddress).balanceOf(
                address(orderManager)
            );

            issuer.fillOrder(
                order,
                orderAmount,
                _receivedAmount,
                _feeAmount / functionsOracle.totalCurrentList()
            );
            IOrderProcessor.PricePoint memory fillPrice = issuer
                .latestFillPrice(order.assetToken, order.paymentToken);
            assertTrue(
                fillPrice.price == 0 ||
                    fillPrice.price ==
                    mulDiv(
                        orderAmount,
                        10 ** (18 - paymentToken.decimals()),
                        _receivedAmount
                    )
            );
            // balances after
            // assertEq(IERC20(tokenAddress).balanceOf(address(orderManager)), userAssetBefore + receivedAmount);
            assertEq(
                uint8(issuer.getOrderStatus(id)),
                uint8(IOrderProcessor.OrderStatus.FULFILLED)
            );
        }
    }

    function _fillAllBuyOrdersWithMultical(
        uint _nonce,
        uint _receivedAmount,
        uint _feeAmount
    ) public {
        for (uint i = 0; i < 10; i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint id = factoryStorage.issuanceRequestId(_nonce, tokenAddress);
            uint orderAmount = factoryStorage.buyRequestPayedAmountById(id);
            IOrderProcessor.Order memory order = factoryStorage
                .getOrderInstanceById(id);
            // balances before
            vm.startPrank(operator);
            uint256 userAssetBefore = IERC20(tokenAddress).balanceOf(
                address(orderManager)
            );

            issuer.fillOrder(
                order,
                orderAmount,
                _receivedAmount,
                _feeAmount / functionsOracle.totalCurrentList()
            );
            IOrderProcessor.PricePoint memory fillPrice = issuer
                .latestFillPrice(order.assetToken, order.paymentToken);
            assertTrue(
                fillPrice.price == 0 ||
                    fillPrice.price ==
                    mulDiv(
                        orderAmount,
                        10 ** (18 - paymentToken.decimals()),
                        _receivedAmount
                    )
            );
            // balances after
            // assertEq(IERC20(tokenAddress).balanceOf(address(orderManager)), userAssetBefore + receivedAmount);
            assertEq(
                uint8(issuer.getOrderStatus(id)),
                uint8(IOrderProcessor.OrderStatus.FULFILLED)
            );
            //multical
            if (factoryProcessor.checkMultical(id)) {
                factoryProcessor.multical(id);
            }
        }
    }

    function _fillAllSellOrders(
        uint _nonce,
        uint _receivedAmount,
        uint _feeAmount
    ) public {
        for (uint i; i < 10; i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint id = factoryStorage.redemptionRequestId(_nonce, tokenAddress);
            uint orderAmount = factoryStorage.sellRequestAssetAmountById(id);
            IOrderProcessor.Order memory order = factoryStorage
                .getOrderInstanceById(id);
            vm.stopPrank();
            vm.prank(admin);
            paymentToken.mint(operator, 100e18);
            vm.prank(operator);
            paymentToken.approve(address(issuer), 100e18);

            vm.prank(operator);
            issuer.fillOrder(order, orderAmount, orderAmount / 10, 1e18);
            assertEq(issuer.getUnfilledAmount(id), 0);
            assertEq(
                uint8(issuer.getOrderStatus(id)),
                uint8(IOrderProcessor.OrderStatus.FULFILLED)
            );
        }
    }

    function _fillAllSellOrdersMultical(
        uint _nonce,
        uint _receivedAmount,
        uint _feeAmount
    ) public {
        for (uint i; i < 10; i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint id = factoryStorage.redemptionRequestId(_nonce, tokenAddress);
            uint orderAmount = factoryStorage.sellRequestAssetAmountById(id);
            IOrderProcessor.Order memory order = factoryStorage
                .getOrderInstanceById(id);
            vm.stopPrank();
            vm.prank(admin);
            paymentToken.mint(operator, 100e18);
            vm.prank(operator);
            paymentToken.approve(address(issuer), 100e18);

            vm.prank(operator);
            issuer.fillOrder(order, 1000e18, 100e18, 1e18);
            assertEq(issuer.getUnfilledAmount(id), 0);
            assertEq(
                uint8(issuer.getOrderStatus(id)),
                uint8(IOrderProcessor.OrderStatus.FULFILLED)
            );

            //check multical
            if (factoryProcessor.checkMultical(id)) {
                assertEq(
                    factoryStorage.checkRedemptionOrdersStatus(_nonce),
                    true
                );
                assertEq(factoryStorage.redemptionIsCompleted(_nonce), false);
                factoryProcessor.multical(id);
            }
        }
    }

    function _fillCancelIssuanceSellOrders(
        uint _nonce,
        uint _receivedAmount,
        uint _feeAmount
    ) public {
        for (uint i; i < 10; i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint id = factoryStorage.cancelIssuanceRequestId(
                _nonce,
                tokenAddress
            );
            uint orderAmount = factoryStorage.sellRequestAssetAmountById(id);
            IOrderProcessor.Order memory order = factoryStorage
                .getOrderInstanceById(id);
            vm.stopPrank();
            vm.prank(admin);
            paymentToken.mint(operator, 100e18);
            vm.prank(operator);
            paymentToken.approve(address(issuer), 100e18);

            vm.prank(operator);
            issuer.fillOrder(order, orderAmount, orderAmount / 10, 1e18);
            assertEq(issuer.getUnfilledAmount(id), 0);
            assertEq(
                uint8(issuer.getOrderStatus(id)),
                uint8(IOrderProcessor.OrderStatus.FULFILLED)
            );
        }
    }

    function testInitialization() public {
        assertEq(issuer.owner() == admin, true);
        assertEq(issuer.owner(), admin);
        assertEq(issuer.treasury(), treasury);
        assertEq(issuer.vault(), operator);
        assertEq(address(issuer.dShareFactory()), address(tokenFactory));
    }

    function deployTokens() public returns (Token[11] memory) {
        Token[11] memory tokens;

        for (uint256 i = 0; i < 11; i++) {
            tokens[i] = new Token(1000000e18);
        }

        return tokens;
    }

    function updateOracleList() public {
        address[] memory assetList = new address[](10);
        assetList[0] = address(token0);
        assetList[1] = address(token1);
        assetList[2] = address(token2);
        assetList[3] = address(token3);
        assetList[4] = address(token4);
        assetList[5] = address(token5);
        assetList[6] = address(token6);
        assetList[7] = address(token7);
        assetList[8] = address(token8);
        assetList[9] = address(token9);

        uint[] memory tokenShares = new uint[](10);
        tokenShares[0] = 10e18;
        tokenShares[1] = 10e18;
        tokenShares[2] = 10e18;
        tokenShares[3] = 10e18;
        tokenShares[4] = 10e18;
        tokenShares[5] = 10e18;
        tokenShares[6] = 10e18;
        tokenShares[7] = 10e18;
        tokenShares[8] = 10e18;
        tokenShares[9] = 10e18;

        link.transfer(address(functionsOracle), 1e17);
        // bytes32 requestId = functionsOracle.requestAssetsData();
        // oracle.fulfillOracleFundingRateRequest(requestId, assetList, tokenShares);
        bytes32 requestId = functionsOracle.requestAssetsData(
            "console.log('Hello, World!');",
            0,
            0
        );
        bytes memory data = abi.encode(assetList, tokenShares);
        oracle.fulfillRequest(address(functionsOracle), requestId, data);
    }

    function updateOracleList2() public {
        address[] memory assetList = new address[](10);
        assetList[0] = address(token0);
        assetList[1] = address(token1);
        assetList[2] = address(token2);
        assetList[3] = address(token3);
        assetList[4] = address(token4);
        assetList[5] = address(token5);
        assetList[6] = address(token6);
        assetList[7] = address(token7);
        assetList[8] = address(token8);
        assetList[9] = address(token9);

        uint[] memory tokenShares = new uint[](10);
        tokenShares[0] = 20e18;
        tokenShares[1] = 5e18;
        tokenShares[2] = 5e18;
        tokenShares[3] = 10e18;
        tokenShares[4] = 10e18;
        tokenShares[5] = 10e18;
        tokenShares[6] = 10e18;
        tokenShares[7] = 10e18;
        tokenShares[8] = 10e18;
        tokenShares[9] = 10e18;

        link.transfer(address(functionsOracle), 1e17);
        // bytes32 requestId = functionsOracle.requestAssetsData();
        // oracle.fulfillOracleFundingRateRequest(requestId, assetList, tokenShares);
        bytes32 requestId = functionsOracle.requestAssetsData(
            "console.log('Hello, World!');",
            0,
            0
        );
        bytes memory data = abi.encode(assetList, tokenShares);
        oracle.fulfillRequest(address(functionsOracle), requestId, data);
    }

    function updateWrappedDshares() public {
        address[] memory assetList = new address[](10);
        assetList[0] = address(token0);
        assetList[1] = address(token1);
        assetList[2] = address(token2);
        assetList[3] = address(token3);
        assetList[4] = address(token4);
        assetList[5] = address(token5);
        assetList[6] = address(token6);
        assetList[7] = address(token7);
        assetList[8] = address(token8);
        assetList[9] = address(token9);

        address[] memory wrappedDshareList = new address[](10);
        wrappedDshareList[0] = address(wrappedToken0);
        wrappedDshareList[1] = address(wrappedToken1);
        wrappedDshareList[2] = address(wrappedToken2);
        wrappedDshareList[3] = address(wrappedToken3);
        wrappedDshareList[4] = address(wrappedToken4);
        wrappedDshareList[5] = address(wrappedToken5);
        wrappedDshareList[6] = address(wrappedToken6);
        wrappedDshareList[7] = address(wrappedToken7);
        wrappedDshareList[8] = address(wrappedToken8);
        wrappedDshareList[9] = address(wrappedToken9);

        // factoryStorage.setWrappedDShareAddresses(assetList, wrappedDshareList);
    }

    function updatePriceFeeds() public {
        address[] memory assetList = new address[](10);
        assetList[0] = address(token0);
        assetList[1] = address(token1);
        assetList[2] = address(token2);
        assetList[3] = address(token3);
        assetList[4] = address(token4);
        assetList[5] = address(token5);
        assetList[6] = address(token6);
        assetList[7] = address(token7);
        assetList[8] = address(token8);
        assetList[9] = address(token9);

        address[] memory priceFeedList = new address[](10);
        priceFeedList[0] = address(priceFeed0);
        priceFeedList[1] = address(priceFeed1);
        priceFeedList[2] = address(priceFeed2);
        priceFeedList[3] = address(priceFeed3);
        priceFeedList[4] = address(priceFeed4);
        priceFeedList[5] = address(priceFeed5);
        priceFeedList[6] = address(priceFeed6);
        priceFeedList[7] = address(priceFeed7);
        priceFeedList[8] = address(priceFeed8);
        priceFeedList[9] = address(priceFeed9);

        address[] memory wrappedDshareList = new address[](10);
        wrappedDshareList[0] = address(wrappedToken0);
        wrappedDshareList[1] = address(wrappedToken1);
        wrappedDshareList[2] = address(wrappedToken2);
        wrappedDshareList[3] = address(wrappedToken3);
        wrappedDshareList[4] = address(wrappedToken4);
        wrappedDshareList[5] = address(wrappedToken5);
        wrappedDshareList[6] = address(wrappedToken6);
        wrappedDshareList[7] = address(wrappedToken7);
        wrappedDshareList[8] = address(wrappedToken8);
        wrappedDshareList[9] = address(wrappedToken9);

        // factoryStorage.setPriceFeedAddresses(assetList, priceFeedList);
        factoryStorage.setWrappedDshareAndPriceFeedAddresses(
            assetList,
            wrappedDshareList,
            priceFeedList
        );
    }

    function _initData() public {
        vm.startPrank(admin);
        updateOracleList();
        updateWrappedDshares();
        updatePriceFeeds();
        vm.stopPrank();
    }

    function testOracleList() public {
        vm.startPrank(admin);
        // token  oracle list
        assertEq(functionsOracle.oracleList(0), address(token0));
        assertEq(functionsOracle.oracleList(1), address(token1));
        assertEq(functionsOracle.oracleList(2), address(token2));
        assertEq(functionsOracle.oracleList(3), address(token3));
        assertEq(functionsOracle.oracleList(4), address(token4));
        assertEq(functionsOracle.oracleList(9), address(token9));
        // token current list
        assertEq(functionsOracle.currentList(0), address(token0));
        assertEq(functionsOracle.currentList(1), address(token1));
        assertEq(functionsOracle.currentList(2), address(token2));
        assertEq(functionsOracle.currentList(3), address(token3));
        assertEq(functionsOracle.currentList(4), address(token4));
        assertEq(functionsOracle.currentList(9), address(token9));
        // token shares
        assertEq(functionsOracle.tokenOracleMarketShare(address(token0)), 10e18);
        assertEq(functionsOracle.tokenOracleMarketShare(address(token1)), 10e18);
        assertEq(functionsOracle.tokenOracleMarketShare(address(token2)), 10e18);
        assertEq(functionsOracle.tokenOracleMarketShare(address(token3)), 10e18);
        assertEq(functionsOracle.tokenOracleMarketShare(address(token4)), 10e18);
        assertEq(functionsOracle.tokenOracleMarketShare(address(token9)), 10e18);

        vm.stopPrank();
    }

    function testWrappedDshareList() public {
        vm.startPrank(admin);
        // token  wrapped list
        assertEq(
            factoryStorage.wrappedDshareAddress(address(token0)),
            address(wrappedToken0)
        );
        assertEq(
            factoryStorage.wrappedDshareAddress(address(token1)),
            address(wrappedToken1)
        );
        assertEq(
            factoryStorage.wrappedDshareAddress(address(token2)),
            address(wrappedToken2)
        );
        assertEq(
            factoryStorage.wrappedDshareAddress(address(token3)),
            address(wrappedToken3)
        );
        assertEq(
            factoryStorage.wrappedDshareAddress(address(token4)),
            address(wrappedToken4)
        );
        assertEq(
            factoryStorage.wrappedDshareAddress(address(token9)),
            address(wrappedToken9)
        );

        //test wrapped asset address
        assertEq(wrappedToken0.asset(), address(token0));
        assertEq(wrappedToken1.asset(), address(token1));
        assertEq(wrappedToken2.asset(), address(token2));
        assertEq(wrappedToken3.asset(), address(token3));
        assertEq(wrappedToken4.asset(), address(token4));
        assertEq(wrappedToken9.asset(), address(token9));

        vm.stopPrank();
    }

    function testIssuance(uint256 inputAmount) public {
        vm.assume(
            inputAmount > 1000000 &&
                inputAmount <
                TOKEN_LIQUIDITY_LIMIT - (TOKEN_LIQUIDITY_LIMIT * 10) / 10000
        );
        vm.startPrank(admin);
        uint feeAmount = factoryStorage.calculateIssuanceFee(inputAmount);
        uint quantityIn = feeAmount + inputAmount + (inputAmount * 10) / 10000;

        paymentToken.mint(address(user), quantityIn);
        vm.stopPrank();

        vm.startPrank(user);

        uint256 userBalanceBefore = paymentToken.balanceOf(user);
        uint256 operatorBalanceBefore = paymentToken.balanceOf(operator);
        paymentToken.approve(address(factory), quantityIn);
        uint nonce = factory.issuanceIndexTokens(inputAmount);

        for (uint i = 0; i < 10; i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint id = factoryStorage.issuanceRequestId(nonce, tokenAddress);
            uint orderAmount = factoryStorage.buyRequestPayedAmountById(id);
            assertEq(
                uint8(issuer.getOrderStatus(id)),
                uint8(IOrderProcessor.OrderStatus.ACTIVE)
            );
            assertEq(issuer.getUnfilledAmount(id), orderAmount);
        }
        assertEq(paymentToken.balanceOf(user), userBalanceBefore - quantityIn);
        assertEq(paymentToken.balanceOf(address(issuer)), feeAmount);
    }

    function testRedemption(uint256 amount) public {
        vm.assume(
            amount > 1e18 &&
                amount <
                TOKEN_LIQUIDITY_LIMIT - (TOKEN_LIQUIDITY_LIMIT * 10) / 10000
        );
        // uint amount = 1000000e18;
        vm.startPrank(admin);
        for (uint i; i < 10; i++) {
            address tokenAddress = functionsOracle.currentList(i);
            address wrappedTokenAddress = factoryStorage.wrappedDshareAddress(
                tokenAddress
            );
            DShare(tokenAddress).mint(address(admin), amount);
            DShare(tokenAddress).approve(wrappedTokenAddress, amount);
            WrappedDShare(wrappedTokenAddress).deposit(amount, address(vault));
        }

        indexToken.setMinter(address(admin), true);
        indexToken.mint(address(user), amount);
        indexToken.setMinter(address(factory), true);

        vm.stopPrank();
        vm.startPrank(user);
        uint nonce = factory.redemption(indexToken.balanceOf(address(user)));

        for (uint i = 0; i < 10; i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint id = factoryStorage.redemptionRequestId(nonce, tokenAddress);
            uint orderAmount = factoryStorage.sellRequestAssetAmountById(id);
            assertEq(
                uint8(issuer.getOrderStatus(id)),
                uint8(IOrderProcessor.OrderStatus.ACTIVE)
            );
            assertEq(issuer.getUnfilledAmount(id), orderAmount);
        }
    }
}
