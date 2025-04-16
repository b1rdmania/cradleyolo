// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Shared Mock ERC20 for all tests
contract MockERC20 is IERC20 {
    using SafeERC20 for IERC20;

    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;
    uint256 public totalSupply_;
    string public name;
    string public symbol;
    uint8 public decimals_;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals_ = _decimals;
    }

    function decimals() external view returns (uint8) {
        return decimals_;
    }

    function totalSupply() external view returns (uint256) {
        return totalSupply_;
    }

    function balanceOf(address _account) external view returns (uint256) {
        return balances[_account];
    }

    function transfer(address _recipient, uint256 _amount) external returns (bool) {
        balances[msg.sender] -= _amount;
        balances[_recipient] += _amount;
        emit Transfer(msg.sender, _recipient, _amount);
        return true;
    }

    function allowance(address _owner, address _spender) external view returns (uint256) {
        return allowances[_owner][_spender];
    }

    function approve(address _spender, uint256 _amount) external returns (bool) {
        allowances[msg.sender][_spender] = _amount;
        emit Approval(msg.sender, _spender, _amount);
        return true;
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) external returns (bool) {
        uint256 currentAllowance = allowances[_sender][msg.sender];
        require(currentAllowance >= _amount, "ERC20: transfer amount exceeds allowance");

        allowances[_sender][msg.sender] -= _amount;
        balances[_sender] -= _amount;
        balances[_recipient] += _amount;
        emit Transfer(_sender, _recipient, _amount);
        return true;
    }

    function mint(address _account, uint256 _amount) external {
        balances[_account] += _amount;
        totalSupply_ += _amount;
        emit Transfer(address(0), _account, _amount);
    }
}
