// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract MockOracle {
    mapping(bytes32 => address) private pendingRequests;

    event OracleRequest(
        bytes32 indexed specId,
        address requester,
        bytes32 requestId,
        uint256 payment,
        address callbackAddr,
        bytes4 callbackFunctionId,
        uint256 cancelExpiration,
        uint256 dataVersion,
        bytes data
    );

    function oracleRequest(
        address sender,
        uint256 payment,
        bytes32 specId,
        address callbackAddress,
        bytes4 callbackFunctionId,
        uint256 nonce,
        uint256 dataVersion,
        bytes calldata data
    ) external returns (bytes32 requestId) {
        requestId = keccak256(abi.encodePacked(sender, nonce));
        pendingRequests[requestId] = callbackAddress;

        emit OracleRequest(
            specId, sender, requestId, payment, callbackAddress, callbackFunctionId, 0, dataVersion, data
        );

        // For testing, immediately fulfill the request with mock data
        // This simulates the oracle response
        (bool success,) = callbackAddress.call(
            abi.encodeWithSelector(callbackFunctionId, requestId, bytes32(uint256(85))) // Mock AI score of 85
        );
        require(success, "Callback failed");

        return requestId;
    }
}
