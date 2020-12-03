import { GebProviderInterface, AbiDefinition, Inputs } from './chain-provider-interface';
import { BigNumber } from '@ethersproject/bignumber';
export declare type TransactionRequest = {
    to?: string;
    from?: string;
    nonce?: number;
    gasLimit?: BigNumber;
    gasPrice?: BigNumber;
    data?: string;
    value?: BigNumber;
    chainId?: number;
};
export declare type MulticallRequest<ReturnType> = {
    abi: AbiDefinition;
    data: string;
    to: string;
};
export interface GebContractAPIConstructorInterface<T extends BaseContractAPI> {
    new (address: string, gebP: GebProviderInterface): T;
}
export declare class BaseContractAPI {
    address: string;
    chainProvider: GebProviderInterface;
    constructor(address: string, chainProvider: GebProviderInterface);
    protected ethCall(abiFragment: AbiDefinition, params: Inputs): Promise<any>;
    protected getTransactionRequest(abiFragment: AbiDefinition, params: Inputs, ethValue?: BigNumber): TransactionRequest;
    protected getMulticallRequest(abiFragment: AbiDefinition, params: Inputs): MulticallRequest<any>;
    protected ethCallOrMulticall(abiFragment: AbiDefinition, params: Inputs, multicall?: true): Promise<any> | MulticallRequest<any>;
}
