pragma solidity ^0.6.7;

import "./uni/interfaces/IUniswapV2Pair.sol";

abstract contract AuctionHouseLike {
    function bids(uint) external view virtual returns (uint, uint, uint, uint, uint48, address, address);
    function buyCollateral(uint256 id, uint256 wad) external virtual;
    function liquidationEngine() view public virtual returns (LiquidationEngineLike);
    function collateralType() view public virtual returns (bytes32);
}

abstract contract SAFEEngineLike {
    mapping (bytes32 => mapping (address => uint256))  public tokenCollateral;  // [wad]
    function canModifySAFE(address, address) virtual public view returns (uint);
    function collateralTypes(bytes32) virtual public view returns (uint, uint, uint, uint, uint);
    function coinBalance(address) virtual public view returns (uint);
    function safes(bytes32, address) virtual public view returns (uint, uint);
    function modifySAFECollateralization(bytes32, address, address, address, int, int) virtual public;
    function approveSAFEModification(address) virtual public;
    function transferInternalCoins(address, address, uint) virtual public;
}

abstract contract CollateralJoinLike {
    function decimals() virtual public returns (uint);
    function collateral() virtual public returns (CollateralLike);
    function join(address, uint) virtual public payable;
    function exit(address, uint) virtual public;
}

abstract contract CoinJoinLike {
    function safeEngine() virtual public returns (SAFEEngineLike);
    function systemCoin() virtual public returns (CollateralLike);
    function join(address, uint) virtual public payable;
    function exit(address, uint) virtual public;
}

abstract contract CollateralLike {
    function approve(address, uint) virtual public;
    function transfer(address, uint) virtual public;
    function transferFrom(address, address, uint) virtual public;
    function deposit() virtual public payable;
    function withdraw(uint) virtual public;
    function balanceOf(address) virtual public view returns (uint);
}

abstract contract LiquidationEngineLike {
    mapping (bytes32 => mapping(address => address)) public chosenSAFESaviour;
    mapping (address => uint256) public safeSaviours;
    function liquidateSAFE(bytes32 collateralType, address safe) virtual external returns (uint256 auctionId);
    function safeEngine() view public virtual returns (SAFEEngineLike);
}

