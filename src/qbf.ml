
(*
copyright (c) 2013-2014, simon cruanes
all rights reserved.

redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer.  redistributions in binary
form must reproduce the above copyright notice, this list of conditions and the
following disclaimer in the documentation and/or other materials provided with
the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*)

(** {1 Bindings to Quantor} *)

type assignment =
  | True
  | False
  | Undef

type quantifier =
  | Forall
  | Exists

type 'a printer = Format.formatter -> 'a -> unit

(** {2 a QBF literal} *)
module Lit = struct
  type t = int
  (** A boolean literal is only a non-zero integer *)

  let make i =
    if i=0 then raise (Invalid_argument "Lit.make");
    i

  let neg i = ~- i
  let to_int i = abs i

  let equal (i:int) j = i=j
  let compare (i:int) j = Pervasives.compare i j
  let hash i = i land max_int
  let print fmt i =
    if i>0
    then Format.fprintf fmt "L%i" i
    else Format.fprintf fmt "¬L%d" (-i)
end

let print_l ?(sep=",") pp_item fmt l =
  let rec print fmt l = match l with
    | x::((y::xs) as l) ->
      pp_item fmt x;
      Format.pp_print_string fmt sep;
      Format.pp_print_cut fmt ();
      print fmt l
    | x::[] -> pp_item fmt x
    | [] -> ()
  in
  print fmt l

let _print_quant fmt = function
  | Forall -> Format.pp_print_string fmt "∀"
  | Exists -> Format.pp_print_string fmt "∃"

