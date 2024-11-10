require("@nomicfoundation/hardhat-toolbox");

const config = {
  solidity: {
    version: "0.8.0",
    settings: {
      // optimizer를 적용하면 배포 시 가스 수수료를 절약 가능
      optimizer: {
        enabled: true,
        runs: 1000,
      },
    },
  },
  networks: {
    hardhat: {},
    goerli: {
      url: "provider api key",
      accounts: ["12312"],
    },
  },
};

export default config;
