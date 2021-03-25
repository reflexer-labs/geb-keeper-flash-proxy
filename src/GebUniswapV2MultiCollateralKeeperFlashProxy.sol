pragma solidity 0.6.7;

import "./uni/interfaces/IUniswapV2Pair.sol";
import "./uni/interfaces/IUniswapV2Factory.sol";

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
contract GebUniswapV2MultiCollateralKeeperFlashProxy {
    SAFEEngineLike          public safeEngine;
    CollateralLike          public weth;
    CollateralLike          public coin;
    CoinJoinLike            public coinJoin;
    IUniswapV2Pair          public uniswapPair;
    IUniswapV2Factory       public uniswapFactory;
    LiquidationEngineLike   public liquidationEngine;
    bytes32                 public collateralType;

    uint256 public constant ZERO           = 0;
    uint256 public constant ONE            = 1;
    uint256 public constant THOUSAND       = 1000;
    uint256 public constant NET_OUT_AMOUNT = 997;

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
        uniswapFactory     = IUniswapV2Factory(uniswapFactoryAddress);
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
        uint amount0Out = address(coin) == uniswapPair.token0() ? amount : ZERO;
        uint amount1Out = address(coin) == uniswapPair.token1() ? amount : ZERO;

        uniswapPair.swap(amount0Out, amount1Out, address(this), data);
    }

    // --- External Utils ---
    /// @notice Callback for Uniswap V2
    /// @param _sender Flashswap requestor (must be this contract)
    /// @param _amount0 Amount of token0
    /// @param _amount1 Amount of token1
    /// @param _data Data sent back from Uniswap
    function uniswapV2Call(address _sender, uint _amount0, uint _amount1, bytes calldata _data) external {
        require(_sender == address(this), "GebUniswapV2MultiCollateralKeeperFlashProxy/invalid-sender");
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
        uint pairBalanceTokenBorrow = coin.balanceOf(address(uniswapPair));
        uint pairBalanceTokenPay = collateralJoin.collateral().balanceOf(address(uniswapPair));
        uint amountToRepay = addition((
          multiply(multiply(THOUSAND, pairBalanceTokenPay), wadAmount) /
          multiply(NET_OUT_AMOUNT, pairBalanceTokenBorrow)
        ), ONE);

        require(amountToRepay <= collateralJoin.collateral().balanceOf(address(this)), "GebUniswapV2MultiCollateralKeeperFlashProxy/profit-not-enough-to-repay-the-flashswap");
        collateralJoin.collateral().transfer(address(uniswapPair), amountToRepay);

        // send profit back
        if (collateralJoin.collateral() == weth) {
            uint profit = weth.balanceOf(address(this));
            weth.withdraw(profit);
            caller.call{value: profit}("");
        } else {
            collateralJoin.collateral().transfer(caller, collateralJoin.collateral().balanceOf(address(this)));
        }

        uniswapPair = IUniswapV2Pair(address(0x0));
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
        (, uint amountToRaise) =  auctionHouse.bids(auctionId);
        require(amountToRaise > ZERO, "GebUniswapV2MultiCollateralKeeperFlashProxy/auction-already-settled");

        bytes memory callbackData = abi.encode(
            msg.sender,
            address(collateralJoin),
            address(auctionHouse),
            auctionId,
            amountToRaise);   // rad

        uniswapPair = IUniswapV2Pair(uniswapFactory.getPair(address(collateralJoin.collateral()), address(coin)));

        safeEngine.approveSAFEModification(address(auctionHouse));
        _startSwap(addition(wad(amountToRaise), ONE), callbackData);
        safeEngine.denySAFEModification(address(auctionHouse));
    }

    // --- Fallback ---
    receive() external payable {
        require(msg.sender == address(weth), "GebUniswapV2MultiCollateralKeeperFlashProxy/only-weth-withdrawals-allowed");
    }
}
