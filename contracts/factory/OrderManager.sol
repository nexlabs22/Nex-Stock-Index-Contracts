// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../dinary/orders/IOrderProcessor.sol";
import {FeeLib} from "../dinary/common/FeeLib.sol";

/// @title Order Manager
/// @author NEX Labs Protocol
/// @notice Allows User to initiate burn/mint requests and allows issuers to approve or deny them
contract OrderManager is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    enum RequestStatus {
        NULL,
        PENDING,
        CANCELED,
        APPROVED,
        REJECTED
    }

    struct Request {
        address requester; // sender of the request.
        uint256 amount; // amount of token to mint/burn.
        address[] depositAddresses; // issuer's asset address in mint, merchant's asset address in burn.
        uint256 nonce; // serial number allocated for each request.
        uint256 timestamp; // time of the request creation.
        RequestStatus status; // status of the request.
    }

    address public custodianWallet;
    IOrderProcessor public issuer;

    address public usdc;
    uint8 public usdcDecimals;

    address public token;

    

    // mapping between a mint request hash and the corresponding request nonce.
    mapping(bytes32 => uint256) public mintRequestNonce;

    // mapping between a burn request hash and the corresponding request nonce.
    mapping(bytes32 => uint256) public burnRequestNonce;

    Request[] public mintRequests;
    Request[] public burnRequests;

    
    function initialize(
        address _usdc,
        uint8 _usdcDecimals,
        address _token,
        address _issuer
    ) external initializer {
        usdc = _usdc;
        usdcDecimals = _usdcDecimals;
        issuer = IOrderProcessor(_issuer);
        token = _token;
        __Ownable_init(msg.sender);
        __Pausable_init();
    }


    function setUsdcAddress(
        address _usdc,
        uint8 _usdcDecimals
    ) public onlyOwner returns (bool) {
        require(_usdc != address(0), "invalid token address");
        usdc = _usdc;
        usdcDecimals = _usdcDecimals;
        return true;
    }

    

    function getAllMintRequests() public view returns (Request[] memory) {
        return mintRequests;
    }

    function getAllBurnRequests() public view returns (Request[] memory) {
        return burnRequests;
    }

    
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function getPrimaryOrder(bool sell) internal view returns (IOrderProcessor.Order memory) {
        return IOrderProcessor.Order({
            requestTimestamp: uint64(block.timestamp),
            recipient: address(this),
            assetToken: address(token),
            paymentToken: address(usdc),
            sell: sell,
            orderType: IOrderProcessor.OrderType.MARKET,
            assetTokenQuantity: sell ? 100 ether : 0,
            paymentTokenQuantity: sell ? 0 : 100 ether,
            price: 0,
            tif: IOrderProcessor.TIF.GTC
        });
    }
    
    function requestBuyOrder(address _token, uint256 orderAmount) public returns(uint) {
       
        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(false, address(usdc));
        uint256 fees = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, orderAmount);
        
        IOrderProcessor.Order memory order = getPrimaryOrder(false);
        order.recipient = address(this);
        order.assetToken = address(_token);
        order.paymentTokenQuantity = orderAmount;
        uint256 quantityIn = order.paymentTokenQuantity + fees;

        IERC20(usdc).transferFrom(msg.sender, address(this), quantityIn);
       
        IERC20(usdc).approve(address(issuer), quantityIn);
        uint256 id = issuer.createOrderStandardFees(order);
        return id;
    }


    function requestSellOrder(address _token, uint256 _orderAmount) public returns(uint) {
        
        IOrderProcessor.Order memory order = getPrimaryOrder(true);
        order.assetToken = _token;
        order.assetTokenQuantity = _orderAmount;

       IERC20(token).transferFrom(msg.sender, address(this), _orderAmount);

       IERC20(token).approve(address(issuer), _orderAmount);

        // balances before
        uint256 id = issuer.createOrderStandardFees(order);
        return id;
    }
    
}
