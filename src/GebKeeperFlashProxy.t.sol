pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./GebKeeperFlashProxy.sol";

contract GebKeeperFlashProxyTest is DSTest {
    GebKeeperFlashProxy proxy;

    function setUp() public {
        proxy = new GebKeeperFlashProxy();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
