pragma solidity ^0.6.7;

import "./uni/interfaces/IUniswapV2Pair.sol";

abstract contract AuctionHouseLike {
    function bids(uint) external virtual returns (uint, uint, uint, uint, uint48, address, address);
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

/// trustless proxy to settle auctions using funds from a flashSwap
/// works only with Eth as collateral for now
contract GebKeeperFlashProxy {
    AuctionHouseLike auctionHouse;
    SAFEEngineLike   safeEngine;
    ManagerLike      manager;
    CollateralLike   weth;
    CollateralLike   coin;
    CoinJoinLike     coinJoin;
    CoinJoinLike     ethJoin;
    IUniswapV2Pair   uniswapPair;
    address payable  caller;
    uint    public   safe;
    bytes32 public   collateralType;

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
        address uniswapPairAddress,
        address safeManagerAddress,
        address coinJoinAddress,
        address ethJoinAddress,
        bytes32 _collateralType
    ) public {
        auctionHouse   = AuctionHouseLike(auctionHouseAddress);
        weth           = CollateralLike(wethAddress);
        coin           = CollateralLike(systemCoinAddress);
        uniswapPair    = IUniswapV2Pair(uniswapPairAddress);
        coinJoin       = CoinJoinLike(coinJoinAddress);
        ethJoin        = CoinJoinLike(ethJoinAddress);
        manager        = ManagerLike(safeManagerAddress);
        safeEngine     = manager.safeEngine();
        safe           = manager.openSAFE(collateralType, address(this));
        collateralType = _collateralType;
    }

    function settleAuction(uint auctionId) public {
        (uint raisedAmount,,, uint amountToRaise, uint48 auctionDeadline,,) = auctionHouse.bids(auctionId);
        require(auctionDeadline > now, "auction-expired");
        uint amount = subtract(amountToRaise, raisedAmount);
        require(amount > 0, "auction-already-settled");
        
        caller = msg.sender;

        bytes memory callbackData = abi.encodeWithSelector(this.bid.selector, auctionId, amount);

        uint amount0Out = address(coin) == uniswapPair.token0() ? wad(amount) : 0;
        uint amount1Out = address(coin) == uniswapPair.token1() ? wad(amount) : 0;

        // flashloan amount
        uniswapPair.swap(amount0Out, amount1Out, address(this), callbackData);
    }

    function uniswapV2Call(address _sender, uint _amount0, uint _amount1, bytes calldata _data) external {
        require(_sender == address(this), "invalid sender");
        require(msg.sender == address(uniswapPair), "invalid uniswap pair");

        // calling bid
        address(this).call(_data);

        // repay loan
        uint pairBalanceTokenBorrow = coin.balanceOf(address(uniswapPair));
        uint pairBalanceTokenPay = weth.balanceOf(address(uniswapPair));
        uint amountToRepay = ((1000 * pairBalanceTokenPay * (_amount0 == 0 ? _amount1 : _amount0)) / (997 * pairBalanceTokenBorrow)) + 1;

        weth.transfer(address(uniswapPair), amountToRepay);
        
        // // send profit back
        // uint profit = weth.balanceOf(address(this));
        // weth.withdraw(profit);
        // caller.call{value: profit}("");
        // caller = address(0x0);
    }    

    function bid(uint auctionId, uint amount) public {
        require(msg.sender == address(this), "only self");
        
        

    }
}
