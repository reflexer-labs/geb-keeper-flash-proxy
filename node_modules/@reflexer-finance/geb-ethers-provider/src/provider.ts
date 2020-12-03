import {
    GebProviderInterface,
    AbiDefinition,
    Inputs,
    Outputs,
    TransactionRequest,
} from '@reflexer-finance/geb-contract-base'
import { providers, utils } from 'ethers'
import { Result } from 'ethers/lib/utils'
import { isNumber } from 'util'

export class GebEthersProvider implements GebProviderInterface {
    constructor(public provider: providers.Provider) {}

    private processEthersResults(results: Result): any {
        if (results.length === 0) {
            return []
        } else if (results.length === 1) {
            return results[0]
        } else {
            // Do this to remove positional references
            let ret: any = {}
            for (let key in results) {
                if (isNumber(key)) continue
                ret[key] = results[key]
            }

            return ret
        }
    }

    async ethCall(transaction: TransactionRequest): Promise<string> {
        return this.provider.call(transaction)
    }

    decodeFunctionData(data: string, abiFragment: AbiDefinition): Outputs {
        const coder = new utils.Interface([abiFragment])
        const result = coder.decodeFunctionResult(abiFragment.name, data)
        return this.processEthersResults(result)
    }

    encodeFunctionData(params: Inputs[], abiFragment: AbiDefinition): string {
        const coder = new utils.Interface([abiFragment])
        return coder.encodeFunctionData(abiFragment.name, params)
    }

    async chainId(): Promise<number> {
        return (await this.provider.getNetwork()).chainId
    }

    async extCodeHash(address: string): Promise<string> {
        const code = await this.provider.getCode(address)
        return utils.keccak256(code)
    }
}
