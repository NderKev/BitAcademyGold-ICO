pragma solidity ^0.4.23;

import "./BitAcademyToken.sol";
import "./RefundVault.sol";

/**
 * @title Crowdsale
 * @dev Crowdsale is a base contract for managing a token crowdsale,
 * allowing investors to purchase tokens with ether. This contract implements
 * such functionality in its most fundamental form and can be extended to provide additional
 * functionality and/or custom behavior.
 * The external interface represents the basic interface for purchasing tokens, and conform
 * the base architecture for crowdsales. They are *not* intended to be modified / overriden.
 * The internal interface conforms the extensible and modifiable surface of crowdsales. Override
 * the methods to add functionality. Consider using 'super' where appropiate to concatenate
 * behavior.
 */
contract Crowdsale is Ownable{
  using SafeMath for uint256;

  // The token being sold
  BitAcademyToken public token;

  // Address where funds are collected
  address public wallet;

  // No of wei needed for each token
  uint256 public rate;

  // Amount of wei raised
  uint256 public weiRaised;

  // Save Token Holder addresses
  address public tokenHolder;

  mapping(address => bool) public whitelist;

  uint256 public openingTime;
  uint256 public closingTime;

  // Remaining tokens which are yet to be sold
  uint256 public remainingTokens;

  // Tokens sold excluding bonus
  uint256 public tokenSoldExcludeBonus;

  // minimum amount of funds to be raised in weis
  uint256 public goal;

  // refund vault used to hold funds while crowdsale is running
  RefundVault public vault;

  /**
   * @dev Reverts if beneficiary is not whitelisted. Can be used when extending this contract.
   */
  modifier isWhitelisted(address _beneficiary) {
    require(whitelist[_beneficiary]);
    _;
  }

  /**
   * @dev Reverts if not in crowdsale time range.
   */
  modifier onlyWhileOpen {
    // solium-disable-next-line security/no-block-members
    require(block.timestamp >= openingTime && block.timestamp <= closingTime);
    _;
  }

  bool public isFinalized = false;

  event Finalized();

  /**
   * @dev Must be called after crowdsale ends, to do some extra finalization
   * work. Calls the contract's finalization function.
   */
  function finalize() onlyOwner public {
    require(!isFinalized);
    require(hasClosed());

    finalization();
    emit Finalized();

    isFinalized = true;
  }

  /**
   * @dev Investors can claim refunds here if crowdsale is unsuccessful
   */
  function claimRefund() public {
    require(isFinalized);
    require(!goalReached());

    vault.refund(msg.sender);
  }

  /**
   * @dev Checks whether funding goal was reached.
   * @return Whether funding goal was reached
   */
  function goalReached() public view returns (bool) {
    return weiRaised >= goal;
  }

  /**
   * @dev vault finalization task, called when owner calls finalize()
   */
  function finalization() internal {
    if (goalReached()) {
      vault.close();
    } else {
      vault.enableRefunds();
    }
  }

  /**
   * Event for token purchase logging
   * @param purchaser who paid for the tokens
   * @param beneficiary who got the tokens
   * @param value weis paid for purchase
   * @param amount amount of tokens purchased
   */
  event TokenPurchase(
    address indexed purchaser,
    address indexed beneficiary,
    uint256 value,
    uint256 amount
  );

  /**
   * @param _rate No of tokens per ether
   * @param _wallet Address where collected funds will be forwarded to
   * @param _token Address of the token being sold
   */
  constructor(uint256 _rate, address _wallet, BitAcademyToken _token, uint256 _openingTime, uint256 _closingTime,address _tokenHolder,uint256 _goal) public {
    require(_rate > 0);
    require(_wallet != address(0));
    require(_token != address(0));
    require(_tokenHolder!= address(0));
    require(_openingTime >= block.timestamp);
    require(_closingTime >= _openingTime);
    require(_goal > 0);

    vault = new RefundVault(wallet);
    goal = _goal;
    rate = _rate;
    wallet = _wallet;
    token = _token;
    tokenHolder = _tokenHolder;
    openingTime = _openingTime;
    closingTime = _closingTime;
    remainingTokens = token.totalSupply();
  }

  // -----------------------------------------
  // Crowdsale external interface
  // -----------------------------------------

  /**
   * @dev fallback function ***DO NOT OVERRIDE***
   */
  function () external payable {
    buyTokens(msg.sender);
  }
  /**
   * @dev low level token purchase ***DO NOT OVERRIDE***
   * @param _beneficiary Address performing the token purchase
   */
  function buyTokens(address _beneficiary) public payable {

    uint256 weiAmount = msg.value;
    uint256 refundWeiAmt = 0;
    uint256 tokens = 0;
    _preValidatePurchase(_beneficiary, weiAmount);

    // calculate token amount to be delivered
     (tokens, refundWeiAmt) = _getTokenAmount(weiAmount);

    /* If the remaining tokens are less than tokens calculated above
     * proceed with purchase of remaining tokens and refund the remaining ethers
     * to the caller
     */
    if(refundWeiAmt > 0) {
      msg.sender.transfer(refundWeiAmt);
      weiAmount = weiAmount.sub(refundWeiAmt);
    }

    // update state
    weiRaised = weiRaised.add(weiAmount);

    _processPurchase(_beneficiary, tokens);
    emit TokenPurchase(
      msg.sender,
      _beneficiary,
      weiAmount,
      tokens
    );

    _updatePurchasingState(_beneficiary, weiAmount);
    _forwardFunds();
    _postValidatePurchase(_beneficiary, weiAmount);
  }

  /**
   * @dev Adds single address to whitelist.
   * @param _beneficiary Address to be added to the whitelist
   */
  function addToWhitelist(address _beneficiary) external onlyOwner {
    whitelist[_beneficiary] = true;
  }

  /**
   * @dev Adds list of addresses to whitelist. Not overloaded due to limitations with truffle testing.
   * @param _beneficiaries Addresses to be added to the whitelist
   */
  function addManyToWhitelist(address[] _beneficiaries) external onlyOwner {
    for (uint256 i = 0; i < _beneficiaries.length; i++) {
      whitelist[_beneficiaries[i]] = true;
    }
  }

  /**
   * @dev Removes single address from whitelist.
   * @param _beneficiary Address to be removed to the whitelist
   */
  function removeFromWhitelist(address _beneficiary) external onlyOwner {
    whitelist[_beneficiary] = false;
  }

  /**
   * @dev Checks whether the period in which the crowdsale is open has already elapsed.
   * @return Whether crowdsale period has elapsed
   */
  function hasClosed() public view returns (bool) {
    // solium-disable-next-line security/no-block-members
    return block.timestamp > closingTime;
  }

  // -----------------------------------------
  // Internal interface (extensible)
  // -----------------------------------------

  /**
   * @dev Validation of an incoming purchase. Use require statements to revert state when conditions are not met. Use super to concatenate validations.
   * @param _beneficiary Address performing the token purchase
   * @param _weiAmount Value in wei involved in the purchase
   */
  function _preValidatePurchase(
    address _beneficiary,
    uint256 _weiAmount
  )
    internal
  {
    require(_beneficiary != address(0));
    require(_weiAmount != 0);
  }

  /**
   * @dev Validation of an executed purchase. Observe state and use revert statements to undo rollback when valid conditions are not met.
   * @param _beneficiary Address performing the token purchase
   * @param _weiAmount Value in wei involved in the purchase
   */
  function _postValidatePurchase(
    address _beneficiary,
    uint256 _weiAmount
  )
    internal
  {
    // optional override
  }

  /**
   * @dev Source of tokens. Override this method to modify the way in which the crowdsale ultimately gets and sends its tokens.
   * @param _beneficiary Address performing the token purchase
   * @param _tokenAmount Number of tokens to be emitted
   */
  function _deliverTokens(
    address _beneficiary,
    uint256 _tokenAmount
  )
    internal
  {
    token.transferFrom(tokenHolder,_beneficiary, _tokenAmount);
  }

  /**
   * @dev Executed when a purchase has been validated and is ready to be executed. Not necessarily emits/sends tokens.
   * @param _beneficiary Address receiving the tokens
   * @param _tokenAmount Number of tokens to be purchased
   */
  function _processPurchase(
    address _beneficiary,
    uint256 _tokenAmount
  )
    internal
    isWhitelisted(_beneficiary)
    onlyWhileOpen
  {
    _deliverTokens(_beneficiary, _tokenAmount);
  }

  /**
   * @dev Override for extensions that require an internal state to check for validity (current user contributions, etc.)
   * @param _beneficiary Address receiving the tokens
   * @param _weiAmount Value in wei involved in the purchase
   */
  function _updatePurchasingState(
    address _beneficiary,
    uint256 _weiAmount
  )
    internal
  {
    // optional override
  }

  /**
   * @dev Override to extend the way in which ether is converted to tokens.
   * @param _weiAmount Value in wei to be converted into tokens
   * @return Token price in weis
   */
  function _getTokenAmount(uint256 _weiAmount)
    internal view returns (uint256, uint256)
  {
    //remainingTokens = remainingTokens.sub(_tokenAmount);
    uint256 noOfTokens = 0;
    uint256 tokensInCondition = 0;
    uint256 weiAmount  = _weiAmount;
    uint256 currentRate = rate;

    if(remainingTokens > 300000000*(10**18)) {
      currentRate = currentRate.mul(10);
      currentRate = currentRate.div(13);
      tokensInCondition = weiAmount.div(currentRate);
      if(tokensInCondition > remainingTokens.sub(300000000*(10**18))){
        tokensInCondition = remainingTokens.sub(300000000*(10**18));
        weiAmount = weiAmount.sub(tokensInCondition.mul(currentRate));
        noOfTokens = noOfTokens.add(tokensInCondition);
        remainingTokens = remainingTokens.sub(noOfTokens);
      }
    }

    if (remainingTokens < 300000000*(10**18) && remainingTokens >= 250000000*(10**18) && weiAmount > 0){

      currentRate = currentRate.mul(100);
      currentRate = currentRate.div(125);
      tokensInCondition = weiAmount.div(currentRate);
      if(tokensInCondition > remainingTokens.sub(250000000*(10**18))){
        tokensInCondition = remainingTokens.sub(250000000*(10**18));
        weiAmount = weiAmount.sub(tokensInCondition.mul(currentRate));
        noOfTokens = noOfTokens.add(tokensInCondition);
        remainingTokens = remainingTokens.sub(noOfTokens);
      }
    }
    if (remainingTokens < 250000000*(10**18) && remainingTokens >= 200000000*(10**18) && weiAmount > 0 ){
      currentRate = currentRate.mul(100);
      currentRate = currentRate.div(120);
      tokensInCondition = weiAmount.div(currentRate);
      if(tokensInCondition > remainingTokens.sub(200000000*(10**18))){
        tokensInCondition = remainingTokens.sub(200000000*(10**18));
        weiAmount = weiAmount.sub(tokensInCondition.mul(currentRate));
        noOfTokens = noOfTokens.add(tokensInCondition);
        remainingTokens = remainingTokens.sub(noOfTokens);
      }
    }
    if (remainingTokens < 200000000*(10**18) && remainingTokens >= 150000000*(10**18) && weiAmount > 0 ){
      currentRate = currentRate.mul(100);
      currentRate = currentRate.div(115);
      tokensInCondition = weiAmount.div(currentRate);
      if(tokensInCondition > remainingTokens.sub(150000000*(10**18))){
        tokensInCondition = remainingTokens.sub(150000000*(10**18));
        weiAmount = weiAmount.sub(tokensInCondition.mul(currentRate));
        noOfTokens = noOfTokens.add(tokensInCondition);
        remainingTokens = remainingTokens.sub(noOfTokens);
      }
    }
     if (remainingTokens < 150000000*(10**18) && remainingTokens >= 100000000*(10**18) && weiAmount > 0){

      currentRate = currentRate.mul(100);
      currentRate = currentRate.div(110);
      tokensInCondition = weiAmount.div(currentRate);
      if(tokensInCondition > remainingTokens.sub(100000000*(10**18))){
        tokensInCondition = remainingTokens.sub(100000000*(10**18));
        weiAmount = weiAmount.sub(tokensInCondition.mul(currentRate));
        noOfTokens = noOfTokens.add(tokensInCondition);
        remainingTokens = remainingTokens.sub(noOfTokens);
      }
    }

    if (remainingTokens < 100000000*(10**18) && remainingTokens >= 50000000*(10**18) ){
      currentRate = currentRate.mul(100);
      currentRate = currentRate.div(105);
      tokensInCondition = weiAmount.div(currentRate);
      if(tokensInCondition > remainingTokens.sub(50000000*(10**18))){
        tokensInCondition = remainingTokens.sub(50000000*(10**18));
        weiAmount = weiAmount.sub(tokensInCondition.mul(currentRate));
        noOfTokens = noOfTokens.add(tokensInCondition);
        remainingTokens = remainingTokens.sub(noOfTokens);
      }
    }
    if(remainingTokens < 50000000*(10**18)){
      tokensInCondition = weiAmount.div(currentRate);
      if(tokensInCondition > remainingTokens) {
        noOfTokens = remainingTokens;
        weiAmount = weiAmount.sub(noOfTokens.mul(currentRate));
      }
    }
    return (noOfTokens, weiAmount);
  }

  /**
   * @dev Determines how ETH is stored/forwarded on purchases.
   */
  function _forwardFunds() internal {
    vault.deposit.value(msg.value)(msg.sender);
  }

  function setRate(uint256 _rate) public onlyOwner{
    rate = _rate;
  }
}
