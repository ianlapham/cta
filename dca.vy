from vyper.interfaces import ERC20

struct User:
  active: bool
  funds: uint256(wei)
  numOfInvestments: uint256
  amtPerInvestment: uint256(wei)
  bounty: uint256(wei)
  timeDelta: timedelta
  lastInvestmentStamp: timestamp
  totalInvestmentsMade: uint256
  totalEthInvested : uint256(wei)

contract Exchange():
  def tokenAddress() -> address: constant
  def getEthToTokenInputPrice(eth_sold: uint256(wei)) -> uint256: constant

# Events 
NewUser: event({_user: indexed(address)})
InvestmentMade : event({_user : indexed(address)})

# global uniswap exchange address for this ERC20
exchange: address

# mapping to hold investment preferences f
userData: map(address, User)

@public
def setup(_exchangeAddress: address):
  """
  @notice Setup dca to point to Uniswap Exchange
  @dev should only be called once
  """

  # check that exchange has not been setup yet 
  assert(self.exchange == ZERO_ADDRESS)

  # set the exchange address
  self.exchange = _exchangeAddress

@public 
@constant
def getExchange() -> address:
  """
  @notice Get exchange address
  """
  return self.exchange

@public 
@payable
def __default__() :
  if self.userData[msg.sender].active:
    self.userData[msg.sender].funds += msg.value
  

@public
def executeInvestment(_userAddress: address):
  """
  @notice invest on the behalf of a registered user 
  @dev called once when user first creates an account
  @dev calls uniswap contract and sells ETH for Rinkeby OMG
  @dev OMG is transfered to registered user and bounty is transfered to caller as reward
  """
  # check that now is >= last investment plus delta 
  assert(block.timestamp >= self.userData[_userAddress].lastInvestmentStamp + self.userData[_userAddress].timeDelta)

  # check that they have investments left to make
  assert(self.userData[_userAddress].numOfInvestments > 0)

  # check that the user has enough to pay bounty to msg.sender plus invest 
  assert(self.userData[_userAddress].funds >= self.userData[_userAddress].amtPerInvestment + self.userData[_userAddress].bounty)

  # calculate the amount of tokens that will be bought
  tokensBought: uint256 = Exchange(self.exchange).getEthToTokenInputPrice(self.userData[_userAddress].amtPerInvestment)

  # send eth to uniswap and collect tokens
  raw_call(self.exchange, b"moose", outsize=32, gas=50000, value=self.userData[_userAddress].amtPerInvestment)

  # get token and transfer from this contract to user 
  ERC20(Exchange(self.exchange).tokenAddress()).transfer(_userAddress, tokensBought)

  # update the last investment time 
  self.userData[_userAddress].lastInvestmentStamp = block.timestamp
  
  # update user balance 
  self.userData[_userAddress].funds -= self.userData[_userAddress].amtPerInvestment

  # 
  self.userData[_userAddress].totalEthInvested += self.userData[_userAddress].amtPerInvestment
  self.userData[_userAddress].totalInvestmentsMade += 1

  # give bounty to msg.sender (only external bounty hunters)
  if msg.sender !=self:
    send(msg.sender, self.userData[_userAddress].bounty)

  log.InvestmentMade(_userAddress)

@public 
@payable
def setupUser(_numOfInvestments: uint256, _amtPerInvestment: uint256(wei), _bounty: uint256(wei), _timeDelta: timedelta):
  """
  @notice create a DCA account for new user
  @dev multiple calls will overwrite existing data 
  """

  # check funds to make first investment and lock bounty
  assert(msg.value >= _amtPerInvestment + _bounty)
  
  # create user entry
  userEntry: User = User({
      active: True,
      funds: msg.value,
      numOfInvestments : _numOfInvestments,
      amtPerInvestment : _amtPerInvestment,
      bounty: _bounty,
      timeDelta: _timeDelta,
      lastInvestmentStamp: block.timestamp - _timeDelta,
      totalInvestmentsMade: 0,
      totalEthInvested : 0
  })

  # add to mapping
  self.userData[msg.sender] = userEntry

  # execute the first payment 
  self.executeInvestment(msg.sender)

  log.NewUser(msg.sender)

@public 
def updateSettings(_numOfInvestments: uint256, _amtPerInvestment: uint256(wei), _bounty: uint256(wei), _timeDelta: timedelta):
  """
  @notice update settings for a resgistered user  
  @dev should only call for existing users 
  """

  # check for active user 
  assert(self.userData[msg.sender].active)

  # update the settings 
  self.userData[msg.sender].numOfInvestments = _numOfInvestments
  self.userData[msg.sender].amtPerInvestment = _amtPerInvestment
  self.userData[msg.sender].bounty = _bounty
  self.userData[msg.sender].timeDelta = _timeDelta

@public
@payable
def addFunds(_userAddress: address):
  """
  @notice increase investing funds for a given user
  @dev must be called if user balance is running low
  """

  # increase the funds for the specified user 
  self.userData[_userAddress].funds += msg.value

@public 
@constant
def getData(_userAddress: address) -> User:
  """
  @notice get user data - useful for UIs
  """

  return self.userData[_userAddress]



