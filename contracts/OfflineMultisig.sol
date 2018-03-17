/* Copyright (c) 2018 adria@codecontext.io / MIT LICENSE */

pragma solidity ^0.4.18;

contract OfflineMultisig {
  event Log(string s);

    bytes constant WEB3_SIGNATURE_PREFIX = "\x19Ethereum Signed Message:\n32";

    bytes32 internal txidcontext;

    address[][] public epochs;

    struct Transaction {
        uint count;
        mapping (address=>bool) approved;
        bool executed;
    }

    struct Signature {
        uint256 epoch;
        bytes data;
        mapping (address=>bytes32[]) sigs;
    }
    
    mapping (bytes32=>Transaction) public txns;
    mapping (bytes32=>Signature) public txnsigs;

    function getEpochs() public view returns (uint) {
       return epochs.length;
    }

    function OfflineMultisig(address[] _signers) public {
      require(checkSignersOrder(_signers));
      uint epoch = epochs.length++;
      epochs[epoch].length = _signers.length;
      for (uint i = 0;i<_signers.length;i++) {
          epochs[epoch][i] = _signers[i];
      }
    }

    function checkSignersOrder(address[] _signers) internal pure returns (bool) {
      for (uint i = 0;i<_signers.length;i++) {
         if (i>0 && uint(_signers[i-1])>=uint(_signers[i])) {
            return false;
         }
      }
      return true;
    }
    
    function isSigner( address _addr) public view returns (bool) {
        uint epoch = epochs.length-1;
        for (uint i = 0;i<epochs[epoch].length;i++) {
           if (epochs[epoch][i]==_addr) {
              return true;
            }
        }
        return false;      
     }
    
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
    

    // parent chain execution
    function fullExecuteOff(uint _epoch, bytes32 _txid, bytes _data, bytes32[] _sigs) public {
        
        bytes32 hash = keccak256(_epoch,_txid,_data);
        bytes32 prefixedHash = keccak256(WEB3_SIGNATURE_PREFIX, hash);

        require(verifyMultiSignature(_epoch,prefixedHash,_sigs));
        require(!txns[_txid].executed);
        
        txidcontext = _txid;
        require(this.call(_data));
        txidcontext = 0x0;
        
        txns[_txid].executed = true;
    }

    // child chain execution
    function partialExecuteOff(bytes32 _txid, bytes _data, bytes32[] _sig) public {

        if (txns[_txid].executed) {
            return;
        }

        uint epoch = epochs.length - 1;
        bytes32 hash = keccak256(epoch,_txid,_data);
        bytes32 prefixedHash = keccak256(WEB3_SIGNATURE_PREFIX, hash);

        uint8 v = uint8(uint256(_sig[0]));
        bytes32 r = _sig[1];
        bytes32 s = _sig[2];

        address signer = ecrecover(prefixedHash,v,r,s);

        if (txnsigs[_txid].data.length>0) {
            assert(keccak256(txnsigs[_txid].data)==keccak256(_data));
            assert(txnsigs[_txid].epoch==epoch);
        } else {
            txnsigs[_txid].data = _data;
            txnsigs[_txid].epoch = epoch;
        }

        txnsigs[_txid].sigs[signer].length = 3;
        txnsigs[_txid].sigs[signer][0] = _sig[0];
        txnsigs[_txid].sigs[signer][1] = _sig[1];
        txnsigs[_txid].sigs[signer][2] = _sig[2];

        partialExecute(_txid,_data,signer);
    }    

    function getSignatures(bytes32 _txid) public constant returns(uint256 epoch, bytes data, bytes32[] sigs) {

        uint i;
        address signer;
        uint count = 0;

        Signature storage signature = txnsigs[_txid];

        for (i = 0;i<epochs[signature.epoch].length;i++) {
            signer = epochs[signature.epoch][i];
            if (signature.sigs[signer].length > 0) {
                count++;
            }
        }

        bytes32[] memory signatures = new bytes32[](3*count);

        count = 0;
        for (i = 0;i<epochs[signature.epoch].length;i++) {
            signer = epochs[signature.epoch][i];
            if (txnsigs[_txid].sigs[signer].length > 0) {
                signatures[3*count] = txnsigs[_txid].sigs[signer][0];
                signatures[3*count+1] = txnsigs[_txid].sigs[signer][1];
                signatures[3*count+2] = txnsigs[_txid].sigs[signer][2];
                count++;
            }
        }

        return (txnsigs[_txid].epoch, txnsigs[_txid].data,signatures);
    }
 
    // child chain execution
    function partialExecuteOn(bytes32 _txid, bytes _data) public {  
        if (txns[_txid].executed) {
            // we are not going to fail here because last PoA senders will 
            return;
        }
        partialExecute(_txid,_data,msg.sender);   
    }    

    // child chain execution
    function partialExecute(bytes32 _txid, bytes _data, address _signer) private {
        
        require (isSigner(_signer));
        require (!txns[_txid].approved[_signer]);

        txns[_txid].count++;
        txns[_txid].approved[_signer] = true;

        address[] storage signers = epochs[epochs.length-1];
        bool quorum = txns[_txid].count >= (2 * signers.length) / 3;
        if (quorum) {
            txidcontext = _txid;
            require(this.call(_data));
            txidcontext = 0x0;

            txns[_txid].executed = true;
        }
    
    }

    /* ---- multisig functions --------------------------------------- */

    event LogSignersChanged(uint epoch, address[] signers);
    
    function _changeSigners(uint _epoch, address[] _signers) public {
        
        require (msg.sender == address(this));
        
        require (_epoch == epochs.length);
        require (checkSignersOrder(_signers));
      
          uint epoch = epochs.length++;
          epochs[epoch].length = _signers.length;
          for (uint i = 0;i<_signers.length;i++) {
              epochs[epoch][i] = _signers[i];
          }

        LogSignersChanged(_epoch,_signers);
    } 
    
}