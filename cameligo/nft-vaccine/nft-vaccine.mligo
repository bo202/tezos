(*// SPDX-License-Identifier: MIT
--------------------------------------------------
WARNING: 
This contract should not run in a production environment since it 
has not been audited for security concerns.  It is presented as is.
Written for the Tezos Development Starter Course on tacode.dev.

END WARNING
--------------------------------------------------


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

Example storage:
The key to the map is shown here as a wallet address, but can include other information to create a unique id for a person.

Map.literal[
(("address representing a person": map_key), {date_issued=true; token_id=("address representing a person": map_key)} )
]

*)


(*
A map_key is unique to a person.  It is used to identfiy a person.
It can be their wallet address, or a tuple with address and other 
information to prevent a person using multiple accounts.

This map key is also the token_id.
*)
type map_key = address

type token_amount = nat

type token_status = {
    date_issued : timestamp; // Has the token been issued.
    token_id    : map_key;
}

(*
The store is a map, which associates each map_key with
that person's token_status.
*)
type storage = (map_key, token_status) big_map


(*
This contract has two entrypoints
- Approve : approve a person, represented by their map_key,
            so that they are allowed a token.
- IssueTo : issue tokens to a person, represented by their map_key.
*)
type action = Approve of map_key

(*
This contract requires an owner who can approve a person's vaccination status
before allow a token to be issued to them.
*)

let owner_address : address =
  ("tz1TGu6TN5GSez2ndXXeDX6LgUDvLzPLqgYV" : address)

// Address of the vaccine token.
let token_address: address = ("tz1TGu6TN5GSez2ndXXeDX6LgUDvLzPLqgYV" : address)

(*
NOTE: The above addresses are placeholder addresses only.
Replace these addresses with the real owner who can approve users
and the real token address when available.
*) 

(* --------------------------------------------
Types for making FA2 token transfers.
*)
type transfer_destination =
[@layhout:comb]
{
    to_      : address;
    token_id : map_key;
    amount   : nat;

}
type transfer = 
[@layout:comb]
{
    from_: address;
    txs  : transfer_destination list;
}


(* --------------------------------------------
Helper functions.
*)
(*
The setup_transfer function sets up the FA2 token transfer.
*)
let setup_transfer(key:map_key):operation =
    (*
    Obtain the "to" address.  Here the map_key is the address.
    As mentioned in the map_key defintion, it can be a tuple 
    consisting of address and other info.
    If it is a tuple, the code can be adjusted to accordingly.

    Assume tokens are owned by this contract if not issued.
    *) 
    let to_user:address = key in
    let tr: transfer = {
        from_ = Tezos.self_address;
        txs = [{
            to_ = to_user;
            token_id = key;
            amount = 1n;
        }
        ]
    }
    in
    let entrypoint : transfer list contract = 
        match (Tezos.get_entrypoint_opt "%transfer" token_address: transfer list contract option) with
        | None -> (failwith "Invalid external contract": transfer list contract)
        | Some e -> e
    in
    Tezos.transaction [tr] 0mutez entrypoint

(*
The approve function approves a person to recieve a token.
Only contract owner can call this function. 
*)

let approve(p, s: map_key * storage) : operation list * storage =
    let () = if Tezos.sender <> owner_address then
        failwith "Action forbidden.  Only contract owner may approve."
    in
    let s: storage = match Map.find_opt p s with
        |None -> Map.add p {date_issued=Tezos.now; token_id=p} s
        |Some _entry -> s  //Storage already reflect this person has a token.
    in

    // Setup transfer after updating storage to avoid reentrancy.
    [setup_transfer(p)],s

(* --------------------------------------------
Main function.
*)
let main(p, s: action * storage) : operation list * storage =

match p with
    | Approve p -> approve(p, s)