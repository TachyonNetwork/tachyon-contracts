// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockLinkToken is ERC20 {
    constructor() ERC20("ChainLink Token", "LINK") {
        _mint(msg.sender, 1000000 * 10**18);
    }

    function transferAndCall(
        address to,
        uint256 value,
        bytes memory data
    ) public returns (bool success) {
        transfer(to, value);
        return true;
    }
}