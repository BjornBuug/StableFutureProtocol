// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.28;

// solhint-disable named-return-values
interface IGasPriceOracle {
    function gasPrice() external view returns (uint256);

    function l1BaseFee() external view returns (uint256);

    function overhead() external view returns (uint256);

    function scalar() external view returns (uint256);

    function decimals() external view returns (uint256);

    function getL1Fee(bytes memory _data) external view returns (uint256);

    function getL1GasUsed(bytes memory _data) external view returns (uint256);
}
