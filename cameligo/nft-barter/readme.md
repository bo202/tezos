# nft-barter.mligo

This contract allows two addresses to exchange the tokens they own. 
The contract exchanges one token address and any number of token_ids associate
with that address from a owner address with another owner address for their
token_ids associated with their token address.  Counterparties can have different
numbers of token ids.
   
The token used in this contract is a FA2 "Multiple Fungible Token".
This means each token address has a number of token_ids, and each token_id
has its own associated supply.
