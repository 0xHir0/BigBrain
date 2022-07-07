// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "./Ownable.sol";
import './IERC20.sol';
import './SafeERC20.sol';

contract USDCVault is Ownable {
    
    address public tokenAddress;
    bool reEntrancyMutex = false;

    event Withdraw(address userWallet, uint256 amount);

    constructor(address _tokenAddress) {
        tokenAddress = _tokenAddress;
    }

    modifier onlyContract {
        if (msg.sender != tokenAddress) revert();
        _;
    }

    /// @dev USDC mainnet address: 0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48
    /// @dev USDC testnet address: 0xeb8f08a975ab53e34d8a0330e0d34de942c95926
    function getUSDCBalance(address usdc) public view returns (uint256) {
        return IERC20(usdc).balanceOf(address(this));
    }
    
    /// @dev Function that the token contract calls to deposit USDC into the vault
    /// @param amount The amount of USDC to deposit
    function deposit(uint256 amount) public onlyContract {
        require(msg.sender == tokenAddress, "Only the deployed token contract can deposit funds");

        /// @notice transfer from the user to the contract- cross-contract call
        SafeERC20.safeTransferFrom(IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48), msg.sender, address(this), amount);
    }

    /// @dev Calculate the user rewards using the formula in the whitepaper
    /// @param amount Amount of tokens they want to withdraw
    function calculateUserRewards(uint256 amount) internal view returns (uint256) {
        uint256 totalContractTokenSupply = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48).balanceOf(address(this));
        
        /// @notice This is a filler- the oracle logic will be used in here to calculate the actual dollar rewards ($price of token * totalContractTokenSupply) / overall user ownership 
        uint256 totalRewards = totalContractTokenSupply / amount;
       
        return totalRewards;
    }

    /// @notice We want to allow the owner to withdraw everything if he chooses to do so- this does open up a lot of security vulnerabilities
    /// @param amount Amount of token that the user wants to withdraw
    /// @notice need reentrancy guard to prevent someone from calling this function multiple times 
    function withdrawUserRewards(uint256 amount) payable external {
        uint256 contractBalance = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48).balanceOf(address(this));
        require(amount <= contractBalance);

        // transfer from contract balance to user
        uint256 userRewards = calculateUserRewards(amount);

        // burn the BigBrain token- call the BigBrain burn function from here
        //  IERC20(tokenAddress).burn(msg.sender, amount);

        // transfer USDC from contract balance to user
        SafeERC20.safeTransferFrom(IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48), address(this), msg.sender, userRewards);
        
        emit Withdraw(msg.sender, amount);
    }

    function setTokenAddress(address _tokenAddress) public onlyOwner {
        tokenAddress = _tokenAddress;
    }
}