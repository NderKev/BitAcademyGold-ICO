pragma solidity ^0.4.23;

import "openzeppelin-solidity/contracts/token/ERC20/PausableToken.sol";

contract BitAcademyToken is PausableToken {
  string public constant name = "Bitcademy Gold";
  string public constant symbol = "BTMG";
  uint public constant decimals = 18;

  constructor(address _reserve,uint _initial_supply) public{
    totalSupply_ = (_initial_supply*(10**decimals));
    balances[_reserve] = (_initial_supply*(10**decimals));
    emit Transfer(this,_reserve,totalSupply_);
  }
}
