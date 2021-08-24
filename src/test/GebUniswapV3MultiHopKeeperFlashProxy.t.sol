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
import {GebProxyIncentivesActions} from "geb-proxy-actions/GebProxyIncentivesActions.sol";
import {LiquidityAmounts} from "../uni/v3/libraries/LiquidityAmounts.sol";

import "../uni/v3/UniswapV3Factory.sol";
import "../uni/v3/UniswapV3Pool.sol";

import "../GebUniswapV3MultiHopKeeperFlashProxy.sol";

contract GebUniswapV3KeeperFlashProxyETHTest is GebDeployTestBase, GebProxyIncentivesActions {
    GebSafeManager manager;
    GebUniswapV3MultiHopKeeperFlashProxy keeperProxy;

    DSToken ext;

    UniswapV3Pool raiEXTPair;
    UniswapV3Pool extETHPair;

    bytes32 collateralAuctionType = bytes32("FIXED_DISCOUNT");

    function setUp() override public {
        super.setUp();
        deployIndexKeepAuth(collateralAuctionType);
        this.modifyParameters(address(safeEngine), "ETH", "debtCeiling", uint(0) - 1);
        this.modifyParameters(address(safeEngine), "globalDebtCeiling", uint(0) - 1);

        ext = new DSToken("EXT", "EXT");
        ext.mint(100000000 ether);

        manager = new GebSafeManager(address(safeEngine));

        // Setup Uniswap
        raiEXTPair = UniswapV3Pool(_deployV3Pool(address(coin), address(ext), 3000));
        raiEXTPair.initialize(address(coin) == raiEXTPair.token0() ? 45742400955009932534161870629 : 137227202865029797602485611888);

        extETHPair = UniswapV3Pool(_deployV3Pool(address(ext), address(weth), 3000));
        extETHPair.initialize(address(ext) == extETHPair.token0() ? 4339505179874779489431521786 : 1446501726624926496477173928);

        // Add pair liquidity
        uint safe = this.openSAFE(address(manager), "ETH", address(this));
        _lockETH(address(manager), address(ethJoin), safe, 500000 ether);
        _generateDebt(address(manager), address(taxCollector), address(coinJoin), safe, 100000000 ether, address(this));
        weth.deposit{value: 1000000 ether}();
        _addWhaleLiquidity();

        // zeroing balances
        coin.transfer(address(1), coin.balanceOf(address(this)));
        weth.transfer(address(1), weth.balanceOf(address(this)));
        ext.transfer(address(1), ext.balanceOf(address(this)));

        // keeper Proxy
        keeperProxy = new GebUniswapV3MultiHopKeeperFlashProxy(
            address(ethIncreasingDiscountCollateralAuctionHouse),
            address(weth),
            address(coin),
            address(raiEXTPair),
            address(extETHPair),
            address(coinJoin),
            address(ethJoin)
        );
    }

    // --- Helpers ---
    function _deployV3Pool(
        address _token0,
        address _token1,
        uint256 _fee
    ) internal returns (address _pool) {
        UniswapV3Factory fac = new UniswapV3Factory();
        _pool = fac.createPool(_token0, _token1, uint24(_fee));
    }

    function _addWhaleLiquidity() internal {
        int24 low = -887220;
        int24 upp = 887220;

        // coin/ext
        (uint160 sqrtRatioX96, , , , , , ) = raiEXTPair.slot0();
        uint128 liq;
        if (address(coin) == raiEXTPair.token0())
            liq = _getLiquidityAmountsForTicks(sqrtRatioX96, low, upp, 10000 ether, 30000 ether);
        else
            liq = _getLiquidityAmountsForTicks(sqrtRatioX96, low, upp, 30000 ether,  10000 ether);
        raiEXTPair.mint(address(this), low, upp, liq, bytes(""));

        // ext/eth
        (sqrtRatioX96, , , , , , ) = raiEXTPair.slot0();
        if (address(ext) == extETHPair.token0())
            liq = _getLiquidityAmountsForTicks(sqrtRatioX96, low, upp, 3000000 ether, 1000 ether);
        else
            liq = _getLiquidityAmountsForTicks(sqrtRatioX96, low, upp, 1000 ether,  3000000 ether);
        extETHPair.mint(address(this), low, upp, liq, bytes(""));
    }

    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata
    ) external {
        DSToken(UniswapV3Pool(msg.sender).token0()).transfer(msg.sender, amount0Owed);
        DSToken(UniswapV3Pool(msg.sender).token1()).transfer(msg.sender, amount1Owed);
    }

    function _getLiquidityAmountsForTicks(
        uint160 sqrtRatioX96,
        int24 _lowerTick,
        int24 upperTick,
        uint256 t0am,
        uint256 t1am
    ) public pure returns (uint128 liquidity) {
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(_lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            t0am,
            t1am
        );
    }

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

    function testSetup() public {
        assertEq(address(keeperProxy.auctionHouse()), address(ethIncreasingDiscountCollateralAuctionHouse));
        assertEq(address(keeperProxy.weth()), address(weth));
        assertEq(address(keeperProxy.coin()), address(coin));
        assertEq(address(keeperProxy.uniswapPair()), address(raiEXTPair));
        assertEq(address(keeperProxy.auxiliaryUniPair()), address(extETHPair));
        assertEq(address(keeperProxy.coinJoin()), address(coinJoin));
        assertEq(address(keeperProxy.collateralJoin()), address(ethJoin));
    }

    function testFailSetupNullAuctionHouse() public {
        keeperProxy = new GebUniswapV3MultiHopKeeperFlashProxy(
            address(0),
            address(weth),
            address(coin),
            address(raiEXTPair),
            address(extETHPair),
            address(coinJoin),
            address(ethJoin)
        );
    }

    function testFailSetupNullWeth() public {
        keeperProxy = new GebUniswapV3MultiHopKeeperFlashProxy(
            address(ethIncreasingDiscountCollateralAuctionHouse),
            address(0),
            address(coin),
            address(raiEXTPair),
            address(extETHPair),
            address(coinJoin),
            address(ethJoin)
        );
    }

    function testFailSetupNullCoin() public {
        keeperProxy = new GebUniswapV3MultiHopKeeperFlashProxy(
            address(ethIncreasingDiscountCollateralAuctionHouse),
            address(weth),
            address(0),
            address(raiEXTPair),
            address(extETHPair),
            address(coinJoin),
            address(ethJoin)
        );
    }

    function testFailSetupNullUniPair() public {
        keeperProxy = new GebUniswapV3MultiHopKeeperFlashProxy(
            address(ethIncreasingDiscountCollateralAuctionHouse),
            address(weth),
            address(coin),
            address(0),
            address(extETHPair),
            address(coinJoin),
            address(ethJoin)
        );
    }

    function testFailSetupNullAuxUniPair() public {
        keeperProxy = new GebUniswapV3MultiHopKeeperFlashProxy(
            address(ethIncreasingDiscountCollateralAuctionHouse),
            address(weth),
            address(coin),
            address(raiEXTPair),
            address(0),
            address(coinJoin),
            address(ethJoin)
        );
    }

    function testFailSetupNullCoinJoin() public {
        keeperProxy = new GebUniswapV3MultiHopKeeperFlashProxy(
            address(ethIncreasingDiscountCollateralAuctionHouse),
            address(weth),
            address(coin),
            address(raiEXTPair),
            address(extETHPair),
            address(0),
            address(ethJoin)
        );
    }

    function testFailSetupNullCollateralJoin() public {
        keeperProxy = new GebUniswapV3MultiHopKeeperFlashProxy(
            address(ethIncreasingDiscountCollateralAuctionHouse),
            address(weth),
            address(coin),
            address(raiEXTPair),
            address(extETHPair),
            address(coinJoin),
            address(0)
        );
    }

    function testFailCallUniswapCallback() public {
        keeperProxy.uniswapV3SwapCallback(int(0), int(0), "");
    }

    function testFailCallBid() public {
        uint auction = _collateralAuctionETH(1);
        keeperProxy.bid(auction, 1 ether);
    }

    uint[] auctions;
    uint[] bids;

    function testFailCallMultipleBid() public {
        uint lastAuction = _collateralAuctionETH(10);

        auctions.push(lastAuction);      // auction already taken, will settle others
        auctions.push(lastAuction - 3);
        bids.push(1 ether);
        bids.push(1 ether);
        keeperProxy.multipleBid(auctions, bids);
    }

    function testSettleAuction() public {
        uint auction = _collateralAuctionETH(1);
        uint previousBalance = address(this).balance;

        keeperProxy.settleAuction(auction);
        emit log_named_uint("Profit", address(this).balance - previousBalance);
        assertTrue(previousBalance < address(this).balance); // profit!

        (, uint amountToRaise,,,,,,,) = ethIncreasingDiscountCollateralAuctionHouse.bids(auction);
        assertEq(amountToRaise, 0);
        assertEq(weth.balanceOf(address(keeperProxy)), 0);
        assertEq(coin.balanceOf(address(keeperProxy)), 0);
        assertEq(ext.balanceOf(address(keeperProxy)), 0);
        assertEq(address(keeperProxy).balance, 0);
    }
    function testSettleAuctions() public {
        uint lastAuction = _collateralAuctionETH(10);

        keeperProxy.settleAuction(lastAuction);

        auctions.push(lastAuction);      // auction already taken, will settle others
        auctions.push(lastAuction - 3);
        auctions.push(lastAuction - 4);
        auctions.push(lastAuction - 8);
        auctions.push(uint(0) - 1);      // unexistent auction, should still settle existing ones
        uint previousBalance = address(this).balance;
        keeperProxy.settleAuction(auctions);
        emit log_named_uint("Profit", address(this).balance - previousBalance);
        assertTrue(previousBalance < address(this).balance); // profit!

        for (uint i = 0; i < auctions.length; i++) {
            (, uint amountToRaise,,,,,,,) = ethIncreasingDiscountCollateralAuctionHouse.bids(auctions[i]);
            assertEq(amountToRaise, 0);
        }
        assertEq(weth.balanceOf(address(keeperProxy)), 0);
        assertEq(coin.balanceOf(address(keeperProxy)), 0);
        assertEq(ext.balanceOf(address(keeperProxy)), 0);
        assertEq(address(keeperProxy).balance, 0);
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
        assertEq(weth.balanceOf(address(keeperProxy)), 0);
        assertEq(coin.balanceOf(address(keeperProxy)), 0);
        assertEq(ext.balanceOf(address(keeperProxy)), 0);
        assertEq(address(keeperProxy).balance, 0);
    }

    function testFailLiquidateProtectedSAFE() public {
        liquidationEngine.connectSAFESaviour(address(0xabc)); // connecting mock savior

        uint safe = _generateUnsafeSafes(1);

        manager.protectSAFE(safe, address(liquidationEngine), address(0xabc));

        keeperProxy.liquidateAndSettleSAFE(manager.safes(safe));
    }
}