pragma solidity 0.6.7;

import "./uni/v3/interfaces/IUniswapV3Pool.sol";
import "./uni/v3/interfaces/IUniswapV3Factory.sol";

abstract contract AuctionHouseLike {
    function bids(uint256) virtual external view returns (uint, uint);
    function buyCollateral(uint256, uint256) virtual external;
    function liquidationEngine() virtual public view returns (LiquidationEngineLike);
    function collateralType() virtual public view returns (bytes32);
}

abstract contract SAFEEngineLike {
    function tokenCollateral(bytes32, address) virtual public view returns (uint);
    function canModifySAFE(address, address) virtual public view returns (uint);
    function collateralTypes(bytes32) virtual public view returns (uint, uint, uint, uint, uint);
    function coinBalance(address) virtual public view returns (uint);
    function safes(bytes32, address) virtual public view returns (uint, uint);
    function modifySAFECollateralization(bytes32, address, address, address, int, int) virtual public;
    function approveSAFEModification(address) virtual public;
    function denySAFEModification(address) virtual public;
    function transferInternalCoins(address, address, uint) virtual public;
}

abstract contract CollateralJoinLike {
    function decimals() virtual public returns (uint);
    function collateral() virtual public returns (CollateralLike);
    function join(address, uint) virtual public payable;
    function exit(address, uint) virtual public;
    function collateralType() virtual public returns (bytes32);
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
    function chosenSAFESaviour(bytes32, address) virtual view public returns (address);
    function safeSaviours(address) virtual view public returns (uint);
    function liquidateSAFE(bytes32 collateralType, address safe) virtual external returns (uint256 auctionId);
    function safeEngine() view public virtual returns (SAFEEngineLike);
    function collateralTypes(bytes32) public virtual returns(AuctionHouseLike,uint,uint);
}

