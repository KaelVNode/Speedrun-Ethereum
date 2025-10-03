// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ExampleExternalContract.sol";

contract Staker {
    ExampleExternalContract public exampleExternalContract;

    mapping(address => uint256) public balances;
    uint256 public constant threshold = 1 ether;
    uint256 public deadline;
    bool public openForWithdraw;

    event Stake(address indexed staker, uint256 amount);

    constructor(address externalContractAddress) {
        exampleExternalContract = ExampleExternalContract(externalContractAddress);
        deadline = block.timestamp + 30 seconds; // buat testing cepat
        openForWithdraw = false;
    }

    modifier beforeDeadline() {
        require(block.timestamp < deadline, "Deadline passed");
        _;
    }

    modifier afterDeadline() {
        require(block.timestamp >= deadline, "Still before deadline");
        _;
    }

    modifier notCompleted() {
        require(!exampleExternalContract.completed(), "Already completed");
        _;
    }

    function stake() public payable beforeDeadline notCompleted {
        require(msg.value > 0, "Must send ETH");
        balances[msg.sender] += msg.value;
        emit Stake(msg.sender, msg.value);
    }

    function execute() public afterDeadline notCompleted {
        uint256 contractBalance = address(this).balance;
        if (contractBalance >= threshold) {
            exampleExternalContract.complete{value: contractBalance}();
        } else {
            openForWithdraw = true;
        }
    }

    function withdraw() public afterDeadline notCompleted {
        require(openForWithdraw, "Withdrawals not open");
        uint256 userBal = balances[msg.sender];
        require(userBal > 0, "No balance");
        balances[msg.sender] = 0;
        (bool sent, ) = payable(msg.sender).call{value: userBal}("");
        require(sent, "Withdraw failed");
    }

    function timeLeft() public view returns (uint256) {
        if (block.timestamp >= deadline) return 0;
        return deadline - block.timestamp;
    }

    receive() external payable {
        stake();
    }
}
