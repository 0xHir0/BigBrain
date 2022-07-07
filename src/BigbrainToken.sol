// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./IERC20.sol";
import "./Address.sol";
import "./Context.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router02.sol";

contract BigBrainToken is Context, IERC20, Ownable {
    using SafeMath for uint256;
    using Address for address;

    /// @dev Address for the USDC vault
    address public vault;

    /// (tokenOwner => amount): reflections owned by a specific user
    mapping (address => uint256) private _rOwned;
    /// (tokenOwner => amount): total tokens owned by a specific user (including reflections)
    mapping (address => uint256) private _tOwned;
    /// (tokenOwner => (tokenSpender => amount)): the amount that someone is allowed to spend on behalf of someone else in transferFrom()
    /// @notice when would you increase/decrease the allowance to spend on behalf of someone?
    mapping (address => mapping (address => uint256)) private _allowances;

    /// the addresses to exclude from the fee- USDC vault contract, this contract, owner
    mapping (address => bool) private _isExcludedFromFee;

    /// @notice why use this vs _isExcludedFromFee?
    mapping (address => bool) private _isExcluded;
    address[] private _excluded;

    /// 
    uint256 private constant MAX = ~uint256(0);
    uint256 private _tTotal = 1000000000 * 10**6 * 10**9;
    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    uint256 private _tFeeTotal;

    string private _name = "BigBrain";
    string private _symbol = "BRAIN";
    uint8 private _decimals = 9;

    uint256 public _taxFee = 5;
    uint256 private _previousTaxFee = _taxFee;

    /// @dev LP fee
    uint256 public _liquidityFee = 3;
    uint256 private _previousLiquidityFee = _liquidityFee;

    /// TODO: needs to be 3.5%
    uint256 public _vaultFee = 3;
    uint256 private _previousVaultFee = _vaultFee;

    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;

    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled = true;

    uint256 public _maxTxAmount = 5000000 * 10**6 * 10**9; 
    /// @dev when the balance reaches this, you send the various amounts to the different tx endpoints- saves on gas deployments
    uint256 public numTokensSellToAddToLiquidity = 500000 * 10**6 * 10**9;

    /// @dev Called in setTaxPercent(), this updates the tax fee that is sent to the owner
    event TaxFeeUpdated(uint256 taxFee);
    /// @dev Called in setLiquidityFee(), this updates the liquidity fee that is sent to the LP
    event LiquidityFeeUpdated(uint256 liquidityFee);
    /// @dev Called in excludeFromReward(), this updates the excluded addresses from getting the tx rewards
    event ExcludeFromRewardUpdated(address account);
    /// @dev Called in includeInReward(), this updates the included addresses from getting the tx rewards
    event IncludeInRewardUpdated(address account);
    /// @dev Called in excludeFromFee(), excludes the address from paying tx fees
    event ExcludeFromFeeUpdated(address account);
    /// @dev Called in includeInFee(), includes the address in paying tx fees
    event IncludeInFeeUpdated(address account);
    /// @dev Called in setMaxTxPercent(), this updates the max amount of tokens that can be sent in a tx
    event MaxTxAmountUpdated(uint _maxTxAmount);
    /// @dev Called in setSwapAndLiquifyEnabled(), this updates the swap and liquify enabled status- 
    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event NumTokensSellToAddToLiquidityUpdated(uint256 _numTokensSellToAddToLiquidity);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    /// contract lock logic 
    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    enum Lock {
      TAX_FEE,
      LIQUIDITY_FEE,
      EXCLUDE_FROM_REWARD,
      INCLUDE_IN_REWARD,
      EXCLUDE_FROM_FEE,
      INCLUDE_IN_FEE,
      MAX_TX,
      SWAP_AND_LIQUIFY_ENABLED,
      NUM_TOKENS_SELL_TO_ADD_TO_LIQUIDITY
    }
    uint256 private constant _TIMELOCK = 1 days;
    mapping(Lock => uint256) public timelocks;

    /// @dev Timelocks a function from being called- need to do this for: 
        /// excludeFromReward
        /// includeInReward
        /// excludeFromFee
        /// includeInFee
        /// setTaxFeePercent
        /// excludeFromReward
        /// setTaxFeePercent
        /// setLiquidityFeePercent
        /// setMaxTxPercent
        /// setSwapAndLiquifyEnabled
        /// setNumTokensSellToAddToLiquidity
        /// @notice So basically all the setters are locked for 1 day, unless overridden
    modifier unlocked(Lock _lock) {
      require(timelocks[_lock] != 0 && timelocks[_lock] <= block.timestamp, "Function is timelocked");
      _;
      timelocks[_lock] = 0;
    }

    constructor () {
        /// set all current reflections for the owner to the total
        _rOwned[msg.sender] = _rTotal;

        /// set the router address
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        
        /// Create a uniswap pair for this new token
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        /// set the rest of the contract variables
        uniswapV2Router = _uniswapV2Router;

        /// exclude owner and this contract from fee
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;

        emit Transfer(address(0), msg.sender, _tTotal);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    /// @dev   Standard balanceOf check for account balance, checks if they are also excluded fromt the fees
    /// @param account The account to check the balance of
    /// @return The reflections owned from the account
    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    /// @dev   Standard transfer that calls the modified _transfer() function, that cascades a bunch of other functions for the taxes
    /// @param recipient The address to transfer to
    /// @param amount The amount to transfer
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /// @dev   Allowance to spend on behalf of another account
    /// @param owner The owner address
    /// @param spender The spender address
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    /// @dev   Approve the msg.sender to spend on behalf of the spender
    /// @param spender The address that will be spent upon
    /// @param amount The amount of tokens that are allowed to be spent
    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }
    /// @dev Approves msg.sender to approve spending on the recipients behalf for a specific amount
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    /// @dev    Increase the allowable amount to spend on behalf of `spender`
    /// @param  spender The address that the owner is spending on behalf of
    /// @param  addedAmount The amount to increase the allowance by
    function increaseAllowance(address spender, uint256 addedAmount) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedAmount));
        return true;
    }

    /// @dev    Increase the allowable amount to spend on behalf of `spender`
    /// @param  spender The address that the owner is spending on behalf of
    /// @param  subtractedAmount The amount to increase the allowance by
    /// @return Bool on whether or not approve whent through for changing the amounts
    function decreaseAllowance(address spender, uint256 subtractedAmount) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedAmount, "ERC20: decreased allowance below zero"));
        return true;
    }

    /// @dev   Check if someone is excluded from the fee
    /// @param account The account to check
    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    /// @dev    Get the total fees accumulated in this cycle
    /// @return The total fees accumulated in this cycle
    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

    /// @dev    Delivers the reflection fees to the people
    /// @param  tAmount Total amount that is being delivered
    /// @notice Only people who are not on the excluded list can call this
    function deliver(uint256 tAmount) public {
        address sender = msg.sender;
        require(!_isExcluded[sender], "Excluded addresses cannot call this function");

        (uint256 rAmount,,,,,) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rTotal = _rTotal.sub(rAmount);
        _tFeeTotal = _tFeeTotal.add(tAmount);
    }

    /// @dev    If the deductTransferFee is false, return normal fees- else return the transferAmount dudcting fees
    /// @param  tAmount The total amount of tokens
    /// @param  deductTransferFee If true, deduct the transfer fee from the total amount
    /// @return The reflections amount with or without the fee dedection
    function reflectionFromToken(uint256 tAmount, bool deductTransferFee) public view returns(uint256) {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferFee) {
            (uint256 rAmount,,,,,) = _getValues(tAmount);
            return rAmount;
        } else {
            (,uint256 rTransferAmount,,,,) = _getValues(tAmount);
            return rTransferAmount;
        }
    }

    /// @dev    Calculate the token from reflection amount / current rate, used in balanceOf and excludeFromReward
    /// @param  rAmount The reflection amount
    /// @return The token amount
    function tokenFromReflection(uint256 rAmount) public view returns(uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate =  _getRate();
        return rAmount.div(currentRate);
    }

    /// @dev   Calculate the reward that is excluded from the fee
    /// @param account Account to exclude from receiving the tax 
    function excludeFromReward(address account) public onlyOwner unlocked(Lock.EXCLUDE_FROM_REWARD) {
        require(!_isExcluded[account], "Account is already excluded");
        if(_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
        emit ExcludeFromRewardUpdated(account);
    }

    /// @dev   Calculate the reward that is included from the fee
    /// @param account Account to include for receiving the tax     
    function includeInReward(address account) external onlyOwner unlocked(Lock.INCLUDE_IN_REWARD) {
        require(_isExcluded[account], "Account is already excluded");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
        emit IncludeInRewardUpdated(account);
    }

    /// @dev   Transfers for two people that are not included in the tax- this basically is an edge case
    /// @param sender Where the tokens are coming from
    /// @param recipient Where the tokens are going
    /// @param tAmount Transfer amount
    function _transferBothExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    /// @dev   Exclude from the fees, meaning they don't pay taxes
    /// @param account The address you are adding to the exclude list
    function excludeFromFee(address account) public onlyOwner unlocked(Lock.EXCLUDE_FROM_FEE) {
        _isExcludedFromFee[account] = true;
        emit ExcludeFromFeeUpdated(account);
    }

    /// @dev   Update an address to start paying the tx fees
    /// @param account The address to start paying the tx fees
    function includeInFee(address account) public onlyOwner unlocked(Lock.INCLUDE_IN_FEE) {
        _isExcludedFromFee[account] = false;
        emit IncludeInFeeUpdated(account);
    }

    /// @dev   Set the normal tax fee percent for contract collection
    /// @param taxFee New fee
    function setTaxFeePercent(uint256 taxFee) external onlyOwner unlocked(Lock.TAX_FEE) {
        require(taxFee <= 15, "Amount must be less than or equal to 15");
        _taxFee = taxFee;
        emit TaxFeeUpdated(taxFee);
    }

    /// @dev   Set the normal liquidity fee percent for contract collection
    /// @param liquidityFee New liquidity fee
    function setLiquidityFeePercent(uint256 liquidityFee) external onlyOwner unlocked(Lock.LIQUIDITY_FEE) {
        require(liquidityFee <= 15, "Amount must be less than or equal to 15");
        _liquidityFee = liquidityFee;
        emit LiquidityFeeUpdated(liquidityFee);
    }

    /// @dev Set the max transcation percent for the traders
    function setMaxTxPercent(uint256 maxTxPercent) external onlyOwner unlocked(Lock.MAX_TX) {
        require(maxTxPercent > 0, "Amount must be greater than 0");
        _maxTxAmount = _tTotal.mul(maxTxPercent).div(
            10**2
        );
        emit MaxTxAmountUpdated(_maxTxAmount);
    }

    /// @dev   Turn on swapping
    /// @param _enabled Boolean for swapping
    function setSwapAndLiquifyEnabled(bool _enabled) public onlyOwner unlocked(Lock.SWAP_AND_LIQUIFY_ENABLED) {
        swapAndLiquifyEnabled = _enabled;
        emit SwapAndLiquifyEnabledUpdated(_enabled);
    }

    /// @dev   Setter for the number of tokens that can be added to the liquidity
    /// @param _numTokensSellToAddToLiquidity The number of tokens that can be added to the liquidity
    function setNumTokensSellToAddToLiquidity(uint256 _numTokensSellToAddToLiquidity) external onlyOwner unlocked(Lock.NUM_TOKENS_SELL_TO_ADD_TO_LIQUIDITY) {
      numTokensSellToAddToLiquidity = _numTokensSellToAddToLiquidity;
      emit NumTokensSellToAddToLiquidityUpdated(_numTokensSellToAddToLiquidity);
    }

     /// To recieve ETH from uniswapV2Router when swapping
    receive() external payable {}

    /// @dev   Reassigns the reflection fee and transaction fee- is reflection tied to the LP and transaction tied to the normal owner fee?
    /// @param rFee The new reflection fee
    /// @param tFee The new total fee
    function _reflectFee(uint256 rFee, uint256 tFee) private {
        ///@notice rTotal excludes the rFee
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    /// @dev    Getter for retreiving the transaction values and the reflection values- output of _getTValues() + _getRValues()
    /// @param  tAmount The amount of tokens to be transferred in the transaction
    /// @return A bunch of uints that represent the values of the transaction and the reflection
    function _getValues(uint256 tAmount) private view returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        (uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getTValues(tAmount);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tFee, tLiquidity, _getRate());
        return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee, tLiquidity);
    }

    /// @dev    Getter for retreiving the total taxes
    /// @param  tAmount The amount of tokens to be collected from the tax
    /// @return The total tax amount for the fee and LP
    function _getTValues(uint256 tAmount) private view returns (uint256, uint256, uint256) {
        uint256 tFee = calculateTaxFee(tAmount);
        uint256 tLiquidity = calculateLiquidityFee(tAmount);
        uint256 tTransferAmount = tAmount.sub(tFee).sub(tLiquidity);
        return (tTransferAmount, tFee, tLiquidity);
    }

    /// @dev    Getter for retreiving the total reflection amounts
    /// @param  tAmount The amount of tokens total in the tax- this is the base for all other calculations
    /// @param  tFee The fee for the transaction- how is this different than the total tax?
    /// @param  tLiquidity The fee for the liquidity 
    /// @param  currentRate The current rate of reflection tokens / total tokens- is total the amount circulating in the LP, or owned by everyone, or stored in the contract?
    /// @return rAmount, rTransferAmount, rFee- all reflection information
    /// @notice rFee, rAmount, rTransferAmount can be reduced down with optimizations
    function _getRValues(uint256 tAmount, uint256 tFee, uint256 tLiquidity, uint256 currentRate) private pure returns (uint256, uint256, uint256) {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        uint256 rLiquidity = tLiquidity.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee).sub(rLiquidity);
        return (rAmount, rTransferAmount, rFee);
    }

    /// @dev    A function to get the reflection amount as a percentage of total token amount
    /// @return The refelection total percent relative to the total tokens
    function _getRate() private view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentTotals();
        return rSupply.div(tSupply);
    }

    /// @dev    Getter for the amount of tokens that are transferred
    /// @return rTotal and tTotal minus the values stored for excluded addresses
    function _getCurrentTotals() private view returns(uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;

        /// loop through excluded list
        for (uint256 i = 0; i < _excluded.length; i++) {
            /// if someone owns more than the reflection total or the total total
            if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply) return (_rTotal, _tTotal);
            /// reflection supply subtracts thw excluded addresses reflection amount? why?
            rSupply = rSupply.sub(_rOwned[_excluded[i]]);
            /// total supply subtracts thw excluded addresses total amount? why?
            tSupply = tSupply.sub(_tOwned[_excluded[i]]);
        }

        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    /// @dev   Tax function for taking the liquidity fee from the transaction
    /// @param tLiquidity Total liquidity fee
    function _takeLiquidity(uint256 tLiquidity) private {
        uint256 currentRate =  _getRate();
        uint256 rLiquidity = tLiquidity.mul(currentRate);
        _rOwned[address(this)] = _rOwned[address(this)].add(rLiquidity);
        if(_isExcluded[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)].add(tLiquidity);
    }

    /// @dev Calculates the standard tax fee for the transaction    
    function calculateTaxFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(_taxFee).div(
            10**2
        );
    }

    /// @dev Calculates the standard liquidity fee for the transaction
    function calculateLiquidityFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(_liquidityFee).div(
            10**2
        );
    }

    /// @dev Calculates the standard vault fee for the transaction
    function calculateVaultFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(_vaultFee).div(
            10**2
        );
    }

    /// @dev Removes all the fees from the tax- sets them to 0
    function removeAllFee() private {
        if(_taxFee == 0 && _liquidityFee == 0) return;

        _previousTaxFee = _taxFee;
        _previousLiquidityFee = _liquidityFee;

        _taxFee = 0;
        _liquidityFee = 0;
    }

    /// @dev Restores the fees to their previous values
    function restoreAllFee() private {
        _taxFee = _previousTaxFee;
        _liquidityFee = _previousLiquidityFee;
    }

    /// @dev   Checks if the address is excluded from the fee
    /// @param account The address to check
    /// @return Boolean on if it is excluded
    function isExcludedFromFee(address account) public view returns(bool) {
        return _isExcludedFromFee[account];
    }

    /// @dev   Owner approves an address to spend on behalf of owner
    /// @param owner Address of the current token owner
    /// @param spender Address of the spender who will spend the owners tokens
    /// @param amount The amount of tokens the spender can spend on behalf of the current owner
    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /// @dev   Custom transfer function, invokes the _transferTokens which takes the taxes
    /// @param from Address of the current token owner
    /// @param to Address of receiver
    /// @param amount The amount of tokens to be transferred
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        if(from != owner() && to != owner())
            require(amount <= _maxTxAmount, "Transfer amount exceeds the maxTxAmount.");

        /// is the token balance of this contract address over the min number of
        /// tokens that we need to initiate a swap + liquidity lock?
            /// also, don't get caught in a circular liquidity event.
            /// also, don't swap & liquify if sender is uniswap pair.
        uint256 contractTokenBalance = balanceOf(address(this));

        /// if the current contract balance is greater than the max tx amount, reduce the contract token balance to the max tx amount
        /// @notice doesnt this reduce the balance? what happens to the tokens that are lost?
        if (contractTokenBalance >= _maxTxAmount) {
            contractTokenBalance = _maxTxAmount;
        }

        bool overMinTokenBalance = contractTokenBalance >= numTokensSellToAddToLiquidity;
        if (
            overMinTokenBalance &&
            !inSwapAndLiquify &&
            from != uniswapV2Pair &&
            swapAndLiquifyEnabled
        ) {
            contractTokenBalance = numTokensSellToAddToLiquidity;
            //add liquidity
            swapAndLiquify(contractTokenBalance);
        }

        //indicates if fee should be deducted from transfer
        bool takeFee = true;

        //if any account belongs to _isExcludedFromFee account then remove the fee
        if(_isExcludedFromFee[from] || _isExcludedFromFee[to]){
            takeFee = false;
        }

        //transfer amount, it will take tax, burn, liquidity fee
        _tokenTransfer(from, to, amount, takeFee);
    }

    /// @dev   Swaps the tokens from the current contract address to the uniswapV2Pair
    /// @param contractTokenBalance The amount of tokens to be swapped
    function swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
        // split the contract balance into halves
        uint256 half = contractTokenBalance.div(2);
        uint256 otherHalf = contractTokenBalance.sub(half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth(half); // <- this breaks the ETH -> BB swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    /// @dev   Trade tokens for network-native token (ETH)
    /// @param tokenAmount Amount of tokens to trade
    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    /// @dev   Add liquidity to trade against in pool (USDC)- needs to be modified to add liquidity to uniswap
    /// @param tokenAmount Amount of tokens to add
    /// @param ethAmount Amount of ETH to add
    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(0),
            block.timestamp
        );
    }

    /// @dev   Take all fees, if takeFee is true
    /// @param sender Address of token sender
    /// @param recipient Address of token receiver
    /// @param amount Total amount being transferred
    /// @param takeFee Boolean on taking the fee or not
    function _tokenTransfer(address sender, address recipient, uint256 amount, bool takeFee) private {
        if(!takeFee)
            removeAllFee();

        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferStandard(sender, recipient, amount);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }

        if(!takeFee)
            restoreAllFee();
    }

    /// @dev   Transfer the standard way and take taxes
    /// @param sender Address of token sender
    /// @param recipient Address of token receiver
    /// @param tAmount Total amount of tokens being transferred
    function _transferStandard(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    /// @dev   Transfer to exlcuded address- same logic as above, since it goes to the excluded addresses
    /// @param sender Address of token sender
    /// @param recipient Address of token receiver
    /// @param tAmount Total amount of tokens being transferred
    function _transferToExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    /// @dev   Transfer from exlcuded address- same logic as above, but opposite. Avoids fees from the excluded addresses
    /// @param sender Address of token sender
    /// @param recipient Address of token receiver
    /// @param tAmount Total amount of tokens being transferred
    function _transferFromExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    // function burn(address addr, uint amt) external { 
    //     // ensure only the vault can call this
    //     require(msg.sender == vault);
    //     // _burn(addr, amt);
    // }
    
    function unlock(Lock _lock) public onlyOwner {
      timelocks[_lock] = block.timestamp + _TIMELOCK;
    }

    function lock(Lock _lock) public onlyOwner {
      timelocks[_lock] = 0;
    }
}