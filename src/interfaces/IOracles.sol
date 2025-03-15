// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

interface IOracles {
    function getPrice(uint32 maxAge) external view returns (uint256 price, uint256 timestamp);

    function getPrice() external view returns (uint256 price, uint256 timestamp);

    function updatePythPrice(address sender, bytes[] calldata updatePriceData) external payable;
}