/*
* @title GEB Multi Collateral Keeper Flash Proxy
* @notice Trustless proxy that facilitates SAFE liquidation and bidding in collateral auctions using Uniswap V2 flashswaps
* @notice Multi collateral version, works with both ETH and general ERC20 collateral
*/
contract GebUniswapV3MultiCollateralKeeperFlashProxy {
    SAFEEngineLike          public safeEngine;
    CollateralLike          public weth;
    CollateralLike          public coin;
    CoinJoinLike            public coinJoin;
    IUniswapV3Pool          public uniswapPair;
    IUniswapV3Factory       public uniswapFactory;
    LiquidationEngineLike   public liquidationEngine;
    bytes32                 public collateralType;

    uint256 public constant ZERO           = 0;
    uint256 public constant ONE            = 1;

    /// @notice Constructor
    /// @param wethAddress WETH address
    /// @param systemCoinAddress System coin address
    /// @param uniswapFactoryAddress Uniswap V2 factory address
    /// @param coinJoinAddress CoinJoin address
    /// @param liquidationEngineAddress Liquidation engine address
    constructor(
        address wethAddress,
        address systemCoinAddress,
        address uniswapFactoryAddress,
        address coinJoinAddress,
        address liquidationEngineAddress
    ) public {
        require(wethAddress != address(0), "GebUniswapV2MultiCollateralKeeperFlashProxy/null-weth");
        require(systemCoinAddress != address(0), "GebUniswapV2MultiCollateralKeeperFlashProxy/null-system-coin");
        require(uniswapFactoryAddress != address(0), "GebUniswapV2MultiCollateralKeeperFlashProxy/null-uniswap-factory");
        require(coinJoinAddress != address(0), "GebUniswapV2MultiCollateralKeeperFlashProxy/null-coin-join");
        require(liquidationEngineAddress != address(0), "GebUniswapV2MultiCollateralKeeperFlashProxy/null-liquidation-engine");

        weth               = CollateralLike(wethAddress);
        coin               = CollateralLike(systemCoinAddress);
        uniswapFactory     = IUniswapV3Factory(uniswapFactoryAddress);
        coinJoin           = CoinJoinLike(coinJoinAddress);
        liquidationEngine  = LiquidationEngineLike(liquidationEngineAddress);
        safeEngine         = liquidationEngine.safeEngine();
    }

    // --- Math ---
    function addition(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "GebUniswapV2MultiCollateralKeeperFlashProxy/add-overflow");
    }
    function subtract(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "GebUniswapV2MultiCollateralKeeperFlashProxy/sub-underflow");
    }
    function multiply(uint x, uint y) internal pure returns (uint z) {
        require(y == ZERO || (z = x * y) / y == x, "GebUniswapV2MultiCollateralKeeperFlashProxy/mul-overflow");
    }
    function wad(uint rad) internal pure returns (uint) {
        return rad / 10 ** 27;
    }

    // --- Internal Utils ---
    /// @notice Initiates a flashwap
    /// @param amount Amount to borrow
    /// @param data Callback data
    function _startSwap(uint amount, bytes memory data) internal {
        (uint160 currentPrice, , , , , , ) = uniswapPair.slot0();
        uint160 sqrtLimitPrice = currentPrice + 1 ether ;

        bool zeroForOne = address(coin) == uniswapPair.token1() ? true : false;

        uniswapPair.swap(address(this), zeroForOne, int256(amount) * -1, sqrtLimitPrice, data);
    }

    // --- External Utils ---
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
        require(msg.sender == address(uniswapPair), "GebUniswapV2MultiCollateralKeeperFlashProxy/invalid-uniswap-pair");

        (address caller, CollateralJoinLike collateralJoin, AuctionHouseLike auctionHouse, uint auctionId, uint amount) = abi.decode(
            _data, (address, CollateralJoinLike, AuctionHouseLike, uint, uint)
        );

        uint wadAmount = addition(wad(amount), ONE);

        // join COIN
        coin.approve(address(coinJoin), wadAmount);
        coinJoin.join(address(this), wadAmount);

        // bid
        auctionHouse.buyCollateral(auctionId, amount);

        // exit collateral
        collateralJoin.exit(address(this), safeEngine.tokenCollateral(collateralJoin.collateralType(), address(this)));

        // repay loan
        uint amountToRepay = _amount0 > int(ZERO) ? uint(_amount0) : uint(_amount1);

        require(amountToRepay <= collateralJoin.collateral().balanceOf(address(this)), "GebUniswapV2MultiCollateralKeeperFlashProxy/unprofitable");
        collateralJoin.collateral().transfer(address(uniswapPair), amountToRepay);

        // send profit back
        if (collateralJoin.collateral() == weth) {
            uint profit = weth.balanceOf(address(this));
            weth.withdraw(profit);
            caller.call{value: profit}("");
        } else {
            collateralJoin.collateral().transfer(caller, collateralJoin.collateral().balanceOf(address(this)));
        }

        uniswapPair = IUniswapV3Pool(address(0x0));
    }

    // --- Core Bidding and Settling Logic ---
    /// @notice Liquidates an underwater SAFE and settles the auction right away
    /// @dev It will revert for protected safes (those that have saviours), these need to be liquidated through the LiquidationEngine
    /// @param collateralJoin Join address for a collateral type
    /// @param safe A SAFE's ID
    /// @return auction Auction ID
    function liquidateAndSettleSAFE(CollateralJoinLike collateralJoin, address safe) public returns (uint auction) {
        collateralType = collateralJoin.collateralType();
        if (liquidationEngine.safeSaviours(liquidationEngine.chosenSAFESaviour(collateralType, safe)) == ONE) {
            require (liquidationEngine.chosenSAFESaviour(collateralType, safe) == address(0),
            "GebUniswapV2MultiCollateralKeeperFlashProxy/safe-is-protected");
        }

        auction = liquidationEngine.liquidateSAFE(collateralType, safe);
        settleAuction(collateralJoin, auction);
    }

    /// @notice Settle an auction
    /// @param collateralJoin Join address for a collateral type
    /// @param auctionId ID of the auction to be settled
    function settleAuction(CollateralJoinLike collateralJoin, uint auctionId) public {
        (AuctionHouseLike auctionHouse,,) = liquidationEngine.collateralTypes(collateralJoin.collateralType());
        (, uint amountToRaise) = auctionHouse.bids(auctionId);
        require(amountToRaise > ZERO, "GebUniswapV2MultiCollateralKeeperFlashProxy/auction-already-settled");

        bytes memory callbackData = abi.encode(
            msg.sender,
            address(collateralJoin),
            address(auctionHouse),
            auctionId,
            amountToRaise);   // rad

        uniswapPair = IUniswapV3Pool(uniswapFactory.getPool(address(collateralJoin.collateral()), address(coin), 3000));

        safeEngine.approveSAFEModification(address(auctionHouse));
        _startSwap(addition(wad(amountToRaise), ONE), callbackData);
        safeEngine.denySAFEModification(address(auctionHouse));
    }

    // --- Fallback ---
    receive() external payable {
        require(msg.sender == address(weth), "GebUniswapV2MultiCollateralKeeperFlashProxy/only-weth-withdrawals-allowed");
    }
}
