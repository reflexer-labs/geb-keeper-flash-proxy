pragma solidity 0.6.7;

import "ds-test/test.sol";
import "ds-weth/weth9.sol";
import "ds-token/token.sol";

import {GebDeployTestBase} from "geb-deploy/test/GebDeploy.t.base.sol";
import {FixedDiscountCollateralAuctionHouse} from "geb/CollateralAuctionHouse.sol";
import {CollateralJoin3, CollateralJoin4} from "geb-deploy/AdvancedTokenAdapters.sol";
import {DSValue} from "ds-value/value.sol";
import {GebSafeManager} from "geb-safe-manager/GebSafeManager.sol";
import {GetSafes} from "geb-safe-manager/GetSafes.sol";
import {GebProxyIncentivesActions} from "geb-proxy-actions/GebProxyActions.sol";

import "./uni/UniswapV2Factory.sol";
import "./uni/UniswapV2Pair.sol";
import "./uni/UniswapV2Router02.sol";

import "./GebKeeperFlashProxy.sol";

contract GebKeeperFlashProxyTest is GebDeployTestBase, GebProxyIncentivesActions {
    GebSafeManager manager;
    GebKeeperFlashProxy keeperProxy;
    
    UniswapV2Factory uniswapFactory;
    UniswapV2Router02 uniswapRouter;
    UniswapV2Pair raiETHPair;
    uint256 initETHRAIPairLiquidity = 5 ether;               // 1250 USD
    uint256 initRAIETHPairLiquidity = 294.672324375E18;      // 1 RAI = 4.242 USD

    bytes32 collateralAuctionType = bytes32("FIXED_DISCOUNT");

    function setUp() override public {
        super.setUp();
        deployIndexWithCreatorPermissions(collateralAuctionType);
        safeEngine.modifyParameters("ETH", "debtCeiling", uint(0) - 1); // unlimited debt ceiling, enough liquidity is needed on Uniswap.
        safeEngine.modifyParameters("globalDebtCeiling", uint(0) - 1); // unlimited globalDebtCeiling
        emit log_named_uint("debtCeiling", uint(0) - 1);

        manager = new GebSafeManager(address(safeEngine));

        // Setup Uniswap
        uniswapFactory = new UniswapV2Factory(address(this));
        raiETHPair = UniswapV2Pair(uniswapFactory.createPair(address(weth), address(coin)));
        uniswapRouter = new UniswapV2Router02(address(uniswapFactory), address(weth));

        // Add pair liquidity
        weth.approve(address(uniswapRouter), uint(-1));
        weth.deposit{value: initETHRAIPairLiquidity}();
        coin.approve(address(uniswapRouter), uint(-1));
        uint safe = this.openSAFE(address(manager), "ETH", address(this));
        _lockETH(address(manager), address(ethJoin), safe, 2000 ether);
        _generateDebt(address(manager), address(taxCollector), address(coinJoin), safe, 100000 ether, address(this));
        uniswapRouter.addLiquidity(address(weth), address(coin), initETHRAIPairLiquidity, 100000 ether, 1000 ether, initRAIETHPairLiquidity, address(this), now);

        // zeroing balances
        coin.transfer(address(0), coin.balanceOf(address(this)));
        raiETHPair.transfer(address(0), raiETHPair.balanceOf(address(this)));

        // keeper Proxy
        keeperProxy = new GebKeeperFlashProxy(
            address(ethFixedDiscountCollateralAuctionHouse),
            address(weth),
            address(coin),
            address(raiETHPair),
            address(manager),
            address(coinJoin),
            address(ethJoin),
            "ETH"
        );
    }

    function _collateralAuctionETH() internal returns (uint batchId) {
        this.modifyParameters(address(liquidationEngine), "ETH", "liquidationQuantity", rad(1000 ether));
        this.modifyParameters(address(liquidationEngine), "ETH", "liquidationPenalty", WAD);

        // open safe
        uint safe = manager.openSAFE("ETH", address(this));

        _lockETH(address(manager), address(ethJoin), safe, 0.1 ether);

        _generateDebt(address(manager), address(taxCollector), address(coinJoin), safe, 20 ether, address(this)); // Maximun COIN generated

        // Liquidate
        orclETH.updateResult(uint(300 * 10 ** 18 - 1)); // Force liquidation
        oracleRelayer.updateCollateralPrice("ETH");
        batchId = liquidationEngine.liquidateSAFE("ETH", manager.safes(safe));
    }

    function testSettleAuction() public {
        uint auction = _collateralAuctionETH();
        uint previousBalance = address(this).balance;
        keeperProxy.settleAuction(auction);
        emit log_named_uint("Profit", address(this).balance - previousBalance);
        assertTrue(previousBalance < address(this).balance); // profit!
    }

    function testFailSettleAuctionTwice() public {
        uint auction = _collateralAuctionETH();
        keeperProxy.settleAuction(auction);
        keeperProxy.settleAuction(auction);
    }

    function testBigRedButton() public {
        uint auction = _collateralAuctionETH();
        uint previousBalance = address(this).balance;
        keeperProxy.bigRedButton();
        emit log_named_uint("Profit", address(this).balance - previousBalance);
        assertEq(keeperProxy.lastKnownSettledAuction(), auction);
        assertTrue(previousBalance < address(this).balance); // profit!
    }
}