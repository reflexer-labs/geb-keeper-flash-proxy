pragma solidity ^0.6.7;

import "ds-test/test.sol";
import "ds-weth/weth9.sol";
import "ds-token/token.sol";

import {SAFEEngine} from "geb/SAFEEngine.sol";
import {FixedDiscountCollateralAuctionHouse} from "geb/CollateralAuctionHouse.sol";
import {OracleRelayer} from "geb/OracleRelayer.sol";

import "./uni/UniswapV2Factory.sol";
import "./uni/UniswapV2Pair.sol";

import "./GebKeeperFlashProxy.sol";

abstract contract Hevm {
    function warp(uint) virtual public;
}

contract Guy {
    FixedDiscountCollateralAuctionHouse fixedDiscountCollateralAuctionHouse;

    constructor(
      FixedDiscountCollateralAuctionHouse fixedDiscountCollateralAuctionHouse_
    ) public {
        fixedDiscountCollateralAuctionHouse = fixedDiscountCollateralAuctionHouse_;
    }
    function approveSAFEModification(bytes32 auctionType, address safe) public {
        address safeEngine = address(fixedDiscountCollateralAuctionHouse.safeEngine());
        SAFEEngine(safeEngine).approveSAFEModification(safe);
    }
    function buyCollateral(uint id, uint wad) public {
        fixedDiscountCollateralAuctionHouse.buyCollateral(id, wad);
    }
    function try_buyCollateral(uint id, uint wad)
        public returns (bool ok)
    {
        string memory sig = "buyCollateral(uint256,uint256)";
        (ok,) = address(fixedDiscountCollateralAuctionHouse).call(abi.encodeWithSignature(sig, id, wad));
    }
    function try_fixedDiscount_terminateAuctionPrematurely(uint id)
        public returns (bool ok)
    {
        string memory sig = "terminateAuctionPrematurely(uint256)";
        (ok,) = address(fixedDiscountCollateralAuctionHouse).call(abi.encodeWithSignature(sig, id));
    }
}

contract SAFEEngine_ is SAFEEngine {
    function mint(address usr, uint wad) public {
        coinBalance[usr] += wad;
    }
    function coin_balance(address usr) public view returns (uint) {
        return coinBalance[usr];
    }
    bytes32 collateralType;
    function set_collateral_type(bytes32 collateralType_) public {
        collateralType = collateralType_;
    }
    function token_collateral_balance(address usr) public view returns (uint) {
        return tokenCollateral[collateralType][usr];
    }
}

contract Feed {
    uint256 public priceFeedValue;
    bool public hasValidValue;
    constructor(bytes32 initPrice, bool initHas) public {
        priceFeedValue = uint(initPrice);
        hasValidValue = initHas;
    }
    function set_val(uint newPrice) external {
        priceFeedValue = newPrice;
    }
    function set_has(bool newHas) external {
        hasValidValue = newHas;
    }
    function getResultWithValidity() external returns (uint256, bool) {
        return (priceFeedValue, hasValidValue);
    }
}

contract DummyLiquidationEngine {
    uint256 public currentOnAuctionSystemCoins;

    constructor(uint rad) public {
        currentOnAuctionSystemCoins = rad;
    }

    function subtract(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }

    function removeCoinsFromAuction(uint rad) public {
      currentOnAuctionSystemCoins = subtract(currentOnAuctionSystemCoins, rad);
    }
}

contract GebKeeperFlashProxyTest is DSTest {
    Hevm hevm;

    DummyLiquidationEngine liquidationEngine;
    SAFEEngine_ safeEngine;
    FixedDiscountCollateralAuctionHouse collateralAuctionHouse;
    OracleRelayer oracleRelayer;
    Feed    collateralFSM;
    Feed    collateralMedian;
    Feed    systemCoinMedian;

    address ali;
    address bob;
    address auctionIncomeRecipient;
    address safeAuctioned = address(0xacab);

    uint constant WAD = 10 ** 18;
    uint constant RAY = 10 ** 27;
    uint constant RAD = 10 ** 45;

    GebKeeperFlashProxy proxy;
    DSToken rai;
    

    UniswapV2Factory uniswapFactory;
    UniswapV2Pair raiETHPair;


    function rad(uint wad) internal pure returns (uint z) {
        z = wad * 10 ** 27;
    }

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

        safeEngine = new SAFEEngine_();

        safeEngine.initializeCollateralType("ETH");
        safeEngine.set_collateral_type("ETH");
        
        liquidationEngine = new DummyLiquidationEngine(rad(1000 ether));
        collateralAuctionHouse = new FixedDiscountCollateralAuctionHouse(address(safeEngine), address(liquidationEngine), "ETH");

        oracleRelayer = new OracleRelayer(address(safeEngine));
        oracleRelayer.modifyParameters("redemptionPrice", 5 * RAY);
        collateralAuctionHouse.modifyParameters("oracleRelayer", address(oracleRelayer));

        collateralFSM = new Feed(bytes32(uint256(0)), true);
        collateralAuctionHouse.modifyParameters("collateralFSM", address(collateralFSM));

        collateralMedian = new Feed(bytes32(uint256(0)), true);
        systemCoinMedian = new Feed(bytes32(uint256(0)), true);

        ali = address(new Guy(collateralAuctionHouse));
        bob = address(new Guy(collateralAuctionHouse));
        auctionIncomeRecipient = address(0xbcd);

        Guy(ali).approveSAFEModification("fixed", address(collateralAuctionHouse));
        Guy(bob).approveSAFEModification("fixed", address(collateralAuctionHouse));
        safeEngine.approveSAFEModification(address(collateralAuctionHouse));

        safeEngine.modifyCollateralBalance("ETH", address(this), 1000 ether);
        safeEngine.mint(ali, 200 ether);
        safeEngine.mint(bob, 200 ether);

        uniswapFactory = new UniswapV2Factory(address(this));
        // raiETHPair = UniswapV2Pair(uniswapFactory.createPair(address(weth), address(coin)));
        // proxy = new GebKeeperFlashProxy();
    }
}
