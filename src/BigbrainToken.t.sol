// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "ds-test/test.sol";
import "./BigBrainToken.sol";
contract BigbrainTest is DSTest {
    BigBrainToken bigbrainToken;
    // address test1Address = 0x7fFcAc23016d7a6348F1F39Ca10bbC4435407523;
    // address test2Address = 0xc16BEb165bd58E32995040c39C9151E1565D569E;
    // uint8 amount = 111;

    function setUp() public {
        bigbrainToken = new BigBrainToken();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }

    function testMax() public {
        emit log_uint(~uint256(0));
    }
}
