# nft-barter.mligo

This contract allows two addresses to exchange the tokens they own. 
The contract exchanges one token address and any number of token_ids associate
with that address from a owner address with another owner address for their
token_ids associated with their token address.  Counterparties can have different
numbers of token ids.
   
The token used in this contract is a FA2 "Multiple Fungible Token".
This means each token address has a number of token_ids, and each token_id
has its own associated supply.

## Storage example

This contract's storage is a mapping from owner addresses to another token address map.  The token address map has keys that are token addresses and values that are maps from token_id to amounts.

	Map.literal [ 
	  ( ("owner0 address" : owner_address), { 
		Map.literal [
		  (("token0 address" : token_address), Map.literal[(1n, 2n); (2n, 2n)])
		  (("token1 address" : token_address), Map.literal[(1n, 2n)])
		]
	   });

	  ( ("owner1 address" : owner_address), { 
		Map.literal [
		  (("token0 address" : token_address), Map.literal[(3n, 2n); (2n, 2n)])
		  (("token1 address" : token_address), Map.literal[(4n, 2n)])
		]
	   }); 
	]


