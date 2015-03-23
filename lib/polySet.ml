(*********************************************************************)
(*                        DIY                                        *)
(*                                                                   *)
(* Luc Maranget, INRIA Paris-Rocquencourt, France.                   *)
(*                                                                   *)
(*  Copyright 2015 Institut National de Recherche en Informatique et *)
(*  en Automatique and the authors. All rights reserved.             *)
(*  This file is distributed  under the terms of the Lesser GNU      *)
(*  General Public License.                                          *)
(*********************************************************************)

(* Cloned from *)

(***********************************************************************)
(*                                                                     *)
(*                                OCaml                                *)
(*                                                                     *)
(*            Xavier Leroy, projet Cristal, INRIA Rocquencourt         *)
(*                                                                     *)
(*  Copyright 1996 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the GNU Library General Public License, with    *)
(*  the special exception on linking described in file ../LICENSE.     *)
(*                                                                     *)
(***********************************************************************)

module type OrderedType =
  sig
    type 'k t
    val compare: 'k t -> 'k t -> int
  end

module type S =
  sig
    type 'k elt
    type 'k t
    val empty:'k t
    val is_empty:'k t -> bool
    val mem:'k elt ->'k t -> bool
    val add:'k elt ->'k t ->'k t
    val singleton:'k elt ->'k t
    val remove:'k elt ->'k t ->'k t
    val union:'k t ->'k t ->'k t
    val inter:'k t ->'k t ->'k t
    val diff:'k t ->'k t ->'k t
    val compare:'k t ->'k t -> int
    val equal:'k t ->'k t -> bool
    val subset:'k t ->'k t -> bool
    val iter: ('k elt -> unit) ->'k t -> unit
    val fold: ('k elt -> 'a -> 'a) ->'k t -> 'a -> 'a
    val for_all: ('k elt -> bool) ->'k t -> bool
    val exists: ('k elt -> bool) ->'k t -> bool
    val filter: ('k elt -> bool) ->'k t ->'k t
    val partition: ('k elt -> bool) ->'k t ->'k t *'k t
    val cardinal:'k t -> int
    val elements:'k t ->'k elt list
    val min_elt:'k t ->'k elt
    val max_elt:'k t ->'k elt
    val choose:'k t ->'k elt
    val split:'k elt ->'k t ->'k t * bool *'k t
    val find:'k elt ->'k t ->'k elt
    val of_list:'k elt list ->'k t
    val pp:
        out_channel -> string ->
      (out_channel -> 'k elt -> unit) -> 'k t -> unit
    val pp_str: string -> ('k elt -> string) -> 'k t -> string
    val unions: 'k t list -> 'k t
  end

module Make(Ord: OrderedType) =
  struct
    type 'k elt = 'k Ord.t
    type 'k t = Empty | Node of 'k t *'k elt * 'k t * int

    (* Sets are represented by balanced binary trees (the heights of the
       children differ by at most 2 *)

    let height = function
        Empty -> 0
      | Node(_, _, _, h) -> h

    (* Creates a new node with left son l, value v and right son r.
       We must have all elements of l < v < all elements of r.
       l and r must be balanced and | height l - height r | <= 2.
       Inline expansion of height for better speed. *)

    let create l v r =
      let hl = match l with Empty -> 0 | Node(_,_,_,h) -> h in
      let hr = match r with Empty -> 0 | Node(_,_,_,h) -> h in
      Node(l, v, r, (if hl >= hr then hl + 1 else hr + 1))

    (* Same as create, but performs one step of rebalancing if necessary.
       Assumes l and r balanced and | height l - height r | <= 3.
       Inline expansion of create for better speed in the most frequent case
       where no rebalancing is required. *)

    let bal l v r =
      let hl = match l with Empty -> 0 | Node(_,_,_,h) -> h in
      let hr = match r with Empty -> 0 | Node(_,_,_,h) -> h in
      if hl > hr + 2 then begin
        match l with
          Empty -> invalid_arg "Set.bal"
        | Node(ll, lv, lr, _) ->
            if height ll >= height lr then
              create ll lv (create lr v r)
            else begin
              match lr with
                Empty -> invalid_arg "Set.bal"
              | Node(lrl, lrv, lrr, _)->
                  create (create ll lv lrl) lrv (create lrr v r)
            end
      end else if hr > hl + 2 then begin
        match r with
          Empty -> invalid_arg "Set.bal"
        | Node(rl, rv, rr, _) ->
            if height rr >= height rl then
              create (create l v rl) rv rr
            else begin
              match rl with
                Empty -> invalid_arg "Set.bal"
              | Node(rll, rlv, rlr, _) ->
                  create (create l v rll) rlv (create rlr rv rr)
            end
      end else
        Node(l, v, r, (if hl >= hr then hl + 1 else hr + 1))

    (* Insertion of one element *)

    let rec add x = function
        Empty -> Node(Empty, x, Empty, 1)
      | Node(l, v, r, _) as t ->
          let c = Ord.compare x v in
          if c = 0 then t else
          if c < 0 then bal (add x l) v r else bal l v (add x r)

    let singleton x = Node(Empty, x, Empty, 1)

    (* Beware: those two functions assume that the added v is *strictly*
       smaller (or bigger) than all the present elements in the tree; it
       does not test for equality with the current min (or max) element.
       Indeed, they are only used during the "join" operation which
       respects this precondition.
    *)

    let rec add_min_element v = function
      | Empty -> singleton v
      | Node (l, x, r, _h) ->
        bal (add_min_element v l) x r

    let rec add_max_element v = function
      | Empty -> singleton v
      | Node (l, x, r, _h) ->
        bal l x (add_max_element v r)

    (* Same as create and bal, but no assumptions are made on the
       relative heights of l and r. *)

    let rec join l v r =
      match (l, r) with
        (Empty, _) -> add_min_element v r
      | (_, Empty) -> add_max_element v l
      | (Node(ll, lv, lr, lh), Node(rl, rv, rr, rh)) ->
          if lh > rh + 2 then bal ll lv (join lr v r) else
          if rh > lh + 2 then bal (join l v rl) rv rr else
          create l v r

    (* Smallest and greatest element of a set *)

    let rec min_elt = function
        Empty -> raise Not_found
      | Node(Empty, v, _r, _) -> v
      | Node(l, _v, _r, _) -> min_elt l

    let rec max_elt = function
        Empty -> raise Not_found
      | Node(_l, v, Empty, _) -> v
      | Node(_l, _v, r, _) -> max_elt r

    (* Remove the smallest element of the given set *)

    let rec remove_min_elt = function
        Empty -> invalid_arg "Set.remove_min_elt"
      | Node(Empty, _v, r, _) -> r
      | Node(l, v, r, _) -> bal (remove_min_elt l) v r

    (* Merge two trees l and r into one.
       All elements of l must precede the elements of r.
       Assume | height l - height r | <= 2. *)

    let merge t1 t2 =
      match (t1, t2) with
        (Empty, t) -> t
      | (t, Empty) -> t
      | (_, _) -> bal t1 (min_elt t2) (remove_min_elt t2)

    (* Merge two trees l and r into one.
       All elements of l must precede the elements of r.
       No assumption on the heights of l and r. *)

    let concat t1 t2 =
      match (t1, t2) with
        (Empty, t) -> t
      | (t, Empty) -> t
      | (_, _) -> join t1 (min_elt t2) (remove_min_elt t2)

    (* Splitting.  split x s returns a triple (l, present, r) where
        - l is the set of elements of s that are < x
        - r is the set of elements of s that are > x
        - present is false if s contains no element equal to x,
          or true if s contains an element equal to x. *)

    let rec split x = function
        Empty ->
          (Empty, false, Empty)
      | Node(l, v, r, _) ->
          let c = Ord.compare x v in
          if c = 0 then (l, true, r)
          else if c < 0 then
            let (ll, pres, rl) = split x l in (ll, pres, join rl v r)
          else
            let (lr, pres, rr) = split x r in (join l v lr, pres, rr)

    (* Implementation of the set operations *)

    let empty = Empty

    let is_empty = function Empty -> true | _ -> false

    let rec mem x = function
        Empty -> false
      | Node(l, v, r, _) ->
          let c = Ord.compare x v in
          c = 0 || mem x (if c < 0 then l else r)

    let rec remove x = function
        Empty -> Empty
      | Node(l, v, r, _) ->
          let c = Ord.compare x v in
          if c = 0 then merge l r else
          if c < 0 then bal (remove x l) v r else bal l v (remove x r)

    let rec union s1 s2 =
      match (s1, s2) with
        (Empty, t2) -> t2
      | (t1, Empty) -> t1
      | (Node(l1, v1, r1, h1), Node(l2, v2, r2, h2)) ->
          if h1 >= h2 then
            if h2 = 1 then add v2 s1 else begin
              let (l2, _, r2) = split v1 s2 in
              join (union l1 l2) v1 (union r1 r2)
            end
          else
            if h1 = 1 then add v1 s2 else begin
              let (l1, _, r1) = split v2 s1 in
              join (union l1 l2) v2 (union r1 r2)
            end

    let rec inter s1 s2 =
      match (s1, s2) with
        (Empty, _t2) -> Empty
      | (_t1, Empty) -> Empty
      | (Node(l1, v1, r1, _), t2) ->
          match split v1 t2 with
            (l2, false, r2) ->
              concat (inter l1 l2) (inter r1 r2)
          | (l2, true, r2) ->
              join (inter l1 l2) v1 (inter r1 r2)

    let rec diff s1 s2 =
      match (s1, s2) with
        (Empty, _t2) -> Empty
      | (t1, Empty) -> t1
      | (Node(l1, v1, r1, _), t2) ->
          match split v1 t2 with
            (l2, false, r2) ->
              join (diff l1 l2) v1 (diff r1 r2)
          | (l2, true, r2) ->
              concat (diff l1 l2) (diff r1 r2)

    type 'k enumeration = End | More of 'k elt * 'k t * 'k enumeration

    let rec cons_enum s e =
      match s with
        Empty -> e
      | Node(l, v, r, _) -> cons_enum l (More(v, r, e))

    let rec compare_aux e1 e2 =
        match (e1, e2) with
        (End, End) -> 0
      | (End, _)  -> -1
      | (_, End) -> 1
      | (More(v1, r1, e1), More(v2, r2, e2)) ->
          let c = Ord.compare v1 v2 in
          if c <> 0
          then c
          else compare_aux (cons_enum r1 e1) (cons_enum r2 e2)

    let compare s1 s2 =
      compare_aux (cons_enum s1 End) (cons_enum s2 End)

    let equal s1 s2 =
      compare s1 s2 = 0

    let rec subset s1 s2 =
      match (s1, s2) with
        Empty, _ ->
          true
      | _, Empty ->
          false
      | Node (l1, v1, r1, _), (Node (l2, v2, r2, _) as t2) ->
          let c = Ord.compare v1 v2 in
          if c = 0 then
            subset l1 l2 && subset r1 r2
          else if c < 0 then
            subset (Node (l1, v1, Empty, 0)) l2 && subset r1 t2
          else
            subset (Node (Empty, v1, r1, 0)) r2 && subset l1 t2

    let rec iter f = function
        Empty -> ()
      | Node(l, v, r, _) -> iter f l; f v; iter f r

    let rec fold f s accu =
      match s with
        Empty -> accu
      | Node(l, v, r, _) -> fold f r (f v (fold f l accu))

    let rec for_all p = function
        Empty -> true
      | Node(l, v, r, _) -> p v && for_all p l && for_all p r

    let rec exists p = function
        Empty -> false
      | Node(l, v, r, _) -> p v || exists p l || exists p r

    let rec filter p = function
        Empty -> Empty
      | Node(l, v, r, _) ->
          (* call [p] in the expected left-to-right order *)
          let l' = filter p l in
          let pv = p v in
          let r' = filter p r in
          if pv then join l' v r' else concat l' r'

    let rec partition p = function
        Empty -> (Empty, Empty)
      | Node(l, v, r, _) ->
          (* call [p] in the expected left-to-right order *)
          let (lt, lf) = partition p l in
          let pv = p v in
          let (rt, rf) = partition p r in
          if pv
          then (join lt v rt, concat lf rf)
          else (concat lt rt, join lf v rf)

    let rec cardinal = function
        Empty -> 0
      | Node(l, _v, r, _) -> cardinal l + 1 + cardinal r

    let rec elements_aux accu = function
        Empty -> accu
      | Node(l, v, r, _) -> elements_aux (v :: elements_aux accu r) l

    let elements s =
      elements_aux [] s

    let choose = min_elt

    let rec find x = function
        Empty -> raise Not_found
      | Node(l, v, r, _) ->
          let c = Ord.compare x v in
          if c = 0 then v
          else find x (if c < 0 then l else r)

    let of_sorted_list l =
      let rec sub n l =
        match n, l with
        | 0, l -> Empty, l
        | 1, x0 :: l -> Node (Empty, x0, Empty, 1), l
        | 2, x0 :: x1 :: l -> Node (Node(Empty, x0, Empty, 1), x1, Empty, 2), l
        | 3, x0 :: x1 :: x2 :: l ->
            Node (Node(Empty, x0, Empty, 1), x1, Node(Empty, x2, Empty, 1), 2),l
        | n, l ->
          let nl = n / 2 in
          let left, l = sub nl l in
          match l with
          | [] -> assert false
          | mid :: l ->
            let right, l = sub (n - nl - 1) l in
            create left mid right, l
      in
      fst (sub (List.length l) l)

    let of_list l =
      match l with
      | [] -> empty
      | [x0] -> singleton x0
      | [x0; x1] -> add x1 (singleton x0)
      | [x0; x1; x2] -> add x2 (add x1 (singleton x0))
      | [x0; x1; x2; x3] -> add x3 (add x2 (add x1 (singleton x0)))
      | [x0; x1; x2; x3; x4] -> add x4 (add x3 (add x2 (add x1 (singleton x0))))
      | _ -> of_sorted_list (List.sort_uniq Ord.compare l)

(* Pretty-print additions *)
    let pp chan delim pp_elt s =
      try
	let fst = min_elt s in
	pp_elt chan fst ;
	let s = remove fst s in
	iter
	  (fun elt ->
	    Printf.fprintf chan "%s%a" delim pp_elt elt)
	  s
      with Not_found -> ()

    let pp_str delim pp_elt s =
      try
	let fst = min_elt s in
	let fst_str = pp_elt fst in
	let s = remove fst s in
	fold
	  (fun elt k ->
	    k ^ (Printf.sprintf "%s%s" delim (pp_elt elt)))
	  s fst_str
      with Not_found -> ""

(* Unions *)
    let rec union2 k sets = match sets with
    | [] -> k
    | [s] -> s::k
    | s1::s2::sets -> union2 (union s1 s2::k) sets
          
    let rec unions sets = match sets with
    | [] -> empty
    | [s] -> s
    | _   -> unions (union2 [] sets)
  end
