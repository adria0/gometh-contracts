/* Copyright (c) 2018 adria@codecontext.io / MIT LICENSE */

pragma solidity ^0.4.18;

import "./OfflineMultisig.sol";
import "./PatriciaTree.sol";
import "./WETH.sol";

contract GomethMain is OfflineMultisig, PatriciaTreeVerifier {

    uint constant DUST = 0; 
    uint constant BLOCKSTOSTALL = 40000; // 1 week
    uint constant BLOCKSTOGLOBALSETTELMENT = 80000; // 2 weeks

    uint256 public wethLocalBlockNo;
    uint256 public wethSideBlockNo;
    bytes32 public wethRootState;

    event LogLock(uint256 epoch,  address from, uint256 value);
    event LogUnlock(address to, uint256 value);

    function GomethMain(address[] _signers) 
    OfflineMultisig(_signers) public {
        wethLocalBlockNo = block.number;
    }
    
    /// User calls this functions to send ETH to child chain
    function lock() payable public {
        require(msg.value > DUST);
        require(block.number - wethLocalBlockNo < BLOCKSTOSTALL);
        LogLock(epochs.length, msg.sender,msg.value);
    }

    // this function is called on global settelment
    //   be carefull, the getProof() should be called at the `wethSideBlockNo` exactly
    mapping (bytes32=>bool) globalSettelmentReturns;

    function refund(uint256 _amount, uint _branchMask, bytes32[] _siblings) public {
        require(block.number - wethLocalBlockNo >= BLOCKSTOGLOBALSETTELMENT);    
    
        bytes32 id = keccak256(msg.sender,_amount,_branchMask,_siblings);
        require(globalSettelmentReturns[id]==false);
        globalSettelmentReturns[id] = true;

        verifyProof(
            wethRootState,
            WETHUtils.addr2bytes(msg.sender), WETHUtils.uint2bytes(_amount),
            _branchMask,_siblings);

        msg.sender.transfer(_amount);
    }

    /* ---- multisig functions --------------------------------------- */

    // This function should be called via fullExecuteOff by a cron job.
    //   it updates the block & WETH states

    function _statechangemultisigned(uint256 blockNo, bytes32 rootState) public {
       require(msg.sender == address(this));
       require(block.number - wethLocalBlockNo < BLOCKSTOGLOBALSETTELMENT);       
       if (blockNo > wethSideBlockNo) {
           wethSideBlockNo = blockNo;
           wethRootState = rootState;
       }
    }

    // This function should be called via fullExecuteOff by an user that
    //   wants to retrieve their ether
    
    function _burnmultisigned(address from, uint value) public {
       require(msg.sender == address(this));
       require(block.number - wethLocalBlockNo < BLOCKSTOSTALL);       
       from.transfer(value);
    }

}