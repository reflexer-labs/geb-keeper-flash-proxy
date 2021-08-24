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

abstract contract JoinLike {
    function safeEngine() virtual public returns (SAFEEngineLike);
    function systemCoin() virtual public returns (CollateralLike);
    function collateral() virtual public returns (CollateralLike);
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

/// @title GEB Multi Hop Keeper Flash Proxy
/// @notice Trustless proxy that facilitates SAFE liquidation and bidding in auctions using Uniswap V3 flashswaps. This contract bids in auctions using multiple pools e.g RAI/USDC + USDC/ETH
/// @notice Uniswap pairs and WETH are trusted contracts, use only against UniV3 pools and weth9
contract GebUniswapV3MultiHopKeeperFlashProxy {
    AuctionHouseLike       public auctionHouse;
    SAFEEngineLike         public safeEngine;
    CollateralLike         public weth;
    CollateralLike         public coin;
    JoinLike           public coinJoin;
    JoinLike           public collateralJoin;
    LiquidationEngineLike  public liquidationEngine;
    // Coin pair (i.e: RAI/XYZ)
    IUniswapV3Pool         public uniswapPair;
    // Pair used to swap non system coin token to ETH, (i.e: XYZ/ETH)
    IUniswapV3Pool         public auxiliaryUniPair;
    bytes32                public collateralType;

    uint256 public   constant ZERO           = 0;
    uint256 public   constant ONE            = 1;
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    /// @notice Constructor
    /// @param auctionHouseAddress Address of the auction house
    /// @param wethAddress WETH address
    /// @param systemCoinAddress System coin address
    /// @param uniswapPairAddress Uniswap V3 pair address (i.e: coin/token)
    /// @param auxiliaryUniswapPairAddress Auxiliary Uniswap V3 pair address (i.e: token/ETH)
    /// @param coinJoinAddress CoinJoin address
    /// @param collateralJoinAddress collateralJoin address
    constructor(
        address auctionHouseAddress,
        address wethAddress,
        address systemCoinAddress,
        address uniswapPairAddress,
        address auxiliaryUniswapPairAddress,
        address coinJoinAddress,
        address collateralJoinAddress
    ) public {
        require(auctionHouseAddress != address(0), "GebUniswapV3MultiHopKeeperFlashProxy/null-auction-house");
        require(wethAddress != address(0), "GebUniswapV3MultiHopKeeperFlashProxy/null-weth");
        require(systemCoinAddress != address(0), "GebUniswapV3MultiHopKeeperFlashProxy/null-system-coin");
        require(uniswapPairAddress != address(0), "GebUniswapV3MultiHopKeeperFlashProxy/null-uniswap-pair");
        require(auxiliaryUniswapPairAddress != address(0), "GebUniswapV3MultiHopKeeperFlashProxy/null-uniswap-pair");
        require(coinJoinAddress != address(0), "GebUniswapV3MultiHopKeeperFlashProxy/null-coin-join");
        require(collateralJoinAddress != address(0), "GebUniswapV3MultiHopKeeperFlashProxy/null-eth-join");

        auctionHouse        = AuctionHouseLike(auctionHouseAddress);
        weth                = CollateralLike(wethAddress);
        coin                = CollateralLike(systemCoinAddress);
        uniswapPair         = IUniswapV3Pool(uniswapPairAddress);
        auxiliaryUniPair    = IUniswapV3Pool(auxiliaryUniswapPairAddress);
        coinJoin            = JoinLike(coinJoinAddress);
        collateralJoin             = JoinLike(collateralJoinAddress);
        collateralType      = auctionHouse.collateralType();
        liquidationEngine   = auctionHouse.liquidationEngine();
        safeEngine          = liquidationEngine.safeEngine();

        safeEngine.approveSAFEModification(address(auctionHouse));
    }

    // --- Math ---
    function addition(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "GebUniswapV3MultiHopKeeperFlashProxy/add-overflow");
    }
    function subtract(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "GebUniswapV3MultiHopKeeperFlashProxy/sub-underflow");
    }
    function multiply(uint x, uint y) internal pure returns (uint z) {
        require(y == ZERO || (z = x * y) / y == x, "GebUniswapV3MultiHopKeeperFlashProxy/mul-overflow");
    }
    function wad(uint rad) internal pure returns (uint) {
        return rad / 10 ** 27;
    }

    // --- External Utils ---
    /// @notice Bids in a single auction
    /// @param auctionId Auction Id
    /// @param amount Amount to bid
    function bid(uint auctionId, uint amount) external {
        require(msg.sender == address(this), "GebUniswapV3MultiHopKeeperFlashProxy/only-self");
        auctionHouse.buyCollateral(auctionId, amount);
    }
    /// @notice Bids in multiple auctions atomically
    /// @param auctionIds Auction IDs
    /// @param amounts Amounts to bid
    function multipleBid(uint[] calldata auctionIds, uint[] calldata amounts) external {
        require(msg.sender == address(this), "GebUniswapV3MultiHopKeeperFlashProxy/only-self");
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
        require(msg.sender == address(uniswapPair) || msg.sender == address(auxiliaryUniPair), "GebUniswapV3MultiHopKeeperFlashProxy/invalid-uniswap-pair");

        uint amountToRepay = _amount0 > int(ZERO) ? uint(_amount0) : uint(_amount1);
        IUniswapV3Pool pool = IUniswapV3Pool(msg.sender);
        CollateralLike tokenToRepay = _amount0 > int(ZERO) ? CollateralLike(pool.token0()) : CollateralLike(pool.token1());

        if (msg.sender == address(uniswapPair)) { // flashswap
            // join COIN
            uint amount = coin.balanceOf(address(this));
            coin.approve(address(coinJoin), amount);
            coinJoin.join(address(this), amount);

            (uint160 sqrtLimitPrice, bytes memory data) = abi.decode(_data, (uint160, bytes));

            // bid
            (bool success, ) = address(this).call(data);
            require(success, "failed bidding");

            // exit WETH
            collateralJoin.exit(address(this), safeEngine.tokenCollateral(collateralType, address(this)));

            // swap secondary secondary weth for exact amount of secondary token
            _startSwap(auxiliaryUniPair, address(tokenToRepay) == auxiliaryUniPair.token1(), amountToRepay, sqrtLimitPrice, "");
        }
        // pay for swap
        tokenToRepay.transfer(msg.sender, amountToRepay);
    }

    // --- Internal Utils ---
    /// @notice Initiates a (flash)swap
    /// @param pool Pool in wich to perform the swap
    /// @param zeroForOne Direction of the swap
    /// @param amount Amount to borrow
    /// @param data Callback data, it will call this contract with the raw data
    function _startSwap(IUniswapV3Pool pool, bool zeroForOne, uint amount, uint160 sqrtLimitPrice, bytes memory data) internal {
        if (sqrtLimitPrice == 0)
            sqrtLimitPrice = zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1;

        pool.swap(address(this), zeroForOne, int256(amount) * -1, sqrtLimitPrice, data);
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
    /// @notice Will send the profits back to caller
    function _payCaller() internal {
        CollateralLike collateral = collateralJoin.collateral();
        uint profit = collateral.balanceOf(address(this));

        if (address(collateral) == address(weth)) {
            weth.withdraw(profit);
            msg.sender.call{value: profit}("");
        } else
            collateral.transfer(msg.sender, profit);
    }

    // --- Core Bidding and Settling Logic ---
    /// @notice Liquidates an underwater safe and settles the auction right away
    /// @dev It will revert for protected SAFEs (those that have saviours). Protected SAFEs need to be liquidated through the LiquidationEngine
    /// @param safe A SAFE's ID
    /// @param sqrtLimitPrices Limit prices for both swaps (in order)
    /// @return auction The auction ID
    function liquidateAndSettleSAFE(address safe, uint160[2] memory sqrtLimitPrices) public returns (uint auction) {
        if (liquidationEngine.safeSaviours(liquidationEngine.chosenSAFESaviour(collateralType, safe)) == 1) {
            require (liquidationEngine.chosenSAFESaviour(collateralType, safe) == address(0),
            "safe-is-protected.");
        }

        auction = liquidationEngine.liquidateSAFE(collateralType, safe);
        settleAuction(auction, sqrtLimitPrices);
    }
    /// @notice Liquidates an underwater safe and settles the auction right away - no slippage control
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
    /// @param sqrtLimitPrices Limit prices for both swaps (in order)
    function settleAuction(uint auctionId, uint160[2] memory sqrtLimitPrices) public {
        (, uint amountToRaise) = auctionHouse.bids(auctionId);
        require(amountToRaise > ZERO, "GebUniswapV3MultiHopKeeperFlashProxy/auction-already-settled");

        bytes memory callbackData = abi.encode(
            sqrtLimitPrices[1],
            abi.encodeWithSelector(this.bid.selector, auctionId, amountToRaise)
        );

        _startSwap(uniswapPair ,address(coin) == uniswapPair.token1(), addition(wad(amountToRaise), ONE), sqrtLimitPrices[0], callbackData);
        _payCaller();
    }
    /// @notice Settle auctions
    /// @param auctionIds IDs of the auctions to be settled
    /// @param sqrtLimitPrices Limit prices for both swaps (in order)
    function settleAuction(uint[] memory auctionIds, uint160[2] memory sqrtLimitPrices) public {
        (uint[] memory ids, uint[] memory bidAmounts, uint totalAmount) = _getOpenAuctionsBidSizes(auctionIds);
        require(totalAmount > ZERO, "GebUniswapV3MultiHopKeeperFlashProxy/all-auctions-already-settled");

        bytes memory callbackData = abi.encode(
            sqrtLimitPrices[1],
            abi.encodeWithSelector(this.multipleBid.selector, ids, bidAmounts)
        );

        _startSwap(uniswapPair, address(coin) == uniswapPair.token1() ,totalAmount, sqrtLimitPrices[0], callbackData);
        _payCaller();
    }
    /// @notice Settle auction - no slippage controls for backward compatibility
    /// @param auctionId ID of the auction to be settled
    function settleAuction(uint auctionId) public {
        uint160[2] memory sqrtLimitPrices;
        settleAuction(auctionId, sqrtLimitPrices);
    }
    /// @notice Settle auction - no slippage controls for backward compatibility
    /// @param auctionIds IDs of the auctions to be settled
    function settleAuction(uint[] memory auctionIds) public {
        uint160[2] memory sqrtLimitPrices;
        settleAuction(auctionIds, sqrtLimitPrices);
    }

    // --- Fallback ---
    receive() external payable {
        require(msg.sender == address(weth), "GebUniswapV3MultiHopKeeperFlashProxy/only-weth-withdrawals-allowed");
    }
}
