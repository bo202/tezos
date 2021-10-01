(* 
--------------------------------------------------
WARNING: 
This contract should not run in a production environment.

END WARNING
--------------------------------------------------
This contract allows two addresses to exchange the tokens they own. 
The contract exchanges one token address and any number of token_ids associate
with that address from a owner address with another owner address for their
token_ids associated with their token address.  Counterparties can have different
numbers of token ids.
   
The token used in this contract is a FA2 "Multiple Fungible Token".
This means each token address has a number of token_ids, and each token_id
has its own associated supply.

To compile contract:

sudo docker run --rm -v "$PWD":"$PWD" -w "$PWD" ligolang/ligo:0.19.0 compile-contract nft-barter.mligo main --output-file=nft-barter.tz

*)

// Use type aliasing to clarify two different addresses
type owner_address = address  // address of owner of tokens
type token_address = address  // address of token contract

// token_id map to amount of that token_id

type token_id_map = (nat, nat)map

// token_addresses maps to token_id_map
type token_addr_map = (token_address, token_id_map) map

// owner addresses map to the owner's token_addr_map
type owner_map = (owner_address, token_addr_map) map

(* 
A counterparty is a owner, the token address of the token to barter,
and a list of the specific token_ids to barter.
*)

type counterparty = owner_address * token_address *  token_id_map

(* 
An exchange is two counterparties.
*)
//type exchange = counterparty * counterparty

(* --------------------------------------------
The adjustment record is used to adjust amounts
in the token_id_map to reflect barter exchanges.
Recursion is applied to a list of adjustment records when 
more than one token_id needs to be adjusted.
*)
type adjustment = {
    token_id : nat;
    amount   : nat;
}

(* --------------------------------------------
Types for making FA2 token transfers.
*)
type transfer_destination =
[@layhout:comb]
{
    to_      : address;
    token_id : nat;
    amount   : nat;

}
type transfer = 
[@layout:comb]
{
    from_: address;
    txs  : transfer_destination list;
}

(* --------------------------------------------
Helper functions
*)
(* This function creates a transfer operation for a token contract with address token_address.*)
let transfer_operation (t_addr, tr_list: token_address * transfer list):operation = 
    let entrypoint: transfer list contract =
        match (Tezos.get_entrypoint_opt "%transfer" t_addr: transfer list contract option) with
        | None   -> (failwith"Invalid external token contract": transfer list contract)
        | Some e -> e
    in
    Tezos.transaction tr_list 0mutez entrypoint


(* This functions takes a token_id_map, and creates a transfer_destination list.
[{to_=..; id = 1; amount=a_1;}, {to_=...; id=2; amount=a_2}, ...]
*)
let get_transfer_destination (new_owner, tid_map : owner_address *  token_id_map) : transfer_destination list =
    Map.fold (fun(record_list, kv : transfer_destination list * (nat * nat) )-> {to_=new_owner; token_id = kv.0; amount=kv.1}::record_list)
             tid_map
             ([]: transfer_destination list)

(* update_token_id_map will updated amounts of a specific token_id.*)
let update_token_tid_map(mult, adj_record, tid_map : int * adjustment * token_id_map):token_id_map =
    
    match Map.find_opt adj_record.token_id tid_map with
        | None ->
            // This token_id does not exist.
            if mult = 1 then
                Map.add adj_record.token_id adj_record.amount tid_map
            else
                (failwith "Owner cannot give away tokens they do not own." : token_id_map)
        | Some base_amount-> 
            // An amount for token_id exists.  Cast to int to update since mult is int.
            let adj_amount : int = int(base_amount) + mult * int(adj_record.amount) in
            if adj_amount < 0 then
                (failwith "Amount for this token_id is insufficient to give away." : token_id_map)
            else if adj_amount = 0 then
                // This token_id is all used up, delete from map.
                Map.remove adj_record.token_id tid_map
            else
                let adj_amount:nat = abs(adj_amount) in
                Map.update adj_record.token_id (Some(adj_amount)) tid_map
    

(*
Adjust the token_id_map to reflect the amounts of the exchange
as indicated by adj_list.  Use recursion on adj_list to loop through it.

-- mult=1 for receiving tokens.
-- mult=-1 for giving away tokens.
*)
let rec adjust_amounts (mult, adj_list, tid_map : int * adjustment list * token_id_map) : token_id_map =
    
    // Use the head of adj_list to update tid_map

    let tid_map : token_id_map = match List.head_opt adj_list with
                |None -> (failwith " Failed to get head of list.": token_id_map)
                |Some head -> update_token_tid_map(mult, head, tid_map)
    in
    // See if more adjustments are left in the tail of adj_list
    let tail: adjustment list = match List.tail_opt adj_list with
                |None -> []
                |Some l -> l
    in
    
    if List.length tail = 0n then
        //If the tail has length 0, then adjustments are finished.
        tid_map
    else
        // The tail has more adjustments remaining, recurse on tail.

        adjust_amounts(mult, tail, tid_map)
