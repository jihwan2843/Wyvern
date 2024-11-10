import { ethers } from "hardhat";

async function main() {
  const ProxyRegistry = await ethers.getContractFactory("WyvernProxyRegistry");
  const proxyRegistry = ProxyRegistry.deploy({ nounce: 22 });
  // 배포가 완료될 때까지 기달리기
  await proxyRegistry.deployed();
  console.log("Proxy Registry Address:", proxyRegistry.address);

  const Exchange = await ethers.getContractFactory("NFTExchange");
  const exchange = await Exchange.deploy("0x", proxyRegistry.address, {
    nounce: 23,
  });

  await exchange.deployed();

  console.log("NFT Exchange", exchange.address);

  await proxyRegistry.function.grantAuthentication(exchange.address, {
    nounce: 24,
  });
  console.log("Allow exchange to use proxy contracts successfully");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
