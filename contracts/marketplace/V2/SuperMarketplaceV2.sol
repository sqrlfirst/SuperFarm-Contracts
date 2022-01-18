// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.8;

import "./core/MarketplaceCore.sol";

/**
 * @title SuperMarketplace version 2.
 * @author Rostislav Khlebnikov
 */
contract SuperMarketplaceV2 is MarketplaceCore {
    string public constant name = "Super Marketplace";

    /**
        @param transferProxy  existing token transfer proxy  address.
        @param platformFeeRecipient  address of a platform fee recipient.
        @param platformFee platform fee amount in percents, e.g. 2% = 200.
     */
    constructor(
        address transferProxy,
        address payable platformFeeRecipient,
        uint256 platformFee
    )
        MarketplaceCore(
            transferProxy,
            platformFeeRecipient,
            platformFee,
            name,
            string(abi.encodePacked(version()))
        )
    {
        setPermit(_msgSender(), UNIVERSAL, FEE_CONFIG, type(uint256).max);
    }

    function version() public pure override returns (uint256) {
        return 2;
    }
}
