import { TransactionRequest } from './base-contract-api'

export interface AbiDefinition {
    name: string
    // constant: boolean;
    // payable: boolean;
    stateMutability?: string
    inputs: AbiParameter[]
    outputs: AbiParameter[]
    type: string
}
export interface AbiParameter {
    name: string
    type: string
    internalType?: string
    components?: AbiParameter[]
}

export interface Inputs extends ReadonlyArray<any> {
    readonly [key: string]: any
}

export interface Outputs extends ReadonlyArray<any> {
    readonly [key: string]: any
}

export interface GebProviderInterface {
    /**
     * Given a transaction request, execute it readonly through the blockchain node.
     * @param  {TransactionRequest} transaction
     * @returns Promise<string> Raw hexadecimal contract output
     */
    ethCall(transaction: TransactionRequest): Promise<string>

    /**
     * Decode a hexadecimal contract response according to a function signature
     * @param  {string} data Raw hexadecimal contract response
     * @param  {AbiDefinition} abiFragment Function definition as an ABI fragment
     * @returns Outputs Smart contract output as per the ABI definition
     */
    decodeFunctionData(data: string, abiFragment: AbiDefinition): Outputs

    /**
     * @param  {Inputs} params Array of input parameter to the contract function
     * @param  {AbiDefinition} abiFragment Function definition as an ABI fragment
     * @returns string encoded hexadecimal value of the call
     */
    encodeFunctionData(params: Inputs, abiFragment: AbiDefinition): string

    chainId(): Promise<number>

    /**
     * Contract code hash from EIP 1052
     * @param address target contract
     */
    extCodeHash(address: string): Promise<string>
}
