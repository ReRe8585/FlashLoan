// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
import {FlashLoanSimpleReceiverBase} from "https://github.com/aave/aave-v3-core/blob/master/contracts/flashloan/base/FlashLoanSimpleReceiverBase.sol";
import {IPoolAddressesProvider} from "https://github.com/aave/aave-v3-core/blob/master/contracts/interfaces/IPoolAddressesProvider.sol";
import {IERC20} from "https://github.com/aave/aave-v3-core/blob/master/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import { SafeMath } from "https://github.com/aave/aave-v3-core/contracts/dependencies/openzeppelin/contracts/SafeMath.sol";

// ----------------------INTERFACE------------------------------
// Uniswap
// Some helper function, it is totally fine if you can finish the lab without using these functions
interface IUniswapV2Router {

    function getAmountsOut(uint amountIn, address[] memory path) external view returns (uint[] memory amounts);

    function getAmountsIn(uint amountOut, address[] memory path) external view returns (uint[] memory amounts);

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactTokensForETH(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external ;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns
     (uint amountToken, uint amountETH, uint liquidity);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (
      uint amountA, uint amountB, uint liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);

}

interface IUniswapV2Pair {
  function token0() external view returns (address);

  function token1() external view returns (address);

  function getReserves()
    external
    view
    returns (
      uint112 reserve0,
      uint112 reserve1,
      uint32 blockTimestampLast
    );

  function swap(
    uint amount0Out,
    uint amount1Out,
    address to,
    bytes calldata data
  ) external;
}

interface IUniswapV2Factory {
  function getPair(address token0, address token1) external view returns (address);
}

// ----------------------IMPLEMENTATION------------------------------
contract FlashloanV3 is FlashLoanSimpleReceiverBase {

    address public constant Uniswap_Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant DAI = 0xDF1742fE5b0bFc12331D8EAec6b478DfDbD31464;
    address public constant MTA = 0xE68f8ca368F9aC387634ad04654Da239F7DB6b96;
    address public constant MTB = 0xCA82465D445BD0528C95073e0195c19De8934663;
    address payable owner;

    using SafeMath for uint256;

    constructor(address _addressProvider)
      FlashLoanSimpleReceiverBase(IPoolAddressesProvider(_addressProvider)){
      owner = payable(msg.sender);
    }

    /**
     * Allows users to access liquidity of one reserve or one transaction as long as the amount taken plus fee is returned.
     * @param _asset The address of the asset you want to borrow
     * @param _amount The borrow amount
     **/
    // Doc: https://docs.aave.com/developers/core-contracts/pool#flashloansimple
    function RequestFlashLoan(address _asset, uint256 _amount) public {
        address receiverAddress = address(this);
        address asset = _asset;
        uint256 amount = _amount;
        bytes memory params = "";
        uint16 referralCode = 0;

        // POOL comes from FlashLoanSimpleReceiverBase
        POOL.flashLoanSimple(
            receiverAddress,
            asset,
            amount,
            params,
            referralCode
        );
    }

    /**
     * This function is called after your contract has received the flash loaned amount
     * @param asset The address of the asset you want to borrow
     * @param amount The borrow amount
     * @param premium The borrow fee
     * @param initiator The address initiates this function
     * @param params Arbitrary bytes-encoded params passed from flash loan
     * @return  true or false
     **/
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    )
        external
        override
        returns (bool)
    {
        address[] memory pair = new address[](2);
        uint[] memory output = new uint[](2);

        pair[0] = DAI;
        pair[1] = MTA;
        output = IUniswapV2Router(Uniswap_Router).getAmountsOut(amount, pair);
        uint balance_MTA = output[1];
        this.swap(amount, balance_MTA, pair);

 
        pair[0] = MTA;
        pair[1] = MTB;
        output = IUniswapV2Router(Uniswap_Router).getAmountsOut(balance_MTA, pair);
        uint balance_MTB = output[1];
        this.swap(balance_MTA, balance_MTB, pair);
        

        pair[0] = MTB;
        pair[1] = DAI;
        output = IUniswapV2Router(Uniswap_Router).getAmountsOut(balance_MTB, pair);
        this.swap(balance_MTB, output[1], pair);

        uint256 amount_to_payback = amount + premium; 
        IERC20(asset).approve(address(POOL), amount_to_payback);
        
        return true;
    }
    function swap(uint input, uint output, address[] memory array) public {

        IERC20(array[0]).approve(address(Uniswap_Router), input);
        IUniswapV2Router(Uniswap_Router).swapExactTokensForTokens(input, output, array, msg.sender, block.timestamp);
    
    }

    function getBalance(address _tokenAddress) external view returns (uint256) {
        return IERC20(_tokenAddress).balanceOf(address(this));
    }

    function withdraw(address _tokenAddress) external onlyOwner {
        IERC20 token = IERC20(_tokenAddress);
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "Only the contract owner can call this function"
        );
        _;
    }

    receive() external payable {}

}
