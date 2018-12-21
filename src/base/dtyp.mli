(** Datatype types and helpers. *)

open Common

(** Nullary datatypes. *)
type leaf =
| Str
| Nat
| Int
| Bytes
| Bool
| Unit
| Mutez
| Address
| Operation
| Key
| KeyH
| Signature
| Timestamp

(** Formatter for nullary datatypes. *)
val fmt_leaf : formatter -> leaf -> unit

(** String to leaf conversion. *)
val leaf_of_string : string -> leaf option

(** Wraps a datatype with a name. *)
type named = {
  inner : t ;
  name : Annot.Field.t option ;
}

(** Nameless datatype. *)
and dtyp =
| Leaf of leaf

| List of t
| Option of t
| Set of t
| Contract of t

| Pair of named * named
| Or of named * named
| Map of t * t
| BigMap of t * t

(** Datatypes. *)
and t = {
  typ : dtyp ;
  alias : Annot.Typ.t option ;
}

(** Named datatype constructor. *)
val mk : ?alias : Annot.Typ.t option -> dtyp -> t

(** Formatter for datatypes. *)
val fmt : formatter -> t -> unit
