pragma solidity ^0.6.7;

import "./uni/v3/interfaces/IUniswapV3Pool.sol";

abstract contract AuctionHouseLike {
    function bids(uint256) virtual external view returns (uint, uint);
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
    function chosenSAFESaviour(bytes32, address) virtual public view returns (address);
    function safeSaviours(address) virtual public view returns (uint256);
    function liquidateSAFE(bytes32 collateralType, address safe) virtual external returns (uint256 auctionId);
    function safeEngine() view public virtual returns (SAFEEngineLike);
}

/// @title GEB Keeper Flash Proxy
/// @notice Trustless proxy that facilitates SAFE liquidation and bidding in auctions using Uniswap V3 flashswaps
/// @notice Single collateral version, only meant to work with ETH collateral types
contract GebUniswapV3KeeperFlashProxyETH {
    AuctionHouseLike       public auctionHouse;
    SAFEEngineLike         public safeEngine;
    CollateralLike         public weth;
    CollateralLike         public coin;
    CoinJoinLike           public coinJoin;
    CoinJoinLike           public ethJoin;
    IUniswapV3Pool         public uniswapPair;
    LiquidationEngineLike  public liquidationEngine;
    address payable        public caller;
    bytes32                public collateralType;

    uint256 public   constant ZERO           = 0;
    uint256 public   constant ONE            = 1;
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    /// @notice Constructor
    /// @param auctionHouseAddress Address of the auction house
    /// @param wethAddress WETH address
    /// @param systemCoinAddress System coin address
    /// @param uniswapPairAddress Uniswap V3 pair address
    /// @param coinJoinAddress CoinJoin address
    /// @param ethJoinAddress ETHJoin address
    constructor(
        address auctionHouseAddress,
        address wethAddress,
        address systemCoinAddress,
        address uniswapPairAddress,
        address coinJoinAddress,
        address ethJoinAddress
    ) public {
        require(auctionHouseAddress != address(0), "GebUniswapV3KeeperFlashProxyETH/null-auction-house");
        require(wethAddress != address(0), "GebUniswapV3KeeperFlashProxyETH/null-weth");
        require(systemCoinAddress != address(0), "GebUniswapV3KeeperFlashProxyETH/null-system-coin");
        require(uniswapPairAddress != address(0), "GebUniswapV3KeeperFlashProxyETH/null-uniswap-pair");
        require(coinJoinAddress != address(0), "GebUniswapV3KeeperFlashProxyETH/null-coin-join");
        require(ethJoinAddress != address(0), "GebUniswapV3KeeperFlashProxyETH/null-eth-join");

        auctionHouse        = AuctionHouseLike(auctionHouseAddress);
        weth                = CollateralLike(wethAddress);
        coin                = CollateralLike(systemCoinAddress);
        uniswapPair         = IUniswapV3Pool(uniswapPairAddress);
        coinJoin            = CoinJoinLike(coinJoinAddress);
        ethJoin             = CoinJoinLike(ethJoinAddress);
        collateralType      = auctionHouse.collateralType();
        liquidationEngine   = auctionHouse.liquidationEngine();
        safeEngine          = liquidationEngine.safeEngine();

        safeEngine.approveSAFEModification(address(auctionHouse));
    }

    // --- Math ---
    function addition(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "GebUniswapV3KeeperFlashProxyETH/add-overflow");
    }
    function subtract(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "GebUniswapV3KeeperFlashProxyETH/sub-underflow");
    }
    function multiply(uint x, uint y) internal pure returns (uint z) {
        require(y == ZERO || (z = x * y) / y == x, "GebUniswapV3KeeperFlashProxyETH/mul-overflow");
    }
    function wad(uint rad) internal pure returns (uint) {
        return rad / 10 ** 27;
    }

    // --- External Utils ---
    /// @notice Bids in a single auction
    /// @param auctionId Auction Id
    /// @param amount Amount to bid
    function bid(uint auctionId, uint amount) external {
        require(msg.sender == address(this), "GebUniswapV3KeeperFlashProxyETH/only-self");
        auctionHouse.buyCollateral(auctionId, amount);
    }
    /// @notice Bids in multiple auctions atomically
    /// @param auctionIds Auction IDs
    /// @param amounts Amounts to bid
    function multipleBid(uint[] calldata auctionIds, uint[] calldata amounts) external {
        require(msg.sender == address(this), "GebUniswapV3KeeperFlashProxyETH/only-self");
        for (uint i = ZERO; i < auctionIds.length; i++) {
            auctionHouse.buyCollateral(auctionIds[i], amounts[i]);
        }
    }
    /// @notice Called to `msg.sender` after executing a swap via IUniswapV3Pool#swap.
    /// @dev In the implementation you must pay the pool tokens owed for the swap.
    /// The caller of this method must be checked to be a UniswapV3Pool deployed by the canonical UniswapV3Factory.
    /// amount0Delta and amount1Delta can both be 0 if no tokens were swapped.
    /// @param _amount0 The amount of token0 that was sent (negative) or must be received (positive) by the pool by
    /// the end of the swap. If positive, the callback must send that amount of token0 to the pool.
    /// @param _amount1 The amount of token1 that was sent (negative) or must be received (positive) by the pool by
    /// the end of the swap. If positive, the callback must send that amount of token1 to the pool.
    /// @param _data Any data passed through by the caller via the IUniswapV3PoolActions#swap call
    function uniswapV3SwapCallback(int256 _amount0, int256 _amount1, bytes calldata _data) external {
        require(msg.sender == address(uniswapPair), "GebUniswapV3KeeperFlashProxyETH/invalid-uniswap-pair");

        // join COIN
        uint amount = coin.balanceOf(address(this));
        coin.approve(address(coinJoin), amount);
        coinJoin.join(address(this), amount);

        // bid
        (bool success, ) = address(this).call(_data);
        require(success, "failed bidding");

        // exit WETH
        ethJoin.exit(address(this), safeEngine.tokenCollateral(collateralType, address(this)));

        // repay loan
        uint amountToRepay = _amount0 > int(ZERO) ? uint(_amount0) : uint(_amount1);
        weth.transfer(address(uniswapPair), amountToRepay);

        // send profit back
        uint profit = weth.balanceOf(address(this));
        weth.withdraw(profit);
        caller.call{value: profit}("");
        caller = address(0x0);
    }

    // --- Internal Utils ---
    /// @notice Initiates a flashwap
    /// @param amount Amount to borrow
    /// @param data Callback date, it will call this contract with the data
    function _startSwap(uint amount, bytes memory data) internal {
        caller = msg.sender;

        bool zeroForOne = address(coin) == uniswapPair.token1() ? true : false;
        uint160 sqrtLimitPrice = zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1;

        uniswapPair.swap(address(this), zeroForOne, int256(amount) * -1, sqrtLimitPrice, data);
    }
    /// @notice Returns all available opportunities from a provided auction list
    /// @param auctionIds Auction IDs
    /// @return ids IDs of active auctions
    /// @return bidAmounts Rad amounts still requested by auctions
    /// @return totalAmount Wad amount to be borrowed
    function _getOpenAuctionsBidSizes(uint[] memory auctionIds) internal view returns (uint[] memory, uint[] memory, uint) {
        uint            amountToRaise;
        uint            totalAmount;
        uint            opportunityCount;

        uint[] memory   ids = new uint[](auctionIds.length);
        uint[] memory   bidAmounts = new uint[](auctionIds.length);

        for (uint i = ZERO; i < auctionIds.length; i++) {
            (, amountToRaise) = auctionHouse.bids(auctionIds[i]);

            if (amountToRaise > ZERO) {
                totalAmount                  = addition(totalAmount, addition(wad(amountToRaise), ONE));
                ids[opportunityCount]        = auctionIds[i];
                bidAmounts[opportunityCount] = amountToRaise;
                opportunityCount++;
            }
        }

        assembly {
            mstore(ids, opportunityCount)
            mstore(bidAmounts, opportunityCount)
        }

        return(ids, bidAmounts, totalAmount);
    }

    // --- Core Bidding and Settling Logic ---
    /// @notice Liquidates an underwater safe and settles the auction right away
    /// @dev It will revert for protected SAFEs (those that have saviours). Protected SAFEs need to be liquidated through the LiquidationEngine
    /// @param safe A SAFE's ID
    /// @return auction The auction ID
    function liquidateAndSettleSAFE(address safe) public returns (uint auction) {
        if (liquidationEngine.safeSaviours(liquidationEngine.chosenSAFESaviour(collateralType, safe)) == 1) {
            require (liquidationEngine.chosenSAFESaviour(collateralType, safe) == address(0),
            "safe-is-protected.");
        }

        auction = liquidationEngine.liquidateSAFE(collateralType, safe);
        settleAuction(auction);
    }
    /// @notice Settle auction
    /// @param auctionId ID of the auction to be settled
    function settleAuction(uint auctionId) public {
        (, uint amountToRaise) = auctionHouse.bids(auctionId);
        require(amountToRaise > ZERO, "GebUniswapV3KeeperFlashProxyETH/auction-already-settled");

        bytes memory callbackData = abi.encodeWithSelector(this.bid.selector, auctionId, amountToRaise);

        _startSwap(addition(wad(amountToRaise), ONE), callbackData);
    }
    /// @notice Settle auctions
    /// @param auctionIds IDs of the auctions to be settled
    function settleAuction(uint[] memory auctionIds) public {
        (uint[] memory ids, uint[] memory bidAmounts, uint totalAmount) = _getOpenAuctionsBidSizes(auctionIds);
        require(totalAmount > ZERO, "GebUniswapV3KeeperFlashProxyETH/all-auctions-already-settled");

        bytes memory callbackData = abi.encodeWithSelector(this.multipleBid.selector, ids, bidAmounts);

        _startSwap(totalAmount, callbackData);
    }

    // --- Fallback ---
    receive() external payable {
        require(msg.sender == address(weth), "GebUniswapV3KeeperFlashProxyETH/only-weth-withdrawals-allowed");
    }
}
