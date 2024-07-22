import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
require("@nomicfoundation/hardhat-foundry");
require("@openzeppelin/hardhat-upgrades");
require("dotenv").config()

const config: HardhatUserConfig = {
  // solidity: "0.8.24",
  solidity: {
    compilers: [
      {
        version: "0.8.23",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.25",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.7",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.20",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  networks: {
    sepolia: {
      url: process.env.ETHEREUM_SEPOLIA_RPC_URL !== undefined ? process.env.ETHEREUM_SEPOLIA_RPC_URL : '',
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
      chainId: 11155111
    }
  },
  etherscan: {
    // apiKey: {
    //   sepolia: process.env.ETHERSCAN_API_KEY as string,
    //   polygonMumbai: process.env.POLYGONSCAN_API_KEY as string,
    //   arbitrumSepolia: process.env.ARBITRUMSCAN_API_KEY as string
    //   // arbitrumTestnet: process.env.ARBITRUMSCAN_API_KEY as string
    // }
    apiKey: process.env.ETHERSCAN_API_KEY as string
  },
};

export default config;