/// @title GEB Keeper Flash Proxy
/// @notice Trustless proxy to allow for bidding in auctions and liquidating Safes using FlashSwaps
// @notice Single collateral version, only ETH
contract GebKeeperFlashProxy {
    AuctionHouseLike        auctionHouse;
    SAFEEngineLike          safeEngine;
    CollateralLike          weth;
    CollateralLike          coin;
    CoinJoinLike            coinJoin;
    CoinJoinLike            ethJoin;
    IUniswapV2Pair          uniswapPair;
    LiquidationEngineLike   liquidationEngine;
    address payable         caller;
    bytes32 public          collateralType;

    // math aux functions
    function subtract(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "sub-overflow");
    }

    function wad(uint rad) internal pure returns (uint) {
        return rad / 10 ** 27;
    }

    /// @notice Constructor
    /// @param auctionHouseAddress address of the auction house
    /// @param wethAddress weth address
    /// @param systemCoinAddress system coin address
    /// @param uniswapPairAddress uniswap v2 pair address
    /// @param coinJoinAddress coinJoin address
    /// @param ethJoinAddress ethJoin address
    constructor(
        address auctionHouseAddress,
        address wethAddress,
        address systemCoinAddress,
        address uniswapPairAddress,
        address coinJoinAddress,
        address ethJoinAddress
    ) public {
        auctionHouse        = AuctionHouseLike(auctionHouseAddress);
        weth                = CollateralLike(wethAddress);
        coin                = CollateralLike(systemCoinAddress);
        uniswapPair         = IUniswapV2Pair(uniswapPairAddress);
        coinJoin            = CoinJoinLike(coinJoinAddress);
        ethJoin             = CoinJoinLike(ethJoinAddress);
        collateralType      = auctionHouse.collateralType();
        liquidationEngine   = auctionHouse.liquidationEngine();
        safeEngine          = liquidationEngine.safeEngine();

        safeEngine.approveSAFEModification(address(auctionHouse)); 
    }

    /// @notice liquidates an underwater safe and settles the auction right away
    /// @dev it will revert for protected safes (saviour), these need to be liquidated through liquidation engine
    /// @param safe SafeId
    /// @return auction auctionId;
    function liquidateAndSettleSAFE(address safe) public returns (uint auction) {
        if (liquidationEngine.safeSaviours(liquidationEngine.chosenSAFESaviour(collateralType, safe)) == 1) {
            require (liquidationEngine.chosenSAFESaviour(collateralType, safe) == address(0),
            "safe-is-protected.");
        }

        auction = liquidationEngine.liquidateSAFE(collateralType, safe);
        settleAuction(auction);
    }

    /// @notice Initiates a flashwap
    /// @param amount amount to borrow
    /// @param data callback date, it will call this contract with the data
    function _startSwap(uint amount, bytes memory data) internal {
        caller = msg.sender;

        uint amount0Out = address(coin) == uniswapPair.token0() ? amount : 0;
        uint amount1Out = address(coin) == uniswapPair.token1() ? amount : 0;

        uniswapPair.swap(amount0Out, amount1Out, address(this), data);
    }

    /// @notice Settle auction
    /// @param auctionId id of the auction to be settled
    function settleAuction(uint auctionId) public {
        (uint raisedAmount,,, uint amountToRaise, uint48 auctionDeadline,,) = auctionHouse.bids(auctionId);
        require(auctionDeadline > now, "auction-expired");
        uint amount = subtract(amountToRaise, raisedAmount);
        require(amount > 0, "auction-already-settled");

        bytes memory callbackData = abi.encodeWithSelector(this.bid.selector, auctionId, amount);

        _startSwap(wad(amount) + 1, callbackData);
    }

    /// @notice Settle auctions
    /// @param auctionIds ids of the auctions to be settled
    function settleAuction(uint[] memory auctionIds) public {
        (uint[] memory ids, uint[] memory bidAmounts, uint totalAmount) = getOpenAuctionsBidSizes(auctionIds);
        require(totalAmount > 0, "all auctions already settled");

        bytes memory callbackData = abi.encodeWithSelector(this.multipleBid.selector, ids, bidAmounts);

        _startSwap(totalAmount, callbackData);
    }

    /// @notice returns all open opprtunities from a provided auction list
    /// @param auctionIds auction Ids
    /// @return ids ids of active auctions;
    /// @return bidAmounts Rad amounts to be bidded;
    /// @return totalAmount Wad amount to be borrowed
    function getOpenAuctionsBidSizes(uint[] memory auctionIds) internal returns (uint[] memory, uint[] memory, uint) {
        uint48          auctionDeadline;
        uint            amountToRaise;
        uint            raisedAmount;
        uint            amountAvailable;
        uint            totalAmount;
        uint            opportunityCount;
        uint[] memory   ids = new uint[](auctionIds.length);
        uint[] memory   bidAmounts = new uint[](auctionIds.length);

        for (uint i = 0; i < auctionIds.length; i++) {
            (raisedAmount,,, amountToRaise, auctionDeadline,,) = auctionHouse.bids(auctionIds[i]);
            amountAvailable = subtract(amountToRaise, raisedAmount);
            if ( amountAvailable > 0 && auctionDeadline > now) {
                totalAmount += wad(amountAvailable) + 1;
                ids[opportunityCount] = auctionIds[i];
                bidAmounts[opportunityCount] = amountAvailable;
                opportunityCount++;
            }            
        }

        assembly { 
            mstore(ids, opportunityCount) 
            mstore(bidAmounts, opportunityCount)
        }
        return(ids, bidAmounts, totalAmount);
    }

    /// @notice callback from Uniswap, funds in hands
    /// @param _sender sender of the flashswap, should be address (this)
    /// @param _amount0 amount of token0
    /// @param _amount1 amount of token1
    /// @param _data data sent back from uniswap
    function uniswapV2Call(address _sender, uint _amount0, uint _amount1, bytes calldata _data) external {
        require(_sender == address(this), "invalid sender");
        require(msg.sender == address(uniswapPair), "invalid uniswap pair");

        // join COIN
        uint amount = (_amount0 == 0 ? _amount1 : _amount0);
        coin.approve(address(coinJoin), amount);
        coinJoin.join(address(this), amount);

        // bid
        (bool success, ) = address(this).call(_data);
        require(success, "failed bidding");

        // exit WETH
        ethJoin.exit(address(this), safeEngine.tokenCollateral(collateralType, address(this)));

        // repay loan
        uint pairBalanceTokenBorrow = coin.balanceOf(address(uniswapPair));
        uint pairBalanceTokenPay = weth.balanceOf(address(uniswapPair));
        uint amountToRepay = ((1000 * pairBalanceTokenPay * amount) / (997 * pairBalanceTokenBorrow)) + 1;
        require(amountToRepay <= weth.balanceOf(address(this)), "profit not enough to repay the flashswap");
        weth.transfer(address(uniswapPair), amountToRepay);
        
        // // send profit back
        uint profit = weth.balanceOf(address(this));
        weth.withdraw(profit);
        caller.call{value: profit}("");
        caller = address(0x0);
    }    

    /// @notice bids in a single auction
    /// @param auctionId auction Id
    /// @param amount amount to bid
    function bid(uint auctionId, uint amount) external {
        require(msg.sender == address(this), "only self");
        auctionHouse.buyCollateral(auctionId, amount);
    }

    /// @notice bids in multiple auctions
    /// @param auctionIds auction Ids
    /// @param amounts amounts to bid
    function multipleBid(uint[] calldata auctionIds, uint[] calldata amounts) external {
        require(msg.sender == address(this), "only self");
        for (uint i = 0; i < auctionIds.length; i++) {
            auctionHouse.buyCollateral(auctionIds[i], amounts[i]);
        }
    }

    receive() external payable {
        require(msg.sender == address(weth), "only weth withdrawals allowed");
    }
}
