(** Contract types and helpers. *)

open Common

(** Contract signature. *)
type signature = {
    name : string option ;
    (** Name of the signature (optional). *)
    entry_param : Dtyp.t ;
    (** Type of the entry parameter. *)
}

(** Signature formatter. *)
val fmt_sig : formatter -> signature -> unit

(** A contract. *)
type t = {
    name : string ;
    (** Name of the contract. *)
    source : Source.t option ;
    (** Source of the contract. *)
    storage : Dtyp.t ;
    (** Type of the contract's storage. *)
    entry_param : Dtyp.t ;
    (** Type of the entry parameter. *)
    entry : Mic.t ;
    (** Code of the entry point. *)
    init : Mic.t option ;
    (** Initializer (optional). *)
}

(** Contract constructor.

    The `Source` tracks whether the contract comes from a file or stdin. `None` for anonymous
    contracts. Last parameter is the initializer.
*)
val mk :
    storage:Dtyp.t ->
    entry_param:Dtyp.t ->
    string ->
    Source.t option ->
    Mic.t ->
    Mic.t option ->
    t

(** Conversion from michelson values. *)
val of_mic : Mic.contract -> t

(** Conversion to michelson values. *)
val to_mic : t -> Mic.contract

(** Unit contract. *)
val unit : t

(** Contract formatter. *)
val fmt : full : bool -> formatter -> t -> unit

(** Name of a contract from the name of the file it was loaded from.

    - drops everything befor the last `'/'`
    - drops everything after the first `'.'`
    - capitalizes the first letter.
*)
val name_of_file : string -> string

(** Changes the name of a contract. *)
val rename : string -> t -> t
