pragma solidity ^0.6.7;

import "./uni/v3/interfaces/IUniswapV3Pool.sol";

abstract contract AuctionHouseLike {
    function bids(uint) external view virtual returns (uint, uint, uint, uint, uint48, address, address);
    function buyCollateral(uint256 id, uint256 wad) external virtual;
}

abstract contract ManagerLike {
    function safeCan(address, uint, address) virtual public view returns (uint);
    function collateralTypes(uint) virtual public view returns (bytes32);
    function ownsSAFE(uint) virtual public view returns (address);
    function safes(uint) virtual public view returns (address);
    function safeEngine() virtual public view returns (SAFEEngineLike);
    function openSAFE(bytes32, address) virtual public returns (uint);
    function transferSAFEOwnership(uint, address) virtual public;
    function allowSAFE(uint, address, uint) virtual public;
    function allowHandler(address, uint) virtual public;
    function modifySAFECollateralization(uint, int, int) virtual public;
    function transferCollateral(uint, address, uint) virtual public;
    function transferInternalCoins(uint, address, uint) virtual public;
    function quitSystem(uint, address) virtual public;
    function enterSystem(address, uint) virtual public;
    function moveSAFE(uint, uint) virtual public;
    function protectSAFE(uint, address, address) virtual public;
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
}

/// @title GEB Keeper Flash Proxy
/// @notice Trustless proxy to allow for bidding in auctions and liquidating Safes using FlashSwaps
contract GebKeeperFlashProxyV3 {
    AuctionHouseLike        auctionHouse;
    SAFEEngineLike          safeEngine;
    ManagerLike             manager;
    CollateralLike          weth;
    CollateralLike          coin;
    CoinJoinLike            coinJoin;
    CoinJoinLike            ethJoin;
    IUniswapV3Pool          uniswapPair;
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
    /// @param safeManagerAddress safe manager address
    /// @param coinJoinAddress coinJoin address
    /// @param ethJoinAddress ethJoin address
    /// @param liquidationEngineAddress liquidation engine address
    /// @param _collateralType collateral type
    constructor(
        address auctionHouseAddress,
        address wethAddress,
        address systemCoinAddress,
        address uniswapPairAddress,
        address safeManagerAddress,
        address coinJoinAddress,
        address ethJoinAddress,
        address liquidationEngineAddress,
        bytes32 _collateralType
    ) public {
        auctionHouse        = AuctionHouseLike(auctionHouseAddress);
        weth                = CollateralLike(wethAddress);
        coin                = CollateralLike(systemCoinAddress);
        uniswapPair         = IUniswapV3Pool(uniswapPairAddress);
        coinJoin            = CoinJoinLike(coinJoinAddress);
        ethJoin             = CoinJoinLike(ethJoinAddress);
        manager             = ManagerLike(safeManagerAddress);
        safeEngine          = manager.safeEngine();
        collateralType      = _collateralType;
        liquidationEngine   = LiquidationEngineLike(liquidationEngineAddress);

        safeEngine.approveSAFEModification(address(auctionHouse));
    }

    /// @notice liquidates an underwater safe and settles the auction right away
    /// @dev it will revert for protected safes (saviour), these need to be liquidated through liquidation engine
    /// @param safe SafeId
    /// @return auction auctionId;
    function liquidateUnprotectedSAFE(uint safe) public returns (uint auction) {
        address safeHandler = manager.safes(safe);
        if (liquidationEngine.safeSaviours(liquidationEngine.chosenSAFESaviour(collateralType, safeHandler)) == 1) {
            require (liquidationEngine.chosenSAFESaviour(collateralType, safeHandler) == address(0),
            "safe-is-protected.");
        }

        auction = liquidationEngine.liquidateSAFE(collateralType, safeHandler);
        settleAuction(auction);
    }

    /// @notice Initiates a flashwap
    /// @param amount amount to borrow
    /// @param data callback date, it will call this contract with the data
    function _startSwap(uint amount, bytes memory data) internal {
        caller = msg.sender;
        (uint160 currentPrice, , , , , , ) = uniswapPair.slot0();
        uint160 sqrtLimitPrice = currentPrice + 1 ether ;

        bool zeroForOne = address(coin) == uniswapPair.token1() ? true : false;

        uniswapPair.swap(address(this), zeroForOne, int256(amount) * -1, sqrtLimitPrice, data); // slippage price not set, will revert if nor profitable
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
        require(msg.sender == address(uniswapPair), "invalid uniswap pair");

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
        uint amountToRepay = (_amount0 > 0) ? uint(_amount0) : uint(_amount1);
        weth.transfer(address(uniswapPair), amountToRepay);

        // send profit back
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

    receive() external payable {}
}
