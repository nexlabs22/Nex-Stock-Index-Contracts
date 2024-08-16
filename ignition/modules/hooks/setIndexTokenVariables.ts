import { ethers } from "hardhat";

import {
    abi as IndexToken_ABI,
    bytecode as IndexToken_BYTECODE,
  } from '../../../artifacts/contracts/token/IndexToken.sol/IndexToken.json'
import {
    abi as Vault_ABI,
    bytecode as Vault_BYTECODE,
  } from '../../../artifacts/contracts/vault/NexVault.sol/NexVault.json'
import { dShares, IndexFactoryAddresses, IndexFactoryProcessorAddresses, IndexFactoryStorageAddresses, Mag7IndexTokenAddresses, NexVaultAddresses, wrappedDshares } from "../../../contractAddresses";
// import { goerliAnfiFactoryAddress } from "../contractAddresses";
require("dotenv").config()

async function main() {
    const [deployer] = await ethers.getSigners();
    const provider = new ethers.JsonRpcProvider(process.env.ETHEREUM_SEPOLIA_RPC_URL)
    const indexTokenContract:any = new ethers.Contract(
        Mag7IndexTokenAddresses['sepolia'] as string,
        IndexToken_ABI,
        provider
    )
    const vaultContract:any = new ethers.Contract(
        NexVaultAddresses['sepolia'] as string,
        Vault_ABI,
        provider
    )

    console.log("setting factory as index token minter...")
    const result1 = await indexTokenContract.connect(deployer).setMinter(
        IndexFactoryAddresses['sepolia'] as string,
        true
    )
    const receipt1 = await result1.wait();

    console.log("setting factoryProcessor as index token minter...")
    const result2 = await indexTokenContract.connect(deployer).setMinter(
        IndexFactoryProcessorAddresses['sepolia'] as string,
        true
    )
    const receipt2 = await result2.wait();

    console.log("setting factory as operator for vault...")
    const result3 = await vaultContract.connect(deployer).setOperator(
        IndexFactoryAddresses['sepolia'] as string,
        true
    );
    const receipt3 = await result3.wait();


    console.log("setting factoryProcessor as operator for vault...")
    const result4 = await vaultContract.connect(deployer).setOperator(
        IndexFactoryProcessorAddresses['sepolia'] as string,
        true
    );
    const receipt4 = await result4.wait();
    console.log('Ended')
}

main()