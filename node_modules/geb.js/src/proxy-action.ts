import {
    GebProviderInterface,
    ContractList,
    GebDeployment,
    getAddressList,
} from '@reflexer-finance/geb-contract-base'
import { TransactionRequest } from '@reflexer-finance/geb-contract-base'
import { BytesLike } from '@ethersproject/bytes'
import { BigNumberish } from '@ethersproject/bignumber'
import { BigNumber } from '@ethersproject/bignumber'

import {
    GebProxyActions as GebProxyActionsCore,
    DsProxy,
    GebProxyActionsGlobalSettlement,
    GebProxyLeverageActions,
    GebProxyIncentivesActions,
} from '@reflexer-finance/geb-contract-api'
import { NULL_ADDRESS } from './utils'

/**
 * Convenience class to call functions from [GebProxyActions](https://github.com/reflexer-labs/geb-proxy-actions/blob/master/src/GebProxyActions.sol) through a proxy contract registered in the [GebProxyRegistry](https://github.com/reflexer-labs/geb-proxy-registry/blob/master/src/GebProxyRegistry.sol). These actions bundle multiple actions in one (e.g: open a safe + lock some ETH + draw some RAI).
 */
export class GebProxyActions {
    /**
     * Underlying proxy object. Can be use to make custom calls to the proxy using `proxy.execute()` function.
     * For the details of each function
     */
    public proxy: DsProxy

    /**
     * Address of the base proxy action contract.
     */
    public proxyActionCoreAddress: string

    /**
     * Address of the proxy action contract for global settlement.
     */
    public proxyActionGlobalSettlementAddress: string

    /**
     * Address of the proxy action contract for uniswap LP share staking.
     */
    public proxyActionIncentiveAddress: string

    /**
     * Address of the proxy action contract for leveraged with flash loans operations.
     */
    public proxyActionLeverageAddress: string

    private addressList: ContractList
    private proxyActionCore: GebProxyActionsCore
    private proxyActionGlobalSettlement: GebProxyActionsGlobalSettlement
    private proxyActionIncentive: GebProxyIncentivesActions
    private proxyActionLeverage: GebProxyLeverageActions
    constructor(
        /**
         * Address of the underlying proxy
         */
        public proxyAddress: string,
        network: GebDeployment,
        private chainProvider: GebProviderInterface
    ) {
        this.addressList = getAddressList(network)

        this.proxy = new DsProxy(proxyAddress, this.chainProvider)

        // Set proxy action contract addresses
        this.proxyActionCoreAddress = this.addressList.PROXY_ACTIONS
        this.proxyActionGlobalSettlementAddress = this.addressList.PROXY_ACTIONS_GLOBAL_SETTLEMENT
        this.proxyActionIncentiveAddress = this.addressList.INCENTIVE_PROXY_ACTIONS
        this.proxyActionLeverageAddress = this.addressList.LEVERAGE_PROXY_ACTION

        // Proxy contract APIs
        this.proxyActionCore = new GebProxyActionsCore(
            this.proxyActionCoreAddress,
            this.chainProvider
        )
        this.proxyActionGlobalSettlement = new GebProxyActionsGlobalSettlement(
            this.proxyActionGlobalSettlementAddress,
            this.chainProvider
        )
        this.proxyActionIncentive = new GebProxyIncentivesActions(
            this.proxyActionIncentiveAddress,
            this.chainProvider
        )
        this.proxyActionLeverage = new GebProxyLeverageActions(
            this.proxyActionLeverageAddress,
            this.chainProvider
        )
    }

    private getProxiedTransactionRequest(
        tx: TransactionRequest
    ): TransactionRequest {
        let ethValue = tx.value
        if (!ethValue) {
            ethValue = BigNumber.from('0')
        }

        if (tx.to === NULL_ADDRESS) {
            throw Error('This proxy action is not supported on this network')
        }

        return this.proxy.execute__AddressBytes(ethValue, tx.to, tx.data)
    }

