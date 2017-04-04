(****************************************************************************)
(*                           the diy toolsuite                              *)
(*                                                                          *)
(* Jade Alglave, University College London, UK.                             *)
(* Luc Maranget, INRIA Paris-Rocquencourt, France.                          *)
(*                                                                          *)
(* Copyright 2017-present Institut National de Recherche en Informatique et *)
(* en Automatique and the authors. All rights reserved.                     *)
(*                                                                          *)
(* This software is governed by the CeCILL-B license under French law and   *)
(* abiding by the rules of distribution of free software. You can use,      *)
(* modify and/ or redistribute the software under the terms of the CeCILL-B *)
(* license as circulated by CEA, CNRS and INRIA at the following URL        *)
(* "http://www.cecill.info". We also give a copy in LICENSE.txt.            *)
(****************************************************************************)

(* a simple litmus for kernel *)

open Printf

let pgm = if Array.length Sys.argv > 0 then Sys.argv.(0) else "klitmus"

(* Local options are in Option module *)
let sources = ref []

module KOption : sig
(* Generic setings *)
  type arg_triple =  string * Arg.spec * string

  val argint :  string -> int ref -> string -> arg_triple
  val arginto : int option ref -> Arg.spec   
  val argkm : string -> int ref -> string -> arg_triple

(* Complex settings *)
  val set_tar : string -> unit
  val get_tar : unit -> string
  val is_out : unit -> bool

(* Direct options *)
  val verbose : int ref
  val hexa : bool ref
  val avail : int option ref
  val size : int ref
  val runs : int ref
  val stride : Stride.t ref
  val names : string list ref
  val excl : string list ref
  val rename : string list ref
  val rcu : Rcu.t ref
  val pad : int ref
  val barrier : KBarrier.t ref
  val affinity : KAffinity.t ref
end = struct
  include Option
  let rcu = ref Rcu.No
  let pad = ref 3
  let barrier = ref KBarrier.User
  let affinity = ref KAffinity.No
end

open KOption
  
module PStride = ParseTag.Make(Stride)

let opts =
  [
(* General behavior *)
   "-v", Arg.Unit (fun () -> incr verbose), " be verbose";
   "-version", Arg.Unit (fun () -> print_endline Version_litmus.version; exit 0),
   " show version number and exit";
   "-libdir", Arg.Unit (fun () -> print_endline Version_litmus.libdir; exit 0),
   " show installation directory and exit";
   "-o", Arg.String set_tar,
     "<name> cross compilation to directory or tar file <name>" ;
   "-mach", Arg.String MyName.read_cfg,
   "<name> read configuration file name.cfg";
   "-hexa", Arg.Set KOption.hexa,
   " output variables in hexadecimal";
   argint "-pad" KOption.pad "size of padding for C litmus source names";   
(* Test parameters *)
   "-a", arginto KOption.avail,
     "<n> Run maximal number of tests concurrently for n available cores (default, run one test)";
   "-avail", arginto KOption.avail, "<n> alias for -a <n>";
   argkm "-s" KOption.size "size of test" ;
   argkm "-size_of_test" KOption.size  "alias for -s";
   argkm "-r" KOption.runs "number of runs" ;
   argkm "-number_of_run" KOption.runs "alias for -r" ;
   PStride.parse "-st" KOption.stride "stride for scanning memory" ;
   PStride.parse "-stride" KOption.stride "stride for scanning memory" ;
   begin let module P = ParseTag.Make(KBarrier)  in
   P.parse "-barrier" KOption.barrier "synchronisation barrier style" end;
(* Affinity *)
   begin let module P = ParseTag.Make(KAffinity) in
   P.parse "-affinity" KOption.affinity
     "attach threads to logical processors" end ;
   "-i",
   Arg.Int
     (fun i ->
       let i = if i >=0 then i else 0 in
       KOption.affinity := KAffinity.Incr i),
   "<n> alias for -affinity incr<n>" ;
(********)
(* Misc *)
(********)
(* Change input *)
   CheckName.parse_names names ;
   CheckName.parse_excl excl ;
   CheckName.parse_rename rename ;
   begin let module P = ParseTag.Make(Rcu) in
   P.parse "-rcu" KOption.rcu "accept RCU tests or not" end ;
 ]


let usage = sprintf   "Usage: %s [opts]* filename" pgm

let () = Arg.parse opts (fun s -> sources := s :: !sources) usage

let sources = !sources
let rename = !rename
let names = !names
let excl = !excl
let verbose = !KOption.verbose
let () =
  try
(* Time to read kind files.. *)
    let module Check =
      CheckName.Make
        (struct
          let verbose = verbose
          let rename = rename
          let select = []
          let names = names
          let excl = excl
        end) in
    let outname =
      if KOption.is_out () then KOption.get_tar ()
      else MySys.mktmpdir () in
    let module Tar =
      Tar.Make
        (struct
          let verbose = verbose
          let outname = Some outname
        end) in
    let module Config = struct
(* Parser *)
      let check_name = Check.ok
      let check_rename = Check.rename_opt
      let check_kind _ = None
      let check_cond _ = None
(* Static options *)
      let verbose = verbose
      let hexa = !hexa
      let is_out = is_out ()
      let size = !size
      let runs = !runs
      let avail = !avail
      let stride =
        let open Stride in
        let st = !stride in
        match st with
        | No|Adapt -> st
        | St i ->  if i > 0 then st else No
      let barrier = !barrier
      let affinity = !affinity
      let rcu = !rcu
      let pad = !pad
(* tar stuff *)
      let tarname = KOption.get_tar ()
    end in
    let module T = Top_klitmus.Top(Config) (Tar) in
    T.from_files sources ;
    if not (KOption.is_out ()) then MySys.rmdir outname ;
    exit 0
  with
    | LexRename.Error|Misc.Exit -> exit 2
    | Misc.Fatal msg ->
        eprintf "Fatal error: %s\n%!" msg ;
        exit 2
