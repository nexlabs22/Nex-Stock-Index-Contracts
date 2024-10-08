import { ethers } from "hardhat";

import {
    abi as USDC_ABI,
    bytecode as USDC_BYTECODE,
  } from '../../../artifacts/contracts/test/Token.sol/Token.json'
import {
    abi as Factory_ABI,
    bytecode as Factory_BYTECODE,
  } from '../../../artifacts/contracts/factory/IndexFactory.sol/IndexFactory.json'
import { dShares, IndexFactoryAddresses, IndexFactoryStorageAddresses, Mag7IndexTokenAddresses, NexVaultAddresses, OrderManagerAddresses, UsdcAddresses, wrappedDshares } from "../../../contractAddresses";
// import { goerliAnfiFactoryAddress } from "../contractAddresses";
require("dotenv").config()

const inputAmount = "100000000"
async function main() {

    const [deployer] = await ethers.getSigners();
    const provider = new ethers.JsonRpcProvider(process.env.ETHEREUM_SEPOLIA_RPC_URL)

    const usdcContract:any = new ethers.Contract(
        UsdcAddresses['sepolia'] as string, //factory goerli
        USDC_ABI,
        provider
    )
    const factoryContract:any = new ethers.Contract(
        IndexFactoryAddresses['sepolia'] as string, //factory goerli
        Factory_ABI,
        provider
    )
    // const fee = await factoryContract.calculateIssuanceFee(inputAmount);
    // console.log("Fee is", fee)
    // return;
    console.log("cancelling request...")
    const result1 = await factoryContract.connect(deployer).cancelIssuance(
        "42", // issuanceNonce
        {gasLimit: 3000000}
    )
    const receipt1 = await result1.wait();
    console.log('hash', receipt1.hash)
    console.log('Ended')
}

main()