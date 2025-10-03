// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Balloons.sol";

contract DEX {
    // 🔔 Event log untuk tracking di test
    event EthToTokenSwap(address indexed swapper, uint256 tokensBought, uint256 ethSold);
    event TokenToEthSwap(address indexed swapper, uint256 tokensIn, uint256 ethOut);
    event LiquidityProvided(address indexed provider, uint256 ethAmount, uint256 tokenAmount, uint256 liquidityMinted);
    event LiquidityRemoved(address indexed provider, uint256 ethAmount, uint256 tokenAmount, uint256 liquidityBurned);

    Balloons public token;
    uint256 public totalLiquidity; // total LP liquidity di pool
    mapping(address => uint256) public liquidity; // LP balance tiap user

    constructor(address token_addr) {
        token = Balloons(token_addr);
    }

    // 🟢 Init pertama kali pool
    function init(uint256 tokens) public payable returns (uint256) {
        require(totalLiquidity == 0, "DEX: already has liquidity");
        require(msg.value > 0 && tokens > 0, "DEX: invalid init params");

        totalLiquidity = address(this).balance; // ETH jadi base liquidity
        liquidity[msg.sender] = totalLiquidity;

        require(token.transferFrom(msg.sender, address(this), tokens), "DEX: transferFrom failed");
        return totalLiquidity;
    }

    // 🔢 Formula constant product pricing (x * y = k)
    function price(uint256 inputAmount, uint256 inputReserve, uint256 outputReserve) public pure returns (uint256) {
        require(inputReserve > 0 && outputReserve > 0, "DEX: invalid reserves");
        uint256 inputAmountWithFee = inputAmount * 997; // 0.3% fee
        uint256 numerator = inputAmountWithFee * outputReserve;
        uint256 denominator = (inputReserve * 1000) + inputAmountWithFee;
        return numerator / denominator;
    }

    // 💱 Swap ETH → Token
function ethToToken() public payable returns (uint256) {
    require(msg.value > 0, "DEX: must send ETH");

    uint256 ethReserve = address(this).balance - msg.value;
    uint256 tokenReserve = token.balanceOf(address(this));

    uint256 tokensBought = price(msg.value, ethReserve, tokenReserve);

    require(token.transfer(msg.sender, tokensBought), "DEX: transfer failed");

    // ✅ emit ETH yang dikirim user (msg.value), bukan yang dihitung
    emit EthToTokenSwap(msg.sender, tokensBought, msg.value);

    return tokensBought;
}


    // 💱 Swap Token → ETH
    function tokenToEth(uint256 tokensSold) public returns (uint256) {
        require(tokensSold > 0, "DEX: must sell tokens");

        uint256 tokenReserve = token.balanceOf(address(this));
        uint256 ethReserve = address(this).balance;

        uint256 ethBought = price(tokensSold, tokenReserve, ethReserve);

        require(token.transferFrom(msg.sender, address(this), tokensSold), "DEX: transferFrom failed");
        payable(msg.sender).transfer(ethBought);

        emit TokenToEthSwap(msg.sender, tokensSold, ethBought);
        return ethBought;
    }

    // ➕ Deposit liquidity ke pool
    function deposit() public payable returns (uint256) {
        require(msg.value > 0, "DEX: must send ETH");

        uint256 ethReserve = address(this).balance - msg.value;
        uint256 tokenReserve = token.balanceOf(address(this));

        uint256 tokenAmount = (msg.value * tokenReserve) / ethReserve;
        uint256 liquidityMinted = (msg.value * totalLiquidity) / ethReserve;

        liquidity[msg.sender] += liquidityMinted;
        totalLiquidity += liquidityMinted;

        require(token.transferFrom(msg.sender, address(this), tokenAmount), "DEX: transferFrom failed");

        emit LiquidityProvided(msg.sender, msg.value, tokenAmount, liquidityMinted);
        return liquidityMinted;
    }

    // ➖ Withdraw liquidity
    function withdraw(uint256 amount) public returns (uint256, uint256) {
        require(liquidity[msg.sender] >= amount, "DEX: not enough liquidity");

        uint256 ethAmount = (amount * address(this).balance) / totalLiquidity;
        uint256 tokenAmount = (amount * token.balanceOf(address(this))) / totalLiquidity;

        liquidity[msg.sender] -= amount;
        totalLiquidity -= amount;

        payable(msg.sender).transfer(ethAmount);
        require(token.transfer(msg.sender, tokenAmount), "DEX: transfer failed");

        emit LiquidityRemoved(msg.sender, ethAmount, tokenAmount, amount);
        return (ethAmount, tokenAmount);
    }

    // 📊 View liquidity user
    function getLiquidity(address user) public view returns (uint256) {
        return liquidity[user];
    }
}
