pragma solidity ^0.6.7;

import "ds-test/test.sol";
import "weth/weth9.sol";

import "./GebKeeperFlashProxy.sol";

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

    GebKeeperFlashProxy proxy;
    DSToken rai;
    

    UniswapV2Factory uniswapFactory;
    UniswapV2Router02 uniswapRouter;
    UniswapV2Pair raiETHPair;

    function setUp() public {

        proxy = new GebKeeperFlashProxy();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
