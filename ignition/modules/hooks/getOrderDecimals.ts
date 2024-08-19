import { ethers } from "hardhat";

import {
    abi as USDC_ABI,
    bytecode as USDC_BYTECODE,
  } from '../../../artifacts/contracts/test/Token.sol/Token.json'
import {
    abi as Factory_ABI,
    bytecode as Factory_BYTECODE,
  } from '../../../artifacts/contracts/factory/IndexFactory.sol/IndexFactory.json'
import {
    abi as Issuer_ABI,
    bytecode as Issuer_BYTECODE,
  } from '../../../artifacts/contracts/dinary/orders/OrderProcessor.sol/OrderProcessor.json'
import { dShares, IndexFactoryAddresses, IndexFactoryStorageAddresses, Mag7IndexTokenAddresses, NexVaultAddresses, OrderManagerAddresses, OrderProcessorAddresses, UsdcAddresses, wrappedDshares } from "../../../contractAddresses";
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
    const issuerContract:any = new ethers.Contract(
        OrderProcessorAddresses['sepolia'] as string, //factory goerli
        Issuer_ABI,
        provider
    )
    
    const tokens = [
        dShares[0], //apple
        dShares[2], //meta
        dShares[3], //amazon
        dShares[5], //nvidia
        dShares[15],// advanced micro devices
        dShares[21],// blockInch
        dShares[39], //reddit
        ]
    for(let i=0; i<tokens.length; i++){
    const dShareTokenContract =  new ethers.Contract(
        tokens[i],
        USDC_ABI,
        provider
    )
    const result = await issuerContract.orderDecimalReduction(tokens[i]);
    console.log("Fee is", result)
    const decimals = Number(await dShareTokenContract.decimals())
    console.log("decimals", decimals)
    const balance = Number(await dShareTokenContract.balanceOf(IndexFactoryAddresses['sepolia']))
    console.log("balance", balance)
    // console.log("Fee is", 1000 % 10 ** (Number(result) - 1))
    console.log("reduction", balance % 10 ** (Number(result) - 1))
    console.log("reduction2", (balance - balance % 10 ** (Number(result) - 1)) % 10 ** (Number(result) - 1))
    }
    // return;
    // console.log("approving tokens...")
    // const result = await usdcContract.connect(deployer).approve(IndexFactoryAddresses[`sepolia`], "101000000")
    // const receipt = await result.wait();
    // console.log("sending request...")
    // const result1 = await factoryContract.connect(deployer).redemption(
    //     "10000000000000000000", //10 usdc
    //     {gasLimit: 5000000}
    // )
    // const result1 = await factoryContract.connect(deployer).tRedemption(
    //     {gasLimit: 5000000}
    // )
    // const receipt1 = await result1.wait();
    // console.log('hash', receipt1.hash)
    // console.log('Ended')
}

main()