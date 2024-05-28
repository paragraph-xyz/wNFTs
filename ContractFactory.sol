// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "./ERC721.sol";

import "./FeeManager.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ERC721Factory is ReentrancyGuard {
    address public implementation;
    address public feeManager;

    // Mapping frmo the signature of the NFT
    // which is sha256(postID, from, to) to the address of the NFT.
    mapping(bytes32 => address) public postToAddress;

    /// @notice the default contractURI.
    string constant _contractURI =
        "https://paragraph.xyz/api/crypto/highlights/contract/";

    constructor(address _feeManagerImplementation) {
        implementation = address(new ERC721());
        feeManager = _feeManagerImplementation;
    }

    // Need to use a struct to avoid "stack too deep" errors in the createAndMint method.
    struct MintData {
        string name_;
        string symbol_;
        address ownerAddr;
        address minterAddr;
        address creatorReferrerAddr;
        uint256 maxSupply;
        uint256 priceWei;
    }

    event ContractDeployed(
        MintData mintData,
        address indexed clone,
        string postId,
        uint256 from,
        uint256 to
    );

    function _createCloneAndInitialize(
        MintData memory mintData
    ) internal returns (address) {
        address clone = Clones.clone(implementation);

        ERC721(clone).initialize(
            address(feeManager),
            address(mintData.creatorReferrerAddr),
            mintData.name_,
            mintData.symbol_,
            _contractURI,
            mintData.maxSupply,
            mintData.priceWei
        );

        return clone;
    }

    // @notice Clones the implementation contract, transfers ownership to the ownerAddr, and mints
    // NFT to minterAddr.
    // @param ownerAddr The address of the owner of the contract (eg Paragraph creator).
    // @param minterAddr The address of the minter of the NFT (eg collector).
    // @param name_ The name of the NFT.
    // @param symbol_ The symbol of the NFT.
    // @param maxSupply The supply of the NFT.
    // @param priceWei The price of the NFT in wei.
    function createAndMint(
        MintData calldata mintData,
        address mintReferrerAddress,
        // This is used to construct a signature to keep track of the specific highlight being minted
        string memory postId,
        uint256 from,
        uint256 to
    ) external payable nonReentrant returns (address) {
        require(mintData.maxSupply > 0, "Need >0 supply");

        require(
            FeeManager(feeManager).isInitialized(),
            "FeeManager not initialized"
        );

        require(msg.value >= mintData.priceWei, "[factory] Not enough funds");

        bytes32 hash = keccak256(abi.encodePacked(postId, from, to));
        require(
            postToAddress[hash] == address(0),
            "[factory] NFT already exists"
        );

        address clone = _createCloneAndInitialize(mintData);

        // This method transfers ownership of the smart contract to the ownerAddr,
        // then mints an NFT to the owner, then finally transfers the NFT from the owner to the minter.
        //
        // We need to first mint to the other in order to establish provenence for the NFT.
        // (OpenSea and other platforms think "first NFT holder === owner".
        ERC721(clone).firstMint{value: msg.value}(
            mintData.ownerAddr,
            mintData.minterAddr,
            mintReferrerAddress
        );

        postToAddress[hash] = clone;
        emit ContractDeployed(mintData, clone, postId, from, to);

        return clone;
    }

    function getAddressFromPost(
        string memory postId,
        uint256 from,
        uint256 to
    ) external view returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(postId, from, to));
        return postToAddress[hash];
    }

    function getMintFee() public view returns (uint256) {
        return FeeManager(feeManager).totalFeeAmount();
    }
}