(** {2 A QBF Formula in CNF} *)
module CNF = struct
  type clause = Lit.t list

  type t =
    | Quant of quantifier * Lit.t list * t
    | CNF of clause list

  let quantify q lits f = match lits, f with
    | [], _ -> f
    | _, Quant (q', lits', f') when q=q' ->
        Quant (q, List.rev_append lits lits', f')
    | _ -> Quant (q, lits, f)

  let forall lits f = quantify Forall lits f
  let exists lits f = quantify Exists lits f

  let cnf c = CNF c

  let equal = (=)
  let compare = Pervasives.compare
  let hash = Hashtbl.hash

  let _print_clause ~pp_lit fmt c = match c with
    | [] -> Format.pp_print_string fmt "[]"
    | [x] -> pp_lit fmt x
    | _::_::_ ->
        Format.fprintf fmt "@[<hov 2>(%a)@]" (print_l ~sep:" ∨ " pp_lit) c
  let _print_clauses ~pp_lit fmt l =
    Format.fprintf fmt "@[<hv>%a@]" (print_l ~sep:", " (_print_clause ~pp_lit)) l

  let print_with ~pp_lit fmt f =
    let rec _print fmt f = match f with
      | CNF l -> _print_clauses ~pp_lit fmt l
      | Quant (q,lits,cnf) ->
          Format.fprintf fmt "%a @[%a@].@ %a" _print_quant q
            (print_l ~sep:" " pp_lit) lits _print cnf
    in
    Format.fprintf fmt "@[<hov2>%a@]" _print f

  let print = print_with ~pp_lit:Lit.print
end

(** {2 a QBF formula} *)
module Formula = struct
  type t =
    | Quant of quantifier * Lit.t list * t
    | Form of form
  and form =
    | And of form list
    | Or of form list
    | Imply of form * form
    | XOr of form list  (* exactly one element in the list is true *)
    | Equiv of form list (* all the elements are true, or all of them are false *)
    | True
    | False
    | Not of form
    | Atom of Lit.t

  let true_ = True
  let false_ = False
  let atom l = Atom l
  let form f = Form f

  let neg = function
    | Not f -> f
    | f -> Not f

  let quantify q lits f = match lits, f with
    | [], _ -> f
    | _, Quant (q', lits', f') when q=q'->
        Quant (q, List.rev_append lits lits', f')
    | _ -> Quant (q, lits, f)

  let forall lits f = quantify Forall lits f
  let exists lits f = quantify Exists lits f

  let and_l = function
    | [] -> True
    | [x] -> x
    | l -> And l

  let or_l = function
    | [] -> False
    | [x] -> x
    | l -> Or l

  let xor_l = function
    | [] -> False
    | [x] -> x
    | l -> XOr l

  let equiv_l = function
    | []
    | [_] -> True
    | l -> Equiv l

  let imply a b = match a with
    | False -> True
    | True -> b
    | _ -> Imply (a,b)

  let equal = (=)
  let compare = Pervasives.compare
  let hash = Hashtbl.hash

  let print_with ~pp_lit fmt f =
    let rec print fmt f = match f with
      | Quant (q,lits,f') ->
          Format.fprintf fmt "@[<hov2>%a @[%a@].@ @[%a@]@]" _print_quant q
            (print_l ~sep:" " pp_lit) lits print f'
      | Form f -> print_f fmt f
    and print_f fmt f = match f with
      | Atom a -> pp_lit fmt a
      | True -> Format.pp_print_string fmt "true"
      | False -> Format.pp_print_string fmt "false"
      | Not f -> Format.fprintf fmt "¬ %a" print_f' f
      | And l -> Format.fprintf fmt "@[%a@]" (print_l ~sep:" ∧ " print_f') l
      | Or l -> Format.fprintf fmt "@[%a@]" (print_l ~sep:" v " print_f') l
      | XOr l -> Format.fprintf fmt "@[Xor %a@]" (print_l ~sep:" " print_f') l
      | Equiv l -> Format.fprintf fmt "@[Equiv %a@]" (print_l ~sep:" " print_f') l
      | Imply (a,b) -> Format.fprintf fmt "@[@[%a@] => @[%a@]@]" print_f' a print_f' b
    and print_f' fmt f = match f with
      | Atom _
      | True
      | False -> print_f fmt f
      | _ -> Format.fprintf fmt "@[(%a)@]" print_f f
    in print fmt f

  let print = print_with ~pp_lit:Lit.print

  let rec simplify = function
    | Quant (q, lits, f) -> Quant (q, lits, simplify f)
    | Form f -> Form (simplify_f f)
  and simplify_f = function
    | Not f -> _neg_simplify f
    | And l -> and_l (List.rev_map simplify_f l)
    | Or l -> or_l (List.rev_map simplify_f l)
    | Atom _ as f -> f
    | Imply (a, b) -> imply (simplify_f a) (simplify_f b)
    | XOr l -> xor_l (List.map simplify_f l)  (* TODO *)
    | Equiv l -> equiv_l (List.map simplify_f l)
    | (True | False) as f -> f
  and _neg_simplify = function
    | Atom l -> Atom (Lit.neg l)
    | And l -> Or (List.map _neg_simplify l)
    | Or l -> And (List.map _neg_simplify l)
    | XOr l -> Not (XOr l)
    | Equiv l -> Not (Equiv l)
    | Imply (a,b) -> and_l [a; _neg_simplify b]
    | Not f -> simplify_f f
    | True -> False
    | False -> True

  (* polarity of a subformula: number of negation on the path to the root *)
  type polarity =
    | Plus
    | Minus

  let _neg_pol = function
    | Plus -> Minus
    | Minus -> Plus

  (* Reduce formula to cnf *)
  module CnfAlgo = struct

    type ctx = {
      gensym : unit -> Lit.t;
      meet_lits : Lit.t list -> unit; (* those lits are quantified *)
      add_clauses : CNF.clause list -> unit; (* declare clauses *)
      get_clauses : unit -> CNF.clause list; (* all clauses so far *)
      get_newlits : unit -> Lit.t list;  (* gensym'd literals *)
    }

    let mk_ctx () =
      let _maxvar = ref 0 in
      let _clauses = ref [] in
      let _newlits = ref [] in
      { gensym=(fun () ->
          incr _maxvar;
          let x = !_maxvar in
          _newlits := x :: !_newlits;
          x
        );
        meet_lits=(fun lits ->
          List.iter (fun i -> _maxvar := max !_maxvar (Lit.to_int i)) lits
        );
        add_clauses=(fun cs -> _clauses := List.rev_append cs !_clauses);
        get_clauses=(fun () -> !_clauses);
        get_newlits=(fun () -> !_newlits);
      }

    (* rename [And_{c in clauses} c] into an atom *)
    let rename_clauses ~ctx clauses =
      let x = ctx.gensym() in
      (* definition of [x]: [not x or c] for every [c] in [clauses] *)
      let side_clauses = List.rev_map
        (fun c -> Lit.neg x :: c)
        clauses
      in
      ctx.add_clauses side_clauses;
      x

    (* list of [f (x,y)] for [x,y] elements of [l] with x occurring before y *)
    let map_diagonal f l =
      let rec gen acc l = match l with
      | [] -> acc
      | x::l' ->
        let acc = List.fold_left (fun acc y -> f x y :: acc) acc l' in
        gen acc l'
      in
      gen [] l

    (* reduce quantifier-free formula to CNF, with Tseitin transformation
      (see https://en.wikipedia.org/wiki/Tseitin_transformation).
      @param acc the list of clauses produced so far
      @param pol the polarity of [f]
      @param gensym generator of fresh *)
    let rec cnf_f ~ctx ~pol acc f = match f, pol with
      | Not f', _ -> cnf_f ~ctx ~pol:(_neg_pol pol) acc f'
      (* trivial cases *)
      | True, Plus
      | False, Minus -> acc  (* tautology *)
      | True, Minus
      | False, Plus -> []::acc  (* empty clause *)
      | Atom a, Plus -> [a]::acc
      | Atom a, Minus -> [Lit.neg a]::acc
      (* and/or-cases *)
      | (Or [] | And [] | XOr [] | Equiv []), _ -> assert false
      | And l, Plus
      | Or l, Minus ->
          List.fold_left (fun acc f' -> cnf_f ~ctx ~pol acc f' ) acc l
      | And (a::l), Minus ->
          let a' = cnf_f ~ctx ~pol [] a in
          let l' = List.map (cnf_f ~ctx ~pol []) l in
          cnf_list ~ctx acc a' l'
      | Or (a::l), Plus ->
          (* CNF of each sub-formula *)
          let a' = cnf_f ~ctx ~pol [] a in
          let l' = List.map (cnf_f ~ctx ~pol []) l in
          (* now express the disjunction of those lists of clauses. For each
              list, we can rename it or just use it *)
          cnf_list ~ctx acc a' l'
      (* specials *)
      | Imply (a,b), Plus ->
          cnf_list ~ctx acc
            (cnf_f ~ctx ~pol:Minus [] a)
            [cnf_f ~ctx ~pol:Plus [] b]
      | Imply (a,b), Minus ->
          (* not (a=>b) ----->   a and not b *)
          let acc = cnf_f ~ctx ~pol:Plus acc a in
          let acc = cnf_f ~ctx ~pol:Minus acc b in
          acc
      | XOr l, _ ->
          (* TODO: efficient version *)
          (* right now, it's
            (Or_{f in l} f) and (And_{f,f' in l, f!=f'} not f or not f')
            *)
          let f = and_l
            (or_l l :: map_diagonal (fun a b -> or_l [neg a; neg b]) l)
          in
          cnf_f ~ctx ~pol acc f
      | Equiv l, _ ->
          (* TODO: efficient version *)
          (* right now, it's  (And_{f in l} f) or (And_{f in l} not f) *)
          let f = or_l [ and_l l; and_l (List.map neg l) ] in
          cnf_f ~ctx ~pol acc f

    (* basically, [cartesian_product previous (cnf l)], but smarter. Adds
        its result to [acc] *)
    and cnf_list ~ctx acc previous l = match l with
      | [] -> List.rev_append previous acc
      | [] :: _ -> acc (* trivial, so product is trivial *)
      | [c] :: tail ->
          (* add [c] to every clause so far *)
          let previous = List.rev_map (fun c' -> List.rev_append c c') previous in
          cnf_list ~ctx acc previous tail
      | clauses :: tail ->
          (* rename [clauses] into a new atom *)
          let x = rename_clauses ~ctx clauses in
          let previous = List.rev_map (fun c' -> x::c') previous in
          cnf_list ~ctx acc previous tail

    (* traverse prenex quantifiers, and convert inner formula into CNF *)
    let rec traverse ~ctx:ctx f = match f with
      | Quant (q, lits, f') ->
          ctx.meet_lits lits;
          CNF.quantify q lits (traverse ~ctx f')
      | Form f ->
          (* CNF of [f], plus a list of new variables to quantify on
            and side clauses that define those variables *)
          let clauses = cnf_f ~ctx ~pol:Plus [] f in
          let clauses' = ctx.get_clauses() in
          let cnf = CNF.cnf (List.rev_append clauses' clauses) in
          CNF.exists (ctx.get_newlits ()) cnf
  end

  let cnf f = CnfAlgo.traverse ~ctx:(CnfAlgo.mk_ctx()) f
end

(** {2 Solvers} *)

type result =
  | Unknown
  | Sat of (Lit.t -> assignment)
  | Unsat
  | Timeout
  | Spaceout

type solver = {
  name : string;
  solve : CNF.t -> result;
}

let solve ~solver cnf =
  solver.solve cnf