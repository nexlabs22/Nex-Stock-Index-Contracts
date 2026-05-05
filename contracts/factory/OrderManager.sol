// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title Order Manager
/// @author NEX Labs Protocol
/// @notice Custodies funds and validates operator signatures (ERC-1271)
contract OrderManager is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable, IERC1271 {
    using SafeERC20 for IERC20;

    event FundsWithdrawn(address token, address to, uint256 amount);

    address public usdc;
    uint8 public usdcDecimals;

    mapping(address => bool) public isOperator;

    /// @notice Index factory allowed to release user escrow on timeout cancellation (no operator signature).
    address public indexFactory;

    event EscrowReleased(address indexed token, address indexed to, uint256 amount);

    function initialize(address _usdc, uint8 _usdcDecimals) external initializer {
        require(_usdc != address(0), "invalid token address");
        require(_usdcDecimals > 0, "invalid decimals");
        usdc = _usdc;
        usdcDecimals = _usdcDecimals;
        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function setUsdcAddress(address _usdc, uint8 _usdcDecimals) public onlyOwner returns (bool) {
        require(_usdc != address(0), "invalid token address");
        usdc = _usdc;
        usdcDecimals = _usdcDecimals;
        return true;
    }

    function setOperator(address _operator, bool _status) public onlyOwner {
        isOperator[_operator] = _status;
    }

    function setIndexFactory(address _indexFactory) external onlyOwner {
        require(_indexFactory != address(0), "invalid factory address");
        indexFactory = _indexFactory;
    }

    /// @notice Releases escrowed ERC20 to a user; only callable by the IndexFactory (timeout cancel path).
    function releaseEscrow(address _token, address _to, uint256 _amount) external nonReentrant {
        require(msg.sender == indexFactory, "Caller is not index factory");
        require(_token != address(0), "invalid token address");
        require(_to != address(0), "invalid address");
        require(_amount > 0, "amount must be greater than 0");
        emit EscrowReleased(_token, _to, _amount);
        IERC20(_token).safeTransfer(_to, _amount);
    }

    function withdrawFunds(address _token, address _to, uint256 _amount) external nonReentrant {
        require(_token != address(0), "invalid token address");
        require(_to != address(0), "invalid address");
        require(_amount > 0, "amount must be greater than 0");
        require(isOperator[msg.sender] || msg.sender == owner(), "Not authorized Sender For Buy And Sell");
        emit FundsWithdrawn(_token, _to, _amount);
        IERC20(_token).safeTransfer(_to, _amount);
    }

    function isValidSignature(bytes32 _hash, bytes memory _signature) public view override returns (bytes4) {
        address signer = ECDSA.recover(_hash, _signature);
        
        if (isOperator[signer]) {
            return IERC1271.isValidSignature.selector;
        } else {
            return 0xffffffff;
        }
    }
}
