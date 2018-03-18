# gometh experimental sidechain

Gometh is a double-peg sidechain that mainly:

- Deploys two contracts, one in the mainchain called `GomethMain` and another in the sidechain named `GomethSide`
- Anybody can send ethers from the mainchain to the side chain by calling the `lock()` method in the `GomethMain`, this will:
  - keep the sent ethers in the main chain (diposit)
  - generates a wrapped ether `WETH` in the sidechain
- This sidechain wrapped ether can be converted to sidechain local ether to execute smartcontracts, but them cannot be converted back to WETH
- `WETH`s can also converted back to mainchain ethers by calling the `burn()` function in the `GomethSide`. In this case, a voucher is generated. This voucher can used in the `GomethMain` contract to recieve the mainchain ethers.

Also provides some aditional functions:

- Allows sidechain signers to be added/removed, since sidechain acts as a multisig. All signer changes in the sidechain, could be applied in the mainchain in one only transaction
- Each some blocks, sidechain should send the block and the root state of `WETH` to the main chain
  - If mainchain `WETH`-sidechain-state-root is not updated in some XXX blocks, is not possible to call `lock()` to transfer ethers to sidechain
  - If mainchain `WETH`-sidechain-state-root is not updated in some YYY (> XXX blocks), the system understands it as a global settelment. In this case:
    - Users annotate the last block submited to the sidechain 
    - Users can query to a archive-node sidechain to access to a proof of their WETH balance at this block and provide the merkle proof to the mainchain, to retrieve the locked ethers.
    
    



