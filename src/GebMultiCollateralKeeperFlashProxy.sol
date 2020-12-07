pragma solidity ^0.6.7;

import "./uni/interfaces/IUniswapV2Pair.sol";
import "./uni/interfaces/IUniswapV2Factory.sol";

abstract contract AuctionHouseLike {
    function bids(uint) external view virtual returns (uint, uint, uint, uint, uint48, address, address);
    function buyCollateral(uint256 id, uint256 wad) external virtual;
    function liquidationEngine() view public virtual returns (LiquidationEngineLike);
    function collateralType() view public virtual returns (bytes32);
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

/// @title GEB Multi Collateral Keeper Flash Proxy
/// @notice Trustless proxy to allow for bidding in auctions and liquidating Safes using FlashSwaps
/// @notice Multi collateral version, works both with ETH and ERC20 collateral
contract GebMultiCollateralKeeperFlashProxy {
    SAFEEngineLike          safeEngine;
    CollateralLike          weth;
    CollateralLike          coin;
    CoinJoinLike            coinJoin;
    IUniswapV2Pair          uniswapPair;
    IUniswapV2Factory       uniswapFactory;
    LiquidationEngineLike   liquidationEngine;
    bytes32 public          collateralType;

    // math aux functions
    function subtract(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "sub-overflow");
    }

    function wad(uint rad) internal pure returns (uint) {
        return rad / 10 ** 27;
    }

    /// @notice Constructor
    /// @param wethAddress weth address
    /// @param systemCoinAddress system coin address
    /// @param uniswapFactoryAddress uniswap v2 factory address
    /// @param coinJoinAddress coinJoin address
    /// @param liquidationEngineAddress liquidationEngine address
    constructor(
        address wethAddress,
        address systemCoinAddress,
        address uniswapFactoryAddress,
        address coinJoinAddress,
        address liquidationEngineAddress
    ) public {
        weth                = CollateralLike(wethAddress);
        coin                = CollateralLike(systemCoinAddress);
        uniswapFactory      = IUniswapV2Factory(uniswapFactoryAddress);
        coinJoin            = CoinJoinLike(coinJoinAddress);
        liquidationEngine   = LiquidationEngineLike(liquidationEngineAddress);
        safeEngine          = liquidationEngine.safeEngine();
    }

    /// @notice liquidates an underwater safe and settles the auction right away
    /// @dev it will revert for protected safes (saviour), these need to be liquidated through liquidation engine
    /// @param collateralJoin join address for the collateral
    /// @param safe SafeId
    /// @return auction auctionId;
    function liquidateAndSettleSAFE(CollateralJoinLike collateralJoin, address safe) public returns (uint auction) {
        collateralType = collateralJoin.collateralType();
        if (liquidationEngine.safeSaviours(liquidationEngine.chosenSAFESaviour(collateralType, safe)) == 1) {
            require (liquidationEngine.chosenSAFESaviour(collateralType, safe) == address(0),
            "safe-is-protected.");
        }

        auction = liquidationEngine.liquidateSAFE(collateralType, safe);
        settleAuction(collateralJoin, auction);
    }

    /// @notice Settle auction
    /// @param collateralJoin join address for the collateral
    /// @param auctionId id of the auction to be settled
    function settleAuction(CollateralJoinLike collateralJoin, uint auctionId) public {
        (AuctionHouseLike auctionHouse,,) = liquidationEngine.collateralTypes(collateralJoin.collateralType());
        (uint raisedAmount,,, uint amountToRaise, uint48 auctionDeadline,,) = auctionHouse.bids(auctionId);
        require(auctionDeadline > now, "auction-expired");
        uint amount = subtract(amountToRaise, raisedAmount);
        require(amount > 0, "auction-already-settled");

        bytes memory callbackData = abi.encode(
            msg.sender, 
            address(collateralJoin),
            address(auctionHouse),
            auctionId, 
            amount);   // rad 
        
        uniswapPair = IUniswapV2Pair(uniswapFactory.getPair(address(collateralJoin.collateral()), address(coin)));

        safeEngine.approveSAFEModification(address(auctionHouse));
        _startSwap(wad(amount) + 1, callbackData);
        safeEngine.denySAFEModification(address(auctionHouse));
    }

    /// @notice Initiates a flashwap
    /// @param amount amount to borrow
    /// @param data callback date, it will call this contract with the data
    function _startSwap(uint amount, bytes memory data) internal {

        uint amount0Out = address(coin) == uniswapPair.token0() ? amount : 0;
        uint amount1Out = address(coin) == uniswapPair.token1() ? amount : 0;

        uniswapPair.swap(amount0Out, amount1Out, address(this), data);
    }

    /// @notice callback from Uniswap, funds in hands
    /// @param _sender sender of the flashswap, should be address (this)
    /// @param _amount0 amount of token0
    /// @param _amount1 amount of token1
    /// @param _data data sent back from uniswap
    function uniswapV2Call(address _sender, uint _amount0, uint _amount1, bytes calldata _data) external {
        require(_sender == address(this), "invalid sender");
        require(msg.sender == address(uniswapPair), "invalid uniswap pair");

        (address caller, CollateralJoinLike collateralJoin, AuctionHouseLike auctionHouse, uint auctionId, uint amount) = abi.decode(
            _data, (address, CollateralJoinLike, AuctionHouseLike, uint, uint)
        );

        uint wadAmount = wad(amount) + 1; 

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
        uint amountToRepay = ((1000 * pairBalanceTokenPay * wadAmount ) / (997 * pairBalanceTokenBorrow)) + 1;
        require(amountToRepay <= collateralJoin.collateral().balanceOf(address(this)), "profit not enough to repay the flashswap");
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

    receive() external payable {
        require(msg.sender == address(weth), "only weth withdrawals allowed");
    }
}
