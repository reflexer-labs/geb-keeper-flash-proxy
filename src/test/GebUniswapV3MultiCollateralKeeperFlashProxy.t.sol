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
import {GebProxyActions} from "geb-proxy-actions/GebProxyActions.sol";
import {GebProxyIncentivesActions} from "geb-proxy-actions/GebProxyIncentivesActions.sol";
import {GebProxyRegistry, DSProxyFactory, DSProxy} from "geb-proxy-registry/GebProxyRegistry.sol";
import {LiquidityAmounts} from "../uni/v3/libraries/LiquidityAmounts.sol";

import "../uni/v3/UniswapV3Factory.sol";
import "../uni/v3/UniswapV3Pool.sol";

import "../GebUniswapV3MultiCollateralKeeperFlashProxy.sol";

contract GebMCKeeperFlashProxyTest is GebDeployTestBase, GebProxyIncentivesActions {
    GebSafeManager manager;
    GebUniswapV3MultiCollateralKeeperFlashProxy keeperProxy;

    DSProxy proxy;
    address gebProxyActions;
    GebProxyRegistry registry;

    UniswapV3Factory uniswapFactory;
    // UniswapV3Router02 uniswapRouter;
    UniswapV3Pool raiETHPair;
    UniswapV3Pool raiCOLPair;

    uint256 initETHRAIPairLiquidity = 5000 ether;         // 1250 USD
    uint256 initRAIETHPairLiquidity = 294672.324375E18;   // 1 RAI = 4.242 USD

    uint[] safes;

    bytes32 collateralAuctionType = bytes32("FIXED_DISCOUNT");

    function setUp() override public {
        super.setUp();
        deployIndexWithCreatorPermissions(collateralAuctionType);
        safeEngine.modifyParameters("ETH", "debtCeiling", uint(0) - 1); // unlimited debt ceiling, enough liquidity is needed on Uniswap.
        safeEngine.modifyParameters("COL", "debtCeiling", uint(0) - 1); // unlimited debt ceiling, enough liquidity is needed on Uniswap.
        safeEngine.modifyParameters("globalDebtCeiling", uint(0) - 1);  // unlimited globalDebtCeiling

        DSProxyFactory factory = new DSProxyFactory();
        registry = new GebProxyRegistry(address(factory));
        gebProxyActions = address(new GebProxyActions());
        proxy = DSProxy(registry.build());
        manager = new GebSafeManager(address(safeEngine));

        // Setup Uniswap
        uint160 priceCoinToken0 = 103203672169272457649230733;
        uint160 priceCoinToken1 = 6082246497092770728082823737800;

        uniswapFactory = new UniswapV3Factory();
        raiETHPair = UniswapV3Pool(uniswapFactory.createPool(address(weth), address(coin), 3000));
        raiETHPair.initialize(address(coin) == raiETHPair.token0() ? priceCoinToken0 : priceCoinToken1);

        raiCOLPair = UniswapV3Pool(uniswapFactory.createPool(address(col), address(coin), 3000));
        raiCOLPair.initialize(address(coin) == raiCOLPair.token0() ? priceCoinToken0 : priceCoinToken1);

        // Add pair liquidity ETH
        uint safe = this.openSAFE(address(manager), "ETH", address(this));
        _lockETH(address(manager), address(ethJoin), safe, 5000 ether);
        _generateDebt(address(manager), address(taxCollector), address(coinJoin), safe, 1000000 ether, address(this));
        _addWhaleLiquidity(address(weth));
        // Add pair liquidity COL
        _addWhaleLiquidity(address(col));

        // zeroing balances
        coin.transfer(address(1), coin.balanceOf(address(this)));
        weth.transfer(address(1), weth.balanceOf(address(this)));
        col.transfer(address(1), weth.balanceOf(address(this)));

        // keeper Proxy
        keeperProxy = new GebUniswapV3MultiCollateralKeeperFlashProxy(
            address(weth),
            address(coin),
            address(coinJoin),
            address(liquidationEngine)
        );
    }

    // --- Utils ---
    function lockTokenCollateralAndGenerateDebt(address, address, address, address, uint, uint, uint, bool) public {
        proxy.execute(gebProxyActions, msg.data);
    }
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
    function _generateUnsafeCOLSafe() internal returns (uint safe) {
        this.modifyParameters(address(liquidationEngine), "COL", "liquidationQuantity", rad(100 ether));
        this.modifyParameters(address(liquidationEngine), "COL", "liquidationPenalty", WAD);

        col.mint(1 ether);
        safe = this.openSAFE(address(manager), "COL", address(proxy));
        col.approve(address(proxy), 1 ether);
        this.lockTokenCollateralAndGenerateDebt(address(manager), address(taxCollector), address(colJoin), address(coinJoin), safe, 1 ether, 40 ether, true);

        orclCOL.updateResult(uint(40 * 10 ** 18)); // Force liquidation
        oracleRelayer.updateCollateralPrice("COL");
    }

    function _addWhaleLiquidity(address token) internal {
        UniswapV3Pool pool = UniswapV3Pool(uniswapFactory.getPool(token, address(coin), 3000));
        int24 low = -887220;
        int24 upp = 887220;
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        uint128 liq;
        if (address(coin) == pool.token0())
            liq = _getLiquidityAmountsForTicks(sqrtRatioX96, low, upp, initRAIETHPairLiquidity, initETHRAIPairLiquidity);
        else
            liq = _getLiquidityAmountsForTicks(sqrtRatioX96, low, upp, initETHRAIPairLiquidity, initRAIETHPairLiquidity);

        pool.mint(address(this), low, upp, liq, abi.encode(token));
    }

    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata
    ) external {
        UniswapV3Pool pool = UniswapV3Pool(msg.sender);
        uint coinAmount = address(coin) == pool.token0() ? amount0Owed : amount1Owed;
        uint collateralAmount = address(coin) == pool.token0() ? amount1Owed : amount0Owed;

        if (msg.sender == address(raiETHPair)) {
            weth.deposit{value: collateralAmount}();
            weth.transfer(msg.sender, collateralAmount);
        } else if (msg.sender == address(raiCOLPair)) {
            col.mint(msg.sender, collateralAmount);
        }
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


    // --- Tests ---
    function testSettleETHAuction() public {
        uint auction = _collateralAuctionETH(1);
        uint previousBalance = address(this).balance;

        keeperProxy.settleAuction(CollateralJoinLike(address(ethJoin)), auction, address(raiETHPair));
        emit log_named_uint("Profit", address(this).balance - previousBalance);
        assertTrue(previousBalance < address(this).balance); // profit!

        (, uint amountToRaise,,,,,,,) = ethIncreasingDiscountCollateralAuctionHouse.bids(auction);
        assertEq(amountToRaise, 0);
    }

    function testFailSettleAuctionTwice() public {
        uint auction = _collateralAuctionETH(1);
        keeperProxy.settleAuction(CollateralJoinLike(address(ethJoin)), auction, address(raiETHPair));
        keeperProxy.settleAuction(CollateralJoinLike(address(ethJoin)), auction, address(raiETHPair));
    }

    function testLiquidateAndSettleETHSAFE() public {
        uint safe = _generateUnsafeSafes(1);
        uint previousBalance = address(this).balance;

        uint auction = keeperProxy.liquidateAndSettleSAFE(CollateralJoinLike(address(ethJoin)), manager.safes(safe), address(raiETHPair));
        emit log_named_uint("Profit", address(this).balance - previousBalance);
        assertTrue(previousBalance < address(this).balance); // profit!

        (, uint amountToRaise,,,,,,,) = ethIncreasingDiscountCollateralAuctionHouse.bids(auction);
        assertEq(amountToRaise, 0);
    }

    function testLiquidateAndSettleTokenCollateralSAFE() public {
        uint safe = _generateUnsafeCOLSafe();
        uint previousBalance = col.balanceOf(address(this));

        uint auction = keeperProxy.liquidateAndSettleSAFE(CollateralJoinLike(address(colJoin)), manager.safes(safe), address(raiCOLPair));
        emit log_named_uint("Profit", col.balanceOf(address(this)) - previousBalance);
        assertTrue(previousBalance < col.balanceOf(address(this))); // profit!

        (, uint amountToRaise,,,,,,,) = colIncreasingDiscountCollateralAuctionHouse.bids(auction);
        assertEq(amountToRaise, 0);
    }

    function testSettleTokenCollateralAuction() public {
        uint safe = _generateUnsafeCOLSafe();
        uint auction = liquidationEngine.liquidateSAFE("COL", manager.safes(safe));

        uint previousBalance = col.balanceOf(address(this));

        keeperProxy.settleAuction(CollateralJoinLike(address(colJoin)), auction, address(raiCOLPair));
        emit log_named_uint("Profit", col.balanceOf(address(this)) - previousBalance);
        assertTrue(previousBalance < col.balanceOf(address(this))); // profit!

        (, uint amountToRaise,,,,,,,) = colIncreasingDiscountCollateralAuctionHouse.bids(auction);
        assertEq(amountToRaise, 0);
    }
}
