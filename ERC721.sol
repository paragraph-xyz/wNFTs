// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./FeeManager.sol";

contract ERC721 is
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ReentrancyGuard,
    OwnableUpgradeable
{
    using StringsUpgradeable for uint256;
    using CountersUpgradeable for CountersUpgradeable.Counter;

    CountersUpgradeable.Counter private _tokenIdCounter;

    event FeeManagerChanged(
        address indexed oldFeeManager,
        address indexed newFeeManager
    );

    event Minted(address indexed to, uint256 indexed tokenId);

    event BaseURIChanged(string baseURI);

    address public feeManager;

    /**
     * The address of the user that originally
     * referred the creator to the platform.
     */
    address public creatorReferrer;

    /// @notice the supply of the NFT.
    uint256 public maxSupply;

    /// @notice the price in wei of the NFT.
    uint256 public priceWei;

    /// @notice the new baseURI
    string public baseURI;

    /// @notice initialize the contract with the given name and symbol
    /// @param name_ the name of the collection
    /// @param symbol_ the symbol of the collection
    /// @param maxSupply_ The total number of possible NFTs in the collection.
    /// @param priceWei_ The price of the NFT in wei.
    function initialize(
        address _feeManagerAddress,
        address _creatorReferrerAddress,
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        uint256 maxSupply_,
        uint256 priceWei_
    ) public initializer {
        __ERC721_init(name_, symbol_);
        __ERC721Enumerable_init();
        __Ownable_init();
        maxSupply = maxSupply_;
        priceWei = priceWei_;
        baseURI = baseURI_;
        feeManager = _feeManagerAddress;
        creatorReferrer = _creatorReferrerAddress;
    }

    /**
     * This occurs the first time the contract is minted.
     * It is a special case because we need to preserve provenence only
     * for the very first NFT that's minted, or else OpenSea and other platforms
     * incorrectly show someone else as an owner.
     */
    function firstMint(
        address owner,
        address minter,
        address mintReferrer
    ) public payable {
        uint256 tokenId = _tokenIdCounter.current();
        require(tokenId == 0, "First token already minted");

        // Transfer smart contract ownership to the owner
        transferOwnership(owner);

        // Then, mint the first NFT to the minter.
        mintWithReferrer(minter, mintReferrer);
    }

    /**
     * Minting, but with no referrer.
     * This is just an easier way to access mintWithReferrer.
     *
     * No need to specify nonReentrant here since it's just an internal
     * wrapper around mintWithReferrer (which has the reentrancy guard).
     */
    function mint(address to) public payable returns (uint256) {
        return mintWithReferrer(to, address(0));
    }

    /// @notice Mints the NFT to the 'to' address.
    /// @param to The address of the future owner of the NFT.
    function mintWithReferrer(
        address to,
        address mintReferrer
    ) public payable nonReentrant returns (uint256) {
        require(totalSupply() < maxSupply, "Max supply reached");

        FeeManager feeManagerInstance = FeeManager(feeManager);

        require(
            feeManagerInstance.isInitialized(),
            "FeeManager not initialized"
        );

        uint256 fee = feeManagerInstance.totalFeeAmount();

        require(msg.value >= priceWei + fee, "Not enough funds");

        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);

        if (fee > 0) {
            feeManagerInstance.distributeFee{value: fee}(
                to,
                owner(),
                mintReferrer == address(0) ? address(0) : mintReferrer,
                creatorReferrer == address(0) ? address(0) : creatorReferrer
            );
        }

        uint256 payout = msg.value - fee;

        if (payout > 0) {
            (bool success, ) = payable(owner()).call{value: payout}("");
            require(success, "Transfer failed");
        }

        emit Minted(to, tokenId);

        return tokenId;
    }

    /**
     * @notice Sets a new fee manager
     * @param newFeeManager The address of the new fee manager
     */
    function setFeeManager(address newFeeManager) public onlyOwner {
        require(newFeeManager != address(0), "New fee manager is zero address");
        require(
            newFeeManager != feeManager,
            "New fee manager is same as current"
        );

        emit FeeManagerChanged(feeManager, newFeeManager);

        feeManager = newFeeManager;
    }

    /**
     * Calculate total mint price (price of the NFT plus all associated fees).
     */
    function getTotalMintPrice() public view returns (uint256) {
        return priceWei + getMintFee();
    }

    /**
     * Calculate the total fee amount (including referral fees).
     */
    function getMintFee() public view returns (uint256) {
        return FeeManager(feeManager).totalFeeAmount();
    }

    function setBaseURI(string memory baseURI_) public nonReentrant onlyOwner {
        emit BaseURIChanged(baseURI_);
        baseURI = baseURI_;
    }

    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        require(_exists(tokenId), "Token doesn't exist");

        return
            string(
                abi.encodePacked(
                    baseURI,
                    StringsUpgradeable.toHexString(address(this)),
                    "/token/",
                    tokenId.toString()
                )
            );
    }

    function contractURI() public view returns (string memory) {
        return
            string.concat(
                baseURI,
                StringsUpgradeable.toHexString(address(this))
            );
    }

    // The following functions are overrides required by Solidity.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
