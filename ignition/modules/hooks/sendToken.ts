import { createPublicClient, createWalletClient, http, Log, publicActions } from 'viem'
import { mainnet, sepolia } from 'viem/chains'
require("dotenv").config()
import {
    abi as Token_ABI,
    bytecode as Token_BYTECODE,
  } from '../../../artifacts/contracts/test/Token.sol/Token.json'
import { UsdcAddresses } from '../../../contractAddresses'
import { privateKeyToAccount } from 'viem/accounts'
// import { Event } from '../../../typechain-types/contracts/factory/TestIndexFactory';
// import {}

// const client = createPublicClient({ 
//   chain: sepolia, 
//   transport: http(process.env.ETHEREUM_SEPOLIA_RPC_URL), 
// }) 
const account = privateKeyToAccount(`0x${process.env.PRIVATE_KEY}` as `0x${string}`) 

const client = createWalletClient({ 
    account,
    chain: sepolia, 
    transport: http(process.env.ETHEREUM_SEPOLIA_RPC_URL), 
  }).extend(publicActions) 


async function main(){
// const blockNumber = await client.getBlockNumber()
// console.log(blockNumber)

const { request } = await client.simulateContract({
    account,
    address: UsdcAddresses[`sepolia`] as `0x${string}`,
    abi: Token_ABI,
    functionName: 'transfer',
    args: ["0xe98A6145acF43Fa2f159B28C70eB036A5Dc69409", 1000000n]
  }) // Public Action
const hash = await client.writeContract(request) // Wallet Action
console.log(hash)
}
main()
