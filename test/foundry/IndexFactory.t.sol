// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../../contracts/test/MockERC20.sol";
import "../../contracts/test/MockV3Aggregator.sol";
import "../../contracts/test/MockApiOracle.sol";
import "../../contracts/test/LinkToken.sol";
import "../../contracts/test/Token.sol";
import "../../contracts/token/IndexToken.sol";
import "../../contracts/vault/NexVault.sol";
import "../../contracts/factory/IndexFactory.sol";
import {MockToken} from "./utils/mocks/MockToken.sol";
import "./utils/mocks/GetMockDShareFactory.sol";
import "./utils/SigUtils.sol";
import "../../contracts/dinary/orders/OrderProcessor.sol";
import "../../contracts/dinary/orders/IOrderProcessor.sol";
import {TransferRestrictor} from "../../contracts/dinary/TransferRestrictor.sol";
import {OrderManager} from "../../contracts/factory/OrderManager.sol";
import {NumberUtils} from "../../contracts/dinary/common/NumberUtils.sol";
import {FeeLib} from "../../contracts/dinary/common/FeeLib.sol";
import {DShare} from "../../contracts/dinary/DShare.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";


contract OrderProcessorTest is Test {
   using GetMockDShareFactory for DShareFactory;

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
    event OrderDecimalReductionSet(address indexed assetToken, uint8 decimalReduction);
    event OperatorSet(address indexed account, bool set);

    event OrderCreated(
        uint256 indexed id, address indexed requester, IOrderProcessor.Order order, uint256 feesEscrowed
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
    event OrderCancelled(uint256 indexed id, address indexed recipient, string reason);

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
    MockV3Aggregator public ethPriceOracle;
    NexVault public vault;


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

    function setUp() public {
        userPrivateKey = 0x01;
        adminPrivateKey = 0x02;
        user = vm.addr(userPrivateKey);
        admin = vm.addr(adminPrivateKey);

        vm.startPrank(admin);
        (tokenFactory,,) = GetMockDShareFactory.getMockDShareFactory(admin);
        token = tokenFactory.deployDShare(admin, "Dinari Token", "dTKN");
        paymentToken = new MockToken("Money", "$");
        sigUtils = new SigUtils(paymentToken.DOMAIN_SEPARATOR());

        OrderProcessor issuerImpl = new OrderProcessor();
        issuer = OrderProcessor(
            address(
                new ERC1967Proxy(
                    address(issuerImpl),
                    abi.encodeCall(OrderProcessor.initialize, (admin, treasury, operator, tokenFactory))
                )
            )
        );

        token.grantRole(token.MINTER_ROLE(), admin);
        token.grantRole(token.MINTER_ROLE(), address(issuer));
        token.grantRole(token.BURNER_ROLE(), address(issuer));

        issuer.setPaymentToken(address(paymentToken), paymentToken.isBlacklisted.selector, 1e8, 5_000, 1e8, 5_000);
        issuer.setOperator(operator, true);

        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(false, address(paymentToken));
        dummyOrderFees = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, 100 ether);

        restrictor = TransferRestrictor(address(token.transferRestrictor()));
        restrictor.grantRole(restrictor.RESTRICTOR_ROLE(), restrictor_role);

        //nex contracts
        orderManager = new OrderManager();
        orderManager.initialize(address(paymentToken), paymentToken.decimals(), address(token), address(issuer));

        link = new LinkToken();
        oracle = new MockApiOracle(address(link));

        ethPriceOracle = new MockV3Aggregator(
            18, //decimals
            2000e18   //initial data
        );

        indexToken = new IndexToken();
        indexToken.initialize(
            "Magnificent 7",
            "MAG7",
            1e18,
            feeReceiver,
            1000000e18
        );

        vault = new NexVault();
        vault.initialize(address(0));
        

        factory = new IndexFactory();
        factory.initialize(
            address(issuer),
            payable(address(indexToken)),
            address(vault),
            address(paymentToken),
            paymentToken.decimals(),
            // address(0),
            address(link),
            address(oracle),
            jobId
        );
        

        indexToken.setMinter(address(factory));
        vault.setOperator(address(factory), true);

        
        DShare[10] memory tokens;
        TransferRestrictor[10] memory restrictors;
        for(uint i = 0; i < 10; i++) {
            tokens[i] = tokenFactory.deployDShare(admin, "Dinari Token", "dTKN");
            tokens[i].grantRole(tokens[i].MINTER_ROLE(), admin);
            tokens[i].grantRole(tokens[i].MINTER_ROLE(), address(issuer));
            tokens[i].grantRole(tokens[i].BURNER_ROLE(), address(issuer));

            restrictors[i] = TransferRestrictor(address(tokens[i].transferRestrictor()));
            restrictors[i].grantRole(restrictors[i].RESTRICTOR_ROLE(), restrictor_role);
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

        vm.stopPrank();
    }

    

    function getDummyOrder(bool sell) internal view returns (IOrderProcessor.Order memory) {
        return IOrderProcessor.Order({
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

    function testInitialization() public {
        
        assertEq(issuer.owner() == admin, true);
        assertEq(issuer.owner(), admin);
        assertEq(issuer.treasury(), treasury);
        assertEq(issuer.vault(), operator);
        assertEq(address(issuer.dShareFactory()), address(tokenFactory));
    }

    function deployTokens() public returns(Token[11] memory) {
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

        
        
        link.transfer(address(factory), 1e17);
        bytes32 requestId = factory.requestAssetsData();
        oracle.fulfillOracleFundingRateRequest(requestId, assetList, tokenShares);
    }

    
    function testOracleList() public {
        vm.startPrank(admin);
        updateOracleList();
        // token  oracle list
        assertEq(factory.oracleList(0), address(token0));
        assertEq(factory.oracleList(1), address(token1));
        assertEq(factory.oracleList(2), address(token2));
        assertEq(factory.oracleList(3), address(token3));
        assertEq(factory.oracleList(4), address(token4));
        assertEq(factory.oracleList(9), address(token9));
        // token current list
        assertEq(factory.currentList(0), address(token0));
        assertEq(factory.currentList(1), address(token1));
        assertEq(factory.currentList(2), address(token2));
        assertEq(factory.currentList(3), address(token3));
        assertEq(factory.currentList(4), address(token4));
        assertEq(factory.currentList(9), address(token9));
        // token shares
        assertEq(factory.tokenOracleMarketShare(address(token0)), 10e18);
        assertEq(factory.tokenOracleMarketShare(address(token1)), 10e18);
        assertEq(factory.tokenOracleMarketShare(address(token2)), 10e18);
        assertEq(factory.tokenOracleMarketShare(address(token3)), 10e18);
        assertEq(factory.tokenOracleMarketShare(address(token4)), 10e18);
        assertEq(factory.tokenOracleMarketShare(address(token9)), 10e18);
        
        vm.stopPrank();
        
    }

    function testIssuance() public {
        uint inputAmount = 1000e18;
        vm.startPrank(admin);
        updateOracleList();
        uint feeAmount = factory.calculateIssuanceFee(inputAmount);
        uint quantityIn = feeAmount + inputAmount;
        
        paymentToken.mint(address(user), quantityIn);
        vm.stopPrank();

        vm.startPrank(user);

        uint256 userBalanceBefore = paymentToken.balanceOf(user);
        uint256 operatorBalanceBefore = paymentToken.balanceOf(operator);
        paymentToken.approve(address(factory), quantityIn);
        uint nonce = factory.issuance(inputAmount);

        for(uint i = 0; i < 10; i++) {
        address tokenAddress = factory.currentList(i);
        uint id = factory.issuanceRequestId(nonce, tokenAddress);
        uint orderAmount = factory.buyRequestPayedAmountById(id);
        assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
        assertEq(issuer.getUnfilledAmount(id), orderAmount);
        }
        assertEq(paymentToken.balanceOf(operator), operatorBalanceBefore + inputAmount);
        assertEq(paymentToken.balanceOf(user), userBalanceBefore - quantityIn);
        assertEq(paymentToken.balanceOf(address(issuer)), feeAmount);
    }


    function testCompleteIssuance() public {
        vm.startPrank(admin);
        updateOracleList();
        // uint totalCurretList = factory.totalCurrentList();
        uint inputAmount = 1000e18;
        uint receivedAmount = 100e18/factory.totalCurrentList();
        uint feeAmount = factory.calculateIssuanceFee(inputAmount);
        // uint quantityIn = feeAmount + inputAmount;
        paymentToken.mint(address(user), feeAmount + inputAmount);
        vm.stopPrank();

        vm.startPrank(user);

        uint256 userBalanceBefore = paymentToken.balanceOf(user);
        uint256 operatorBalanceBefore = paymentToken.balanceOf(operator);
        paymentToken.approve(address(factory), feeAmount + inputAmount);
        uint nonce = factory.issuance(inputAmount);
        vm.stopPrank();
        for(uint i = 0; i < 10; i++) {
            address tokenAddress = factory.currentList(i);
            uint id = factory.issuanceRequestId(nonce, tokenAddress);
            uint orderAmount = factory.buyRequestPayedAmountById(id);
            IOrderProcessor.Order memory order = factory.getOrderInctanceById(id);
            // balances before
            vm.startPrank(operator);
            uint256 userAssetBefore = IERC20(tokenAddress).balanceOf(factory.coaByIssuanceNonce(nonce));
            
            
            issuer.fillOrder(order, orderAmount, receivedAmount, feeAmount/factory.totalCurrentList());
            // assertEq(issuer.getUnfilledAmount(id), orderAmount - fillAmount);
            IOrderProcessor.PricePoint memory fillPrice = issuer.latestFillPrice(order.assetToken, order.paymentToken);
            assertTrue(
                fillPrice.price == 0
                    || fillPrice.price == mulDiv(orderAmount, 10 ** (18 - paymentToken.decimals()), receivedAmount)
            );
            // balances after
            assertEq(IERC20(tokenAddress).balanceOf(factory.coaByIssuanceNonce(nonce)), userAssetBefore + receivedAmount);
            assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.FULFILLED));
            
        }
        assertEq(factory.checkIssuanceOrdersStatus(nonce), true);
        factory.completeIssuance(nonce);
        assertEq(factory.issuanceIsCompleted(nonce), true);
    }

    function testRedemption() public {
        vm.startPrank(admin);
        updateOracleList();
        
        for(uint i; i < 10; i++) {
        address tokenAddress = factory.currentList(i);
        DShare(tokenAddress).mint(address(vault), 100e18);
        }
        
        indexToken.setMinter(address(admin));
        indexToken.mint(address(user), 100e18);
        indexToken.setMinter(address(factory));
        
        vm.stopPrank();
        vm.startPrank(user);
        uint nonce = factory.redemption(indexToken.balanceOf(address(user)));


        for(uint i = 0; i < 10; i++) {
        address tokenAddress = factory.currentList(i);
        uint id = factory.redemptionRequestId(nonce, tokenAddress);
        uint orderAmount = factory.sellRequestAssetAmountById(id);
        assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.ACTIVE));
        assertEq(issuer.getUnfilledAmount(id), orderAmount);
        }
        

    }


    function testCompleteRedemption() public {
        vm.startPrank(admin);
        updateOracleList();

        
        
        
        for(uint i; i < 10; i++) {
        address tokenAddress = factory.currentList(i);
        DShare(tokenAddress).mint(address(vault), 1000e18);
        }
        
        indexToken.setMinter(address(admin));
        indexToken.mint(address(user), 10000e18);
        indexToken.setMinter(address(factory));
        
        vm.stopPrank();
        vm.startPrank(user);
        uint nonce = factory.redemption(indexToken.balanceOf(address(user)));

        for(uint i; i < 10; i++) {
        address tokenAddress = factory.currentList(i);
        uint id = factory.redemptionRequestId(nonce, tokenAddress);
        uint orderAmount = factory.sellRequestAssetAmountById(id);
        IOrderProcessor.Order memory order = factory.getOrderInctanceById(id);
        vm.stopPrank();
        vm.prank(admin);
        paymentToken.mint(operator, 100e18);
        vm.prank(operator);
        paymentToken.approve(address(issuer), 100e18);

        // uint256 userPaymentBefore = paymentToken.balanceOf(address());
        // uint256 operatorPaymentBefore = paymentToken.balanceOf(operator);
        vm.prank(operator);
        issuer.fillOrder(order, 1000e18, 100e18, 1e18);
        assertEq(issuer.getUnfilledAmount(id), 0);
        assertEq(uint8(issuer.getOrderStatus(id)), uint8(IOrderProcessor.OrderStatus.FULFILLED));
        
        }

        assertEq(factory.checkRedemptionOrdersStatus(nonce), true);
        assertEq(factory.redemptionIsCompleted(nonce), false);
        factory.completeRedemption(nonce);
        assertEq(factory.redemptionIsCompleted(nonce), true);
    }

    
}
