pragma solidity 0.6.7;

import "ds-test/test.sol";
import "ds-weth/weth9.sol";
import "ds-token/token.sol";
import {DSValue} from "ds-value/value.sol";

import {GebDeployTestBase} from "geb-deploy/test/GebDeploy.t.base.sol";
import {FixedDiscountCollateralAuctionHouse} from "geb/CollateralAuctionHouse.sol";
import {CollateralJoin3, CollateralJoin4} from "geb-deploy/AdvancedTokenAdapters.sol";
import {GebSafeManager} from "geb-safe-manager/GebSafeManager.sol";
import {GetSafes} from "geb-safe-manager/GetSafes.sol";
import {GebProxyIncentivesActions} from "geb-proxy-actions/GebProxyIncentivesActions.sol";

import "../uni/v2/UniswapV2Factory.sol";
import "../uni/v2/UniswapV2Pair.sol";
import "../uni/v2/UniswapV2Router02.sol";

import "../GebUniswapV2KeeperFlashProxyETH.sol";

contract GebUniswapV2KeeperFlashProxyETHTest is GebDeployTestBase, GebProxyIncentivesActions {
    GebSafeManager manager;
    GebUniswapV2KeeperFlashProxyETH keeperProxy;

    UniswapV2Factory uniswapFactory;
    UniswapV2Router02 uniswapRouter;
    UniswapV2Pair raiETHPair;
    uint256 initETHRAIPairLiquidity = 5 ether;               // 1250 USD
    uint256 initRAIETHPairLiquidity = 294.672324375E18;      // 1 RAI = 4.242 USD

    uint[] auctions;
    bytes32 collateralAuctionType = bytes32("FIXED_DISCOUNT");

    function setUp() override public {
        super.setUp();
        deployIndexWithCreatorPermissions(collateralAuctionType);

        safeEngine.modifyParameters("ETH", "debtCeiling", uint(-1)); // unlimited debt ceiling, enough liquidity is needed on Uniswap.
        safeEngine.modifyParameters("globalDebtCeiling", uint(-1));  // unlimited globalDebtCeiling

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
        coin.transfer(address(1), coin.balanceOf(address(this)));
        raiETHPair.transfer(address(0), raiETHPair.balanceOf(address(this)));

        // keeper Proxy
        keeperProxy = new GebUniswapV2KeeperFlashProxyETH(
            address(ethIncreasingDiscountCollateralAuctionHouse),
            address(weth),
            address(coin),
            address(raiETHPair),
            address(coinJoin),
            address(ethJoin)
        );
    }

    // --- Utils ---
    uint[] safes;
    function _collateralAuctionETH(uint numberOfAuctions) internal returns (uint lastBidId) {
        this.modifyParameters(address(liquidationEngine), "ETH", "liquidationQuantity", rad(1000 ether));
        this.modifyParameters(address(liquidationEngine), "ETH", "liquidationPenalty", WAD);

        for (uint i = 0; i < numberOfAuctions; i++) {
            uint safe = manager.openSAFE("ETH", address(this));
            safes.push(safe);

            _lockETH(address(manager), address(ethJoin), safe, 0.1 ether);

            _generateDebt(address(manager), address(taxCollector), address(coinJoin), safe, 20 ether, address(this)); // Maximun COIN generated
        }

        // Liquidate
        orclETH.updateResult(uint(300 * 10 ** 18 - 1)); // Force liquidation
        oracleRelayer.updateCollateralPrice("ETH");
        for (uint i = 0; i < safes.length; i++) {
            lastBidId = liquidationEngine.liquidateSAFE("ETH", manager.safes(safes[i]));
        }
    }
    function _generateUnsafeSafes(uint numberOfSafes) internal returns (uint lastSafeId) {
        this.modifyParameters(address(liquidationEngine), "ETH", "liquidationQuantity", rad(1000 ether));
        this.modifyParameters(address(liquidationEngine), "ETH", "liquidationPenalty", WAD);

        for (uint i = 0; i < numberOfSafes; i++) {
            lastSafeId = manager.openSAFE("ETH", address(this));
            safes.push(lastSafeId);

            _lockETH(address(manager), address(ethJoin), lastSafeId, 0.1 ether);

            _generateDebt(address(manager), address(taxCollector), address(coinJoin), lastSafeId, 20 ether, address(this)); // Maximun COIN generated
        }

        // Liquidate
        orclETH.updateResult(uint(300 * 10 ** 18 - 1)); // Force liquidation
        oracleRelayer.updateCollateralPrice("ETH");
    }

    // --- Tests ---
    function testSettleAuction() public {
        uint auction = _collateralAuctionETH(1);
        uint previousBalance = address(this).balance;

        keeperProxy.settleAuction(auction);
        emit log_named_uint("Profit", address(this).balance - previousBalance);
        assertTrue(previousBalance < address(this).balance); // profit!

        (, uint amountToRaise,,,,,,,) = ethIncreasingDiscountCollateralAuctionHouse.bids(auction);
        assertEq(amountToRaise, 0);
    }

    function testSettleAuctions() public {
        uint lastAuction = _collateralAuctionETH(10);

        keeperProxy.settleAuction(lastAuction);

        auctions.push(lastAuction);      // auction already taken, will settle others
        auctions.push(lastAuction - 3);
        auctions.push(lastAuction - 4);
        auctions.push(lastAuction - 8);
        auctions.push(uint(0) - 1);      // inexistent auction, should still settle existing ones

        uint previousBalance = address(this).balance;
        keeperProxy.settleAuction(auctions);
        emit log_named_uint("Profit", address(this).balance - previousBalance);
        assertTrue(previousBalance < address(this).balance); // profit!

        for (uint i = 0; i < auctions.length; i++) {
            (, uint amountToRaise,,,,,,,) = ethIncreasingDiscountCollateralAuctionHouse.bids(auctions[i]);
            assertEq(amountToRaise, 0);
        }
    }

    function testFailSettleAuctionTwice() public {
        uint auction = _collateralAuctionETH(1);
        keeperProxy.settleAuction(auction);
        keeperProxy.settleAuction(auction);
    }

    function testLiquidateAndSettleSAFE() public {
        uint safe = _generateUnsafeSafes(1);
        uint previousBalance = address(this).balance;

        uint auction = keeperProxy.liquidateAndSettleSAFE(manager.safes(safe));
        emit log_named_uint("Profit", address(this).balance - previousBalance);
        assertTrue(previousBalance < address(this).balance); // profit!

        (, uint amountToRaise,,,,,,,) = ethIncreasingDiscountCollateralAuctionHouse.bids(auction);
        assertEq(amountToRaise, 0);
    }

    function testFailLiquidateProtectedSAFE() public {
        liquidationEngine.connectSAFESaviour(address(0xabc)); // connecting mock savior

        uint safe = _generateUnsafeSafes(1);

        manager.protectSAFE(safe, address(liquidationEngine), address(0xabc));

        keeperProxy.liquidateAndSettleSAFE(manager.safes(safe));
    }
}
