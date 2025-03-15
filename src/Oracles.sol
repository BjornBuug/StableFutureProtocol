// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {StableFutureStructs} from "src/libraries/StableFutureStructs.sol";
import {StableFutureErrors} from "src/libraries/StableFutureErrors.sol";
import {StableFutureEvents} from "src/libraries/StableFutureEvents.sol";
import {StableModuleKeys} from "src/libraries/StableModuleKeys.sol";
import {ReentrancyGuardUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {ModuleUpgradeable} from "src/abstracts/ModuleUpgradeable.sol";
import {IStableFutureVault} from "src/interfaces/IStableFutureVault.sol";
import {IChainlinkAggregatorV3} from "src/interfaces/IChainlinkAggregatorV3.sol";
import {IPyth} from "pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "pyth-sdk-solidity/PythStructs.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";

contract Oracles is ReentrancyGuardUpgradeable, ModuleUpgradeable {
    address public asset; // Asset to price

    using SafeERC20 for IERC20;
    using SafeCast for *;
    using SignedMath for int256;

    // Structs that represent both PythNetowrkOracle, chainlinkOracle.
    StableFutureStructs.ChainlinkOracle public chainlinkOracle; // struct reference(assigning the struct to a variable)
    StableFutureStructs.PythNetworkOracle public pythNetworkOracle; // struct reference

    uint256 public maxPriceDiffPercent;

    /// @dev To prevent the implementation contract from being used, we invoke the _disableInitializers
    /// function in the constructor to automatically lock it when it is deployed.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the OracleModule.
     * @param _asset The asset contract.
     * @param _vault The vault contract.
     * @param _newchainlinkOracle The new chainlinkOracle struct.
     * @param _newPythNetworkOracle The new PythNetworkOracle struct.
     * @param _maxPriceDiffPercent The maximum price difference percentage.
     */
    function initialize(
        address _asset,
        IStableFutureVault _vault,
        StableFutureStructs.ChainlinkOracle calldata _newchainlinkOracle,
        StableFutureStructs.PythNetworkOracle calldata _newPythNetworkOracle,
        uint256 _maxPriceDiffPercent
    ) external initializer {
        __init_Module(StableModuleKeys._ORACLE_MODULE_KEY, _vault);
        __ReentrancyGuard_init();

        _setchainlinkOracle(_newchainlinkOracle);
        _setPythNetworkOracle(_newPythNetworkOracle);
        _setMaxPriceDiffPercent(_maxPriceDiffPercent);
        _setAsset(_asset);
    }

    function updatePythPrice(address sender, bytes[] calldata updatePriceData) external payable nonReentrant {
        // get the fees to pay for updatePriceData
        uint256 fee = pythNetworkOracle.pythNetworkContract.getUpdateFee(updatePriceData);

        // update the price
        pythNetworkOracle.pythNetworkContract.updatePriceFeeds{value: fee}(updatePriceData);

        // refund any remaining ETH
        if (msg.value - fee > 0) {
            (bool succ,) = sender.call{value: msg.value - fee}("");
            if (!succ) revert StableFutureErrors.RefundFailed();
        }
    }

    function getPrice(uint32 maxAge) external view returns (uint256 price, uint256 timestamp) {
        (price, timestamp) = _getPrice(maxAge);
    }

    function getPrice() external view returns (uint256 price, uint256 timestamp) {
        (price, timestamp) = _getPrice(type(uint32).max);
    }

    function _getPrice(uint32 maxAge) internal view returns (uint256 price, uint256 timestamp) {
        // 1- Retrieve both prices from both oracles
        (uint256 chainlinkTimestamp, uint256 chainlinkPrice) = _getChainlinkPrice();
        (uint256 pythPrice, bool invalidPythPrice, uint256 pythTimestamp) = _getPythNetworkPrice();

        bool pythPriceUsed;

        // 2- calculate the diff of between both prices.
        uint256 priceDiff = (int256(chainlinkPrice) - int256(pythPrice)).abs(); // take unsigned value and return signe value(SignedMath)

        // 3- Calculate the percentage of the priceDiff
        uint256 priceDiffPercent = ((priceDiff * 1e18) / chainlinkPrice); // 5%, 3%, 4% etc

        // 4- check if the priceDiffPercent is not greater than maxDiffPrice
        if (priceDiffPercent > maxPriceDiffPercent) {
            revert StableFutureErrors.ExcessivePriceDeviation(priceDiffPercent);
        }

        // check which the price is the most fresh based on validity and time
        if (invalidPythPrice = false) {
            if (pythTimestamp >= chainlinkTimestamp) {
                price = pythPrice;
                timestamp = pythTimestamp;
                pythPriceUsed = true;
            } else {
                price = chainlinkPrice;
                timestamp = chainlinkTimestamp;
            }
        } else {
            price = chainlinkPrice;
            timestamp = chainlinkTimestamp;
        }

        if (timestamp + maxAge < block.timestamp) {
            revert StableFutureErrors.PriceStale(
                pythPriceUsed
                    ? StableFutureErrors.PriceSource.pythOracle
                    : StableFutureErrors.PriceSource.chainlinkOracle
            );
        }
    }

    function _getChainlinkPrice() internal view returns (uint256 timestamp, uint256 price) {
        // Get the contract address of chainlink contract associtated with the pair
        IChainlinkAggregatorV3 oracle = chainlinkOracle.chainlinkOracle;

        if (address(oracle) == address(0)) {
            revert StableFutureErrors.ZeroAddress("oracle");
        }

        // get the price using latestRoundData
        (, int256 answer,, uint256 updatedAt,) = oracle.latestRoundData();

        // Check if the price is stale or within a certain freshness window
        if (block.timestamp - updatedAt > chainlinkOracle.maxAge) {
            revert StableFutureErrors.PriceStale(StableFutureErrors.PriceSource.chainlinkOracle); // add which price is stale
        }

        if (answer > 0) {
            price = uint256(answer) * (10 ** 10); // convert the return value from 8 to 18 decimals
            timestamp = updatedAt;
        } else {
            revert StableFutureErrors.InvalidPrice(StableFutureErrors.PriceSource.chainlinkOracle);
        }
    }

    function _getPythNetworkPrice() internal view returns (uint256 price, bool invalid, uint256 timestamp) {
        // get the Pyth oracle address contract
        IPyth oracle = pythNetworkOracle.pythNetworkContract;

        if (address(oracle) == address(0)) {
            revert StableFutureErrors.ZeroAddress("oracle");
        }

        // get the price
        try oracle.getPriceNoOlderThan(pythNetworkOracle.priceId, pythNetworkOracle.maxAge) returns (
            PythStructs.Price memory oracleData
        ) {
            // Check if the price is not invalid based on the passed params to getPriceNoOlderThan
            if (oracleData.price > 0 && oracleData.conf > 0 && oracleData.expo < 0) {
                // scale the price to 18 decimals
                price = ((oracleData.price).toUint256()) * (10 ** (18 + oracleData.expo).toUint256());

                timestamp = oracleData.publishTime;

                // check if the price is accurate(respecte the minimum price confidence)
                // Devide the returns price but the returned confidence
                // conf price should always be greater than minConfiRatio
                if (oracleData.price / int64(oracleData.conf) < int32(pythNetworkOracle.minConfidenceRatio)) {
                    invalid = true;
                }
            } else {
                invalid = true;
            }
        } catch {
            invalid = true; // // couldn't fetch the price with the asked input param
        }
    }

    /////////////////////////////////////////////
    //            Setter Functions             //
    /////////////////////////////////////////////

    /**
     * @dev Sets the chainlinkOracle configuration.
     * @param newOracle The new chainlinkOracle struct to be set.
     */
    function _setchainlinkOracle(StableFutureStructs.ChainlinkOracle calldata newOracle) internal {
        // Sanity checks
        if (address(newOracle.chainlinkOracle) == address(0) || newOracle.maxAge <= 0) {
            revert StableFutureErrors.InvalidOracleConfig();
        }

        // set chainLink oracle config to struct
        chainlinkOracle = StableFutureStructs.ChainlinkOracle(newOracle.chainlinkOracle, newOracle.maxAge);

        // Emit the event
        emit StableFutureEvents.NewchainlinkOracleSet(newOracle);
    }

    /**
     * @dev Sets the PythNetworkOracle configuration.
     * @param newOracle The new PythNetworkOracle struct to be set.
     */
    function _setPythNetworkOracle(StableFutureStructs.PythNetworkOracle calldata newOracle) internal {
        // Check the validity of these configs
        if (
            address(newOracle.pythNetworkContract) == address(0) || newOracle.priceId == bytes32(0)
                || newOracle.maxAge <= 0 || newOracle.minConfidenceRatio <= 0
        ) revert StableFutureErrors.InvalidOracleConfig();

        // Set new Pyth network config to struct
        pythNetworkOracle = StableFutureStructs.PythNetworkOracle(
            newOracle.pythNetworkContract, newOracle.priceId, newOracle.maxAge, newOracle.minConfidenceRatio
        );

        emit StableFutureEvents.NewPythNetworkOracleSet(newOracle);
    }

    /**
     * @dev Sets the asset address.
     * @param _asset The new asset address to be set.
     */
    function _setAsset(address _asset) internal {
        if (_asset == address(0)) {
            revert StableFutureErrors.ZeroAddress("newAsset");
        }

        asset = _asset;

        emit StableFutureEvents.AssetSet(_asset);
    }

    /**
     * @dev the priceDiff between chainlink and Pyth must be bewteen 0(no difference is tolerated) and
     *            maxPriceDiffPerecent(any difference is acceptable) 1e18 = 100%
     * @dev Sets the maximum price difference percentage.
     * @param _maxPriceDiffPercent The new maximum price difference percentage to be set.
     */
    function _setMaxPriceDiffPercent(uint256 _maxPriceDiffPercent) internal {
        if (_maxPriceDiffPercent == 0 || _maxPriceDiffPercent > 1e18) {
            revert StableFutureErrors.InvalidOracleConfig();
        }

        maxPriceDiffPercent = _maxPriceDiffPercent;

        emit StableFutureEvents.MaxPriceDiffPerecentSet(_maxPriceDiffPercent);
    }

    /////////////////////////////////////////////
    //             Owner Functions             //
    /////////////////////////////////////////////

    function setOracles(
        address _asset,
        StableFutureStructs.PythNetworkOracle calldata newPythOracle,
        StableFutureStructs.ChainlinkOracle calldata newChainlinkOracle
    ) external onlyVaultOwner {
        _setAsset(_asset);
        _setchainlinkOracle(newChainlinkOracle);
        _setPythNetworkOracle(newPythOracle);
    }

    function setNewMaxDiffPercent(uint256 _maxDiffPercent) external onlyVaultOwner {
        _setMaxPriceDiffPercent(_maxDiffPercent);
    }
}
