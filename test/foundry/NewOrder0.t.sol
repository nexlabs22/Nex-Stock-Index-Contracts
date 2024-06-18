// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
// import "solady/test/utils/mocks/MockERC20.sol";
import "../../contracts/test/MockERC20.sol";
import {MockToken} from "./utils/mocks/MockToken.sol";
import "./utils/mocks/GetMockDShareFactory.sol";
import "./utils/SigUtils.sol";
import "../../contracts/dinary/orders/OrderProcessor.sol";
import "../../contracts/dinary/orders/IOrderProcessor.sol";
import {TransferRestrictor} from "../../contracts/dinary/TransferRestrictor.sol";
import {NumberUtils} from "../../contracts/dinary/common/NumberUtils.sol";
import {FeeLib} from "../../contracts/dinary/common/FeeLib.sol";
import {DShare} from "../../contracts/dinary/DShare.sol";
// import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract OrderProcessorTest is Test {
   using GetMockDShareFactory for DShareFactory;

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

    uint256 userPrivateKey;
    uint256 adminPrivateKey;
    address user;
    address admin;

    address constant operator = address(3);
    address constant treasury = address(4);
    address public restrictor_role = address(1);

    uint256 dummyOrderFees;

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
        console.log("issuer.owner()", issuer.owner());
        console.log("admin", admin);
        console.log("issuer.owner()", issuer.owner() == admin);
        assertEq(issuer.owner() == admin, true);
        // assert(address(issuer.owner()), address(admin));
        // console.log("issuer.treasury()", issuer.treasury());
        // assertEq(issuer.owner(), admin);
        // assertEq(issuer.treasury(), treasury);
        // assertEq(issuer.vault(), operator);
        // assertEq(address(issuer.dShareFactory()), address(tokenFactory));
    }
}
