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

  mapping (address => mapping (address => uint256)) private _allowances;

  address[] private _holders;
  mapping (address => uint256) private _holderIndex;

  uint256 private constant SCALE = 1e18;
  uint256 private _dividendPerToken;
  mapping (address => uint256) private _lastDividendPerToken;
  mapping (address => uint256) private _creditedDividends;

  function _settle(address addr, uint256 dpt) internal {
    uint256 bal = balanceOf[addr];
    if (bal == 0) {
      // Skip SSTORE when no balance — just sync the pointer if needed
      if (_lastDividendPerToken[addr] != dpt) {
        _lastDividendPerToken[addr] = dpt;
      }
      return;
    }
    uint256 last = _lastDividendPerToken[addr];
    if (last < dpt) {
      _creditedDividends[addr] = _creditedDividends[addr].add(
        bal.mul(dpt.sub(last)).div(SCALE)
      );
      _lastDividendPerToken[addr] = dpt;
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
      address last = _holders[lastIdx - 1];
      _holders[idx - 1] = last;
      _holderIndex[last] = idx;
    }
    _holders.pop();
    _holderIndex[addr] = 0;
  }

  // IERC20

  function allowance(address owner, address spender) external view override returns (uint256) {
    return _allowances[owner][spender];
  }

  function transfer(address to, uint256 value) external override returns (bool) {
    uint256 senderBal = balanceOf[msg.sender];
    require(senderBal >= value, "bal");

    uint256 dpt = _dividendPerToken;
    _settle(msg.sender, dpt);
    _settle(to, dpt);

    balanceOf[msg.sender] = senderBal.sub(value);
    balanceOf[to] = balanceOf[to].add(value);

    if (balanceOf[msg.sender] == 0) _removeHolder(msg.sender);
    if (value > 0) _addHolder(to);

    return true;
  }

  function approve(address spender, uint256 value) external override returns (bool) {
    _allowances[msg.sender][spender] = value;
    return true;
  }

  function transferFrom(address from, address to, uint256 value) external override returns (bool) {
    uint256 fromBal = balanceOf[from];
    require(fromBal >= value, "bal");
    require(_allowances[from][msg.sender] >= value, "allow");

    uint256 dpt = _dividendPerToken;
    _settle(from, dpt);
    _settle(to, dpt);

    balanceOf[from] = fromBal.sub(value);
    balanceOf[to] = balanceOf[to].add(value);
    _allowances[from][msg.sender] = _allowances[from][msg.sender].sub(value);

    if (balanceOf[from] == 0) _removeHolder(from);
    if (value > 0) _addHolder(to);

    return true;
  }

  // IMintableToken

  function mint() external payable override {
    require(msg.value > 0, "val");

    _settle(msg.sender, _dividendPerToken);

    balanceOf[msg.sender] = balanceOf[msg.sender].add(msg.value);
    totalSupply = totalSupply.add(msg.value);

    _addHolder(msg.sender);
  }

  function burn(address payable dest) external override {
    uint256 amount = balanceOf[msg.sender];
    require(amount > 0, "bal");

    _settle(msg.sender, _dividendPerToken);

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
    if (index == 0 || index > _holders.length) return address(0);
    return _holders[index - 1];
  }

  function recordDividend() external payable override {
    require(msg.value > 0, "val");
    _dividendPerToken = _dividendPerToken.add(msg.value.mul(SCALE).div(totalSupply));
  }

  function getWithdrawableDividend(address payee) external view override returns (uint256) {
    uint256 dpt = _dividendPerToken;
    uint256 owed = dpt.sub(_lastDividendPerToken[payee]);
    return _creditedDividends[payee].add(balanceOf[payee].mul(owed).div(SCALE));
  }

  function withdrawDividend(address payable dest) external override {
    _settle(msg.sender, _dividendPerToken);
    uint256 amount = _creditedDividends[msg.sender];
    require(amount > 0, "div");

    _creditedDividends[msg.sender] = 0;
    dest.transfer(amount);
  }
}
