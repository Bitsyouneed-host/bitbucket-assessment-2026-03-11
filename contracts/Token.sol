pragma solidity 0.7.0;

import "./IERC20.sol";
import "./IMintableToken.sol";
import "./IDividends.sol";
import "./SafeMath.sol";

contract Token is IERC20, IMintableToken, IDividends {
  // ------------------------------------------ //
  // ----- BEGIN: DO NOT EDIT THIS SECTION ---- //
  // ------------------------------------------ //
  using SafeMath for uint256;
  uint256 public totalSupply;
  uint256 public decimals = 18;
  string public name = "Test token";
  string public symbol = "TEST";
  mapping (address => uint256) public balanceOf;
  // ------------------------------------------ //
  // ----- END: DO NOT EDIT THIS SECTION ------ //
  // ------------------------------------------ //

  // ERC-20 allowances
  mapping (address => mapping (address => uint256)) private _allowances;

  // Holder tracking: 1-based index array
  address[] private _holders;
  mapping (address => uint256) private _holderIndex; // 1-based; 0 = not a holder

  // Dividends
  mapping (address => uint256) private _dividends;

  // --- Internal holder management ---

  function _addHolder(address addr) internal {
    if (_holderIndex[addr] == 0) {
      _holders.push(addr);
      _holderIndex[addr] = _holders.length;
    }
  }

  function _removeHolder(address addr) internal {
    uint256 idx = _holderIndex[addr];
    if (idx == 0) return;

    uint256 lastIdx = _holders.length;
    if (idx != lastIdx) {
      address lastHolder = _holders[lastIdx - 1];
      _holders[idx - 1] = lastHolder;
      _holderIndex[lastHolder] = idx;
    }
    _holders.pop();
    _holderIndex[addr] = 0;
  }

  function _updateHolder(address addr) internal {
    if (balanceOf[addr] > 0) {
      _addHolder(addr);
    } else {
      _removeHolder(addr);
    }
  }

  // IERC20

  function allowance(address owner, address spender) external view override returns (uint256) {
    return _allowances[owner][spender];
  }

  function transfer(address to, uint256 value) external override returns (bool) {
    require(balanceOf[msg.sender] >= value, "Insufficient balance");

    balanceOf[msg.sender] = balanceOf[msg.sender].sub(value);
    balanceOf[to] = balanceOf[to].add(value);

    _updateHolder(msg.sender);
    _updateHolder(to);

    return true;
  }

  function approve(address spender, uint256 value) external override returns (bool) {
    _allowances[msg.sender][spender] = value;
    return true;
  }

  function transferFrom(address from, address to, uint256 value) external override returns (bool) {
    require(balanceOf[from] >= value, "Insufficient balance");
    require(_allowances[from][msg.sender] >= value, "Insufficient allowance");

    balanceOf[from] = balanceOf[from].sub(value);
    balanceOf[to] = balanceOf[to].add(value);
    _allowances[from][msg.sender] = _allowances[from][msg.sender].sub(value);

    _updateHolder(from);
    _updateHolder(to);

    return true;
  }

  // IMintableToken

  function mint() external payable override {
    require(msg.value > 0, "Must send ETH");

    balanceOf[msg.sender] = balanceOf[msg.sender].add(msg.value);
    totalSupply = totalSupply.add(msg.value);

    _addHolder(msg.sender);
  }

  function burn(address payable dest) external override {
    uint256 amount = balanceOf[msg.sender];
    require(amount > 0, "No tokens to burn");

    balanceOf[msg.sender] = 0;
    totalSupply = totalSupply.sub(amount);

    _removeHolder(msg.sender);

    dest.transfer(amount);
  }

  // IDividends

  function getNumTokenHolders() external view override returns (uint256) {
    return _holders.length;
  }

  function getTokenHolder(uint256 index) external view override returns (address) {
    if (index == 0 || index > _holders.length) {
      return address(0);
    }
    return _holders[index - 1];
  }

  function recordDividend() external payable override {
    require(msg.value > 0, "Must send ETH");

    uint256 total = totalSupply;
    uint256 len = _holders.length;

    for (uint256 i = 0; i < len; i++) {
      address holder = _holders[i];
      uint256 share = msg.value.mul(balanceOf[holder]).div(total);
      _dividends[holder] = _dividends[holder].add(share);
    }
  }

  function getWithdrawableDividend(address payee) external view override returns (uint256) {
    return _dividends[payee];
  }

  function withdrawDividend(address payable dest) external override {
    uint256 amount = _dividends[msg.sender];
    require(amount > 0, "No dividends");

    _dividends[msg.sender] = 0;
    dest.transfer(amount);
  }
}
