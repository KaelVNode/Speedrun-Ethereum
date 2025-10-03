import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const deployVendor: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { getNamedAccounts, deployments, ethers } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  // ambil deployment YourToken dari step 00
  const yourToken = await deployments.get("YourToken");

  // deploy Vendor dengan address token
  const vendor = await deploy("Vendor", {
    from: deployer,
    args: [yourToken.address],
    log: true,
  });

  // transfer 900 token ke Vendor
  const tokenContract = await ethers.getContractAt("YourToken", yourToken.address);
  const tx = await tokenContract.transfer(vendor.address, ethers.parseUnits("900", 18));
  await tx.wait();

  console.log(`✅ Vendor deployed at ${vendor.address} & funded with 900 YTK`);
};

export default deployVendor;
deployVendor.tags = ["Vendor"];
