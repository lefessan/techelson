(* Types and helpers for macro expansion. *)

module Utils = struct
    let macro_op_to_mic (vars : Annot.vars) (op : Mic.Macro.op) : Mic.t =
        let leaf : Mic.leaf =
            match op with
            | Mic.Macro.Eq -> Eq
            | Mic.Macro.Neq -> Neq
            | Mic.Macro.Lt -> Lt
            | Mic.Macro.Le -> Le
            | Mic.Macro.Ge -> Ge
            | Mic.Macro.Gt -> Gt
        in
        Mic.mk ~vars:(vars) (Mic.Leaf leaf)
end

let macro_cmp (vars : Annot.vars) (op : Mic.Macro.op) : Mic.t list = [
    Mic.mk_leaf Mic.Compare ;
    Utils.macro_op_to_mic vars op ;
]
let macro_if (op : Mic.Macro.op) (i_1 : Mic.t) (i_2 : Mic.t) : Mic.t list = [
    Utils.macro_op_to_mic [] op ;
    Mic.If (i_1, i_2) |> Mic.mk ;
]
let macro_if_cmp (op : Mic.Macro.op) (i_1 : Mic.t) (i_2 : Mic.t) : Mic.t list = [
    Mic.mk_leaf Mic.Compare ;
    Utils.macro_op_to_mic [] op ;
    Mic.If (i_1, i_2) |> Mic.mk ;
]

let macro_fail : Mic.t list = [
    Mic.mk_leaf Mic.Unit ;
    Mic.mk_leaf Mic.Failwith ;
]

let macro_assert : Mic.t list = [
    Mic.If (Mic.mk_seq [],  Mic.mk_seq macro_fail) |> Mic.mk ;
]

let macro_assert_ (op : Mic.Macro.op) : Mic.t list =
    macro_if op (Mic.mk_seq []) (Mic.mk_seq macro_fail)

let macro_assert_cmp (op : Mic.Macro.op) : Mic.t list =
    macro_if_cmp op (Mic.mk_seq []) (Mic.mk_seq macro_fail)

let macro_assert_none : Mic.t list = [
    Mic.IfNone (Mic.mk_seq [], Mic.mk_seq macro_fail) |> Mic.mk ;
]

let macro_assert_some : Mic.t list = [
    Mic.IfNone (Mic.mk_seq macro_fail, Mic.mk_seq []) |> Mic.mk ;
]

let macro_assert_left : Mic.t list = [
    Mic.IfLeft (Mic.mk_seq [], Mic.mk_seq macro_fail) |> Mic.mk ;
]

let macro_assert_right : Mic.t list = [
    Mic.IfLeft (Mic.mk_seq macro_fail, Mic.mk_seq []) |> Mic.mk ;
]

let macro_dip (n : int) (code : Mic.t) : Mic.t list =
    assert (n > 0);
    (* Note that `DIIP <code>` expands to `DIP (DIP <code>)`.
        Hence we're generating `n + 1` nested `DIP`s.
    *)
    let rec loop (acc : Mic.t) (count : int) : Mic.t =
        if count > 0 then loop (Mic.Dip acc |> Mic.mk) (count - 1)
        else acc
    in
    [ loop (Mic.Dip code |> Mic.mk) n ]

let macro_dup (annot : Annot.vars) (n : int) : Mic.t list =
    assert (n > 0);
    (* Note that `DUUP <code>` expands to `DIP (DUP <code>)`.
        Hence we're generating `n + 1` nested `DIP`s.
    *)
    let rec loop (acc : Mic.t) (count : int) : Mic.t =
        if count > 0 then (
            let dip = Mic.Dip acc |> Mic.mk in
            let swap = Mic.Swap |> Mic.mk_leaf in
            let seq = Mic.Seq [dip ; swap] |> Mic.mk in
            loop seq (count - 1)
        ) else acc
    in
    [ loop (Mic.Dup |> Mic.mk_leaf ~vars:annot) n ]

(* The following deals with pairs...

    The way this is done is by constructing an intermediary tree. This step can be removed but
    for now that's how it works.
    
    The types/helpers below are for tree construction. `pre_tree` is the type of the frames of
    the stack maintained. A frame corresponds to a pair constructor. When tree building goes
    up, meaning a tree was constructed, it looks at the top of the stack and checks whether i)
    we're done, ii) we just built the left part of a pair (and need to do the right one), or
    iii) we just built the right part of a pair and need to combine it with its left part.
