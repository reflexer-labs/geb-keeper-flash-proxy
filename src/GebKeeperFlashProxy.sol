pragma solidity ^0.6.7;

import "./uni/interfaces/IUniswapV2Pair.sol";

contract AuctionHouseLike {
    struct Bid {
        // System coins raised up until now
        uint256 raisedAmount;                                                                                         // [rad]
        // Amount of collateral that has been sold up until now
        uint256 soldAmount;                                                                                           // [wad]
        // How much collateral is sold in an auction
        uint256 amountToSell;                                                                                         // [wad]
        // Total/max amount of coins to raise
        uint256 amountToRaise;                                                                                        // [rad]
        // Duration of time after which the auction can be settled
        uint48  auctionDeadline;                                                                                      // [unix epoch time]
        // Who (which SAFE) receives leftover collateral that is not sold in the auction; usually the liquidated SAFE
        address forgoneCollateralReceiver;
        // Who receives the coins raised from the auction; usually the accounting engine
        address auctionIncomeRecipient;
    }

    // Bid data for each separate auction
    mapping (uint256 => Bid) public bids;

    /**
     * @notice Buy collateral from an auction at a fixed discount
     * @param id ID of the auction to buy collateral from
     * @param wad New bid submitted (as a WAD which has 18 decimals)
     */
    function buyCollateral(uint256 id, uint256 wad) external;

    // uint256 remainingToRaise = subtract(bids[id].amountToRaise, bids[id].raisedAmount);
}

abstract contract WethLike {
    function balanceOf(address) virtual public view returns (uint);
    function approve(address, uint) virtual public;
    function transfer(address, uint) virtual public;
    function transferFrom(address, address, uint) virtual public;
    function deposit() virtual public payable;
    function withdraw(uint) virtual public;
}

abstract contract DSTokenLike {
    function balanceOf(address) virtual public view returns (uint);
    function approve(address, uint) virtual public;
    function transfer(address, uint) virtual public;
    function transferFrom(address, address, uint) virtual public;
}

/// trustless proxy to settle auctions using funds from a flashSwap
/// works only with Eth as collateral for now
contract GebKeeperFlashProxy {
    AuctionHouseLike auctionHouse;
    WethLike weth;
    DSTokenLike coin;
    IUniswapV2Pair uniswapPair;

    function subtract(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "sub-overflow");
    }

    function wad(uint rad_) internal pure returns (uint) {
        return rad_ / 10 ** 27;
    }

    constructor(
        address auctionHouseAddress,
        address wethAddress,
        address systemCoinAddress,
        address uniswapPairAddress
    ) public {
        auctionHouse = AuctionHouseLike(auctionHouseAddress);
        weth = WethLike(wethAddress);
        coin = DSTokenLike(systemCoinAddress);
        uniswapPair = IUniswapV2Pair(uniswapPairAddress);
    }

    function settleAuction(uint auctionId) public {
        (uint raisedAmount,,, uint amountToRaise, uint48 auctionDeadline,,) = auctionHouse.bids(auctionId);
        require(auctionDeadline > now, "auction-expired");
        uint amount = subtract(amountToRaise, raisedAmount);
        require(amount > 0, "auction-already-settled");

        bytes memory callbackData = abi.encodeWithSelector(this.bid.selector, auctionId, amount);

        uint amount0Out = address(coin) == IUniswapV2Pair(uniswapPair).token0() ? wad(amount) : 0;
        uint amount1Out = address(coin) == IUniswapV2Pair(uniswapPair).token1() ? wad(amount) : 0;

        // flashloan amount
        uniswapPair.swap(amount0Out, amount1Out, address(this), callbackData);
    }

    function uniswapV2Call(address _sender, uint _amount0, uint _amount1, bytes calldata _data) external {
        require(_sender == address(this), "invalid sender");
        require(msg.sender == uniswapPair, "invalid uniswap pair");

        // calling bid
        address(this).call(_data);

        // repay loan
        uint pairBalanceTokenBorrow = coin.balanceOf(address(uniswapPair));
        uint pairBalanceTokenPay = weth.balanceOf(address(uniswapPair));
        uint amountToRepay = ((1000 * pairBalanceTokenPay * (_amount0 == 0) ? _amount1 : _amount0) / (997 * pairBalanceTokenBorrow)) + 1;

        weth.deposit{value: amountToRepay}();
        weth.transfer(uniswapPair, amountToRepay);
        
        // send leftover eth back to msg.origin for now
        tx.origin.call{value: address(this).balance}();

    }    

    function bid(uint auctionId, uint amount) {
        require(msg.sender == address(this), "only-self");
        auctionHouse.buyCollateral(auctionId, amount);
    }
}
