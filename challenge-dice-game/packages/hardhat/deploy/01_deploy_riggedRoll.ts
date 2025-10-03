import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy, get } = deployments;
  const { deployer } = await getNamedAccounts();

  // Ambil contract DiceGame yang sudah dideploy di step 00
  const diceGame = await get("DiceGame");

  await deploy("RiggedRoll", {
    from: deployer,
    args: [diceGame.address], // ✅ cuma 1 argumen
    log: true,
  });
};

export default func;
func.tags = ["RiggedRoll"];