*)
module PairHelp = struct
    (* Bail for pair macro expansion. *)
    let bail_pair (n : int) : 'a =
        Format.sprintf "illegal sequence of characters (%i)" n |> Exc.throw

    (* Intermediary structure generated by the function below. *)
    type tree =
    | LeafI
    | LeafA
    | Pair of tree * tree

    (* Stack frame: when building the tree and going up, this tells us what to do.

        Values of this type are added to the stack when reading a pair `P` constructor.
    *)
    type pre_tree =
    (* Initial stack frame pushed when running in a pair constructor. When going up, it means "keep
        reading for the right part of the pair".
    *)
    | PairLeft
    (* When going up the variant above, we need to remember the tre constructed for the left branch
        of the pair. This variant stores it.

        When going up, it means "keep going up by combining this tree and the tree you just
        constructed".
    *)
    | PairRight of tree

    (* Tree formatter, for debugging. Not tailrec. *)
    (* let rec fmt_tree (fmt : formatter) (tree : tree) =
        match tree with
        | LeafI -> fprintf fmt "I"
        | LeafA -> fprintf fmt "A"
        | Pair (lft, rgt) -> fprintf fmt "P(%a,%a)" fmt_tree lft fmt_tree rgt *)

    (* Turns a sequence of pair operators into a tree.

        This is used to expand `P[AIP]+R` and `UNP[AIP]+R` macros.
    *)
    let macro_pair_to_tree (ops : Mic.Macro.pair_op list) : tree =

        (* Look at the stream of pair operators and decide what to do. *)
        let rec go_down
            (stack : pre_tree list)
            (to_do : Mic.Macro.pair_op list)
            : tree
        =
            (* log_1 "down (%i)@." (List.length to_do); *)
            match to_do with

            (* Going up from the left branch. *)
            | A :: to_do ->
                (* log_1 "  A@."; *)
                go_up stack to_do LeafA

            (* Going up from the right branch. *)
            | I :: to_do ->
                (* log_1 "  I@."; *)
                go_up stack to_do LeafI

            (* Go down the left part of a pair constructor. *)
            | P :: to_do ->
                (* log_1 "  P@."; *)
                go_down (PairLeft :: stack) to_do

            | [] -> bail_pair 1

        (* Given a tree, check the stack and decide to go up or down. *)
        and go_up
            (stack : pre_tree list)
            (to_do : Mic.Macro.pair_op list)
            (tree : tree)
            : tree
        =
            (* log_1 "up %a@." fmt_tree tree; *)
            match stack with

            (* Going up a left branch, need to go down the left branch now. *)
            | PairLeft :: stack ->
                (* log_1 "  P left@."; *)
                go_down ((PairRight tree) :: stack) to_do

            (* Going up a right branch from a pair constructor. *)
            | (PairRight left_branch) :: stack -> 
                (* log_1 "  P right@."; *)
                go_up stack to_do (Pair (left_branch, tree))

            (* Reached the top of the stack, there should be no operator left. *)
            | [] -> if to_do = [] then tree else bail_pair 2
        in

        ops |> go_down []

    (* This type encodes the type of stack frames when expanding the tree.

        The process builds a list of instructions, and this types says what to do with it.

        Each variant corresponds to one of the `A`, `I` and `P` pair operators. The last two
        variants deal with `P`.
    *)
    type stack_frame =
    (* Going up an `A`: `DIP` the instructions and add `PAIR` at the end. *)
    | UppDipPost of Annot.fields
    (* Going up an `I`: add `PAIR` at the beginning. *)
    | UppPref
    (* Going up a partial `P`: current instructions describe the left part. This tree is the right
        part. We need to go down this tree and remember the left part using the `Upp` variant
        below.
    *)
    | Dwn of tree
    (* Going up a `P` for which we have the left part. Current instructions are the right part.
        Done, concatenate and add `PAIR` at the end. *)
    | Upp of Mic.t list

    (* Splits a list into its head and its tail. *)
    let lst_split (l : 'a list) : ('a list * 'a list) =
        match l with
        | head :: tail -> [head], tail
        | [] -> [], []

    (* Turns a tree for a pair macro into a list of instructions. *)
    let macro_pair_tree_to_list
        (vars : Annot.vars)
        (fields : Annot.fields)
        (tree : tree)
        : Mic.t list
    =
        let pair (stack : 'a list) (fields : Annot.fields) : Mic.t =
            if stack = [] then Mic.mk_leaf ~vars:vars ~fields:fields Mic.Pair
            else Mic.mk_leaf ~fields:fields Mic.Pair
        in
        (* Go down the tree and decide what to do. *)
        let rec go_down
            (fields : Annot.fields)
            (stack : stack_frame list)
            (tree : tree)
            : Mic.t list
        =
            match tree with
            (* Simple pair constructor. *)
            | Pair (LeafA, LeafI) ->
                let field_a, fields = lst_split fields in
                let field_b, fields = lst_split fields in
                go_up fields stack [pair stack (field_a @ field_b)]
            (* Left part is fine, go down the left part. *)
            | Pair (LeafA, right) ->
                let field, fields = lst_split fields in
                go_down fields ((UppDipPost field) :: stack) right
            (* Right part is fine, go down the left part. *)
            | Pair (left, LeafI) ->
                go_down fields (UppPref :: stack) left
            (* Go down left first, then right. *)
            | Pair (left, right) ->
                go_down fields (
                    (Dwn right) :: stack
                ) left
            (* Everything else should be illegal. *)
            | _ -> bail_pair 3
        (* Go up the stack, building the instructions as we go. *)
        and go_up
            (fields : Annot.fields)
            (stack : stack_frame list)
            (lst : Mic.t list)
            : Mic.t list
        =
            match stack with
            (* Going up an `A`: `DIP` instructions and add `PAIR` at the end. *)
            | (UppDipPost field) :: stack ->
                let pair_fields = if field <> [] then field @ [Annot.Field.wild] else [] in
                let dipped = Mic.Dip (Mic.mk_seq lst) |> Mic.mk in
                let pair = pair stack pair_fields in
                go_up fields stack [dipped ; pair]
            (* Going up an `I`: prefix with `PAIR`. *)
            | UppPref :: stack ->
                let field, fields = lst_split fields in
                let pair_fields = if field <> [] then Annot.Field.wild :: field else [] in
                let pair = pair stack pair_fields in
                go_up fields stack (lst @ [pair])
            (* Need to go down `tree`, memorize `lst` in the stack for later. *)
            | (Dwn tree) :: stack ->
                go_down fields ((Upp lst) :: stack) tree
            (* We have the left (`pref`) and right (`lst`) instructions, just need to build the
                pair.
            *)
            | (Upp pref) :: stack ->
                let pair = pair stack [] in
                go_up fields stack (pref @ lst @ [pair])
            (* We drained the stack, done. *)
            | [] -> lst
        in
        go_down fields [] tree

    (* This type encodes the type of stack frames when expanding the tree.

        The process builds a list of instructions, and this types says what to do with it.

        Each variant corresponds to one of the `A`, `I` and `P` pair operators. The last two
        variants deal with `P`.
    *)
    type un_stack_frame =
    (* Going up an `A`: `DIP` the instructions and add `UNPAIR` at the beginning. *)
    | UppDipPref of Annot.vars
    (* Going up an `I`: add `PAIR` at the beginning. *)
    | UppPref
    (* Going up a partial `P`: current instructions describe the left part. This tree is the right
        part. We need to go down this tree and remember the left part using the `Upp` variant
        below.
    *)
    | Dwn of tree
    (* Going up a `P` for which we have the left part. Current instructions are the right part.
        Done, concatenate and add `PAIR` at the end. *)
    | Upp of Mic.t list

    (* Sequence of instructions corresponding to `UNPAIR`. *)
    let unpair_inss (vars : Annot.vars) (left : bool) (right : bool) : Mic.t list * Annot.vars =
        let car_annot, vars = if left then lst_split vars else [], vars in
        let cdr_annot, vars = if right then lst_split vars else [], vars in
        [
            Mic.Dup |> Mic.mk_leaf ;
            Mic.Car |> Mic.mk_leaf ~vars:car_annot ;
            Mic.Dip (Mic.Cdr |> Mic.mk_leaf ~vars:cdr_annot) |> Mic.mk ;
        ], vars

    (* Turns a tree for an unpair macro into a list of instructions. *)
    let macro_unpair_tree_to_list (vars : Annot.vars) (tree : tree) : Mic.t list =
        (* Go down the tree and decide what to do. *)
        let rec go_down
            (vars : Annot.vars)
            (stack : un_stack_frame list)
            (tree : tree)
            : Mic.t list
        =
            match tree with
            (* Simple pair deconstructor. *)
            | Pair (LeafA, LeafI) ->
                let inss, vars = unpair_inss vars true true in
                go_up vars stack inss
            (* Left part is fine, go down the left part. *)
            | Pair (LeafA, right) ->
                let annot, vars = lst_split vars in
                go_down vars ((UppDipPref annot) :: stack) right
            (* Right part is fine, go down the right part. *)
            | Pair (left, LeafI) -> go_down vars (UppPref :: stack) left
            (* Go down left first, then right. *)
            | Pair (left, right) -> go_down vars (
                (Dwn right) :: stack
            ) left
            (* Everything else should be illegal. *)
            | _ -> bail_pair 4
        (* Go up the stack, building the instructions as we go. *)
        and go_up
            (vars : Annot.vars)
            (stack : un_stack_frame list)
            (lst : Mic.t list)
            : Mic.t list
        =
            match stack with
            (* Going up an `A`: `DIP` instructions and add `UNPAIR` at the beginning. *)
            | (UppDipPref annot) :: stack ->
                let dipped = Mic.Dip (Mic.mk_seq lst) |> Mic.mk in
                let inss, _ = unpair_inss annot true false in
                inss @ [ dipped ] |> go_up vars stack
            (* Going up an `I`: prefix with `UNPAIR`. *)
            | UppPref :: stack ->
                let inss, vars = unpair_inss vars false true in
                inss @ lst |> go_up vars stack
            (* Need to go down `tree`, memorize `lst` in the stack for later. *)
            | (Dwn tree) :: stack ->
                go_down vars ((Upp lst) :: stack) tree
            (* We have the left (`lft`) and right (`lst`) instructions, just need to build the
                pair.
            *)
            | (Upp lft) :: stack ->
                let inss, vars = unpair_inss vars false false in
                go_up vars stack (inss @ lft @ lst)
            (* We drained the stack, done. *)
            | [] -> lst
        in
        go_down vars [] tree

    (* Helper for `SET_C[AD]+R` and `MAP_C[AD]+R`.
    
        Takes the sequence of instruction leaves (`A` or `D`) correspond to. *)
    let macro_cadr_ins
        (vars : Annot.vars)
        (leaf_A : (bool -> Mic.t list))
        (leaf_D : (bool -> Mic.t list))
        (ops : Mic.Macro.unpair_op list)
        : Mic.t list
    =
        (* Go down the list of operators. This function only calls `go_up` when it ran out of
            operators.
        *)
        let rec go_down
            (vars : Annot.vars)
            (stack : (Mic.t list * Mic.t * Mic.t list) list)
            (ops : Mic.Macro.unpair_op list)
            : Mic.t list
        =
            match ops with
            | [A] -> go_up stack (stack = [] |> leaf_A)
            | [D] -> go_up stack (stack = [] |> leaf_D)
            | A :: ops ->
                go_down
                    []
                    (
                        (
                            [ Mic.mk_leaf Mic.Dup ],
                            Mic.mk_leaf Mic.Car,
                            [
                                Mic.mk_leaf Mic.Cdr ;
                                Mic.mk_leaf Mic.Swap ;
                                Mic.mk_leaf ~vars:vars Mic.Pair
                            ]
                        ) :: stack
                    )
                    ops
            | D :: ops ->
                go_down
                    []
                    (
                        (
                            [ Mic.mk_leaf Mic.Dup ],
                            Mic.mk_leaf Mic.Cdr,
                            [
                                Mic.mk_leaf Mic.Car ;
                                Mic.mk_leaf ~vars:vars Mic.Pair
                            ]
                        ) :: stack
                    )
                    ops
            | [] -> Exc.unreachable ()

        (* Goes up the stack constructing the instruction list. *)
        and go_up
            (stack : (Mic.t list * Mic.t * Mic.t list) list)
            (lst : Mic.t list)
            : Mic.t list
        =
            match stack with
            | (pref, ins, suff) :: stack ->
                let inner =
                    Mic.Dip (ins :: lst |> Mic.mk_seq) |> Mic.mk
                in
                inner :: suff |> List.rev_append pref |> go_up stack
            | [] -> lst
        in
        go_down vars [] ops
end

let macro_pair
    (vars : Annot.vars)
    (fields : Annot.fields)
    (ops : Mic.Macro.pair_op list)
    : Mic.t list
=
    PairHelp.macro_pair_to_tree ops |> PairHelp.macro_pair_tree_to_list vars fields

let macro_unpair (vars : Annot.vars) (ops : Mic.Macro.pair_op list) : Mic.t list =
    PairHelp.macro_pair_to_tree ops |> PairHelp.macro_unpair_tree_to_list vars

let macro_cadr
    (vars : Annot.vars)
    (fields : Annot.fields)
    (ops : Mic.Macro.unpair_op list)
    : Mic.t list
=
    let rec loop (acc : Mic.t list) (ops : Mic.Macro.unpair_op list) : Mic.t list =
        match ops with
        | A :: ops -> loop ((Mic.mk_leaf ~vars:vars ~fields:fields Mic.Car) :: acc) ops
        | D :: ops -> loop ((Mic.mk_leaf ~vars:vars ~fields:fields Mic.Cdr) :: acc) ops
        | [] -> List.rev acc
    in
    loop [] ops

let macro_set_cadr
    (vars : Annot.vars)
    (fields : Annot.fields)
    (ops : Mic.Macro.unpair_op list)
    : Mic.t list
=
    PairHelp.macro_cadr_ins
        vars
        (* Instructions for `SET_CAR`. *)
        (
            fun is_top ->
                let last_pair = if is_top then Mic.mk_leaf ~vars:vars Pair else Mic.mk_leaf Pair in
                [ Mic.mk_leaf ~fields:fields Cdr ; Mic.mk_leaf Swap ; last_pair ]
        )
        (* Instructions for `SET_CDR`. *)
        (
            fun is_top ->
                let last_pair = if is_top then Mic.mk_leaf ~vars:vars Pair else Mic.mk_leaf Pair in
                [ Mic.mk_leaf ~fields:fields Car ; last_pair ]
        )
        ops

let macro_map_cadr
    (vars : Annot.vars)
    (fields : Annot.fields)
    (ops : Mic.Macro.unpair_op list)
    (ins : Mic.t)
    : Mic.t list
=
    PairHelp.macro_cadr_ins
        vars
        (* Instructions for `MAP_CAR`. *)
        (
            fun is_top ->
                let last_pair = if is_top then Mic.mk_leaf ~vars:vars Pair else Mic.mk_leaf Pair in
                [
                    Mic.mk_leaf Dup ;
                    Mic.mk_leaf Cdr ;
                    Mic.Dip (
                        [ Mic.mk_leaf ~fields:fields Car ; ins ] |> Mic.mk_seq
                    ) |> Mic.mk ;
                    Mic.mk_leaf Swap ;
                    last_pair
                ]
        )
        (* Instructions for `MAP_CDR`. *)
        (
            fun is_top ->
                let last_pair = if is_top then Mic.mk_leaf ~vars:vars Pair else Mic.mk_leaf Pair in
                [
                    Mic.mk_leaf Dup ;
                    Mic.mk_leaf Cdr ~fields:fields ;
                    ins ;
                    Mic.mk_leaf Swap ;
                    Mic.mk_leaf Car ;
                    last_pair
                ]
        )
        ops

let macro_if_some (ins_1 : Mic.t) (ins_2 : Mic.t) : Mic.t list =
    [ Mic.IfNone (ins_2, ins_1) |> Mic.mk ]

let macro_int : Mic.t list =
    [ Mic.Cast (Dtyp.mk_leaf Dtyp.Int) |> Mic.mk ]
