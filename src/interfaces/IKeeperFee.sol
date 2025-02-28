// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.28;

interface IKeeperFee {
    function getKeeperFee() external view returns (uint256 keeperFee);

    function getConfig()
        external
        view
        returns (
            uint256 profitMarginUSD,
            uint256 profitMarginPercent,
            uint256 minKeeperFeeUpperBound,
            uint256 minKeeperFeeLowerBound,
            uint256 gasUnitsL1,
            uint256 gasUnitsL2
        );

    function setParameters(uint256 keeperFeeUpperBound, uint256 keeperFeeLowerBound) external;
}
