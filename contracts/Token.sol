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

  // Dividends — O(1) accumulator pattern
  uint256 private constant SCALE = 1e18;
  uint256 private _dividendPerToken;
  mapping (address => uint256) private _lastDividendPerToken;
  mapping (address => uint256) private _creditedDividends;

  // --- Internal helpers ---

  function _settleDividends(address addr) internal {
    uint256 owed = _dividendPerToken.sub(_lastDividendPerToken[addr]);
    if (owed > 0) {
      _creditedDividends[addr] = _creditedDividends[addr].add(
        balanceOf[addr].mul(owed).div(SCALE)
      );
      _lastDividendPerToken[addr] = _dividendPerToken;
    }
  }

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

    _settleDividends(msg.sender);
    _settleDividends(to);

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

    _settleDividends(from);
    _settleDividends(to);

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

    _settleDividends(msg.sender);

    balanceOf[msg.sender] = balanceOf[msg.sender].add(msg.value);
    totalSupply = totalSupply.add(msg.value);

    _addHolder(msg.sender);
  }

  function burn(address payable dest) external override {
    uint256 amount = balanceOf[msg.sender];
    require(amount > 0, "No tokens to burn");

    _settleDividends(msg.sender);

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
    _dividendPerToken = _dividendPerToken.add(msg.value.mul(SCALE).div(totalSupply));
  }

  function getWithdrawableDividend(address payee) external view override returns (uint256) {
    uint256 owed = _dividendPerToken.sub(_lastDividendPerToken[payee]);
    return _creditedDividends[payee].add(balanceOf[payee].mul(owed).div(SCALE));
  }

  function withdrawDividend(address payable dest) external override {
    _settleDividends(msg.sender);
    uint256 amount = _creditedDividends[msg.sender];
    require(amount > 0, "No dividends");

    _creditedDividends[msg.sender] = 0;
    dest.transfer(amount);
  }
}
