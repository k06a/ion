// Copyright (c) 2016-2018 Clearmatics Technologies Ltd
// SPDX-License-Identifier: LGPL-3.0+
pragma solidity ^0.4.23;

import "./libraries/ECVerify.sol";
import "./libraries/RLP.sol";
import "./libraries/PatriciaTrie.sol";
import "./libraries/SolidityUtils.sol";

contract Ion {
    using RLP for RLP.RLPItem;
    using RLP for RLP.Iterator;
    using RLP for bytes;

    /*
    *   @description    BlockHeader struct containing trie root hashes for tx verifications
    */
    struct BlockHeader {
        bytes32 txRootHash;
        bytes32 receiptRootHash;
    }

    bytes32 public chainId;
    bytes32[] public registeredChains;

    mapping (bytes32 => bool) public m_chains;
    mapping (address => bool) public m_validation_modules;
    mapping (bytes32 => bool) public m_blockhashes;
    mapping (bytes32 => BlockHeader) public m_blockheaders;


    /*
    * Constructor
    * param: id (bytes32) Unique id to identify this chain that the contract is being deployed to.
    *
    * Supplied with a unique id to identify this chain to others that may interoperate with it.
    * The deployer must assert that the id is indeed public and that it is not already being used
    * by another chain
    */
    constructor(bytes32 _id) public {
        chainId = _id;
    }

    enum ProofType { TX, RECEIPT, ROOTS }

    event VerifiedProof(bytes32 chainId, bytes32 blockHash, uint proofType);
    event BroadcastSignature(address signer);
    event BroadcastHash(bytes32 blockHash);
    
/*
========================================================================================================================

    Modifiers

========================================================================================================================
*/

    /*
    * onlyRegisteredChains
    * param: _id (bytes32) Unique id of chain supplied to function
    *
    * Modifier that checks if the provided chain id has been registered to this contract
    */
    modifier onlyRegisteredChains(bytes32 _id) {
        require(m_chains[_id], "Chain is not registered");
        _;
    }

    /*
    * onlyRegisteredValidation
    * param: _addr (address) Address of the Validation module being registered
    *
    * Modifier that checks if the provided chain id has been registered to this contract
    */
    modifier onlyRegisteredValidation(address _addr) {
        require(m_validation_modules[_addr], "Validation module is not registered");
        _;
    }

    /*
    * onlyExistingBlocks
    * param: _id (bytes32) Unique id of chain supplied to function
    * param: _hash (bytes32) Block hash which needs validation
    *
    * Modifier that checks if the provided block hash has been verified by the validation contract
    */
    modifier onlyExistingBlocks(bytes32 _id, bytes32 _hash) {
        require(m_blockhashes[_hash], "Block does not exist for chain");
        _;
    }

/*
========================================================================================================================

    Functions

========================================================================================================================
*/

    /*
    * addChain
    * param: id        Unique id of another chain to interoperate with
    * param: addr      Address of the validation module used for this new chain
    *
    * Supplied with an id of another chain, checks if this id already exists in the known set of ids
    * and adds it to the list of known m_chains. 
    *
    *Should be called by the validation registerChain() function
    */
    function addChain(bytes32 _id) public returns (bool) {
        require( _id != chainId, "Cannot add this chain id to chain register" );
        require(!m_chains[_id], "Chain already exists" );
        m_chains[_id] = true;
        m_validation_modules[msg.sender] = true;
        registeredChains.push(_id);

        return true;
    }

    /*
    * CheckTxProof
    * param: _id (bytes32) Unique id of chain submitting block from
    * param: _blockHash (bytes32) Block hash of block being submitted
    * param: _value (bytes) RLP-encoded transaction object array with fields defined as: https://github.com/ethereumjs/ethereumjs-tx/blob/0358fad36f6ebc2b8bea441f0187f0ff0d4ef2db/index.js#L50
    * param: _parentNodes (bytes) RLP-encoded array of all relevant nodes from root node to node to prove
    * param: _path (bytes) Byte array of the path to the node to be proved
    *
    * emits: VerifiedTxProof(chainId, blockHash, proofType)
    *        chainId: (bytes32) hash of the chain verifying proof against
    *        blockHash: (bytes32) hash of the block verifying proof against
    *        proofType: (uint) enum of proof type
    *
    * All data associated with the proof must be constructed and provided to this function. Modifiers restrict execution
    * of this function to only allow if the chain the proof is for is registered to this contract and if the block that
    * the proof is for has been submitted.
    */
    function CheckTxProof(
        bytes32 _id,
        bytes32 _blockHash,
        bytes _value,
        bytes _parentNodes,
        bytes _path
    )
        onlyRegisteredChains(_id)
        onlyExistingBlocks(_id, _blockHash)
        public
        returns (bool)
    {
        verifyProof(_value, _parentNodes, _path, m_blockheaders[_blockHash].txRootHash);

        emit VerifiedProof(_id, _blockHash, uint(ProofType.TX));
        return true;
    }

    /*
    * CheckReceiptProof
    * param: _id (bytes32) Unique id of chain submitting block from
    * param: _blockHash (bytes32) Block hash of block being submitted
    * param: _value (bytes) RLP-encoded receipt object array with fields defined as: https://github.com/ethereumjs/ethereumjs-tx/blob/0358fad36f6ebc2b8bea441f0187f0ff0d4ef2db/index.js#L50
    * param: _parentNodes (bytes) RLP-encoded array of all relevant nodes from root node to node to prove
    * param: _path (bytes) Byte array of the path to the node to be proved
    *
    * emits: VerifiedTxProof(chainId, blockHash, proofType)
    *        chainId: (bytes32) hash of the chain verifying proof against
    *        blockHash: (bytes32) hash of the block verifying proof against
    *        proofType: (uint) enum of proof type
    *
    * All data associated with the proof must be constructed and paddChainrovided to this function. Modifiers restrict execution
    * of this function to only allow if the chain the proof is for is registered to this contract and if the block that
    * the proof is for has been submitted.
    */
    function CheckReceiptProof(
        bytes32 _id,
        bytes32 _blockHash,
        bytes _value,
        bytes _parentNodes,
        bytes _path
    )
        onlyRegisteredChains(_id)
        onlyExistingBlocks(_id, _blockHash)
        public
        returns (bool)
    {
        verifyProof(_value, _parentNodes, _path, m_blockheaders[_blockHash].receiptRootHash);

        emit VerifiedProof(_id, _blockHash, uint(ProofType.RECEIPT));
        return true;
    }

    /*
    * CheckRootsProof
    * param: _id (bytes32) Unique id of chain submitting block from
    * param: _blockHash (bytes32) Block hash of block being submitted
    * param: _txNodes (bytes) RLP-encoded relevant nodes of the Tx trie
    * param: _receiptNodes (bytes) RLP-encoded relevant nodes of the Receipt trie
    *
    * emits: VerifiedTxProof(chainId, blockHash, proofType)
    *        chainId: (bytes32) hash of the chain verifying proof against
    *        blockHash: (bytes32) hash of the block verifying proof against
    *        proofType: (uint) enum of proof type
    *
    * All data associated with the proof must be constructed and provided to this function. Modifiers restrict execution
    * of this function to only allow if the chain the proof is for is registered to this contract and if the block that
    * the proof is for has been submitted.
    */
    function CheckRootsProof(
        bytes32 _id,
        bytes32 _blockHash,
        bytes _txNodes,
        bytes _receiptNodes
    )
        onlyRegisteredChains(_id)
        onlyExistingBlocks(_id, _blockHash)
        public
        returns (bool)
    {
        assert( m_blockheaders[_blockHash].txRootHash == getRootNodeHash(_txNodes) );
        assert( m_blockheaders[_blockHash].receiptRootHash == getRootNodeHash(_receiptNodes) );

        emit VerifiedProof(_id, _blockHash, uint(ProofType.ROOTS));
        return true;
    }

    /*
     * Verify proof assertion to avoid  stack to deep error (it doesn't show during compile time but it breaks
     * blockchain simulator)
     */
    function verifyProof(bytes _value, bytes _parentNodes, bytes _path, bytes32 _hash) {
        assert( PatriciaTrie.verifyProof(_value, _parentNodes, _path, _hash) );
    }

    /*
    * @description              when a block is submitted the header must be added to a mapping of blockhashes and m_chains to blockheaders
    * @param _hash              root hash of the block being added
    * @param _txRootHash        transaction root hash of the block being added
    * @param _receiptRootHash   receipt root hash of the block being added
    */
    function addBlock(bytes32 _id, bytes32 _hash, bytes32 _txRootHash, bytes32 _receiptRootHash, bytes _rlpBlockHeader) 
        onlyRegisteredValidation(msg.sender)
        onlyRegisteredChains(_id)
    {
        require(!m_blockhashes[_hash]);

        RLP.RLPItem[] memory header = _rlpBlockHeader.toRLPItem().toList();

        bytes32 hashedHeader = keccak256(_rlpBlockHeader);
        require(hashedHeader == _hash, "Hashed header does not match submitted block hash!");

        m_blockhashes[_hash] = true;
        m_blockheaders[_hash].txRootHash = _txRootHash;
        m_blockheaders[_hash].receiptRootHash = _receiptRootHash;
    }


/*
========================================================================================================================

    Helper Functions

========================================================================================================================
*/

    /*
    * @description      returns the root node of an RLP encoded Patricia Trie
	* @param _rlpNodes  RLP encoded trie
	* @returns          root hash
	*/
    function getRootNodeHash(bytes _rlpNodes) private returns (bytes32) {
        RLP.RLPItem memory nodes = RLP.toRLPItem(_rlpNodes);
        RLP.RLPItem[] memory nodeList = RLP.toList(nodes);

        bytes memory b_nodeRoot = RLP.toBytes(nodeList[0]);

        return keccak256(b_nodeRoot);
    }


}

