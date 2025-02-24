// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../chainlink/FunctionsClient.sol";
import "../chainlink/ConfirmedOwner.sol";
import "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";

/// @title Index Token Factory Storage
/// @notice Stores data and provides functions for managing index token issuance and redemption
contract FunctionsOracle is
    Initializable,
    FunctionsClient, 
    ConfirmedOwner
{
    using FunctionsRequest for FunctionsRequest.Request;

    

    // Addresses of factory contracts
    address public factoryBalancerAddress;

    bytes32 public donId; // DON ID for the Functions DON to which the requests are sent
    address public functionsRouterAddress;
    uint public lastUpdateTime;


    // Total number of oracles and current list
    uint public totalOracleList;
    uint public totalCurrentList;
    
    // Mappings for oracle and current lists
    mapping(uint => address) public oracleList;
    mapping(uint => address) public currentList;



    // Mappings for token indices
    mapping(address => uint) public tokenOracleListIndex;
    mapping(address => uint) public tokenCurrentListIndex;

    // Mappings for token market shares
    mapping(address => uint) public tokenCurrentMarketShare;
    mapping(address => uint) public tokenOracleMarketShare;



    /// @notice Initializes the contract with the given parameters
    /// @param _functionsRouterAddress The address of the functions router
    /// @param _newDonId The don ID for the oracle
    function initialize(
        address _functionsRouterAddress,
        bytes32 _newDonId
    ) external initializer {
        require(_functionsRouterAddress != address(0), "invalid functions router address");
        require(_newDonId.length > 0, "invalid don id");
        __FunctionsClient_init(_functionsRouterAddress);
        __ConfirmedOwner_init(msg.sender);
        donId = _newDonId;
        functionsRouterAddress = _functionsRouterAddress;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }


    /**
     * @notice Set the DON ID
     * @param newDonId New DON ID
     */
    function setDonId(bytes32 newDonId) external onlyOwner {
        donId = newDonId;
    }

    

   

    function setFactoryBalancer(address _factoryBalancerAddress) public onlyOwner {
        require(_factoryBalancerAddress != address(0), "invalid factory balancer address");
        factoryBalancerAddress = _factoryBalancerAddress;
    }



    function requestAssetsData(
        string calldata source,
        bytes calldata encryptedSecretsReference,
        string[] calldata args,
        bytes[] calldata bytesArgs,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) public returns (bytes32) {
        FunctionsRequest.Request memory req;
        req.initializeRequest(FunctionsRequest.Location.Inline, FunctionsRequest.CodeLanguage.JavaScript, source);
        req.secretsLocation = FunctionsRequest.Location.Remote;
        req.encryptedSecretsReference = encryptedSecretsReference;
        if (args.length > 0) {
        req.setArgs(args);
        }
        if (bytesArgs.length > 0) {
        req.setBytesArgs(bytesArgs);
        }
        return _sendRequest(req.encodeCBOR(), subscriptionId, callbackGasLimit, donId);
    }

    /**
    * @notice Store latest result/error
    * @param requestId The request ID, returned by sendRequest()
    * @param response Aggregated response from the user code
    * @param err Aggregated error from the user code or from the execution pipeline
    * Either response or error parameter will be set, but never both
    */
    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
        (address[] memory _tokens,
        uint256[] memory _marketShares) = abi.decode(response, (address[], uint256[]));
        require(requestId.length > 0, "invalid request id");
        require(_tokens.length > 0, "invalid tokens");
        require(_marketShares.length > 0, "invalid market shares");
        _initData(_tokens, _marketShares);
    }

    

    function _initData(address[] memory _tokens, uint256[] memory _marketShares) private {
        address[] memory tokens0 = _tokens;
        uint[] memory marketShares0 = _marketShares;

        // //save mappings
        for(uint i =0; i < tokens0.length; i++){
            oracleList[i] = tokens0[i];
            tokenOracleListIndex[tokens0[i]] = i;
            tokenOracleMarketShare[tokens0[i]] = marketShares0[i];
            if(totalCurrentList == 0){
                currentList[i] = tokens0[i];
                tokenCurrentMarketShare[tokens0[i]] = marketShares0[i];
                tokenCurrentListIndex[tokens0[i]] = i;
            }
        }
        totalOracleList = tokens0.length;
        if(totalCurrentList == 0){
            totalCurrentList  = tokens0.length;
        }
        lastUpdateTime = block.timestamp;
    }

    function updateCurrentList() external {
        require(msg.sender == factoryBalancerAddress, "caller must be factory balancer");
        totalCurrentList = totalOracleList;
        for(uint i = 0; i < totalOracleList; i++){
            address tokenAddress = oracleList[i];
            currentList[i] = tokenAddress;
            tokenCurrentMarketShare[tokenAddress] = tokenOracleMarketShare[tokenAddress];
            tokenCurrentListIndex[tokenAddress] = i;
        }
    }

    function mockFillAssetsList(address[] memory _tokens, uint256[] memory _marketShares)
    public
    onlyOwner
    {
        _initData(_tokens, _marketShares);
    }
    

    
    
}
