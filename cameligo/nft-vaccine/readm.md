# nft-vaccine.mligo

This contract issues a token to individuals which can
be used to indicate their vaccination status.  Showing someone
else that you have this token shows you have been vaccinated.

Since this token can potentially be issued to millions of users,
a big_map data structure is used to keep track of who has a token.

This contract assumes the token used is a FA2 non-fungible token.
See: https://gitlab.com/tezos/tzip/-/blob/master/proposals/tzip-12/implementing-fa2.md.

- Each person has a token with a unique token_id.
- Only one person has a token with that particular token_id.

As for the token contract itself, there can be a separate token contract
for each country or region to keep the big_map size manageable.

To compile the contract:

   sudo docker run --rm -v "$PWD":"$PWD" -w "$PWD" ligolang/ligo:0.19.0 compile-contract nft-vaccine.mligo main --output-file=nft-vaccine.tz
