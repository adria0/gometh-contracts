/* Copyright (c) 2018 adria@codecontext.io / MIT LICENSE */

pragma solidity ^0.4.18;

contract OfflineMultisig {

    event Log(string s);

    // the prefix generated with web3 signatures
    bytes constant WEB3_SIGNATURE_PREFIX = "\x19Ethereum Signed Message:\n32";

    // the context of the transaction when calling internally a multisig function
    bytes32 internal txidcontext;

    // for each epoch, an ordered list of valid signers
    address[][] public epochs;

    // a transaction to be executed
    struct Transaction {
        bytes   data;     // the transaction data
        uint    count;    // number of singatures/approvals
        bool    executed; // if transaction has been executed
        uint256 epoch;    // of the signers

        mapping (address=>bool) approved;  // approved by onchain signature
        mapping (address=>bytes32[]) sigs; // approved by offchain signatures
    }

    // the transactions
    mapping (bytes32=>Transaction) public txns;

    // how many signer epochs
    function getEpochs() public view returns (uint) {
       return epochs.length;
    }

    // Constuctor, initialize with the ordered list of actual signers
    function OfflineMultisig(address[] _signers) public {
      require(checkSignersOrder(_signers));

      uint epoch = epochs.length++;
      epochs[epoch].length = _signers.length;
      for (uint i = 0;i<_signers.length;i++) {
          epochs[epoch][i] = _signers[i];
      }
    }

    // Check if the signers are ordered
    function checkSignersOrder(address[] _signers) internal pure returns (bool) {

      for (uint i = 0;i<_signers.length;i++) {
         if (i>0 && uint(_signers[i-1])>=uint(_signers[i])) {
            return false;
         }
      }
      return true;
    }
    
    // Check if is a valid signer NOW
    function isSigner( address _addr) public view returns (bool) {

        uint epoch = epochs.length-1;
        for (uint i = 0;i<epochs[epoch].length;i++) {
           if (epochs[epoch][i]==_addr) {
              return true;
            }
        }
        return false;      
     }
    
    // Verify signatures made over a hash, in an ordered way in a epoch
    function verifyMultiSignature(uint _epoch, bytes32 _hash, bytes32[] _sigs) view public
    returns (bool) {

        uint signerNo = 0;
        
        address[] storage signers = epochs[epochs.length-1];
        if ( _epoch != 0 ) {
            signers = epochs[_epoch];
        }
        
        for (uint i = 0;i<_sigs.length;i += 3) {
          
          // retrieve the signer
          
          uint8 v = uint8(uint256(_sigs[i]));
          bytes32 r = _sigs[i+1];
          bytes32 s = _sigs[i+2];
          address signer = ecrecover(_hash,v,r,s); 

          // check that this signer exists in the current signer list
          
          while (signerNo<signers.length && signers[signerNo]!=signer) {
              signerNo++;
          }
          if (signerNo>=signers.length) {
              return false;
          }
          
          // jump to the next signer, to avoid duplicates
          
          signerNo++;
    
        }
        
        return true;
     }
    

    // Execute a multisig function with all the necessary signatures (in an ordered way by signer)
    function fullExecuteOff(uint _epoch, bytes32 _txid, bytes _data, bytes32[] _sigs) public {
        
        bytes32 hash = keccak256(_epoch,_txid,_data);
        bytes32 prefixedHash = keccak256(WEB3_SIGNATURE_PREFIX, hash);

        require(verifyMultiSignature(_epoch,prefixedHash,_sigs));
        require(!txns[_txid].executed);
        
        // call the multisig function
        txidcontext = _txid;
        require(this.call(_data));
        txidcontext = 0x0; // clear storage
        
        txns[_txid].executed = true;
    }

    // Approve a multisig function with offchain signature and execute it if there's enough quorum
    function partialExecuteOff(bytes32 _txid, bytes _data, bytes32[] _sig) public {

        // do not fail if previously executed, this could easely happen on multiple
        // tx sent at the same time by sidechain nodes
        if (txns[_txid].executed) {
            return;
        }

        uint epoch = epochs.length - 1;

        // retrieve the signer
        bytes32 hash = keccak256(epoch,_txid,_data);
        bytes32 prefixedHash = keccak256(WEB3_SIGNATURE_PREFIX, hash);
        uint8 v = uint8(uint256(_sig[0]));
        bytes32 r = _sig[1];
        bytes32 s = _sig[2];
        address signer = ecrecover(prefixedHash,v,r,s);

        // store the call information, check if exactly the same if defined previously
        if (txns[_txid].data.length>0) {
            assert(keccak256(txns[_txid].data)==keccak256(_data));
            assert(txns[_txid].epoch==epoch);
        } else {
            txns[_txid].data = _data;
            txns[_txid].epoch = epoch;
        }
        txns[_txid].sigs[signer].length = 3;
        txns[_txid].sigs[signer][0] = _sig[0];
        txns[_txid].sigs[signer][1] = _sig[1];
        txns[_txid].sigs[signer][2] = _sig[2];

        // execute the function
        partialExecute(_txid,_data,signer);
    }    

    // Approve a multisig function, and execute it if quorum is reached. Onchain signature.
    function partialExecuteOn(bytes32 _txid, bytes _data) public {  
        if (txns[_txid].executed) {
            return;
        }
        partialExecute(_txid,_data,msg.sender);   
    }    

    // Approve a multisig function, and execute it if quorum is reached
    function partialExecute(bytes32 _txid, bytes _data, address _signer) private {
        
        require (isSigner(_signer));
        require (!txns[_txid].approved[_signer]);

        // annotate the approval
        txns[_txid].count++;
        txns[_txid].approved[_signer] = true;

        // check if there's enough quorum
        address[] storage signers = epochs[epochs.length-1];
        bool quorum = txns[_txid].count >= (2 * signers.length) / 3;
        if (quorum) {

            // execute multisig function; set & clear context 
            txidcontext = _txid;
            require(this.call(_data));
            txidcontext = 0x0;

            txns[_txid].executed = true;
        }
    
    }

    // Retrieve theordered list of signatures for an executed transation made with a set of previous
    //   partialExecuteOff calls. The return of the function can be re-executed with fullExecuteOff
    //   in another chain
    function getSignatures(bytes32 _txid) public constant returns(uint256 epoch, bytes data, bytes32[] sigs) {

        uint i;
        address signer;
        uint count = 0;

        Transaction storage txn = txns[_txid];

        // count how many signers 
        for (i = 0;i<epochs[txn.epoch].length;i++) {
            signer = epochs[txn.epoch][i];
            if (txn.sigs[signer].length > 0) {
                count++;
            }
        }

        // allocate return for signers
        bytes32[] memory signatures = new bytes32[](3*count);

        // collect signers
        count = 0;
        for (i = 0;i<epochs[txn.epoch].length;i++) {
            signer = epochs[txn.epoch][i];
            if (txns[_txid].sigs[signer].length > 0) {
                signatures[3*count] = txn.sigs[signer][0];
                signatures[3*count+1] = txn.sigs[signer][1];
                signatures[3*count+2] = txn.sigs[signer][2];
                count++;
            }
        }

        // return the full set of data
        return (txns[_txid].epoch, txns[_txid].data,signatures);
    }
 
    /* ---- multisig functions --------------------------------------- */

    event LogChangeSignersMultisigned(uint epoch, address[] signers);
    
    // change the set of current signers
    function _changesignersmultisigned(uint _epoch, address[] _signers) public {
        
        require (msg.sender == address(this));
        
        require (_epoch == epochs.length);
        require (checkSignersOrder(_signers));
      
          uint epoch = epochs.length++;
          epochs[epoch].length = _signers.length;
          for (uint i = 0;i<_signers.length;i++) {
              epochs[epoch][i] = _signers[i];
          }

        LogChangeSignersMultisigned(_epoch,_signers);
    } 
    
}