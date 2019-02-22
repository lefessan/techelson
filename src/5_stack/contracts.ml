open Base
open Common

module Contracts (T : Theo.Sigs.Theory) : Sigs.ContractEnv with module Theory = T = struct
    module Theory = T

    type live = {
        address : Theory.Address.t ;
        contract : Contract.t ;
        mutable balance : Theory.Tez.t ;
        mutable storage : Theory.value ;
        params : Theory.contract_params ;
    }

    type t = {
        mutable defs : (string, Contract.t) Hashtbl.t ;
        mutable key_map : (Theory.KeyH.t, Theory.Address.t) Hashtbl.t ;
        mutable live : (int, live) Hashtbl.t ;
        mutable next_op_uid : int ;
        mutable expired_uids : IntSet.t ;
        mutable typ_cxt : DtypCheck.t
    }

    let expired_uids (self : t) : IntSet.t =
        self.expired_uids

    let empty () : t = {
        defs = Hashtbl.create 47 ;
        key_map = Hashtbl.create 47 ;
        live = Hashtbl.create 47 ;
        next_op_uid = 0 ;
        expired_uids = IntSet.empty () ;
        typ_cxt = DtypCheck.empty () ;
    }

    let clone (self : t) : t = {
        defs = Hashtbl.copy self.defs ;
        key_map = Hashtbl.copy self.key_map ;
        live = Hashtbl.copy self.live ;
        next_op_uid = self.next_op_uid ;
        expired_uids = IntSet.clone self.expired_uids ;
        typ_cxt = DtypCheck.clone self.typ_cxt
    }

    let add (contract : Contract.t) (self : t) : unit =
        if Hashtbl.mem self.defs contract.name then (
            asprintf "trying to register two contracts named `%s`" contract.Contract.name
            |> Exc.throw
        ) else (
            Hashtbl.add self.defs contract.name contract
        )

    let get (name : string) (self : t) : Contract.t =
        (fun () -> Hashtbl.find self.defs name)
        |> Exc.erase_err (
            fun () -> sprintf "could not find contract `%s`" name
        )

    let unify (self : t) (t_1 : Dtyp.t) (t_2 : Dtyp.t) : unit =
        DtypCheck.unify self.typ_cxt t_1 t_2

    module Live = struct
        let update
            (balance : Theory.Tez.t)
            ((storage, dtyp) : Theory.value * Dtyp.t)
            (address : Theory.Address.t)
            (self : t)
            : unit
        =
            let uid = Theory.Address.uid address in
            let live =
                try Hashtbl.find self.live uid with
                | Not_found ->
                    asprintf "cannot update contract at unknown address %a"
                        Theory.Address.fmt address
                    |> Exc.throw
            in
            (fun () -> unify self dtyp live.contract.storage |> ignore)
            |> Exc.chain_err (
                fun () -> asprintf "while updating storage at %a" Theory.Address.fmt address
            );
            live.balance <- balance;
            live.storage <- storage;
            ()

        let fmt (fmt : formatter) (live : live) : unit =
            fprintf fmt "%s (%a) %a"
                live.contract.name
                Theory.Tez.fmt live.balance
                Theory.Address.fmt live.address

        let update_storage
            (self : t)
            (storage : Theory.value)
            (storage_dtyp : Dtyp.t)
            (live : live)
            : unit
        =
            unify self live.contract.storage storage_dtyp
            |> ignore;
            live.storage <- storage

        let count (self : t) : int = Hashtbl.length self.live

        let create
            (params : Theory.contract_params)
            (contract : Contract.t)
            (self : t)
        : unit =
            let address = params.address in
            let uid = Theory.Address.uid address in
            if Hashtbl.mem self.live uid then (
                [
                    asprintf "trying to create two contracts with address `%a`"
                        Theory.Address.fmt address ;
                    asprintf "one called `%s`" contract.name ;
                    asprintf "another one called `%s`" (Hashtbl.find self.live uid).contract.name ;
                ] |> Exc.throws
            ) else (
                let deployed =
                    { address ; contract ; balance = params.tez ; storage = params.value ; params }
                in
                Hashtbl.add self.live uid deployed
            )

        let get (address : Theory.Address.t) (self : t) : live option =
            try Some (Hashtbl.find self.live (Theory.Address.uid address)) with
            | Not_found -> None

        let transfer ~(src : string) (tez : Theory.Tez.t) (live : live) : unit =
            (fun () -> live.balance <- Theory.Tez.add live.balance tez)
            |> Exc.chain_err (
                fun () ->
                    asprintf "while transfering %a from %s to live contract %a"
                        Theory.Tez.fmt tez src fmt live
            )

        let collect ~(tgt : string) (tez : Theory.Tez.t) (live : live) : unit =
            if Theory.Tez.compare live.balance tez >= 0 then (
                live.balance <- Theory.Tez.sub live.balance tez
            ) else
                Exc.Throw.too_poor ~src:live.contract.name ~tgt ~amount:(Theory.Tez.to_native tez)

        let set_delegate (delegate : Theory.KeyH.t option) (self : live) : unit =
            Theory.set_delegate delegate self.params
    end


    let fmt (fmt: formatter) (self : t) : unit =
        fprintf fmt "@[<v>";
        Hashtbl.fold (
            fun _ live is_first ->
                if not is_first then (
                    fprintf fmt "@ "
                );
                Live.fmt fmt live;
                false
        ) self.live true
        |> ignore;
        fprintf fmt "@]"

    type operation = {
        operation : Theory.operation ;
        uid : int ;
    }

    let get_uid (self : t) : int =
        let res = self.next_op_uid in
        self.next_op_uid <- self.next_op_uid + 1;
        res

    module Op = struct
        let fmt (fmt : formatter) (self : operation) : unit =
            Theory.fmt_operation self.uid fmt self.operation

        let uid (self : operation) : int = self.uid

        let op (env : t) (self : operation) : Theory.operation =
            let is_new = IntSet.add self.uid env.expired_uids in
            if is_new then (
                self.operation
            ) else (
                asprintf "cannot run the exact same operation twice: %a"
                    (Theory.fmt_operation self.uid) self.operation
                |> Exc.Throw.tezos
            )

        let must_fail
            (env : t)
            (expected : (Theory.value * Dtyp.t) option)
            (self : operation)
            : Theory.value
        =
            let must_fail_uid = get_uid env in
            Theory.Of.Operation.must_fail must_fail_uid expected (self.operation, self.uid)

        let mk (uid : int) (operation : Theory.operation) : operation =
            { operation ; uid }
    end

    module Account = struct
        let implicit (key : Theory.KeyH.t) (self : t) : live =
            try (
                let address = Hashtbl.find self.key_map key in
                try Theory.Address.uid address |> Hashtbl.find self.live with
                | Not_found ->
                    asprintf "unable to retrieve implicit contract for key hash %a"
                        Theory.KeyH.fmt key
                    |> Exc.throw
            ) with
            | Not_found -> (
                let binding =
                    Some (Theory.KeyH.to_string key |> Annot.Var.of_string)
                in
                let address = Theory.Address.fresh binding in
                Hashtbl.add self.key_map key address;
                let uid = Theory.Address.uid address in
                (
                    try (
                        Hashtbl.find self.live uid |> ignore;
                        asprintf "fresh address for implicit account for %a is not fresh"
                            Theory.KeyH.fmt key
                        |> Exc.throw
                    ) with
                    | Not_found -> ()
                );
                let params =
                    Theory.mk_contract_params
                        ~spendable:true
                        ~delegatable:true
                        key
                        None
                        Theory.Tez.zero
                        address
                        Theory.Of.unit
                in
                Live.create params Contract.unit self;
                try Hashtbl.find self.live uid with
                | Not_found -> Exc.unreachable ()
            )
    end
end
