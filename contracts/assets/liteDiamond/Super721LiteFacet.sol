// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;
import "@openzeppelin/contracts/utils/introspection/ERC165Storage.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../../access/PermitControlds.sol";
import "../../proxy/StubProxyRegistry.sol";
import "../../utils/Utils.sol";
import "./Super721LiteBlueprint.sol";

/**
  @title A lite ERC-721 item creation contract.
  @author Tim Clancy
  @author 0xthrpw
  @author Qazawat Zirak
  
  This contract represents the NFTs within a single collection. It allows for a
  designated collection owner address to manage the creation of NFTs within this
  collection. The collection owner grants approval to or removes approval from
  other addresses governing their ability to mint NFTs from this collection.
  
  This contract is forked from the inherited OpenZeppelin dependency, and uses
  ideas inherited from the Super721 reference implementation and ERC721A Azuki.
  
  January 15th, 2022.
*/
contract Super721LiteFacet is 
PermitControlds, ERC165Storage, IERC721, IERC721Enumerable, IERC721Metadata {

  using Address for address;

  /**
    An event that gets emitted when the metadata collection URI is changed.
    @param oldURI The old metadata URI.
    @param newURI The new metadata URI.
  */
  event ChangeURI(string indexed oldURI, string indexed newURI);

 /**
    An event that gets emitted when the contract URI is changed.
    
    @param oldURI The old metadata URI.
    @param newURI The new metadata URI.
  */
  event ChangeContractURI(string indexed oldURI, string indexed newURI);

  /**
    An event that gets emitted when the proxy registry address is changed.
    @param oldRegistry The old proxy registry address.
    @param newRegistry The new proxy registry address.
  */
  event ChangeProxyRegistry(address indexed oldRegistry,
    address indexed newRegistry);

  /**
    An event that gets emitted when the item collection is locked to further
    creation.
    @param locker The caller who locked the collection.
  */
  event CollectionLocked(address indexed locker);

  /**
    An event that gets emitted when a token ID has its on-chain metadata
    changed.
    @param changer The caller who triggered the metadata change.
    @param id The ID of the token which had its metadata changed.
    @param oldMetadata The old metadata of the token.
    @param newMetadata The new metadata of the token.
  */
  event MetadataChanged(address indexed changer, uint256 indexed id,
    string oldMetadata, string indexed newMetadata);

  /**
    An event that indicates we have set a permanent metadata URI for a token.
    @param _value The value of the permanent metadata URI.
    @param _id The token ID associated with the permanent metadata value.
  */
  event PermanentURI(string _value, uint256 indexed _id);

  /**
    An event that indicates we have set a permanent contract URI.
    @param _value The value of the permanent contract URI.
    @param _id The token ID associated with the permanent contract value.
  */
  event PermanentContractURI(string _value, uint256 indexed _id);

  /**
    A modifier which allows only the super-administrative owner or addresses
    with a specified valid right to perform a call on some specific item. Rights
    can be applied to the universal or item ID circumstance.

    @param _id The item ID on which we check for the validity of the specified
      `right`.
    @param _right The right to validate for the calling address. It must be
      non-expired and exist within the specified `_itemId`.
  */
  modifier hasItemRight(uint256 _id, bytes32 _right) {
    
    if (_msgSender() == owner()) {
      _;
    } else if (hasRight(_msgSender(), UNIVERSAL, _right)) {
      _;
    } else if (hasRight(_msgSender(), bytes32(_id), _right)) {
      _;
    } else {
      revert("Super721: caller has no right for that action");
    }
  }

  /** 
    A function that needs to be called immediately after deployment.
    Sets the owner of the newly deployed proxy.
  */
  function initialize() external initializer {
      __Ownable_init_unchained();
  }

/**
   * @dev Returns whether `tokenId` exists.
   *
   * Tokens can be managed by their owner or approved accounts via 
   * {approve} or {setApprovalForAll}.
   *
   * Tokens start existing when they are minted (`_mint`),
   */
  function _exists(uint256 tokenId) internal view 
  returns (bool) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    return tokenId < b.mintIndex;
  }

  /** 
    Get the ownership of a specific token.

    @param tokenId The token to check the owner for.
  */
  function ownershipOf(uint256 tokenId) internal view 
  returns (address) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    require(_exists(tokenId), 
      "ERC721: owner query for nonexistent token");

    uint256 lowestTokenToCheck;
    if (tokenId >= b.batchSize) {
      lowestTokenToCheck = tokenId - b.batchSize + 1;
    }

    for (uint256 curr = tokenId; curr >= lowestTokenToCheck; curr--) {
      address ownership = b.ownerships[curr];
      if (ownership != address(0)) {
        return ownership;
      }
    }

    revert("ERC721: ownership cannot be determined");
  }

  /**
   * @dev See {IERC721-ownerOf}.
   */
  function ownerOf(uint256 tokenId) public view 
  override returns (address) {

    return ownershipOf(tokenId);
  }

  /**
   * @dev See {IERC721-approve}.
   */
  function approve(address to, uint256 tokenId) public 
  virtual override {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    address tokenOwner = ownerOf(tokenId);
    require(to != tokenOwner, 
      "Super721: approval to current owner");

    require(_msgSender() == tokenOwner || 
      isApprovedForAll(tokenOwner, _msgSender()),
      "Super721: approve caller is not owner or approved");

    b.tokenApprovals[tokenId] = to;
    emit Approval(ownerOf(tokenId), to, tokenId);
  }

  /**
    Return a version number for this contract's interface.
  */
  function version() external pure 
  virtual override returns (uint256) {

    return 1;
  }

  /**
    Return the item collection's metadata URI. This implementation returns the
    same URI for all tokens within the collection and relies on client-side
    ID substitution per https://eips.ethereum.org/EIPS/eip-721#metadata. Per
    said specification, clients calling this function must replace the {id}
    substring with the actual token ID in hex, not prefixed by 0x, and padded
    to 64 characters in length.

    @return The metadata URI string of the item with ID `_itemId`.
  */
  function tokenURI(uint256 id) external override view 
  returns (string memory) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    if(bytes(b.metadataUri).length == 0) {
      return b.metadata[id];
    }
    return Utils.interpolate(b.metadataUri, id);
  }

  /**
    Allow the item collection owner or an approved manager to update the
    metadata URI of this collection. This implementation relies on a single URI
    for all items within the collection, and as such does not emit the standard
    URI event. Instead, we emit our own event to reflect changes in the URI.

    @param _uri The new URI to update to.
  */
  function setURI(string calldata _uri) external 
  virtual hasValidPermit(UNIVERSAL, Super721LiteBlueprint.SET_URI) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    require(!b.uriLocked,
      "Super721: the collection URI has been permanently locked");
    string memory oldURI = b.metadataUri;
    b.metadataUri = _uri;
    emit ChangeURI(oldURI, _uri);
  }

  /**
    Allow approved manager to update the contract URI. At the end of update, we 
    emit our own event to reflect changes in the URI.

    @param _uri The new contract URI to update to.
   */
  function setContractURI(string calldata _uri) external 
  virtual hasValidPermit(UNIVERSAL, Super721LiteBlueprint.SET_URI) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    require(!b.contractUriLocked,
      "Super721: the contract URI has been permanently locked");
    string memory oldContractUri = b.contractURI;
    b.contractURI = _uri;
    emit ChangeContractURI(oldContractUri, _uri);
  }

  /**
    Allow the item collection owner or an approved manager to update proxy
    registry address handling delegated approval.

    @param _proxyRegistryAddress The address of the new proxy registry to
      update to.
  */
  function setProxyRegistry(address _proxyRegistryAddress) external 
  virtual hasValidPermit(UNIVERSAL, Super721LiteBlueprint.SET_PROXY_REGISTRY) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    address oldRegistry = b.proxyRegistryAddress;
    b.proxyRegistryAddress = _proxyRegistryAddress;
    emit ChangeProxyRegistry(oldRegistry, _proxyRegistryAddress);
  }

  /**
   * @dev See {IERC721-balanceOf}.
   */
  function balanceOf(address _owner) public view 
  virtual override returns (uint256) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    require(_owner != address(0), 
      "ERC721: balance query for the zero address");
    return b.balances[_owner];
  }

  /**
    Retrieve in a single call the balances of multiple owners.

    @param _owners The owners to check for balances.
    @return the amount of tokens owned by each owner.
  */
  function balanceOfBatch(address[] calldata _owners) external view 
  virtual returns (uint256[] memory) {

    // Populate and return an array of balances.
    uint256[] memory batchBalances = new uint256[](_owners.length);
    for (uint256 i = 0; i < _owners.length; ++i) {
      batchBalances[i] = balanceOf(_owners[i]);
    }
    return batchBalances;
  }

  /**
    This function returns true if `_operator` is approved to transfer items
    owned by `_owner`. This approval check features an override to explicitly
    whitelist any addresses delegated in the proxy registry.

    @param _owner The owner of items to check for transfer ability.
    @param _operator The potential transferrer of `_owner`'s items.
    @return Whether `_operator` may transfer items owned by `_owner`.
  */
  function isApprovedForAll(address _owner, address _operator) public view 
  virtual override returns (bool) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    StubProxyRegistry proxyRegistry = StubProxyRegistry(b.proxyRegistryAddress);
    if (address(proxyRegistry.proxies(_owner)) == _operator) {
      return true;
    }

    // We did not find an explicit whitelist in the proxy registry.
    return b.operatorApprovals[_owner][_operator];
  }

  /**
    Enable or disable approval for a third party `_operator` address to manage
    all of the caller's tokens.

    @param _operator The address to grant management rights over all of the
      caller's tokens.
    @param _approved The status of the `_operator`'s approval for the caller.
  */
  function setApprovalForAll(address _operator, bool _approved) external 
  virtual override {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    require(_msgSender() != _operator,
      "Super721: setting approval status for self");
    b.operatorApprovals[_msgSender()][_operator] = _approved;
    emit ApprovalForAll(_msgSender(), _operator, _approved);
  }

  /**
    This private helper function converts a number into a single-element array.
    @param _element The element to convert to an array.

    @return The array containing the single `_element`.
  */
  function _asSingletonArray(uint256 _element) private pure 
  returns (uint256[] memory) {
      
    uint256[] memory array = new uint256[](1);
    array[0] = _element;
    return array;
  }

  /**
    An inheritable and configurable pre-transfer hook that can be overridden.
    It fires before any token transfer, including mints.

    @param _operator The caller who triggers the token transfer.
    @param _from The address to transfer tokens from.
    @param _to The address to transfer tokens to.
    @param _startTokenId The owner of the batch.
    @param _quantity The amounts of the specific `_ids` to transfer.
    @param _data Additional call data to send with this transfer.
  */
  function _beforeTokenTransfer(address _operator, address _from, address _to,
    uint256 _startTokenId, uint256 _quantity, bytes memory _data)
    internal virtual {
  }

  /**
    An inheritable and configurable post-transfer hook that can be overridden.
    It fires after any token transfer, including mints.

    @param _operator The caller who triggers the token transfer.
    @param _from The address to transfer tokens from.
    @param _to The address to transfer tokens to.
    @param _startTokenId The owner of the batch.
    @param _quantity The amounts of the specific `_ids` to transfer.
    @param _data Additional call data to send with this transfer.
  */
  function _afterTokenTransfer(address _operator, address _from, address _to,
    uint256 _startTokenId, uint256 _quantity, bytes memory _data)
    internal virtual {
  }

  /**
    ERC-721 dictates that any contract which wishes to receive ERC-721 tokens
    must explicitly designate itself as such. This function checks for such
    designation to prevent undesirable token transfers.

    @param _operator The caller who triggers the token transfer.
    @param _from The address to transfer tokens from.
    @param _to The address to transfer tokens to.
    @param _id The specific token ID to transfer.
    @param _data Additional call data to send with this transfer.
  */
  function _doSafeTransferAcceptanceCheck(address _operator, address _from,
    address _to, uint256 _id, bytes memory _data) private {

    if (_to.isContract()) {
      try IERC721Receiver(_to).onERC721Received(_operator, _from, _id,
        _data) returns (bytes4 response) {
        if (response != IERC721Receiver(_to).onERC721Received.selector) {
          revert("Super721::_doSafeTransferAcceptanceCheck: ERC721Receiver rejected tokens");
        }
      } catch Error(string memory reason) {
        revert(reason);
      } catch {
        revert("Super721::_doSafeTransferAcceptanceCheck: transfer to non ERC721Receiver implementer");
      }
    }
  }

  /**
    Transfer on behalf of a caller or one of their authorized token managers
    items from one address to another.

    @param _from The address to transfer tokens from.
    @param _to The address to transfer tokens to.
    @param _ids The specific token IDs to transfer.
    @param _data Additional call data to send with this transfer.
  */
  function safeBatchTransferFrom(address _from, address _to, 
  uint256[] memory _ids, bytes memory _data) public 
  virtual {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    require(_to != address(0), 
      "ERC721: transfer to the zero address");
      
    _beforeTokenTransfer(_msgSender(), address(0), _to, b.mintIndex, _ids.length, _data);
    for (uint256 i = 0; i < _ids.length; i++) {
      require(_exists(_ids[i]),
        "ERC721: non existent token id");

      address prevOwnership = ownershipOf(_ids[i]);
      require(prevOwnership == _from, 
        "ERC721: transfer from incorrect owner");

      bool isApprovedOrOwner = (_msgSender() == prevOwnership ||
        getApproved(_ids[i]) == _msgSender() ||
        isApprovedForAll(prevOwnership, _msgSender()));
      require(isApprovedOrOwner, 
        "ERC721: transfer caller is not owner nor approved");

      // Clear approvals from the previous owner
      approve(address(0), _ids[i]);

      b.balances[_from] -= 1;
      b.balances[_to] += 1;
      b.ownerships[_ids[i]] = _to;

      // Set the immediate ownership of token index + 1
      uint256 nextTokenId = _ids[i] + 1;
      if (b.ownerships[nextTokenId] == address(0)) {
        if (_exists(nextTokenId)) {
          b.ownerships[nextTokenId] = prevOwnership;
        }
      }
      emit Transfer(_from, _to, _ids[i]);
    }

    _afterTokenTransfer(_msgSender(), address(0), _to, b.mintIndex, _ids.length, _data);
  }

  /**
    @dev See {IERC721-safeTransferFrom}.
    Transfer on behalf of a caller or one of their authorized token managers
    items from one address to another.

    @param from The address to transfer tokens from.
    @param to The address to transfer tokens to.
    @param tokenId The specific token ID to transfer.
    @param data Additional call data to send with this transfer.
  */
  function safeTransferFrom(address from, address to, 
  uint256 tokenId, bytes memory data) public 
  virtual override {

    safeBatchTransferFrom(from, to, _asSingletonArray(tokenId), data);
    _doSafeTransferAcceptanceCheck(_msgSender(), from, to, tokenId, data);
  }

  /**
   * @dev See {IERC721-safeTransferFrom}.
   */
  function safeTransferFrom(address from, address to, uint256 tokenId) public 
  virtual override {

    safeTransferFrom(from, to, tokenId, bytes(""));
  }

  /**
   * @dev See {IERC721-transferFrom}.
   */
  function transferFrom(address from, address to, uint256 tokenId) public 
  virtual override {

    safeBatchTransferFrom(from, to, _asSingletonArray(tokenId), bytes(""));
  }

  /**
    Mint a batch of tokens and send them to the `_recipient` address.

    @param _recipient The address to receive all NFTs.
    @param _quantity The amount of NFT's to be minted.
    @param _data Any associated data to use on items minted in this transaction.
  */

  function mintBatch(address _recipient, uint256 _quantity, bytes memory _data) external 
  virtual hasValidPermit(UNIVERSAL, Super721LiteBlueprint.MINT) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    require(_recipient != address(0), "Super721: mint to zero address");
    require(_quantity <= b.batchSize, "Super721: quantity too high");
    require(b.mintIndex + _quantity <= b.totalSupply, "Super721: cap reached");

    _beforeTokenTransfer(_msgSender(), address(0), _recipient, 
      b.mintIndex, _quantity, _data);

    uint256 startTokenId = b.mintIndex;
    uint256 updatedId = startTokenId;

    for (uint256 j = 0; j < _quantity; j++) {
      _doSafeTransferAcceptanceCheck(_msgSender(), address(0), _recipient, 
        updatedId, _data);
      emit Transfer(address(0), _recipient, updatedId);
      updatedId++;
    }

    // Update storage of special balances and circulating values.
    b.mintIndex = updatedId;
    b.ownerships[startTokenId] = _recipient;
    b.balances[_recipient] = b.balances[_recipient] + _quantity;

    _afterTokenTransfer(_msgSender(), address(0), _recipient, 
      b.mintIndex, _quantity, _data);
  }

  /**
    Set the on-chain metadata attached to a specific token ID so long as the
    collection as a whole or the token specifically has not had metadata
    editing frozen.

    @param _id The ID of the token to set the `_metadata` for.
    @param _metadata The metadata string to store on-chain.
  */
  function setMetadata(uint256 _id, string memory _metadata) external 
  hasItemRight(_id, Super721LiteBlueprint.SET_METADATA) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    require(!b.uriLocked && !b.metadataFrozen[_id], 
      "Super721: metadata is frozen");
    string memory oldMetadata = b.metadata[_id];
    b.metadata[_id] = _metadata;
    emit MetadataChanged(_msgSender(), _id, oldMetadata, _metadata);
  }

  /**
    Allow the item collection owner or an associated manager to forever lock the
    metadata URI on the entire collection to future changes.
  */
  function lockURI() external 
  hasValidPermit(UNIVERSAL, Super721LiteBlueprint.LOCK_URI) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    b.uriLocked = true;
    emit PermanentURI(b.metadataUri, 2 ** 256 - 1);
  }

  /**
    Allow the associated manager to forever lock the contract URI to future changes
   */
  function lockContractUri() external 
  hasValidPermit(UNIVERSAL, Super721LiteBlueprint.LOCK_URI) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    b.contractUriLocked = true;
    emit PermanentContractURI(b.contractURI, 2 ** 256 - 1);   
  }

  /**
    Allow the item collection owner or an associated manager to forever lock the
    metadata URI on an item to future changes.
    
    @param _uri The value of the URI to lock for `_id`.
    @param _id The token ID to lock a metadata URI value into.
  */
  function lockItemURI(string calldata _uri, uint256 _id) external 
  hasItemRight(_id, Super721LiteBlueprint.LOCK_ITEM_URI) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    b.metadataFrozen[_id] = true;
    emit PermanentURI(_uri, _id);
  }

  /**
    Allow the item collection owner or an associated manager to forever lock
    this contract to further item minting.
  */
  function lock() external virtual 
  hasValidPermit(UNIVERSAL, Super721LiteBlueprint.LOCK_CREATION) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    b.locked = true;
    emit CollectionLocked(_msgSender());
  }

  /** 
    A function used for registering interface when deploying.
    
    @param interfaceId The hash of the interface.
  */
  function registerInterface(bytes4 interfaceId) external 
  virtual onlyOwner {

    _registerInterface(interfaceId);
  }

  /**
   * @dev See {IERC721-getApproved}.
   */
  function getApproved(uint256 tokenId) public view 
  override returns (address) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    require(_exists(tokenId), 
      "ERC721: approved query for nonexistent token");
    return b.tokenApprovals[tokenId];
  }
  
  /**
   * @dev See {IERC721Enumerable-tokenOfOwnerByIndex}.
   */
  function tokenOfOwnerByIndex(address _owner, uint256 _index) public view 
  returns (uint256) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    require(_owner != address(0), 
      "ERC721: invalid owner address");
    require(_index < balanceOf(_owner), 
      "ERC721: owner index out of bounds");

    uint256 numMintedSoFar = b.mintIndex;
    uint256 tokenIdsIdx = 0;
    address currOwnershipAddr = address(0);
    for (uint256 i = 0; i < numMintedSoFar; i++) {
      address ownership = b.ownerships[i];
      if (ownership != address(0)) {
        currOwnershipAddr = ownership;
      }
      if (currOwnershipAddr == _owner) {
        if (tokenIdsIdx == _index) {
          return i;
        }
        tokenIdsIdx++;
      }
    }
    revert("ERC721: unable to get token of owner by index");
  }

  /**
   * @dev See {IERC721Enumerable-tokenByIndex}.
   */
  function tokenByIndex(uint256 index) public view 
  returns (uint256) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    require(index < b.totalSupply, 
      "ERC721: index out of bounds");
    return index;
  }

  /**
   * @dev See {IERC721Enumerable-name}.
   */
  function name() external view 
  virtual override returns (string memory _name) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    _name = b.name;
  }

  /**
   * @dev See {IERC721Enumerable-symbol}.
   */
  function symbol() external view 
  virtual override returns (string memory _symbol) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    _symbol = b.symbol;
  }

  function metadataUri() external view
  virtual returns (string memory) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    return b.metadataUri;
  }

  function contractURI() external view
  virtual returns (string memory) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    return b.contractURI;
  }

  /**
   * @dev See {IERC721Enumerable-totalSupply}.
   */
  function totalSupply() external view 
  virtual override returns (uint256) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    return b.totalSupply;
  }

  function mintIndex() external view
  virtual returns (uint256) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    return b.mintIndex;
  }

  /** 
    A function to get batchSize via a delegate call.
  */
  function batchSize() external view
  virtual returns (uint256) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    return b.batchSize;
  }

  /** 
    A function to get implementation address via a delegate call.
  */
  function implementation() external view
  virtual returns (address) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    return b.implementation;
  }

  function proxyRegistryAddress() external view
  virtual returns (address) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    return b.proxyRegistryAddress;
  }

  function ownerships(uint256 _id) external view
  virtual returns (address) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    return b.ownerships[_id];
  }

  function balances(address _owner) external view
  virtual returns (uint256) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    return b.balances[_owner];
  }

  function operatorApprovals(address _owner, address _operator) external view
  virtual returns (bool) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    return b.operatorApprovals[_owner][_operator];
  }

  function tokenApprovals(uint256 _id) external view
  virtual returns (address) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    return b.tokenApprovals[_id];
  }

  function metadataFrozen(uint256 _id) external view
  virtual returns (bool) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    return b.metadataFrozen[_id];
  }

  function metadata(uint256 _id) external view
  virtual returns (string memory) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    return b.metadata[_id];
  }

  function uriLocked() external view
  virtual returns (bool) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    return b.uriLocked;
  }

  function contractUriLocked() external view
  virtual returns (bool) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    return b.contractUriLocked;
  }

  function locked() external view
  virtual returns (bool) {

    Super721LiteBlueprint.Super721LiteStateVariables
      storage b = Super721LiteBlueprint.super721LiteStateVariables();

    return b.locked;
  }
}