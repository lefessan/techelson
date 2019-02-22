(** Datatype types and helpers. *)

open Common

(** Type of type variables. *)
type tvar = int

(** Formats type variables. *)
val fmt_tvar : formatter -> tvar -> unit

(** Generates a fresh type variable. *)
val fresh_tvar : unit -> tvar

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
| Var of tvar

(** Formatter for nullary datatypes. *)
val fmt_leaf : formatter -> leaf -> unit

(** String to leaf conversion. *)
val leaf_of_string : string -> leaf option

(** Type of type aliases. *)
type alias = Annot.Typ.t option

(** Wraps a datatype with a name. *)
type named = {
    inner : t ;
    (** Actual datatype. *)
    name : Annot.Field.t option ;
    (** Field annotation. *)
}

(** Nameless datatype. *)
and dtyp =
| Leaf of leaf

| Pair of named * named
| Or of named * named
| Option of named

| List of t
| Set of t
| Contract of t

| Map of t * t
| BigMap of t * t
| Lambda of t * t

(** Datatype with an alias. *)
and t = {
    typ : dtyp ;
    (** Actual datatype. *)
    alias : alias ;
    (** Type annotation. *)
}

(** Named datatype constructor. *)
val mk : ?alias : alias -> dtyp -> t

(** Constructs a datatype with a field annotation. *)
val mk_named : Annot.Field.t option -> t -> named

(** Named datatype constructor from a leaf. *)
val mk_leaf : ?alias : alias -> leaf -> t

(** Creates a fresh type variable. *)
val mk_var : ?alias : alias -> unit -> t

(** True if the type is comparable. *)
val is_comparable : t -> bool

(** Renames a datatype. *)
val rename : alias -> t -> t

(** Renames a datatype if the alias is `Some`. *)
val rename_if_some : alias -> t -> t

(** Formatter for datatypes. *)
val fmt : formatter -> t -> unit

(** The unit type *)
val unit : t

(** The integer type. *)
val int : t

(** The natural type. *)
val nat : t

(** The timestamp type. *)
val timestamp : t

(** Type destructors. *)
module Inspect : sig
    (** Retrieves the two type parameters of a union type. *)
    val either : t -> t * t

    (** Retrieves the type parameter of an option type. *)
    val option : t -> t

    (** Retrieves the type parameter of a list type. *)
    val list : t -> t

    (** Retrieves the two type parameters of a pair. *)
    val pair : t -> t * t

    (** Retrieves the type parameter of a set. *)
    val set : t -> t

    (** Retrieves the two type parameters of a map or a bigmap. *)
    val map : t -> t * t

    (** Retrieves the type of the elements taken by an iterator over some collection. *)
    val iter_elm : t -> t

    (** Retrieves the two type parameters of a lambda. *)
    val lambda : t -> t * t
end