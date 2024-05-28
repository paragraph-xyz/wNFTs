// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

//import "hardhat/console.sol";

contract FeeManager is OwnableUpgradeable {
    /**
     * The address of a Paragraph wallet that receives
     * platform fees.
     */
    address payable public feeRecipient;

    /**
     * The total amount in wei for ALL fees.
     * This is the sum of all other fee amounts.
     */
    uint256 public totalFeeAmount;

    /**
     * The amount in wei to send the fee recipient.
     */
    uint256 public platformFeeAmount;

    /**
     * The amount in wei to send the mint referrer.
     */
    uint256 public mintReferrerAmount;
    /**
     * The amount in wei to send the creator referrer.
     */
    uint256 public creatorReferrerAmount;
    /**
     * The amount in wei to send the creator.
     */
    uint256 public creatorAmount;

    bool public isInitialized;

    function initialize(
        address payable _feeRecipient,
        uint256 _platformFeeAmount,
        uint256 _creatorAmount,
        uint256 _mintReferrerAmount,
        uint256 _creatorReferrerAmount
    ) public initializer {
        __Ownable_init();
        // The Paragrpah recipient and fee amounts.
        feeRecipient = _feeRecipient;
        platformFeeAmount = _platformFeeAmount;

        // The amount to pay the creator.
        creatorAmount = _creatorAmount;

        // The amount to pay the user that referred
        // this specific mint.
        mintReferrerAmount = _mintReferrerAmount;

        // The amount to pay the the user that referred
        // the creator to originally create this NFT.
        creatorReferrerAmount = _creatorReferrerAmount;

        updateTotalFeeAmount();

        isInitialized = true;
    }

    function setFeeRecipient(address payable _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
    }

    function setPlatformFeeAmount(
        uint256 _platformFeeAmount
    ) external onlyOwner {
        platformFeeAmount = _platformFeeAmount;
        updateTotalFeeAmount();
    }

    function setMintReferrerAmount(uint256 _amount) external onlyOwner {
        mintReferrerAmount = _amount;
        updateTotalFeeAmount();
    }

    function setCreatorReferrerAmount(uint256 _amount) external onlyOwner {
        creatorReferrerAmount = _amount;
        updateTotalFeeAmount();
    }

    function setCreatorAmount(uint256 _amount) external onlyOwner {
        creatorAmount = _amount;
        updateTotalFeeAmount();
    }

    function updateTotalFeeAmount() internal {
        totalFeeAmount =
            platformFeeAmount +
            mintReferrerAmount +
            creatorReferrerAmount +
            creatorAmount;
    }

    /**
     * mintReferrer is the address that referred this specific mint
     * creatorReferrer is the address that originally referred the user
     */
    function distributeFee(
        /**
         * The address of the minter. They do NOT receive any fees,
         * but instead are passed in for logging purposes.
         */
        address minter,
        /**
         * The address of the creator of the NFT, that receievs
         * creator fees.
         */
        address creator,
        /**
         * The address of the mint referrer, that receives
         * mint referrer fees.
         */
        address mintReferrer,
        /**
         * The address of the creator referrer, that receives
         * creator referrer fees.
         */
        address creatorReferrer
    ) external payable {
        uint256 value = msg.value;
        require(value > 0, "FeeManager: Fee must be >0");
        require(value >= totalFeeAmount, "FeeManager: Not enough sent");

        bool success; // Declare it once here

        if (mintReferrer != address(0) && mintReferrerAmount > 0) {
            (success, ) = payable(mintReferrer).call{value: mintReferrerAmount}(
                ""
            );
            require(success, "Transfer to mintReferrer failed");
            emit FeeDistributed(
                minter,
                msg.sender,
                mintReferrer,
                mintReferrerAmount,
                "mintReferrer"
            );
            value -= mintReferrerAmount;
        }

        if (creatorReferrer != address(0) && creatorReferrerAmount > 0) {
            (success, ) = payable(creatorReferrer).call{
                value: creatorReferrerAmount
            }("");
            require(success, "Transfer to creatorReferrer failed");
            emit FeeDistributed(
                minter,
                msg.sender,
                creatorReferrer,
                creatorReferrerAmount,
                "creatorReferrer"
            );
            value -= creatorReferrerAmount;
        }

        if (creator != address(0) && creatorAmount > 0) {
            (success, ) = payable(creator).call{value: creatorAmount}("");
            require(success, "Transfer to creator failed");
            emit FeeDistributed(
                minter,
                msg.sender,
                creator,
                creatorAmount,
                "creator"
            );
            value -= creatorAmount;
        }

        (success, ) = payable(feeRecipient).call{value: value}("");
        require(success, "Transfer to feeRecipient failed");
        emit FeeDistributed(
            minter,
            msg.sender,
            feeRecipient,
            value,
            "feeRecipient"
        );
    }

    event FeeDistributed(
        /**
         * The address of the minter.
         */
        address indexed minter,
        /**
         * The address of the contract that called the distributeFee method.
         * Eg, the NFT contract.
         */
        address indexed caller,
        /**
         * The address of the recipient of the fee.
         * Can be Paragraph, the creator, or the referrer.
         */
        address indexed recipient,
        uint256 amount,
        /**
         * The type of the fee. Used to determine what
         * recipient is.
         */
        string feeType
    );
}
