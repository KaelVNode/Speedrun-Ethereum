// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
  function transfer(address to, uint256 amount) external returns (bool);
  function transferFrom(address from, address to, uint256 amount) external returns (bool);
  function balanceOf(address account) external view returns (uint256);
  function allowance(address owner, address spender) external view returns (uint256);
}

interface ICornDEX {
  /// @dev Harga 1 ETH dalam CORN (skala 1e18).
  function currentPrice() external view returns (uint256);
}

contract Lending {
  /* ---------- Constants ---------- */
  uint256 private constant PRECISION = 1e18;
  uint256 private constant HUNDRED_PERCENT = 100 * PRECISION;

  /// @notice minimal rasio kolateral 120% (dalam persen * 1e18).
  uint256 public constant COLLATERAL_RATIO = 120 * PRECISION;
  /// @notice insentif likuidator 10% (dalam persen * 1e18).
  uint256 public constant LIQUIDATOR_REWARD = 10 * PRECISION;

  /* ---------- Immutables ---------- */
  IERC20 public immutable i_corn;
  ICornDEX public immutable i_cornDEX;

  /* ---------- Storage ---------- */
  mapping(address => uint256) public s_userCollateral; // ETH (wei)
  mapping(address => uint256) public s_userBorrowed;   // CORN (1e18)

  /* ---------- Events ---------- */
  event CollateralAdded(address indexed user, uint256 amountEth, uint256 priceCornPerEth);
  event CollateralWithdrawn(address indexed user, uint256 amountEth, uint256 priceCornPerEth);
  event AssetBorrowed(address indexed user, uint256 amountCorn, uint256 priceCornPerEth);
  event AssetRepaid(address indexed user, uint256 amountCorn, uint256 priceCornPerEth);
  event Liquidation(address indexed borrower, address indexed liquidator, uint256 repaidCorn, uint256 paidEth, uint256 priceCornPerEth);

  /* ---------- Errors (samakan dengan test) ---------- */
  error Lending__InvalidAmount();
  error Lending__InsufficientCollateral();
  error Lending__InsufficientBorrowed();
  error Lending__UnsafePositionRatio();
  error Lending__NotLiquidatable();
  error Lending__InsufficientLiquidatorCorn();
  error Lending__TransferFailed();
  error Lending__RepayingFailed();

  /* ---------- Constructor (URUTANNYA: DEX dulu, lalu CORN) ---------- */
  constructor(ICornDEX _dex, IERC20 _corn) {
    i_cornDEX = _dex;
    i_corn = _corn;
  }

  /* ---------------- Collateral ---------------- */

  function addCollateral() external payable {
    if (msg.value == 0) revert Lending__InvalidAmount();
    s_userCollateral[msg.sender] += msg.value;
    emit CollateralAdded(msg.sender, msg.value, i_cornDEX.currentPrice());
  }

  function withdrawCollateral(uint256 amount) external {
    if (amount == 0) revert Lending__InvalidAmount();
uint256 current = s_userCollateral[msg.sender];
// if (amount > current) revert Lending__InsufficientCollateral();
if (amount > current) revert Lending__InvalidAmount();


    unchecked {
      s_userCollateral[msg.sender] = current - amount;
    }

    // Jika masih punya utang, pastikan tetap aman setelah penarikan
    if (s_userBorrowed[msg.sender] > 0) _validatePosition(msg.sender);

    (bool ok, ) = payable(msg.sender).call{value: amount}("");
    if (!ok) revert Lending__TransferFailed();

    emit CollateralWithdrawn(msg.sender, amount, i_cornDEX.currentPrice());
  }

  /* ---------------- Helpers ---------------- */

  /// @notice nilai kolateral (ETH) user dalam CORN (1e18)
  function calculateCollateralValue(address user) public view returns (uint256) {
    uint256 collateralEth = s_userCollateral[user];
    uint256 priceCornPerEth = i_cornDEX.currentPrice(); // CORN per 1 ETH (1e18)
    return (collateralEth * priceCornPerEth) / PRECISION;
  }

  /// @dev (collateralValue / borrowed) * 100% * 1e18  (contoh 133% => 133e18)
  function _calculatePositionRatio(address user) internal view returns (uint256) {
    uint256 borrowed = s_userBorrowed[user];
    if (borrowed == 0) {
      return type(uint256).max;
    }
    uint256 collateralValueCorn = calculateCollateralValue(user);
    return (collateralValueCorn * HUNDRED_PERCENT) / borrowed;
  }

  function isLiquidatable(address user) public view returns (bool) {
    return _calculatePositionRatio(user) < COLLATERAL_RATIO;
  }

  function _validatePosition(address user) internal view {
    if (isLiquidatable(user)) revert Lending__UnsafePositionRatio();
  }

  /* ---------------- Borrow / Repay ---------------- */

  function borrowCorn(uint256 borrowAmount) external {
    if (borrowAmount == 0) revert Lending__InvalidAmount();

    s_userBorrowed[msg.sender] += borrowAmount;
    _validatePosition(msg.sender);

    bool ok = i_corn.transfer(msg.sender, borrowAmount);
    if (!ok) revert Lending__TransferFailed();

    emit AssetBorrowed(msg.sender, borrowAmount, i_cornDEX.currentPrice());
  }

  function repayCorn(uint256 repayAmount) external {
    if (repayAmount == 0) revert Lending__InvalidAmount();
uint256 borrowed = s_userBorrowed[msg.sender];
// if (repayAmount > borrowed) revert Lending__InsufficientBorrowed();
if (repayAmount > borrowed) revert Lending__InvalidAmount();

    s_userBorrowed[msg.sender] = borrowed - repayAmount;

    bool ok = i_corn.transferFrom(msg.sender, address(this), repayAmount);
    if (!ok) revert Lending__RepayingFailed();

    emit AssetRepaid(msg.sender, repayAmount, i_cornDEX.currentPrice());
  }

  /* ---------------- Liquidate ---------------- */

  function liquidate(address borrower) external {
    if (!isLiquidatable(borrower)) revert Lending__NotLiquidatable();

    uint256 debtCorn = s_userBorrowed[borrower];
    if (debtCorn == 0) revert Lending__NotLiquidatable();

    if (i_corn.balanceOf(msg.sender) < debtCorn || i_corn.allowance(msg.sender, address(this)) < debtCorn) {
      revert Lending__InsufficientLiquidatorCorn();
    }

    bool pulled = i_corn.transferFrom(msg.sender, address(this), debtCorn);
    if (!pulled) revert Lending__TransferFailed();

    // clear utang
    s_userBorrowed[borrower] = 0;

    // konversi CORN -> ETH berdasar harga DEX
    uint256 priceCornPerEth = i_cornDEX.currentPrice(); // CORN per 1 ETH
    uint256 baseEth = (debtCorn * PRECISION) / priceCornPerEth;

    // reward
    uint256 rewardEth = (baseEth * LIQUIDATOR_REWARD) / HUNDRED_PERCENT;
    uint256 payEth = baseEth + rewardEth;

    uint256 col = s_userCollateral[borrower];
    if (payEth > col) payEth = col;

    s_userCollateral[borrower] = col - payEth;

    (bool sent, ) = payable(msg.sender).call{value: payEth}("");
    if (!sent) revert Lending__TransferFailed();

    emit Liquidation(borrower, msg.sender, debtCorn, payEth, priceCornPerEth);
  }

  receive() external payable {}
}
