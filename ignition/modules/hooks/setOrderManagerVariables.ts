import { ethers } from "hardhat";

import {
    abi as OrderManager_ABI,
    bytecode as OrderManager_BYTECODE,
  } from '../../../artifacts/contracts/factory/OrderManager.sol/OrderManager.json'
import { dShares, IndexFactoryAddresses, IndexFactoryProcessorAddresses, IndexFactoryStorageAddresses, Mag7IndexTokenAddresses, NexVaultAddresses, OrderManagerAddresses, wrappedDshares } from "../../../contractAddresses";
// import { goerliAnfiFactoryAddress } from "../contractAddresses";
require("dotenv").config()

async function main() {

    const [deployer] = await ethers.getSigners();
    const provider = new ethers.JsonRpcProvider(process.env.ETHEREUM_SEPOLIA_RPC_URL)

    const orderManagerContract:any = new ethers.Contract(
        OrderManagerAddresses['sepolia'] as string, //factory goerli
        OrderManager_ABI,
        provider
    )

    console.log("setting factory as order manager operator...")
    const result1 = await orderManagerContract.connect(deployer).setOperator(
        IndexFactoryAddresses['sepolia'] as string,
        true
    )
    const receipt1 = await result1.wait();

    console.log("setting factoryProcessor as order manager operator...")
    const result2 = await orderManagerContract.connect(deployer).setOperator(
        IndexFactoryProcessorAddresses['sepolia'] as string,
        true
    )
    const receipt2 = await result2.wait();
    console.log('Ended')
}

main()