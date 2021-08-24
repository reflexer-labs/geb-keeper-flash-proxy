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

import "../GebUniswapV3KeeperFlashProxyETH.sol";

contract GebUniswapV3KeeperFlashProxyETHTest is GebDeployTestBase, GebProxyIncentivesActions {
    GebSafeManager manager;
    GebUniswapV3KeeperFlashProxyETH keeperProxy;
    address payable token0;
    address payable token1;

    UniswapV3Pool raiETHPair;
    uint256 initETHRAIPairLiquidity = 5000 ether;            // 1250 USD
    uint256 initRAIETHPairLiquidity = 294672.324375E18;      // 1 RAI = 4.242 USD

    bytes32 collateralAuctionType = bytes32("FIXED_DISCOUNT");

    function setUp() override public {
        super.setUp();
        deployIndexWithCreatorPermissions(collateralAuctionType);
        safeEngine.modifyParameters("ETH", "debtCeiling", uint(0) - 1); // unlimited debt ceiling, enough liquidity is needed on Uniswap.
        safeEngine.modifyParameters("globalDebtCeiling", uint(0) - 1); // unlimited globalDebtCeiling

        manager = new GebSafeManager(address(safeEngine));

        // Setup Uniswap
        uint160 priceCoinToken0 = 103203672169272457649230733;
        uint160 priceCoinToken1 = 6082246497092770728082823737800;

        raiETHPair = UniswapV3Pool(_deployV3Pool(address(coin), address(weth), 3000));
        raiETHPair.initialize(address(coin) == raiETHPair.token0() ? priceCoinToken0 : priceCoinToken1);

        // Add pair liquidity
        uint safe = this.openSAFE(address(manager), "ETH", address(this));
        _lockETH(address(manager), address(ethJoin), safe, 5000 ether);
        _generateDebt(address(manager), address(taxCollector), address(coinJoin), safe, 1000000 ether, address(this));
        _addWhaleLiquidity();

        // zeroing balances
        coin.transfer(address(1), coin.balanceOf(address(this)));
        weth.transfer(address(1), weth.balanceOf(address(this)));

        // keeper Proxy
        keeperProxy = new GebUniswapV3KeeperFlashProxyETH(
            address(ethIncreasingDiscountCollateralAuctionHouse),
            address(weth),
            address(coin),
            address(raiETHPair),
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
        (uint160 sqrtRatioX96, , , , , , ) = raiETHPair.slot0();
        uint128 liq;
        if (address(coin) == raiETHPair.token0())
            liq = _getLiquidityAmountsForTicks(sqrtRatioX96, low, upp, initRAIETHPairLiquidity, initETHRAIPairLiquidity);
        else
            liq = _getLiquidityAmountsForTicks(sqrtRatioX96, low, upp, initETHRAIPairLiquidity, initRAIETHPairLiquidity);
        raiETHPair.mint(address(this), low, upp, liq, bytes(""));
    }

    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata
    ) external {
        uint coinAmount = address(coin) == raiETHPair.token0() ? amount0Owed : amount1Owed;
        uint collateralAmount = address(coin) == raiETHPair.token0() ? amount1Owed : amount0Owed;

        weth.deposit{value: collateralAmount}();
        weth.transfer(msg.sender, collateralAmount);
        coin.transfer(address(msg.sender), coinAmount);
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

    function testSettleAuction() public {
        uint auction = _collateralAuctionETH(1);
        uint previousBalance = address(this).balance;

        keeperProxy.settleAuction(auction);
        emit log_named_uint("Profit", address(this).balance - previousBalance);
        assertTrue(previousBalance < address(this).balance); // profit!

        (, uint amountToRaise,,,,,,,) = ethIncreasingDiscountCollateralAuctionHouse.bids(auction);
        assertEq(amountToRaise, 0);
    }

    uint[] auctions;
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