(*
Update the token_address->token_id_map mapping to reflect changes in the amounts
of a token_id.
*)
let update_token_addr_map (mult, t_addr, adj_tid_map, t_addr_map : int * token_address * token_id_map * token_addr_map) : token_addr_map = 
    
    match Map.find_opt t_addr t_addr_map with
        | None -> 
            // t_addr_map does not have this token address.
            if mult = 1 then
                Map.add t_addr adj_tid_map t_addr_map
            else
                (failwith "Owner does not own any tokens from this token address.  Owner can recieve tokens from this address.": token_addr_map)
        | Some tid_map ->
            (* t_addr_map has an entry, tid_map, for this token address,
                and has returned a map of token_ids to amount.
                Convert the adjust_list to a list so the helper function
                adjust_amounts can recurse on this list and use each list
                item to update tid_map.
            *)
            let adj_list : adjustment list = 
                Map.fold (fun(l, record:adjustment list * (nat * nat)) -> {token_id = record.0; amount = record.1}::l)
                adj_tid_map
                ([] : adjustment list)
            in 
            let tid_map = adjust_amounts (mult, adj_list, tid_map) in
            Map.update t_addr (Some(tid_map)) t_addr_map
    
    //Map.empty

(* --------------------------------------------
main function

The main function updates the owner_map to reflect an exchange of tokens
and creates the FA2 transactions to send the tokens to their new owners.

*)
let main (x, storage : (token_address * token_id_map * counterparty) * owner_map) : operation list * owner_map =
    
    (*  adj_token_id0 and adj_token_id1 has the amounts exchanged 
        for each token_id.  The amounts are used to adjust the storage.
    *)

    let owner0        : owner_address     = Tezos.sender    in
    let token_addr0   : token_address     = x.0             in
    let adj_token_id0 : token_id_map      = x.1             in

    let counterparty1 : counterparty      = x.2             in
    let owner1        : owner_address     = counterparty1.0 in
    let token_addr1   : token_address     = counterparty1.1 in
    let adj_token_id1 : token_id_map      = counterparty1.2 in

    (* --------------------------------------------
    Update owner_map.
    *)

    // Update owner_map for owner0
    let storage : owner_map = match Map.find_opt owner0 storage with
        // If owner0's address is not in the owner_map, add it.
        | None -> let t_addr_map0 : token_addr_map 
                = Map.add token_addr0 adj_token_id0 Map.empty in
                Map.add owner0 t_addr_map0 storage
        | Some t_addr_map0 ->
            (* Update to reflect owner0 giving away token_addr0 -> token_id0 and
                receiving token_addr1 -> token_id1 
            *)
            let t_addr_map0 = update_token_addr_map(-1, token_addr0, adj_token_id0, t_addr_map0) in
            let t_addr_map0 = update_token_addr_map(1,  token_addr1, adj_token_id1, t_addr_map0) in
            Map.update owner0 (Some(t_addr_map0)) storage
    in
    // Update owner_map for owner1
    let storage : owner_map = match Map.find_opt owner1 storage with
        // If owner1's address is not in the owner_map, add it.
        | None -> let t_addr_map1 : token_addr_map 
                = Map.add token_addr1 adj_token_id1 Map.empty in
                Map.add owner1 t_addr_map1 storage
        | Some t_addr_map1 ->
            (* Update to reflect owner1 giving away token_addr1 -> token_id1 and
                receiving token_addr0 -> token_id0
            *)
            let t_addr_map1 = update_token_addr_map(-1, token_addr1, adj_token_id1, t_addr_map1) in
            let t_addr_map1 = update_token_addr_map(1,  token_addr0, adj_token_id0, t_addr_map1) in
            Map.update owner1 (Some(t_addr_map1)) storage
    in
    (* --------------------------------------------
    End of update owner_map.
    *)

    (* --------------------------------------------
    Setup transactions.  token_id0 go to owner1 and token_id1 go to owner0.
    *)

    let transfer_destination0 = get_transfer_destination (owner1, adj_token_id0) in
    let tr0 : transfer = {

        from_ = owner0;
        txs   = transfer_destination0
    } in 

    let transfer_destination1 = get_transfer_destination(owner0, adj_token_id1) in
    let tr1 : transfer = {
        from_ = owner1;
        txs   = transfer_destination1
    } in
    (* Create the transfer operations.*)
    let fa2_tr_operation0: operation = transfer_operation(token_addr0, [tr0]) in
    let fa2_tr_operation1: operation = transfer_operation(token_addr1, [tr1]) in
    (* --------------------------------------------
    End of transactions.
    *)

    [fa2_tr_operation0;fa2_tr_operation1], storage