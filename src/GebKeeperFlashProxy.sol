pragma solidity ^0.6.7;

import "./uni/interfaces/IUniswapV2Pair.sol";

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
    bytes32 public   collateralType;

    function subtract(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "sub-overflow");
    }

    function wad(uint rad) internal pure returns (uint) {
        return rad / 10 ** 27;
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
        collateralType = _collateralType;
        safeEngine.approveSAFEModification(address(auctionHouse)); 
    }

    function _startSwap(uint amount, bytes memory data) internal {
        caller = msg.sender;

        uint amount0Out = address(coin) == uniswapPair.token0() ? amount : 0;
        uint amount1Out = address(coin) == uniswapPair.token1() ? amount : 0;

        uniswapPair.swap(amount0Out, amount1Out, address(this), data);
    }

    function settleAuction(uint auctionId) public {
        (uint raisedAmount,,, uint amountToRaise, uint48 auctionDeadline,,) = auctionHouse.bids(auctionId);
        require(auctionDeadline > now, "auction-expired");
        uint amount = subtract(amountToRaise, raisedAmount);
        require(amount > 0, "auction-already-settled");

        bytes memory callbackData = abi.encodeWithSelector(this.bid.selector, auctionId, amount);

        _startSwap(wad(amount) + 1, callbackData);
    }

    function settleAuction(uint[] memory auctionIds) public {
        (uint[] memory ids, uint[] memory bidAmounts, uint totalAmount) = getOpenAuctionsBidSizes(auctionIds);
        require(totalAmount > 0, "all auctions already settled");

        bytes memory callbackData = abi.encodeWithSelector(this.multipleBid.selector, ids, bidAmounts);

        _startSwap(totalAmount, callbackData);
    }

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
        weth.transfer(address(uniswapPair), amountToRepay);
        
        // // send profit back
        uint profit = weth.balanceOf(address(this));
        weth.withdraw(profit);
        caller.call{value: profit}("");
        caller = address(0x0);
    }    

    function bid(uint auctionId, uint amount) external {
        require(msg.sender == address(this), "only self");
        auctionHouse.buyCollateral(auctionId, amount);
    }

    function multipleBid(uint[] calldata auctionIds, uint[] calldata amounts) external {
        require(msg.sender == address(this), "only self");
        for (uint i = 0; i < auctionIds.length; i++) {
            auctionHouse.buyCollateral(auctionIds[i], amounts[i]);
        }
    }

    receive() external payable {}
}
