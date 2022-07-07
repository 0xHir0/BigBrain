// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

// import "@openzeppelin/token/ERC20/ERC20.sol";
// import "@openzeppelin/access/Ownable.sol";
// // import "https://github.com/Uniswap/uniswap-v3-periphery/blob/main/contracts/interfaces/ISwapRouter.sol";

// // contract BigbrainToken is ERC20, Ownable, ISwapRouter {
// contract Bigbrain is ERC20, Ownable {
//     address teamWallet;
//     address liquidityWallet; /// @notice this will be replaced with the liquidity pool logic, this is just filler for testing
//     uint8 public baseMod = 100;
//     uint8 public liquidityFee = 3;
//     uint8 public collateralFee = 8;
//     uint8 public teamFee = 1;
//     bool public isTaxOn = true;
//     uint32 public maxTxAmount = 20000000;

//     // IUniswapRouter public constant uniswapRouter = IUniswapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
//     // address usdcAddress = 0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48;
//     address usdcAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

//     mapping(address => bool) public isExcluded;

//     event DebugUint(string, uint256);
//     event DebugAddress(string, address);

//     constructor(string memory name, string memory symbol, address _teamWallet) ERC20(name, symbol) {
//         _mint(msg.sender, 1000000000);
//         teamWallet = _teamWallet;
//     }

//     function toggleTax() public onlyOwner {
//         isTaxOn = !isTaxOn;
//     }

//     // function transfer(recipient, amount) override;

//     /// @dev Custom _transfer() function to handle taxes. This is called from the normal, inherited transfer() function in ERC20.sol
//     /// @param from Address the funds are transferred from
//     /// @param to Address the funds are transferred to
//     /// @param amount The amount of funds transferred
//     function _transfer(address from, address to, uint256 amount) internal override {
//         // from = msg.sender from transfer()
//         emit DebugAddress("from", from);
//         emit DebugAddress("to", to);
//         emit DebugUint("amount", amount);
//         emit DebugUint("msg.value", msg.value);

//         uint256 contractTokenBalance = balanceOf(address(this));
//         _tokenTransfer(from, to, amount, isTaxOn);
//     }

//     function _tokenTransfer(address from, address to, uint256 amount, bool takeFee) private {
//         if (!isTaxOn) {
//             // transfer normally
//             emit DebugUint("address(this.balance)", address(this).balance);
//             emit DebugAddress("from", from);
//             emit DebugAddress("to", to);
//             payable(from).transfer(amount);
            
//         } 
//     }

//     // function _transfer(address from, address to, uint256 amount) public override returns (bool) {
//     // function _transfer(address from, address to, uint256 amount) public override returns (bool) {
//     //     require(from != address(0), "ERC20: transfer from the zero address");
//     //     require(to != address(0), "ERC20: transfer to the zero address");
//     //     require(amount > 0, "Transfer amount must be greater than zero");
//     //     require(from != to, "ERC20: transfer from and to addresses must be different");
//     //     require(amount <= maxTxAmount, "Transfer amount exceeds the maxTxAmount.");

//     //     _transferToken(from, to, amount, isTaxOn);
//     // }

//     function _takeTeam(uint16 tTeam) private {
//         if (tTeam == 0) return;
//         _transfer(msg.sender, teamWallet, tTeam);
//     }

//     function _transferToken(address from, address to, uint256 amount, bool tax) public returns (bool) {
//         if (tax) {
//             // take out LP tax
//             uint256 liquidityAmount = amount * (liquidityFee / 100);
//             payable(address(this)).transfer(liquidityAmount);
//             // payable(beneficiary).transfer(address(this).balance); // sending contract balance to someone
//             // take out collateral tax
//             uint256 collateralAmount = amount * (collateralFee / 100);
//             // take out fee3
//             uint256 teamAmount = amount * (teamFee / 100);
//             // finally transfer to the buyer/seller
//             payable(from).transfer(amount - liquidityAmount - collateralAmount - teamAmount);
//         } else {
//             // transfer to the buyer/seller without a tax
//             // how does a transfer work from first principles
//             payable(to).transfer(amount);
//         }
//         return true;
//     }

//     /// @dev Take a 3% tax and return it to the liquidity pool
//     /// @notice This function will be different than the other tax ones
//     function takeLiquidity(uint256 amount) internal {
//         if (amount == 0) return;
//         // needs to come from the transfer amount
//         payable(address(this)).transfer(amount);
//         _transfer(msg.sender, liquidityWallet, amount);
//     }

//     /// @dev Take the 8% collateralization tax for the vault
//     /// @notice Will need to add the USDC swap before depositing
//     function takeCollateral(uint256 amount) internal {
//         if (amount == 0) return;
//         _transfer(msg.sender, address(this), amount);
//     }   

//     /// @dev Take the 1% tax for the team
//     function takeTeam(uint256 amount) internal {
//         if (amount == 0) return;
//         _transfer(msg.sender, teamWallet, amount);
//     }

//     // function convertExactEthToUsdc() external payable {
//     //     require(msg.value > 0, "Must pass non 0 ETH amount");
//     //     uint256 deadline = block.timestamp + 15; // using 'now' for convenience, for mainnet pass deadline from frontend!
//     //     address tokenIn = WETH9;
//     //     address tokenOut = usdcAddress;
//     //     uint24 fee = 3000;
//     //     address recipient = msg.sender; // need to change this to be called by our contract?
//     //     uint256 amountIn = msg.value;
//     //     uint256 amountOutMinimum = 1;
//     //     uint160 sqrtPriceLimitX96 = 0;

//     //     ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams(
//     //         tokenIn,
//     //         tokenOut,
//     //         fee,
//     //         recipient,
//     //         deadline,
//     //         amountIn,
//     //         amountOutMinimum,
//     //         sqrtPriceLimitX96
//     //     );
//     //     uniswapRouter.exactInputSingle{value: msg.value}(params);
//     //     // uniswapRouter.refundETH(); not sure if we need this, it returns all ETH in the contract
    
//     //     // refund leftover ETH to user
//     //     (bool success,) = msg.sender.call{ value: address(this).balance }("");
//     //     require(success, "refund failed");
//     // }
// }
