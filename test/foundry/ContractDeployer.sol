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
import "../../contracts/factory/IndexFactoryProcessor.sol";
import "../../contracts/factory/IndexFactoryStorage.sol";
import "../../contracts/factory/IndexFactoryBalancer.sol";
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
import {WrappedDShare} from "../../contracts/dinary/WrappedDShare.sol";
import {MockV3Aggregator} from "../../contracts/test/MockV3Aggregator.sol";

contract ContractDeployer is Test {
   using GetMockDShareFactory for DShareFactory;

   bytes32 jobId = "6b88e0402e5d415eb946e528b8e0c7ba";

    
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



    function deployAllContracts() public {
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
        orderManager.initialize(address(paymentToken), paymentToken.decimals(), address(issuer));

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
        
        factoryStorage = new IndexFactoryStorage();
        factoryStorage.initialize(
            address(issuer), 
            address(indexToken), 
            address(vault), 
            address(paymentToken), 
            paymentToken.decimals(), 
            address(link), 
            address(oracle), 
            jobId,
            true
        );

        factoryBalancer = new IndexFactoryBalancer();
        factoryBalancer.initialize(
            address(factoryStorage)
        );

        factory = new IndexFactory();
        factory.initialize(
            address(factoryStorage)
        );

        factoryProcessor = new IndexFactoryProcessor();
        factoryProcessor.initialize(
            address(factoryStorage)
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

        for(uint i = 0; i < 10; i++) {
            tokens[i] = tokenFactory.deployDShare(admin, "Dinari Token", "dTKN");
            
            tokens[i].grantRole(tokens[i].MINTER_ROLE(), admin);
            tokens[i].grantRole(tokens[i].MINTER_ROLE(), address(issuer));
            tokens[i].grantRole(tokens[i].BURNER_ROLE(), address(issuer));

            restrictors[i] = TransferRestrictor(address(tokens[i].transferRestrictor()));
            restrictors[i].grantRole(restrictors[i].RESTRICTOR_ROLE(), restrictor_role);

            //set decimal reduction
            uint8 tokenDecimals = token.decimals();
            issuer.setOrderDecimalReduction(address(tokens[i]), tokenDecimals);
            //deploy wrapped dshare
            WrappedDShare wrappedTokensImp = new WrappedDShare();
            wrappedTokens[i] = WrappedDShare(
            address(
                new ERC1967Proxy(
                    address(wrappedTokensImp),
                    abi.encodeCall(wrappedTokensImp.initialize, (address(admin), tokens[i], "Wrapped Dinari Token", "wDTKN"))
                )
            )
            );
            //mint token to dshare
            tokens[i].mint(address(admin), 1000e18);
            tokens[i].approve(address(wrappedTokens[i]), 1000e18);
            wrappedTokens[i].deposit(1000e18, address(admin));
            //deploy price feed
            priceFeeds[i] = new MockV3Aggregator(
                18, //decimals
                10e18   //initial data
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
    }

    

    

    function deployTokens() public returns(Token[11] memory) {
        Token[11] memory tokens;
        
        for (uint256 i = 0; i < 11; i++) {
            tokens[i] = new Token(1000000e18);
        }

        return tokens;
    }

    
    
    

    
}
