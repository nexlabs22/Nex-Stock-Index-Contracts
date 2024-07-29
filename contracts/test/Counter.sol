// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";


/// @title Order Manager
/// @author NEX Labs Protocol
/// @notice Allows User to initiate burn/mint requests and allows issuers to approve or deny them
contract Counter is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    uint public number;

    function initialize() external initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
    }

    function increaseNumber() public {
        number += 1;
    }
    
}