    // ==== Proxy Action Core ====

    allowSAFE(
        safe: BigNumberish,
        usr: string,
        ok: BigNumberish
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.allowSAFE(
                this.addressList.SAFE_MANAGER,
                safe,
                usr,
                ok
            )
        )
    }

    approveSAFEModification(obj: string, usr: string): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.approveSAFEModification(obj, usr)
        )
    }

    coinJoin_join(
        apt: string,
        safeHandler: string,
        wad: BigNumberish
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.coinJoin_join(apt, safeHandler, wad)
        )
    }

    denySAFEModification(obj: string, usr: string): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.denySAFEModification(obj, usr)
        )
    }

    enterSystem(src: string, safe: BigNumberish): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.enterSystem(
                this.addressList.SAFE_MANAGER,
                src,
                safe
            )
        )
    }

    ethJoin_join(
        ethValue: BigNumberish,
        apt: string,
        safe: string
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.ethJoin_join(
                BigNumber.from(ethValue),
                apt,
                safe
            )
        )
    }

    exitETH(safe: BigNumberish, wad: BigNumberish): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.exitETH(
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_JOIN_ETH_A,
                safe,
                wad
            )
        )
    }

    exitTokenCollateral(
        collateralJoin: string,
        safe: BigNumberish,
        amt: BigNumberish
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.exitTokenCollateral(
                this.addressList.SAFE_MANAGER,
                collateralJoin,
                safe,
                amt
            )
        )
    }

    freeETH(safe: BigNumberish, wad: BigNumberish): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.freeETH(
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_JOIN_ETH_A,
                safe,
                wad
            )
        )
    }

    freeTokenCollateral(
        collateralJoin: string,
        safe: BigNumberish,
        amt: BigNumberish
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.freeTokenCollateral(
                this.addressList.SAFE_MANAGER,
                collateralJoin,
                safe,
                amt
            )
        )
    }

    generateDebt(safe: BigNumberish, wad: BigNumberish): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.generateDebt(
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_TAX_COLLECTOR,
                this.addressList.GEB_COIN_JOIN,
                safe,
                wad
            )
        )
    }

    generateDebtAndProtectSAFE(
        safe: BigNumberish,
        wad: BigNumberish,
        saviour: string
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.generateDebtAndProtectSAFE(
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_TAX_COLLECTOR,
                this.addressList.GEB_COIN_JOIN,
                safe,
                wad,
                this.addressList.GEB_LIQUIDATION_ENGINE,
                saviour
            )
        )
    }

    lockETH(ethValue: BigNumberish, safe: BigNumberish): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.lockETH(
                BigNumber.from(ethValue),
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_JOIN_ETH_A,
                safe
            )
        )
    }

    lockETHAndGenerateDebt(
        ethValue: BigNumberish,
        safe: BigNumberish,
        deltaWad: BigNumberish
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.lockETHAndGenerateDebt(
                BigNumber.from(ethValue),
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_TAX_COLLECTOR,
                this.addressList.GEB_JOIN_ETH_A,
                this.addressList.GEB_COIN_JOIN,
                safe,
                deltaWad
            )
        )
    }

    lockTokenCollateral(
        collateralJoin: string,
        safe: BigNumberish,
        amt: BigNumberish,
        transferFrom: boolean
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.lockTokenCollateral(
                this.addressList.SAFE_MANAGER,
                collateralJoin,
                safe,
                amt,
                transferFrom
            )
        )
    }

    lockTokenCollateralAndGenerateDebt(
        collateralJoin: string,
        safe: BigNumberish,
        collateralAmount: BigNumberish,
        deltaWad: BigNumberish,
        transferFrom: boolean
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.lockTokenCollateralAndGenerateDebt(
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_TAX_COLLECTOR,
                collateralJoin,
                this.addressList.GEB_COIN_JOIN,
                safe,
                collateralAmount,
                deltaWad,
                transferFrom
            )
        )
    }

    lockTokenCollateralGenerateDebtAndProtectSAFE(
        collateralJoin: string,
        safe: BigNumberish,
        collateralAmount: BigNumberish,
        deltaWad: BigNumberish,
        transferFrom: boolean,
        saviour: string
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.lockTokenCollateralGenerateDebtAndProtectSAFE(
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_TAX_COLLECTOR,
                collateralJoin,
                this.addressList.GEB_COIN_JOIN,
                safe,
                collateralAmount,
                deltaWad,
                transferFrom,
                this.addressList.GEB_LIQUIDATION_ENGINE,
                saviour
            )
        )
    }

    makeCollateralBag(collateralJoin: string): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.makeCollateralBag(collateralJoin)
        )
    }

    modifySAFECollateralization(
        safe: BigNumberish,
        deltaCollateral: BigNumberish,
        deltaDebt: BigNumberish
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.modifySAFECollateralization(
                this.addressList.SAFE_MANAGER,
                safe,
                deltaCollateral,
                deltaDebt
            )
        )
    }

    moveSAFE(safeSrc: BigNumberish, safeDst: BigNumberish): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.moveSAFE(
                this.addressList.SAFE_MANAGER,
                safeSrc,
                safeDst
            )
        )
    }

    openLockETHAndGenerateDebt(
        ethValue: BigNumberish,
        collateralType: BytesLike,
        deltaWad: BigNumberish
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.openLockETHAndGenerateDebt(
                BigNumber.from(ethValue),
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_TAX_COLLECTOR,
                this.addressList.GEB_JOIN_ETH_A,
                this.addressList.GEB_COIN_JOIN,
                collateralType,
                deltaWad
            )
        )
    }

    openLockETHGenerateDebtAndProtectSAFE(
        ethValue: BigNumberish,
        collateralType: BytesLike,
        deltaWad: BigNumberish,
        saviour: string
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.openLockETHGenerateDebtAndProtectSAFE(
                BigNumber.from(ethValue),
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_TAX_COLLECTOR,
                this.addressList.GEB_JOIN_ETH_A,
                this.addressList.GEB_COIN_JOIN,
                collateralType,
                deltaWad,
                this.addressList.GEB_LIQUIDATION_ENGINE,
                saviour
            )
        )
    }

    openLockGNTAndGenerateDebt(
        gntJoin: string,
        collateralType: BytesLike,
        collateralAmount: BigNumberish,
        deltaWad: BigNumberish
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.openLockGNTAndGenerateDebt(
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_TAX_COLLECTOR,
                gntJoin,
                this.addressList.GEB_COIN_JOIN,
                collateralType,
                collateralAmount,
                deltaWad
            )
        )
    }

    openLockGNTGenerateDebtAndProtectSAFE(
        gntJoin: string,
        collateralType: BytesLike,
        collateralAmount: BigNumberish,
        deltaWad: BigNumberish,
        saviour: string
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.openLockGNTGenerateDebtAndProtectSAFE(
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_TAX_COLLECTOR,
                gntJoin,
                this.addressList.GEB_COIN_JOIN,
                collateralType,
                collateralAmount,
                deltaWad,
                this.addressList.GEB_LIQUIDATION_ENGINE,
                saviour
            )
        )
    }

    openLockTokenCollateralAndGenerateDebt(
        collateralJoin: string,
        collateralType: BytesLike,
        collateralAmount: BigNumberish,
        deltaWad: BigNumberish,
        transferFrom: boolean
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.openLockTokenCollateralAndGenerateDebt(
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_TAX_COLLECTOR,
                collateralJoin,
                this.addressList.GEB_COIN_JOIN,
                collateralType,
                collateralAmount,
                deltaWad,
                transferFrom
            )
        )
    }

    openLockTokenCollateralGenerateDebtAndProtectSAFE(
        collateralJoin: string,
        collateralType: BytesLike,
        collateralAmount: BigNumberish,
        deltaWad: BigNumberish,
        transferFrom: boolean,
        saviour: string
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.openLockTokenCollateralGenerateDebtAndProtectSAFE(
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_TAX_COLLECTOR,
                collateralJoin,
                this.addressList.GEB_COIN_JOIN,
                collateralType,
                collateralAmount,
                deltaWad,
                transferFrom,
                this.addressList.GEB_LIQUIDATION_ENGINE,
                saviour
            )
        )
    }

    openSAFE(collateralType: BytesLike, usr: string): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.openSAFE(
                this.addressList.SAFE_MANAGER,
                collateralType,
                usr
            )
        )
    }

    protectSAFE(safe: BigNumberish, saviour: string): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.protectSAFE(
                this.addressList.SAFE_MANAGER,
                safe,
                this.addressList.GEB_LIQUIDATION_ENGINE,
                saviour
            )
        )
    }

    quitSystem(safe: BigNumberish, dst: string): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.quitSystem(
                this.addressList.SAFE_MANAGER,
                safe,
                dst
            )
        )
    }

    repayAllDebt(safe: BigNumberish): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.repayAllDebt(
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_COIN_JOIN,
                safe
            )
        )
    }

    repayAllDebtAndFreeETH(
        safe: BigNumberish,
        collateralWad: BigNumberish
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.repayAllDebtAndFreeETH(
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_JOIN_ETH_A,
                this.addressList.GEB_COIN_JOIN,
                safe,
                collateralWad
            )
        )
    }

    repayAllDebtAndFreeTokenCollateral(
        collateralJoin: string,
        safe: BigNumberish,
        collateralAmount: BigNumberish
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.repayAllDebtAndFreeTokenCollateral(
                this.addressList.SAFE_MANAGER,
                collateralJoin,
                this.addressList.GEB_COIN_JOIN,
                safe,
                collateralAmount
            )
        )
    }

    repayDebt(safe: BigNumberish, wad: BigNumberish): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.repayDebt(
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_COIN_JOIN,
                safe,
                wad
            )
        )
    }

    repayDebtAndFreeETH(
        safe: BigNumberish,
        collateralWad: BigNumberish,
        deltaWad: BigNumberish
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.repayDebtAndFreeETH(
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_JOIN_ETH_A,
                this.addressList.GEB_COIN_JOIN,
                safe,
                collateralWad,
                deltaWad
            )
        )
    }

    repayDebtAndFreeTokenCollateral(
        collateralJoin: string,
        safe: BigNumberish,
        collateralAmount: BigNumberish,
        deltaWad: BigNumberish
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.repayDebtAndFreeTokenCollateral(
                this.addressList.SAFE_MANAGER,
                collateralJoin,
                this.addressList.GEB_COIN_JOIN,
                safe,
                collateralAmount,
                deltaWad
            )
        )
    }

    safeLockETH(
        ethValue: BigNumberish,
        safe: BigNumberish,
        owner: string
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.safeLockETH(
                BigNumber.from(ethValue),
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_JOIN_ETH_A,
                safe,
                owner
            )
        )
    }

    safeLockTokenCollateral(
        collateralJoin: string,
        safe: BigNumberish,
        amt: BigNumberish,
        transferFrom: boolean,
        owner: string
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.safeLockTokenCollateral(
                this.addressList.SAFE_MANAGER,
                collateralJoin,
                safe,
                amt,
                transferFrom,
                owner
            )
        )
    }

    safeRepayAllDebt(safe: BigNumberish, owner: string): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.safeRepayAllDebt(
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_COIN_JOIN,
                safe,
                owner
            )
        )
    }

    safeRepayDebt(
        safe: BigNumberish,
        wad: BigNumberish,
        owner: string
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.safeRepayDebt(
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_COIN_JOIN,
                safe,
                wad,
                owner
            )
        )
    }

    tokenCollateralJoin_join(
        apt: string,
        safe: string,
        amt: BigNumberish,
        transferFrom: boolean
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.tokenCollateralJoin_join(
                apt,
                safe,
                amt,
                transferFrom
            )
        )
    }

    transfer(
        collateral: string,
        dst: string,
        amt: BigNumberish
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.transfer(collateral, dst, amt)
        )
    }

    transferCollateral(
        safe: BigNumberish,
        dst: string,
        wad: BigNumberish
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.transferCollateral(
                this.addressList.SAFE_MANAGER,
                safe,
                dst,
                wad
            )
        )
    }

    transferInternalCoins(
        safe: BigNumberish,
        dst: string,
        rad: BigNumberish
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.transferInternalCoins(
                this.addressList.SAFE_MANAGER,
                safe,
                dst,
                rad
            )
        )
    }

    transferSAFEOwnership(safe: BigNumberish, usr: string): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.transferSAFEOwnership(
                this.addressList.SAFE_MANAGER,
                safe,
                usr
            )
        )
    }

    transferSAFEOwnershipToProxy(
        safe: BigNumberish,
        dst: string
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionCore.transferSAFEOwnershipToProxy(
                this.addressList.PROXY_REGISTRY,
                this.addressList.SAFE_MANAGER,
                safe,
                dst
            )
        )
    }

    // ==== Proxy Actions Global Settlement ====

    prepareCoinsForRedeemingGlobalSettlement(
        wad: BigNumberish
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionGlobalSettlement.prepareCoinsForRedeeming(
                this.addressList.GEB_COIN_JOIN,
                this.addressList.GEB_GLOBAL_SETTLEMENT,
                wad
            )
        )
    }

    freeTokenCollateralGlobalSettlement(
        collateralJoin: string,
        safe: BigNumberish
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionGlobalSettlement.freeTokenCollateral(
                this.addressList.SAFE_MANAGER,
                collateralJoin,
                this.addressList.GEB_GLOBAL_SETTLEMENT,
                safe
            )
        )
    }

    redeemETHGlobalSettlement(
        ethJoin: string,
        collateralType: BytesLike,
        wad: BigNumberish
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionGlobalSettlement.redeemETH(
                ethJoin,
                this.addressList.GEB_GLOBAL_SETTLEMENT,
                collateralType,
                wad
            )
        )
    }

    redeemTokenCollateralGlobalSettlement(
        collateralJoin: string,
        collateralType: BytesLike,
        wad: BigNumberish
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionGlobalSettlement.redeemTokenCollateral(
                collateralJoin,
                this.addressList.GEB_GLOBAL_SETTLEMENT,
                collateralType,
                wad
            )
        )
    }

    // ==== Proxy Actions Incentive ====

    exitAndRemoveLiquidity(
        minTokenAmounts: [BigNumberish, BigNumberish]
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionIncentive.exitAndRemoveLiquidity(
                this.addressList.GEB_COIN_JOIN,
                this.addressList.GEB_UNISWAP_INCENTIVE,
                this.addressList.UNISWAP_ROUTER,
                minTokenAmounts
            )
        )
    }

    exitMine(incentives: string): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionIncentive.exitMine(incentives)
        )
    }

    exitRemoveLiquidityRepayDebt(
        safe: BigNumberish,
        minTokenAmounts: [BigNumberish, BigNumberish]
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionIncentive.exitRemoveLiquidityRepayDebt(
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_COIN_JOIN,
                safe,
                this.addressList.GEB_UNISWAP_INCENTIVE,
                this.addressList.UNISWAP_ROUTER,
                minTokenAmounts
            )
        )
    }

    exitRemoveLiquidityRepayDebtFreeETH(
        safe: BigNumberish,
        ethToFree: BigNumberish,
        minTokenAmounts: [BigNumberish, BigNumberish]
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionIncentive.exitRemoveLiquidityRepayDebtFreeETH(
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_JOIN_ETH_A,
                this.addressList.GEB_COIN_JOIN,
                safe,
                this.addressList.GEB_UNISWAP_INCENTIVE,
                ethToFree,
                this.addressList.UNISWAP_ROUTER,
                minTokenAmounts
            )
        )
    }

    generateDebtAndProvideLiquidityStake(
        ethValue: BigNumberish,
        safe: BigNumberish,
        wad: BigNumberish,
        minTokenAmounts: [BigNumberish, BigNumberish]
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionIncentive.generateDebtAndProvideLiquidityStake(
                BigNumber.from(ethValue),
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_TAX_COLLECTOR,
                this.addressList.GEB_COIN_JOIN,
                this.addressList.UNISWAP_ROUTER,
                this.addressList.GEB_UNISWAP_INCENTIVE,
                safe,
                wad,
                minTokenAmounts
            )
        )
    }

    generateDebtAndProvideLiquidityUniswap(
        ethValue: BigNumberish,
        safe: BigNumberish,
        wad: BigNumberish,
        minTokenAmounts: [BigNumberish, BigNumberish]
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionIncentive.generateDebtAndProvideLiquidityUniswap(
                BigNumber.from(ethValue),
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_TAX_COLLECTOR,
                this.addressList.GEB_COIN_JOIN,
                this.addressList.UNISWAP_ROUTER,
                safe,
                wad,
                minTokenAmounts
            )
        )
    }

    getLockedReward(campaignId: BigNumberish): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionIncentive.getLockedReward(
                this.addressList.GEB_UNISWAP_INCENTIVE,
                campaignId
            )
        )
    }

    harvestReward(campaignId: BigNumberish): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionIncentive.harvestReward(
                this.addressList.GEB_UNISWAP_INCENTIVE,
                campaignId
            )
        )
    }

    lockETHGenerateDebtProvideLiquidityStake(
        ethValue: BigNumberish,
        safe: BigNumberish,
        deltaWad: BigNumberish,
        liquidityWad: BigNumberish,
        minTokenAmounts: [BigNumberish, BigNumberish]
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionIncentive.lockETHGenerateDebtProvideLiquidityStake(
                BigNumber.from(ethValue),
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_TAX_COLLECTOR,
                this.addressList.GEB_JOIN_ETH_A,
                this.addressList.GEB_COIN_JOIN,
                this.addressList.UNISWAP_ROUTER,
                this.addressList.GEB_UNISWAP_INCENTIVE,
                safe,
                deltaWad,
                liquidityWad,
                minTokenAmounts
            )
        )
    }

    lockETHGenerateDebtProvideLiquidityUniswap(
        ethValue: BigNumberish,
        safe: BigNumberish,
        deltaWad: BigNumberish,
        liquidityWad: BigNumberish,
        minTokenAmounts: [BigNumberish, BigNumberish]
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionIncentive.lockETHGenerateDebtProvideLiquidityUniswap(
                BigNumber.from(ethValue),
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_TAX_COLLECTOR,
                this.addressList.GEB_JOIN_ETH_A,
                this.addressList.GEB_COIN_JOIN,
                this.addressList.UNISWAP_ROUTER,
                safe,
                deltaWad,
                liquidityWad,
                minTokenAmounts
            )
        )
    }

    openLockETHGenerateDebtProvideLiquidityStake(
        ethValue: BigNumberish,
        deltaWad: BigNumberish,
        collateralType: string,
        liquidityWad: BigNumberish,
        minTokenAmounts: [BigNumberish, BigNumberish]
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionIncentive.openLockETHGenerateDebtProvideLiquidityStake(
                BigNumber.from(ethValue),
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_TAX_COLLECTOR,
                this.addressList.GEB_JOIN_ETH_A,
                this.addressList.GEB_COIN_JOIN,
                this.addressList.UNISWAP_ROUTER,
                this.addressList.GEB_UNISWAP_INCENTIVE,
                collateralType,
                deltaWad,
                liquidityWad,
                minTokenAmounts
            )
        )
    }

    openLockETHGenerateDebtProvideLiquidityUniswap(
        ethValue: BigNumberish,
        deltaWad: BigNumberish,
        collateralType: string,
        liquidityWad: BigNumberish,
        minTokenAmounts: [BigNumberish, BigNumberish]
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionIncentive.openLockETHGenerateDebtProvideLiquidityUniswap(
                BigNumber.from(ethValue),
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_TAX_COLLECTOR,
                this.addressList.GEB_JOIN_ETH_A,
                this.addressList.GEB_COIN_JOIN,
                this.addressList.UNISWAP_ROUTER,
                collateralType,
                deltaWad,
                liquidityWad,
                minTokenAmounts
            )
        )
    }

    provideLiquidityUniswap(
        ethValue: BigNumberish,
        wad: BigNumberish,
        minTokenAmounts: [BigNumberish, BigNumberish]
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionIncentive.provideLiquidityUniswap(
                BigNumber.from(ethValue),
                this.addressList.GEB_COIN_JOIN,
                this.addressList.UNISWAP_ROUTER,
                wad,
                minTokenAmounts
            )
        )
    }

    removeLiquidityUniswap(
        systemCoin: string,
        value: BigNumberish,
        minTokenAmounts: [BigNumberish, BigNumberish]
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionIncentive.removeLiquidityUniswap(
                this.addressList.UNISWAP_ROUTER,
                systemCoin,
                value,
                minTokenAmounts
            )
        )
    }

    stakeInMine(wad: BigNumberish): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionIncentive.stakeInMine(
                this.addressList.GEB_UNISWAP_INCENTIVE,
                wad
            )
        )
    }

    withdrawAndHarvest(
        value: BigNumberish,
        campaignId: BigNumberish
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionIncentive.withdrawAndHarvest(
                this.addressList.GEB_UNISWAP_INCENTIVE,
                value,
                campaignId
            )
        )
    }

    withdrawAndRemoveLiquidity(
        value: BigNumberish,
        minTokenAmounts: [BigNumberish, BigNumberish]
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionIncentive.withdrawAndRemoveLiquidity(
                this.addressList.GEB_COIN_JOIN,
                this.addressList.GEB_UNISWAP_INCENTIVE,
                value,
                this.addressList.UNISWAP_ROUTER,
                minTokenAmounts
            )
        )
    }

    withdrawFromMine(value: BigNumberish): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionIncentive.withdrawFromMine(
                this.addressList.GEB_UNISWAP_INCENTIVE,
                value
            )
        )
    }

    withdrawRemoveLiquidityRepayDebt(
        safe: BigNumberish,
        value: BigNumberish,
        minTokenAmounts: [BigNumberish, BigNumberish]
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionIncentive.withdrawRemoveLiquidityRepayDebt(
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_COIN_JOIN,
                safe,
                this.addressList.GEB_UNISWAP_INCENTIVE,
                value,
                this.addressList.UNISWAP_ROUTER,
                minTokenAmounts
            )
        )
    }

    withdrawRemoveLiquidityRepayDebtFreeETH(
        safe: BigNumberish,
        valueToWithdraw: BigNumberish,
        ethToFree: BigNumberish,
        minTokenAmounts: [BigNumberish, BigNumberish]
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionIncentive.withdrawRemoveLiquidityRepayDebtFreeETH(
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_JOIN_ETH_A,
                this.addressList.GEB_COIN_JOIN,
                safe,
                this.addressList.GEB_UNISWAP_INCENTIVE,
                valueToWithdraw,
                ethToFree,
                this.addressList.UNISWAP_ROUTER,
                minTokenAmounts
            )
        )
    }

    getRewards(campaignId: BigNumberish): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionIncentive.getRewards(
                this.addressList.GEB_UNISWAP_INCENTIVE,
                campaignId
            )
        )
    }

    provideLiquidityStake(
        ethValue: BigNumberish,
        wad: BigNumberish,
        minTokenAmounts: [BigNumberish, BigNumberish]
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionIncentive.provideLiquidityStake(
                ethValue,
                this.addressList.GEB_COIN_JOIN,
                this.addressList.UNISWAP_ROUTER,
                this.addressList.GEB_UNISWAP_INCENTIVE,
                wad,
                minTokenAmounts
            )
        )
    }

    withdrawHarvestRemoveLiquidity(
        amount: BigNumberish,
        campaignId: BigNumberish,
        minTokenAmounts: [BigNumberish, BigNumberish]
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionIncentive.withdrawHarvestRemoveLiquidity(
                this.addressList.GEB_UNISWAP_INCENTIVE,
                this.addressList.UNISWAP_ROUTER,
                this.addressList.GEB_COIN_JOIN,
                amount,
                campaignId,
                minTokenAmounts
            )
        )
    }

    // ==== Proxy Actions Leverage ====

    flashDeleverage(
        uniswapV2Pair: string,
        callbackProxy: string,
        safe: BigNumberish
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionLeverage.flashDeleverage(
                uniswapV2Pair,
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_JOIN_ETH_A,
                this.addressList.GEB_TAX_COLLECTOR,
                this.addressList.GEB_COIN_JOIN,
                this.addressList.ETH,
                callbackProxy,
                safe
            )
        )
    }

    flashDeleverageFreeETH(
        uniswapV2Pair: string,
        callbackProxy: string,
        safe: BigNumberish,
        amountToFree: BigNumberish
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionLeverage.flashDeleverageFreeETH(
                uniswapV2Pair,
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_JOIN_ETH_A,
                this.addressList.GEB_TAX_COLLECTOR,
                this.addressList.GEB_COIN_JOIN,
                this.addressList.ETH,
                callbackProxy,
                safe,
                amountToFree
            )
        )
    }

    flashLeverage(
        uniswapV2Pair: string,
        callbackProxy: string,
        safe: BigNumberish,
        leverage: BigNumberish
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionLeverage.flashLeverage(
                uniswapV2Pair,
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_JOIN_ETH_A,
                this.addressList.GEB_TAX_COLLECTOR,
                this.addressList.GEB_COIN_JOIN,
                this.addressList.ETH,
                callbackProxy,
                safe,
                leverage
            )
        )
    }

    lockETHLeverage(
        ethValue: BigNumberish,
        uniswapV2Pair: string,
        callbackProxy: string,
        safe: BigNumberish,
        leverage: BigNumberish
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionLeverage.lockETHLeverage(
                BigNumber.from(ethValue),
                uniswapV2Pair,
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_JOIN_ETH_A,
                this.addressList.GEB_TAX_COLLECTOR,
                this.addressList.GEB_COIN_JOIN,
                this.addressList.ETH,
                callbackProxy,
                safe,
                leverage
            )
        )
    }

    openLockETHLeverage(
        ethValue: BigNumberish,
        uniswapV2Pair: string,
        callbackProxy: string,
        leverage: BigNumberish
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionLeverage.openLockETHLeverage(
                BigNumber.from(ethValue),
                uniswapV2Pair,
                this.addressList.SAFE_MANAGER,
                this.addressList.GEB_JOIN_ETH_A,
                this.addressList.GEB_TAX_COLLECTOR,
                this.addressList.GEB_COIN_JOIN,
                this.addressList.ETH,
                callbackProxy,
                leverage
            )
        )
    }

    uniswapV2Call(
        _sender: string,
        _amount0: BigNumberish,
        _amount1: BigNumberish,
        _data: BytesLike
    ): TransactionRequest {
        return this.getProxiedTransactionRequest(
            this.proxyActionLeverage.uniswapV2Call(
                _sender,
                _amount0,
                _amount1,
                _data
            )
        )
    }
}
