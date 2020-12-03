import { BigNumberish, BigNumber, FixedNumber } from '@ethersproject/bignumber'

// === Constants ===

/**
 * byte32 value for the "ETH-A" collateral
 */
const ETH_A =
    '0x4554482d41000000000000000000000000000000000000000000000000000000'

/**
 * 0x0 address or burn address
 */
const NULL_ADDRESS = '0x0000000000000000000000000000000000000000'

/**
 * Constant 10^18
 */
const WAD = BigNumber.from('1000000000000000000')

/**
 * Constant 10^27
 */
const RAY = BigNumber.from('1000000000000000000000000000')

/**
 * Constant 10^45
 */
const RAD = BigNumber.from('1000000000000000000000000000000000000000000000')

// ==== Utils functions ===

/**
 * Return a fixed number object from a RAD
 * @param  {BigNumberish} rad
 */
const radToFixed = (rad: BigNumberish) => {
    return FixedNumber.fromValue(BigNumber.from(rad), 45, 'fixed256x45')
}

/**
 * Return a fixed number object from a RAD
 * @param  {BigNumberish} rad
 */
const rayToFixed = (ray: BigNumberish) => {
    return FixedNumber.fromValue(BigNumber.from(ray), 27, 'fixed256x27')
}

/**
 * Return a fixed number object from a RAD
 * @param  {BigNumberish} wad
 */
const wadToFixed = (wad: BigNumberish) => {
    return FixedNumber.fromValue(BigNumber.from(wad), 18, 'fixed256x18')
}

/**
 * Multiply by the power of 10 !! Precision loss if shift < 0 !!
 * @param val Value to convert
 * @param shift Number of places to shift the decimal
 */
const decimalShift = (val: BigNumberish, shift: number) => {
    if (shift > 0) {
        return BigNumber.from(val).mul(BigNumber.from(10).pow(shift))
    } else if (shift < 0) {
        return BigNumber.from(val).div(BigNumber.from(10).pow(Math.abs(shift)))
    } else {
        BigNumber.from(val)
    }

    return BigNumber.from(val)
}

/**
 * Given any kind of error object from an Ethereum RPC. Will look for an error string from a solidity require statement. Returns null if not found.
 * @param  {any} RPC error object of any kind
 * @returns string
 */
const getRequireString = (error: any): string | null => {
    // Stringify to object
    let str: string
    try {
        str = JSON.stringify(error)
    } catch {
        return null
    }
    // Search for the require error string selector 0x08c379a0
    const hexerrorArray = str.match(/0x08c379a0[0-9a-fA-F]*/g)

    if (hexerrorArray) {
        // Convert from hex to UTF-8 string
        return decodeURIComponent(
            hexerrorArray[0].slice(12).replace(/[0-9a-f]{2}/g, '%$&')
        )
            .replace(/\0/g, '')
            .slice(2)
    } else {
        return null
    }
}

export {
    // Constants
    ETH_A,
    NULL_ADDRESS,
    WAD,
    RAY,
    RAD,
    //Utils
    wadToFixed,
    rayToFixed,
    radToFixed,
    decimalShift,
    getRequireString,
}
