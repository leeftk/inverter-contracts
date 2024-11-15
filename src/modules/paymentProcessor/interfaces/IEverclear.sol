pragma solidity ^0.8.0;

interface IEverclearSpoke {
    function newIntent(
        uint32[] memory destinations,
        address to,
        address inputAsset,
        address outputAsset,
        uint amount,
        uint24 maxFee,
        uint48 ttl,
        bytes memory data
    ) external returns (bytes32 intentId, uint amountOut);
}
