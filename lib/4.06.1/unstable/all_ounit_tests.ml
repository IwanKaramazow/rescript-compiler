module OUnitTypes
= struct
#1 "oUnitTypes.ml"

(**
  * Commont types for OUnit
  *
  * @author Sylvain Le Gall
  *
  *)

(** See OUnit.mli. *) 
type node = ListItem of int | Label of string

(** See OUnit.mli. *) 
type path = node list 

(** See OUnit.mli. *) 
type log_severity = 
  | LError
  | LWarning
  | LInfo

(** See OUnit.mli. *) 
type test_result =
  | RSuccess of path
  | RFailure of path * string
  | RError of path * string
  | RSkip of path * string
  | RTodo of path * string

(** See OUnit.mli. *) 
type test_event =
  | EStart of path
  | EEnd of path
  | EResult of test_result
  | ELog of log_severity * string
  | ELogRaw of string

(** Events which occur at the global level. *)
type global_event =
  | GStart  (** Start running the tests. *)
  | GEnd    (** Finish running the tests. *)
  | GResults of (float * test_result list * int)

(* The type of test function *)
type test_fun = unit -> unit 

(* The type of tests *)
type test = 
  | TestCase of test_fun
  | TestList of test list
  | TestLabel of string * test

type state = 
    {
      tests_planned : (path * (unit -> unit)) list;
      results : test_result list;
    }


end
module OUnitChooser
= struct
#1 "oUnitChooser.ml"


(**
    Heuristic to pick a test to run.
   
    @author Sylvain Le Gall
  *)

open OUnitTypes

(** Most simple heuristic, just pick the first test. *)
let simple state =
  List.hd state.tests_planned

end
module OUnitUtils
= struct
#1 "oUnitUtils.ml"

(**
  * Utilities for OUnit
  *
  * @author Sylvain Le Gall
  *)

open OUnitTypes

let is_success = 
  function
    | RSuccess _  -> true 
    | RFailure _ | RError _  | RSkip _ | RTodo _ -> false 

let is_failure = 
  function
    | RFailure _ -> true
    | RSuccess _ | RError _  | RSkip _ | RTodo _ -> false

let is_error = 
  function 
    | RError _ -> true
    | RSuccess _ | RFailure _ | RSkip _ | RTodo _ -> false

let is_skip = 
  function
    | RSkip _ -> true
    | RSuccess _ | RFailure _ | RError _  | RTodo _ -> false

let is_todo = 
  function
    | RTodo _ -> true
    | RSuccess _ | RFailure _ | RError _  | RSkip _ -> false

let result_flavour = 
  function
    | RError _ -> "Error"
    | RFailure _ -> "Failure"
    | RSuccess _ -> "Success"
    | RSkip _ -> "Skip"
    | RTodo _ -> "Todo"

let result_path = 
  function
    | RSuccess path 
    | RError (path, _)
    | RFailure (path, _)
    | RSkip (path, _)
    | RTodo (path, _) -> path

let result_msg = 
  function
    | RSuccess _ -> "Success"
    | RError (_, msg)
    | RFailure (_, msg)
    | RSkip (_, msg)
    | RTodo (_, msg) -> msg

(* Returns true if the result list contains successes only. *)
let rec was_successful = 
  function
    | [] -> true
    | RSuccess _::t 
    | RSkip _::t -> 
        was_successful t

    | RFailure _::_
    | RError _::_ 
    | RTodo _::_ -> 
        false

let string_of_node = 
  function
    | ListItem n -> 
        string_of_int n
    | Label s -> 
        s

(* Return the number of available tests *)
let rec test_case_count = 
  function
    | TestCase _ -> 1 
    | TestLabel (_, t) -> test_case_count t
    | TestList l -> 
        List.fold_left 
          (fun c t -> c + test_case_count t) 
          0 l

let string_of_path path =
  String.concat ":" (List.rev_map string_of_node path)

let buff_format_printf f = 
  let buff = Buffer.create 13 in
  let fmt = Format.formatter_of_buffer buff in
    f fmt;
    Format.pp_print_flush fmt ();
    Buffer.contents buff

(* Applies function f in turn to each element in list. Function f takes
   one element, and integer indicating its location in the list *)
let mapi f l = 
  let rec rmapi cnt l = 
    match l with 
      | [] -> 
          [] 

      | h :: t -> 
          (f h cnt) :: (rmapi (cnt + 1) t) 
  in
    rmapi 0 l

let fold_lefti f accu l =
  let rec rfold_lefti cnt accup l = 
    match l with
      | [] -> 
          accup

      | h::t -> 
          rfold_lefti (cnt + 1) (f accup h cnt) t
  in
    rfold_lefti 0 accu l

end
module OUnitLogger
= struct
#1 "oUnitLogger.ml"
(*
 * Logger for information and various OUnit events.
 *)

open OUnitTypes
open OUnitUtils

type event_type = GlobalEvent of global_event | TestEvent of test_event

let format_event verbose event_type =
  match event_type with
    | GlobalEvent e ->
        begin
          match e with 
            | GStart ->
                ""
            | GEnd ->
                ""
            | GResults (running_time, results, test_case_count) -> 
                let separator1 = String.make (Format.get_margin ()) '=' in
                let separator2 = String.make (Format.get_margin ()) '-' in
                let buf = Buffer.create 1024 in
                let bprintf fmt = Printf.bprintf buf fmt in
                let print_results = 
                  List.iter 
                    (fun result -> 
                       bprintf "%s\n%s: %s\n\n%s\n%s\n" 
                         separator1 
                         (result_flavour result) 
                         (string_of_path (result_path result)) 
                         (result_msg result) 
                         separator2)
                in
                let errors   = List.filter is_error results in
                let failures = List.filter is_failure results in
                let skips    = List.filter is_skip results in
                let todos    = List.filter is_todo results in

                  if not verbose then
                    bprintf "\n";

                  print_results errors;
                  print_results failures;
                  bprintf "Ran: %d tests in: %.2f seconds.\n" 
                    (List.length results) running_time;

                  (* Print final verdict *)
                  if was_successful results then 
                    begin
                      if skips = [] then
                        bprintf "OK"
                      else 
                        bprintf "OK: Cases: %d Skip: %d"
                          test_case_count (List.length skips)
                    end
                  else
                    begin
                      bprintf
                        "FAILED: Cases: %d Tried: %d Errors: %d \
                              Failures: %d Skip:%d Todo:%d" 
                        test_case_count (List.length results) 
                        (List.length errors) (List.length failures)
                        (List.length skips) (List.length todos);
                    end;
                  bprintf "\n";
                  Buffer.contents buf
        end

    | TestEvent e ->
        begin
          let string_of_result = 
            if verbose then
              function
                | RSuccess _      -> "ok\n"
                | RFailure (_, _) -> "FAIL\n"
                | RError (_, _)   -> "ERROR\n"
                | RSkip (_, _)    -> "SKIP\n"
                | RTodo (_, _)    -> "TODO\n"
            else
              function
                | RSuccess _      -> "."
                | RFailure (_, _) -> "F"
                | RError (_, _)   -> "E"
                | RSkip (_, _)    -> "S"
                | RTodo (_, _)    -> "T"
          in
            if verbose then
              match e with 
                | EStart p -> 
                    Printf.sprintf "%s start\n" (string_of_path p)
                | EEnd p -> 
                    Printf.sprintf "%s end\n" (string_of_path p)
                | EResult result -> 
                    string_of_result result
                | ELog (lvl, str) ->
                    let prefix = 
                      match lvl with 
                        | LError -> "E"
                        | LWarning -> "W"
                        | LInfo -> "I"
                    in
                      prefix^": "^str
                | ELogRaw str ->
                    str
            else 
              match e with 
                | EStart _ | EEnd _ | ELog _ | ELogRaw _ -> ""
                | EResult result -> string_of_result result
        end

let file_logger fn =
  let chn = open_out fn in
    (fun ev ->
       output_string chn (format_event true ev);
       flush chn),
    (fun () -> close_out chn)

let std_logger verbose =
  (fun ev -> 
     print_string (format_event verbose ev);
     flush stdout),
  (fun () -> ())

let null_logger =
  ignore, ignore

let create output_file_opt verbose (log,close) =
  let std_log, std_close = std_logger verbose in
  let file_log, file_close = 
    match output_file_opt with 
      | Some fn ->
          file_logger fn
      | None ->
          null_logger
  in
    (fun ev ->
       std_log ev; file_log ev; log ev),
    (fun () ->
       std_close (); file_close (); close ())

let printf log fmt =
  Printf.ksprintf
    (fun s ->
       log (TestEvent (ELogRaw s)))
    fmt

end
module OUnit : sig 
#1 "oUnit.mli"
(***********************************************************************)
(* The OUnit library                                                   *)
(*                                                                     *)
(* Copyright (C) 2002-2008 Maas-Maarten Zeeman.                        *)
(* Copyright (C) 2010 OCamlCore SARL                                   *)
(*                                                                     *)
(* See LICENSE for details.                                            *)
(***********************************************************************)

(** Unit test building blocks
 
    @author Maas-Maarten Zeeman
    @author Sylvain Le Gall
  *)

(** {2 Assertions} 

    Assertions are the basic building blocks of unittests. *)

(** Signals a failure. This will raise an exception with the specified
    string. 

    @raise Failure signal a failure *)
val assert_failure : string -> 'a

(** Signals a failure when bool is false. The string identifies the 
    failure.
    
    @raise Failure signal a failure *)
val assert_bool : string -> bool -> unit

(** Shorthand for assert_bool 

    @raise Failure to signal a failure *)
val ( @? ) : string -> bool -> unit

(** Signals a failure when the string is non-empty. The string identifies the
    failure. 
    
    @raise Failure signal a failure *) 
val assert_string : string -> unit

(** [assert_command prg args] Run the command provided.

    @param exit_code expected exit code
    @param sinput provide this [char Stream.t] as input of the process
    @param foutput run this function on output, it can contains an
                   [assert_equal] to check it
    @param use_stderr redirect [stderr] to [stdout]
    @param env Unix environment
    @param verbose if a failure arise, dump stdout/stderr of the process to stderr

    @since 1.1.0
  *)
val assert_command : 
    ?exit_code:Unix.process_status ->
    ?sinput:char Stream.t ->
    ?foutput:(char Stream.t -> unit) ->
    ?use_stderr:bool ->
    ?env:string array ->
    ?verbose:bool ->
    string -> string list -> unit

(** [assert_equal expected real] Compares two values, when they are not equal a
    failure is signaled.

    @param cmp customize function to compare, default is [=]
    @param printer value printer, don't print value otherwise
    @param pp_diff if not equal, ask a custom display of the difference
                using [diff fmt exp real] where [fmt] is the formatter to use
    @param msg custom message to identify the failure

    @raise Failure signal a failure 
    
    @version 1.1.0
  *)
val assert_equal : 
  ?cmp:('a -> 'a -> bool) ->
  ?printer:('a -> string) -> 
  ?pp_diff:(Format.formatter -> ('a * 'a) -> unit) ->
  ?msg:string -> 'a -> 'a -> unit

(** Asserts if the expected exception was raised. 
   
    @param msg identify the failure

    @raise Failure description *)
val assert_raises : ?msg:string -> exn -> (unit -> 'a) -> unit

val assert_raise_any : ?msg:string ->  (unit -> 'a) -> unit

(** {2 Skipping tests } 
  
   In certain condition test can be written but there is no point running it, because they
   are not significant (missing OS features for example). In this case this is not a failure
   nor a success. Following functions allow you to escape test, just as assertion but without
   the same error status.
  
   A test skipped is counted as success. A test todo is counted as failure.
  *)

(** [skip cond msg] If [cond] is true, skip the test for the reason explain in [msg].
    For example [skip_if (Sys.os_type = "Win32") "Test a doesn't run on windows"].
    
    @since 1.0.3
  *)
val skip_if : bool -> string -> unit

(** The associated test is still to be done, for the reason given.
    
    @since 1.0.3
  *)
val todo : string -> unit

(** {2 Compare Functions} *)

(** Compare floats up to a given relative error. 
    
    @param epsilon if the difference is smaller [epsilon] values are equal
  *)
val cmp_float : ?epsilon:float -> float -> float -> bool

(** {2 Bracket}

    A bracket is a functional implementation of the commonly used
    setUp and tearDown feature in unittests. It can be used like this:

    ["MyTestCase" >:: (bracket test_set_up test_fun test_tear_down)] 
    
  *)

(** [bracket set_up test tear_down] The [set_up] function runs first, then
    the [test] function runs and at the end [tear_down] runs. The 
    [tear_down] function runs even if the [test] failed and help to clean
    the environment.
  *)
val bracket: (unit -> 'a) -> ('a -> unit) -> ('a -> unit) -> unit -> unit

(** [bracket_tmpfile test] The [test] function takes a temporary filename
    and matching output channel as arguments. The temporary file is created
    before the test and removed after the test.

    @param prefix see [Filename.open_temp_file]
    @param suffix see [Filename.open_temp_file]
    @param mode see [Filename.open_temp_file]
    
    @since 1.1.0
  *)
val bracket_tmpfile: 
  ?prefix:string -> 
  ?suffix:string -> 
  ?mode:open_flag list ->
  ((string * out_channel) -> unit) -> unit -> unit 

(** {2 Constructing Tests} *)

(** The type of test function *)
type test_fun = unit -> unit

(** The type of tests *)
type test =
    TestCase of test_fun
  | TestList of test list
  | TestLabel of string * test

(** Create a TestLabel for a test *)
val (>:) : string -> test -> test

(** Create a TestLabel for a TestCase *)
val (>::) : string -> test_fun -> test

(** Create a TestLabel for a TestList *)
val (>:::) : string -> test list -> test

(** Some shorthands which allows easy test construction.

   Examples:

   - ["test1" >: TestCase((fun _ -> ()))] =>  
   [TestLabel("test2", TestCase((fun _ -> ())))]
   - ["test2" >:: (fun _ -> ())] => 
   [TestLabel("test2", TestCase((fun _ -> ())))]
   - ["test-suite" >::: ["test2" >:: (fun _ -> ());]] =>
   [TestLabel("test-suite", TestSuite([TestLabel("test2", TestCase((fun _ -> ())))]))]
*)

(** [test_decorate g tst] Apply [g] to test function contains in [tst] tree.
    
    @since 1.0.3
  *)
val test_decorate : (test_fun -> test_fun) -> test -> test

(** [test_filter paths tst] Filter test based on their path string representation. 
    
    @param skip] if set, just use [skip_if] for the matching tests.
    @since 1.0.3
  *)
val test_filter : ?skip:bool -> string list -> test -> test option

(** {2 Retrieve Information from Tests} *)

(** Returns the number of available test cases *)
val test_case_count : test -> int

(** Types which represent the path of a test *)
type node = ListItem of int | Label of string
type path = node list (** The path to the test (in reverse order). *)

(** Make a string from a node *)
val string_of_node : node -> string

(** Make a string from a path. The path will be reversed before it is 
    tranlated into a string *)
val string_of_path : path -> string

(** Returns a list with paths of the test *)
val test_case_paths : test -> path list

(** {2 Performing Tests} *)

(** Severity level for log. *) 
type log_severity = 
  | LError
  | LWarning
  | LInfo

(** The possible results of a test *)
type test_result =
    RSuccess of path
  | RFailure of path * string
  | RError of path * string
  | RSkip of path * string
  | RTodo of path * string

(** Events which occur during a test run. *)
type test_event =
    EStart of path                (** A test start. *)
  | EEnd of path                  (** A test end. *)
  | EResult of test_result        (** Result of a test. *)
  | ELog of log_severity * string (** An event is logged in a test. *)
  | ELogRaw of string             (** Print raw data in the log. *)

(** Perform the test, allows you to build your own test runner *)
val perform_test : (test_event -> 'a) -> test -> test_result list

(** A simple text based test runner. It prints out information
    during the test. 

    @param verbose print verbose message
  *)
val run_test_tt : ?verbose:bool -> test -> test_result list

(** Main version of the text based test runner. It reads the supplied command 
    line arguments to set the verbose level and limit the number of test to 
    run.
    
    @param arg_specs add extra command line arguments
    @param set_verbose call a function to set verbosity

    @version 1.1.0
  *)
val run_test_tt_main : 
    ?arg_specs:(Arg.key * Arg.spec * Arg.doc) list -> 
    ?set_verbose:(bool -> unit) -> 
    test -> test_result list

end = struct
#1 "oUnit.ml"
(***********************************************************************)
(* The OUnit library                                                   *)
(*                                                                     *)
(* Copyright (C) 2002-2008 Maas-Maarten Zeeman.                        *)
(* Copyright (C) 2010 OCamlCore SARL                                   *)
(*                                                                     *)
(* See LICENSE for details.                                            *)
(***********************************************************************)
[@@@warning "a"]
open OUnitUtils
include OUnitTypes

(*
 * Types and global states.
 *)

let global_verbose = ref false

let global_output_file = 
  let pwd = Sys.getcwd () in
  let ocamlbuild_dir = Filename.concat pwd "_build" in
  let dir = 
    if Sys.file_exists ocamlbuild_dir && Sys.is_directory ocamlbuild_dir then
      ocamlbuild_dir
    else 
      pwd
  in
    ref (Some (Filename.concat dir "oUnit.log"))

let global_logger = ref (fst OUnitLogger.null_logger)

let global_chooser = ref OUnitChooser.simple

let bracket set_up f tear_down () =
  let fixture = 
    set_up () 
  in
  let () = 
    try
      let () = f fixture in
        tear_down fixture
    with e -> 
      let () = 
        tear_down fixture
      in
        raise e
  in
    ()

let bracket_tmpfile ?(prefix="ounit-") ?(suffix=".txt") ?mode f =
  bracket
    (fun () ->
       Filename.open_temp_file ?mode prefix suffix)
    f 
    (fun (fn, chn) ->
       begin
         try 
           close_out chn
         with _ ->
           ()
       end;
       begin
         try
           Sys.remove fn
         with _ ->
           ()
       end)

exception Skip of string
let skip_if b msg =
  if b then
    raise (Skip msg)

exception Todo of string
let todo msg =
  raise (Todo msg)

let assert_failure msg = 
  failwith ("OUnit: " ^ msg)

let assert_bool msg b =
  if not b then assert_failure msg

let assert_string str =
  if not (str = "") then assert_failure str

let assert_equal ?(cmp = ( = )) ?printer ?pp_diff ?msg expected actual =
  let get_error_string () =
    let res =
      buff_format_printf
        (fun fmt ->
           Format.pp_open_vbox fmt 0;
           begin
             match msg with 
               | Some s ->
                   Format.pp_open_box fmt 0;
                   Format.pp_print_string fmt s;
                   Format.pp_close_box fmt ();
                   Format.pp_print_cut fmt ()
               | None -> 
                   ()
           end;

           begin
             match printer with
               | Some p ->
                   Format.fprintf fmt
                     "@[expected: @[%s@]@ but got: @[%s@]@]@,"
                     (p expected)
                     (p actual)

               | None ->
                   Format.fprintf fmt "@[not equal@]@,"
           end;

           begin
             match pp_diff with 
               | Some d ->
                   Format.fprintf fmt 
                     "@[differences: %a@]@,"
                      d (expected, actual)

               | None ->
                   ()
           end;
           Format.pp_close_box fmt ())
    in
    let len = 
      String.length res
    in
      if len > 0 && res.[len - 1] = '\n' then
        String.sub res 0 (len - 1)
      else
        res
  in
    if not (cmp expected actual) then 
      assert_failure (get_error_string ())

let assert_command 
    ?(exit_code=Unix.WEXITED 0)
    ?(sinput=Stream.of_list [])
    ?(foutput=ignore)
    ?(use_stderr=true)
    ?env
    ?verbose
    prg args =

    bracket_tmpfile 
      (fun (fn_out, chn_out) ->
         let cmd_print fmt =
           let () = 
             match env with
               | Some e ->
                   begin
                     Format.pp_print_string fmt "env";
                     Array.iter (Format.fprintf fmt "@ %s") e;
                     Format.pp_print_space fmt ()
                   end
               
               | None ->
                   ()
           in
             Format.pp_print_string fmt prg;
             List.iter (Format.fprintf fmt "@ %s") args
         in

         (* Start the process *)
         let in_write = 
           Unix.dup (Unix.descr_of_out_channel chn_out)
         in
         let (out_read, out_write) = 
           Unix.pipe () 
         in
         let err = 
           if use_stderr then
             in_write
           else
             Unix.stderr
         in
         let args = 
           Array.of_list (prg :: args)
         in
         let pid =
           OUnitLogger.printf !global_logger "%s"
             (buff_format_printf
                (fun fmt ->
                   Format.fprintf fmt "@[Starting command '%t'@]\n" cmd_print));
           Unix.set_close_on_exec out_write;
           match env with 
             | Some e -> 
                 Unix.create_process_env prg args e out_read in_write err
             | None -> 
                 Unix.create_process prg args out_read in_write err
         in
         let () =
           Unix.close out_read; 
           Unix.close in_write
         in
         let () =
           (* Dump sinput into the process stdin *)
           let buff = Bytes.of_string " " in
             Stream.iter 
               (fun c ->
                  let _i : int =
                    Bytes.set buff 0  c;
                    Unix.write out_write buff 0 1
                  in
                    ())
               sinput;
             Unix.close out_write
         in
         let _, real_exit_code =
           let rec wait_intr () = 
             try 
               Unix.waitpid [] pid
             with Unix.Unix_error (Unix.EINTR, _, _) ->
               wait_intr ()
           in
             wait_intr ()
         in
         let exit_code_printer =
           function
             | Unix.WEXITED n ->
                 Printf.sprintf "exit code %d" n
             | Unix.WSTOPPED n ->
                 Printf.sprintf "stopped by signal %d" n
             | Unix.WSIGNALED n ->
                 Printf.sprintf "killed by signal %d" n
         in

           (* Dump process output to stderr *)
           begin
             let chn = open_in fn_out in
             let buff = Bytes.make 4096 'X' in
             let len = ref (-1) in
               while !len <> 0 do 
                 len := input chn buff 0 (Bytes.length buff);
                 OUnitLogger.printf !global_logger "%s" (Bytes.to_string @@ Bytes.sub buff 0 !len);
               done;
               close_in chn
           end;

           (* Check process status *)
           assert_equal 
             ~msg:(buff_format_printf 
                     (fun fmt ->
                        Format.fprintf fmt 
                          "@[Exit status of command '%t'@]" cmd_print))
             ~printer:exit_code_printer
             exit_code
             real_exit_code;

           begin
             let chn = open_in fn_out in
               try 
                 foutput (Stream.of_channel chn)
               with e ->
                 close_in chn;
                 raise e
           end)
      ()

let raises f =
  try
    ignore (f ());
    None
  with e -> 
    Some e

let assert_raises ?msg exn (f: unit -> 'a) = 
  let pexn = 
    Printexc.to_string 
  in
  let get_error_string () =
    let str = 
      Format.sprintf 
        "expected exception %s, but no exception was raised." 
        (pexn exn)
    in
      match msg with
        | None -> 
            assert_failure str
              
        | Some s -> 
            assert_failure (s^"\n"^str)
  in    
    match raises f with
      | None -> 
          assert_failure (get_error_string ())

      | Some e -> 
          assert_equal ?msg ~printer:pexn exn e


let assert_raise_any ?msg (f: unit -> 'a) = 
  let pexn = 
    Printexc.to_string 
  in
  let get_error_string () =
    let str = 
      Format.sprintf 
        "expected exception , but no exception was raised." 
        
    in
      match msg with
        | None -> 
            assert_failure str
              
        | Some s -> 
            assert_failure (s^"\n"^str)
  in    
    match raises f with
      | None -> 
          assert_failure (get_error_string ())

      | Some exn -> 
          assert_bool (pexn exn) true
(* Compare floats up to a given relative error *)
let cmp_float ?(epsilon = 0.00001) a b =
  abs_float (a -. b) <= epsilon *. (abs_float a) ||
    abs_float (a -. b) <= epsilon *. (abs_float b) 
      
(* Now some handy shorthands *)
let (@?) = assert_bool

(* Some shorthands which allows easy test construction *)
let (>:) s t = TestLabel(s, t)             (* infix *)
let (>::) s f = TestLabel(s, TestCase(f))  (* infix *)
let (>:::) s l = TestLabel(s, TestList(l)) (* infix *)

(* Utility function to manipulate test *)
let rec test_decorate g =
  function
    | TestCase f -> 
        TestCase (g f)
    | TestList tst_lst ->
        TestList (List.map (test_decorate g) tst_lst)
    | TestLabel (str, tst) ->
        TestLabel (str, test_decorate g tst)

let test_case_count = OUnitUtils.test_case_count 
let string_of_node = OUnitUtils.string_of_node
let string_of_path = OUnitUtils.string_of_path
    
(* Returns all possible paths in the test. The order is from test case
   to root 
 *)
let test_case_paths test = 
  let rec tcps path test = 
    match test with 
      | TestCase _ -> 
          [path] 

      | TestList tests -> 
          List.concat 
            (mapi (fun t i -> tcps ((ListItem i)::path) t) tests)

      | TestLabel (l, t) -> 
          tcps ((Label l)::path) t
  in
    tcps [] test

(* Test filtering with their path *)
module SetTestPath = Set.Make(String)

let test_filter ?(skip=false) only test =
  let set_test =
    List.fold_left 
      (fun st str -> SetTestPath.add str st)
      SetTestPath.empty
      only
  in
  let rec filter_test path tst =
    if SetTestPath.mem (string_of_path path) set_test then
      begin
        Some tst
      end

    else
      begin
        match tst with
          | TestCase f ->
              begin
                if skip then
                  Some 
                    (TestCase 
                       (fun () ->
                          skip_if true "Test disabled";
                          f ()))
                else
                  None
              end

          | TestList tst_lst ->
              begin
                let ntst_lst =
                  fold_lefti 
                    (fun ntst_lst tst i ->
                       let nntst_lst =
                         match filter_test ((ListItem i) :: path) tst with
                           | Some tst ->
                               tst :: ntst_lst
                           | None ->
                               ntst_lst
                       in
                         nntst_lst)
                    []
                    tst_lst
                in
                  if not skip && ntst_lst = [] then
                    None
                  else
                    Some (TestList (List.rev ntst_lst))
              end

          | TestLabel (lbl, tst) ->
              begin
                let ntst_opt =
                  filter_test 
                    ((Label lbl) :: path)
                    tst
                in
                  match ntst_opt with 
                    | Some ntst ->
                        Some (TestLabel (lbl, ntst))
                    | None ->
                        if skip then
                          Some (TestLabel (lbl, tst))
                        else
                          None
              end
      end
  in
    filter_test [] test


(* The possible test results *)
let is_success = OUnitUtils.is_success
let is_failure = OUnitUtils.is_failure
let is_error   = OUnitUtils.is_error  
let is_skip    = OUnitUtils.is_skip   
let is_todo    = OUnitUtils.is_todo   

(* TODO: backtrace is not correct *)
let maybe_backtrace = ""
  (* Printexc.get_backtrace () *)
    (* (if Printexc.backtrace_status () then *)
    (*    "\n" ^ Printexc.get_backtrace () *)
    (*  else "") *)
(* Events which can happen during testing *)

(* DEFINE MAYBE_BACKTRACE = *)
(* IFDEF BACKTRACE THEN *)
(*     (if Printexc.backtrace_status () then *)
(*        "\n" ^ Printexc.get_backtrace () *)
(*      else "") *)
(* ELSE *)
(*     "" *)
(* ENDIF *)

(* Run all tests, report starts, errors, failures, and return the results *)
let perform_test report test =
  let run_test_case f path =
    try 
      ignore(f ());
      RSuccess path
    with
      | Failure s -> 
          RFailure (path, s ^ maybe_backtrace)

      | Skip s -> 
          RSkip (path, s)

      | Todo s -> 
          RTodo (path, s)

      | s -> 
          RError (path, (Printexc.to_string s) ^ maybe_backtrace)
  in
  let rec flatten_test path acc = 
    function
      | TestCase(f) -> 
          (path, f) :: acc

      | TestList (tests) ->
          fold_lefti 
            (fun acc t cnt -> 
               flatten_test 
                 ((ListItem cnt)::path) 
                 acc t)
            acc tests
      
      | TestLabel (label, t) -> 
          flatten_test ((Label label)::path) acc t
  in
  let test_cases = List.rev (flatten_test [] [] test) in
  let runner (path, f) = 
    let result = 
      ignore @@ report (EStart path);
      run_test_case f path 
    in
      ignore @@ report (EResult result);
      ignore @@ report (EEnd path);
      result
  in
  let rec iter state = 
    match state.tests_planned with 
      | [] ->
          state.results
      | _ ->
          let (path, f) = !global_chooser state in            
          let result = runner (path, f) in
            iter 
              {
                results = result :: state.results;
                tests_planned = 
                  List.filter 
                    (fun (path', _) -> path <> path') state.tests_planned
              }
  in
    iter {results = []; tests_planned = test_cases}

(* Function which runs the given function and returns the running time
   of the function, and the original result in a tuple *)
let time_fun f x y =
  let begin_time = Unix.gettimeofday () in
  let result = f x y in
  let end_time = Unix.gettimeofday () in
    (end_time -. begin_time, result)

(* A simple (currently too simple) text based test runner *)
let run_test_tt ?verbose test =
  let log, log_close = 
    OUnitLogger.create 
      !global_output_file 
      !global_verbose 
      OUnitLogger.null_logger
  in
  let () = 
    global_logger := log
  in

  (* Now start the test *)
  let running_time, results = 
    time_fun 
      perform_test 
      (fun ev ->
         log (OUnitLogger.TestEvent ev))
      test 
  in
    
    (* Print test report *)
    log (OUnitLogger.GlobalEvent (GResults (running_time, results, test_case_count test)));

    (* Reset logger. *)
    log_close ();
    global_logger := fst OUnitLogger.null_logger;

    (* Return the results possibly for further processing *)
    results
      
(* Call this one from you test suites *)
let run_test_tt_main ?(arg_specs=[]) ?(set_verbose=ignore) suite = 
  let only_test = ref [] in
  let () = 
    Arg.parse
      (Arg.align
         [
           "-verbose", 
           Arg.Set global_verbose, 
           " Run the test in verbose mode.";

           "-only-test", 
           Arg.String (fun str -> only_test := str :: !only_test),
           "path Run only the selected test";

           "-output-file",
           Arg.String (fun s -> global_output_file := Some s),
           "fn Output verbose log in this file.";

           "-no-output-file",
           Arg.Unit (fun () -> global_output_file := None),
           " Prevent to write log in a file.";

           "-list-test",
           Arg.Unit
             (fun () -> 
                List.iter
                  (fun pth ->
                     print_endline (string_of_path pth))
                  (test_case_paths suite);
                exit 0),
           " List tests";
         ] @ arg_specs
      )
      (fun x -> raise (Arg.Bad ("Bad argument : " ^ x)))
      ("usage: " ^ Sys.argv.(0) ^ " [-verbose] [-only-test path]*")
  in
  let nsuite = 
    if !only_test = [] then
      suite
    else
      begin
        match test_filter ~skip:true !only_test suite with 
          | Some test ->
              test
          | None ->
              failwith ("Filtering test "^
                        (String.concat ", " !only_test)^
                        " lead to no test")
      end
  in

  let result = 
    set_verbose !global_verbose;
    run_test_tt ~verbose:!global_verbose nsuite 
  in
    if not (was_successful result) then
      exit 1
    else
      result

end
module Ext_array : sig 
#1 "ext_array.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)






(** Some utilities for {!Array} operations *)
val reverse_range : 'a array -> int -> int -> unit
val reverse_in_place : 'a array -> unit
val reverse : 'a array -> 'a array 
val reverse_of_list : 'a list -> 'a array

val filter : 
  'a array -> 
  ('a -> bool) ->   
  'a array

val filter_map : 
  'a array -> 
  ('a -> 'b option) -> 
  'b array

val range : int -> int -> int array

val map2i : (int -> 'a -> 'b -> 'c ) -> 'a array -> 'b array -> 'c array

val to_list_f : 
  'a array -> 
  ('a -> 'b) -> 
  'b list 

val to_list_map : 
  'a array -> ('a -> 'b option) -> 'b list 

val to_list_map_acc : 
  'a array -> 
  'b list -> 
  ('a -> 'b option) -> 
  'b list 

val of_list_map : 
  'a list -> 
  ('a -> 'b) -> 
  'b array 

val rfind_with_index : 'a array -> ('a -> 'b -> bool) -> 'b -> int



type 'a split = No_split | Split of  'a array *  'a array 


val find_and_split : 
  'a array ->
  ('a -> 'b -> bool) ->
  'b -> 'a split

val exists : 
  'a array -> 
  ('a -> bool) ->  
  bool 

val is_empty : 'a array -> bool 

val for_all2_no_exn : 
  'a array ->
  'b array -> 
  ('a -> 'b -> bool) -> 
  bool

val for_alli : 
  'a array -> 
  (int -> 'a -> bool) -> 
  bool 

val map :   
  'a array -> 
  ('a -> 'b) -> 
  'b array

val iter :
  'a array -> 
  ('a -> unit) -> 
  unit

val fold_left :   
  'b array -> 
  'a -> 
  ('a -> 'b -> 'a) ->   
  'a

val get_or :   
  'a array -> 
  int -> 
  (unit -> 'a) -> 
  'a
end = struct
#1 "ext_array.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)





let reverse_range a i len =
  if len = 0 then ()
  else
    for k = 0 to (len-1)/2 do
      let t = Array.unsafe_get a (i+k) in
      Array.unsafe_set a (i+k) ( Array.unsafe_get a (i+len-1-k));
      Array.unsafe_set a (i+len-1-k) t;
    done


let reverse_in_place a =
  reverse_range a 0 (Array.length a)

let reverse a =
  let b_len = Array.length a in
  if b_len = 0 then [||] else  
    let b = Array.copy a in  
    for i = 0 to  b_len - 1 do
      Array.unsafe_set b i (Array.unsafe_get a (b_len - 1 -i )) 
    done;
    b  

let reverse_of_list =  function
  | [] -> [||]
  | hd::tl as l ->
    let len = List.length l in
    let a = Array.make len hd in
    let rec fill i = function
      | [] -> a
      | hd::tl -> Array.unsafe_set a (len - i - 2) hd; fill (i+1) tl in
    fill 0 tl

let filter a f =
  let arr_len = Array.length a in
  let rec aux acc i =
    if i = arr_len 
    then reverse_of_list acc 
    else
      let v = Array.unsafe_get a i in
      if f  v then 
        aux (v::acc) (i+1)
      else aux acc (i + 1) 
  in aux [] 0


let filter_map a (f : _ -> _ option)  =
  let arr_len = Array.length a in
  let rec aux acc i =
    if i = arr_len 
    then reverse_of_list acc 
    else
      let v = Array.unsafe_get a i in
      match f  v with 
      | Some v -> 
        aux (v::acc) (i+1)
      | None -> 
        aux acc (i + 1) 
  in aux [] 0

let range from to_ =
  if from > to_ then invalid_arg "Ext_array.range"  
  else Array.init (to_ - from + 1) (fun i -> i + from)

let map2i f a b = 
  let len = Array.length a in 
  if len <> Array.length b then 
    invalid_arg "Ext_array.map2i"  
  else
    Array.mapi (fun i a -> f i  a ( Array.unsafe_get b i )) a 

let rec tolist_f_aux a f  i res =
  if i < 0 then res else
    let v = Array.unsafe_get a i in
    tolist_f_aux a f  (i - 1)
      (f v :: res)

let to_list_f a f = tolist_f_aux a f (Array.length a  - 1) []

let rec tolist_aux a f  i res =
  if i < 0 then res else
    let v = Array.unsafe_get a i in
    tolist_aux a f  (i - 1)
      (match f v with
       | Some v -> v :: res
       | None -> res) 

let to_list_map a f  = 
  tolist_aux a f (Array.length a - 1) []

let to_list_map_acc a acc f = 
  tolist_aux a f (Array.length a - 1) acc


let of_list_map a f = 
  match a with 
  | [] -> [||]
  | [a0] -> 
    let b0 = f a0 in
    [|b0|]
  | [a0;a1] -> 
    let b0 = f a0 in  
    let b1 = f a1 in 
    [|b0;b1|]
  | [a0;a1;a2] -> 
    let b0 = f a0 in  
    let b1 = f a1 in 
    let b2 = f a2 in  
    [|b0;b1;b2|]
  | [a0;a1;a2;a3] -> 
    let b0 = f a0 in  
    let b1 = f a1 in 
    let b2 = f a2 in  
    let b3 = f a3 in 
    [|b0;b1;b2;b3|]
  | [a0;a1;a2;a3;a4] -> 
    let b0 = f a0 in  
    let b1 = f a1 in 
    let b2 = f a2 in  
    let b3 = f a3 in 
    let b4 = f a4 in 
    [|b0;b1;b2;b3;b4|]

  | a0::a1::a2::a3::a4::tl -> 
    let b0 = f a0 in  
    let b1 = f a1 in 
    let b2 = f a2 in  
    let b3 = f a3 in 
    let b4 = f a4 in 
    let len = List.length tl + 5 in 
    let arr = Array.make len b0  in
    Array.unsafe_set arr 1 b1 ;  
    Array.unsafe_set arr 2 b2 ;
    Array.unsafe_set arr 3 b3 ; 
    Array.unsafe_set arr 4 b4 ; 
    let rec fill i = function
      | [] -> arr 
      | hd :: tl -> 
        Array.unsafe_set arr i (f hd); 
        fill (i + 1) tl in 
    fill 5 tl

(**
   {[
     # rfind_with_index [|1;2;3|] (=) 2;;
     - : int = 1
               # rfind_with_index [|1;2;3|] (=) 1;;
     - : int = 0
               # rfind_with_index [|1;2;3|] (=) 3;;
     - : int = 2
               # rfind_with_index [|1;2;3|] (=) 4;;
     - : int = -1
   ]}
*)
let rfind_with_index arr cmp v = 
  let len = Array.length arr in 
  let rec aux i = 
    if i < 0 then i
    else if  cmp (Array.unsafe_get arr i) v then i
    else aux (i - 1) in 
  aux (len - 1)

type 'a split = No_split | Split of  'a array *  'a array 


let find_with_index arr cmp v = 
  let len  = Array.length arr in 
  let rec aux i len = 
    if i >= len then -1 
    else if cmp (Array.unsafe_get arr i ) v then i 
    else aux (i + 1) len in 
  aux 0 len

let find_and_split arr cmp v : _ split = 
  let i = find_with_index arr cmp v in 
  if i < 0 then 
    No_split
  else
    Split (Array.sub arr 0 i, Array.sub arr (i + 1 ) (Array.length arr - i - 1))

(** TODO: available since 4.03, use {!Array.exists} *)

let exists a p =
  let n = Array.length a in
  let rec loop i =
    if i = n then false
    else if p (Array.unsafe_get a i) then true
    else loop (succ i) in
  loop 0


let is_empty arr =
  Array.length arr = 0


let rec unsafe_loop index len p xs ys  = 
  if index >= len then true
  else 
    p 
      (Array.unsafe_get xs index)
      (Array.unsafe_get ys index) &&
    unsafe_loop (succ index) len p xs ys 

let for_alli a p =
  let n = Array.length a in
  let rec loop i =
    if i = n then true
    else if p i (Array.unsafe_get a i) then loop (succ i)
    else false in
  loop 0

let for_all2_no_exn xs ys p = 
  let len_xs = Array.length xs in 
  let len_ys = Array.length ys in 
  len_xs = len_ys &&    
  unsafe_loop 0 len_xs p xs ys


let map a f =
  let open Array in 
  let l = length a in
  if l = 0 then [||] else begin
    let r = make l (f(unsafe_get a 0)) in
    for i = 1 to l - 1 do
      unsafe_set r i (f(unsafe_get a i))
    done;
    r
  end

let iter a f =
  let open Array in 
  for i = 0 to length a - 1 do f(unsafe_get a i) done


let fold_left a x f =
  let open Array in 
  let r = ref x in    
  for i = 0 to length a - 1 do
    r := f !r (unsafe_get a i)
  done;
  !r

let get_or arr i cb =     
  if i >=0 && i < Array.length arr then 
    Array.unsafe_get arr i 
  else cb ()  
end
module Ext_bytes : sig 
#1 "ext_bytes.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)





external unsafe_blit_string : string -> int -> bytes -> int -> int -> unit
  = "caml_blit_string" 
[@@noalloc]




end = struct
#1 "ext_bytes.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)







external unsafe_blit_string : string -> int -> bytes -> int -> int -> unit
  = "caml_blit_string" 
[@@noalloc]                     


end
module Ext_string : sig 
#1 "ext_string.mli"
(* Copyright (C) 2015 - 2016 Bloomberg Finance L.P.
 * Copyright (C) 2017 - Hongbo Zhang, Authors of ReScript
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)








(** Extension to the standard library [String] module, fixed some bugs like
    avoiding locale sensitivity *) 

(** default is false *)    
val split_by : ?keep_empty:bool -> (char -> bool) -> string -> string list


(** remove whitespace letters ('\t', '\n', ' ') on both side*)
val trim : string -> string 


(** default is false *)
val split : ?keep_empty:bool -> string -> char -> string list

(** split by space chars for quick scripting *)
val quick_split_by_ws : string -> string list 



val starts_with : string -> string -> bool

(**
   return [-1] when not found, the returned index is useful 
   see [ends_with_then_chop]
*)
val ends_with_index : string -> string -> int

val ends_with : string -> string -> bool

(**
   [ends_with_then_chop name ext]
   @example:
   {[
     ends_with_then_chop "a.cmj" ".cmj"
       "a"
   ]}
   This is useful in controlled or file case sensitve system
*)
val ends_with_then_chop : string -> string -> string option




(**
   [for_all_from  s start p]
   if [start] is negative, it raises,
   if [start] is too large, it returns true
*)
val for_all_from:
  string -> 
  int -> 
  (char -> bool) -> 
  bool 

val for_all : 
  string -> 
  (char -> bool) -> 
  bool

val is_empty : string -> bool

val repeat : int -> string -> string 

val equal : string -> string -> bool

(**
   [extract_until s cursor sep]
   When [sep] not found, the cursor is updated to -1,
   otherwise cursor is increased to 1 + [sep_position]
   User can not determine whether it is found or not by
   telling the return string is empty since 
   "\n\n" would result in an empty string too.
*)
(* val extract_until:
   string -> 
   int ref -> (* cursor to be updated *)
   char -> 
   string *)

val index_count:  
  string -> 
  int ->
  char -> 
  int -> 
  int 

(* val index_next :
   string -> 
   int ->
   char -> 
   int  *)


(**
   [find ~start ~sub s]
   returns [-1] if not found
*)
val find : ?start:int -> sub:string -> string -> int

val contain_substring : string -> string -> bool 

val non_overlap_count : sub:string -> string -> int 

val rfind : sub:string -> string -> int

(** [tail_from s 1]
    return a substring from offset 1 (inclusive)
*)
val tail_from : string -> int -> string


(** returns negative number if not found *)
val rindex_neg : string -> char -> int 

val rindex_opt : string -> char -> int option


val no_char : string -> char -> int -> int -> bool 


val no_slash : string -> bool 

(** return negative means no slash, otherwise [i] means the place for first slash *)
val no_slash_idx : string -> int 

val no_slash_idx_from : string -> int -> int 

(** if no conversion happens, reference equality holds *)
val replace_slash_backward : string -> string 

(** if no conversion happens, reference equality holds *)
val replace_backward_slash : string -> string 

val empty : string 


external compare : string -> string -> int = "caml_string_length_based_compare" [@@noalloc];;  
  
val single_space : string

val concat3 : string -> string -> string -> string 
val concat4 : string -> string -> string -> string -> string 
val concat5 : string -> string -> string -> string -> string -> string  
val inter2 : string -> string -> string
val inter3 : string -> string -> string -> string 
val inter4 : string -> string -> string -> string -> string
val concat_array : string -> string array -> string 

val single_colon : string 

val parent_dir_lit : string
val current_dir_lit : string

val capitalize_ascii : string -> string

val capitalize_sub:
  string -> 
  int -> 
  string

val uncapitalize_ascii : string -> string

val lowercase_ascii : string -> string 

(** Play parity to {!Ext_buffer.add_int_1} *)
(* val get_int_1 : string -> int -> int 
   val get_int_2 : string -> int -> int 
   val get_int_3 : string -> int -> int 
   val get_int_4 : string -> int -> int  *)

val get_1_2_3_4 : 
  string -> 
  off:int ->  
  int -> 
  int 

val unsafe_sub :   
  string -> 
  int -> 
  int -> 
  string

val is_valid_hash_number:
  string -> 
  bool

val hash_number_as_i32_exn:
  string ->
  int32
end = struct
#1 "ext_string.ml"
(* Copyright (C) 2015 - 2016 Bloomberg Finance L.P.
 * Copyright (C) 2017 - Hongbo Zhang, Authors of ReScript
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)







(*
   {[ split " test_unsafe_obj_ffi_ppx.cmi" ~keep_empty:false ' ']}
*)
let split_by ?(keep_empty=false) is_delim str =
  let len = String.length str in
  let rec loop acc last_pos pos =
    if pos = -1 then
      if last_pos = 0 && not keep_empty then

        acc
      else 
        String.sub str 0 last_pos :: acc
    else
    if is_delim str.[pos] then
      let new_len = (last_pos - pos - 1) in
      if new_len <> 0 || keep_empty then 
        let v = String.sub str (pos + 1) new_len in
        loop ( v :: acc)
          pos (pos - 1)
      else loop acc pos (pos - 1)
    else loop acc last_pos (pos - 1)
  in
  loop [] len (len - 1)

let trim s = 
  let i = ref 0  in
  let j = String.length s in 
  while !i < j &&  
        let u = String.unsafe_get s !i in 
        u = '\t' || u = '\n' || u = ' ' 
  do 
    incr i;
  done;
  let k = ref (j - 1)  in 
  while !k >= !i && 
        let u = String.unsafe_get s !k in 
        u = '\t' || u = '\n' || u = ' ' do 
    decr k ;
  done;
  String.sub s !i (!k - !i + 1)

let split ?keep_empty  str on = 
  if str = "" then [] else 
    split_by ?keep_empty (fun x -> (x : char) = on) str  ;;

let quick_split_by_ws str : string list = 
  split_by ~keep_empty:false (fun x -> x = '\t' || x = '\n' || x = ' ') str

let starts_with s beg = 
  let beg_len = String.length beg in
  let s_len = String.length s in
  beg_len <=  s_len &&
  (let i = ref 0 in
   while !i <  beg_len 
         && String.unsafe_get s !i =
            String.unsafe_get beg !i do 
     incr i 
   done;
   !i = beg_len
  )

let rec ends_aux s end_ j k = 
  if k < 0 then (j + 1)
  else if String.unsafe_get s j = String.unsafe_get end_ k then 
    ends_aux s end_ (j - 1) (k - 1)
  else  -1   

(** return an index which is minus when [s] does not 
    end with [beg]
*)
let ends_with_index s end_ : int = 
  let s_finish = String.length s - 1 in
  let s_beg = String.length end_ - 1 in
  if s_beg > s_finish then -1
  else
    ends_aux s end_ s_finish s_beg

let ends_with s end_ = ends_with_index s end_ >= 0 

let ends_with_then_chop s beg = 
  let i =  ends_with_index s beg in 
  if i >= 0 then Some (String.sub s 0 i) 
  else None

(* let check_suffix_case = ends_with  *)
(* let check_suffix_case_then_chop = ends_with_then_chop *)

(* let check_any_suffix_case s suffixes = 
   Ext_list.exists suffixes (fun x -> check_suffix_case s x)  *)

(* let check_any_suffix_case_then_chop s suffixes = 
   let rec aux suffixes = 
    match suffixes with 
    | [] -> None 
    | x::xs -> 
      let id = ends_with_index s x in 
      if id >= 0 then Some (String.sub s 0 id)
      else aux xs in 
   aux suffixes     *)




(* it is unsafe to expose such API as unsafe since 
   user can provide bad input range 

*)
let rec unsafe_for_all_range s ~start ~finish p =     
  start > finish ||
  p (String.unsafe_get s start) && 
  unsafe_for_all_range s ~start:(start + 1) ~finish p

let for_all_from s start  p = 
  let len = String.length s in 
  if start < 0  then invalid_arg "Ext_string.for_all_from"
  else unsafe_for_all_range s ~start ~finish:(len - 1) p 


let for_all s (p : char -> bool)  =   
  unsafe_for_all_range s ~start:0  ~finish:(String.length s - 1) p 

let is_empty s = String.length s = 0


let repeat n s  =
  let len = String.length s in
  let res = Bytes.create(n * len) in
  for i = 0 to pred n do
    String.blit s 0 res (i * len) len
  done;
  Bytes.to_string res




let unsafe_is_sub ~sub i s j ~len =
  let rec check k =
    if k = len
    then true
    else 
      String.unsafe_get sub (i+k) = 
      String.unsafe_get s (j+k) && check (k+1)
  in
  j+len <= String.length s && check 0



let find ?(start=0) ~sub s =
  let exception Local_exit in
  let n = String.length sub in
  let s_len = String.length s in 
  let i = ref start in  
  try
    while !i + n <= s_len do
      if unsafe_is_sub ~sub 0 s !i ~len:n then
        raise_notrace Local_exit;
      incr i
    done;
    -1
  with Local_exit ->
    !i

let contain_substring s sub = 
  find s ~sub >= 0 

(** TODO: optimize 
    avoid nonterminating when string is empty 
*)
let non_overlap_count ~sub s = 
  let sub_len = String.length sub in 
  let rec aux  acc off = 
    let i = find ~start:off ~sub s  in 
    if i < 0 then acc 
    else aux (acc + 1) (i + sub_len) in
  if String.length sub = 0 then invalid_arg "Ext_string.non_overlap_count"
  else aux 0 0  


let rfind ~sub s =
  let exception Local_exit in   
  let n = String.length sub in
  let i = ref (String.length s - n) in
  try
    while !i >= 0 do
      if unsafe_is_sub ~sub 0 s !i ~len:n then 
        raise_notrace Local_exit;
      decr i
    done;
    -1
  with Local_exit ->
    !i

let tail_from s x = 
  let len = String.length s  in 
  if  x > len then invalid_arg ("Ext_string.tail_from " ^s ^ " : "^ string_of_int x )
  else String.sub s x (len - x)

let equal (x : string) y  = x = y

(* let rec index_rec s lim i c =
   if i >= lim then -1 else
   if String.unsafe_get s i = c then i 
   else index_rec s lim (i + 1) c *)



let rec index_rec_count s lim i c count =
  if i >= lim then -1 else
  if String.unsafe_get s i = c then 
    if count = 1 then i 
    else index_rec_count s lim (i + 1) c (count - 1)
  else index_rec_count s lim (i + 1) c count

let index_count s i c count =     
  let lim = String.length s in 
  if i < 0 || i >= lim || count < 1 then 
    invalid_arg ("index_count: ( " ^string_of_int i ^ "," ^string_of_int count ^ ")" );
  index_rec_count s lim i c count 

(* let index_next s i c =   
   index_count s i c 1  *)

(* let extract_until s cursor c =       
   let len = String.length s in   
   let start = !cursor in 
   if start < 0 || start >= len then (
    cursor := -1;
    ""
    )
   else 
    let i = index_rec s len start c in   
    let finish = 
      if i < 0 then (      
        cursor := -1 ;
        len 
      )
      else (
        cursor := i + 1;
        i 
      ) in 
    String.sub s start (finish - start) *)

let rec rindex_rec s i c =
  if i < 0 then i else
  if String.unsafe_get s i = c then i else rindex_rec s (i - 1) c;;

let rec rindex_rec_opt s i c =
  if i < 0 then None else
  if String.unsafe_get s i = c then Some i else rindex_rec_opt s (i - 1) c;;

let rindex_neg s c = 
  rindex_rec s (String.length s - 1) c;;

let rindex_opt s c = 
  rindex_rec_opt s (String.length s - 1) c;;


(** TODO: can be improved to return a positive integer instead *)
let rec unsafe_no_char x ch i  last_idx = 
  i > last_idx  || 
  (String.unsafe_get x i <> ch && unsafe_no_char x ch (i + 1)  last_idx)

let rec unsafe_no_char_idx x ch i last_idx = 
  if i > last_idx  then -1 
  else 
  if String.unsafe_get x i <> ch then 
    unsafe_no_char_idx x ch (i + 1)  last_idx
  else i

let no_char x ch i len  : bool =
  let str_len = String.length x in 
  if i < 0 || i >= str_len || len >= str_len then invalid_arg "Ext_string.no_char"   
  else unsafe_no_char x ch i len 


let no_slash x = 
  unsafe_no_char x '/' 0 (String.length x - 1)

let no_slash_idx x = 
  unsafe_no_char_idx x '/' 0 (String.length x - 1)

let no_slash_idx_from x from = 
  let last_idx = String.length x - 1  in 
  assert (from >= 0); 
  unsafe_no_char_idx x '/' from last_idx

let replace_slash_backward (x : string ) = 
  let len = String.length x in 
  if unsafe_no_char x '/' 0  (len - 1) then x 
  else 
    String.map (function 
        | '/' -> '\\'
        | x -> x ) x 

let replace_backward_slash (x : string)=
  let len = String.length x in
  if unsafe_no_char x '\\' 0  (len -1) then x 
  else  
    String.map (function 
        |'\\'-> '/'
        | x -> x) x

let empty = ""


external compare : string -> string -> int = "caml_string_length_based_compare" [@@noalloc];;    

let single_space = " "
let single_colon = ":"

let concat_array sep (s : string array) =   
  let s_len = Array.length s in 
  match s_len with 
  | 0 -> empty 
  | 1 -> Array.unsafe_get s 0
  | _ ->     
    let sep_len = String.length sep in 
    let len = ref 0 in 
    for i = 0 to  s_len - 1 do 
      len := !len + String.length (Array.unsafe_get s i)
    done;
    let target = 
      Bytes.create 
        (!len + (s_len - 1) * sep_len ) in    
    let hd = (Array.unsafe_get s 0) in     
    let hd_len = String.length hd in 
    String.unsafe_blit hd  0  target 0 hd_len;   
    let current_offset = ref hd_len in     
    for i = 1 to s_len - 1 do 
      String.unsafe_blit sep 0 target  !current_offset sep_len;
      let cur = Array.unsafe_get s i in 
      let cur_len = String.length cur in     
      let new_off_set = (!current_offset + sep_len ) in
      String.unsafe_blit cur 0 target new_off_set cur_len; 
      current_offset := 
        new_off_set + cur_len ; 
    done;
    Bytes.unsafe_to_string target   

let concat3 a b c = 
  let a_len = String.length a in 
  let b_len = String.length b in 
  let c_len = String.length c in 
  let len = a_len + b_len + c_len in 
  let target = Bytes.create len in 
  String.unsafe_blit a 0 target 0 a_len ; 
  String.unsafe_blit b 0 target a_len b_len;
  String.unsafe_blit c 0 target (a_len + b_len) c_len;
  Bytes.unsafe_to_string target

let concat4 a b c d =
  let a_len = String.length a in 
  let b_len = String.length b in 
  let c_len = String.length c in 
  let d_len = String.length d in 
  let len = a_len + b_len + c_len + d_len in 

  let target = Bytes.create len in 
  String.unsafe_blit a 0 target 0 a_len ; 
  String.unsafe_blit b 0 target a_len b_len;
  String.unsafe_blit c 0 target (a_len + b_len) c_len;
  String.unsafe_blit d 0 target (a_len + b_len + c_len) d_len;
  Bytes.unsafe_to_string target


let concat5 a b c d e =
  let a_len = String.length a in 
  let b_len = String.length b in 
  let c_len = String.length c in 
  let d_len = String.length d in 
  let e_len = String.length e in 
  let len = a_len + b_len + c_len + d_len + e_len in 

  let target = Bytes.create len in 
  String.unsafe_blit a 0 target 0 a_len ; 
  String.unsafe_blit b 0 target a_len b_len;
  String.unsafe_blit c 0 target (a_len + b_len) c_len;
  String.unsafe_blit d 0 target (a_len + b_len + c_len) d_len;
  String.unsafe_blit e 0 target (a_len + b_len + c_len + d_len) e_len;
  Bytes.unsafe_to_string target



let inter2 a b = 
  concat3 a single_space b 


let inter3 a b c = 
  concat5 a  single_space  b  single_space  c 





let inter4 a b c d =
  concat_array single_space [| a; b ; c; d|]


let parent_dir_lit = ".."    
let current_dir_lit = "."


(* reference {!Bytes.unppercase} *)
let capitalize_ascii (s : string) : string = 
  if String.length s = 0 then s 
  else 
    begin
      let c = String.unsafe_get s 0 in 
      if (c >= 'a' && c <= 'z')
      || (c >= '\224' && c <= '\246')
      || (c >= '\248' && c <= '\254') then 
        let uc = Char.unsafe_chr (Char.code c - 32) in 
        let bytes = Bytes.of_string s in
        Bytes.unsafe_set bytes 0 uc;
        Bytes.unsafe_to_string bytes 
      else s 
    end

let capitalize_sub (s : string) len : string = 
  let slen = String.length s in 
  if  len < 0 || len > slen then invalid_arg "Ext_string.capitalize_sub"
  else 
  if len = 0 then ""
  else 
    let bytes = Bytes.create len in 
    let uc = 
      let c = String.unsafe_get s 0 in 
      if (c >= 'a' && c <= 'z')
      || (c >= '\224' && c <= '\246')
      || (c >= '\248' && c <= '\254') then 
        Char.unsafe_chr (Char.code c - 32) else c in 
    Bytes.unsafe_set bytes 0 uc;
    for i = 1 to len - 1 do 
      Bytes.unsafe_set bytes i (String.unsafe_get s i)
    done ;
    Bytes.unsafe_to_string bytes 



let uncapitalize_ascii =
  String.uncapitalize_ascii

let lowercase_ascii = String.lowercase_ascii

external (.![]) : string -> int -> int = "%string_unsafe_get"

let get_int_1_unsafe (x : string) off : int = 
  x.![off]

let get_int_2_unsafe (x : string) off : int =   
  x.![off] lor   
  x.![off+1] lsl 8

let get_int_3_unsafe (x : string) off : int = 
  x.![off] lor   
  x.![off+1] lsl 8  lor 
  x.![off+2] lsl 16


let get_int_4_unsafe (x : string) off : int =     
  x.![off] lor   
  x.![off+1] lsl 8  lor 
  x.![off+2] lsl 16 lor
  x.![off+3] lsl 24 

let get_1_2_3_4 (x : string) ~off len : int =  
  if len = 1 then get_int_1_unsafe x off 
  else if len = 2 then get_int_2_unsafe x off 
  else if len = 3 then get_int_3_unsafe x off 
  else if len = 4 then get_int_4_unsafe x off 
  else assert false

let unsafe_sub  x offs len =
  let b = Bytes.create len in 
  Ext_bytes.unsafe_blit_string x offs b 0 len;
  (Bytes.unsafe_to_string b)

let is_valid_hash_number (x:string) = 
  let len = String.length x in 
  len > 0 && (
    let a = x.![0] in 
    a <= 57 &&
    (if len > 1 then 
       a > 48 && 
       for_all_from x 1 (function '0' .. '9' -> true | _ -> false)
     else
       a >= 48 )
  ) 


let hash_number_as_i32_exn 
    ( x : string) : int32 = 
  Int32.of_string x    
end
module Ounit_array_tests
= struct
#1 "ounit_array_tests.ml"
let ((>::),
    (>:::)) = OUnit.((>::),(>:::))

let (=~) = OUnit.assert_equal

let printer_int_array = fun xs -> 
    String.concat ","
    (List.map string_of_int @@ Array.to_list xs )

let suites = 
    __FILE__
    >:::
    [
     __LOC__ >:: begin fun _ ->
        Ext_array.find_and_split 
            [|"a"; "b";"c"|]
            Ext_string.equal "--" =~ No_split
     end;
    __LOC__ >:: begin fun _ ->
        Ext_array.find_and_split 
            [|"a"; "b";"c";"--"|]
            Ext_string.equal "--" =~ Split( [|"a";"b";"c"|], [||])
     end;
     __LOC__ >:: begin fun _ ->
        Ext_array.find_and_split 
            [|"--"; "a"; "b";"c";"--"|]
            Ext_string.equal "--" =~ Split ([||], [|"a";"b";"c";"--"|])
     end;
    __LOC__ >:: begin fun _ ->
        Ext_array.find_and_split 
            [| "u"; "g"; "--"; "a"; "b";"c";"--"|]
            Ext_string.equal "--" =~ Split ([|"u";"g"|], [|"a";"b";"c";"--"|])
     end;
    __LOC__ >:: begin fun _ ->
        Ext_array.reverse [|1;2|] =~ [|2;1|];
        Ext_array.reverse [||] =~ [||]  
    end     ;
    __LOC__ >:: begin fun _ -> 
        let (=~) = OUnit.assert_equal ~printer:printer_int_array in 
        let k x y = Ext_array.of_list_map y x in 
        k succ [] =~ [||];
        k succ [1]  =~ [|2|];
        k succ [1;2;3]  =~ [|2;3;4|];
        k succ [1;2;3;4]  =~ [|2;3;4;5|];
        k succ [1;2;3;4;5]  =~ [|2;3;4;5;6|];
        k succ [1;2;3;4;5;6]  =~ [|2;3;4;5;6;7|];
        k succ [1;2;3;4;5;6;7]  =~ [|2;3;4;5;6;7;8|];
    end; 
    __LOC__ >:: begin fun _ -> 
        Ext_array.to_list_map_acc
        [|1;2;3;4;5;6|] [1;2;3]
        (fun x -> if x mod 2 = 0 then Some x else None )
        =~ [2;4;6;1;2;3]
    end;
    __LOC__ >:: begin fun _ -> 
        Ext_array.to_list_map_acc
        [|1;2;3;4;5;6|] []
        (fun x -> if x mod 2 = 0 then Some x else None )
        =~ [2;4;6]
    end;

    __LOC__ >:: begin fun _ -> 
    OUnit.assert_bool __LOC__ 
        (Ext_array.for_all2_no_exn        
        [|1;2;3|]
        [|1;2;3|]
        (=)
        )
    end;
    __LOC__ >:: begin fun _ -> 
    OUnit.assert_bool __LOC__
    (Ext_array.for_all2_no_exn
    [||] [||] (=) 
    );
    OUnit.assert_bool __LOC__
    (not @@ Ext_array.for_all2_no_exn
    [||] [|1|] (=) 
    )
    end
    ;
    __LOC__ >:: begin fun _ -> 
    OUnit.assert_bool __LOC__
    (not (Ext_array.for_all2_no_exn        
        [|1;2;3|]
        [|1;2;33|]
        (=)
        ))
    end
    ]
end
module Ounit_tests_util
= struct
#1 "ounit_tests_util.ml"



let time ?nums description  f  =
  match nums with 
  | None -> 
    begin 
      let start = Unix.gettimeofday () in 
      ignore @@ f ();
      let finish = Unix.gettimeofday () in
      Printf.printf "\n%s elapsed %f\n" description (finish -. start) ;
      flush stdout; 
    end

  | Some nums -> 
    begin 
        let start = Unix.gettimeofday () in 
        for _i = 0 to nums - 1 do 
          ignore @@ f ();
        done  ;
      let finish = Unix.gettimeofday () in
      Printf.printf "\n%s elapsed %f\n" description (finish -. start)  ;
      flush stdout;
    end

end
module Set_gen : sig 
#1 "set_gen.mli"
type 'a t =private
    Empty
  | Leaf of 'a
  | Node of { l : 'a t; v : 'a; r : 'a t; h : int; }


val empty : 'a t
val [@inline] is_empty : 'a t-> bool
val unsafe_two_elements : 
  'a -> 'a -> 'a t

val cardinal : 'a t-> int

val elements : 'a t-> 'a list
val choose : 'a t-> 'a
val iter : 'a t-> ('a -> unit) -> unit
val fold : 'a t-> 'c -> ('a -> 'c -> 'c) -> 'c
val for_all : 'a t-> ('a -> bool) -> bool
val exists : 'a t-> ('a -> bool) -> bool
val check : 'a t-> unit
val bal : 'a t-> 'a -> 'a t-> 'a t
val remove_min_elt : 'a t-> 'a t
val singleton : 'a -> 'a t
val internal_merge : 'a t-> 'a t-> 'a t
val internal_join : 'a t-> 'a -> 'a t-> 'a t
val internal_concat : 'a t-> 'a t-> 'a t
val partition : 'a t-> ('a -> bool) -> 'a t * 'a t
val of_sorted_array : 'a array -> 'a t
val is_ordered : cmp:('a -> 'a -> int) -> 'a t-> bool
val invariant : cmp:('a -> 'a -> int) -> 'a t-> bool

module type S =
sig
  type elt
  type t
  val empty : t
  val is_empty : t -> bool
  val iter : t -> (elt -> unit) -> unit
  val fold : t -> 'a -> (elt -> 'a -> 'a) -> 'a
  val for_all : t -> (elt -> bool) -> bool
  val exists : t -> (elt -> bool) -> bool
  val singleton : elt -> t
  val cardinal : t -> int
  val elements : t -> elt list
  val choose : t -> elt
  val mem : t -> elt -> bool
  val add : t -> elt -> t
  val remove : t -> elt -> t
  val union : t -> t -> t
  val inter : t -> t -> t
  val diff : t -> t -> t    
  val of_list : elt list -> t
  val of_sorted_array : elt array -> t
  val invariant : t -> bool
  val print : Format.formatter -> t -> unit
end

end = struct
#1 "set_gen.ml"
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
[@@@warnerror "+55"]

(* balanced tree based on stdlib distribution *)

type 'a t0 = 
  | Empty 
  | Leaf of  'a 
  | Node of { l : 'a t0 ; v :  'a ; r : 'a t0 ; h :  int }

let empty = Empty
let  [@inline] height = function
  | Empty -> 0 
  | Leaf _ -> 1
  | Node {h} -> h   

let [@inline] calc_height a b =  
  (if a >= b then a else b) + 1 

(* 
    Invariants: 
    1. {[ l < v < r]}
    2. l and r balanced 
    3. [height l] - [height r] <= 2
*)
let [@inline] unsafe_node v l  r h = 
  Node{l;v;r; h }         

let [@inline] unsafe_node_maybe_leaf v l r h =   
  if h = 1 then Leaf v   
  else Node{l;v;r; h }         

let [@inline] singleton x = Leaf x

let [@inline] unsafe_two_elements x v = 
  unsafe_node v (singleton x) empty 2 

type 'a t = 'a t0 = private
  | Empty 
  | Leaf of 'a
  | Node of { l : 'a t0 ; v :  'a ; r : 'a t0 ; h :  int }


(* Smallest and greatest element of a set *)

let rec min_exn = function
  | Empty -> raise Not_found
  | Leaf v -> v 
  | Node{l; v} ->
    match l with 
    | Empty -> v 
    | Leaf _
    | Node _ ->  min_exn l


let [@inline] is_empty = function Empty -> true | _ -> false

let rec cardinal_aux acc  = function
  | Empty -> acc 
  | Leaf _ -> acc + 1
  | Node {l;r} -> 
    cardinal_aux  (cardinal_aux (acc + 1)  r ) l 

let cardinal s = cardinal_aux 0 s 

let rec elements_aux accu = function
  | Empty -> accu
  | Leaf v -> v :: accu
  | Node{l; v; r} -> elements_aux (v :: elements_aux accu r) l

let elements s =
  elements_aux [] s

let choose = min_exn

let rec iter  x f = match x with
  | Empty -> ()
  | Leaf v -> f v 
  | Node {l; v; r} -> iter l f ; f v; iter r f 

let rec fold s accu f =
  match s with
  | Empty -> accu
  | Leaf v -> f v accu
  | Node{l; v; r} -> fold r (f v (fold l accu f)) f 

let rec for_all x p = match x with
  | Empty -> true
  | Leaf v -> p v 
  | Node{l; v; r} -> p v && for_all l p && for_all r p 

let rec exists x p = match x with
  | Empty -> false
  | Leaf v -> p v 
  | Node {l; v; r} -> p v || exists l p  || exists r p





exception Height_invariant_broken
exception Height_diff_borken 

let rec check_height_and_diff = 
  function 
  | Empty -> 0
  | Leaf _ -> 1
  | Node{l;r;h} -> 
    let hl = check_height_and_diff l in
    let hr = check_height_and_diff r in
    if h <>  calc_height hl hr  then raise Height_invariant_broken
    else  
      let diff = (abs (hl - hr)) in  
      if  diff > 2 then raise Height_diff_borken 
      else h     

let check tree = 
  ignore (check_height_and_diff tree)

(* Same as create, but performs one step of rebalancing if necessary.
    Invariants:
    1. {[ l < v < r ]}
    2. l and r balanced 
    3. | height l - height r | <= 3.

    Proof by indunction

    Lemma: the height of  [bal l v r] will bounded by [max l r] + 1 
*)
let bal l v r : _ t =
  let hl = height l in
  let hr = height r in
  if hl > hr + 2 then 
    let [@warning "-8"] Node ({l=ll;r= lr} as l) = l in 
    let hll = height ll in 
    let hlr = height lr in 
    if hll >= hlr then
      let hnode = calc_height hlr hr in       
      unsafe_node l.v 
        ll  
        (unsafe_node_maybe_leaf v lr  r hnode ) 
        (calc_height hll hnode)
    else       
      let [@warning "-8"] Node ({l = lrl; r = lrr } as lr) = lr in 
      let hlrl = height lrl in 
      let hlrr = height lrr in 
      let hlnode = calc_height hll hlrl in 
      let hrnode = calc_height hlrr hr in 
      unsafe_node lr.v 
        (unsafe_node_maybe_leaf l.v ll  lrl hlnode)  
        (unsafe_node_maybe_leaf v lrr  r hrnode)
        (calc_height hlnode hrnode)
  else if hr > hl + 2 then begin    
    let [@warning "-8"] Node ({l=rl; r=rr} as r) = r in 
    let hrr = height rr in 
    let hrl = height rl in 
    if hrr >= hrl then
      let hnode = calc_height hl hrl in
      unsafe_node r.v 
        (unsafe_node_maybe_leaf v l  rl hnode) 
        rr 
        (calc_height hnode hrr )
    else begin
      let [@warning "-8"] Node ({l = rll ; r = rlr } as rl) = rl in 
      let hrll = height rll in 
      let hrlr = height rlr in 
      let hlnode = (calc_height hl hrll) in
      let hrnode = (calc_height hrlr hrr) in
      unsafe_node rl.v 
        (unsafe_node_maybe_leaf v l rll hlnode)  
        (unsafe_node_maybe_leaf r.v rlr rr hrnode)
        (calc_height hlnode hrnode)
    end
  end else
    unsafe_node_maybe_leaf v l  r (calc_height hl hr)


let rec remove_min_elt = function
    Empty -> invalid_arg "Set.remove_min_elt"
  | Leaf _ -> empty  
  | Node{l=Empty; r} -> r
  | Node{l; v; r} -> bal (remove_min_elt l) v r



(* 
   All elements of l must precede the elements of r.
       Assume | height l - height r | <= 2.
   weak form of [concat] 
*)

let internal_merge l r =
  match (l, r) with
  | (Empty, t) -> t
  | (t, Empty) -> t
  | (_, _) -> bal l (min_exn r) (remove_min_elt r)


(* Beware: those two functions assume that the added v is *strictly*
    smaller (or bigger) than all the present elements in the tree; it
    does not test for equality with the current min (or max) element.
    Indeed, they are only used during the "join" operation which
    respects this precondition.
*)

let rec add_min v = function
  | Empty -> singleton v
  | Leaf x -> unsafe_two_elements v x
  | Node n ->
    bal (add_min v n.l) n.v n.r

let rec add_max v = function
  | Empty -> singleton v
  | Leaf x -> unsafe_two_elements x v
  | Node n  ->
    bal n.l n.v (add_max v n.r)

(** 
    Invariants:
    1. l < v < r 
    2. l and r are balanced 

    Proof by induction
    The height of output will be ~~ (max (height l) (height r) + 2)
    Also use the lemma from [bal]
*)
let rec internal_join l v r =
  match (l, r) with
    (Empty, _) -> add_min v r
  | (_, Empty) -> add_max v l
  | Leaf lv, Node {h = rh} ->
    if rh > 3 then 
      add_min lv (add_min v r ) (* FIXME: could inlined *)
    else unsafe_node  v l r (rh + 1)
  | Leaf _, Leaf _ -> 
    unsafe_node  v l r 2
  | Node {h = lh}, Leaf rv ->
    if lh > 3 then       
      add_max rv (add_max v l)
    else unsafe_node  v l r (lh + 1)    
  | (Node{l=ll;v= lv;r= lr;h= lh}, Node {l=rl; v=rv; r=rr; h=rh}) ->
    if lh > rh + 2 then 
      (* proof by induction:
         now [height of ll] is [lh - 1] 
      *)
      bal ll lv (internal_join lr v r) 
    else
    if rh > lh + 2 then bal (internal_join l v rl) rv rr 
    else unsafe_node  v l r (calc_height lh rh)


(*
    Required Invariants: 
    [t1] < [t2]  
*)
let internal_concat t1 t2 =
  match (t1, t2) with
  | (Empty, t) -> t
  | (t, Empty) -> t
  | (_, _) -> internal_join t1 (min_exn t2) (remove_min_elt t2)


let rec partition x p = match x with 
  | Empty -> (empty, empty)
  | Leaf v -> let pv = p v in if pv then x, empty else empty, x
  | Node{l; v; r} ->
    (* call [p] in the expected left-to-right order *)
    let (lt, lf) = partition l p in
    let pv = p v in
    let (rt, rf) = partition r p in
    if pv
    then (internal_join lt v rt, internal_concat lf rf)
    else (internal_concat lt rt, internal_join lf v rf)


let of_sorted_array l =   
  let rec sub start n l  =
    if n = 0 then empty else 
    if n = 1 then 
      let x0 = Array.unsafe_get l start in
      singleton x0
    else if n = 2 then     
      let x0 = Array.unsafe_get l start in 
      let x1 = Array.unsafe_get l (start + 1) in 
      unsafe_node x1 (singleton x0)  empty 2 else
    if n = 3 then 
      let x0 = Array.unsafe_get l start in 
      let x1 = Array.unsafe_get l (start + 1) in
      let x2 = Array.unsafe_get l (start + 2) in
      unsafe_node x1 (singleton x0)  (singleton x2) 2
    else 
      let nl = n / 2 in
      let left = sub start nl l in
      let mid = start + nl in 
      let v = Array.unsafe_get l mid in 
      let right = sub (mid + 1) (n - nl - 1) l in        
      unsafe_node v left  right (calc_height (height left) (height right))
  in
  sub 0 (Array.length l) l 

let is_ordered ~cmp tree =
  let rec is_ordered_min_max tree =
    match tree with
    | Empty -> `Empty
    | Leaf v -> `V (v,v)
    | Node {l;v;r} -> 
      begin match is_ordered_min_max l with
        | `No -> `No 
        | `Empty ->
          begin match is_ordered_min_max r with
            | `No  -> `No
            | `Empty -> `V (v,v)
            | `V(l,r) ->
              if cmp v l < 0 then
                `V(v,r)
              else
                `No
          end
        | `V(min_v,max_v)->
          begin match is_ordered_min_max r with
            | `No -> `No
            | `Empty -> 
              if cmp max_v v < 0 then 
                `V(min_v,v)
              else
                `No 
            | `V(min_v_r, max_v_r) ->
              if cmp max_v min_v_r < 0 then
                `V(min_v,max_v_r)
              else `No
          end
      end  in 
  is_ordered_min_max tree <> `No 

let invariant ~cmp t = 
  check t ; 
  is_ordered ~cmp t 


module type S = sig
  type elt 
  type t
  val empty: t
  val is_empty: t -> bool
  val iter: t ->  (elt -> unit) -> unit
  val fold: t -> 'a -> (elt -> 'a -> 'a) -> 'a
  val for_all: t -> (elt -> bool) ->  bool
  val exists: t -> (elt -> bool) -> bool
  val singleton: elt -> t
  val cardinal: t -> int
  val elements: t -> elt list
  val choose: t -> elt
  val mem: t -> elt -> bool
  val add: t -> elt -> t
  val remove: t -> elt -> t
  val union: t -> t -> t
  val inter: t -> t -> t
  val diff: t -> t -> t
  val of_list: elt list -> t
  val of_sorted_array : elt array -> t 
  val invariant : t -> bool 
  val print : Format.formatter -> t -> unit 
end 

end
module Ext_int : sig 
#1 "ext_int.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


type t = int
val compare : t -> t -> int 
val equal : t -> t -> bool 

(** 
   works on 64 bit platform only
   given input as an uint32 and convert it io int64
*)
val int32_unsigned_to_int : int32 -> int 
end = struct
#1 "ext_int.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


type t = int

let compare (x : t) (y : t) = Pervasives.compare x y 

let equal (x : t) (y : t) = x = y

let move = 0x1_0000_0000
(* works only on 64 bit platform *)
let int32_unsigned_to_int (n : int32) : int =
  let i = Int32.to_int n in (if i < 0 then i + move else i)

end
module Set_int : sig 
#1 "set_int.mli"


include Set_gen.S with type elt = int 
end = struct
#1 "set_int.ml"
# 1 "ext/set.cppo.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


# 43 "ext/set.cppo.ml"
type elt = int 
let compare_elt = Ext_int.compare 
let print_elt = Format.pp_print_int
let [@inline] eq_elt (x : elt) y = x = y


# 52 "ext/set.cppo.ml"
(* let (=) (a:int) b = a = b *)

type ('a ) t0 = 'a Set_gen.t 

type  t = elt t0

let empty = Set_gen.empty 
let is_empty = Set_gen.is_empty
let iter = Set_gen.iter
let fold = Set_gen.fold
let for_all = Set_gen.for_all 
let exists = Set_gen.exists 
let singleton = Set_gen.singleton 
let cardinal = Set_gen.cardinal
let elements = Set_gen.elements
let choose = Set_gen.choose 

let of_sorted_array = Set_gen.of_sorted_array

let rec mem (tree : t) (x : elt) =  match tree with 
  | Empty -> false
  | Leaf v -> eq_elt x  v 
  | Node{l; v; r} ->
    let c = compare_elt x v in
    c = 0 || mem (if c < 0 then l else r) x

type split = 
  | Yes of  {l : t ;  r :  t }
  | No of { l : t; r : t}  

let [@inline] split_l (x : split) = 
  match x with 
  | Yes {l} | No {l} -> l 

let [@inline] split_r (x : split) = 
  match x with 
  | Yes {r} | No {r} -> r       

let [@inline] split_pres (x : split) = match x with | Yes _ -> true | No _ -> false   

let rec split (tree : t) x : split =  match tree with 
  | Empty ->
     No {l = empty;  r = empty}
  | Leaf v ->   
    let c = compare_elt x v in
    if c = 0 then Yes {l = empty; r = empty}
    else if c < 0 then
      No {l = empty;  r = tree}
    else
      No {l = tree;  r = empty}
  | Node {l; v; r} ->
    let c = compare_elt x v in
    if c = 0 then Yes {l; r}
    else if c < 0 then
      match split l x with 
      | Yes result -> 
        Yes { result with r = Set_gen.internal_join result.r v r }
      | No result ->
        No { result with r= Set_gen.internal_join result.r v r }
    else
      match split r x with
      | Yes result -> 
        Yes {result with l = Set_gen.internal_join l v result.l}
      | No result ->   
        No {result with l = Set_gen.internal_join l v result.l}

let rec add (tree : t) x : t =  match tree with 
  | Empty -> singleton x
  | Leaf v -> 
    let c = compare_elt x v in
    if c = 0 then tree else     
    if c < 0 then 
      Set_gen.unsafe_two_elements x v
    else 
      Set_gen.unsafe_two_elements v x 
  | Node {l; v; r} as t ->
    let c = compare_elt x v in
    if c = 0 then t else
    if c < 0 then Set_gen.bal (add l x ) v r else Set_gen.bal l v (add r x )

let rec union (s1 : t) (s2 : t) : t  =
  match (s1, s2) with
  | (Empty, t) 
  | (t, Empty) -> t
  | Node _, Leaf v2 ->
    add s1 v2 
  | Leaf v1, Node _ -> 
    add s2 v1 
  | Leaf x, Leaf v -> 
    let c = compare_elt x v in
    if c = 0 then s1 else     
    if c < 0 then 
      Set_gen.unsafe_two_elements x v
    else 
      Set_gen.unsafe_two_elements v x
  | Node{l=l1; v=v1; r=r1; h=h1}, Node{l=l2; v=v2; r=r2; h=h2} ->
    if h1 >= h2 then    
      let split_result =  split s2 v1 in
      Set_gen.internal_join 
        (union l1 (split_l split_result)) v1 
        (union r1 (split_r split_result))  
    else    
      let split_result =  split s1 v2 in
      Set_gen.internal_join 
        (union (split_l split_result) l2) v2 
        (union (split_r split_result) r2)


let rec inter (s1 : t)  (s2 : t) : t  =
  match (s1, s2) with
  | (Empty, _) 
  | (_, Empty) -> empty  
  | Leaf v, _ -> 
    if mem s2 v then s1 else empty
  | Node ({ v } as s1), _ ->
    let result = split s2 v in 
    if split_pres result then 
      Set_gen.internal_join 
        (inter s1.l (split_l result)) 
        v 
        (inter s1.r (split_r result))
    else
      Set_gen.internal_concat 
        (inter s1.l (split_l result)) 
        (inter s1.r (split_r result))


let rec diff (s1 : t) (s2 : t) : t  =
  match (s1, s2) with
  | (Empty, _) -> empty
  | (t1, Empty) -> t1
  | Leaf v, _-> 
    if mem s2 v then empty else s1 
  | (Node({ v} as s1), _) ->
    let result =  split s2 v in
    if split_pres result then 
      Set_gen.internal_concat 
        (diff s1.l (split_l result)) 
        (diff s1.r (split_r result))    
    else
      Set_gen.internal_join 
        (diff s1.l (split_l result))
        v 
        (diff s1.r (split_r result))







let rec remove (tree : t)  (x : elt) : t = match tree with 
  | Empty -> empty (* This case actually would be never reached *)
  | Leaf v ->     
    if eq_elt x  v then empty else tree    
  | Node{l; v; r} ->
    let c = compare_elt x v in
    if c = 0 then Set_gen.internal_merge l r else
    if c < 0 then Set_gen.bal (remove l x) v r else Set_gen.bal l v (remove r x )

(* let compare s1 s2 = Set_gen.compare ~cmp:compare_elt s1 s2  *)



let of_list l =
  match l with
  | [] -> empty
  | [x0] -> singleton x0
  | [x0; x1] -> add (singleton x0) x1 
  | [x0; x1; x2] -> add (add (singleton x0)  x1) x2 
  | [x0; x1; x2; x3] -> add (add (add (singleton x0) x1 ) x2 ) x3 
  | [x0; x1; x2; x3; x4] -> add (add (add (add (singleton x0) x1) x2 ) x3 ) x4 
  | _ -> 
    let arrs = Array.of_list l in 
    Array.sort compare_elt arrs ; 
    of_sorted_array arrs



(* also check order *)
let invariant t =
  Set_gen.check t ;
  Set_gen.is_ordered ~cmp:compare_elt t          

let print fmt s = 
  Format.fprintf 
   fmt   "@[<v>{%a}@]@."
    (fun fmt s   -> 
       iter s
         (fun e -> Format.fprintf fmt "@[<v>%a@],@ " 
         print_elt e) 
    )
    s     






end
module Ounit_bal_tree_tests
= struct
#1 "ounit_bal_tree_tests.ml"
let ((>::),
     (>:::)) = OUnit.((>::),(>:::))

let (=~) = OUnit.assert_equal

module Set_poly =  struct 
  include Set_int
let of_sorted_list xs = Array.of_list xs |> of_sorted_array 
let of_array l = 
  Ext_array.fold_left l empty add
end
let suites = 
  __FILE__ >:::
  [
    __LOC__ >:: begin fun _ ->
      OUnit.assert_bool __LOC__
        (Set_poly.invariant 
           (Set_poly.of_array (Array.init 1000 (fun n -> n))))
    end;
    __LOC__ >:: begin fun _ ->
      OUnit.assert_bool __LOC__
        (Set_poly.invariant 
           (Set_poly.of_array (Array.init 1000 (fun n -> 1000-n))))
    end;
    __LOC__ >:: begin fun _ ->
      OUnit.assert_bool __LOC__
        (Set_poly.invariant 
           (Set_poly.of_array (Array.init 1000 (fun _ -> Random.int 1000))))
    end;
    __LOC__ >:: begin fun _ ->
      OUnit.assert_bool __LOC__
        (Set_poly.invariant 
           (Set_poly.of_sorted_list (Array.to_list (Array.init 1000 (fun n -> n)))))
    end;
    __LOC__ >:: begin fun _ ->
      let arr = Array.init 1000 (fun n -> n) in
      let set = (Set_poly.of_sorted_array arr) in
      OUnit.assert_bool __LOC__
        (Set_poly.invariant set );
      OUnit.assert_equal 1000 (Set_poly.cardinal set)    
    end;
    __LOC__ >:: begin fun _ ->
      for i = 0 to 200 do 
        let arr = Array.init i (fun n -> n) in
        let set = (Set_poly.of_sorted_array arr) in
        OUnit.assert_bool __LOC__
          (Set_poly.invariant set );
        OUnit.assert_equal i (Set_poly.cardinal set)
      done    
    end;
    __LOC__ >:: begin fun _ ->
      let arr_size = 200 in
      let arr_sets = Array.make 200 Set_poly.empty in  
      for i = 0 to arr_size - 1 do
        let size = Random.int 1000 in  
        let arr = Array.init size (fun n -> n) in
        arr_sets.(i)<- (Set_poly.of_sorted_array arr)            
      done;
      let large = Array.fold_left Set_poly.union Set_poly.empty arr_sets in 
      OUnit.assert_bool __LOC__ (Set_poly.invariant large)
    end;

     __LOC__ >:: begin fun _ ->
      let arr_size = 1_00_000 in
      let v = ref Set_int.empty in 
      for _ = 0 to arr_size - 1 do
        let size = Random.int 0x3FFFFFFF in  
         v := Set_int.add !v size                       
      done;       
      OUnit.assert_bool __LOC__ (Set_int.invariant !v)
    end;

  ]


type ident = { stamp : int ; name : string ; mutable flags : int}

module Set_ident = Set.Make(struct type t = ident 
    let compare = Pervasives.compare end)

let compare_ident x y = 
  let a =  compare (x.stamp : int) y.stamp in 
  if a <> 0 then a 
  else 
    let b = compare (x.name : string) y.name in 
    if b <> 0 then b 
    else compare (x.flags : int) y.flags     


let rec add (tree : _ Set_gen.t) x  =  match tree with 
  | Empty -> Set_gen.singleton x
  | Leaf v -> 
    let c = compare_ident x v in
    if c = 0 then tree else     
    if c < 0 then 
      Set_gen.unsafe_two_elements x v
    else 
      Set_gen.unsafe_two_elements v x
  | Node {l; v; r} as t ->
    let c = compare_ident x v in
    if c = 0 then t else
    if c < 0 then Set_gen.bal (add l x ) v r else Set_gen.bal l v (add r x )

let rec mem (tree : _ Set_gen.t) x =  match tree with 
    | Empty -> false
    | Leaf v -> compare_ident x v = 0
    | Node{l; v; r} ->
      let c = compare_ident x v in
      c = 0 || mem (if c < 0 then l else r) x
  
module Ident_set2 = Set.Make(struct type t = ident 
    let compare  = compare_ident            
  end)

let bench () = 
  let times = 1_000_000 in
  Ounit_tests_util.time "functor set" begin fun _ -> 
    let v = ref Set_ident.empty in  
    for i = 0 to  times do
      v := Set_ident.add   {stamp = i ; name = "name"; flags = -1 } !v 
    done;
    for i = 0 to times do
      ignore @@ Set_ident.mem   {stamp = i; name = "name" ; flags = -1} !v 
    done 
  end ;
  Ounit_tests_util.time "functor set (specialized)" begin fun _ -> 
    let v = ref Ident_set2.empty in  
    for i = 0 to  times do
      v := Ident_set2.add   {stamp = i ; name = "name"; flags = -1 } !v 
    done;
    for i = 0 to times do
      ignore @@ Ident_set2.mem   {stamp = i; name = "name" ; flags = -1} !v 
    done 
  end ;

  Ounit_tests_util.time "poly set" begin fun _ -> 
    let module Set_poly = Set_ident in 
    let v = ref Set_poly.empty in  
    for i = 0 to  times do
      v := Set_poly.add   {stamp = i ; name = "name"; flags = -1 } !v 
    done;
    for i = 0 to times do
      ignore @@ Set_poly.mem   {stamp = i; name = "name" ; flags = -1} !v 
    done;
  end;
  Ounit_tests_util.time "poly set (specialized)" begin fun _ -> 
    let v = ref Set_gen.empty in  
    for i = 0 to  times do
      v := add  !v {stamp = i ; name = "name"; flags = -1 }  
    done;
    for i = 0 to times do
      ignore @@ mem  !v  {stamp = i; name = "name" ; flags = -1} 
    done 

  end ; 

end
module Ext_list : sig 
#1 "ext_list.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


val map : 
  'a list -> 
  ('a -> 'b) -> 
  'b list 

val map_combine :  
  'a list -> 
  'b list -> 
  ('a -> 'c) -> 
  ('c * 'b) list 

val combine_array:
  'a array ->
  'b list -> 
  ('a -> 'c) ->
  ('c * 'b) list   

val combine_array_append:
  'a array ->
  'b list ->
  ('c * 'b) list -> 
  ('a -> 'c) ->
  ('c * 'b) list   

val has_string :   
  string list ->
  string -> 
  bool


val map_split_opt :  
  'a list ->
  ('a -> 'b option * 'c option) ->
  'b list * 'c list 

val mapi :
  'a list -> 
  (int -> 'a -> 'b) -> 
  'b list 

val mapi_append :
  'a list -> 
  (int -> 'a -> 'b) -> 
  'b list -> 
  'b list 

val map_snd : ('a * 'b) list -> ('b -> 'c) -> ('a * 'c) list 

(** [map_last f xs ]
    will pass [true] to [f] for the last element, 
    [false] otherwise. 
    For empty list, it returns empty
*)
val map_last : 
  'a list -> 
  (bool -> 'a -> 'b) -> 'b list

(** [last l]
    return the last element
    raise if the list is empty
*)
val last : 'a list -> 'a

val append : 
  'a list -> 
  'a list -> 
  'a list 

val append_one :  
  'a list -> 
  'a -> 
  'a list

val map_append :  
  'b list -> 
  'a list -> 
  ('b -> 'a) -> 
  'a list

val fold_right : 
  'a list -> 
  'b -> 
  ('a -> 'b -> 'b) -> 
  'b

val fold_right2 : 
  'a list -> 
  'b list -> 
  'c -> 
  ('a -> 'b -> 'c -> 'c) ->  'c

val fold_right3 : 
  'a list -> 
  'b list -> 
  'c list -> 
  'd -> 
  ('a -> 'b -> 'c -> 'd -> 'd) -> 
  'd


val map2 : 
  'a list ->
  'b list ->
  ('a -> 'b -> 'c) ->
  'c list

val fold_left_with_offset : 
  'a list -> 
  'acc -> 
  int -> 
  ('a -> 'acc ->  int ->  'acc) ->   
  'acc 


(** @unused *)
val filter_map : 
  'a list -> 
  ('a -> 'b option) -> 
  'b list  

(** [exclude p l] is the opposite of [filter p l] *)
val exclude : 
  'a list -> 
  ('a -> bool) -> 
  'a list 

(** [excludes p l]
    return a tuple [excluded,newl]
    where [exluded] is true indicates that at least one  
    element is removed,[newl] is the new list where all [p x] for [x] is false

*)
val exclude_with_val : 
  'a list -> 
  ('a -> bool) -> 
  'a list option


val same_length : 'a list -> 'b list -> bool

val init : int -> (int -> 'a) -> 'a list

(** [split_at n l]
    will split [l] into two lists [a,b], [a] will be of length [n], 
    otherwise, it will raise
*)
val split_at : 
  'a list -> 
  int -> 
  'a list * 'a list


(** [split_at_last l]
    It is equivalent to [split_at (List.length l - 1) l ]
*)
val split_at_last : 'a list -> 'a list * 'a

val filter_mapi : 
  'a list -> 
  ('a -> int ->  'b option) -> 
  'b list

val filter_map2 : 
  'a list -> 
  'b list -> 
  ('a -> 'b -> 'c option) -> 
  'c list


val length_compare : 'a list -> int -> [`Gt | `Eq | `Lt ]

val length_ge : 'a list -> int -> bool

(**

   {[length xs = length ys + n ]}
   input n should be positive 
   TODO: input checking
*)

val length_larger_than_n : 
  'a list -> 
  'a list -> 
  int -> 
  bool


(**
   [rev_map_append f l1 l2]
   [map f l1] and reverse it to append [l2]
   This weird semantics is due to it is the most efficient operation
   we can do
*)
val rev_map_append : 
  'a list -> 
  'b list -> 
  ('a -> 'b) -> 
  'b list


val flat_map : 
  'a list -> 
  ('a -> 'b list) -> 
  'b list

val flat_map_append : 
  'a list -> 
  'b list  ->
  ('a -> 'b list) -> 
  'b list


(**
    [stable_group eq lst]
    Example:
    Input:
   {[
     stable_group (=) [1;2;3;4;3]
   ]}
    Output:
   {[
     [[1];[2];[4];[3;3]]
   ]}
    TODO: this is O(n^2) behavior 
    which could be improved later
*)
val stable_group : 
  'a list -> 
  ('a -> 'a -> bool) -> 
  'a list list 

(** [drop n list]
    raise when [n] is negative
    raise when list's length is less than [n]
*)
val drop : 
  'a list -> 
  int -> 
  'a list 

val find_first :   
  'a list ->
  ('a -> bool) ->
  'a option 

(** [find_first_not p lst ]
    if all elements in [lst] pass, return [None] 
    otherwise return the first element [e] as [Some e] which
    fails the predicate
*)
val find_first_not : 
  'a list -> 
  ('a -> bool) -> 
  'a option 

(** [find_opt f l] returns [None] if all return [None],  
    otherwise returns the first one. 
*)

val find_opt : 
  'a list -> 
  ('a -> 'b option) -> 
  'b option 

val find_def : 
  'a list -> 
  ('a -> 'b option) ->
  'b ->
  'b 


val rev_iter : 
  'a list -> 
  ('a -> unit) -> 
  unit 

val iter:   
  'a list ->  
  ('a -> unit) -> 
  unit

val for_all:  
  'a list -> 
  ('a -> bool) -> 
  bool
val for_all_snd:    
  ('a * 'b) list -> 
  ('b -> bool) -> 
  bool

(** [for_all2_no_exn p xs ys]
    return [true] if all satisfied,
    [false] otherwise or length not equal
*)
val for_all2_no_exn : 
  'a list -> 
  'b list -> 
  ('a -> 'b -> bool) -> 
  bool



(** [f] is applied follow the list order *)
val split_map : 
  'a list -> 
  ('a -> 'b * 'c) -> 
  'b list * 'c list       

(** [fn] is applied from left to right *)
val reduce_from_left : 
  'a list -> 
  ('a -> 'a -> 'a) ->
  'a

val sort_via_array :
  'a list -> 
  ('a -> 'a -> int) -> 
  'a list  

val sort_via_arrayf:
  'a list -> 
  ('a -> 'a -> int) ->
  ('a -> 'b ) -> 
  'b list  



(** [assoc_by_string default key lst]
    if  [key] is found in the list  return that val,
    other unbox the [default], 
    otherwise [assert false ]
*)
val assoc_by_string : 
  (string * 'a) list -> 
  string -> 
  'a  option ->   
  'a  

val assoc_by_int : 
  (int * 'a) list -> 
  int -> 
  'a  option ->   
  'a   


val nth_opt : 'a list -> int -> 'a option  

val iter_snd : ('a * 'b) list -> ('b -> unit) -> unit 

val iter_fst : ('a * 'b) list -> ('a -> unit) -> unit 

val exists : 'a list -> ('a -> bool) -> bool 

val exists_fst : 
  ('a * 'b) list ->
  ('a -> bool) ->
  bool

val exists_snd : 
  ('a * 'b) list -> 
  ('b -> bool) -> 
  bool

val concat_append:
  'a list list -> 
  'a list -> 
  'a list

val fold_left2:
  'a list -> 
  'b list -> 
  'c -> 
  ('a -> 'b -> 'c -> 'c)
  -> 'c 

val fold_left:    
  'a list -> 
  'b -> 
  ('b -> 'a -> 'b) -> 
  'b

val singleton_exn:     
  'a list -> 'a

val mem_string :     
  string list -> 
  string -> 
  bool
end = struct
#1 "ext_list.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)




let rec map l f =
  match l with
  | [] ->
    []
  | [x1] ->
    let y1 = f x1 in
    [y1]
  | [x1; x2] ->
    let y1 = f x1 in
    let y2 = f x2 in
    [y1; y2]
  | [x1; x2; x3] ->
    let y1 = f x1 in
    let y2 = f x2 in
    let y3 = f x3 in
    [y1; y2; y3]
  | [x1; x2; x3; x4] ->
    let y1 = f x1 in
    let y2 = f x2 in
    let y3 = f x3 in
    let y4 = f x4 in
    [y1; y2; y3; y4]
  | x1::x2::x3::x4::x5::tail ->
    let y1 = f x1 in
    let y2 = f x2 in
    let y3 = f x3 in
    let y4 = f x4 in
    let y5 = f x5 in
    y1::y2::y3::y4::y5::(map tail f)

let rec has_string l f =
  match l with
  | [] ->
    false
  | [x1] ->
    x1 = f
  | [x1; x2] ->
    x1 = f || x2 = f
  | [x1; x2; x3] ->
    x1 = f || x2 = f || x3 = f
  | x1 :: x2 :: x3 :: x4 ->
    x1 = f || x2 = f || x3 = f || has_string x4 f 

let rec map_combine l1 l2 f =
  match (l1, l2) with
    ([], []) -> []
  | (a1::l1, a2::l2) -> 
    (f a1, a2) :: map_combine l1 l2 f 
  | (_, _) -> 
    invalid_arg "Ext_list.map_combine"

let rec combine_array_unsafe arr l i j acc f =    
  if i = j then acc
  else 
    match l with
    | [] -> invalid_arg "Ext_list.combine"
    | h :: tl ->
      (f (Array.unsafe_get arr i) , h) ::
      combine_array_unsafe arr tl (i + 1) j acc f

let combine_array_append arr l acc f = 
  let len = Array.length arr in
  combine_array_unsafe arr l 0 len acc f

let combine_array arr l f = 
  let len = Array.length arr in
  combine_array_unsafe arr l 0 len [] f 

let rec map_split_opt 
    (xs : 'a list)  (f : 'a -> 'b option * 'c option) 
  : 'b list * 'c list = 
  match xs with 
  | [] -> [], []
  | x::xs ->
    let c,d = f x in 
    let cs,ds = map_split_opt xs f in 
    (match c with Some c -> c::cs | None -> cs),
    (match d with Some d -> d::ds | None -> ds)

let rec map_snd l f =
  match l with
  | [] ->
    []
  | [ v1,x1 ] ->
    let y1 = f x1 in
    [v1,y1]
  | [v1, x1; v2, x2] ->
    let y1 = f x1 in
    let y2 = f x2 in
    [v1, y1; v2, y2]
  | [ v1, x1; v2, x2; v3, x3] ->
    let y1 = f x1 in
    let y2 = f x2 in
    let y3 = f x3 in
    [v1, y1; v2, y2; v3, y3]
  | [ v1, x1; v2, x2; v3, x3; v4, x4] ->
    let y1 = f x1 in
    let y2 = f x2 in
    let y3 = f x3 in
    let y4 = f x4 in
    [v1, y1; v2, y2; v3, y3; v4, y4]
  | (v1, x1) ::(v2, x2) :: (v3, x3)::(v4, x4) :: (v5, x5) ::tail ->
    let y1 = f x1 in
    let y2 = f x2 in
    let y3 = f x3 in
    let y4 = f x4 in
    let y5 = f x5 in
    (v1, y1)::(v2, y2) :: (v3, y3) :: (v4, y4) :: (v5, y5) :: (map_snd tail f)


let rec map_last l f=
  match l with
  | [] ->
    []
  | [x1] ->
    let y1 = f true x1 in
    [y1]
  | [x1; x2] ->
    let y1 = f false x1 in
    let y2 = f true x2 in
    [y1; y2]
  | [x1; x2; x3] ->
    let y1 = f false x1 in
    let y2 = f false x2 in
    let y3 = f true x3 in
    [y1; y2; y3]
  | [x1; x2; x3; x4] ->
    let y1 = f false x1 in
    let y2 = f false x2 in
    let y3 = f false x3 in
    let y4 = f true x4 in
    [y1; y2; y3; y4]
  | x1::x2::x3::x4::tail ->
    (* make sure that tail is not empty *)    
    let y1 = f false x1 in
    let y2 = f false x2 in
    let y3 = f false x3 in
    let y4 = f false x4 in
    y1::y2::y3::y4::(map_last tail f)

let rec mapi_aux lst i f tail = 
  match lst with
    [] -> tail
  | a::l -> 
    let r = f i a in r :: mapi_aux l (i + 1) f tail

let mapi lst f = mapi_aux lst 0 f []
let mapi_append lst f tail = mapi_aux lst 0 f tail
let rec last xs =
  match xs with 
  | [x] -> x 
  | _ :: tl -> last tl 
  | [] -> invalid_arg "Ext_list.last"    



let rec append_aux l1 l2 = 
  match l1 with
  | [] -> l2
  | [a0] -> a0::l2
  | [a0;a1] -> a0::a1::l2
  | [a0;a1;a2] -> a0::a1::a2::l2
  | [a0;a1;a2;a3] -> a0::a1::a2::a3::l2
  | [a0;a1;a2;a3;a4] -> a0::a1::a2::a3::a4::l2
  | a0::a1::a2::a3::a4::rest -> a0::a1::a2::a3::a4::append_aux rest l2

let append l1 l2 =   
  match l2 with 
  | [] -> l1 
  | _ -> append_aux l1 l2  

let append_one l1 x = append_aux l1 [x]  

let rec map_append l1 l2 f =   
  match l1 with
  | [] -> l2
  | [a0] -> f a0::l2
  | [a0;a1] -> 
    let b0 = f a0 in 
    let b1 = f a1 in 
    b0::b1::l2
  | [a0;a1;a2] -> 
    let b0 = f a0 in 
    let b1 = f a1 in  
    let b2 = f a2 in 
    b0::b1::b2::l2
  | [a0;a1;a2;a3] -> 
    let b0 = f a0 in 
    let b1 = f a1 in 
    let b2 = f a2 in 
    let b3 = f a3 in 
    b0::b1::b2::b3::l2
  | [a0;a1;a2;a3;a4] -> 
    let b0 = f a0 in 
    let b1 = f a1 in 
    let b2 = f a2 in 
    let b3 = f a3 in 
    let b4 = f a4 in 
    b0::b1::b2::b3::b4::l2

  | a0::a1::a2::a3::a4::rest ->
    let b0 = f a0 in 
    let b1 = f a1 in 
    let b2 = f a2 in 
    let b3 = f a3 in 
    let b4 = f a4 in 
    b0::b1::b2::b3::b4::map_append rest l2 f



let rec fold_right l acc f  = 
  match l with  
  | [] -> acc 
  | [a0] -> f a0 acc 
  | [a0;a1] -> f a0 (f a1 acc)
  | [a0;a1;a2] -> f a0 (f a1 (f a2 acc))
  | [a0;a1;a2;a3] -> f a0 (f a1 (f a2 (f a3 acc))) 
  | [a0;a1;a2;a3;a4] -> 
    f a0 (f a1 (f a2 (f a3 (f a4 acc))))
  | a0::a1::a2::a3::a4::rest -> 
    f a0 (f a1 (f a2 (f a3 (f a4 (fold_right rest acc f )))))  

let rec fold_right2 l r acc f = 
  match l,r  with  
  | [],[] -> acc 
  | [a0],[b0] -> f a0 b0 acc 
  | [a0;a1],[b0;b1] -> f a0 b0 (f a1 b1 acc)
  | [a0;a1;a2],[b0;b1;b2] -> f a0 b0 (f a1 b1 (f a2 b2 acc))
  | [a0;a1;a2;a3],[b0;b1;b2;b3] ->
    f a0 b0 (f a1 b1 (f a2 b2 (f a3 b3 acc))) 
  | [a0;a1;a2;a3;a4], [b0;b1;b2;b3;b4] -> 
    f a0 b0 (f a1 b1 (f a2 b2 (f a3 b3 (f a4 b4 acc))))
  | a0::a1::a2::a3::a4::arest, b0::b1::b2::b3::b4::brest -> 
    f a0 b0 (f a1 b1 (f a2 b2 (f a3 b3 (f a4 b4 (fold_right2 arest brest acc f )))))  
  | _, _ -> invalid_arg "Ext_list.fold_right2"

let rec fold_right3 l r last acc f = 
  match l,r,last  with  
  | [],[],[] -> acc 
  | [a0],[b0],[c0] -> f a0 b0 c0 acc 
  | [a0;a1],[b0;b1],[c0; c1] -> f a0 b0 c0 (f a1 b1 c1 acc)
  | [a0;a1;a2],[b0;b1;b2],[c0;c1;c2] -> f a0 b0 c0 (f a1 b1 c1 (f a2 b2 c2 acc))
  | [a0;a1;a2;a3],[b0;b1;b2;b3],[c0;c1;c2;c3] ->
    f a0 b0 c0 (f a1 b1 c1 (f a2 b2 c2 (f a3 b3 c3 acc))) 
  | [a0;a1;a2;a3;a4], [b0;b1;b2;b3;b4], [c0;c1;c2;c3;c4] -> 
    f a0 b0 c0 (f a1 b1 c1 (f a2 b2 c2 (f a3 b3 c3 (f a4 b4 c4 acc))))
  | a0::a1::a2::a3::a4::arest, b0::b1::b2::b3::b4::brest, c0::c1::c2::c3::c4::crest -> 
    f a0 b0 c0 (f a1 b1 c1 (f a2 b2 c2 (f a3 b3 c3 (f a4 b4 c4 (fold_right3 arest brest crest acc f )))))  
  | _, _, _ -> invalid_arg "Ext_list.fold_right2"

let rec map2  l r f = 
  match l,r  with  
  | [],[] -> []
  | [a0],[b0] -> [f a0 b0]
  | [a0;a1],[b0;b1] -> 
    let c0 = f a0 b0 in 
    let c1 = f a1 b1 in 
    [c0; c1]
  | [a0;a1;a2],[b0;b1;b2] -> 
    let c0 = f a0 b0 in 
    let c1 = f a1 b1 in 
    let c2 = f a2 b2 in 
    [c0;c1;c2]
  | [a0;a1;a2;a3],[b0;b1;b2;b3] ->
    let c0 = f a0 b0 in 
    let c1 = f a1 b1 in 
    let c2 = f a2 b2 in 
    let c3 = f a3 b3 in 
    [c0;c1;c2;c3]
  | [a0;a1;a2;a3;a4], [b0;b1;b2;b3;b4] -> 
    let c0 = f a0 b0 in 
    let c1 = f a1 b1 in 
    let c2 = f a2 b2 in 
    let c3 = f a3 b3 in 
    let c4 = f a4 b4 in 
    [c0;c1;c2;c3;c4]
  | a0::a1::a2::a3::a4::arest, b0::b1::b2::b3::b4::brest -> 
    let c0 = f a0 b0 in 
    let c1 = f a1 b1 in 
    let c2 = f a2 b2 in 
    let c3 = f a3 b3 in 
    let c4 = f a4 b4 in 
    c0::c1::c2::c3::c4::map2 arest brest f
  | _, _ -> invalid_arg "Ext_list.map2"

let rec fold_left_with_offset l accu i f =
  match l with
  | [] -> accu
  | a::l -> 
    fold_left_with_offset 
      l     
      (f  a accu  i)  
      (i + 1)
      f  


let rec filter_map xs (f: 'a -> 'b option)= 
  match xs with 
  | [] -> []
  | y :: ys -> 
    begin match f y with 
      | None -> filter_map ys f 
      | Some z -> z :: filter_map ys f 
    end

let rec exclude (xs : 'a list) (p : 'a -> bool) : 'a list =   
  match xs with 
  | [] ->  []
  | x::xs -> 
    if p x then exclude xs p
    else x:: exclude xs p

let rec exclude_with_val l p =
  match l with 
  | [] ->  None
  | a0::xs -> 
    if p a0 then Some (exclude xs p)
    else 
      match xs with 
      | [] -> None
      | a1::rest -> 
        if p a1 then 
          Some (a0:: exclude rest p)
        else 
          match exclude_with_val rest p with 
          | None -> None 
          | Some  rest -> Some (a0::a1::rest)



let rec same_length xs ys = 
  match xs, ys with 
  | [], [] -> true
  | _::xs, _::ys -> same_length xs ys 
  | _, _ -> false 


let init n f = 
  match n with 
  | 0 -> []
  | 1 -> 
    let a0 = f 0 in  
    [a0]
  | 2 -> 
    let a0 = f 0 in 
    let a1 = f 1 in 
    [a0; a1]
  | 3 -> 
    let a0 = f 0 in 
    let a1 = f 1 in 
    let a2 = f 2 in 
    [a0; a1; a2]
  | 4 -> 
    let a0 = f 0 in 
    let a1 = f 1 in 
    let a2 = f 2 in 
    let a3 = f 3 in 
    [a0; a1; a2; a3]
  | 5 -> 
    let a0 = f 0 in 
    let a1 = f 1 in 
    let a2 = f 2 in 
    let a3 = f 3 in 
    let a4 = f 4 in  
    [a0; a1; a2; a3; a4]
  | _ ->
    Array.to_list (Array.init n f)

let rec rev_append l1 l2 =
  match l1 with
  | [] -> l2
  | [a0] -> a0::l2 (* single element is common *)
  | [a0 ; a1] -> a1 :: a0 :: l2 
  |  a0::a1::a2::rest -> rev_append rest (a2::a1::a0::l2) 

let rev l = rev_append l []      

let rec small_split_at n acc l = 
  if n <= 0 then rev acc , l 
  else 
    match l with 
    | x::xs -> small_split_at (n - 1) (x ::acc) xs 
    | _ -> invalid_arg "Ext_list.split_at"

let split_at l n = 
  small_split_at n [] l 

let rec split_at_last_aux acc x = 
  match x with 
  | [] -> invalid_arg "Ext_list.split_at_last"
  | [ x] -> rev acc, x
  | y0::ys -> split_at_last_aux (y0::acc) ys   

let split_at_last (x : 'a list) = 
  match x with 
  | [] -> invalid_arg "Ext_list.split_at_last"
  | [a0] -> 
    [], a0
  | [a0;a1] -> 
    [a0], a1  
  | [a0;a1;a2] -> 
    [a0;a1], a2 
  | [a0;a1;a2;a3] -> 
    [a0;a1;a2], a3 
  | [a0;a1;a2;a3;a4] ->
    [a0;a1;a2;a3], a4 
  | a0::a1::a2::a3::a4::rest  ->  
    let rev, last = split_at_last_aux [] rest
    in 
    a0::a1::a2::a3::a4::  rev , last

(**
   can not do loop unroll due to state combination
*)  
let  filter_mapi xs f  = 
  let rec aux i xs = 
    match xs with 
    | [] -> []
    | y :: ys -> 
      begin match f y i with 
        | None -> aux (i + 1) ys
        | Some z -> z :: aux (i + 1) ys
      end in
  aux 0 xs 

let rec filter_map2  xs ys (f: 'a -> 'b -> 'c option) = 
  match xs,ys with 
  | [],[] -> []
  | u::us, v :: vs -> 
    begin match f u v with 
      | None -> filter_map2 us vs f (* idea: rec f us vs instead? *)
      | Some z -> z :: filter_map2  us vs f
    end
  | _ -> invalid_arg "Ext_list.filter_map2"


let rec rev_map_append l1 l2 f =
  match l1 with
  | [] -> l2
  | a :: l -> rev_map_append l (f a :: l2) f



(** It is not worth loop unrolling, 
    it is already tail-call, and we need to be careful 
    about evaluation order when unroll
*)
let rec flat_map_aux f acc append lx =
  match lx with
  | [] -> rev_append acc  append
  | a0::rest -> 
    let new_acc = 
      match f a0 with 
      | [] -> acc 
      | [a0] -> a0::acc
      | [a0;a1] -> a1::a0::acc
      | a0::a1::a2::rest -> 
        rev_append rest (a2::a1::a0::acc)  
    in 
    flat_map_aux f  new_acc append rest 

let flat_map lx f  =
  flat_map_aux f [] [] lx

let flat_map_append lx append f =
  flat_map_aux f [] append lx  


let rec length_compare l n = 
  if n < 0 then `Gt 
  else 
    begin match l with 
      | _ ::xs -> length_compare xs (n - 1)
      | [] ->  
        if n = 0 then `Eq 
        else `Lt 
    end

let rec length_ge l n =   
  if n > 0 then
    match l with 
    | _ :: tl -> length_ge tl (n - 1)
    | [] -> false
  else true

(**
   {[length xs = length ys + n ]}
*)
let rec length_larger_than_n xs ys n =
  match xs, ys with 
  | _, [] -> length_compare xs n = `Eq   
  | _::xs, _::ys -> 
    length_larger_than_n xs ys n
  | [], _ -> false 




let rec group (eq : 'a -> 'a -> bool) lst =
  match lst with 
  | [] -> []
  | x::xs -> 
    aux eq x (group eq xs )

and aux eq (x : 'a)  (xss : 'a list list) : 'a list list = 
  match xss with 
  | [] -> [[x]]
  | (y0::_ as y)::ys -> (* cannot be empty *) 
    if eq x y0 then
      (x::y) :: ys 
    else
      y :: aux eq x ys                                 
  | _ :: _ -> assert false    

let stable_group lst eq =  group eq lst |> rev  

let rec drop h n = 
  if n < 0 then invalid_arg "Ext_list.drop"
  else
  if n = 0 then h 
  else 
    match h with 
    | [] ->
      invalid_arg "Ext_list.drop"
    | _ :: tl ->   
      drop tl (n - 1)

let rec find_first x p = 
  match x with 
  | [] -> None
  | x :: l -> 
    if p x then Some x 
    else find_first l p

let rec find_first_not  xs p = 
  match xs with 
  | [] -> None
  | a::l -> 
    if p a 
    then find_first_not l p 
    else Some a 


let rec rev_iter l f = 
  match l with
  | [] -> ()    
  | [x1] ->
    f x1 
  | [x1; x2] ->
    f x2 ; f x1 
  | [x1; x2; x3] ->
    f x3 ; f x2 ; f x1 
  | [x1; x2; x3; x4] ->
    f x4; f x3; f x2; f x1 
  | x1::x2::x3::x4::x5::tail ->
    rev_iter tail f;
    f x5; f x4 ; f x3; f x2 ; f x1

let rec iter l f = 
  match l with
  | [] -> ()    
  | [x1] ->
    f x1 
  | [x1; x2] ->
    f x1 ; f x2
  | [x1; x2; x3] ->
    f x1 ; f x2 ; f x3
  | [x1; x2; x3; x4] ->
    f x1; f x2; f x3; f x4
  | x1::x2::x3::x4::x5::tail ->
    f x1; f x2 ; f x3; f x4 ; f x5;
    iter tail f 


let rec for_all lst p = 
  match lst with 
    [] -> true
  | a::l -> p a && for_all l p

let rec for_all_snd lst p = 
  match lst with 
    [] -> true
  | (_,a)::l -> p a && for_all_snd l p


let rec for_all2_no_exn  l1 l2 p = 
  match (l1, l2) with
  | ([], []) -> true
  | (a1::l1, a2::l2) -> p a1 a2 && for_all2_no_exn l1 l2 p
  | (_, _) -> false


let rec find_opt xs p = 
  match xs with 
  | [] -> None
  | x :: l -> 
    match  p x with 
    | Some _ as v  ->  v
    | None -> find_opt l p

let rec find_def xs p def =
  match xs with 
  | [] -> def
  | x::l -> 
    match p x with 
    | Some v -> v 
    | None -> find_def l p def   

let rec split_map l f = 
  match l with
  | [] ->
    [],[]
  | [x1] ->
    let a0,b0 = f x1 in
    [a0],[b0]
  | [x1; x2] ->
    let a1,b1 = f x1 in
    let a2,b2 = f x2 in
    [a1;a2],[b1;b2]
  | [x1; x2; x3] ->
    let a1,b1 = f x1 in
    let a2,b2 = f x2 in
    let a3,b3 = f x3 in
    [a1;a2;a3], [b1;b2;b3]
  | [x1; x2; x3; x4] ->
    let a1,b1 = f x1 in
    let a2,b2 = f x2 in
    let a3,b3 = f x3 in
    let a4,b4 = f x4 in
    [a1;a2;a3;a4], [b1;b2;b3;b4] 
  | x1::x2::x3::x4::x5::tail ->
    let a1,b1 = f x1 in
    let a2,b2 = f x2 in
    let a3,b3 = f x3 in
    let a4,b4 = f x4 in
    let a5,b5 = f x5 in
    let ass,bss = split_map tail f in 
    a1::a2::a3::a4::a5::ass,
    b1::b2::b3::b4::b5::bss




let sort_via_array lst cmp =
  let arr = Array.of_list lst  in
  Array.sort cmp arr;
  Array.to_list arr

let sort_via_arrayf lst cmp f  = 
  let arr = Array.of_list lst  in
  Array.sort cmp arr;
  Ext_array.to_list_f arr f 


let rec assoc_by_string lst (k : string) def  = 
  match lst with 
  | [] -> 
    begin match def with 
      | None -> assert false 
      | Some x -> x end
  | (k1,v1)::rest -> 
    if  k1 = k then v1 else 
      assoc_by_string  rest k def 

let rec assoc_by_int lst (k : int) def = 
  match lst with 
  | [] -> 
    begin match def with
      | None -> assert false 
      | Some x -> x end
  | (k1,v1)::rest -> 
    if k1 = k then v1 else 
      assoc_by_int rest k def 


let rec nth_aux l n =
  match l with
  | [] -> None
  | a::l -> if n = 0 then Some a else nth_aux l (n-1)

let nth_opt l n =
  if n < 0 then None 
  else
    nth_aux l n

let rec iter_snd lst f =     
  match lst with
  | [] -> ()
  | (_,x)::xs -> 
    f x ; 
    iter_snd xs f 

let rec iter_fst lst f =     
  match lst with
  | [] -> ()
  | (x,_)::xs -> 
    f x ; 
    iter_fst xs f 

let rec exists l p =     
  match l with 
    [] -> false  
  | x :: xs -> p x || exists xs p

let rec exists_fst l p = 
  match l with 
    [] -> false
  | (a,_)::l -> p a || exists_fst l p 

let rec exists_snd l p = 
  match l with 
    [] -> false
  | (_, a)::l -> p a || exists_snd l p 

let rec concat_append 
    (xss : 'a list list)  
    (xs : 'a list) : 'a list = 
  match xss with 
  | [] -> xs 
  | l::r -> append l (concat_append r xs)

let rec fold_left l accu f =
  match l with
    [] -> accu
  | a::l -> fold_left l (f accu a) f 

let reduce_from_left lst fn = 
  match lst with 
  | first :: rest ->  fold_left rest first fn 
  | _ -> invalid_arg "Ext_list.reduce_from_left"

let rec fold_left2 l1 l2 accu f =
  match (l1, l2) with
    ([], []) -> accu
  | (a1::l1, a2::l2) -> fold_left2  l1 l2 (f a1 a2 accu) f 
  | (_, _) -> invalid_arg "Ext_list.fold_left2"

let singleton_exn xs = match xs with [x] -> x | _ -> assert false

let rec mem_string (xs : string list) (x : string) = 
  match xs with 
    [] -> false
  | a::l ->  a = x  || mem_string l x

end
module Map_gen : sig 
#1 "map_gen.mli"
type ('key, + 'a) t = private
  | Empty
  | Leaf of {
      k : 'key ;
      v : 'a
    }
  | Node of {
      l : ('key,'a) t ;
      k : 'key ;
      v : 'a ;
      r : ('key,'a) t ;
      h : int
    }


val cardinal : ('a, 'b) t -> int

val bindings : ('a, 'b) t -> ('a * 'b) list
val fill_array_with_f :
  ('a, 'b) t -> int -> 'c array -> ('a -> 'b -> 'c) -> int
val fill_array_aux : ('a, 'b) t -> int -> ('a * 'b) array -> int
val to_sorted_array : ('key, 'a) t -> ('key * 'a) array
val to_sorted_array_with_f : ('a, 'b) t -> ('a -> 'b -> 'c) -> 'c array

val keys : ('a, 'b) t -> 'a list

val height : ('a, 'b) t -> int


val singleton : 'a -> 'b -> ('a, 'b) t

val [@inline] unsafe_node : 
  'a -> 
  'b -> 
  ('a, 'b ) t ->
  ('a, 'b ) t ->
  int -> 
  ('a, 'b ) t

(** smaller comes first *)
val [@inline] unsafe_two_elements :
  'a -> 
  'b -> 
  'a -> 
  'b -> 
  ('a, 'b) t

val bal : ('a, 'b) t -> 'a -> 'b -> ('a, 'b) t -> ('a, 'b) t
val empty : ('a, 'b) t
val is_empty : ('a, 'b) t -> bool




val merge : ('a, 'b) t -> ('a, 'b) t -> ('a, 'b) t
val iter : ('a, 'b) t -> ('a -> 'b -> unit) -> unit
val map : ('a, 'b) t -> ('b -> 'c) -> ('a, 'c) t
val mapi : ('a, 'b) t -> ('a -> 'b -> 'c) -> ('a, 'c) t
val fold : ('a, 'b) t -> 'c -> ('a -> 'b -> 'c -> 'c) -> 'c
val for_all : ('a, 'b) t -> ('a -> 'b -> bool) -> bool
val exists : ('a, 'b) t -> ('a -> 'b -> bool) -> bool


val join : ('a, 'b) t -> 'a -> 'b -> ('a, 'b) t -> ('a, 'b) t
val concat : ('a, 'b) t -> ('a, 'b) t -> ('a, 'b) t
val concat_or_join :
  ('a, 'b) t -> 'a -> 'b option -> ('a, 'b) t -> ('a, 'b) t

module type S =
sig
  type key
  type +'a t
  val empty : 'a t
  val compare_key : key -> key -> int
  val is_empty : 'a t -> bool
  val mem : 'a t -> key -> bool
  val to_sorted_array : 'a t -> (key * 'a) array
  val to_sorted_array_with_f : 'a t -> (key -> 'a -> 'b) -> 'b array
  val add : 'a t -> key -> 'a -> 'a t
  val adjust : 'a t -> key -> ('a option -> 'a) -> 'a t
  val singleton : key -> 'a -> 'a t
  val remove : 'a t -> key -> 'a t
  (* val merge :
     'a t -> 'b t -> (key -> 'a option -> 'b option -> 'c option) -> 'c t *)
  val disjoint_merge_exn : 
    'a t -> 
    'a t -> 
    (key -> 'a -> 'a -> exn) -> 
    'a t

  val iter : 'a t -> (key -> 'a -> unit) -> unit
  val fold : 'a t -> 'b -> (key -> 'a -> 'b -> 'b) -> 'b
  val for_all : 'a t -> (key -> 'a -> bool) -> bool
  val exists : 'a t -> (key -> 'a -> bool) -> bool
  (* val filter : 'a t -> (key -> 'a -> bool) -> 'a t *)
  (* val partition : 'a t -> (key -> 'a -> bool) -> 'a t * 'a t *)
  val cardinal : 'a t -> int
  val bindings : 'a t -> (key * 'a) list
  val keys : 'a t -> key list
  (* val choose : 'a t -> key * 'a *)

  val find_exn : 'a t -> key -> 'a
  val find_opt : 'a t -> key -> 'a option
  val find_default : 'a t -> key -> 'a -> 'a
  val map : 'a t -> ('a -> 'b) -> 'b t
  val mapi : 'a t -> (key -> 'a -> 'b) -> 'b t
  val of_list : (key * 'a) list -> 'a t
  val of_array : (key * 'a) array -> 'a t
  val add_list : (key * 'b) list -> 'b t -> 'b t
end

end = struct
#1 "map_gen.ml"
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

[@@@warnerror "+55"]
(* adapted from stdlib *)

type ('key,'a) t0 =
  | Empty
  | Leaf of {k : 'key ; v : 'a}
  | Node of {
      l : ('key,'a) t0 ;
      k : 'key ;
      v : 'a ;
      r : ('key,'a) t0 ;
      h : int
    }

let  empty = Empty
let rec map x f = match x with
    Empty -> Empty
  | Leaf {k;v} -> Leaf {k; v = f v}  
  | Node ({l; v ; r} as x) ->
    let l' = map l f in
    let d' = f v in
    let r' = map r f in
    Node { x with  l = l';  v = d'; r = r'}

let rec mapi x f = match x with
    Empty -> Empty
  | Leaf {k;v} -> Leaf {k; v = f k v}  
  | Node ({l; k ; v ; r} as x) ->
    let l' = mapi l f in
    let v' = f k v in
    let r' = mapi r f in
    Node {x with l = l'; v = v'; r = r'}

let [@inline] calc_height a b = (if a >= b  then a else b) + 1 
let [@inline] singleton k v = Leaf {k;v}
let [@inline] height = function
  | Empty -> 0
  | Leaf _ -> 1
  | Node {h} -> h

let [@inline] unsafe_node k v l  r h =   
  Node {l; k; v; r; h}
let [@inline] unsafe_two_elements k1 v1 k2 v2 = 
  unsafe_node k2 v2 (singleton k1 v1) empty 2   
let [@inline] unsafe_node_maybe_leaf k v l r h =   
  if h = 1 then Leaf {k ; v}   
  else Node{l;k;v;r; h }           


type ('key, + 'a) t = ('key,'a) t0 = private
  | Empty
  | Leaf of {
      k : 'key ;
      v : 'a
    }
  | Node of {
      l : ('key,'a) t ;
      k : 'key ;
      v : 'a ;
      r : ('key,'a) t ;
      h : int
    }

let rec cardinal_aux acc  = function
  | Empty -> acc 
  | Leaf _ -> acc + 1
  | Node {l; r} -> 
    cardinal_aux  (cardinal_aux (acc + 1)  r ) l 

let cardinal s = cardinal_aux 0 s 

let rec bindings_aux accu = function
  | Empty -> accu
  | Leaf {k;v} -> (k,v) :: accu
  | Node {l;k;v;r} -> bindings_aux ((k, v) :: bindings_aux accu r) l

let bindings s =
  bindings_aux [] s

let rec fill_array_with_f (s : _ t) i arr  f : int =    
  match s with 
  | Empty -> i 
  | Leaf  {k;v} -> 
    Array.unsafe_set arr i (f k v); i + 1
  | Node {l; k; v; r} -> 
    let inext = fill_array_with_f l i arr f in 
    Array.unsafe_set arr inext (f k v);
    fill_array_with_f r (inext + 1) arr f

let rec fill_array_aux (s : _ t) i arr : int =    
  match s with 
  | Empty -> i 
  | Leaf {k;v} -> 
    Array.unsafe_set arr i (k, v); i + 1
  | Node {l;k;v;r} -> 
    let inext = fill_array_aux l i arr in 
    Array.unsafe_set arr inext (k,v);
    fill_array_aux r (inext + 1) arr 


let to_sorted_array (s : ('key,'a) t)  : ('key * 'a ) array =    
  match s with 
  | Empty -> [||]
  | Leaf {k;v} -> [|k,v|]
  | Node {l;k;v;r} -> 
    let len = 
      cardinal_aux (cardinal_aux 1 r) l in 
    let arr =
      Array.make len (k,v) in  
    ignore (fill_array_aux s 0 arr : int);
    arr 

let to_sorted_array_with_f (type key a b ) (s : (key,a) t)  (f : key -> a -> b): b array =    
  match s with 
  | Empty -> [||]
  | Leaf {k;v} -> [| f k v|]
  | Node {l;k;v;r} -> 
    let len = 
      cardinal_aux (cardinal_aux 1 r) l in 
    let arr =
      Array.make len (f k v) in  
    ignore (fill_array_with_f s 0 arr f: int);
    arr     

let rec keys_aux accu = function
    Empty -> accu
  | Leaf {k} -> k :: accu
  | Node {l; k;r} -> keys_aux (k :: keys_aux accu r) l

let keys s = keys_aux [] s





let bal l x d r =
  let hl = height l in
  let hr = height r in
  if hl > hr + 2 then begin
    let [@warning "-8"] Node ({l=ll; r = lr} as l) = l in
    let hll = height ll in 
    let hlr = height lr in 
    if hll >= hlr then
      let hnode = calc_height hlr hr in       
      unsafe_node l.k l.v 
        ll  
        (unsafe_node_maybe_leaf x d lr  r hnode)
        (calc_height hll hnode)
    else         
      let [@warning "-8"] Node ({l=lrl; r=lrr} as lr) = lr in 
      let hlrl = height lrl in 
      let hlrr = height lrr in 
      let hlnode = calc_height hll hlrl in 
      let hrnode = calc_height hlrr hr in 
      unsafe_node lr.k lr.v 
        (unsafe_node_maybe_leaf l.k l.v ll  lrl hlnode)  
        (unsafe_node_maybe_leaf x d lrr r hrnode)      
        (calc_height hlnode hrnode)
  end else if hr > hl + 2 then begin
    let [@warning "-8"] Node ({l=rl; r=rr} as r) = r in 
    let hrr = height rr in 
    let hrl = height rl in 
    if hrr >= hrl then
      let hnode = calc_height hl hrl in
      unsafe_node r.k r.v 
        (unsafe_node_maybe_leaf x d l rl hnode)
        rr
        (calc_height hnode hrr)
    else 
      let [@warning "-8"] Node ({l=rll;  r=rlr} as rl) = rl in 
      let hrll = height rll in 
      let hrlr = height rlr in 
      let hlnode = (calc_height hl hrll) in
      let hrnode = (calc_height hrlr hrr) in      
      unsafe_node rl.k rl.v 
        (unsafe_node_maybe_leaf x d l  rll hlnode)  
        (unsafe_node_maybe_leaf r.k r.v rlr  rr hrnode)
        (calc_height hlnode hrnode)
  end else
    unsafe_node_maybe_leaf x d l r (calc_height hl hr)



let [@inline] is_empty = function Empty -> true | _ -> false

let rec min_binding_exn = function
    Empty -> raise Not_found
  | Leaf {k;v} -> (k,v)  
  | Node{l; k; v} -> 
    match l with 
    | Empty -> (k, v) 
    | Leaf _
    | Node _ -> 
      min_binding_exn l


let rec remove_min_binding = function
    Empty -> invalid_arg "Map.remove_min_elt"
  | Leaf _ -> empty  
  | Node{l=Empty;r} -> r
  | Node{l; k; v ; r} -> bal (remove_min_binding l) k v r

let merge t1 t2 =
  match (t1, t2) with
    (Empty, t) -> t
  | (t, Empty) -> t
  | (_, _) ->
    let (x, d) = min_binding_exn t2 in
    bal t1 x d (remove_min_binding t2)


let rec iter x f = match x with 
    Empty -> ()
  | Leaf {k;v} -> (f k v : unit) 
  | Node{l; k ; v ; r} ->
    iter l f; f k v; iter r f



let rec fold m accu f =
  match m with
    Empty -> accu
  | Leaf {k;v} -> f k v accu  
  | Node {l; k; v; r} ->
    fold r (f k v (fold l accu f)) f 

let rec for_all x p = match x with 
    Empty -> true
  | Leaf {k; v} -> p k v   
  | Node{l; k; v ; r} -> p k v && for_all l p && for_all r p

let rec exists x p = match x with
    Empty -> false
  | Leaf {k; v} -> p k v   
  | Node{l; k; v; r} -> p k v || exists l p || exists r p

(* Beware: those two functions assume that the added k is *strictly*
   smaller (or bigger) than all the present keys in the tree; it
   does not test for equality with the current min (or max) key.

   Indeed, they are only used during the "join" operation which
   respects this precondition.
*)

let rec add_min k v = function
  | Empty -> singleton k v
  | Leaf l -> unsafe_two_elements k v l.k l.v
  | Node tree ->
    bal (add_min k v tree.l) tree.k tree.v tree.r

let rec add_max k v = function
  | Empty -> singleton k v
  | Leaf l -> unsafe_two_elements l.k l.v k v
  | Node tree ->
    bal tree.l tree.k tree.v (add_max k v tree.r)

(* Same as create and bal, but no assumptions are made on the
   relative heights of l and r. *)

let rec join l v d r =
  match l with
  | Empty -> add_min v d r
  | Leaf leaf ->
    add_min leaf.k leaf.v (add_min v d r)
  | Node xl ->
    match r with  
    | Empty -> add_max v d l
    | Leaf leaf -> 
      add_max leaf.k leaf.v (add_max v d l)  
    | Node  xr ->
      let lh = xl.h in  
      let rh = xr.h in 
      if lh > rh + 2 then bal xl.l xl.k xl.v (join xl.r v d r) else
      if rh > lh + 2 then bal (join l v d xr.l) xr.k xr.v xr.r else
        unsafe_node v d l  r (calc_height lh rh)

(* Merge two trees l and r into one.
   All elements of l must precede the elements of r.
   No assumption on the heights of l and r. *)

let concat t1 t2 =
  match (t1, t2) with
    (Empty, t) -> t
  | (t, Empty) -> t
  | (_, _) ->
    let (x, d) = min_binding_exn t2 in
    join t1 x d (remove_min_binding t2)

let concat_or_join t1 v d t2 =
  match d with
  | Some d -> join t1 v d t2
  | None -> concat t1 t2


module type S =
sig
  type key
  type +'a t
  val empty: 'a t
  val compare_key: key -> key -> int 
  val is_empty: 'a t -> bool
  val mem: 'a t -> key -> bool
  val to_sorted_array : 
    'a t -> (key * 'a ) array
  val to_sorted_array_with_f : 
    'a t -> (key -> 'a -> 'b) -> 'b array  
  val add: 'a t -> key -> 'a -> 'a t
  (** [add x y m] 
      If [x] was already bound in [m], its previous binding disappears. *)

  val adjust: 'a t -> key -> ('a option->  'a) ->  'a t 
  (** [adjust acc k replace ] if not exist [add (replace None ], otherwise 
      [add k v (replace (Some old))]
  *)

  val singleton: key -> 'a -> 'a t

  val remove: 'a t -> key -> 'a t
  (** [remove x m] returns a map containing the same bindings as
      [m], except for [x] which is unbound in the returned map. *)

  (* val merge:
       'a t -> 'b t ->
       (key -> 'a option -> 'b option -> 'c option) ->  'c t *)
  (** [merge f m1 m2] computes a map whose keys is a subset of keys of [m1]
      and of [m2]. The presence of each such binding, and the corresponding
      value, is determined with the function [f].
      @since 3.12.0
  *)

  val disjoint_merge_exn : 
    'a t 
    -> 'a t 
    -> (key -> 'a -> 'a -> exn)
    -> 'a t
  (* merge two maps, will raise if they have the same key *)



  val iter: 'a t -> (key -> 'a -> unit) ->  unit
  (** [iter f m] applies [f] to all bindings in map [m].
      The bindings are passed to [f] in increasing order. *)

  val fold: 'a t -> 'b -> (key -> 'a -> 'b -> 'b) -> 'b
  (** [fold f m a] computes [(f kN dN ... (f k1 d1 a)...)],
      where [k1 ... kN] are the keys of all bindings in [m]
      (in increasing order) *)

  val for_all: 'a t -> (key -> 'a -> bool) -> bool
  (** [for_all p m] checks if all the bindings of the map.
      order unspecified
  *)

  val exists: 'a t -> (key -> 'a -> bool) -> bool
  (** [exists p m] checks if at least one binding of the map
      satisfy the predicate [p]. 
      order unspecified
  *)

  (* val filter: 'a t -> (key -> 'a -> bool) -> 'a t *)
  (** [filter p m] returns the map with all the bindings in [m]
      that satisfy predicate [p].
      order unspecified
  *)

  (* val partition: 'a t -> (key -> 'a -> bool) ->  'a t * 'a t *)
  (** [partition p m] returns a pair of maps [(m1, m2)], where
      [m1] contains all the bindings of [s] that satisfy the
      predicate [p], and [m2] is the map with all the bindings of
      [s] that do not satisfy [p].
  *)

  val cardinal: 'a t -> int
  (** Return the number of bindings of a map. *)

  val bindings: 'a t -> (key * 'a) list
  (** Return the list of all bindings of the given map.
      The returned list is sorted in increasing order with respect
      to the ordering *)

  val keys : 'a t -> key list 
  (* Increasing order *)



  (* val split: 'a t -> key -> 'a t * 'a option * 'a t *)
  (** [split x m] returns a triple [(l, data, r)], where
        [l] is the map with all the bindings of [m] whose key
      is strictly less than [x];
        [r] is the map with all the bindings of [m] whose key
      is strictly greater than [x];
        [data] is [None] if [m] contains no binding for [x],
        or [Some v] if [m] binds [v] to [x].
      @since 3.12.0
  *)

  val find_exn: 'a t -> key ->  'a
  (** [find x m] returns the current binding of [x] in [m],
      or raises [Not_found] if no such binding exists. *)
      
  val find_opt:  'a t ->  key ->'a option
  val find_default: 'a t -> key  ->  'a  -> 'a 
  val map: 'a t -> ('a -> 'b) -> 'b t
  (** [map f m] returns a map with same domain as [m], where the
      associated value [a] of all bindings of [m] has been
      replaced by the result of the application of [f] to [a].
      The bindings are passed to [f] in increasing order
      with respect to the ordering over the type of the keys. *)

  val mapi: 'a t ->  (key -> 'a -> 'b) -> 'b t
  (** Same as {!Map.S.map}, but the function receives as arguments both the
      key and the associated value for each binding of the map. *)

  val of_list : (key * 'a) list -> 'a t 
  val of_array : (key * 'a ) array -> 'a t 
  val add_list : (key * 'b) list -> 'b t -> 'b t

end

end
module Map_string : sig 
#1 "map_string.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


include Map_gen.S with type key = string

end = struct
#1 "map_string.ml"

# 2 "ext/map.cppo.ml"
(* we don't create [map_poly], since some operations require raise an exception which carries [key] *)

# 5 "ext/map.cppo.ml"
type key = string 
let compare_key = Ext_string.compare
let [@inline] eq_key (x : key) y = x = y
    
# 19 "ext/map.cppo.ml"
    (* let [@inline] (=) (a : int) b = a = b *)
type + 'a t = (key,'a) Map_gen.t

let empty = Map_gen.empty 
let is_empty = Map_gen.is_empty
let iter = Map_gen.iter
let fold = Map_gen.fold
let for_all = Map_gen.for_all 
let exists = Map_gen.exists 
let singleton = Map_gen.singleton 
let cardinal = Map_gen.cardinal
let bindings = Map_gen.bindings
let to_sorted_array = Map_gen.to_sorted_array
let to_sorted_array_with_f = Map_gen.to_sorted_array_with_f
let keys = Map_gen.keys



let map = Map_gen.map 
let mapi = Map_gen.mapi
let bal = Map_gen.bal 
let height = Map_gen.height 


let rec add (tree : _ Map_gen.t as 'a) x data  : 'a = match tree with 
  | Empty ->
    singleton x data
  | Leaf {k;v} ->
    let c = compare_key x k in 
    if c = 0 then singleton x data else
    if c < 0 then 
      Map_gen.unsafe_two_elements x data k v 
    else 
      Map_gen.unsafe_two_elements k v x data  
  | Node {l; k ; v ; r; h} ->
    let c = compare_key x k in
    if c = 0 then
      Map_gen.unsafe_node x data l r h (* at least need update data *)
    else if c < 0 then
      bal (add l x data ) k v r
    else
      bal l k v (add r x data )


let rec adjust (tree : _ Map_gen.t as 'a) x replace  : 'a = 
  match tree with 
  | Empty ->
    singleton x (replace None)
  | Leaf {k ; v} -> 
    let c = compare_key x k in 
    if c = 0 then singleton x (replace (Some v)) else 
    if c < 0 then 
      Map_gen.unsafe_two_elements x (replace None) k v   
    else
      Map_gen.unsafe_two_elements k v x (replace None)   
  | Node ({l; k ; r} as tree) ->
    let c = compare_key x k in
    if c = 0 then
      Map_gen.unsafe_node x (replace  (Some tree.v)) l r tree.h
    else if c < 0 then
      bal (adjust l x  replace ) k tree.v r
    else
      bal l k tree.v (adjust r x  replace )


let rec find_exn (tree : _ Map_gen.t ) x = match tree with 
  | Empty ->
    raise Not_found
  | Leaf leaf -> 
    if eq_key x leaf.k then leaf.v else raise Not_found  
  | Node tree ->
    let c = compare_key x tree.k in
    if c = 0 then tree.v
    else find_exn (if c < 0 then tree.l else tree.r) x

let rec find_opt (tree : _ Map_gen.t ) x = match tree with 
  | Empty -> None 
  | Leaf leaf -> 
    if eq_key x leaf.k then Some leaf.v else None
  | Node tree ->
    let c = compare_key x tree.k in
    if c = 0 then Some tree.v
    else find_opt (if c < 0 then tree.l else tree.r) x

let rec find_default (tree : _ Map_gen.t ) x  default     = match tree with 
  | Empty -> default  
  | Leaf leaf -> 
    if eq_key x leaf.k then  leaf.v else default
  | Node tree ->
    let c = compare_key x tree.k in
    if c = 0 then tree.v
    else find_default (if c < 0 then tree.l else tree.r) x default

let rec mem (tree : _ Map_gen.t )  x= match tree with 
  | Empty ->
    false
  | Leaf leaf -> eq_key x leaf.k 
  | Node{l; k ;  r} ->
    let c = compare_key x k in
    c = 0 || mem (if c < 0 then l else r) x 

let rec remove (tree : _ Map_gen.t as 'a) x : 'a = match tree with 
  | Empty -> empty
  | Leaf leaf -> 
    if eq_key x leaf.k then empty 
    else tree
  | Node{l; k ; v; r} ->
    let c = compare_key x k in
    if c = 0 then
      Map_gen.merge l r
    else if c < 0 then
      bal (remove l x) k v r
    else
      bal l k v (remove r x )

type 'a split = 
  | Yes of {l : (key,'a) Map_gen.t; r : (key,'a)Map_gen.t ; v : 'a}
  | No of {l : (key,'a) Map_gen.t; r : (key,'a)Map_gen.t }


let rec split  (tree : (key,'a) Map_gen.t) x : 'a split  = 
  match tree with 
  | Empty ->
    No {l = empty; r = empty}
  | Leaf leaf -> 
    let c = compare_key x leaf.k in 
    if c = 0 then Yes {l = empty; v= leaf.v; r = empty} 
    else if c < 0 then No { l = empty; r = tree }
    else  No { l = tree; r = empty}
  | Node {l; k ; v ; r} ->
    let c = compare_key x k in
    if c = 0 then Yes {l; v; r}
    else if c < 0 then      
      match  split l x with 
      | Yes result -> Yes {result with r = Map_gen.join result.r k v r }
      | No result -> No {result with r = Map_gen.join result.r k v r } 
    else
      match split r x with 
      | Yes result -> 
        Yes {result with l = Map_gen.join l k v result.l}
      | No result -> 
        No {result with l = Map_gen.join l k v result.l}


let rec disjoint_merge_exn  
    (s1 : _ Map_gen.t) 
    (s2  : _ Map_gen.t) 
    fail : _ Map_gen.t =
  match s1 with
  | Empty -> s2  
  | Leaf ({k } as l1)  -> 
    begin match s2 with 
      | Empty -> s1 
      | Leaf l2 -> 
        let c = compare_key k l2.k in 
        if c = 0 then raise_notrace (fail k l1.v l2.v)
        else if c < 0 then Map_gen.unsafe_two_elements l1.k l1.v l2.k l2.v
        else Map_gen.unsafe_two_elements l2.k l2.v k l1.v
      | Node _ -> 
        adjust s2 k (fun data -> 
            match data with 
            |  None -> l1.v
            | Some s2v  -> raise_notrace (fail k l1.v s2v)
          )        
    end
  | Node ({k} as xs1) -> 
    if  xs1.h >= height s2 then
      begin match split s2 k with 
        | No {l; r} -> 
          Map_gen.join 
            (disjoint_merge_exn  xs1.l l fail)
            k 
            xs1.v 
            (disjoint_merge_exn xs1.r r fail)
        | Yes { v =  s2v} ->
          raise_notrace (fail k xs1.v s2v)
      end        
    else let [@warning "-8"] (Node ({k} as s2) : _ Map_gen.t)  = s2 in 
      begin match  split s1 k with 
        | No {l;  r} -> 
          Map_gen.join 
            (disjoint_merge_exn  l s2.l fail) k s2.v 
            (disjoint_merge_exn  r s2.r fail)
        | Yes { v = s1v} -> 
          raise_notrace (fail k s1v s2.v)
      end






let add_list (xs : _ list ) init = 
  Ext_list.fold_left xs init (fun  acc (k,v) -> add acc k v )

let of_list xs = add_list xs empty

let of_array xs = 
  Ext_array.fold_left xs empty (fun acc (k,v) -> add acc k v ) 

end
module Bsb_db : sig 
#1 "bsb_db.mli"

(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

(** Store a file called [.bsbuild] that can be communicated 
    between [bsb.exe] and [bsb_helper.exe]. 
    [bsb.exe] stores such data which would be retrieved by 
    [bsb_helper.exe]. It is currently used to combine with 
    ocamldep to figure out which module->file it depends on
*) 

type case = bool 

type info = 
  | Intf (* intemediate state *)
  | Impl
  | Impl_intf

type syntax_kind =   
  | Ml 
  | Reason     
  | Res

type module_info = 
  {
    mutable info : info;
    dir : string;
    syntax_kind : syntax_kind;
    (* This is actually not stored in bsbuild meta info 
       since creating .d file only emit .cmj/.cmi dependencies, so it does not
       need know which syntax it is written
    *)
    case : bool;
    name_sans_extension : string;
  }

type map = module_info Map_string.t 

type 'a cat  = {
  mutable lib : 'a ; 
  mutable dev : 'a;
}

type t = map cat  

(** store  the meta data indexed by {!Bsb_dir_index}
    {[
      0 --> lib group
        1 --> dev 1 group
                    .

    ]}
*)






end = struct
#1 "bsb_db.ml"

(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

type case = bool
(** true means upper case*)


type info = 
  | Intf (* intemediate state *)
  | Impl
  | Impl_intf

type syntax_kind =   
  | Ml 
  | Reason     
  | Res

type module_info = 
  {
    mutable info : info;
    dir : string ; 
    syntax_kind : syntax_kind;
    case : bool;
    name_sans_extension : string  ;
  }


type map = module_info Map_string.t 

type 'a cat  = {
  mutable lib : 'a;
  mutable dev : 'a
}

type t = map cat 
(** indexed by the group *)






end
module Ext_pervasives : sig 
#1 "ext_pervasives.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)








(** Extension to standard library [Pervavives] module, safe to open 
*)

external reraise: exn -> 'a = "%reraise"

val finally : 
  'a ->
  clean:('a -> unit) -> 
  ('a -> 'b) -> 'b

(* val try_it : (unit -> 'a) ->  unit  *)

val with_file_as_chan : string -> (out_channel -> 'a) -> 'a













(* external id : 'a -> 'a = "%identity" *)

(** Copied from {!Btype.hash_variant}:
    need sync up and add test case
*)
(* val hash_variant : string -> int *)

(* val todo : string -> 'a *)

val nat_of_string_exn : string -> int

val parse_nat_of_string:
  string -> 
  int ref -> 
  int 
end = struct
#1 "ext_pervasives.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)






external reraise: exn -> 'a = "%reraise"

let finally v ~clean:action f   = 
  match f v with
  | exception e -> 
    action v ;
    reraise e 
  | e ->  action v ; e 

(* let try_it f  =   
   try ignore (f ()) with _ -> () *)

let with_file_as_chan filename f = 
  finally (open_out_bin filename) ~clean:close_out f 






(* external id : 'a -> 'a = "%identity" *)

(* 
let hash_variant s =
  let accu = ref 0 in
  for i = 0 to String.length s - 1 do
    accu := 223 * !accu + Char.code s.[i]
  done;
  (* reduce to 31 bits *)
  accu := !accu land (1 lsl 31 - 1);
  (* make it signed for 64 bits architectures *)
  if !accu > 0x3FFFFFFF then !accu - (1 lsl 31) else !accu *)

(* let todo loc = 
   failwith (loc ^ " Not supported yet")
*)



let rec int_of_string_aux s acc off len =  
  if off >= len then acc 
  else 
    let d = (Char.code (String.unsafe_get s off) - 48) in 
    if d >=0 && d <= 9 then 
      int_of_string_aux s (10*acc + d) (off + 1) len
    else -1 (* error *)

let nat_of_string_exn (s : string) = 
  let acc = int_of_string_aux s 0 0 (String.length s) in 
  if acc < 0 then invalid_arg s 
  else acc 


(** return index *)
let parse_nat_of_string (s : string) (cursor : int ref) =  
  let current = !cursor in 
  assert (current >= 0);
  let acc = ref 0 in 
  let s_len = String.length s in 
  let todo = ref true in 
  let cur = ref current in 
  while !todo && !cursor < s_len do 
    let d = Char.code (String.unsafe_get s !cur) - 48 in 
    if d >=0 && d <= 9 then begin 
      acc := 10* !acc + d;
      incr cur
    end else todo := false
  done ;
  cursor := !cur;
  !acc 
end
module Ext_io : sig 
#1 "ext_io.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

val load_file : string -> string

val rev_lines_of_file : string -> string list

val rev_lines_of_chann : in_channel -> string list

val write_file : string -> string -> unit

end = struct
#1 "ext_io.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


(** on 32 bit , there are 16M limitation *)
let load_file f =
  Ext_pervasives.finally (open_in_bin f) ~clean:close_in begin fun ic ->   
    let n = in_channel_length ic in
    let s = Bytes.create n in
    really_input ic s 0 n;
    Bytes.unsafe_to_string s
  end


let  rev_lines_of_chann chan = 
  let rec loop acc chan = 
    match input_line chan with
    | line -> loop (line :: acc) chan
    | exception End_of_file -> close_in chan ; acc in
  loop [] chan


let rev_lines_of_file file = 
  Ext_pervasives.finally 
    ~clean:close_in 
    (open_in_bin file) rev_lines_of_chann


let write_file f content = 
  Ext_pervasives.finally ~clean:close_out 
    (open_out_bin f)  begin fun oc ->   
    output_string oc content
  end

end
module Ext_string_array : sig 
#1 "ext_string_array.mli"
(* Copyright (C) 2020 - Present Authors of ReScript
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

val cmp : string -> string -> int 

val find_sorted : 
  string array -> string -> int option

val find_sorted_assoc : 
  (string * 'a ) array -> 
  string -> 
  'a option
end = struct
#1 "ext_string_array.ml"
(* Copyright (C) 2020 - Present Hongbo Zhang, Authors of ReScript
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


(* Invariant: the same as encoding Map_string.compare_key  *)  
let cmp  =  Ext_string.compare


let rec binarySearchAux (arr : string array) (lo : int) (hi : int) (key : string)  : _ option = 
  let mid = (lo + hi)/2 in 
  let midVal = Array.unsafe_get arr mid in 
  let c = cmp key midVal in 
  if c = 0 then Some (mid)
  else if c < 0 then  (*  a[lo] =< key < a[mid] <= a[hi] *)
    if hi = mid then  
      let loVal = (Array.unsafe_get arr lo) in 
      if  loVal = key then Some lo
      else None
    else binarySearchAux arr lo mid key 
  else  (*  a[lo] =< a[mid] < key <= a[hi] *)
  if lo = mid then 
    let hiVal = (Array.unsafe_get arr hi) in 
    if  hiVal = key then Some hi
    else None
  else binarySearchAux arr mid hi key 

let find_sorted sorted key  : int option =  
  let len = Array.length sorted in 
  if len = 0 then None
  else 
    let lo = Array.unsafe_get sorted 0 in 
    let c = cmp key lo in 
    if c < 0 then None
    else
      let hi = Array.unsafe_get sorted (len - 1) in 
      let c2 = cmp key hi in 
      if c2 > 0 then None
      else binarySearchAux sorted 0 (len - 1) key

let rec binarySearchAssoc  (arr : (string * _) array) (lo : int) (hi : int) (key : string)  : _ option = 
  let mid = (lo + hi)/2 in 
  let midVal = Array.unsafe_get arr mid in 
  let c = cmp key (fst midVal) in 
  if c = 0 then Some (snd midVal)
  else if c < 0 then  (*  a[lo] =< key < a[mid] <= a[hi] *)
    if hi = mid then  
      let loVal = (Array.unsafe_get arr lo) in 
      if  fst loVal = key then Some (snd loVal)
      else None
    else binarySearchAssoc arr lo mid key 
  else  (*  a[lo] =< a[mid] < key <= a[hi] *)
  if lo = mid then 
    let hiVal = (Array.unsafe_get arr hi) in 
    if  fst hiVal = key then Some (snd hiVal)
    else None
  else binarySearchAssoc arr mid hi key 

let find_sorted_assoc (type a) (sorted : (string * a) array) (key : string)  : a option =  
  let len = Array.length sorted in 
  if len = 0 then None
  else 
    let lo = Array.unsafe_get sorted 0 in 
    let c = cmp key (fst lo) in 
    if c < 0 then None
    else
      let hi = Array.unsafe_get sorted (len - 1) in 
      let c2 = cmp key (fst hi) in 
      if c2 > 0 then None
      else binarySearchAssoc sorted 0 (len - 1) key

end
module Literals
= struct
#1 "literals.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)







let js_array_ctor = "Array"
let js_type_number = "number"
let js_type_string = "string"
let js_type_object = "object"
let js_type_boolean = "boolean"
let js_undefined = "undefined"
let js_prop_length = "length"

let prim = "prim"
let param = "param"
let partial_arg = "partial_arg"
let tmp = "tmp"

let create = "create" (* {!Caml_exceptions.create}*)

let runtime = "runtime" (* runtime directory *)

let stdlib = "stdlib"

let imul = "imul" (* signed int32 mul *)

let setter_suffix = "#="
let setter_suffix_len = String.length setter_suffix

let debugger = "debugger"

let fn_run = "fn_run"
let method_run = "method_run"

let fn_method = "fn_method"
let fn_mk = "fn_mk"
(*let js_fn_runmethod = "js_fn_runmethod"*)





(** nodejs *)
let node_modules = "node_modules"
let node_modules_length = String.length "node_modules"
let package_json = "package.json"
let bsconfig_json = "bsconfig.json"
let build_ninja = "build.ninja"

(* Name of the library file created for each external dependency. *)
let library_file = "lib"

let suffix_a = ".a"
let suffix_cmj = ".cmj"
let suffix_cmo = ".cmo"
let suffix_cma = ".cma"
let suffix_cmi = ".cmi"
let suffix_cmx = ".cmx"
let suffix_cmxa = ".cmxa"
let suffix_mll = ".mll"
let suffix_ml = ".ml"
let suffix_mli = ".mli"
let suffix_re = ".re"
let suffix_rei = ".rei"
let suffix_res = ".res"
let suffix_resi = ".resi"
let suffix_mlmap = ".mlmap"

let suffix_cmt = ".cmt"
let suffix_cmti = ".cmti"
let suffix_ast = ".ast"
let suffix_iast = ".iast"
let suffix_d = ".d"
let suffix_js = ".js"
let suffix_bs_js = ".bs.js"
let suffix_mjs = ".mjs"
let suffix_cjs = ".cjs"
let suffix_gen_js = ".gen.js"
let suffix_gen_tsx = ".gen.tsx"

let commonjs = "commonjs"

let es6 = "es6"
let es6_global = "es6-global"

let unused_attribute = "Unused attribute "







(** Used when produce node compatible paths *)
let node_sep = "/"
let node_parent = ".."
let node_current = "."

let gentype_import = "genType.import"

let bsbuild_cache = ".bsbuild"

let sourcedirs_meta = ".sourcedirs.json"

(* Note the build system should check the validity of filenames
   espeically, it should not contain '-'
*)
let ns_sep_char = '-'
let ns_sep = "-"
let exception_id = "RE_EXN_ID"

let polyvar_hash = "NAME"
let polyvar_value = "VAL"

let cons = "::"
let hd = "hd"
let tl = "tl"

let lazy_done = "LAZY_DONE"
let lazy_val = "VAL"

let pure = "@__PURE__"
end
module Bsb_db_decode : sig 
#1 "bsb_db_decode.mli"
(* Copyright (C) 2019 - Present Authors of ReScript
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)




type group = private 
  | Dummy 
  | Group of {
      modules : string array ; 
      dir_length : int;
      dir_info_offset : int ; 
      module_info_offset : int;
    }

type t = { 
  lib : group ;
  dev : group ; 
  content : string (* string is whole content*)
}

val read_build_cache : 
  dir:string -> t



type module_info = {
  case : bool (* Bsb_db.case*);
  dir_name : string
} 

val find:
  t -> (* contains global info *)
  string -> (* module name *)
  bool -> (* more likely to be zero *)
  module_info option 


val decode : string -> t   
end = struct
#1 "bsb_db_decode.ml"
(* Copyright (C) 2019 - Present Hongbo Zhang, Authors of ReScript
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

let bsbuild_cache = Literals.bsbuild_cache


type group = 
  | Dummy 
  | Group of {
      modules : string array ; 
      dir_length : int;
      dir_info_offset : int ; 
      module_info_offset : int;
    }

type t = { 
  lib : group ;
  dev : group ; 
  content : string (* string is whole content*)
}


type cursor = int ref 


(*TODO: special case when module_count is zero *)
let rec decode (x : string) : t =   
  let (offset : cursor)  = ref 0 in 
  let lib = decode_single x offset in 
  let dev = decode_single x offset in
  {lib; dev; content = x}

and decode_single (x : string) (offset : cursor) : group = 
  let module_number = Ext_pervasives.parse_nat_of_string x offset in 
  incr offset;
  if module_number <> 0 then begin 
    let modules = decode_modules x offset module_number in 
    let dir_info_offset = !offset in 
    let module_info_offset = 
      String.index_from x dir_info_offset '\n'  + 1 in
    let dir_length = Char.code x.[module_info_offset] - 48 (* Char.code '0'*) in
    offset := 
      module_info_offset +
      1 +
      dir_length * module_number +
      1 
    ;
    Group { modules ; dir_info_offset; module_info_offset ; dir_length}
  end else Dummy
and decode_modules (x : string) (offset : cursor) module_number : string array =   
  let result = Array.make module_number "" in 
  let last = ref !offset in 
  let cur = ref !offset in 
  let tasks = ref 0 in 
  while !tasks <> module_number do 
    if String.unsafe_get x !cur = '\n' then 
      begin 
        let offs = !last in 
        let len = (!cur - !last) in         
        Array.unsafe_set result !tasks
          (Ext_string.unsafe_sub x offs len);
        incr tasks;
        last := !cur + 1;
      end;
    incr cur
  done ;
  offset := !cur;
  result


(* TODO: shall we check the consistency of digest *)
let read_build_cache ~dir  : t =   
  let all_content = 
    Ext_io.load_file (Filename.concat dir bsbuild_cache) in   
  decode all_content 



type module_info =  {
  case : bool ; (* which is Bsb_db.case*)
  dir_name : string
} 


let find_opt 
    ({content = whole} as db : t )  
    lib (key : string) 
  : module_info option = 
  match if lib then db.lib else db.dev with  
  | Dummy -> None
  | Group ({modules ;} as group) ->
    let i = Ext_string_array.find_sorted  modules key in 
    match i with 
    | None -> None 
    | Some count ->     
      let encode_len = group.dir_length in 
      let index = 
        Ext_string.get_1_2_3_4 whole 
          ~off:(group.module_info_offset + 1 + count * encode_len)
          encode_len
      in 
      let case = not (index mod 2 = 0) in 
      let ith = index lsr 1 in 
      let dir_name_start = 
        if ith = 0 then group.dir_info_offset 
        else 
          Ext_string.index_count 
            whole group.dir_info_offset '\t'
            ith + 1
      in 
      let dir_name_finish = 
        String.index_from
          whole dir_name_start '\t' 
      in    
      Some {case ; dir_name = String.sub whole dir_name_start (dir_name_finish - dir_name_start)}

let find db dependent_module is_not_lib_dir =         
  let opt = find_opt db true dependent_module in 
  match opt with 
  | Some _ -> opt
  | None -> 
    if is_not_lib_dir then 
      find_opt db false dependent_module 
    else None       
end
module Ext_buffer : sig 
#1 "ext_buffer.mli"
(***********************************************************************)
(*                                                                     *)
(*                                OCaml                                *)
(*                                                                     *)
(*  Pierre Weis and Xavier Leroy, projet Cristal, INRIA Rocquencourt   *)
(*                                                                     *)
(*  Copyright 1999 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the GNU Library General Public License, with    *)
(*  the special exception on linking described in file ../LICENSE.     *)
(*                                                                     *)
(***********************************************************************)

(** Extensible buffers.

    This module implements buffers that automatically expand
    as necessary.  It provides accumulative concatenation of strings
    in quasi-linear time (instead of quadratic time when strings are
    concatenated pairwise).
*)

(* ReScript customization: customized for efficient digest *)

type t
(** The abstract type of buffers. *)

val create : int -> t
(** [create n] returns a fresh buffer, initially empty.
    The [n] parameter is the initial size of the internal byte sequence
    that holds the buffer contents. That byte sequence is automatically
    reallocated when more than [n] characters are stored in the buffer,
    but shrinks back to [n] characters when [reset] is called.
    For best performance, [n] should be of the same order of magnitude
    as the number of characters that are expected to be stored in
    the buffer (for instance, 80 for a buffer that holds one output
    line).  Nothing bad will happen if the buffer grows beyond that
    limit, however. In doubt, take [n = 16] for instance.
    If [n] is not between 1 and {!Sys.max_string_length}, it will
    be clipped to that interval. *)

val contents : t -> string
(** Return a copy of the current contents of the buffer.
    The buffer itself is unchanged. *)

val length : t -> int
(** Return the number of characters currently contained in the buffer. *)

val is_empty : t -> bool

val clear : t -> unit
(** Empty the buffer. *)


val [@inline] add_char : t -> char -> unit
(** [add_char b c] appends the character [c] at the end of the buffer [b]. *)

val add_string : t -> string -> unit
(** [add_string b s] appends the string [s] at the end of the buffer [b]. *)

(* val add_bytes : t -> bytes -> unit *)
(** [add_string b s] appends the string [s] at the end of the buffer [b].
    @since 4.02 *)

(* val add_substring : t -> string -> int -> int -> unit *)
(** [add_substring b s ofs len] takes [len] characters from offset
    [ofs] in string [s] and appends them at the end of the buffer [b]. *)

(* val add_subbytes : t -> bytes -> int -> int -> unit *)
(** [add_substring b s ofs len] takes [len] characters from offset
    [ofs] in byte sequence [s] and appends them at the end of the buffer [b].
    @since 4.02 *)

(* val add_buffer : t -> t -> unit *)
(** [add_buffer b1 b2] appends the current contents of buffer [b2]
    at the end of buffer [b1].  [b2] is not modified. *)    

(* val add_channel : t -> in_channel -> int -> unit *)
(** [add_channel b ic n] reads exactly [n] character from the
    input channel [ic] and stores them at the end of buffer [b].
    Raise [End_of_file] if the channel contains fewer than [n]
    characters. *)

val output_buffer : out_channel -> t -> unit
(** [output_buffer oc b] writes the current contents of buffer [b]
    on the output channel [oc]. *)   

val digest : t -> Digest.t   

val not_equal : 
  t -> 
  string -> 
  bool 

val add_int_1 :    
  t -> int -> unit 

val add_int_2 :    
  t -> int -> unit 

val add_int_3 :    
  t -> int -> unit 

val add_int_4 :    
  t -> int -> unit 

val add_string_char :    
  t -> 
  string ->
  char -> 
  unit

val add_ninja_prefix_var : 
  t -> 
  string -> 
  unit 


val add_char_string :    
  t -> 
  char -> 
  string -> 
  unit
end = struct
#1 "ext_buffer.ml"
(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*    Pierre Weis and Xavier Leroy, projet Cristal, INRIA Rocquencourt    *)
(*                                                                        *)
(*   Copyright 1999 Institut National de Recherche en Informatique et     *)
(*     en Automatique.                                                    *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

(* Extensible buffers *)

type t =
  {mutable buffer : bytes;
   mutable position : int;
   mutable length : int;
   initial_buffer : bytes}

let create n =
  let n = if n < 1 then 1 else n in
  let s = Bytes.create n in
  {buffer = s; position = 0; length = n; initial_buffer = s}

let contents b = Bytes.sub_string b.buffer 0 b.position
(* let to_bytes b = Bytes.sub b.buffer 0 b.position  *)

(* let sub b ofs len =
   if ofs < 0 || len < 0 || ofs > b.position - len
   then invalid_arg "Ext_buffer.sub"
   else Bytes.sub_string b.buffer ofs len *)


(* let blit src srcoff dst dstoff len =
   if len < 0 || srcoff < 0 || srcoff > src.position - len
             || dstoff < 0 || dstoff > (Bytes.length dst) - len
   then invalid_arg "Ext_buffer.blit"
   else
    Bytes.unsafe_blit src.buffer srcoff dst dstoff len *)

let length b = b.position
let is_empty b = b.position = 0
let clear b = b.position <- 0

(* let reset b =
   b.position <- 0; b.buffer <- b.initial_buffer;
   b.length <- Bytes.length b.buffer *)

let resize b more =
  let len = b.length in
  let new_len = ref len in
  while b.position + more > !new_len do new_len := 2 * !new_len done;
  let new_buffer = Bytes.create !new_len in
  (* PR#6148: let's keep using [blit] rather than [unsafe_blit] in
     this tricky function that is slow anyway. *)
  Bytes.blit b.buffer 0 new_buffer 0 b.position;
  b.buffer <- new_buffer;
  b.length <- !new_len ;
  assert (b.position + more <= b.length)

let [@inline] add_char b c =
  let pos = b.position in
  if pos >= b.length then resize b 1;
  Bytes.unsafe_set b.buffer pos c;
  b.position <- pos + 1  

(* let add_substring b s offset len =
   if offset < 0 || len < 0 || offset > String.length s - len
   then invalid_arg "Ext_buffer.add_substring/add_subbytes";
   let new_position = b.position + len in
   if new_position > b.length then resize b len;
   Ext_bytes.unsafe_blit_string s offset b.buffer b.position len;
   b.position <- new_position   *)


(* let add_subbytes b s offset len =
   add_substring b (Bytes.unsafe_to_string s) offset len *)

let add_string b s =
  let len = String.length s in
  let new_position = b.position + len in
  if new_position > b.length then resize b len;
  Ext_bytes.unsafe_blit_string s 0 b.buffer b.position len;
  b.position <- new_position  

(* TODO: micro-optimzie *)
let add_string_char b s c =
  let s_len = String.length s in
  let len = s_len + 1 in 
  let new_position = b.position + len in
  if new_position > b.length then resize b len;
  let b_buffer = b.buffer in 
  Ext_bytes.unsafe_blit_string s 0 b_buffer b.position s_len;
  Bytes.unsafe_set b_buffer (new_position - 1) c;
  b.position <- new_position 

let add_char_string b c s  =
  let s_len = String.length s in
  let len = s_len + 1 in 
  let new_position = b.position + len in
  if new_position > b.length then resize b len;
  let b_buffer = b.buffer in 
  let b_position = b.position in 
  Bytes.unsafe_set b_buffer b_position c ; 
  Ext_bytes.unsafe_blit_string s 0 b_buffer (b_position + 1) s_len;
  b.position <- new_position

(* equivalent to add_char " "; add_char "$"; add_string s  *)
let add_ninja_prefix_var b s =  
  let s_len = String.length s in
  let len = s_len + 2 in 
  let new_position = b.position + len in
  if new_position > b.length then resize b len;
  let b_buffer = b.buffer in 
  let b_position = b.position in 
  Bytes.unsafe_set b_buffer b_position ' ' ; 
  Bytes.unsafe_set b_buffer (b_position + 1) '$' ; 
  Ext_bytes.unsafe_blit_string s 0 b_buffer (b_position + 2) s_len;
  b.position <- new_position


(* let add_bytes b s = add_string b (Bytes.unsafe_to_string s)

   let add_buffer b bs =
   add_subbytes b bs.buffer 0 bs.position *)

(* let add_channel b ic len =
   if len < 0 
    || len > Sys.max_string_length 
    then   (* PR#5004 *)
    invalid_arg "Ext_buffer.add_channel";
   if b.position + len > b.length then resize b len;
   really_input ic b.buffer b.position len;
   b.position <- b.position + len *)

let output_buffer oc b =
  output oc b.buffer 0 b.position  

external unsafe_string: bytes -> int -> int -> Digest.t = "caml_md5_string"

let digest b = 
  unsafe_string 
    b.buffer 0 b.position    

let rec not_equal_aux (b : bytes) (s : string) i len = 
  if i >= len then false
  else 
    (Bytes.unsafe_get b i 
     <>
     String.unsafe_get s i )
    || not_equal_aux b s (i + 1) len 

(** avoid a large copy *)
let not_equal  (b : t) (s : string) = 
  let b_len = b.position in 
  let s_len = String.length s in 
  b_len <> s_len 
  || not_equal_aux b.buffer s 0 s_len


(**
   It could be one byte, two bytes, three bytes and four bytes 
   TODO: inline for better performance
*)
let add_int_1 (b : t ) (x : int ) = 
  let c = (Char.unsafe_chr (x land 0xff)) in 
  let pos = b.position in
  if pos >= b.length then resize b 1;
  Bytes.unsafe_set b.buffer pos c;
  b.position <- pos + 1  

let add_int_2 (b : t ) (x : int ) = 
  let c1 = (Char.unsafe_chr (x land 0xff)) in 
  let c2 = (Char.unsafe_chr (x lsr 8 land 0xff)) in   
  let pos = b.position in
  if pos + 1 >= b.length then resize b 2;
  let b_buffer = b.buffer in 
  Bytes.unsafe_set b_buffer pos c1;
  Bytes.unsafe_set b_buffer (pos + 1) c2;
  b.position <- pos + 2

let add_int_3 (b : t ) (x : int ) = 
  let c1 = (Char.unsafe_chr (x land 0xff)) in 
  let c2 = (Char.unsafe_chr (x lsr 8 land 0xff)) in   
  let c3 = (Char.unsafe_chr (x lsr 16 land 0xff)) in
  let pos = b.position in
  if pos + 2 >= b.length then resize b 3;
  let b_buffer = b.buffer in 
  Bytes.unsafe_set b_buffer pos c1;
  Bytes.unsafe_set b_buffer (pos + 1) c2;
  Bytes.unsafe_set b_buffer (pos + 2) c3;
  b.position <- pos + 3


let add_int_4 (b : t ) (x : int ) = 
  let c1 = (Char.unsafe_chr (x land 0xff)) in 
  let c2 = (Char.unsafe_chr (x lsr 8 land 0xff)) in   
  let c3 = (Char.unsafe_chr (x lsr 16 land 0xff)) in
  let c4 = (Char.unsafe_chr (x lsr 24 land 0xff)) in
  let pos = b.position in
  if pos + 3 >= b.length then resize b 4;
  let b_buffer = b.buffer in 
  Bytes.unsafe_set b_buffer pos c1;
  Bytes.unsafe_set b_buffer (pos + 1) c2;
  Bytes.unsafe_set b_buffer (pos + 2) c3;
  Bytes.unsafe_set b_buffer (pos + 3) c4;
  b.position <- pos + 4




end
module Bs_hash_stubs
= struct
#1 "bs_hash_stubs.ml"


external hash_string :  string -> int = "caml_bs_hash_string" [@@noalloc];;

external hash_string_int :  string -> int  -> int = "caml_bs_hash_string_and_int" [@@noalloc];;

external hash_string_small_int :  string -> int  -> int = "caml_bs_hash_string_and_small_int" [@@noalloc];;

external hash_stamp_and_name : int -> string -> int = "caml_bs_hash_stamp_and_name" [@@noalloc];;

external hash_small_int : int -> int = "caml_bs_hash_small_int" [@@noalloc];;

external hash_int :  int  -> int = "caml_bs_hash_int" [@@noalloc];;

external string_length_based_compare : string -> string -> int  = "caml_string_length_based_compare" [@@noalloc];;

external    
  int_unsafe_blit : 
  int array -> int -> int array -> int -> int -> unit = "caml_int_array_blit" [@@noalloc];;





external set_as_old_file : string -> unit = "caml_stale_file"
end
module Ext_util : sig 
#1 "ext_util.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)



val power_2_above : int -> int -> int


val stats_to_string : Hashtbl.statistics -> string 
end = struct
#1 "ext_util.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

(**
   {[
     (power_2_above 16 63 = 64)
       (power_2_above 16 76 = 128)
   ]}
*)
let rec power_2_above x n =
  if x >= n then x
  else if x * 2 > Sys.max_array_length then x
  else power_2_above (x * 2) n


let stats_to_string ({num_bindings; num_buckets; max_bucket_length; bucket_histogram} : Hashtbl.statistics) = 
  Printf.sprintf 
    "bindings: %d,buckets: %d, longest: %d, hist:[%s]" 
    num_bindings 
    num_buckets 
    max_bucket_length
    (String.concat "," (Array.to_list (Array.map string_of_int bucket_histogram)))
end
module Hash_gen
= struct
#1 "hash_gen.ml"
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

(* Hash tables *)




(* We do dynamic hashing, and resize the table and rehash the elements
   when buckets become too long. *)

type ('a, 'b) bucket =
  | Empty
  | Cons of {
      mutable key : 'a ; 
      mutable data : 'b ; 
      mutable next :  ('a, 'b) bucket
    }

type ('a, 'b) t =
  { mutable size: int;                        (* number of entries *)
    mutable data: ('a, 'b) bucket array;  (* the buckets *)
    initial_size: int;                        (* initial array size *)
  }



let create  initial_size =
  let s = Ext_util.power_2_above 16 initial_size in
  { initial_size = s; size = 0; data = Array.make s Empty }

let clear h =
  h.size <- 0;
  let len = Array.length h.data in
  for i = 0 to len - 1 do
    Array.unsafe_set h.data i  Empty  
  done

let reset h =
  h.size <- 0;
  h.data <- Array.make h.initial_size Empty


let length h = h.size

let resize indexfun h =
  let odata = h.data in
  let osize = Array.length odata in
  let nsize = osize * 2 in
  if nsize < Sys.max_array_length then begin
    let ndata = Array.make nsize Empty in
    let ndata_tail = Array.make nsize Empty in 
    h.data <- ndata;          (* so that indexfun sees the new bucket count *)
    let rec insert_bucket = function
        Empty -> ()
      | Cons {key; next} as cell ->
        let nidx = indexfun h key in
        begin match Array.unsafe_get ndata_tail nidx with 
          | Empty -> 
            Array.unsafe_set ndata nidx cell
          | Cons tail ->
            tail.next <- cell  
        end;
        Array.unsafe_set ndata_tail nidx cell;
        insert_bucket next
    in
    for i = 0 to osize - 1 do
      insert_bucket (Array.unsafe_get odata i)
    done;
    for i = 0 to nsize - 1 do 
      match Array.unsafe_get ndata_tail i with 
      | Empty -> ()  
      | Cons tail -> tail.next <- Empty
    done   
  end



let iter h f =
  let rec do_bucket = function
    | Empty ->
      ()
    | Cons l  ->
      f l.key l.data; do_bucket l.next in
  let d = h.data in
  for i = 0 to Array.length d - 1 do
    do_bucket (Array.unsafe_get d i)
  done

let fold h init f =
  let rec do_bucket b accu =
    match b with
      Empty ->
      accu
    | Cons l ->
      do_bucket l.next (f l.key l.data accu) in
  let d = h.data in
  let accu = ref init in
  for i = 0 to Array.length d - 1 do
    accu := do_bucket (Array.unsafe_get d i) !accu
  done;
  !accu

let to_list h f =
  fold h [] (fun k data acc -> f k data :: acc)  




let rec small_bucket_mem (lst : _ bucket) eq key  =
  match lst with 
  | Empty -> false 
  | Cons lst -> 
    eq  key lst.key ||
    match lst.next with
    | Empty -> false 
    | Cons lst -> 
      eq key lst.key  || 
      match lst.next with 
      | Empty -> false 
      | Cons lst -> 
        eq key lst.key  ||
        small_bucket_mem lst.next eq key 


let rec small_bucket_opt eq key (lst : _ bucket) : _ option =
  match lst with 
  | Empty -> None 
  | Cons lst -> 
    if eq  key lst.key then Some lst.data else 
      match lst.next with
      | Empty -> None 
      | Cons lst -> 
        if eq key lst.key then Some lst.data else 
          match lst.next with 
          | Empty -> None 
          | Cons lst -> 
            if eq key lst.key  then Some lst.data else 
              small_bucket_opt eq key lst.next


let rec small_bucket_key_opt eq key (lst : _ bucket) : _ option =
  match lst with 
  | Empty -> None 
  | Cons {key=k;  next} -> 
    if eq  key k then Some k else 
      match next with
      | Empty -> None 
      | Cons {key=k; next} -> 
        if eq key k then Some k else 
          match next with 
          | Empty -> None 
          | Cons {key=k; next} -> 
            if eq key k  then Some k else 
              small_bucket_key_opt eq key next


let rec small_bucket_default eq key default (lst : _ bucket) =
  match lst with 
  | Empty -> default 
  | Cons lst -> 
    if eq  key lst.key then  lst.data else 
      match lst.next with
      | Empty -> default 
      | Cons lst -> 
        if eq key lst.key then  lst.data else 
          match lst.next with 
          | Empty -> default 
          | Cons lst -> 
            if eq key lst.key  then lst.data else 
              small_bucket_default eq key default lst.next

let rec remove_bucket 
    h  (i : int)
    key 
    ~(prec : _ bucket) 
    (buck : _ bucket) 
    eq_key = 
  match buck with   
  | Empty ->
    ()
  | Cons {key=k; next }  ->
    if eq_key k key 
    then begin
      h.size <- h.size - 1;
      match prec with
      | Empty -> Array.unsafe_set h.data i  next
      | Cons c -> c.next <- next
    end
    else remove_bucket h i key ~prec:buck next eq_key

let rec replace_bucket key data (buck : _ bucket) eq_key = 
  match buck with   
  | Empty ->
    true
  | Cons slot ->
    if eq_key slot.key key
    then (slot.key <- key; slot.data <- data; false)
    else replace_bucket key data slot.next eq_key

module type S = sig 
  type key
  type 'a t
  val create: int -> 'a t
  val clear: 'a t -> unit
  val reset: 'a t -> unit

  val add: 'a t -> key -> 'a -> unit
  val add_or_update: 
    'a t -> 
    key -> 
    update:('a -> 'a) -> 
    'a -> unit 
  val remove: 'a t -> key -> unit
  val find_exn: 'a t -> key -> 'a
  val find_all: 'a t -> key -> 'a list
  val find_opt: 'a t -> key  -> 'a option

  (** return the key found in the hashtbl.
      Use case: when you find the key existed in hashtbl, 
      you want to use the one stored in the hashtbl. 
      (they are semantically equivlanent, but may have other information different) 
  *)
  val find_key_opt: 'a t -> key -> key option 

  val find_default: 'a t -> key -> 'a -> 'a 

  val replace: 'a t -> key -> 'a -> unit
  val mem: 'a t -> key -> bool
  val iter: 'a t -> (key -> 'a -> unit) -> unit
  val fold: 
    'a t -> 'b ->
    (key -> 'a -> 'b -> 'b) ->  'b
  val length: 'a t -> int
  (* val stats: 'a t -> Hashtbl.statistics *)
  val to_list : 'a t -> (key -> 'a -> 'c) -> 'c list
  val of_list2: key list -> 'a list -> 'a t
end





end
module Hash_string : sig 
#1 "hash_string.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


include Hash_gen.S with type key = string




end = struct
#1 "hash_string.ml"
# 9 "ext/hash.cppo.ml"
type key = string
type 'a t = (key, 'a)  Hash_gen.t 
let key_index (h : _ t ) (key : key) =
  (Bs_hash_stubs.hash_string  key ) land (Array.length h.data - 1)
let eq_key = Ext_string.equal 

  
# 33 "ext/hash.cppo.ml"
  type ('a, 'b) bucket = ('a,'b) Hash_gen.bucket
  let create = Hash_gen.create
  let clear = Hash_gen.clear
  let reset = Hash_gen.reset
  let iter = Hash_gen.iter
  let to_list = Hash_gen.to_list
  let fold = Hash_gen.fold
  let length = Hash_gen.length
  (* let stats = Hash_gen.stats *)



  let add (h : _ t) key data =
    let i = key_index h key in
    let h_data = h.data in   
    Array.unsafe_set h_data i (Cons{key; data; next=Array.unsafe_get h_data i});
    h.size <- h.size + 1;
    if h.size > Array.length h_data lsl 1 then Hash_gen.resize key_index h

  (* after upgrade to 4.04 we should provide an efficient [replace_or_init] *)
  let add_or_update 
      (h : 'a t) 
      (key : key) 
      ~update:(modf : 'a -> 'a) 
      (default :  'a) : unit =
    let rec find_bucket (bucketlist : _ bucket) : bool =
      match bucketlist with
      | Cons rhs  ->
        if eq_key rhs.key key then begin rhs.data <- modf rhs.data; false end
        else find_bucket rhs.next
      | Empty -> true in
    let i = key_index h key in 
    let h_data = h.data in 
    if find_bucket (Array.unsafe_get h_data i) then
      begin 
        Array.unsafe_set h_data i  (Cons{key; data=default; next = Array.unsafe_get h_data i});
        h.size <- h.size + 1 ;
        if h.size > Array.length h_data lsl 1 then Hash_gen.resize key_index h 
      end

  let remove (h : _ t ) key =
    let i = key_index h key in
    let h_data = h.data in 
    Hash_gen.remove_bucket h i key ~prec:Empty (Array.unsafe_get h_data i) eq_key

  (* for short bucket list, [find_rec is not called ] *)
  let rec find_rec key (bucketlist : _ bucket) = match bucketlist with  
    | Empty ->
      raise Not_found
    | Cons rhs  ->
      if eq_key key rhs.key then rhs.data else find_rec key rhs.next

  let find_exn (h : _ t) key =
    match Array.unsafe_get h.data (key_index h key) with
    | Empty -> raise Not_found
    | Cons rhs  ->
      if eq_key key rhs.key then rhs.data else
        match rhs.next with
        | Empty -> raise Not_found
        | Cons rhs  ->
          if eq_key key rhs.key then rhs.data else
            match rhs.next with
            | Empty -> raise Not_found
            | Cons rhs ->
              if eq_key key rhs.key  then rhs.data else find_rec key rhs.next

  let find_opt (h : _ t) key =
    Hash_gen.small_bucket_opt eq_key key (Array.unsafe_get h.data (key_index h key))

  let find_key_opt (h : _ t) key =
    Hash_gen.small_bucket_key_opt eq_key key (Array.unsafe_get h.data (key_index h key))

  let find_default (h : _ t) key default = 
    Hash_gen.small_bucket_default eq_key key default (Array.unsafe_get h.data (key_index h key))

  let find_all (h : _ t) key =
    let rec find_in_bucket (bucketlist : _ bucket) = match bucketlist with 
      | Empty ->
        []
      | Cons rhs  ->
        if eq_key key rhs.key
        then rhs.data :: find_in_bucket rhs.next
        else find_in_bucket rhs.next in
    find_in_bucket (Array.unsafe_get h.data (key_index h key))


  let replace h key data =
    let i = key_index h key in
    let h_data = h.data in 
    let l = Array.unsafe_get h_data i in
    if Hash_gen.replace_bucket key data l eq_key then 
      begin 
        Array.unsafe_set h_data i (Cons{key; data; next=l});
        h.size <- h.size + 1;
        if h.size > Array.length h_data lsl 1 then Hash_gen.resize key_index h;
      end 

  let mem (h : _ t) key = 
    Hash_gen.small_bucket_mem 
      (Array.unsafe_get h.data (key_index h key))
      eq_key key 


  let of_list2 ks vs = 
    let len = List.length ks in 
    let map = create len in 
    List.iter2 (fun k v -> add map k v) ks vs ; 
    map


end
module Bsb_db_encode : sig 
#1 "bsb_db_encode.mli"
(* Copyright (C) 2019 - Present Hongbo Zhang, Authors of ReScript
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


val encode : 
  Bsb_db.t -> 
  Ext_buffer.t -> 
  unit 

val write_build_cache : 
  dir:string -> Bsb_db.t -> string

end = struct
#1 "bsb_db_encode.ml"
(* Copyright (C) 2019 - Present Hongbo Zhang, Authors of ReScript
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


let bsbuild_cache = Literals.bsbuild_cache


let nl buf = 
  Ext_buffer.add_char buf '\n'



(* IDEAS: 
   Pros: 
   - could be even shortened to a single byte
     Cons: 
   - decode would allocate
   - code too verbose
   - not readable 
*)  

let make_encoding length buf : Ext_buffer.t -> int -> unit =
  let max_range = length lsl 1 + 1 in 
  if max_range <= 0xff then begin 
    Ext_buffer.add_char buf '1';
    Ext_buffer.add_int_1
  end
  else if max_range <= 0xff_ff then begin 
    Ext_buffer.add_char buf '2';
    Ext_buffer.add_int_2
  end
  else if length <= 0x7f_ff_ff then begin 
    Ext_buffer.add_char buf '3';
    Ext_buffer.add_int_3
  end
  else if length <= 0x7f_ff_ff_ff then begin
    Ext_buffer.add_char buf '4';
    Ext_buffer.add_int_4
  end else assert false 
(* Make sure [tmp_buf1] and [tmp_buf2] is cleared ,
   they are only used to control the order.
   Strictly speaking, [tmp_buf1] is not needed
*)
let encode_single (db : Bsb_db.map) (buf : Ext_buffer.t) =    
  (* module name section *)  
  let len = Map_string.cardinal db in 
  Ext_buffer.add_string_char buf (string_of_int len) '\n';
  if len <> 0 then begin 
    let mapping = Hash_string.create 50 in 
    Map_string.iter db (fun name {dir} ->  
        Ext_buffer.add_string_char buf name '\n'; 
        if not (Hash_string.mem mapping dir) then
          Hash_string.add mapping dir (Hash_string.length mapping)
      ); 
    let length = Hash_string.length mapping in   
    let rev_mapping = Array.make length "" in 
    Hash_string.iter mapping (fun k i -> Array.unsafe_set rev_mapping i k);
    (* directory name section *)
    Ext_array.iter rev_mapping (fun s -> Ext_buffer.add_string_char buf s '\t');
    nl buf; (* module name info section *)
    let len_encoding = make_encoding length buf in 
    Map_string.iter db (fun _ module_info ->       
        len_encoding buf 
          (Hash_string.find_exn  mapping module_info.dir lsl 1 + (Obj.magic (module_info.case : bool) : int)));      
    nl buf 
  end
let encode (dbs : Bsb_db.t) buf =     
  encode_single dbs.lib buf ;
  encode_single dbs.dev buf 


(*  shall we avoid writing such file (checking the digest)?
    It is expensive to start scanning the whole code base,
    we should we avoid it in the first place, if we do start scanning,
    this operation seems affordable
*)
let write_build_cache ~dir (bs_files : Bsb_db.t)  : string = 
  let oc = open_out_bin (Filename.concat dir bsbuild_cache) in 
  let buf = Ext_buffer.create 100_000 in 
  encode bs_files buf ; 
  Ext_buffer.output_buffer oc buf;
  close_out oc; 
  let digest = Ext_buffer.digest buf in 
  Digest.to_hex digest 

end
module Bsb_pkg_types : sig 
#1 "bsb_pkg_types.mli"
(* Copyright (C) 2019- Hongbo Zhang, Authors of ReScript
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


type t = 
  | Global of string
  | Scope of string * scope
and scope = string  

val to_string : t -> string 
val print : Format.formatter -> t -> unit 
val equal : t -> t -> bool 

(* The second element could be empty or dropped 
*)
val extract_pkg_name_and_file : string -> t * string 
val string_as_package : string -> t 
end = struct
#1 "bsb_pkg_types.ml"

(* Copyright (C) 2018- Hongbo Zhang, Authors of ReScript
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

let (//) = Filename.concat

type t = 
  | Global of string
  | Scope of string * scope
and scope = string  

let to_string (x : t) = 
  match x with
  | Global s -> s
  | Scope (s,scope) -> scope // s 

let print fmt (x : t) = 
  match x with   
  | Global s -> Format.pp_print_string fmt s 
  | Scope(name,scope) -> 
    Format.fprintf fmt "%s/%s" scope name

let equal (x : t) y = 
  match x, y with 
  | Scope(a0,a1), Scope(b0,b1) 
    -> a0 = b0 && a1 = b1
  | Global a0, Global b0 -> a0 = b0
  | Scope _, Global _ 
  | Global _, Scope _ -> false

(**
   input: {[
     @hello/yy/xx
        hello/yy
   ]}
   FIXME: fix invalid input
   {[
     hello//xh//helo
   ]}
*)
let extract_pkg_name_and_file (s : string) =   
  let len = String.length s in 
  assert (len  > 0 ); 
  let v = String.unsafe_get s 0 in 
  if v = '@' then 
    let scope_id = 
      Ext_string.no_slash_idx s  in 
    assert (scope_id > 0);
    let pkg_id =   
      Ext_string.no_slash_idx_from
        s (scope_id + 1)   in 
    let scope =     
      String.sub s 0 scope_id in 

    if pkg_id < 0 then     
      (Scope(String.sub s (scope_id + 1) (len - scope_id - 1), scope),"")
    else 
      (Scope(
          String.sub s (scope_id + 1) (pkg_id - scope_id - 1), scope), 
       String.sub s (pkg_id + 1) (len - pkg_id - 1))
  else     
    let pkg_id = Ext_string.no_slash_idx s in 
    if pkg_id < 0 then 
      Global s , ""
    else 
      Global (String.sub s 0 pkg_id), 
      (String.sub s (pkg_id + 1) (len - pkg_id - 1))


let string_as_package (s : string) : t = 
  let len = String.length s in 
  assert (len > 0); 
  let v = String.unsafe_get s 0 in 
  if v = '@' then 
    let scope_id = 
      Ext_string.no_slash_idx s in 
    assert (scope_id > 0); 
    (* better-eror message for invalid scope package:
       @rescript/std
    *)
    Scope(
      String.sub s (scope_id + 1) (len - scope_id - 1),
      String.sub s 0 scope_id
    )    
  else Global s       
end
module Ounit_bsb_pkg_tests
= struct
#1 "ounit_bsb_pkg_tests.ml"


let ((>::),
     (>:::)) = OUnit.((>::),(>:::))

let printer_string = fun x -> x 
let (=~) = OUnit.assert_equal  ~printer:printer_string  


let scope_test s (a,b,c)= 
  match Bsb_pkg_types.extract_pkg_name_and_file s with 
  | Scope(a0,b0),c0 -> 
    a =~ a0 ; b =~ b0 ; c =~ c0
  | Global _,_ -> OUnit.assert_failure __LOC__

let global_test s (a,b) = 
  match Bsb_pkg_types.extract_pkg_name_and_file s with 
  | Scope _, _ -> 
    OUnit.assert_failure __LOC__
  | Global a0, b0-> 
    a=~a0; b=~b0

let s_test0 s (a,b)=     
  match Bsb_pkg_types.string_as_package s with 
  | Scope(name,scope) -> 
      a =~ name ; b =~scope 
  | _ -> OUnit.assert_failure __LOC__     

let s_test1 s a =     
  match Bsb_pkg_types.string_as_package s with 
  | Global x  -> 
      a =~ x
  | _ -> OUnit.assert_failure __LOC__       

let group0 = Map_string.of_list [
  "Liba", 
  {Bsb_db.info = Impl_intf; dir= "a";syntax_kind=Ml;case = false;
  name_sans_extension = "liba"}
]
let group1 =  Map_string.of_list [
  "Ciba", 
  {Bsb_db.info = Impl_intf; dir= "b";syntax_kind=Ml;case = false;
  name_sans_extension = "liba"}
] 

let parse_db db : Bsb_db_decode.t =   
  let buf = Ext_buffer.create 10_000 in   
  Bsb_db_encode.encode db buf;
  let s = Ext_buffer.contents buf in
  Bsb_db_decode.decode s

let suites = 
  __FILE__ >::: [
    __LOC__ >:: begin fun _ -> 
      scope_test "@hello/hi"
        ("hi", "@hello","");

      scope_test "@hello/hi/x"
        ("hi", "@hello","x");

      
      scope_test "@hello/hi/x/y"
        ("hi", "@hello","x/y");  
  end ;
  __LOC__ >:: begin fun _ -> 
    global_test "hello"
      ("hello","");
    global_test "hello/x"
      ("hello","x");  
    global_test "hello/x/y"
      ("hello","x/y")    
  end ;
  __LOC__ >:: begin fun _ -> 
    s_test0 "@x/y" ("y","@x");
    s_test0 "@x/y/z" ("y/z","@x");
    s_test1 "xx" "xx";
    s_test1 "xx/yy/zz" "xx/yy/zz"
  end;

  __LOC__ >:: begin fun _ ->
    match parse_db {lib= group0; dev = group1}with 
    | {lib = Group {modules = [|"Liba"|]};
       dev = Group {modules = [|"Ciba"|]}}
        -> OUnit.assert_bool __LOC__ true
    | _ ->
      OUnit.assert_failure __LOC__    
  end  ;
  __LOC__ >:: begin fun _ -> 
    match parse_db {lib = group0;dev = Map_string.empty } with
    | {lib = Group {modules = [|"Liba"|]};
      dev = Dummy}
      -> OUnit.assert_bool __LOC__ true
    | _ ->
      OUnit.assert_failure __LOC__    
  end  ;
  __LOC__ >:: begin fun _ -> 
    match parse_db {lib = Map_string.empty ; dev = group1} with
    | {lib = Dummy;
       dev = Group {modules = [|"Ciba"|]}
       }
      -> OUnit.assert_bool __LOC__ true
    | _ ->
      OUnit.assert_failure __LOC__    
  end
  (* __LOC__ >:: begin fun _ -> 
  OUnit.assert_equal parse_data_one  data_one
  end ;
  __LOC__ >:: begin fun _ -> 
  
  OUnit.assert_equal parse_data_two data_two
  end  *)
  ]




end
module Bsb_regex : sig 
#1 "bsb_regex.mli"
(* Copyright (C) 2017 Hongbo Zhang, Authors of ReScript
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


(** Used in `bsb -init` command *)
val global_substitute:
  string -> 
  reg:string ->
  (string -> string list -> string) -> 
  string
end = struct
#1 "bsb_regex.ml"
(* Copyright (C) 2017 Hongbo Zhang, Authors of ReScript
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

let string_after s n = String.sub s n (String.length s - n)



(* There seems to be a bug in {!Str.global_substitute} 
   {[
     Str.global_substitute (Str.regexp "\\${rescript:\\([-a-zA-Z0-9]+\\)}") (fun x -> (x^":found")) {|   ${rescript:hello-world}  ${rescript:x} ${x}|}  ;;
     - : bytes =
     "      ${rescript:hello-world}  ${rescript:x} ${x}:found     ${rescript:hello-world}  ${rescript:x} ${x}:found ${x}"
   ]}
*)
let global_substitute text ~reg:expr repl_fun =
  let text_len = String.length text in 
  let expr = Str.regexp expr in  
  let rec replace accu start last_was_empty =
    let startpos = if last_was_empty then start + 1 else start in
    if startpos > text_len then
      string_after text start :: accu
    else
      match Str.search_forward expr text startpos with
      | exception Not_found -> 
        string_after text start :: accu
      |  pos ->
        let end_pos = Str.match_end() in
        let matched = (Str.matched_string text) in 
        let  groups = 
          let rec aux n  acc = 
            match Str.matched_group n text with 
            | exception (Not_found | Invalid_argument _ ) 
              -> acc 
            | v -> aux (succ n) (v::acc) in 
          aux 1 []  in 
        let repl_text = repl_fun matched groups  in
        replace (repl_text :: String.sub text start (pos-start) :: accu)
          end_pos (end_pos = pos)
  in
  String.concat "" (List.rev (replace [] 0 false))

end
module Ounit_bsb_regex_tests
= struct
#1 "ounit_bsb_regex_tests.ml"


let ((>::),
     (>:::)) = OUnit.((>::),(>:::))

let (=~) = OUnit.assert_equal


let test_eq x y  = 
    Bsb_regex.global_substitute ~reg:"\\${rescript:\\([-a-zA-Z0-9]+\\)}" x
        (fun _ groups -> 
            match groups with 
            | x::_ -> x 
            | _ -> assert false 
        )  =~ y 


let suites = 
    __FILE__ 
    >:::
    [
        __LOC__ >:: begin fun _ -> 
        test_eq 
        {| hi hi hi ${rescript:name}
        ${rescript:x}
        ${rescript:u}
        |}        
        {| hi hi hi name
        x
        u
        |}
    end;
    __LOC__ >:: begin  fun _ ->
    test_eq  "xx" "xx";
    test_eq "${rescript:x}" "x";
    test_eq "a${rescript:x}" "ax";
    
    end;

    __LOC__ >:: begin fun _ ->
        test_eq "${rescript:x}x" "xx"
    end;

    __LOC__ >:: begin fun _ -> 
        test_eq {|
{
  "name": "${rescript:name}",
  "version": "${rescript:proj-version}",
  "sources": [
    "src"
  ],
  "reason" : { "react-jsx" : true},
  "bs-dependencies" : [
      // add your bs-dependencies here 
  ]
}
|} {|
{
  "name": "name",
  "version": "proj-version",
  "sources": [
    "src"
  ],
  "reason" : { "react-jsx" : true},
  "bs-dependencies" : [
      // add your bs-dependencies here 
  ]
}
|}
    end

    ;
    __LOC__ >:: begin fun _ -> 
    test_eq {|
{
  "name": "${rescript:name}",
  "version": "${rescript:proj-version}",
  "scripts": {
    "clean": "bsb -clean",
    "clean:all": "bsb -clean-world",
    "build": "bsb",
    "build:all": "bsb -make-world",
    "watch": "bsb -w",
  },
  "keywords": [
    "Bucklescript"
  ],
  "license": "MIT",
  "devDependencies": {
    "bs-platform": "${rescript:bs-version}"
  }
}
|} {|
{
  "name": "name",
  "version": "proj-version",
  "scripts": {
    "clean": "bsb -clean",
    "clean:all": "bsb -clean-world",
    "build": "bsb",
    "build:all": "bsb -make-world",
    "watch": "bsb -w",
  },
  "keywords": [
    "Bucklescript"
  ],
  "license": "MIT",
  "devDependencies": {
    "bs-platform": "bs-version"
  }
}
|}
    end;
    __LOC__ >:: begin fun _ -> 
    test_eq {|
{
    "version": "0.1.0",
    "command": "${rescript:bsb}",
    "options": {
        "cwd": "${workspaceRoot}"
    },
    "isShellCommand": true,
    "args": [
        "-w"
    ],
    "showOutput": "always",
    "isWatching": true,
    "problemMatcher": {
        "fileLocation": "absolute",
        "owner": "ocaml",
        "watching": {
            "activeOnStart": true,
            "beginsPattern": ">>>> Start compiling",
            "endsPattern": ">>>> Finish compiling"
        },
        "pattern": [
            {
                "regexp": "^File \"(.*)\", line (\\d+)(?:, characters (\\d+)-(\\d+))?:$",
                "file": 1,
                "line": 2,
                "column": 3,
                "endColumn": 4
            },
            {
                "regexp": "^(?:(?:Parse\\s+)?(Warning|[Ee]rror)(?:\\s+\\d+)?:)?\\s+(.*)$",
                "severity": 1,
                "message": 2,
                "loop": true
            }
        ]
    }
}
|} {|
{
    "version": "0.1.0",
    "command": "bsb",
    "options": {
        "cwd": "${workspaceRoot}"
    },
    "isShellCommand": true,
    "args": [
        "-w"
    ],
    "showOutput": "always",
    "isWatching": true,
    "problemMatcher": {
        "fileLocation": "absolute",
        "owner": "ocaml",
        "watching": {
            "activeOnStart": true,
            "beginsPattern": ">>>> Start compiling",
            "endsPattern": ">>>> Finish compiling"
        },
        "pattern": [
            {
                "regexp": "^File \"(.*)\", line (\\d+)(?:, characters (\\d+)-(\\d+))?:$",
                "file": 1,
                "line": 2,
                "column": 3,
                "endColumn": 4
            },
            {
                "regexp": "^(?:(?:Parse\\s+)?(Warning|[Ee]rror)(?:\\s+\\d+)?:)?\\s+(.*)$",
                "severity": 1,
                "message": 2,
                "loop": true
            }
        ]
    }
}
|}
    end
    ]
end
module Ounit_cmd_util : sig 
#1 "ounit_cmd_util.mli"
type output = {
  stderr : string ; 
  stdout : string ;
  exit_code : int 
}


val perform : string -> string array -> output 


val perform_bsc : string array -> output 


val bsc_check_eval : string -> output  

val debug_output : output -> unit 
end = struct
#1 "ounit_cmd_util.ml"
let (//) = Filename.concat

(** may nonterminate when [cwd] is '.' *)
let rec unsafe_root_dir_aux cwd  = 
  if Sys.file_exists (cwd//Literals.bsconfig_json) then cwd 
  else unsafe_root_dir_aux (Filename.dirname cwd)     

let project_root = unsafe_root_dir_aux (Sys.getcwd ())
let jscomp = project_root // "jscomp"


let bsc_exe = project_root // "bsc"
let runtime_dir = jscomp // "runtime"
let others_dir = jscomp // "others"


let stdlib_dir = jscomp // "stdlib-406"

(* let rec safe_dup fd =
  let new_fd = Unix.dup fd in
  if (Obj.magic new_fd : int) >= 3 then
    new_fd (* [dup] can not be 0, 1, 2*)
  else begin
    let res = safe_dup fd in
    Unix.close new_fd;
    res
  end *)

let safe_close fd =
  try Unix.close fd with Unix.Unix_error(_,_,_) -> ()


type output = {
  stderr : string ; 
  stdout : string ;
  exit_code : int 
}

let perform command args = 
  let new_fd_in, new_fd_out = Unix.pipe () in 
  let err_fd_in, err_fd_out = Unix.pipe () in 
  match Unix.fork () with 
  | 0 -> 
    begin try 
        safe_close new_fd_in;  
        safe_close err_fd_in;
        Unix.dup2 err_fd_out Unix.stderr ; 
        Unix.dup2 new_fd_out Unix.stdout; 
        Unix.execv command args 
      with _ -> 
        exit 127
    end
  | pid ->
    (* when all the descriptors on a pipe's input are closed and the pipe is 
        empty, a call to [read] on its output returns zero: end of file.
       when all the descriptiors on a pipe's output are closed, a call to 
       [write] on its input kills the writing process (EPIPE).
    *)
    safe_close new_fd_out ; 
    safe_close err_fd_out ; 
    let in_chan = Unix.in_channel_of_descr new_fd_in in 
    let err_in_chan = Unix.in_channel_of_descr err_fd_in in 
    let buf = Buffer.create 1024 in 
    let err_buf = Buffer.create 1024 in 
    (try 
       while true do 
         Buffer.add_string buf (input_line in_chan );             
         Buffer.add_char buf '\n'
       done;
     with
       End_of_file -> ()) ; 
    (try 
       while true do 
         Buffer.add_string err_buf (input_line err_in_chan );
         Buffer.add_char err_buf '\n'
       done;
     with
       End_of_file -> ()) ; 
    let exit_code = match snd @@ Unix.waitpid [] pid with 
      | Unix.WEXITED exit_code -> exit_code 
      | Unix.WSIGNALED _signal_number 
      | Unix.WSTOPPED _signal_number  -> 127 in 
    {
      stdout = Buffer.contents buf ; 
      stderr = Buffer.contents err_buf;
      exit_code 
    }


let perform_bsc args = 
  perform bsc_exe 
    (Array.append 
       [|bsc_exe ; 
         "-bs-package-name" ; "bs-platform"; 
         "-bs-no-version-header"; 
         "-bs-cross-module-opt";
         "-w";
         "-40";
         "-I" ;
         runtime_dir ; 
         "-I"; 
         others_dir ; 
         "-I" ; 
         stdlib_dir
       |] args)

let bsc_check_eval str = 
  perform_bsc [|"-bs-eval"; str|]        

  let debug_output o = 
  Printf.printf "\nexit_code:%d\nstdout:%s\nstderr:%s\n"
    o.exit_code o.stdout o.stderr

end
module Ounit_cmd_tests
= struct
#1 "ounit_cmd_tests.ml"
let (//) = Filename.concat




let ((>::),
     (>:::)) = OUnit.((>::),(>:::))

let (=~) = OUnit.assert_equal





(* let output_of_exec_command command args =
    let readme, writeme = Unix.pipe () in
    let pid = Unix.create_process command args Unix.stdin writeme Unix.stderr in
    let in_chan = Unix.in_channel_of_descr readme *)



let perform_bsc = Ounit_cmd_util.perform_bsc
let bsc_check_eval = Ounit_cmd_util.bsc_check_eval

let ok b output = 
  if not b then 
    Ounit_cmd_util.debug_output output;
  OUnit.assert_bool __LOC__ b  

let suites =
  __FILE__
  >::: [
    __LOC__ >:: begin fun _ ->
      let v_output = perform_bsc  [| "-v" |] in
      OUnit.assert_bool __LOC__ ((perform_bsc [| "-h" |]).exit_code  = 0  );
      OUnit.assert_bool __LOC__ (v_output.exit_code = 0);
      (* Printf.printf "\n*>%s" v_output.stdout; *)
      (* Printf.printf "\n*>%s" v_output.stderr ; *)
    end;
    __LOC__ >:: begin fun _ ->
      let v_output =
        perform_bsc  [| "-bs-eval"; {|let str = "'a'" |}|] in
      ok (v_output.exit_code = 0) v_output
    end;
    __LOC__ >:: begin fun _ -> 
      let v_output = perform_bsc [|"-bs-eval"; {|type 'a arra = 'a array
    external
      f : 
      int -> int -> int arra -> unit
      = ""
      [@@bs.send.pipe:int]
      [@@bs.splice]|}|] in  
      OUnit.assert_bool __LOC__ (Ext_string.contain_substring v_output.stderr "variadic")
    end;
    __LOC__ >:: begin fun _ -> 
      let v_output = perform_bsc [|"-bs-eval"; {|external
  f2 : 
  int -> int -> ?y:int array -> unit  
  = ""
  [@@bs.send.pipe:int]
  [@@bs.splice]  |}|] in  
      OUnit.assert_bool __LOC__ (Ext_string.contain_substring v_output.stderr "variadic")
    end;

    __LOC__ >:: begin fun _ ->
      let should_be_warning =
        bsc_check_eval  {|let bla4 foo x y= foo##(method1 x y [@bs]) |} in
      (* debug_output should_be_warning; *)
      OUnit.assert_bool __LOC__ (Ext_string.contain_substring
                                   should_be_warning.stderr "Unused")
    end;
    __LOC__ >:: begin fun _ ->
      let should_be_warning =
        bsc_check_eval  {| external mk : int -> ([`a|`b [@bs.string]]) = "mk" [@@bs.val] |} in
      OUnit.assert_bool __LOC__
        (Ext_string.contain_substring
           should_be_warning.stderr "Unused")
    end;
    __LOC__ >:: begin fun _ ->
      let should_err = bsc_check_eval {|
external ff :
    resp -> (_ [@bs.as "x"]) -> int -> unit =
    "x" [@@bs.set]
      |} in
      OUnit.assert_bool __LOC__
        (Ext_string.contain_substring should_err.stderr
           "Ill defined"
        )
    end;

    __LOC__ >:: begin fun _ ->
      (* used in return value
          This should fail, we did not
          support uncurry return value yet
      *)
      let should_err = bsc_check_eval {|
    external v3 :
    int -> int -> (int -> int -> int [@bs.uncurry])
    = "v3"[@@bs.val]

    |} in
      (* Ounit_cmd_util.debug_output should_err;*)
      OUnit.assert_bool __LOC__
        (Ext_string.contain_substring
           should_err.stderr "bs.uncurry")
    end ;

    __LOC__ >:: begin fun _ ->
      let should_err = bsc_check_eval {|
    external v4 :
    (int -> int -> int [@bs.uncurry]) = ""
    [@@bs.val]

    |} in
      (* Ounit_cmd_util.debug_output should_err ; *)
      OUnit.assert_bool __LOC__
        (Ext_string.contain_substring
           should_err.stderr "uncurry")
    end ;

    __LOC__ >:: begin fun _ ->
      let should_err = bsc_check_eval {|
      {js| \uFFF|js}
      |} in
      OUnit.assert_bool __LOC__ (not @@ Ext_string.is_empty should_err.stderr)
    end;

    __LOC__ >:: begin fun _ ->
      let should_err = bsc_check_eval {|
      external mk : int -> ([`a|`b] [@bs.string]) = "" [@@bs.val]
      |} in
      OUnit.assert_bool __LOC__ (not @@ Ext_string.is_empty should_err.stderr)
    end;

    __LOC__ >:: begin fun _ ->
      let should_err = bsc_check_eval {|
      external mk : int -> ([`a|`b] ) = "mk" [@@bs.val]
      |} in
      OUnit.assert_bool __LOC__ ( Ext_string.is_empty should_err.stderr)
      (* give a warning or ?
         ( [`a | `b ] [@bs.string] )
         (* auto-convert to ocaml poly-variant *)
      *)
    end;

    __LOC__ >:: begin fun _ ->
      let should_err = bsc_check_eval {|
      type t
      external mk : int -> (_ [@bs.as {json| { x : 3 } |json}]) ->  t = "mk" [@@bs.val]
      |} in
      OUnit.assert_bool __LOC__ (Ext_string.is_empty should_err.stderr)
    end
    ;
    __LOC__ >:: begin fun _ ->
      let should_err = bsc_check_eval {|
      type t
      external mk : int -> (_ [@bs.as {json| { "x" : 3 } |json}]) ->  t = "mk" [@@bs.val]
      |} in
      OUnit.assert_bool __LOC__ (Ext_string.is_empty should_err.stderr)
    end
    ;
    (* #1510 *)
    __LOC__ >:: begin fun _ ->
      let should_err = bsc_check_eval {|
       let should_fail = fun [@bs.this] (Some x) y u -> y + u
      |} in
      OUnit.assert_bool __LOC__
        (Ext_string.contain_substring  should_err.stderr "simple")
    end;

    __LOC__ >:: begin fun _ ->
      let should_err = bsc_check_eval {|
       let should_fail = fun [@bs.this] (Some x as v) y u -> y + u
      |} in
      (* Ounit_cmd_util.debug_output should_err; *)
      OUnit.assert_bool __LOC__
        (Ext_string.contain_substring  should_err.stderr "simple")
    end;

    (* __LOC__ >:: begin fun _ ->
       let should_err = bsc_check_eval {|
       external f : string -> unit -> unit = "x.y" [@@bs.send]
       |} in
       OUnit.assert_bool __LOC__
        (Ext_string.contain_substring should_err.stderr "Not a valid method name")
       end; *)


    __LOC__ >:: begin fun _ -> 
      let should_err = bsc_check_eval {|
      (* let rec must be rejected *)
type t10 = A of t10 [@@ocaml.unboxed];;
let rec x = A x;;
      |} in 
      OUnit.assert_bool __LOC__
        (Ext_string.contain_substring should_err.stderr "This kind of expression is not allowed")
    end;

    __LOC__ >:: begin fun _ -> 
      let should_err = bsc_check_eval {|
      type t = {x: int64} [@@unboxed];;
let rec x = {x = y} and y = 3L;;
      |} in 
      OUnit.assert_bool __LOC__
        (Ext_string.contain_substring should_err.stderr "This kind of expression is not allowed")
    end;
    __LOC__ >:: begin fun _ -> 
      let should_err = bsc_check_eval {|
      type r = A of r [@@unboxed];;
let rec y = A y;;
      |} in 
      OUnit.assert_bool __LOC__
        (Ext_string.contain_substring should_err.stderr "This kind of expression is not allowed")
    end;

    __LOC__ >:: begin fun _ ->
      let should_err = bsc_check_eval {|
          external f : int = "%identity"
|} in
      OUnit.assert_bool __LOC__
        (not (Ext_string.is_empty should_err.stderr))
    end;

    __LOC__ >:: begin fun _ ->
      let should_err = bsc_check_eval {|
          external f : int -> int = "%identity"
|} in
      OUnit.assert_bool __LOC__
        (Ext_string.is_empty should_err.stderr)
    end;
    __LOC__ >:: begin fun _ ->
      let should_err = bsc_check_eval {|
          external f : int -> int -> int = "%identity"
|} in
      OUnit.assert_bool __LOC__
        (not (Ext_string.is_empty should_err.stderr))
    end;
    __LOC__ >:: begin fun _ ->
      let should_err = bsc_check_eval {|
          external f : (int -> int) -> int = "%identity"
|} in
      OUnit.assert_bool __LOC__
        ( (Ext_string.is_empty should_err.stderr))

    end;

    __LOC__ >:: begin fun _ ->
      let should_err = bsc_check_eval {|
          external f : int -> (int-> int) = "%identity"
|} in
      OUnit.assert_bool __LOC__
        (not (Ext_string.is_empty should_err.stderr))

    end;
    __LOC__ >:: begin fun _ ->
      let should_err = bsc_check_eval {|
    external foo_bar :
    (_ [@bs.as "foo"]) ->
    string ->
    string = "bar"
  [@@bs.send]
    |} in
      OUnit.assert_bool __LOC__
        (Ext_string.contain_substring should_err.stderr "Ill defined attribute")
    end;
    __LOC__ >:: begin fun _ ->
      let should_err = bsc_check_eval {|
      let bla4 foo x y = foo##(method1 x y [@bs])
    |} in
      (* Ounit_cmd_util.debug_output should_err ;  *)
      OUnit.assert_bool __LOC__
        (Ext_string.contain_substring should_err.stderr
           "Unused")
    end;
    __LOC__ >:: begin fun _ ->
      let should_err = bsc_check_eval {|
    external mk : int ->
  (
    [`a|`b]
     [@bs.string]
  ) = "mk" [@@bs.val]
    |} in
      (* Ounit_cmd_util.debug_output should_err ;  *)
      OUnit.assert_bool __LOC__
        (Ext_string.contain_substring should_err.stderr
           "Unused")
    end;
    __LOC__ >:: begin fun _ ->
      let should_err = bsc_check_eval {|
    type -'a t = {k : 'a } [@@bs.deriving abstract]
    |} in
      OUnit.assert_bool __LOC__
        (Ext_string.contain_substring should_err.stderr "contravariant")
    end;
    __LOC__ >:: begin fun _ ->
      let should_err = bsc_check_eval {|
    let u = [||]
    |} in
      OUnit.assert_bool __LOC__
        (Ext_string.contain_substring should_err.stderr "cannot be generalized")
    end;
    __LOC__ >:: begin fun _ -> 
      let should_err = bsc_check_eval {|  
external push : 'a array -> 'a -> unit = "push" [@@send]
let a = [||]
let () = 
  push a 3 |. ignore ; 
  push a "3" |. ignore  
  |} in
      OUnit.assert_bool __LOC__
        (Ext_string.contain_substring should_err.stderr "has type string")
    end
    (* __LOC__ >:: begin fun _ ->  *)
    (*   let should_infer = perform_bsc [| "-i"; "-bs-eval"|] {| *)
         (*      let  f = fun [@bs] x -> let (a,b) = x in a + b  *)
         (* |}  in  *)
    (*   let infer_type  = bsc_eval (Printf.sprintf {| *)

         (*      let f : %s  = fun [@bs] x -> let (a,b) = x in a + b  *)
         (*  |} should_infer.stdout ) in  *)
    (*  begin  *)
    (*    Ounit_cmd_util.debug_output should_infer ; *)
    (*    Ounit_cmd_util.debug_output infer_type ; *)
    (*    OUnit.assert_bool __LOC__  *)
    (*      ((Ext_string.is_empty infer_type.stderr)) *)
    (*  end *)
    (* end *)
  ]


end
module Ext_ref : sig 
#1 "ext_ref.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

(** [non_exn_protect ref value f] assusme [f()] 
    would not raise
*)

val non_exn_protect : 'a ref -> 'a -> (unit -> 'b) -> 'b
val protect : 'a ref -> 'a -> (unit -> 'b) -> 'b

val protect2 : 'a ref -> 'b ref -> 'a -> 'b -> (unit -> 'c) -> 'c

(** [non_exn_protect2 refa refb va vb f ]
    assume [f ()] would not raise
*)
val non_exn_protect2 : 'a ref -> 'b ref -> 'a -> 'b -> (unit -> 'c) -> 'c

val protect_list : ('a ref * 'a) list -> (unit -> 'b) -> 'b

end = struct
#1 "ext_ref.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

let non_exn_protect r v body = 
  let old = !r in
  r := v;
  let res = body() in
  r := old;
  res

let protect r v body =
  let old = !r in
  try
    r := v;
    let res = body() in
    r := old;
    res
  with x ->
    r := old;
    raise x

let non_exn_protect2 r1 r2 v1 v2 body = 
  let old1 = !r1 in
  let old2 = !r2 in  
  r1 := v1;
  r2 := v2;
  let res = body() in
  r1 := old1;
  r2 := old2;
  res

let protect2 r1 r2 v1 v2 body =
  let old1 = !r1 in
  let old2 = !r2 in  
  try
    r1 := v1;
    r2 := v2;
    let res = body() in
    r1 := old1;
    r2 := old2;
    res
  with x ->
    r1 := old1;
    r2 := old2;
    raise x

let protect_list rvs body = 
  let olds =  Ext_list.map  rvs (fun (x,_) -> !x) in 
  let () = List.iter (fun (x,y) -> x:=y) rvs in 
  try 
    let res = body () in 
    List.iter2 (fun (x,_) old -> x := old) rvs olds;
    res 
  with e -> 
    List.iter2 (fun (x,_) old -> x := old) rvs olds;
    raise e 

end
module Ml_binary : sig 
#1 "ml_binary.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)



(* This file was used to read reason ast
   and part of parsing binary ast
*)
type _ kind = 
  | Ml : Parsetree.structure kind 
  | Mli : Parsetree.signature kind


val read_ast : 'a kind -> in_channel -> 'a 

val write_ast :
  'a kind -> string -> 'a -> out_channel -> unit

val magic_of_kind : 'a kind -> string   


end = struct
#1 "ml_binary.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


type _ kind = 
  | Ml : Parsetree.structure kind 
  | Mli : Parsetree.signature kind

(** [read_ast kind ic] assume [ic] channel is 
    in the right position *)
let read_ast (type t ) (kind : t  kind) ic : t  =
  let magic =
    match kind with 
    | Ml -> Config.ast_impl_magic_number
    | Mli -> Config.ast_intf_magic_number in 
  let buffer = really_input_string ic (String.length magic) in
  assert(buffer = magic); (* already checked by apply_rewriter *)
  Location.set_input_name (input_value ic);
  input_value ic 

let write_ast (type t) (kind : t kind) 
    (fname : string)
    (pt : t) oc = 
  let magic = 
    match kind with 
    | Ml -> Config.ast_impl_magic_number
    | Mli -> Config.ast_intf_magic_number in
  output_string oc magic ;
  output_value oc fname;
  output_value oc pt

let magic_of_kind : type a . a kind -> string = function
  | Ml -> Config.ast_impl_magic_number
  | Mli -> Config.ast_intf_magic_number



end
module Ast_extract : sig 
#1 "ast_extract.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)









module Set_string = Depend.StringSet

val read_parse_and_extract : 'a Ml_binary.kind -> 'a -> Set_string.t


end = struct
#1 "ast_extract.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

(* type module_name = private string *)

module Set_string = Depend.StringSet

(* FIXME: [Clflags.open_modules] seems not to be properly used *)
module SMap = Depend.StringMap
let bound_vars = SMap.empty 


type 'a kind = 'a Ml_binary.kind 


let read_parse_and_extract (type t) (k : t kind) (ast : t) : Set_string.t =
  Depend.free_structure_names := Set_string.empty;
  Ext_ref.protect Clflags.transparent_modules false begin fun _ -> 
    List.iter (* check *)
      (fun modname  ->
         ignore @@ 
         Depend.open_module bound_vars (Longident.Lident modname))
      (!Clflags.open_modules);
    (match k with
     | Ml_binary.Ml  -> Depend.add_implementation bound_vars ast
     | Ml_binary.Mli  -> Depend.add_signature bound_vars ast  ); 
    !Depend.free_structure_names
  end






end
module Ounit_depends_format_test
= struct
#1 "ounit_depends_format_test.ml"
let ((>::),
     (>:::)) = OUnit.((>::),(>:::))

let (=~) (xs : string list) (ys : string list) = 
     OUnit.assert_equal xs ys 
     ~printer:(fun xs -> String.concat "," xs )

let f (x : string) = 
     let stru = Parse.implementation (Lexing.from_string x)  in 
     Ast_extract.Set_string.elements (Ast_extract.read_parse_and_extract Ml_binary.Ml stru)


let suites = 
  __FILE__
  >::: [
    __LOC__ >:: begin fun _ -> 
      f {|module X = List|} =~ ["List"];
      f {|module X = List module X0 = List1|} =~ ["List";"List1"]
    end 
  ]
end
module Ounit_ffi_error_debug_test
= struct
#1 "ounit_ffi_error_debug_test.ml"
let (//) = Filename.concat




let ((>::),
     (>:::)) = OUnit.((>::),(>:::))

let (=~) = OUnit.assert_equal




let bsc_eval = Ounit_cmd_util.bsc_check_eval

let debug_output = Ounit_cmd_util.debug_output


let suites = 
    __FILE__ 
    >::: [
        __LOC__ >:: begin fun _ -> 
        let output = bsc_eval {|
external err : 
   hi_should_error:([`a of int | `b of string ] [@bs.string]) ->         
   unit -> _ = "" [@@bs.obj]
        |} in
        OUnit.assert_bool __LOC__
            (Ext_string.contain_substring output.stderr "hi_should_error")
        end;
        __LOC__ >:: begin fun _ -> 
let output = bsc_eval {|
    external err : 
   ?hi_should_error:([`a of int | `b of string ] [@bs.string]) ->         
   unit -> _ = "" [@@bs.obj]
        |} in
        OUnit.assert_bool __LOC__
            (Ext_string.contain_substring output.stderr "hi_should_error")        
        end;
        __LOC__ >:: begin fun _ -> 
        let output = bsc_eval {|
    external err : 
   ?hi_should_error:([`a of int | `b of string ] [@bs.string]) ->         
   unit -> unit = "err" [@@bs.val]
        |} in
        OUnit.assert_bool __LOC__
            (Ext_string.contain_substring output.stderr "hi_should_error")        
        end;

        __LOC__ >:: begin fun _ ->
          (*
             Each [@bs.unwrap] variant constructor requires an argument
          *)
          let output =
            bsc_eval {|
              external err :
              ?hi_should_error:([`a of int | `b] [@bs.unwrap]) -> unit -> unit = "err" [@@bs.val]
            |}
          in
          OUnit.assert_bool __LOC__
            (Ext_string.contain_substring output.stderr "unwrap")
        end;

        __LOC__ >:: begin fun _ ->
          (*
             [@bs.unwrap] args are not supported in [@@bs.obj] functions
          *)
          let output =
            bsc_eval {|
              external err :
              ?hi_should_error:([`a of int] [@bs.unwrap]) -> unit -> _ = "" [@@bs.obj]
            |}
          in
          OUnit.assert_bool __LOC__
            (Ext_string.contain_substring output.stderr "hi_should_error")
        end

    ]

end
module Hash_set_gen
= struct
#1 "hash_set_gen.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


(* We do dynamic hashing, and resize the table and rehash the elements
   when buckets become too long. *)

type 'a bucket = 
  | Empty
  | Cons of {
      mutable key : 'a ; 
      mutable next : 'a bucket 
    }

type 'a t =
  { mutable size: int;                        (* number of entries *)
    mutable data: 'a bucket array;  (* the buckets *)
    initial_size: int;                        (* initial array size *)
  }




let create  initial_size =
  let s = Ext_util.power_2_above 16 initial_size in
  { initial_size = s; size = 0; data = Array.make s Empty }

let clear h =
  h.size <- 0;
  let len = Array.length h.data in
  for i = 0 to len - 1 do
    Array.unsafe_set h.data i  Empty
  done

let reset h =
  h.size <- 0;
  h.data <- Array.make h.initial_size Empty

let length h = h.size

let resize indexfun h =
  let odata = h.data in
  let osize = Array.length odata in
  let nsize = osize * 2 in
  if nsize < Sys.max_array_length then begin
    let ndata = Array.make nsize Empty in
    let ndata_tail = Array.make nsize Empty in 
    h.data <- ndata;          (* so that indexfun sees the new bucket count *)
    let rec insert_bucket = function
        Empty -> ()
      | Cons {key; next} as cell ->
        let nidx = indexfun h key in
        begin match Array.unsafe_get ndata_tail nidx with 
          | Empty ->
            Array.unsafe_set ndata nidx cell
          | Cons tail -> 
            tail.next <- cell
        end;
        Array.unsafe_set ndata_tail nidx  cell;          
        insert_bucket next
    in
    for i = 0 to osize - 1 do
      insert_bucket (Array.unsafe_get odata i)
    done;
    for i = 0 to nsize - 1 do 
      match Array.unsafe_get ndata_tail i with 
      | Empty -> ()
      | Cons tail -> tail.next <- Empty
    done 
  end

let iter h f =
  let rec do_bucket = function
    | Empty ->
      ()
    | Cons l  ->
      f l.key  ; do_bucket l.next in
  let d = h.data in
  for i = 0 to Array.length d - 1 do
    do_bucket (Array.unsafe_get d i)
  done

let fold h init f =
  let rec do_bucket b accu =
    match b with
      Empty ->
      accu
    | Cons l  ->
      do_bucket l.next (f l.key  accu) in
  let d = h.data in
  let accu = ref init in
  for i = 0 to Array.length d - 1 do
    accu := do_bucket (Array.unsafe_get d i) !accu
  done;
  !accu


let to_list set = 
  fold set [] List.cons




let rec small_bucket_mem eq key lst =
  match lst with 
  | Empty -> false 
  | Cons lst -> 
    eq key lst.key ||
    match lst.next with 
    | Empty -> false 
    | Cons lst  -> 
      eq key   lst.key ||
      match lst.next with 
      | Empty -> false 
      | Cons lst  -> 
        eq key lst.key ||
        small_bucket_mem eq key lst.next 

let rec remove_bucket 
    (h : _ t) (i : int)
    key 
    ~(prec : _ bucket) 
    (buck : _ bucket) 
    eq_key = 
  match buck with   
  | Empty ->
    ()
  | Cons {key=k; next } ->
    if eq_key k key 
    then begin
      h.size <- h.size - 1;
      match prec with
      | Empty -> Array.unsafe_set h.data i  next
      | Cons c -> c.next <- next
    end
    else remove_bucket h i key ~prec:buck next eq_key


module type S =
sig
  type key
  type t
  val create: int ->  t
  val clear : t -> unit
  val reset : t -> unit
  (* val copy: t -> t *)
  val remove:  t -> key -> unit
  val add :  t -> key -> unit
  val of_array : key array -> t 
  val check_add : t -> key -> bool
  val mem : t -> key -> bool
  val iter: t -> (key -> unit) -> unit
  val fold: t -> 'b  -> (key -> 'b -> 'b) -> 'b
  val length:  t -> int
  (* val stats:  t -> Hashtbl.statistics *)
  val to_list : t -> key list 
end



end
module Hash_set : sig 
#1 "hash_set.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

(** Ideas are based on {!Hash}, 
    however, {!Hash.add} does not really optimize and has a bad semantics for {!Hash_set}, 
    This module fixes the semantics of [add].
    [remove] is not optimized since it is not used too much 
*)





module Make ( H : Hashtbl.HashedType) : (Hash_set_gen.S with type key = H.t)
(** A naive t implementation on top of [hashtbl], the value is [unit]*)


end = struct
#1 "hash_set.ml"
# 1 "ext/hash_set.cppo.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)
[@@@warning "-32"] (* FIXME *)
# 44 "ext/hash_set.cppo.ml"
module Make (H: Hashtbl.HashedType) : (Hash_set_gen.S with type key = H.t) = struct 
  type key = H.t 
  let eq_key = H.equal
  let key_index (h :  _ Hash_set_gen.t ) key =
    (H.hash  key) land (Array.length h.data - 1)
  type t = key Hash_set_gen.t



      
# 65 "ext/hash_set.cppo.ml"
      let create = Hash_set_gen.create
  let clear = Hash_set_gen.clear
  let reset = Hash_set_gen.reset
  (* let copy = Hash_set_gen.copy *)
  let iter = Hash_set_gen.iter
  let fold = Hash_set_gen.fold
  let length = Hash_set_gen.length
  (* let stats = Hash_set_gen.stats *)
  let to_list = Hash_set_gen.to_list



  let remove (h : _ Hash_set_gen.t ) key =
    let i = key_index h key in
    let h_data = h.data in 
    Hash_set_gen.remove_bucket h i key ~prec:Empty (Array.unsafe_get h_data i) eq_key    



  let add (h : _ Hash_set_gen.t) key =
    let i = key_index h key  in 
    let h_data = h.data in 
    let old_bucket = (Array.unsafe_get h_data i) in
    if not (Hash_set_gen.small_bucket_mem eq_key key old_bucket) then 
      begin 
        Array.unsafe_set h_data i (Cons {key = key ; next =  old_bucket});
        h.size <- h.size + 1 ;
        if h.size > Array.length h_data lsl 1 then Hash_set_gen.resize key_index h
      end

  let of_array arr = 
    let len = Array.length arr in 
    let tbl = create len in 
    for i = 0 to len - 1  do
      add tbl (Array.unsafe_get arr i);
    done ;
    tbl 


  let check_add (h : _ Hash_set_gen.t) key : bool =
    let i = key_index h key  in 
    let h_data = h.data in  
    let old_bucket = (Array.unsafe_get h_data i) in
    if not (Hash_set_gen.small_bucket_mem eq_key key old_bucket) then 
      begin 
        Array.unsafe_set h_data i  (Cons { key = key ; next =  old_bucket});
        h.size <- h.size + 1 ;
        if h.size > Array.length h_data lsl 1 then Hash_set_gen.resize key_index h;
        true 
      end
    else false 


  let mem (h :  _ Hash_set_gen.t) key =
    Hash_set_gen.small_bucket_mem eq_key key (Array.unsafe_get h.data (key_index h key)) 

# 122 "ext/hash_set.cppo.ml"
end


end
module Hash_set_poly : sig 
#1 "hash_set_poly.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


type   'a t 

val create : int -> 'a t

val clear : 'a t -> unit

val reset : 'a t -> unit

(* val copy : 'a t -> 'a t *)

val add : 'a t -> 'a  -> unit
val remove : 'a t -> 'a -> unit

val mem : 'a t -> 'a -> bool

val iter : 'a t -> ('a -> unit) -> unit

val to_list : 'a t -> 'a list

val length : 'a t -> int 

(* val stats:  'a t -> Hashtbl.statistics *)

end = struct
#1 "hash_set_poly.ml"
# 1 "ext/hash_set.cppo.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)
[@@@warning "-32"] (* FIXME *)
  
# 52 "ext/hash_set.cppo.ml"
  [@@@ocaml.warning "-3"]
  (* we used cppo the mixture does not work*)
  external seeded_hash_param :
    int -> int -> int -> 'a -> int = "caml_hash" "noalloc"
  let key_index (h :  _ Hash_set_gen.t ) (key : 'a) =
    seeded_hash_param 10 100 0 key land (Array.length h.data - 1)
  let eq_key = (=)
  type  'a t = 'a Hash_set_gen.t 


      
# 65 "ext/hash_set.cppo.ml"
      let create = Hash_set_gen.create
  let clear = Hash_set_gen.clear
  let reset = Hash_set_gen.reset
  (* let copy = Hash_set_gen.copy *)
  let iter = Hash_set_gen.iter
  let fold = Hash_set_gen.fold
  let length = Hash_set_gen.length
  (* let stats = Hash_set_gen.stats *)
  let to_list = Hash_set_gen.to_list



  let remove (h : _ Hash_set_gen.t ) key =
    let i = key_index h key in
    let h_data = h.data in 
    Hash_set_gen.remove_bucket h i key ~prec:Empty (Array.unsafe_get h_data i) eq_key    



  let add (h : _ Hash_set_gen.t) key =
    let i = key_index h key  in 
    let h_data = h.data in 
    let old_bucket = (Array.unsafe_get h_data i) in
    if not (Hash_set_gen.small_bucket_mem eq_key key old_bucket) then 
      begin 
        Array.unsafe_set h_data i (Cons {key = key ; next =  old_bucket});
        h.size <- h.size + 1 ;
        if h.size > Array.length h_data lsl 1 then Hash_set_gen.resize key_index h
      end

  let of_array arr = 
    let len = Array.length arr in 
    let tbl = create len in 
    for i = 0 to len - 1  do
      add tbl (Array.unsafe_get arr i);
    done ;
    tbl 


  let check_add (h : _ Hash_set_gen.t) key : bool =
    let i = key_index h key  in 
    let h_data = h.data in  
    let old_bucket = (Array.unsafe_get h_data i) in
    if not (Hash_set_gen.small_bucket_mem eq_key key old_bucket) then 
      begin 
        Array.unsafe_set h_data i  (Cons { key = key ; next =  old_bucket});
        h.size <- h.size + 1 ;
        if h.size > Array.length h_data lsl 1 then Hash_set_gen.resize key_index h;
        true 
      end
    else false 


  let mem (h :  _ Hash_set_gen.t) key =
    Hash_set_gen.small_bucket_mem eq_key key (Array.unsafe_get h.data (key_index h key)) 



end
module Hash_set_string : sig 
#1 "hash_set_string.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


include Hash_set_gen.S with type key = string

end = struct
#1 "hash_set_string.ml"
# 1 "ext/hash_set.cppo.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)
[@@@warning "-32"] (* FIXME *)
# 32 "ext/hash_set.cppo.ml"
type key = string 
let key_index (h :  _ Hash_set_gen.t ) (key : key) =
  (Bs_hash_stubs.hash_string  key) land (Array.length h.data - 1)
let eq_key = Ext_string.equal 
type  t = key  Hash_set_gen.t 


      
# 65 "ext/hash_set.cppo.ml"
      let create = Hash_set_gen.create
  let clear = Hash_set_gen.clear
  let reset = Hash_set_gen.reset
  (* let copy = Hash_set_gen.copy *)
  let iter = Hash_set_gen.iter
  let fold = Hash_set_gen.fold
  let length = Hash_set_gen.length
  (* let stats = Hash_set_gen.stats *)
  let to_list = Hash_set_gen.to_list



  let remove (h : _ Hash_set_gen.t ) key =
    let i = key_index h key in
    let h_data = h.data in 
    Hash_set_gen.remove_bucket h i key ~prec:Empty (Array.unsafe_get h_data i) eq_key    



  let add (h : _ Hash_set_gen.t) key =
    let i = key_index h key  in 
    let h_data = h.data in 
    let old_bucket = (Array.unsafe_get h_data i) in
    if not (Hash_set_gen.small_bucket_mem eq_key key old_bucket) then 
      begin 
        Array.unsafe_set h_data i (Cons {key = key ; next =  old_bucket});
        h.size <- h.size + 1 ;
        if h.size > Array.length h_data lsl 1 then Hash_set_gen.resize key_index h
      end

  let of_array arr = 
    let len = Array.length arr in 
    let tbl = create len in 
    for i = 0 to len - 1  do
      add tbl (Array.unsafe_get arr i);
    done ;
    tbl 


  let check_add (h : _ Hash_set_gen.t) key : bool =
    let i = key_index h key  in 
    let h_data = h.data in  
    let old_bucket = (Array.unsafe_get h_data i) in
    if not (Hash_set_gen.small_bucket_mem eq_key key old_bucket) then 
      begin 
        Array.unsafe_set h_data i  (Cons { key = key ; next =  old_bucket});
        h.size <- h.size + 1 ;
        if h.size > Array.length h_data lsl 1 then Hash_set_gen.resize key_index h;
        true 
      end
    else false 


  let mem (h :  _ Hash_set_gen.t) key =
    Hash_set_gen.small_bucket_mem eq_key key (Array.unsafe_get h.data (key_index h key)) 



end
module Ounit_hash_set_tests
= struct
#1 "ounit_hash_set_tests.ml"
let ((>::),
     (>:::)) = OUnit.((>::),(>:::))

let (=~) = OUnit.assert_equal

type id = { name : string ; stamp : int }

module Id_hash_set = Hash_set.Make(struct 
    type t = id 
    let equal x y = x.stamp = y.stamp && x.name = y.name 
    let hash x = Hashtbl.hash x.stamp
  end
  )

let const_tbl = [|"0"; "1"; "2"; "3"; "4"; "5"; "6"; "7"; "8"; "9"; "10"; "100"; "99"; "98";
          "97"; "96"; "95"; "94"; "93"; "92"; "91"; "90"; "89"; "88"; "87"; "86"; "85";
          "84"; "83"; "82"; "81"; "80"; "79"; "78"; "77"; "76"; "75"; "74"; "73"; "72";
          "71"; "70"; "69"; "68"; "67"; "66"; "65"; "64"; "63"; "62"; "61"; "60"; "59";
          "58"; "57"; "56"; "55"; "54"; "53"; "52"; "51"; "50"; "49"; "48"; "47"; "46";
          "45"; "44"; "43"; "42"; "41"; "40"; "39"; "38"; "37"; "36"; "35"; "34"; "33";
          "32"; "31"; "30"; "29"; "28"; "27"; "26"; "25"; "24"; "23"; "22"; "21"; "20";
          "19"; "18"; "17"; "16"; "15"; "14"; "13"; "12"; "11"|]
let suites = 
  __FILE__
  >:::
  [
    __LOC__ >:: begin fun _ ->
      let v = Hash_set_poly.create 31 in
      for i = 0 to 1000 do
        Hash_set_poly.add v i  
      done  ;
      OUnit.assert_equal (Hash_set_poly.length v) 1001
    end ;
    __LOC__ >:: begin fun _ ->
      let v = Hash_set_poly.create 31 in
      for _ = 0 to 1_0_000 do
        Hash_set_poly.add v 0
      done  ;
      OUnit.assert_equal (Hash_set_poly.length v) 1
    end ;
    __LOC__ >:: begin fun _ -> 
      let v = Hash_set_poly.create 30 in 
      for i = 0 to 2_000 do 
        Hash_set_poly.add v {name = "x" ; stamp = i}
      done ;
      for i = 0 to 2_000 do 
        Hash_set_poly.add v {name = "x" ; stamp = i}
      done  ; 
      for i = 0 to 2_000 do 
        assert (Hash_set_poly.mem v {name = "x"; stamp = i})
      done;  
      OUnit.assert_equal (Hash_set_poly.length v)  2_001;
      for i =  1990 to 3_000 do 
        Hash_set_poly.remove v {name = "x"; stamp = i}
      done ;
      OUnit.assert_equal (Hash_set_poly.length v) 1990;
      (* OUnit.assert_equal (Hash_set.stats v) *)
      (*   {Hashtbl.num_bindings = 1990; num_buckets = 1024; max_bucket_length = 7; *)
      (*    bucket_histogram = [|139; 303; 264; 178; 93; 32; 12; 3|]} *)
    end ;
    __LOC__ >:: begin fun _ -> 
      let v = Id_hash_set.create 30 in 
      for i = 0 to 2_000 do 
        Id_hash_set.add v {name = "x" ; stamp = i}
      done ;
      for i = 0 to 2_000 do 
        Id_hash_set.add v {name = "x" ; stamp = i}
      done  ; 
      for i = 0 to 2_000 do 
        assert (Id_hash_set.mem v {name = "x"; stamp = i})
      done;  
      OUnit.assert_equal (Id_hash_set.length v)  2_001;
      for i =  1990 to 3_000 do 
        Id_hash_set.remove v {name = "x"; stamp = i}
      done ;
      OUnit.assert_equal (Id_hash_set.length v) 1990;
      for i = 1000 to 3990 do 
        Id_hash_set.remove v { name = "x"; stamp = i }
      done;
      OUnit.assert_equal (Id_hash_set.length v) 1000;
      for i = 1000 to 1100 do 
        Id_hash_set.add v { name = "x"; stamp = i};
      done;
      OUnit.assert_equal (Id_hash_set.length v ) 1101;
      for i = 0 to 1100 do 
        OUnit.assert_bool "exist" (Id_hash_set.mem v {name = "x"; stamp = i})
      done  
      (* OUnit.assert_equal (Hash_set.stats v) *)
      (*   {num_bindings = 1990; num_buckets = 1024; max_bucket_length = 8; *)
      (*    bucket_histogram = [|148; 275; 285; 182; 95; 21; 14; 2; 2|]} *)

    end 
    ;
    
    __LOC__ >:: begin fun _ -> 
      let duplicate arr = 
        let len = Array.length arr in 
        let rec aux tbl off = 
          if off >= len  then None
          else 
            let curr = (Array.unsafe_get arr off) in
            if Hash_set_string.check_add tbl curr then 
              aux tbl (off + 1)
            else   Some curr in 
        aux (Hash_set_string.create len) 0 in 
      let v = [| "if"; "a"; "b"; "c" |] in 
      OUnit.assert_equal (duplicate v) None;
      OUnit.assert_equal (duplicate [|"if"; "a"; "b"; "b"; "c"|]) (Some "b")
    end;
    __LOC__ >:: begin fun _ -> 
      let of_array lst =
        let len = Array.length lst in 
        let tbl = Hash_set_string.create len in 
        Ext_array.iter lst (Hash_set_string.add tbl) ; tbl  in 
      let hash = of_array const_tbl  in 
      let len = Hash_set_string.length hash in 
      Hash_set_string.remove hash "x";
      OUnit.assert_equal len (Hash_set_string.length hash);
      Hash_set_string.remove hash "0";
      OUnit.assert_equal (len - 1 ) (Hash_set_string.length hash)
    end
  ]

end
module Hash_set_int : sig 
#1 "hash_set_int.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


include Hash_set_gen.S with type key = int

end = struct
#1 "hash_set_int.ml"
# 1 "ext/hash_set.cppo.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)
[@@@warning "-32"] (* FIXME *)
# 26 "ext/hash_set.cppo.ml"
type key = int
let key_index (h :  _ Hash_set_gen.t ) (key : key) =
  (Bs_hash_stubs.hash_int  key) land (Array.length h.data - 1)
let eq_key = Ext_int.equal 
type  t = key  Hash_set_gen.t 


      
# 65 "ext/hash_set.cppo.ml"
      let create = Hash_set_gen.create
  let clear = Hash_set_gen.clear
  let reset = Hash_set_gen.reset
  (* let copy = Hash_set_gen.copy *)
  let iter = Hash_set_gen.iter
  let fold = Hash_set_gen.fold
  let length = Hash_set_gen.length
  (* let stats = Hash_set_gen.stats *)
  let to_list = Hash_set_gen.to_list



  let remove (h : _ Hash_set_gen.t ) key =
    let i = key_index h key in
    let h_data = h.data in 
    Hash_set_gen.remove_bucket h i key ~prec:Empty (Array.unsafe_get h_data i) eq_key    



  let add (h : _ Hash_set_gen.t) key =
    let i = key_index h key  in 
    let h_data = h.data in 
    let old_bucket = (Array.unsafe_get h_data i) in
    if not (Hash_set_gen.small_bucket_mem eq_key key old_bucket) then 
      begin 
        Array.unsafe_set h_data i (Cons {key = key ; next =  old_bucket});
        h.size <- h.size + 1 ;
        if h.size > Array.length h_data lsl 1 then Hash_set_gen.resize key_index h
      end

  let of_array arr = 
    let len = Array.length arr in 
    let tbl = create len in 
    for i = 0 to len - 1  do
      add tbl (Array.unsafe_get arr i);
    done ;
    tbl 


  let check_add (h : _ Hash_set_gen.t) key : bool =
    let i = key_index h key  in 
    let h_data = h.data in  
    let old_bucket = (Array.unsafe_get h_data i) in
    if not (Hash_set_gen.small_bucket_mem eq_key key old_bucket) then 
      begin 
        Array.unsafe_set h_data i  (Cons { key = key ; next =  old_bucket});
        h.size <- h.size + 1 ;
        if h.size > Array.length h_data lsl 1 then Hash_set_gen.resize key_index h;
        true 
      end
    else false 


  let mem (h :  _ Hash_set_gen.t) key =
    Hash_set_gen.small_bucket_mem eq_key key (Array.unsafe_get h.data (key_index h key)) 



end
module Ounit_hash_stubs_test
= struct
#1 "ounit_hash_stubs_test.ml"
let ((>::),
    (>:::)) = OUnit.((>::),(>:::))

let (=~) = OUnit.assert_equal

let count = 2_000_000

let bench () = 
  Ounit_tests_util.time "int hash set" begin fun _ -> 
    let v = Hash_set_int.create 2_000_000 in 
    for i = 0 to  count do 
      Hash_set_int.add  v i
    done ;
    for _ = 0 to 3 do 
      for i = 0 to count do 
        assert (Hash_set_int.mem v i)
      done
    done
  end;
  Ounit_tests_util.time "int hash set" begin fun _ -> 
    let v = Hash_set_poly.create 2_000_000 in 
    for i = 0 to  count do 
      Hash_set_poly.add  v i
    done ;
    for _ = 0 to 3 do 
      for i = 0 to count do 
        assert (Hash_set_poly.mem v i)
     done
    done
  end


type id (* = Ident.t *) = { stamp : int; name : string; mutable flags : int; }
let hash id = Bs_hash_stubs.hash_stamp_and_name id.stamp id.name 
let suites = 
    __FILE__
    >:::
    [
      __LOC__ >:: begin fun _ -> 
        Bs_hash_stubs.hash_int 0 =~ Hashtbl.hash 0
      end;
      __LOC__ >:: begin fun _ -> 
        Bs_hash_stubs.hash_int max_int =~ Hashtbl.hash max_int
      end;
      __LOC__ >:: begin fun _ -> 
        Bs_hash_stubs.hash_int max_int =~ Hashtbl.hash max_int
      end;
      __LOC__ >:: begin fun _ -> 
        Bs_hash_stubs.hash_string "The quick brown fox jumps over the lazy dog"  =~ 
        Hashtbl.hash "The quick brown fox jumps over the lazy dog"
      end;
      __LOC__ >:: begin fun _ ->
        Array.init 100 (fun i -> String.make i 'a' )
        |> Array.iter (fun x -> 
          Bs_hash_stubs.hash_string x =~ Hashtbl.hash x) 
      end;
      __LOC__ >:: begin fun _ ->
        (* only stamp matters here *)
        hash {stamp = 1 ; name = "xx"; flags = 0} =~ Bs_hash_stubs.hash_small_int 1 ;
        hash {stamp = 11 ; name = "xx"; flags = 0} =~ Bs_hash_stubs.hash_small_int 11;
      end;
      __LOC__ >:: begin fun _ ->
        (* only string matters here *)
        hash {stamp = 0 ; name = "Pervasives"; flags = 0} =~ Bs_hash_stubs.hash_string "Pervasives";
        hash {stamp = 0 ; name = "UU"; flags = 0} =~ Bs_hash_stubs.hash_string "UU";
      end;
      __LOC__ >:: begin fun _ -> 
        let v = Array.init 20 (fun i -> i) in 
        let u = Array.init 30 (fun i ->   (0-i)  ) in  
        Bs_hash_stubs.int_unsafe_blit 
         v 0 u 10 20 ; 
        OUnit.assert_equal u (Array.init 30 (fun i -> if i < 10 then -i else i - 10)) 
      end
    ]

end
module Ext_obj : sig 
#1 "ext_obj.mli"
(* Copyright (C) 2019-Present Authors of ReScript 
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)
val dump : 'a -> string 
val dump_endline : ?__LOC__:string -> 'a -> unit 
val pp_any : Format.formatter -> 'a -> unit 
val bt : unit -> unit
end = struct
#1 "ext_obj.ml"
(* Copyright (C) 2019-Present Hongbo Zhang, Authors of ReScript 
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

let rec dump r =
  if Obj.is_int r then
    string_of_int (Obj.magic r : int)
  else (* Block. *)
    let rec get_fields acc = function
      | 0 -> acc
      | n -> let n = n-1 in get_fields (Obj.field r n :: acc) n
    in
    let rec is_list r =
      if Obj.is_int r then
        r = Obj.repr 0 (* [] *)
      else
        let s = Obj.size r and t = Obj.tag r in
        t = 0 && s = 2 && is_list (Obj.field r 1) (* h :: t *)
    in
    let rec get_list r =
      if Obj.is_int r then
        []
      else
        let h = Obj.field r 0 and t = get_list (Obj.field r 1) in
        h :: t
    in
    let opaque name =
      (* XXX In future, print the address of value 'r'.  Not possible
       * in pure OCaml at the moment.  *)
      "<" ^ name ^ ">"
    in
    let s = Obj.size r and t = Obj.tag r in
    (* From the tag, determine the type of block. *)
    match t with
    | _ when is_list r ->
      let fields = get_list r in
      "[" ^ String.concat "; " (Ext_list.map fields dump) ^ "]"
    | 0 ->
      let fields = get_fields [] s in
      "(" ^ String.concat ", " (Ext_list.map fields dump) ^ ")"
    | x when x = Obj.lazy_tag ->
      (* Note that [lazy_tag .. forward_tag] are < no_scan_tag.  Not
         * clear if very large constructed values could have the same
         * tag. XXX *)
      opaque "lazy"
    | x when x = Obj.closure_tag ->
      opaque "closure"
    | x when x = Obj.object_tag ->
      let fields = get_fields [] s in
      let _clasz, id, slots =
        match fields with
        | h::h'::t -> h, h', t
        | _ -> assert false
      in
      (* No information on decoding the class (first field).  So just print
         * out the ID and the slots. *)
      "Object #" ^ dump id ^ " (" ^ String.concat ", " (Ext_list.map slots dump) ^ ")"
    | x when x = Obj.infix_tag ->
      opaque "infix"
    | x when x = Obj.forward_tag ->
      opaque "forward"
    | x when x < Obj.no_scan_tag ->
      let fields = get_fields [] s in
      "Tag" ^ string_of_int t ^
      " (" ^ String.concat ", " (Ext_list.map fields dump) ^ ")"
    | x when x = Obj.string_tag ->
      "\"" ^ String.escaped (Obj.magic r : string) ^ "\""
    | x when x = Obj.double_tag ->
      string_of_float (Obj.magic r : float)
    | x when x = Obj.abstract_tag ->
      opaque "abstract"
    | x when x = Obj.custom_tag ->
      opaque "custom"
    | x when x = Obj.custom_tag ->
      opaque "final"
    | x when x = Obj.double_array_tag ->
      "[|"^
      String.concat ";"
        (Array.to_list (Array.map string_of_float (Obj.magic r : float array))) ^
      "|]"
    | _ ->
      opaque (Printf.sprintf "unknown: tag %d size %d" t s)

let dump v = dump (Obj.repr v)
let dump_endline ?(__LOC__="") v = 
    print_endline __LOC__;    
    print_endline (dump v )
let pp_any fmt v = 
  Format.fprintf fmt "@[%s@]"
    (dump v )


let bt () = 
  let raw_bt = Printexc.backtrace_slots (Printexc.get_raw_backtrace()) in       
  match raw_bt with 
  | None -> ()
  | Some raw_bt ->
    let acc = ref [] in 
    (for i =  Array.length raw_bt - 1  downto 0 do 
       let slot =  raw_bt.(i) in 
       match Printexc.Slot.location slot with 
       | None
         -> ()
       | Some bt ->
         (match !acc with 
          | [] -> acc := [bt]
          | hd::_ -> if hd <> bt then acc := bt :: !acc )

     done); 
    Ext_list.iter !acc (fun bt ->       
        Printf.eprintf "File \"%s\", line %d, characters %d-%d\n"
          bt.filename bt.line_number bt.start_char bt.end_char )

end
module Ounit_hashtbl_tests
= struct
#1 "ounit_hashtbl_tests.ml"
let ((>::),
     (>:::)) = OUnit.((>::),(>:::))

let (=~) = OUnit.assert_equal ~printer:Ext_obj.dump


let suites = 
  __FILE__
  >:::[
    (* __LOC__ >:: begin fun _ ->  *)
    (*   let h = Hash_string.create 0 in  *)
    (*   let accu key = *)
    (*     Hash_string.replace_or_init h key   succ 1 in  *)
    (*   let count = 1000 in  *)
    (*   for i = 0 to count - 1 do      *)
    (*     Array.iter accu  [|"a";"b";"c";"d";"e";"f"|]     *)
    (*   done; *)
    (*   Hash_string.length h =~ 6; *)
    (*   Hash_string.iter (fun _ v -> v =~ count ) h *)
    (* end; *)

    "add semantics " >:: begin fun _ -> 
      let h = Hash_string.create 0 in 
      let count = 1000 in 
      for _ = 0 to 1 do  
        for i = 0 to count - 1 do                 
          Hash_string.add h (string_of_int i) i 
        done
      done ;
      Hash_string.length h =~ 2 * count 
    end; 
    "replace semantics" >:: begin fun _ -> 
      let h = Hash_string.create 0 in 
      let count = 1000 in 
      for _ = 0 to 1 do  
        for i = 0 to count - 1 do                 
          Hash_string.replace h (string_of_int i) i 
        done
      done ;
      Hash_string.length h =~  count 
    end; 
    
    __LOC__ >:: begin fun _ ->
      let h = Hash_string.create 0 in 
      let count = 10 in 
      for i = 0 to count - 1 do 
        Hash_string.replace h (string_of_int i) i
      done; 
      let xs = Hash_string.to_list h (fun k _ -> k) in 
      let ys = List.sort compare xs  in 
      ys =~ ["0";"1";"2";"3";"4";"5";"6";"7";"8";"9"]
    end
  ]

end
module Js_reserved_map : sig 
#1 "js_reserved_map.mli"
(* Copyright (C) 2019-Present Authors of ReScript
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


val is_reserved : 
  string -> bool 
end = struct
#1 "js_reserved_map.ml"

(* Copyright (C) 2019-Present Hongbo Zhang, Authors of ReScript
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

let sorted_keywords = [|
  "AbortController";
  "AbortSignal";
  "ActiveXObject";
  "AnalyserNode";
  "AnimationEvent";
  "Array";
  "ArrayBuffer";
  "Atomics";
  "Attr";
  "Audio";
  "AudioBuffer";
  "AudioBufferSourceNode";
  "AudioContext";
  "AudioDestinationNode";
  "AudioListener";
  "AudioNode";
  "AudioParam";
  "AudioParamMap";
  "AudioProcessingEvent";
  "AudioScheduledSourceNode";
  "AudioWorkletNode";
  "BarProp";
  "BaseAudioContext";
  "BatteryManager";
  "BeforeInstallPromptEvent";
  "BeforeUnloadEvent";
  "BigInt";
  "BigInt64Array";
  "BigUint64Array";
  "BiquadFilterNode";
  "Blob";
  "BlobEvent";
  "BluetoothUUID";
  "Boolean";
  "BroadcastChannel";
  "Buffer";
  "ByteLengthQueuingStrategy";
  "CDATASection";
  "CSS";
  "CSSConditionRule";
  "CSSFontFaceRule";
  "CSSGroupingRule";
  "CSSImageValue";
  "CSSImportRule";
  "CSSKeyframeRule";
  "CSSKeyframesRule";
  "CSSKeywordValue";
  "CSSMathInvert";
  "CSSMathMax";
  "CSSMathMin";
  "CSSMathNegate";
  "CSSMathProduct";
  "CSSMathSum";
  "CSSMathValue";
  "CSSMatrixComponent";
  "CSSMediaRule";
  "CSSNamespaceRule";
  "CSSNumericArray";
  "CSSNumericValue";
  "CSSPageRule";
  "CSSPerspective";
  "CSSPositionValue";
  "CSSRotate";
  "CSSRule";
  "CSSRuleList";
  "CSSScale";
  "CSSSkew";
  "CSSSkewX";
  "CSSSkewY";
  "CSSStyleDeclaration";
  "CSSStyleRule";
  "CSSStyleSheet";
  "CSSStyleValue";
  "CSSSupportsRule";
  "CSSTransformComponent";
  "CSSTransformValue";
  "CSSTranslate";
  "CSSUnitValue";
  "CSSUnparsedValue";
  "CSSVariableReferenceValue";
  "CanvasCaptureMediaStreamTrack";
  "CanvasGradient";
  "CanvasPattern";
  "CanvasRenderingContext2D";
  "ChannelMergerNode";
  "ChannelSplitterNode";
  "CharacterData";
  "ClipboardEvent";
  "CloseEvent";
  "Comment";
  "CompositionEvent";
  "ConstantSourceNode";
  "ConvolverNode";
  "CountQueuingStrategy";
  "Crypto";
  "CryptoKey";
  "CustomElementRegistry";
  "CustomEvent";
  "DOMError";
  "DOMException";
  "DOMImplementation";
  "DOMMatrix";
  "DOMMatrixReadOnly";
  "DOMParser";
  "DOMPoint";
  "DOMPointReadOnly";
  "DOMQuad";
  "DOMRect";
  "DOMRectList";
  "DOMRectReadOnly";
  "DOMStringList";
  "DOMStringMap";
  "DOMTokenList";
  "DataTransfer";
  "DataTransferItem";
  "DataTransferItemList";
  "DataView";
  "Date";
  "DelayNode";
  "DeviceMotionEvent";
  "DeviceOrientationEvent";
  "Document";
  "DocumentFragment";
  "DocumentType";
  "DragEvent";
  "DynamicsCompressorNode";
  "Element";
  "EnterPictureInPictureEvent";
  "Error";
  "ErrorEvent";
  "EvalError";
  "Event";
  "EventSource";
  "EventTarget";
  "File";
  "FileList";
  "FileReader";
  "Float32Array";
  "Float64Array";
  "FocusEvent";
  "FontFace";
  "FontFaceSetLoadEvent";
  "FormData";
  "Function";
  "GainNode";
  "Gamepad";
  "GamepadButton";
  "GamepadEvent";
  "GamepadHapticActuator";
  "HTMLAllCollection";
  "HTMLAnchorElement";
  "HTMLAreaElement";
  "HTMLAudioElement";
  "HTMLBRElement";
  "HTMLBaseElement";
  "HTMLBodyElement";
  "HTMLButtonElement";
  "HTMLCanvasElement";
  "HTMLCollection";
  "HTMLContentElement";
  "HTMLDListElement";
  "HTMLDataElement";
  "HTMLDataListElement";
  "HTMLDetailsElement";
  "HTMLDialogElement";
  "HTMLDirectoryElement";
  "HTMLDivElement";
  "HTMLDocument";
  "HTMLElement";
  "HTMLEmbedElement";
  "HTMLFieldSetElement";
  "HTMLFontElement";
  "HTMLFormControlsCollection";
  "HTMLFormElement";
  "HTMLFrameElement";
  "HTMLFrameSetElement";
  "HTMLHRElement";
  "HTMLHeadElement";
  "HTMLHeadingElement";
  "HTMLHtmlElement";
  "HTMLIFrameElement";
  "HTMLImageElement";
  "HTMLInputElement";
  "HTMLLIElement";
  "HTMLLabelElement";
  "HTMLLegendElement";
  "HTMLLinkElement";
  "HTMLMapElement";
  "HTMLMarqueeElement";
  "HTMLMediaElement";
  "HTMLMenuElement";
  "HTMLMetaElement";
  "HTMLMeterElement";
  "HTMLModElement";
  "HTMLOListElement";
  "HTMLObjectElement";
  "HTMLOptGroupElement";
  "HTMLOptionElement";
  "HTMLOptionsCollection";
  "HTMLOutputElement";
  "HTMLParagraphElement";
  "HTMLParamElement";
  "HTMLPictureElement";
  "HTMLPreElement";
  "HTMLProgressElement";
  "HTMLQuoteElement";
  "HTMLScriptElement";
  "HTMLSelectElement";
  "HTMLShadowElement";
  "HTMLSlotElement";
  "HTMLSourceElement";
  "HTMLSpanElement";
  "HTMLStyleElement";
  "HTMLTableCaptionElement";
  "HTMLTableCellElement";
  "HTMLTableColElement";
  "HTMLTableElement";
  "HTMLTableRowElement";
  "HTMLTableSectionElement";
  "HTMLTemplateElement";
  "HTMLTextAreaElement";
  "HTMLTimeElement";
  "HTMLTitleElement";
  "HTMLTrackElement";
  "HTMLUListElement";
  "HTMLUnknownElement";
  "HTMLVideoElement";
  "HashChangeEvent";
  "Headers";
  "History";
  "IDBCursor";
  "IDBCursorWithValue";
  "IDBDatabase";
  "IDBFactory";
  "IDBIndex";
  "IDBKeyRange";
  "IDBObjectStore";
  "IDBOpenDBRequest";
  "IDBRequest";
  "IDBTransaction";
  "IDBVersionChangeEvent";
  "IIRFilterNode";
  "IdleDeadline";
  "Image";
  "ImageBitmap";
  "ImageBitmapRenderingContext";
  "ImageCapture";
  "ImageData";
  "Infinity";
  "InputDeviceCapabilities";
  "InputDeviceInfo";
  "InputEvent";
  "Int16Array";
  "Int32Array";
  "Int8Array";
  "IntersectionObserver";
  "IntersectionObserverEntry";
  "Intl";
  "JSON";
  "KeyboardEvent";
  "Location";
  "MIDIAccess";
  "MIDIConnectionEvent";
  "MIDIInput";
  "MIDIInputMap";
  "MIDIMessageEvent";
  "MIDIOutput";
  "MIDIOutputMap";
  "MIDIPort";
  "Map";
  "Math";
  "MediaCapabilities";
  "MediaCapabilitiesInfo";
  "MediaDeviceInfo";
  "MediaDevices";
  "MediaElementAudioSourceNode";
  "MediaEncryptedEvent";
  "MediaError";
  "MediaList";
  "MediaQueryList";
  "MediaQueryListEvent";
  "MediaRecorder";
  "MediaSettingsRange";
  "MediaSource";
  "MediaStream";
  "MediaStreamAudioDestinationNode";
  "MediaStreamAudioSourceNode";
  "MediaStreamEvent";
  "MediaStreamTrack";
  "MediaStreamTrackEvent";
  "MessageChannel";
  "MessageEvent";
  "MessagePort";
  "MimeType";
  "MimeTypeArray";
  "MouseEvent";
  "MutationEvent";
  "MutationObserver";
  "MutationRecord";
  "NaN";
  "NamedNodeMap";
  "Navigator";
  "NetworkInformation";
  "Node";
  "NodeFilter";
  "NodeIterator";
  "NodeList";
  "Notification";
  "Number";
  "Object";
  "OfflineAudioCompletionEvent";
  "OfflineAudioContext";
  "OffscreenCanvas";
  "OffscreenCanvasRenderingContext2D";
  "Option";
  "OscillatorNode";
  "OverconstrainedError";
  "PageTransitionEvent";
  "PannerNode";
  "Path2D";
  "PaymentInstruments";
  "PaymentManager";
  "PaymentRequestUpdateEvent";
  "Performance";
  "PerformanceEntry";
  "PerformanceLongTaskTiming";
  "PerformanceMark";
  "PerformanceMeasure";
  "PerformanceNavigation";
  "PerformanceNavigationTiming";
  "PerformanceObserver";
  "PerformanceObserverEntryList";
  "PerformancePaintTiming";
  "PerformanceResourceTiming";
  "PerformanceServerTiming";
  "PerformanceTiming";
  "PeriodicWave";
  "PermissionStatus";
  "Permissions";
  "PhotoCapabilities";
  "PictureInPictureWindow";
  "Plugin";
  "PluginArray";
  "PointerEvent";
  "PopStateEvent";
  "ProcessingInstruction";
  "ProgressEvent";
  "Promise";
  "PromiseRejectionEvent";
  "Proxy";
  "PushManager";
  "PushSubscription";
  "PushSubscriptionOptions";
  "RTCCertificate";
  "RTCDTMFSender";
  "RTCDTMFToneChangeEvent";
  "RTCDataChannel";
  "RTCDataChannelEvent";
  "RTCIceCandidate";
  "RTCPeerConnection";
  "RTCPeerConnectionIceEvent";
  "RTCRtpContributingSource";
  "RTCRtpReceiver";
  "RTCRtpSender";
  "RTCRtpTransceiver";
  "RTCSessionDescription";
  "RTCStatsReport";
  "RTCTrackEvent";
  "RadioNodeList";
  "Range";
  "RangeError";
  "ReadableStream";
  "ReferenceError";
  "Reflect";
  "RegExp";
  "RemotePlayback";
  "ReportingObserver";
  "Request";
  "ResizeObserver";
  "ResizeObserverEntry";
  "Response";
  "SVGAElement";
  "SVGAngle";
  "SVGAnimateElement";
  "SVGAnimateMotionElement";
  "SVGAnimateTransformElement";
  "SVGAnimatedAngle";
  "SVGAnimatedBoolean";
  "SVGAnimatedEnumeration";
  "SVGAnimatedInteger";
  "SVGAnimatedLength";
  "SVGAnimatedLengthList";
  "SVGAnimatedNumber";
  "SVGAnimatedNumberList";
  "SVGAnimatedPreserveAspectRatio";
  "SVGAnimatedRect";
  "SVGAnimatedString";
  "SVGAnimatedTransformList";
  "SVGAnimationElement";
  "SVGCircleElement";
  "SVGClipPathElement";
  "SVGComponentTransferFunctionElement";
  "SVGDefsElement";
  "SVGDescElement";
  "SVGDiscardElement";
  "SVGElement";
  "SVGEllipseElement";
  "SVGFEBlendElement";
  "SVGFEColorMatrixElement";
  "SVGFEComponentTransferElement";
  "SVGFECompositeElement";
  "SVGFEConvolveMatrixElement";
  "SVGFEDiffuseLightingElement";
  "SVGFEDisplacementMapElement";
  "SVGFEDistantLightElement";
  "SVGFEDropShadowElement";
  "SVGFEFloodElement";
  "SVGFEFuncAElement";
  "SVGFEFuncBElement";
  "SVGFEFuncGElement";
  "SVGFEFuncRElement";
  "SVGFEGaussianBlurElement";
  "SVGFEImageElement";
  "SVGFEMergeElement";
  "SVGFEMergeNodeElement";
  "SVGFEMorphologyElement";
  "SVGFEOffsetElement";
  "SVGFEPointLightElement";
  "SVGFESpecularLightingElement";
  "SVGFESpotLightElement";
  "SVGFETileElement";
  "SVGFETurbulenceElement";
  "SVGFilterElement";
  "SVGForeignObjectElement";
  "SVGGElement";
  "SVGGeometryElement";
  "SVGGradientElement";
  "SVGGraphicsElement";
  "SVGImageElement";
  "SVGLength";
  "SVGLengthList";
  "SVGLineElement";
  "SVGLinearGradientElement";
  "SVGMPathElement";
  "SVGMarkerElement";
  "SVGMaskElement";
  "SVGMatrix";
  "SVGMetadataElement";
  "SVGNumber";
  "SVGNumberList";
  "SVGPathElement";
  "SVGPatternElement";
  "SVGPoint";
  "SVGPointList";
  "SVGPolygonElement";
  "SVGPolylineElement";
  "SVGPreserveAspectRatio";
  "SVGRadialGradientElement";
  "SVGRect";
  "SVGRectElement";
  "SVGSVGElement";
  "SVGScriptElement";
  "SVGSetElement";
  "SVGStopElement";
  "SVGStringList";
  "SVGStyleElement";
  "SVGSwitchElement";
  "SVGSymbolElement";
  "SVGTSpanElement";
  "SVGTextContentElement";
  "SVGTextElement";
  "SVGTextPathElement";
  "SVGTextPositioningElement";
  "SVGTitleElement";
  "SVGTransform";
  "SVGTransformList";
  "SVGUnitTypes";
  "SVGUseElement";
  "SVGViewElement";
  "Screen";
  "ScreenOrientation";
  "ScriptProcessorNode";
  "SecurityPolicyViolationEvent";
  "Selection";
  "Set";
  "ShadowRoot";
  "SharedArrayBuffer";
  "SharedWorker";
  "SourceBuffer";
  "SourceBufferList";
  "SpeechSynthesisErrorEvent";
  "SpeechSynthesisEvent";
  "SpeechSynthesisUtterance";
  "StaticRange";
  "StereoPannerNode";
  "Storage";
  "StorageEvent";
  "String";
  "StylePropertyMap";
  "StylePropertyMapReadOnly";
  "StyleSheet";
  "StyleSheetList";
  "SubtleCrypto";
  "Symbol";
  "SyncManager";
  "SyntaxError";
  "TaskAttributionTiming";
  "Text";
  "TextDecoder";
  "TextDecoderStream";
  "TextEncoder";
  "TextEncoderStream";
  "TextEvent";
  "TextMetrics";
  "TextTrack";
  "TextTrackCue";
  "TextTrackCueList";
  "TextTrackList";
  "TimeRanges";
  "Touch";
  "TouchEvent";
  "TouchList";
  "TrackEvent";
  "TransformStream";
  "TransitionEvent";
  "TreeWalker";
  "TypeError";
  "UIEvent";
  "URIError";
  "URL";
  "URLSearchParams";
  "Uint16Array";
  "Uint32Array";
  "Uint8Array";
  "Uint8ClampedArray";
  "UserActivation";
  "VTTCue";
  "ValidityState";
  "VisualViewport";
  "WaveShaperNode";
  "WeakMap";
  "WeakSet";
  "WebAssembly";
  "WebGL2RenderingContext";
  "WebGLActiveInfo";
  "WebGLBuffer";
  "WebGLContextEvent";
  "WebGLFramebuffer";
  "WebGLProgram";
  "WebGLQuery";
  "WebGLRenderbuffer";
  "WebGLRenderingContext";
  "WebGLSampler";
  "WebGLShader";
  "WebGLShaderPrecisionFormat";
  "WebGLSync";
  "WebGLTexture";
  "WebGLTransformFeedback";
  "WebGLUniformLocation";
  "WebGLVertexArrayObject";
  "WebKitCSSMatrix";
  "WebKitMutationObserver";
  "WebSocket";
  "WheelEvent";
  "Window";
  "Worker";
  "WritableStream";
  "XDomainRequest";
  "XMLDocument";
  "XMLHttpRequest";
  "XMLHttpRequestEventTarget";
  "XMLHttpRequestUpload";
  "XMLSerializer";
  "XPathEvaluator";
  "XPathExpression";
  "XPathResult";
  "XSLTProcessor";
  "__dirname";
  "__esModule";
  "__filename";
  "abstract";
  "arguments";
  "await";
  "boolean";
  "break";
  "byte";
  "case";
  "catch";
  "char";
  "class";
  "clearImmediate";
  "clearInterval";
  "clearTimeout";
  "console";
  "const";
  "continue";
  "debugger";
  "decodeURI";
  "decodeURIComponent";
  "default";
  "delete";
  "do";
  "document";
  "double";
  "else";
  "encodeURI";
  "encodeURIComponent";
  "enum";
  "escape";
  "eval";
  "event";
  "export";
  "exports";
  "extends";
  "false";
  "fetch";
  "final";
  "finally";
  "float";
  "for";
  "function";
  "global";
  "goto";
  "if";
  "implements";
  "import";
  "in";
  "instanceof";
  "int";
  "interface";
  "isFinite";
  "isNaN";
  "let";
  "location";
  "long";
  "module";
  "native";
  "navigator";
  "new";
  "null";
  "package";
  "parseFloat";
  "parseInt";
  "private";
  "process";
  "protected";
  "public";
  "require";
  "return";
  "setImmediate";
  "setInterval";
  "setTimeout";
  "short";
  "static";
  "super";
  "switch";
  "synchronized";
  "then";
  "this";
  "throw";
  "transient";
  "true";
  "try";
  "typeof";
  "undefined";
  "unescape";
  "var";
  "void";
  "volatile";
  "while";
  "window";
  "with";
  "yield";
  |]


type element = string 

let rec binarySearchAux (arr : element array) (lo : int) (hi : int) key : bool =   
    let mid = (lo + hi)/2 in 
    let midVal = Array.unsafe_get arr mid in 
    (* let c = cmp key midVal [@bs] in  *)
    if key = midVal then true 
    else if key < midVal then  (*  a[lo] =< key < a[mid] <= a[hi] *)
      if hi = mid then  
        (Array.unsafe_get arr lo) = key 
      else binarySearchAux arr lo mid key 
    else  (*  a[lo] =< a[mid] < key <= a[hi] *)
      if lo = mid then 
        (Array.unsafe_get arr hi) = key 
      else binarySearchAux arr mid hi key 

let binarySearch (sorted : element array) (key : element)  : bool =  
  let len = Array.length sorted in 
  if len = 0 then false
  else 
    let lo = Array.unsafe_get sorted 0 in 
    (* let c = cmp key lo [@bs] in  *)
    if key < lo then false
    else
    let hi = Array.unsafe_get sorted (len - 1) in 
    (* let c2 = cmp key hi [@bs]in  *)
    if key > hi then false
    else binarySearchAux sorted 0 (len - 1) key 

let is_reserved s = binarySearch sorted_keywords s     

end
module Ext_ident : sig 
#1 "ext_ident.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)








(** A wrapper around [Ident] module in compiler-libs*)

val is_js : Ident.t -> bool 

val is_js_object : Ident.t -> bool

(** create identifiers for predefined [js] global variables *)
val create_js : string -> Ident.t

val create : string -> Ident.t

val make_js_object : Ident.t -> unit 

val reset : unit -> unit

val create_tmp :  ?name:string -> unit -> Ident.t

val make_unused : unit -> Ident.t 



(**
   Invariant: if name is not converted, the reference should be equal
*)
val convert : string -> string



val is_js_or_global : Ident.t -> bool



val compare : Ident.t -> Ident.t -> int
val equal : Ident.t -> Ident.t -> bool 

end = struct
#1 "ext_ident.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 2017 - Hongbo Zhang, Authors of ReScript
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)








let js_flag = 0b1_000 (* check with ocaml compiler *)

(* let js_module_flag = 0b10_000 (\* javascript external modules *\) *)
(* TODO:
    check name conflicts with javascript conventions
   {[
     Ext_ident.convert "^";;
     - : string = "$caret"
   ]}
*)
let js_object_flag = 0b100_000 (* javascript object flags *)

let is_js (i : Ident.t) =
  i.flags land js_flag <> 0

let is_js_or_global (i : Ident.t) =
  i.flags land (8 lor 1) <> 0


let is_js_object (i : Ident.t) =
  i.flags land js_object_flag <> 0

let make_js_object (i : Ident.t) =
  i.flags <- i.flags lor js_object_flag

(* It's a js function hard coded by js api, so when printing,
   it should preserve the name
*)
let create_js (name : string) : Ident.t  =
  { name = name; flags = js_flag ; stamp = 0}

let create = Ident.create

(* FIXME: no need for `$' operator *)
let create_tmp ?(name=Literals.tmp) () = create name


let js_module_table : Ident.t Hash_string.t = Hash_string.create 31

(* This is for a js exeternal module, we can change it when printing
   for example
   {[
     var React$1 = require('react');
     React$1.render(..)
   ]}

   Given a name, if duplicated, they should  have the same id
*)
(* let create_js_module (name : string) : Ident.t =
   let name =
    String.concat "" @@ Ext_list.map
    (Ext_string.split name '-')  Ext_string.capitalize_ascii in
   (* TODO: if we do such transformation, we should avoid       collision for example:
      react-dom
      react--dom
      check collision later
  *)
   match Hash_string.find_exn js_module_table name  with
   | exception Not_found ->
    let ans = Ident.create name in
    (* let ans = { v with flags = js_module_flag} in  *)
    Hash_string.add js_module_table name ans;
    ans
   | v -> (* v *) Ident.rename v


*)

let [@inline] convert ?(op=false) (c : char) : string =
  (match c with
   | '*' ->   "$star"
   | '\'' ->   "$p"
   | '!' ->   "$bang"
   | '>' ->   "$great"
   | '<' ->   "$less"
   | '=' ->   "$eq"
   | '+' ->   "$plus"
   | '-' ->   if op then "$neg" else "$"
   | '@' ->   "$at"
   | '^' ->   "$caret"
   | '/' ->   "$slash"
   | '|' ->   "$pipe"
   | '.' ->   "$dot"
   | '%' ->   "$percent"
   | '~' ->   "$tilde"
   | '#' ->   "$hash"
   | ':' ->   "$colon"
   | '?' ->   "$question"
   | '&' ->   "$amp"
   | '(' ->   "$lpar"
   | ')' ->   "$rpar"
   | '{' ->   "$lbrace"
   | '}' ->   "$lbrace"
   | '[' ->   "$lbrack"
   | ']' ->   "$rbrack"

   | _ ->   "$unknown")  
let [@inline] no_escape (c : char) =  
  match c with   
  | 'a' .. 'z' | 'A' .. 'Z'
  | '0' .. '9' | '_' | '$' -> true 
  | _ -> false

exception Not_normal_letter of int
let name_mangle name =
  let len = String.length name  in
  try
    for i  = 0 to len - 1 do
      if not (no_escape (String.unsafe_get name i)) then
        raise_notrace (Not_normal_letter i)
    done;
    name (* Normal letter *)
  with
  | Not_normal_letter i ->
    let buffer = Ext_buffer.create len in
    for j = 0 to  len - 1 do
      let c = String.unsafe_get name j in
      if no_escape c then Ext_buffer.add_char buffer c 
      else 
        Ext_buffer.add_string buffer (convert ~op:(i=0) c)        
    done; Ext_buffer.contents buffer

(* TODO:
    check name conflicts with javascript conventions
   {[
     Ext_ident.convert "^";;
     - : string = "$caret"
   ]}
   [convert name] if [name] is a js keyword,add "$$"
   otherwise do the name mangling to make sure ocaml identifier it is
   a valid js identifier
*)
let convert (name : string) =
  if  Js_reserved_map.is_reserved name  then
    "$$" ^ name
  else name_mangle name

(** keyword could be used in property *)

(* It is currently made a persistent ident to avoid fresh ids
    which would result in different signature files
   - other solution: use lazy values
*)
let make_unused () = create "_"



let reset () =
  Hash_string.clear js_module_table


(* Has to be total order, [x < y]
   and [x > y] should be consistent
   flags are not relevant here
*)
let compare (x : Ident.t ) ( y : Ident.t) =
  let u = x.stamp - y.stamp in
  if u = 0 then
    Ext_string.compare x.name y.name
  else u

let equal ( x : Ident.t) ( y : Ident.t) =
  if x.stamp <> 0 then x.stamp = y.stamp
  else y.stamp = 0 && x.name = y.name

end
module Hash_set_ident_mask : sig 
#1 "hash_set_ident_mask.mli"


(** Based on [hash_set] specialized for mask operations  *)
type ident = Ident.t  


type t

val create: int ->  t


(* add one ident 
   ident is unmaksed by default
*)
val add_unmask :  t -> ident -> unit


(** [check_mask h key] if [key] exists mask it otherwise nothing
    return true if all keys are masked otherwise false
*)
val mask_and_check_all_hit : 
  t -> 
  ident ->  
  bool

(** [iter_and_unmask f h] iterating the collection and mask all idents,
    dont consul the collection in function [f]
    TODO: what happens if an exception raised in the callback,
    would the hashtbl still be in consistent state?
*)
val iter_and_unmask: 
  t -> 
  (ident -> bool ->  unit) -> 
  unit





end = struct
#1 "hash_set_ident_mask.ml"

(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

(** A speicalized datastructure for scc algorithm *)

type ident = Ident.t

type bucket =
  | Empty 
  | Cons of {
      ident : ident; 
      mutable mask : bool;
      rest : bucket
    }

type t = {
  mutable size : int ; 
  mutable data : bucket array;
  mutable mask_size : int (* mark how many idents are marked *)
}



let key_index_by_ident (h : t) (key : Ident.t) =    
  (Bs_hash_stubs.hash_string_int  key.name key.stamp) land (Array.length h.data - 1)




let create  initial_size =
  let s = Ext_util.power_2_above 8 initial_size in
  { size = 0; data = Array.make s Empty ; mask_size = 0}

let iter_and_unmask h f =
  let rec iter_bucket buckets = 
    match buckets with 
    | Empty ->
      ()
    | Cons k ->    
      let k_mask = k.mask in 
      f k.ident k_mask ;
      if k_mask then 
        begin 
          k.mask <- false ;
          (* we can set [h.mask_size] to zero,
             however, it would result inconsistent state
             once [f] throw
          *)
          h.mask_size <- h.mask_size - 1
        end; 
      iter_bucket k.rest 
  in
  let d = h.data in
  for i = 0 to Array.length d - 1 do
    iter_bucket (Array.unsafe_get d i)
  done


let rec small_bucket_mem key lst =
  match lst with 
  | Empty -> false 
  | Cons rst -> 
    Ext_ident.equal key   rst.ident ||
    match rst.rest with 
    | Empty -> false 
    | Cons rst -> 
      Ext_ident.equal key   rst.ident ||
      match rst.rest with 
      | Empty -> false 
      | Cons rst -> 
        Ext_ident.equal key   rst.ident ||
        small_bucket_mem key rst.rest 

let resize indexfun h =
  let odata = h.data in
  let osize = Array.length odata in
  let nsize = osize * 2 in
  if nsize < Sys.max_array_length then begin
    let ndata = Array.make nsize Empty in
    h.data <- ndata;          (* so that indexfun sees the new bucket count *)
    let rec insert_bucket = function
        Empty -> ()
      | Cons {ident = key;  mask; rest} ->
        let nidx = indexfun h key in
        Array.unsafe_set 
          ndata (nidx)  
          (Cons {ident = key; mask; rest = Array.unsafe_get ndata (nidx)});
        insert_bucket rest
    in
    for i = 0 to osize - 1 do
      insert_bucket (Array.unsafe_get odata i)
    done
  end

let add_unmask (h : t) (key : Ident.t) =
  let i = key_index_by_ident h key  in 
  let h_data = h.data in 
  let old_bucket = Array.unsafe_get h_data i in
  if not (small_bucket_mem key old_bucket) then 
    begin 
      Array.unsafe_set h_data i 
        (Cons {ident = key; mask = false; rest =  old_bucket});
      h.size <- h.size + 1 ;
      if h.size > Array.length h_data lsl 1 then resize key_index_by_ident h
    end




let rec small_bucket_mask  key lst =
  match lst with 
  | Empty -> false 
  | Cons rst -> 
    if Ext_ident.equal key   rst.ident  then 
      if rst.mask then false else (rst.mask <- true ; true) 
    else 
      match rst.rest with 
      | Empty -> false
      | Cons rst -> 
        if Ext_ident.equal key rst.ident  then 
          if rst.mask then false else (rst.mask <- true ; true)
        else 
          match rst.rest with 
          | Empty -> false
          | Cons rst -> 
            if Ext_ident.equal key rst.ident then 
              if rst.mask then false else (rst.mask <- true ; true)
            else 
              small_bucket_mask  key rst.rest 

let mask_and_check_all_hit (h : t) (key : Ident.t) =     
  if 
    small_bucket_mask key 
      (Array.unsafe_get h.data (key_index_by_ident h key )) then 
    begin 
      h.mask_size <- h.mask_size + 1 
    end;
  h.size = h.mask_size 




end
module Ounit_ident_mask_tests
= struct
#1 "ounit_ident_mask_tests.ml"
let ((>::),
     (>:::)) = OUnit.((>::),(>:::))

let (=~) = OUnit.assert_equal
let suites = 
  __FILE__
  >:::
  [
    __LOC__ >:: begin fun _ -> 
      let set = Hash_set_ident_mask.create 0  in
      let a,b,_,_ = 
        Ident.create "a", 
        Ident.create "b", 
        Ident.create "c",
        Ident.create "d" in 
      Hash_set_ident_mask.add_unmask set a ;     
      Hash_set_ident_mask.add_unmask set a ;     
      Hash_set_ident_mask.add_unmask set b ;     
      OUnit.assert_bool __LOC__ (not @@ Hash_set_ident_mask.mask_and_check_all_hit set  a);
      OUnit.assert_bool __LOC__ (Hash_set_ident_mask.mask_and_check_all_hit set  b );
      Hash_set_ident_mask.iter_and_unmask set (fun id mask -> 
          if id.Ident.name = "a" then
            OUnit.assert_bool __LOC__ mask 
          else if id.Ident.name = "b" then 
            OUnit.assert_bool __LOC__ mask 
          else ()        
        ) ;
      OUnit.assert_bool __LOC__ (not @@ Hash_set_ident_mask.mask_and_check_all_hit set a );
      OUnit.assert_bool __LOC__ (Hash_set_ident_mask.mask_and_check_all_hit set  b );
    end;
    __LOC__ >:: begin fun _ -> 
        let len = 1000 in 
        let idents = Array.init len (fun i -> Ident.create (string_of_int i)) in 
        let set = Hash_set_ident_mask.create 0 in 
        Array.iter (fun i -> Hash_set_ident_mask.add_unmask set i) idents;
        for i = 0 to len - 2 do 
                OUnit.assert_bool __LOC__ (not @@ Hash_set_ident_mask.mask_and_check_all_hit set idents.(i));
        done ;
         for i = 0 to len - 2 do 
                OUnit.assert_bool __LOC__ (not @@ Hash_set_ident_mask.mask_and_check_all_hit set idents.(i) );
        done ; 
         OUnit.assert_bool __LOC__ (Hash_set_ident_mask.mask_and_check_all_hit  set idents.(len - 1)) ;
         Hash_set_ident_mask.iter_and_unmask set(fun _ _ -> ()) ;
        for i = 0 to len - 2 do 
                OUnit.assert_bool __LOC__ (not @@ Hash_set_ident_mask.mask_and_check_all_hit set idents.(i) );
        done ;
         for i = 0 to len - 2 do 
                OUnit.assert_bool __LOC__ (not @@ Hash_set_ident_mask.mask_and_check_all_hit set idents.(i));
        done ; 
         OUnit.assert_bool __LOC__ (Hash_set_ident_mask.mask_and_check_all_hit  set idents.(len - 1)) ;
         
    end
  ]
end
module Vec_gen
= struct
#1 "vec_gen.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


module type ResizeType = 
sig 
  type t 
  val null : t (* used to populate new allocated array checkout {!Obj.new_block} for more performance *)
end

module type S = 
sig 
  type elt 
  type t
  val length : t -> int 
  val compact : t -> unit
  val singleton : elt -> t 
  val empty : unit -> t 
  val make : int -> t 
  val init : int -> (int -> elt) -> t
  val is_empty : t -> bool
  val of_sub_array : elt array -> int -> int -> t

  (** Exposed for some APIs which only take array as input, 
      when exposed   
  *)
  val unsafe_internal_array : t -> elt array
  val reserve : t -> int -> unit
  val push :  t -> elt -> unit
  val delete : t -> int -> unit 
  val pop : t -> unit
  val get_last_and_pop : t -> elt
  val delete_range : t -> int -> int -> unit 
  val get_and_delete_range : t -> int -> int -> t
  val clear : t -> unit 
  val reset : t -> unit 
  val to_list : t -> elt list 
  val of_list : elt list -> t
  val to_array : t -> elt array 
  val of_array : elt array -> t
  val copy : t -> t 
  val reverse_in_place : t -> unit
  val iter : t -> (elt -> unit) -> unit 
  val iteri : t -> (int -> elt -> unit ) -> unit 
  val iter_range : t -> from:int -> to_:int -> (elt -> unit) -> unit 
  val iteri_range : t -> from:int -> to_:int -> (int -> elt -> unit) -> unit
  val map : (elt -> elt) -> t ->  t
  val mapi : (int -> elt -> elt) -> t -> t
  val map_into_array : (elt -> 'f) -> t -> 'f array
  val map_into_list : (elt -> 'f) -> t -> 'f list 
  val fold_left : ('f -> elt -> 'f) -> 'f -> t -> 'f
  val fold_right : (elt -> 'g -> 'g) -> t -> 'g -> 'g
  val filter : (elt -> bool) -> t -> t
  val inplace_filter : (elt -> bool) -> t -> unit
  val inplace_filter_with : (elt -> bool) -> cb_no:(elt -> 'a -> 'a) -> 'a -> t -> 'a 
  val inplace_filter_from : int -> (elt -> bool) -> t -> unit 
  val equal : (elt -> elt -> bool) -> t -> t -> bool 
  val get : t -> int -> elt
  val unsafe_get : t -> int -> elt
  val last : t -> elt
  val capacity : t -> int
  val exists : (elt -> bool) -> t -> bool
  val sub : t -> int -> int  -> t 
end


end
module Vec_int : sig 
#1 "vec_int.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

include Vec_gen.S with type elt = int

end = struct
#1 "vec_int.ml"
# 1 "ext/vec.cppo.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

# 34 "ext/vec.cppo.ml"
type elt = int 
let null = 0 (* can be optimized *)
let unsafe_blit = Bs_hash_stubs.int_unsafe_blit

# 41 "ext/vec.cppo.ml"
external unsafe_sub : 'a array -> int -> int -> 'a array = "caml_array_sub"

type  t = {
  mutable arr : elt array ;
  mutable len : int ;  
}

let length d = d.len

let compact d =
  let d_arr = d.arr in 
  if d.len <> Array.length d_arr then 
    begin
      let newarr = unsafe_sub d_arr 0 d.len in 
      d.arr <- newarr
    end
let singleton v = 
  {
    len = 1 ; 
    arr = [|v|]
  }

let empty () =
  {
    len = 0;
    arr = [||];
  }

let is_empty d =
  d.len = 0

let reset d = 
  d.len <- 0; 
  d.arr <- [||]


(* For [to_*] operations, we should be careful to call {!Array.*} function 
   in case we operate on the whole array
*)
let to_list d =
  let rec loop (d_arr : elt array) idx accum =
    if idx < 0 then accum else loop d_arr (idx - 1) (Array.unsafe_get d_arr idx :: accum)
  in
  loop d.arr (d.len - 1) []


let of_list lst =
  let arr = Array.of_list lst in 
  { arr ; len = Array.length arr}


let to_array d = 
  unsafe_sub d.arr 0 d.len

let of_array src =
  {
    len = Array.length src;
    arr = Array.copy src;
    (* okay to call {!Array.copy}*)
  }
let of_sub_array arr off len = 
  { 
    len = len ; 
    arr = Array.sub arr off len  
  }  
let unsafe_internal_array v = v.arr  
(* we can not call {!Array.copy} *)
let copy src =
  let len = src.len in
  {
    len ;
    arr = unsafe_sub src.arr 0 len ;
  }

(* FIXME *)
let reverse_in_place src = 
  Ext_array.reverse_range src.arr 0 src.len 




(* {!Array.sub} is not enough for error checking, it 
   may contain some garbage
 *)
let sub (src : t) start len =
  let src_len = src.len in 
  if len < 0 || start > src_len - len then invalid_arg "Vec.sub"
  else 
  { len ; 
    arr = unsafe_sub src.arr start len }

let iter d  f = 
  let arr = d.arr in 
  for i = 0 to d.len - 1 do
    f (Array.unsafe_get arr i)
  done

let iteri d f =
  let arr = d.arr in
  for i = 0 to d.len - 1 do
    f i (Array.unsafe_get arr i)
  done

let iter_range d ~from ~to_ f =
  if from < 0 || to_ >= d.len then invalid_arg "Vec.iter_range"
  else 
    let d_arr = d.arr in 
    for i = from to to_ do 
      f  (Array.unsafe_get d_arr i)
    done

let iteri_range d ~from ~to_ f =
  if from < 0 || to_ >= d.len then invalid_arg "Vec.iteri_range"
  else 
    let d_arr = d.arr in 
    for i = from to to_ do 
      f i (Array.unsafe_get d_arr i)
    done

let map_into_array f src =
  let src_len = src.len in 
  let src_arr = src.arr in 
  if src_len = 0 then [||]
  else 
    let first_one = f (Array.unsafe_get src_arr 0) in 
    let arr = Array.make  src_len  first_one in
    for i = 1 to src_len - 1 do
      Array.unsafe_set arr i (f (Array.unsafe_get src_arr i))
    done;
    arr 
let map_into_list f src = 
  let src_len = src.len in 
  let src_arr = src.arr in 
  if src_len = 0 then []
  else 
    let acc = ref [] in         
    for i =  src_len - 1 downto 0 do
      acc := f (Array.unsafe_get src_arr i) :: !acc
    done;
    !acc

let mapi f src =
  let len = src.len in 
  if len = 0 then { len ; arr = [| |] }
  else 
    let src_arr = src.arr in 
    let arr = Array.make len (Array.unsafe_get src_arr 0) in
    for i = 1 to len - 1 do
      Array.unsafe_set arr i (f i (Array.unsafe_get src_arr i))
    done;
    {
      len ;
      arr ;
    }

let fold_left f x a =
  let rec loop a_len (a_arr : elt array) idx x =
    if idx >= a_len then x else 
      loop a_len a_arr (idx + 1) (f x (Array.unsafe_get a_arr idx))
  in
  loop a.len a.arr 0 x

let fold_right f a x =
  let rec loop (a_arr : elt array) idx x =
    if idx < 0 then x
    else loop a_arr (idx - 1) (f (Array.unsafe_get a_arr idx) x)
  in
  loop a.arr (a.len - 1) x

(**  
   [filter] and [inplace_filter]
*)
let filter f d =
  let new_d = copy d in 
  let new_d_arr = new_d.arr in 
  let d_arr = d.arr in
  let p = ref 0 in
  for i = 0 to d.len  - 1 do
    let x = Array.unsafe_get d_arr i in
    (* TODO: can be optimized for segments blit *)
    if f x  then
      begin
        Array.unsafe_set new_d_arr !p x;
        incr p;
      end;
  done;
  new_d.len <- !p;
  new_d 

let equal eq x y : bool = 
  if x.len <> y.len then false 
  else 
    let rec aux x_arr y_arr i =
      if i < 0 then true else  
      if eq (Array.unsafe_get x_arr i) (Array.unsafe_get y_arr i) then 
        aux x_arr y_arr (i - 1)
      else false in 
    aux x.arr y.arr (x.len - 1)

let get d i = 
  if i < 0 || i >= d.len then invalid_arg "Vec.get"
  else Array.unsafe_get d.arr i
let unsafe_get d i = Array.unsafe_get d.arr i 
let last d = 
  if d.len <= 0 then invalid_arg   "Vec.last"
  else Array.unsafe_get d.arr (d.len - 1)

let capacity d = Array.length d.arr

(* Attention can not use {!Array.exists} since the bound is not the same *)  
let exists p d = 
  let a = d.arr in 
  let n = d.len in   
  let rec loop i =
    if i = n then false
    else if p (Array.unsafe_get a i) then true
    else loop (succ i) in
  loop 0

let map f src =
  let src_len = src.len in 
  if src_len = 0 then { len = 0 ; arr = [||]}
  (* TODO: we may share the empty array 
     but sharing mutable state is very challenging, 
     the tricky part is to avoid mutating the immutable array,
     here it looks fine -- 
     invariant: whenever [.arr] mutated, make sure  it is not an empty array
     Actually no: since starting from an empty array 
     {[
       push v (* the address of v should not be changed *)
     ]}
  *)
  else 
    let src_arr = src.arr in 
    let first = f (Array.unsafe_get src_arr 0 ) in 
    let arr = Array.make  src_len first in
    for i = 1 to src_len - 1 do
      Array.unsafe_set arr i (f (Array.unsafe_get src_arr i))
    done;
    {
      len = src_len;
      arr = arr;
    }

let init len f =
  if len < 0 then invalid_arg  "Vec.init"
  else if len = 0 then { len = 0 ; arr = [||] }
  else 
    let first = f 0 in 
    let arr = Array.make len first in
    for i = 1 to len - 1 do
      Array.unsafe_set arr i (f i)
    done;
    {

      len ;
      arr 
    }



  let make initsize : t =
    if initsize < 0 then invalid_arg  "Vec.make" ;
    {

      len = 0;
      arr = Array.make  initsize null ;
    }



  let reserve (d : t ) s = 
    let d_len = d.len in 
    let d_arr = d.arr in 
    if s < d_len || s < Array.length d_arr then ()
    else 
      let new_capacity = min Sys.max_array_length s in 
      let new_d_arr = Array.make new_capacity null in 
       unsafe_blit d_arr 0 new_d_arr 0 d_len;
      d.arr <- new_d_arr 

  let push (d : t) v  =
    let d_len = d.len in
    let d_arr = d.arr in 
    let d_arr_len = Array.length d_arr in
    if d_arr_len = 0 then
      begin 
        d.len <- 1 ;
        d.arr <- [| v |]
      end
    else  
      begin 
        if d_len = d_arr_len then 
          begin
            if d_len >= Sys.max_array_length then 
              failwith "exceeds max_array_length";
            let new_capacity = min Sys.max_array_length d_len * 2 
            (* [d_len] can not be zero, so [*2] will enlarge   *)
            in
            let new_d_arr = Array.make new_capacity null in 
            d.arr <- new_d_arr;
             unsafe_blit d_arr 0 new_d_arr 0 d_len ;
          end;
        d.len <- d_len + 1;
        Array.unsafe_set d.arr d_len v
      end

(** delete element at offset [idx], will raise exception when have invalid input *)
  let delete (d : t) idx =
    let d_len = d.len in 
    if idx < 0 || idx >= d_len then invalid_arg "Vec.delete" ;
    let arr = d.arr in 
     unsafe_blit arr (idx + 1) arr idx  (d_len - idx - 1);
    let idx = d_len - 1 in 
    d.len <- idx
    
# 362 "ext/vec.cppo.ml"
(** pop the last element, a specialized version of [delete] *)
  let pop (d : t) = 
    let idx  = d.len - 1  in
    if idx < 0 then invalid_arg "Vec.pop";
    d.len <- idx
  
# 373 "ext/vec.cppo.ml"
(** pop and return the last element *)  
  let get_last_and_pop (d : t) = 
    let idx  = d.len - 1  in
    if idx < 0 then invalid_arg "Vec.get_last_and_pop";
    let last = Array.unsafe_get d.arr idx in 
    d.len <- idx 
    
# 384 "ext/vec.cppo.ml"
    ;
    last 

(** delete elements start from [idx] with length [len] *)
  let delete_range (d : t) idx len =
    let d_len = d.len in 
    if len < 0 || idx < 0 || idx + len > d_len then invalid_arg  "Vec.delete_range"  ;
    let arr = d.arr in 
     unsafe_blit arr (idx + len) arr idx (d_len  - idx - len);
    d.len <- d_len - len

# 402 "ext/vec.cppo.ml"
(** delete elements from [idx] with length [len] return the deleted elements as a new vec*)
  let get_and_delete_range (d : t) idx len : t = 
    let d_len = d.len in 
    if len < 0 || idx < 0 || idx + len > d_len then invalid_arg  "Vec.get_and_delete_range"  ;
    let arr = d.arr in 
    let value =  unsafe_sub arr idx len in
     unsafe_blit arr (idx + len) arr idx (d_len  - idx - len);
    d.len <- d_len - len; 
    
# 416 "ext/vec.cppo.ml"
    {len = len ; arr = value}


  (** Below are simple wrapper around normal Array operations *)  

  let clear (d : t ) =
    
# 428 "ext/vec.cppo.ml"
    d.len <- 0



  let inplace_filter f (d : t) : unit = 
    let d_arr = d.arr in     
    let d_len = d.len in
    let p = ref 0 in
    for i = 0 to d_len - 1 do 
      let x = Array.unsafe_get d_arr i in 
      if f x then 
        begin 
          let curr_p = !p in 
          (if curr_p <> i then 
             Array.unsafe_set d_arr curr_p x) ;
          incr p
        end
    done ;
    let last = !p  in 
    
# 448 "ext/vec.cppo.ml"
    d.len <-  last 
    (* INT , there is not need to reset it, since it will cause GC behavior *)

  
# 454 "ext/vec.cppo.ml"
  let inplace_filter_from start f (d : t) : unit = 
    if start < 0 then invalid_arg "Vec.inplace_filter_from"; 
    let d_arr = d.arr in     
    let d_len = d.len in
    let p = ref start in    
    for i = start to d_len - 1 do 
      let x = Array.unsafe_get d_arr i in 
      if f x then 
        begin 
          let curr_p = !p in 
          (if curr_p <> i then 
             Array.unsafe_set d_arr curr_p x) ;
          incr p
        end
    done ;
    let last = !p  in 
    
# 471 "ext/vec.cppo.ml"
    d.len <-  last 


# 477 "ext/vec.cppo.ml"
(** inplace filter the elements and accumulate the non-filtered elements *)
  let inplace_filter_with  f ~cb_no acc (d : t)  = 
    let d_arr = d.arr in     
    let p = ref 0 in
    let d_len = d.len in
    let acc = ref acc in 
    for i = 0 to d_len - 1 do 
      let x = Array.unsafe_get d_arr i in 
      if f x then 
        begin 
          let curr_p = !p in 
          (if curr_p <> i then 
             Array.unsafe_set d_arr curr_p x) ;
          incr p
        end
      else 
        acc := cb_no  x  !acc
    done ;
    let last = !p  in 
    
# 497 "ext/vec.cppo.ml"
    d.len <-  last 
    (* INT , there is not need to reset it, since it will cause GC behavior *)
    
# 502 "ext/vec.cppo.ml"
    ; !acc 




end
module Int_vec_util : sig 
#1 "int_vec_util.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


val mem : int -> Vec_int.t -> bool
end = struct
#1 "int_vec_util.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


let rec unsafe_mem_aux arr  i (key : int) bound = 
  if i <= bound then 
    if Array.unsafe_get arr i = (key : int) then 
      true 
    else unsafe_mem_aux arr (i + 1) key bound    
  else false 



let mem key (x : Vec_int.t) =
  let internal_array = Vec_int.unsafe_internal_array x in 
  let len = Vec_int.length x in 
  unsafe_mem_aux internal_array 0 key (len - 1)

end
module Ounit_int_vec_tests
= struct
#1 "ounit_int_vec_tests.ml"
let ((>::),
    (>:::)) = OUnit.((>::),(>:::))

let (=~) = OUnit.assert_equal
let suites = 
    __FILE__
    >:::
    [
        __LOC__ >:: begin fun _ -> 
            OUnit.assert_bool __LOC__
             (Int_vec_util.mem 3 (Vec_int.of_list [1;2;3]))
             ;
            OUnit.assert_bool __LOC__ 
             (not @@ Int_vec_util.mem 0 (Vec_int.of_list [1;2]) ); 
            
            let v = Vec_int.make 100 in 
            OUnit.assert_bool __LOC__ 
                (not @@ Int_vec_util.mem 0 v) ;
            Vec_int.push v 0;
            OUnit.assert_bool __LOC__ 
                (Int_vec_util.mem 0 v )
        end;

        __LOC__ >:: begin fun _ -> 
            let u = Vec_int.make 100 in 
            Vec_int.push u 1;
            OUnit.assert_bool __LOC__
            (not @@ Int_vec_util.mem 0 u );
            Vec_int.push u 0; 
            OUnit.assert_bool __LOC__
            (Int_vec_util.mem 0 u)
        end
    ]
end
module Ext_utf8 : sig 
#1 "ext_utf8.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

type byte =
  | Single of int
  | Cont of int
  | Leading of int * int
  | Invalid


val classify : char -> byte 

val follow : 
  string -> 
  int -> 
  int -> 
  int ->
  int * int 


(** 
   return [-1] if failed 
*)
val next :  string -> remaining:int -> int -> int 


exception Invalid_utf8 of string 


val decode_utf8_string : string -> int list
end = struct
#1 "ext_utf8.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

type byte =
  | Single of int
  | Cont of int
  | Leading of int * int
  | Invalid

(** [classify chr] returns the {!byte} corresponding to [chr] *)
let classify chr =
  let c = int_of_char chr in
  (* Classify byte according to leftmost 0 bit *)
  if c land 0b1000_0000 = 0 then Single c else
    (* c 0b0____*)
  if c land 0b0100_0000 = 0 then Cont (c land 0b0011_1111) else
    (* c 0b10___*)
  if c land 0b0010_0000 = 0 then Leading (1, c land 0b0001_1111) else
    (* c 0b110__*)
  if c land 0b0001_0000 = 0 then Leading (2, c land 0b0000_1111) else
    (* c 0b1110_ *)
  if c land 0b0000_1000 = 0 then Leading (3, c land 0b0000_0111) else
    (* c 0b1111_0___*)
  if c land 0b0000_0100 = 0 then Leading (4, c land 0b0000_0011) else
    (* c 0b1111_10__*)
  if c land 0b0000_0010 = 0 then Leading (5, c land 0b0000_0001)
  (* c 0b1111_110__ *)
  else Invalid

exception Invalid_utf8 of string 

(* when the first char is [Leading],
   TODO: need more error checking 
   when out of bond
*)
let rec follow s n (c : int) offset = 
  if n = 0 then (c, offset)
  else 
    begin match classify s.[offset+1] with
      | Cont cc -> follow s (n-1) ((c lsl 6) lor (cc land 0x3f)) (offset+1)
      | _ -> raise (Invalid_utf8 "Continuation byte expected")
    end


let rec next s ~remaining  offset = 
  if remaining = 0 then offset 
  else 
    begin match classify s.[offset+1] with
      | Cont _cc -> next s ~remaining:(remaining-1) (offset+1)
      | _ ->  -1 
      | exception _ ->  -1 (* it can happen when out of bound *)
    end




let decode_utf8_string s =
  let lst = ref [] in
  let add elem = lst := elem :: !lst in
  let rec  decode_utf8_cont s i s_len =
    if i = s_len  then ()
    else 
      begin 
        match classify s.[i] with
        | Single c -> 
          add c; decode_utf8_cont s (i+1) s_len
        | Cont _ -> raise (Invalid_utf8 "Unexpected continuation byte")
        | Leading (n, c) ->
          let (c', i') = follow s n c i in add c';
          decode_utf8_cont s (i' + 1) s_len
        | Invalid -> raise (Invalid_utf8 "Invalid byte")
      end
  in decode_utf8_cont s 0 (String.length s); 
  List.rev !lst


(** To decode {j||j} we need verify in the ast so that we have better error 
    location, then we do the decode later
*)  

(* let verify s loc = 
   assert false *)
end
module Ext_js_regex : sig 
#1 "ext_js_regex.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

(* This is a module that checks if js regex is valid or not *)

val js_regex_checker : string -> bool
end = struct
#1 "ext_js_regex.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


let check_from_end al =
  let rec aux l seen =
    match l with
    | [] -> false
    | (e::r) ->
      if e < 0 || e > 255 then false
      else (let c = Char.chr e in
            if c = '/' then true
            else (if Ext_list.exists seen (fun x -> x = c)  then false (* flag should not be repeated *)
                  else (if c = 'i' || c = 'g' || c = 'm' || c = 'y' || c ='u' then aux r (c::seen) 
                        else false)))
  in aux al []

let js_regex_checker s =
  match Ext_utf8.decode_utf8_string s with 
  | [] -> false 
  | 47 (* [Char.code '/' = 47 ]*)::tail -> 
    check_from_end (List.rev tail)       
  | _ :: _ -> false 
  | exception Ext_utf8.Invalid_utf8 _ -> false 

end
module Ounit_js_regex_checker_tests
= struct
#1 "ounit_js_regex_checker_tests.ml"
let ((>::),
    (>:::)) = OUnit.((>::),(>:::))

open Ext_js_regex

let suites =
    __FILE__
    >:::
    [
        "test_empty_string" >:: begin fun _ ->
        let b = js_regex_checker "" in
        OUnit.assert_equal b false
        end;
        "test_normal_regex" >:: begin fun _ ->
        let b = js_regex_checker "/abc/" in
        OUnit.assert_equal b true
        end;
        "test_wrong_regex_last" >:: begin fun _ ->
        let b = js_regex_checker "/abc" in 
        OUnit.assert_equal b false
        end;
        "test_regex_with_flag" >:: begin fun _ ->
        let b = js_regex_checker "/ss/ig" in
        OUnit.assert_equal b true
        end;
        "test_regex_with_invalid_flag" >:: begin fun _ ->
        let b = js_regex_checker "/ss/j" in
        OUnit.assert_equal b false
        end;
        "test_regex_invalid_regex" >:: begin fun _ ->
        let b = js_regex_checker "abc/i" in 
        OUnit.assert_equal b false
        end;
        "test_regex_empty_pattern" >:: begin fun _  ->
        let b = js_regex_checker "//" in 
        OUnit.assert_equal b true
        end;
        "test_regex_with_utf8" >:: begin fun _ ->
        let b = js_regex_checker "/😃/" in
        OUnit.assert_equal b true
        end;
        "test_regex_repeated_flags" >:: begin fun _ ->
        let b = js_regex_checker "/abc/gg" in
        OUnit.assert_equal b false
        end;
    ]
end
module Ext_json_types
= struct
#1 "ext_json_types.ml"
(* Copyright (C) 2015-2017 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

type loc = Lexing.position
type json_str = 
  { str : string ; loc : loc}

type json_flo  =
  { flo : string ; loc : loc}
type json_array =
  { content : t array ; 
    loc_start : loc ; 
    loc_end : loc ; 
  }

and json_map = 
  { map : t Map_string.t ; loc :  loc }
and t = 
  | True of loc 
  | False of loc 
  | Null of loc 
  | Flo of json_flo
  | Str of json_str
  | Arr  of json_array
  | Obj of json_map


end
module Ext_position : sig 
#1 "ext_position.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


type t = Lexing.position = {
  pos_fname : string ;
  pos_lnum : int ;
  pos_bol : int ;
  pos_cnum : int
}

(** [offset pos newpos]
    return a new position
    here [newpos] is zero based, the use case is that
    at position [pos], we get a string and Lexing from that string,
    therefore, we get a [newpos] and we need rebase it on top of 
    [pos]
*)
val offset : t -> t -> t 

val lexbuf_from_channel_with_fname:
  in_channel -> string -> 
  Lexing.lexbuf

val print : Format.formatter -> t -> unit 
end = struct
#1 "ext_position.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


type t = Lexing.position = {
  pos_fname : string ;
  pos_lnum : int ;
  pos_bol : int ;
  pos_cnum : int
}

let offset (x : t) (y:t) =
  {
    x with 
    pos_lnum =
      x.pos_lnum + y.pos_lnum - 1;
    pos_cnum = 
      x.pos_cnum + y.pos_cnum;
    pos_bol = 
      if y.pos_lnum = 1 then 
        x.pos_bol
      else x.pos_cnum + y.pos_bol
  }

let print fmt (pos : t) =
  Format.fprintf fmt "(line %d, column %d)" pos.pos_lnum (pos.pos_cnum - pos.pos_bol)



let lexbuf_from_channel_with_fname ic fname = 
  let x = Lexing.from_function (fun buf n -> input ic buf 0 n) in 
  let pos : t = {
    pos_fname = fname ; 
    pos_lnum = 1; 
    pos_bol = 0;
    pos_cnum = 0 (* copied from zero_pos*)
  } in 
  x.lex_start_p <- pos;
  x.lex_curr_p <- pos ; 
  x


end
module Ext_json : sig 
#1 "ext_json.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


type path = string list 
type status = 
  | No_path
  | Found of Ext_json_types.t 
  | Wrong_type of path 


type callback = 
  [
    `Str of (string -> unit) 
  | `Str_loc of (string -> Lexing.position -> unit)
  | `Flo of (string -> unit )
  | `Flo_loc of (string -> Lexing.position -> unit )
  | `Bool of (bool -> unit )
  | `Obj of (Ext_json_types.t Map_string.t -> unit)
  | `Arr of (Ext_json_types.t array -> unit )
  | `Arr_loc of 
      (Ext_json_types.t array -> Lexing.position -> Lexing.position -> unit)
  | `Null of (unit -> unit)
  | `Not_found of (unit -> unit)
  | `Id of (Ext_json_types.t -> unit )
  ]

val test:
  ?fail:(unit -> unit) ->
  string -> callback 
  -> Ext_json_types.t Map_string.t
  -> Ext_json_types.t Map_string.t


val loc_of : Ext_json_types.t -> Ext_position.t



end = struct
#1 "ext_json.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

type callback = 
  [
    `Str of (string -> unit) 
  | `Str_loc of (string -> Lexing.position -> unit)
  | `Flo of (string -> unit )
  | `Flo_loc of (string -> Lexing.position -> unit )
  | `Bool of (bool -> unit )
  | `Obj of (Ext_json_types.t Map_string.t -> unit)
  | `Arr of (Ext_json_types.t array -> unit )
  | `Arr_loc of (Ext_json_types.t array -> Lexing.position -> Lexing.position -> unit)
  | `Null of (unit -> unit)
  | `Not_found of (unit -> unit)
  | `Id of (Ext_json_types.t -> unit )
  ]


type path = string list 

type status = 
  | No_path
  | Found  of Ext_json_types.t 
  | Wrong_type of path 

let test   ?(fail=(fun () -> ())) key 
    (cb : callback) (m  : Ext_json_types.t Map_string.t)
  =
  begin match Map_string.find_exn m key, cb with 
    | exception Not_found  ->
      begin match cb with `Not_found f ->  f ()
                        | _ -> fail ()
      end      
    | True _, `Bool cb -> cb true
    | False _, `Bool cb  -> cb false 
    | Flo {flo = s} , `Flo cb  -> cb s 
    | Flo {flo = s; loc} , `Flo_loc cb  -> cb s loc
    | Obj {map = b} , `Obj cb -> cb b 
    | Arr {content}, `Arr cb -> cb content 
    | Arr {content; loc_start ; loc_end}, `Arr_loc cb -> 
      cb content  loc_start loc_end 
    | Null _, `Null cb  -> cb ()
    | Str {str = s }, `Str cb  -> cb s 
    | Str {str = s ; loc }, `Str_loc cb -> cb s loc 
    |  any  , `Id  cb -> cb any
    | _, _ -> fail () 
  end;
  m


let loc_of (x : Ext_json_types.t) =
  match x with
  | True p | False p | Null p -> p 
  | Str p -> p.loc 
  | Arr p -> p.loc_start
  | Obj p -> p.loc
  | Flo p -> p.loc





end
module Ext_json_noloc : sig 
#1 "ext_json_noloc.mli"
(* Copyright (C) 2017- Authors of ReScript
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


type t = private 
  | True 
  | False 
  | Null 
  | Flo of string 
  | Str of string
  | Arr of t array 
  | Obj of t Map_string.t

val true_  : t 
val false_ : t 
val null : t 
val str : string -> t 
val flo : string -> t 
val arr : t array -> t 
val obj : t Map_string.t -> t 
val kvs : (string * t) list -> t 

val to_string : t -> string 


val to_channel : out_channel -> t -> unit

val to_file : 
  string -> 
  t -> 
  unit 

end = struct
#1 "ext_json_noloc.ml"
(* Copyright (C) 2017- Hongbo Zhang, Authors of ReScript
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

(* This file is only used in bsb watcher searlization *)
type t = 
  | True 
  | False 
  | Null 
  | Flo of string 
  | Str of string
  | Arr of t array 
  | Obj of t Map_string.t


(** poor man's serialization *)
let naive_escaped (unmodified_input : string) : string =
  let n = ref 0 in
  let len = String.length unmodified_input in 
  for i = 0 to len - 1 do
    n := !n +
         (match String.unsafe_get unmodified_input i with
          | '\"' | '\\' | '\n' | '\t' | '\r' | '\b' -> 2
          | _ -> 1
         )
  done;
  if !n = len then  unmodified_input else begin
    let result = Bytes.create !n in
    n := 0;
    for i = 0 to len - 1 do
      let open Bytes in   
      begin match String.unsafe_get unmodified_input i with
        | ('\"' | '\\') as c ->
          unsafe_set result !n '\\'; incr n; unsafe_set result !n c
        | '\n' ->
          unsafe_set result !n '\\'; incr n; unsafe_set result !n 'n'
        | '\t' ->
          unsafe_set result !n '\\'; incr n; unsafe_set result !n 't'
        | '\r' ->
          unsafe_set result !n '\\'; incr n; unsafe_set result !n 'r'
        | '\b' ->
          unsafe_set result !n '\\'; incr n; unsafe_set result !n 'b'
        |  c -> unsafe_set result !n c      
      end;
      incr n
    done;
    Bytes.unsafe_to_string result
  end

let quot x = 
  "\"" ^ naive_escaped x ^ "\""
let true_ = True
let false_ = False
let null = Null 
let str s  = Str s 
let flo s = Flo s 
let arr s = Arr s 
let obj s = Obj s 
let kvs s = 
  Obj (Map_string.of_list s)

let rec encode_buf (x : t ) 
    (buf : Buffer.t) : unit =  
  let a str = Buffer.add_string buf str in 
  match x with 
  | Null  -> a "null"
  | Str s   -> a (quot s)
  | Flo  s -> 
    a s (* 
    since our parsing keep the original float representation, we just dump it as is, there is no cases like [nan] *)
  | Arr  content -> 
    begin match content with 
      | [||] -> a "[]"
      | _ -> 
        a "[ ";
        encode_buf
          (Array.unsafe_get content 0)
          buf ; 
        for i = 1 to Array.length content - 1 do 
          a " , ";
          encode_buf 
            (Array.unsafe_get content i)
            buf
        done;    
        a " ]"
    end
  | True  -> a "true"
  | False  -> a "false"
  | Obj map -> 
    if Map_string.is_empty map then 
      a "{}"
    else 
      begin  
        (*prerr_endline "WEIRD";
          prerr_endline (string_of_int @@ Map_string.cardinal map );   *)
        a "{ ";
        let _ : int =  Map_string.fold map 0 (fun  k v i -> 
            if i <> 0 then begin
              a " , " 
            end; 
            a (quot k);
            a " : ";
            encode_buf v buf ;
            i + 1 
          ) in 
        a " }"
      end


let to_string x  = 
  let buf = Buffer.create 1024 in 
  encode_buf x buf ;
  Buffer.contents buf 

let to_channel (oc : out_channel) x  = 
  let buf = Buffer.create 1024 in 
  encode_buf x buf ;
  Buffer.output_buffer oc buf   

let to_file name v =     
  let ochan = open_out_bin name in 
  to_channel ochan v ;
  close_out ochan
end
module Ext_json_parse : sig 
#1 "ext_json_parse.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

type error

val report_error : Format.formatter -> error -> unit 

exception Error of Lexing.position * Lexing.position * error

val parse_json_from_string : string -> Ext_json_types.t 

val parse_json_from_chan :
  string ->  in_channel -> Ext_json_types.t 

val parse_json_from_file  : string -> Ext_json_types.t


end = struct
#1 "ext_json_parse.ml"
# 1 "ext/ext_json_parse.mll"
 
type error =
  | Illegal_character of char
  | Unterminated_string
  | Unterminated_comment
  | Illegal_escape of string
  | Unexpected_token 
  | Expect_comma_or_rbracket
  | Expect_comma_or_rbrace
  | Expect_colon
  | Expect_string_or_rbrace 
  | Expect_eof 
  (* | Trailing_comma_in_obj *)
  (* | Trailing_comma_in_array *)


let fprintf  = Format.fprintf
let report_error ppf = function
  | Illegal_character c ->
      fprintf ppf "Illegal character (%s)" (Char.escaped c)
  | Illegal_escape s ->
      fprintf ppf "Illegal backslash escape in string or character (%s)" s
  | Unterminated_string -> 
      fprintf ppf "Unterminated_string"
  | Expect_comma_or_rbracket ->
    fprintf ppf "Expect_comma_or_rbracket"
  | Expect_comma_or_rbrace -> 
    fprintf ppf "Expect_comma_or_rbrace"
  | Expect_colon -> 
    fprintf ppf "Expect_colon"
  | Expect_string_or_rbrace  -> 
    fprintf ppf "Expect_string_or_rbrace"
  | Expect_eof  -> 
    fprintf ppf "Expect_eof"
  | Unexpected_token 
    ->
    fprintf ppf "Unexpected_token"
  (* | Trailing_comma_in_obj  *)
  (*   -> fprintf ppf "Trailing_comma_in_obj" *)
  (* | Trailing_comma_in_array  *)
  (*   -> fprintf ppf "Trailing_comma_in_array" *)
  | Unterminated_comment 
    -> fprintf ppf "Unterminated_comment"
         

exception Error of Lexing.position * Lexing.position * error


let () = 
  Printexc.register_printer
    (function x -> 
     match x with 
     | Error (loc_start,loc_end,error) -> 
       Some (Format.asprintf 
          "@[%a:@ %a@ -@ %a)@]" 
          report_error  error
          Ext_position.print loc_start
          Ext_position.print loc_end
       )

     | _ -> None
    )





type token = 
  | Comma
  | Eof
  | False
  | Lbrace
  | Lbracket
  | Null
  | Colon
  | Number of string
  | Rbrace
  | Rbracket
  | String of string
  | True   
  
let error  (lexbuf : Lexing.lexbuf) e = 
  raise (Error (lexbuf.lex_start_p, lexbuf.lex_curr_p, e))


let lexeme_len (x : Lexing.lexbuf) =
  x.lex_curr_pos - x.lex_start_pos

let update_loc ({ lex_curr_p; _ } as lexbuf : Lexing.lexbuf) diff =
  lexbuf.lex_curr_p <-
    {
      lex_curr_p with
      pos_lnum = lex_curr_p.pos_lnum + 1;
      pos_bol = lex_curr_p.pos_cnum - diff;
    }

let char_for_backslash = function
  | 'n' -> '\010'
  | 'r' -> '\013'
  | 'b' -> '\008'
  | 't' -> '\009'
  | c -> c

let dec_code c1 c2 c3 =
  100 * (Char.code c1 - 48) + 10 * (Char.code c2 - 48) + (Char.code c3 - 48)

let hex_code c1 c2 =
  let d1 = Char.code c1 in
  let val1 =
    if d1 >= 97 then d1 - 87
    else if d1 >= 65 then d1 - 55
    else d1 - 48 in
  let d2 = Char.code c2 in
  let val2 =
    if d2 >= 97 then d2 - 87
    else if d2 >= 65 then d2 - 55
    else d2 - 48 in
  val1 * 16 + val2

let lf = '\010'

# 124 "ext/ext_json_parse.ml"
let __ocaml_lex_tables = {
  Lexing.lex_base =
   "\000\000\239\255\240\255\241\255\000\000\025\000\011\000\244\255\
    \245\255\246\255\247\255\248\255\249\255\000\000\000\000\000\000\
    \041\000\001\000\254\255\005\000\005\000\253\255\001\000\002\000\
    \252\255\000\000\000\000\003\000\251\255\001\000\003\000\250\255\
    \079\000\089\000\099\000\121\000\131\000\141\000\153\000\163\000\
    \001\000\253\255\254\255\023\000\255\255\006\000\246\255\189\000\
    \248\255\215\000\255\255\249\255\249\000\181\000\252\255\009\000\
    \063\000\075\000\234\000\251\255\032\001\250\255";
  Lexing.lex_backtrk =
   "\255\255\255\255\255\255\255\255\013\000\013\000\016\000\255\255\
    \255\255\255\255\255\255\255\255\255\255\016\000\016\000\016\000\
    \016\000\016\000\255\255\000\000\012\000\255\255\255\255\255\255\
    \255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\
    \255\255\255\255\013\000\255\255\013\000\255\255\013\000\255\255\
    \255\255\255\255\255\255\001\000\255\255\255\255\255\255\008\000\
    \255\255\255\255\255\255\255\255\006\000\006\000\255\255\006\000\
    \001\000\002\000\255\255\255\255\255\255\255\255";
  Lexing.lex_default =
   "\001\000\000\000\000\000\000\000\255\255\255\255\255\255\000\000\
    \000\000\000\000\000\000\000\000\000\000\255\255\255\255\255\255\
    \255\255\255\255\000\000\255\255\020\000\000\000\255\255\255\255\
    \000\000\255\255\255\255\255\255\000\000\255\255\255\255\000\000\
    \255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\
    \042\000\000\000\000\000\255\255\000\000\047\000\000\000\047\000\
    \000\000\051\000\000\000\000\000\255\255\255\255\000\000\255\255\
    \255\255\255\255\255\255\000\000\255\255\000\000";
  Lexing.lex_trans =
   "\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\
    \000\000\019\000\018\000\018\000\019\000\017\000\019\000\255\255\
    \048\000\019\000\255\255\057\000\000\000\000\000\000\000\000\000\
    \000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\
    \019\000\000\000\003\000\000\000\000\000\019\000\000\000\000\000\
    \050\000\000\000\000\000\043\000\008\000\006\000\033\000\016\000\
    \004\000\005\000\005\000\005\000\005\000\005\000\005\000\005\000\
    \005\000\005\000\007\000\004\000\005\000\005\000\005\000\005\000\
    \005\000\005\000\005\000\005\000\005\000\032\000\044\000\033\000\
    \056\000\005\000\005\000\005\000\005\000\005\000\005\000\005\000\
    \005\000\005\000\005\000\021\000\057\000\000\000\000\000\000\000\
    \020\000\000\000\000\000\012\000\000\000\011\000\032\000\056\000\
    \000\000\025\000\049\000\000\000\000\000\032\000\014\000\024\000\
    \028\000\000\000\000\000\057\000\026\000\030\000\013\000\031\000\
    \000\000\000\000\022\000\027\000\015\000\029\000\023\000\000\000\
    \000\000\000\000\039\000\010\000\039\000\009\000\032\000\038\000\
    \038\000\038\000\038\000\038\000\038\000\038\000\038\000\038\000\
    \038\000\034\000\034\000\034\000\034\000\034\000\034\000\034\000\
    \034\000\034\000\034\000\034\000\034\000\034\000\034\000\034\000\
    \034\000\034\000\034\000\034\000\034\000\000\000\000\000\000\000\
    \000\000\000\000\000\000\000\000\037\000\000\000\037\000\000\000\
    \035\000\036\000\036\000\036\000\036\000\036\000\036\000\036\000\
    \036\000\036\000\036\000\036\000\036\000\036\000\036\000\036\000\
    \036\000\036\000\036\000\036\000\036\000\036\000\036\000\036\000\
    \036\000\036\000\036\000\036\000\036\000\036\000\036\000\255\255\
    \035\000\038\000\038\000\038\000\038\000\038\000\038\000\038\000\
    \038\000\038\000\038\000\038\000\038\000\038\000\038\000\038\000\
    \038\000\038\000\038\000\038\000\038\000\000\000\000\000\255\255\
    \000\000\056\000\000\000\000\000\055\000\058\000\058\000\058\000\
    \058\000\058\000\058\000\058\000\058\000\058\000\058\000\000\000\
    \000\000\000\000\000\000\000\000\000\000\000\000\000\000\054\000\
    \000\000\054\000\000\000\000\000\000\000\000\000\054\000\000\000\
    \002\000\041\000\000\000\000\000\000\000\255\255\046\000\053\000\
    \053\000\053\000\053\000\053\000\053\000\053\000\053\000\053\000\
    \053\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\
    \000\000\255\255\059\000\059\000\059\000\059\000\059\000\059\000\
    \059\000\059\000\059\000\059\000\000\000\000\000\000\000\000\000\
    \000\000\060\000\060\000\060\000\060\000\060\000\060\000\060\000\
    \060\000\060\000\060\000\054\000\000\000\000\000\000\000\000\000\
    \000\000\054\000\060\000\060\000\060\000\060\000\060\000\060\000\
    \000\000\000\000\000\000\000\000\000\000\054\000\000\000\000\000\
    \000\000\054\000\000\000\054\000\000\000\000\000\000\000\052\000\
    \061\000\061\000\061\000\061\000\061\000\061\000\061\000\061\000\
    \061\000\061\000\060\000\060\000\060\000\060\000\060\000\060\000\
    \000\000\061\000\061\000\061\000\061\000\061\000\061\000\000\000\
    \000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\
    \000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\
    \000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\
    \000\000\061\000\061\000\061\000\061\000\061\000\061\000\000\000\
    \000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\
    \000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\
    \000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\
    \000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\
    \000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\
    \000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\
    \000\000\000\000\000\000\000\000\000\000\255\255\000\000\000\000\
    \000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\
    \000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\
    \000\000\000\000\000\000\000\000\000\000\000\000\000\000\255\255\
    \000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\
    \000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\
    \000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\
    \000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\
    \000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\
    \000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\
    \000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\
    \000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\
    \000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\
    \000\000";
  Lexing.lex_check =
   "\255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\
    \255\255\000\000\000\000\017\000\000\000\000\000\019\000\020\000\
    \045\000\019\000\020\000\055\000\255\255\255\255\255\255\255\255\
    \255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\
    \000\000\255\255\000\000\255\255\255\255\019\000\255\255\255\255\
    \045\000\255\255\255\255\040\000\000\000\000\000\004\000\000\000\
    \000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\
    \000\000\000\000\000\000\006\000\006\000\006\000\006\000\006\000\
    \006\000\006\000\006\000\006\000\006\000\004\000\043\000\005\000\
    \056\000\005\000\005\000\005\000\005\000\005\000\005\000\005\000\
    \005\000\005\000\005\000\016\000\057\000\255\255\255\255\255\255\
    \016\000\255\255\255\255\000\000\255\255\000\000\005\000\056\000\
    \255\255\014\000\045\000\255\255\255\255\004\000\000\000\023\000\
    \027\000\255\255\255\255\057\000\025\000\029\000\000\000\030\000\
    \255\255\255\255\015\000\026\000\000\000\013\000\022\000\255\255\
    \255\255\255\255\032\000\000\000\032\000\000\000\005\000\032\000\
    \032\000\032\000\032\000\032\000\032\000\032\000\032\000\032\000\
    \032\000\033\000\033\000\033\000\033\000\033\000\033\000\033\000\
    \033\000\033\000\033\000\034\000\034\000\034\000\034\000\034\000\
    \034\000\034\000\034\000\034\000\034\000\255\255\255\255\255\255\
    \255\255\255\255\255\255\255\255\035\000\255\255\035\000\255\255\
    \034\000\035\000\035\000\035\000\035\000\035\000\035\000\035\000\
    \035\000\035\000\035\000\036\000\036\000\036\000\036\000\036\000\
    \036\000\036\000\036\000\036\000\036\000\037\000\037\000\037\000\
    \037\000\037\000\037\000\037\000\037\000\037\000\037\000\047\000\
    \034\000\038\000\038\000\038\000\038\000\038\000\038\000\038\000\
    \038\000\038\000\038\000\039\000\039\000\039\000\039\000\039\000\
    \039\000\039\000\039\000\039\000\039\000\255\255\255\255\047\000\
    \255\255\049\000\255\255\255\255\049\000\053\000\053\000\053\000\
    \053\000\053\000\053\000\053\000\053\000\053\000\053\000\255\255\
    \255\255\255\255\255\255\255\255\255\255\255\255\255\255\049\000\
    \255\255\049\000\255\255\255\255\255\255\255\255\049\000\255\255\
    \000\000\040\000\255\255\255\255\255\255\020\000\045\000\049\000\
    \049\000\049\000\049\000\049\000\049\000\049\000\049\000\049\000\
    \049\000\255\255\255\255\255\255\255\255\255\255\255\255\255\255\
    \255\255\047\000\058\000\058\000\058\000\058\000\058\000\058\000\
    \058\000\058\000\058\000\058\000\255\255\255\255\255\255\255\255\
    \255\255\052\000\052\000\052\000\052\000\052\000\052\000\052\000\
    \052\000\052\000\052\000\049\000\255\255\255\255\255\255\255\255\
    \255\255\049\000\052\000\052\000\052\000\052\000\052\000\052\000\
    \255\255\255\255\255\255\255\255\255\255\049\000\255\255\255\255\
    \255\255\049\000\255\255\049\000\255\255\255\255\255\255\049\000\
    \060\000\060\000\060\000\060\000\060\000\060\000\060\000\060\000\
    \060\000\060\000\052\000\052\000\052\000\052\000\052\000\052\000\
    \255\255\060\000\060\000\060\000\060\000\060\000\060\000\255\255\
    \255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\
    \255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\
    \255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\
    \255\255\060\000\060\000\060\000\060\000\060\000\060\000\255\255\
    \255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\
    \255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\
    \255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\
    \255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\
    \255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\
    \255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\
    \255\255\255\255\255\255\255\255\255\255\047\000\255\255\255\255\
    \255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\
    \255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\
    \255\255\255\255\255\255\255\255\255\255\255\255\255\255\049\000\
    \255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\
    \255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\
    \255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\
    \255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\
    \255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\
    \255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\
    \255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\
    \255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\
    \255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\255\
    \255\255";
  Lexing.lex_base_code =
   "";
  Lexing.lex_backtrk_code =
   "";
  Lexing.lex_default_code =
   "";
  Lexing.lex_trans_code =
   "";
  Lexing.lex_check_code =
   "";
  Lexing.lex_code =
   "";
}

let rec lex_json buf lexbuf =
   __ocaml_lex_lex_json_rec buf lexbuf 0
and __ocaml_lex_lex_json_rec buf lexbuf __ocaml_lex_state =
  match Lexing.engine __ocaml_lex_tables __ocaml_lex_state lexbuf with
      | 0 ->
# 142 "ext/ext_json_parse.mll"
          ( lex_json buf lexbuf)
# 314 "ext/ext_json_parse.ml"

  | 1 ->
# 143 "ext/ext_json_parse.mll"
                   ( 
    update_loc lexbuf 0;
    lex_json buf  lexbuf
  )
# 322 "ext/ext_json_parse.ml"

  | 2 ->
# 147 "ext/ext_json_parse.mll"
                ( comment buf lexbuf)
# 327 "ext/ext_json_parse.ml"

  | 3 ->
# 148 "ext/ext_json_parse.mll"
         ( True)
# 332 "ext/ext_json_parse.ml"

  | 4 ->
# 149 "ext/ext_json_parse.mll"
          (False)
# 337 "ext/ext_json_parse.ml"

  | 5 ->
# 150 "ext/ext_json_parse.mll"
         (Null)
# 342 "ext/ext_json_parse.ml"

  | 6 ->
# 151 "ext/ext_json_parse.mll"
       (Lbracket)
# 347 "ext/ext_json_parse.ml"

  | 7 ->
# 152 "ext/ext_json_parse.mll"
       (Rbracket)
# 352 "ext/ext_json_parse.ml"

  | 8 ->
# 153 "ext/ext_json_parse.mll"
       (Lbrace)
# 357 "ext/ext_json_parse.ml"

  | 9 ->
# 154 "ext/ext_json_parse.mll"
       (Rbrace)
# 362 "ext/ext_json_parse.ml"

  | 10 ->
# 155 "ext/ext_json_parse.mll"
       (Comma)
# 367 "ext/ext_json_parse.ml"

  | 11 ->
# 156 "ext/ext_json_parse.mll"
        (Colon)
# 372 "ext/ext_json_parse.ml"

  | 12 ->
# 157 "ext/ext_json_parse.mll"
                      (lex_json buf lexbuf)
# 377 "ext/ext_json_parse.ml"

  | 13 ->
# 159 "ext/ext_json_parse.mll"
         ( Number (Lexing.lexeme lexbuf))
# 382 "ext/ext_json_parse.ml"

  | 14 ->
# 161 "ext/ext_json_parse.mll"
      (
  let pos = Lexing.lexeme_start_p lexbuf in
  scan_string buf pos lexbuf;
  let content = (Buffer.contents  buf) in 
  Buffer.clear buf ;
  String content 
)
# 393 "ext/ext_json_parse.ml"

  | 15 ->
# 168 "ext/ext_json_parse.mll"
       (Eof )
# 398 "ext/ext_json_parse.ml"

  | 16 ->
let
# 169 "ext/ext_json_parse.mll"
       c
# 404 "ext/ext_json_parse.ml"
= Lexing.sub_lexeme_char lexbuf lexbuf.Lexing.lex_start_pos in
# 169 "ext/ext_json_parse.mll"
          ( error lexbuf (Illegal_character c ))
# 408 "ext/ext_json_parse.ml"

  | __ocaml_lex_state -> lexbuf.Lexing.refill_buff lexbuf;
      __ocaml_lex_lex_json_rec buf lexbuf __ocaml_lex_state

and comment buf lexbuf =
   __ocaml_lex_comment_rec buf lexbuf 40
and __ocaml_lex_comment_rec buf lexbuf __ocaml_lex_state =
  match Lexing.engine __ocaml_lex_tables __ocaml_lex_state lexbuf with
      | 0 ->
# 171 "ext/ext_json_parse.mll"
              (lex_json buf lexbuf)
# 420 "ext/ext_json_parse.ml"

  | 1 ->
# 172 "ext/ext_json_parse.mll"
     (comment buf lexbuf)
# 425 "ext/ext_json_parse.ml"

  | 2 ->
# 173 "ext/ext_json_parse.mll"
       (error lexbuf Unterminated_comment)
# 430 "ext/ext_json_parse.ml"

  | __ocaml_lex_state -> lexbuf.Lexing.refill_buff lexbuf;
      __ocaml_lex_comment_rec buf lexbuf __ocaml_lex_state

and scan_string buf start lexbuf =
   __ocaml_lex_scan_string_rec buf start lexbuf 45
and __ocaml_lex_scan_string_rec buf start lexbuf __ocaml_lex_state =
  match Lexing.engine __ocaml_lex_tables __ocaml_lex_state lexbuf with
      | 0 ->
# 177 "ext/ext_json_parse.mll"
      ( () )
# 442 "ext/ext_json_parse.ml"

  | 1 ->
# 179 "ext/ext_json_parse.mll"
  (
        let len = lexeme_len lexbuf - 2 in
        update_loc lexbuf len;

        scan_string buf start lexbuf
      )
# 452 "ext/ext_json_parse.ml"

  | 2 ->
# 186 "ext/ext_json_parse.mll"
      (
        let len = lexeme_len lexbuf - 3 in
        update_loc lexbuf len;
        scan_string buf start lexbuf
      )
# 461 "ext/ext_json_parse.ml"

  | 3 ->
let
# 191 "ext/ext_json_parse.mll"
                                               c
# 467 "ext/ext_json_parse.ml"
= Lexing.sub_lexeme_char lexbuf (lexbuf.Lexing.lex_start_pos + 1) in
# 192 "ext/ext_json_parse.mll"
      (
        Buffer.add_char buf (char_for_backslash c);
        scan_string buf start lexbuf
      )
# 474 "ext/ext_json_parse.ml"

  | 4 ->
let
# 196 "ext/ext_json_parse.mll"
                 c1
# 480 "ext/ext_json_parse.ml"
= Lexing.sub_lexeme_char lexbuf (lexbuf.Lexing.lex_start_pos + 1)
and
# 196 "ext/ext_json_parse.mll"
                               c2
# 485 "ext/ext_json_parse.ml"
= Lexing.sub_lexeme_char lexbuf (lexbuf.Lexing.lex_start_pos + 2)
and
# 196 "ext/ext_json_parse.mll"
                                             c3
# 490 "ext/ext_json_parse.ml"
= Lexing.sub_lexeme_char lexbuf (lexbuf.Lexing.lex_start_pos + 3)
and
# 196 "ext/ext_json_parse.mll"
                                                    s
# 495 "ext/ext_json_parse.ml"
= Lexing.sub_lexeme lexbuf lexbuf.Lexing.lex_start_pos (lexbuf.Lexing.lex_start_pos + 4) in
# 197 "ext/ext_json_parse.mll"
      (
        let v = dec_code c1 c2 c3 in
        if v > 255 then
          error lexbuf (Illegal_escape s) ;
        Buffer.add_char buf (Char.chr v);

        scan_string buf start lexbuf
      )
# 506 "ext/ext_json_parse.ml"

  | 5 ->
let
# 205 "ext/ext_json_parse.mll"
                        c1
# 512 "ext/ext_json_parse.ml"
= Lexing.sub_lexeme_char lexbuf (lexbuf.Lexing.lex_start_pos + 2)
and
# 205 "ext/ext_json_parse.mll"
                                         c2
# 517 "ext/ext_json_parse.ml"
= Lexing.sub_lexeme_char lexbuf (lexbuf.Lexing.lex_start_pos + 3) in
# 206 "ext/ext_json_parse.mll"
      (
        let v = hex_code c1 c2 in
        Buffer.add_char buf (Char.chr v);

        scan_string buf start lexbuf
      )
# 526 "ext/ext_json_parse.ml"

  | 6 ->
let
# 212 "ext/ext_json_parse.mll"
             c
# 532 "ext/ext_json_parse.ml"
= Lexing.sub_lexeme_char lexbuf (lexbuf.Lexing.lex_start_pos + 1) in
# 213 "ext/ext_json_parse.mll"
      (
        Buffer.add_char buf '\\';
        Buffer.add_char buf c;

        scan_string buf start lexbuf
      )
# 541 "ext/ext_json_parse.ml"

  | 7 ->
# 220 "ext/ext_json_parse.mll"
      (
        update_loc lexbuf 0;
        Buffer.add_char buf lf;

        scan_string buf start lexbuf
      )
# 551 "ext/ext_json_parse.ml"

  | 8 ->
# 227 "ext/ext_json_parse.mll"
      (
        let ofs = lexbuf.lex_start_pos in
        let len = lexbuf.lex_curr_pos - ofs in
        Buffer.add_subbytes buf lexbuf.lex_buffer ofs len;

        scan_string buf start lexbuf
      )
# 562 "ext/ext_json_parse.ml"

  | 9 ->
# 235 "ext/ext_json_parse.mll"
      (
        error lexbuf Unterminated_string
      )
# 569 "ext/ext_json_parse.ml"

  | __ocaml_lex_state -> lexbuf.Lexing.refill_buff lexbuf;
      __ocaml_lex_scan_string_rec buf start lexbuf __ocaml_lex_state

;;

# 239 "ext/ext_json_parse.mll"
 






let  parse_json lexbuf =
  let buf = Buffer.create 64 in 
  let look_ahead = ref None in
  let token () : token = 
    match !look_ahead with 
    | None ->  
      lex_json buf lexbuf 
    | Some x -> 
      look_ahead := None ;
      x 
  in
  let push e = look_ahead := Some e in 
  let rec json (lexbuf : Lexing.lexbuf) : Ext_json_types.t = 
    match token () with 
    | True -> True lexbuf.lex_start_p
    | False -> False lexbuf.lex_start_p
    | Null -> Null lexbuf.lex_start_p
    | Number s ->  Flo {flo = s; loc = lexbuf.lex_start_p}  
    | String s -> Str { str = s; loc =    lexbuf.lex_start_p}
    | Lbracket -> parse_array  lexbuf.lex_start_p lexbuf.lex_curr_p [] lexbuf
    | Lbrace -> parse_map lexbuf.lex_start_p Map_string.empty lexbuf
    |  _ -> error lexbuf Unexpected_token

(* Note if we remove [trailing_comma] support 
    we should report errors (actually more work), for example 
    {[
    match token () with 
    | Rbracket ->
      if trailing_comma then
        error lexbuf Trailing_comma_in_array
      else
    ]} 
    {[
    match token () with 
    | Rbrace -> 
      if trailing_comma then
        error lexbuf Trailing_comma_in_obj
      else

    ]}   
 *)
  and parse_array   loc_start loc_finish acc lexbuf 
    : Ext_json_types.t =
    match token () with 
    | Rbracket ->
        Arr {loc_start ; content = Ext_array.reverse_of_list acc ; 
              loc_end = lexbuf.lex_curr_p }
    | x -> 
      push x ;
      let new_one = json lexbuf in 
      begin match token ()  with 
      | Comma -> 
          parse_array  loc_start loc_finish (new_one :: acc) lexbuf 
      | Rbracket 
        -> Arr {content = (Ext_array.reverse_of_list (new_one::acc));
                     loc_start ; 
                     loc_end = lexbuf.lex_curr_p }
      | _ -> 
        error lexbuf Expect_comma_or_rbracket
      end
  and parse_map loc_start  acc lexbuf : Ext_json_types.t = 
    match token () with 
    | Rbrace -> 
        Obj { map = acc ; loc = loc_start}
    | String key -> 
      begin match token () with 
      | Colon ->
        let value = json lexbuf in
        begin match token () with 
        | Rbrace -> Obj {map = Map_string.add acc key value  ; loc = loc_start}
        | Comma -> 
          parse_map loc_start  (Map_string.add acc key value ) lexbuf 
        | _ -> error lexbuf Expect_comma_or_rbrace
        end
      | _ -> error lexbuf Expect_colon
      end
    | _ -> error lexbuf Expect_string_or_rbrace
  in 
  let v = json lexbuf in 
  match token () with 
  | Eof -> v 
  | _ -> error lexbuf Expect_eof

let parse_json_from_string s = 
  parse_json (Lexing.from_string s )

let parse_json_from_chan fname in_chan = 
  let lexbuf = 
    Ext_position.lexbuf_from_channel_with_fname
    in_chan fname in 
  parse_json lexbuf 

let parse_json_from_file s = 
  let in_chan = open_in s in 
  let lexbuf = 
    Ext_position.lexbuf_from_channel_with_fname
    in_chan s in 
  match parse_json lexbuf with 
  | exception e -> close_in in_chan ; raise e
  | v  -> close_in in_chan;  v





# 689 "ext/ext_json_parse.ml"

end
module Ounit_json_tests
= struct
#1 "ounit_json_tests.ml"

let ((>::),
     (>:::)) = OUnit.((>::),(>:::))
type t = Ext_json_noloc.t     
let rec equal 
    (x : t)
    (y : t) = 
  match x with 
  | Null  -> (* [%p? Null _ ] *)
    begin match y with
      | Null  -> true
      | _ -> false end
  | Str str  -> 
    begin match y with 
      | Str str2 -> str = str2
      | _ -> false end
  | Flo flo 
    ->
    begin match y with
      |  Flo flo2 -> 
        flo = flo2 
      | _ -> false
    end
  | True  -> 
    begin match y with 
      | True  -> true 
      | _ -> false 
    end
  | False  -> 
    begin match y with 
      | False  -> true 
      | _ -> false 
    end     
  | Arr content 
    -> 
    begin match y with 
      | Arr content2
        ->
        Ext_array.for_all2_no_exn content content2 equal 
      | _ -> false 
    end

  | Obj map -> 
    begin match y with 
      | Obj map2 -> 
        let xs = Map_string.bindings map 
                 |> List.sort (fun (a,_) (b,_) -> compare a b) in 
        let ys = Map_string.bindings map2 
                 |> List.sort (fun (a,_) (b,_) -> compare a b) in 
        Ext_list.for_all2_no_exn xs ys (fun (k0,v0) (k1,v1) -> k0=k1 && equal v0 v1)
      | _ -> false 
    end 


open Ext_json_parse
let (|?)  m (key, cb) =
  m  |> Ext_json.test key cb 

let rec strip (x : Ext_json_types.t) : Ext_json_noloc.t = 
  let open Ext_json_noloc in 
  match x with 
  | True _ -> true_
  | False _ -> false_
  | Null _ -> null
  | Flo {flo = s} -> flo s 
  | Str {str = s} -> str s 
  | Arr {content } -> arr (Array.map strip content)
  | Obj {map} -> 
    obj (Map_string.map map strip)

let id_parsing_serializing x = 
  let normal_s = 
    Ext_json_noloc.to_string 
      @@ strip 
      @@ Ext_json_parse.parse_json_from_string x  
  in 
  let normal_ss = 
    Ext_json_noloc.to_string 
    @@ strip 
    @@ Ext_json_parse.parse_json_from_string normal_s
  in 
  if normal_s <> normal_ss then 
    begin 
      prerr_endline "ERROR";
      prerr_endline normal_s ;
      prerr_endline normal_ss ;
    end;
  OUnit.assert_equal ~cmp:(fun (x:string) y -> x = y) normal_s normal_ss

let id_parsing_x2 x = 
  let stru = Ext_json_parse.parse_json_from_string x |> strip in 
  let normal_s = Ext_json_noloc.to_string stru in 
  let normal_ss = strip (Ext_json_parse.parse_json_from_string normal_s) in 
  if equal stru normal_ss then 
    true
  else begin 
    prerr_endline "ERROR";
    prerr_endline normal_s;
    Format.fprintf Format.err_formatter 
    "%a@.%a@." Ext_obj.pp_any stru Ext_obj.pp_any normal_ss; 
    
    prerr_endline (Ext_json_noloc.to_string normal_ss);
    false
  end  

let test_data = 
  [{|
      {}
      |};
   {| [] |};
   {| [1,2,3]|};
   {| ["x", "y", 1,2,3 ]|};
   {| { "x" :  3, "y" : "x", "z" : [1,2,3, "x"] }|};
   {| {"x " : true , "y" : false , "z\"" : 1} |}
  ] 
exception Parse_error 
let suites = 
  __FILE__ 
  >:::
  [

    __LOC__ >:: begin fun _ -> 
      List.iter id_parsing_serializing test_data
    end;

    __LOC__ >:: begin fun _ -> 
      List.iteri (fun i x -> OUnit.assert_bool (__LOC__ ^ string_of_int i ) (id_parsing_x2 x)) test_data
    end;
    "empty_json" >:: begin fun _ -> 
      let v =parse_json_from_string "{}" in
      match v with 
      | Obj {map = v} -> OUnit.assert_equal (Map_string.is_empty v ) true
      | _ -> OUnit.assert_failure "should be empty"
    end
    ;
    "empty_arr" >:: begin fun _ -> 
      let v =parse_json_from_string "[]" in
      match v with 
      | Arr {content = [||]} -> ()
      | _ -> OUnit.assert_failure "should be empty"
    end
    ;
    "empty trails" >:: begin fun _ -> 
      (OUnit.assert_raises Parse_error @@ fun _ -> 
       try parse_json_from_string {| [,]|} with _ -> raise Parse_error);
      OUnit.assert_raises Parse_error @@ fun _ -> 
      try parse_json_from_string {| {,}|} with _ -> raise Parse_error
    end;
    "two trails" >:: begin fun _ -> 
      (OUnit.assert_raises Parse_error @@ fun _ -> 
       try parse_json_from_string {| [1,2,,]|} with _ -> raise Parse_error);
      (OUnit.assert_raises Parse_error @@ fun _ -> 
       try parse_json_from_string {| { "x": 3, ,}|} with _ -> raise Parse_error)
    end;

    "two trails fail" >:: begin fun _ -> 
      (OUnit.assert_raises Parse_error @@ fun _ -> 
       try parse_json_from_string {| { "x": 3, 2 ,}|} with _ -> raise Parse_error)
    end;

    "trail comma obj" >:: begin fun _ -> 
      let v =  parse_json_from_string {| { "x" : 3 , }|} in 
      let v1 =  parse_json_from_string {| { "x" : 3 , }|} in 
      let test (v : Ext_json_types.t)  = 
        match v with 
        | Obj {map = v} -> 
          v
          |? ("x" , `Flo (fun x -> OUnit.assert_equal x "3"))
          |> ignore 
        | _ -> OUnit.assert_failure "trail comma" in 
      test v ;
      test v1 
    end
    ;
    "trail comma arr" >:: begin fun _ -> 
      let v = parse_json_from_string {| [ 1, 3, ]|} in
      let v1 = parse_json_from_string {| [ 1, 3 ]|} in
      let test (v : Ext_json_types.t) = 
        match v with 
        | Arr { content = [| Flo {flo = "1"} ; Flo { flo = "3"} |] } -> ()
        | _ -> OUnit.assert_failure "trailing comma array" in 
      test v ;
      test v1
    end
  ]

end
module Ounit_list_test
= struct
#1 "ounit_list_test.ml"
let ((>::),
     (>:::)) = OUnit.((>::),(>:::))

let (=~) = OUnit.assert_equal
let printer_int_list = fun xs -> Format.asprintf "%a" 
      (Format.pp_print_list  Format.pp_print_int
      ~pp_sep:Format.pp_print_space 
      ) xs 
let suites = 
  __FILE__
  >:::
  [
    __LOC__ >:: begin fun _ -> 
      OUnit.assert_equal
        (Ext_list.flat_map [1;2] (fun x -> [x;x]) ) [1;1;2;2] 
    end;
    __LOC__ >:: begin fun _ -> 
      OUnit.assert_equal
        (Ext_list.flat_map_append 
           [1;2] [3;4] (fun x -> [x;x]) ) [1;1;2;2;3;4] 
    end;
    __LOC__ >:: begin fun _ -> 
    
     let (=~)  = OUnit.assert_equal ~printer:printer_int_list in 
     (Ext_list.flat_map  [] (fun x -> [succ x ])) =~ [];
     (Ext_list.flat_map [1] (fun x -> [x;succ x ]) ) =~ [1;2];
     (Ext_list.flat_map [1;2] (fun x -> [x;succ x ])) =~ [1;2;2;3];
     (Ext_list.flat_map [1;2;3] (fun x -> [x;succ x ]) ) =~ [1;2;2;3;3;4]
    end
    ;
    __LOC__ >:: begin fun _ ->
      OUnit.assert_equal 
      (Ext_list.stable_group 
        [1;2;3;4;3] (=)
      )
      ([[1];[2];[4];[3;3]])
    end
    ;
    __LOC__ >:: begin fun _ -> 
      let (=~)  = OUnit.assert_equal ~printer:printer_int_list in 
      let f b _v = if b then 1 else 0 in 
      Ext_list.map_last  []  f =~ [];
      Ext_list.map_last [0] f =~ [1];
      Ext_list.map_last [0;0] f =~ [0;1];
      Ext_list.map_last [0;0;0] f =~ [0;0;1];
      Ext_list.map_last [0;0;0;0] f =~ [0;0;0;1];
      Ext_list.map_last [0;0;0;0;0] f =~ [0;0;0;0;1];
      Ext_list.map_last [0;0;0;0;0;0] f =~ [0;0;0;0;0;1];
      Ext_list.map_last [0;0;0;0;0;0;0] f =~ [0;0;0;0;0;0;1];
    end
    ;
    __LOC__ >:: begin fun _ ->
      OUnit.assert_equal (
        Ext_list.flat_map_append           
          [1;2] [false;false] 
          (fun x -> if x mod 2 = 0 then [true] else [])
      )  [true;false;false]
    end;
    __LOC__ >:: begin fun _ -> 
      OUnit.assert_equal (
        Ext_list.map_append  
          [0;1;2] 
          ["1";"2";"3"]
          (fun x -> string_of_int x) 
      )
        ["0";"1";"2"; "1";"2";"3"]
    end;

    __LOC__ >:: begin fun _ -> 
      let (a,b) = Ext_list.split_at [1;2;3;4;5;6]  3 in 
      OUnit.assert_equal (a,b)
        ([1;2;3],[4;5;6]);
      OUnit.assert_equal (Ext_list.split_at  [1] 1)
        ([1],[])  ;
      OUnit.assert_equal (Ext_list.split_at [1;2;3]  2 )
        ([1;2],[3])  
    end;
    __LOC__ >:: begin fun _ -> 
      let printer = fun (a,b) -> 
        Format.asprintf "([%a],%d)"
          (Format.pp_print_list Format.pp_print_int ) a  
          b 
      in 
      let (=~) = OUnit.assert_equal ~printer in 
      (Ext_list.split_at_last [1;2;3])
      =~ ([1;2],3);
      (Ext_list.split_at_last [1;2;3;4;5;6;7;8])
      =~
      ([1;2;3;4;5;6;7],8);
      (Ext_list.split_at_last [1;2;3;4;5;6;7;])
      =~
      ([1;2;3;4;5;6],7)
    end;
    __LOC__ >:: begin fun _ -> 
      OUnit.assert_equal (Ext_list.assoc_by_int  [2,"x"; 3,"y"; 1, "z"] 1 None) "z"
    end;
    __LOC__ >:: begin fun _ -> 
      OUnit.assert_raise_any
        (fun _ -> Ext_list.assoc_by_int [2,"x"; 3,"y"; 1, "z"] 11 None )
    end ;
    __LOC__ >:: begin fun _ -> 
      OUnit.assert_equal
        (Ext_list.length_compare [0;0;0] 3) `Eq ;
      OUnit.assert_equal
        (Ext_list.length_compare [0;0;0] 1) `Gt ;   
      OUnit.assert_equal
        (Ext_list.length_compare [0;0;0] 4) `Lt ;   
      OUnit.assert_equal
        (Ext_list.length_compare [] (-1)) `Gt ;   
      OUnit.assert_equal
        (Ext_list.length_compare [] (0)) `Eq ;          
    end;
    __LOC__ >:: begin fun _ -> 
      OUnit.assert_bool __LOC__ 
        (Ext_list.length_larger_than_n [1;2] [1] 1 );
      OUnit.assert_bool __LOC__ 
        (Ext_list.length_larger_than_n [1;2] [1;2] 0);
      OUnit.assert_bool __LOC__ 
        (Ext_list.length_larger_than_n [1;2] [] 2)

    end;

    __LOC__ >:: begin fun _ ->
      OUnit.assert_bool __LOC__
        (Ext_list.length_ge [1;2;3] 3 );
      OUnit.assert_bool __LOC__
        (Ext_list.length_ge [] 0 );
      OUnit.assert_bool __LOC__
        (not (Ext_list.length_ge [] 1 ));

    end;

    __LOC__ >:: begin fun _ ->
      let (=~) = OUnit.assert_equal in 

      let f p x = Ext_list.exclude_with_val x p  in 
      f  (fun x -> x = 1) [1;2;3] =~ (Some [2;3]);
      f (fun x -> x = 4) [1;2;3] =~ (None);
      f (fun x -> x = 2) [1;2;3;2] =~ (Some [1;3]);
      f (fun x -> x = 2) [1;2;2;3;2] =~ (Some [1;3]);
      f (fun x -> x = 2) [2;2;2] =~ (Some []);
      f (fun x -> x = 3) [2;2;2] =~ (None)
    end ;

  ]
end
module Map_int : sig 
#1 "map_int.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)








include Map_gen.S with type key = int

end = struct
#1 "map_int.ml"

# 2 "ext/map.cppo.ml"
(* we don't create [map_poly], since some operations require raise an exception which carries [key] *)

# 9 "ext/map.cppo.ml"
type key = int
let compare_key = Ext_int.compare
let [@inline] eq_key (x : key) y = x = y
    
# 19 "ext/map.cppo.ml"
    (* let [@inline] (=) (a : int) b = a = b *)
type + 'a t = (key,'a) Map_gen.t

let empty = Map_gen.empty 
let is_empty = Map_gen.is_empty
let iter = Map_gen.iter
let fold = Map_gen.fold
let for_all = Map_gen.for_all 
let exists = Map_gen.exists 
let singleton = Map_gen.singleton 
let cardinal = Map_gen.cardinal
let bindings = Map_gen.bindings
let to_sorted_array = Map_gen.to_sorted_array
let to_sorted_array_with_f = Map_gen.to_sorted_array_with_f
let keys = Map_gen.keys



let map = Map_gen.map 
let mapi = Map_gen.mapi
let bal = Map_gen.bal 
let height = Map_gen.height 


let rec add (tree : _ Map_gen.t as 'a) x data  : 'a = match tree with 
  | Empty ->
    singleton x data
  | Leaf {k;v} ->
    let c = compare_key x k in 
    if c = 0 then singleton x data else
    if c < 0 then 
      Map_gen.unsafe_two_elements x data k v 
    else 
      Map_gen.unsafe_two_elements k v x data  
  | Node {l; k ; v ; r; h} ->
    let c = compare_key x k in
    if c = 0 then
      Map_gen.unsafe_node x data l r h (* at least need update data *)
    else if c < 0 then
      bal (add l x data ) k v r
    else
      bal l k v (add r x data )


let rec adjust (tree : _ Map_gen.t as 'a) x replace  : 'a = 
  match tree with 
  | Empty ->
    singleton x (replace None)
  | Leaf {k ; v} -> 
    let c = compare_key x k in 
    if c = 0 then singleton x (replace (Some v)) else 
    if c < 0 then 
      Map_gen.unsafe_two_elements x (replace None) k v   
    else
      Map_gen.unsafe_two_elements k v x (replace None)   
  | Node ({l; k ; r} as tree) ->
    let c = compare_key x k in
    if c = 0 then
      Map_gen.unsafe_node x (replace  (Some tree.v)) l r tree.h
    else if c < 0 then
      bal (adjust l x  replace ) k tree.v r
    else
      bal l k tree.v (adjust r x  replace )


let rec find_exn (tree : _ Map_gen.t ) x = match tree with 
  | Empty ->
    raise Not_found
  | Leaf leaf -> 
    if eq_key x leaf.k then leaf.v else raise Not_found  
  | Node tree ->
    let c = compare_key x tree.k in
    if c = 0 then tree.v
    else find_exn (if c < 0 then tree.l else tree.r) x

let rec find_opt (tree : _ Map_gen.t ) x = match tree with 
  | Empty -> None 
  | Leaf leaf -> 
    if eq_key x leaf.k then Some leaf.v else None
  | Node tree ->
    let c = compare_key x tree.k in
    if c = 0 then Some tree.v
    else find_opt (if c < 0 then tree.l else tree.r) x

let rec find_default (tree : _ Map_gen.t ) x  default     = match tree with 
  | Empty -> default  
  | Leaf leaf -> 
    if eq_key x leaf.k then  leaf.v else default
  | Node tree ->
    let c = compare_key x tree.k in
    if c = 0 then tree.v
    else find_default (if c < 0 then tree.l else tree.r) x default

let rec mem (tree : _ Map_gen.t )  x= match tree with 
  | Empty ->
    false
  | Leaf leaf -> eq_key x leaf.k 
  | Node{l; k ;  r} ->
    let c = compare_key x k in
    c = 0 || mem (if c < 0 then l else r) x 

let rec remove (tree : _ Map_gen.t as 'a) x : 'a = match tree with 
  | Empty -> empty
  | Leaf leaf -> 
    if eq_key x leaf.k then empty 
    else tree
  | Node{l; k ; v; r} ->
    let c = compare_key x k in
    if c = 0 then
      Map_gen.merge l r
    else if c < 0 then
      bal (remove l x) k v r
    else
      bal l k v (remove r x )

type 'a split = 
  | Yes of {l : (key,'a) Map_gen.t; r : (key,'a)Map_gen.t ; v : 'a}
  | No of {l : (key,'a) Map_gen.t; r : (key,'a)Map_gen.t }


let rec split  (tree : (key,'a) Map_gen.t) x : 'a split  = 
  match tree with 
  | Empty ->
    No {l = empty; r = empty}
  | Leaf leaf -> 
    let c = compare_key x leaf.k in 
    if c = 0 then Yes {l = empty; v= leaf.v; r = empty} 
    else if c < 0 then No { l = empty; r = tree }
    else  No { l = tree; r = empty}
  | Node {l; k ; v ; r} ->
    let c = compare_key x k in
    if c = 0 then Yes {l; v; r}
    else if c < 0 then      
      match  split l x with 
      | Yes result -> Yes {result with r = Map_gen.join result.r k v r }
      | No result -> No {result with r = Map_gen.join result.r k v r } 
    else
      match split r x with 
      | Yes result -> 
        Yes {result with l = Map_gen.join l k v result.l}
      | No result -> 
        No {result with l = Map_gen.join l k v result.l}


let rec disjoint_merge_exn  
    (s1 : _ Map_gen.t) 
    (s2  : _ Map_gen.t) 
    fail : _ Map_gen.t =
  match s1 with
  | Empty -> s2  
  | Leaf ({k } as l1)  -> 
    begin match s2 with 
      | Empty -> s1 
      | Leaf l2 -> 
        let c = compare_key k l2.k in 
        if c = 0 then raise_notrace (fail k l1.v l2.v)
        else if c < 0 then Map_gen.unsafe_two_elements l1.k l1.v l2.k l2.v
        else Map_gen.unsafe_two_elements l2.k l2.v k l1.v
      | Node _ -> 
        adjust s2 k (fun data -> 
            match data with 
            |  None -> l1.v
            | Some s2v  -> raise_notrace (fail k l1.v s2v)
          )        
    end
  | Node ({k} as xs1) -> 
    if  xs1.h >= height s2 then
      begin match split s2 k with 
        | No {l; r} -> 
          Map_gen.join 
            (disjoint_merge_exn  xs1.l l fail)
            k 
            xs1.v 
            (disjoint_merge_exn xs1.r r fail)
        | Yes { v =  s2v} ->
          raise_notrace (fail k xs1.v s2v)
      end        
    else let [@warning "-8"] (Node ({k} as s2) : _ Map_gen.t)  = s2 in 
      begin match  split s1 k with 
        | No {l;  r} -> 
          Map_gen.join 
            (disjoint_merge_exn  l s2.l fail) k s2.v 
            (disjoint_merge_exn  r s2.r fail)
        | Yes { v = s1v} -> 
          raise_notrace (fail k s1v s2.v)
      end






let add_list (xs : _ list ) init = 
  Ext_list.fold_left xs init (fun  acc (k,v) -> add acc k v )

let of_list xs = add_list xs empty

let of_array xs = 
  Ext_array.fold_left xs empty (fun acc (k,v) -> add acc k v ) 

end
module Ounit_map_tests
= struct
#1 "ounit_map_tests.ml"
let ((>::),
    (>:::)) = OUnit.((>::),(>:::))

let (=~) = OUnit.assert_equal 

let test_sorted_strict arr = 
  let v = Map_int.of_array arr |> Map_int.to_sorted_array in 
  let arr_copy = Array.copy arr in 
  Array.sort (fun ((a:int),_) (b,_) -> compare a b ) arr_copy;
  v =~ arr_copy 

let suites = 
  __MODULE__ >:::
  [
    __LOC__ >:: begin fun _ -> 
      [1,"1"; 2,"2"; 12,"12"; 3, "3"]
      |> Map_int.of_list 
      |> Map_int.keys 
      |> OUnit.assert_equal [1;2;3;12]
    end
    ;
    __LOC__ >:: begin fun _ -> 
      OUnit.assert_equal (Map_int.cardinal Map_int.empty) 0 ;
      OUnit.assert_equal ([1,"1"; 2,"2"; 12,"12"; 3, "3"]
      |> Map_int.of_list|>Map_int.cardinal )  4      
    end;
    __LOC__ >:: begin fun _ -> 
      let v = 
      [1,"1"; 2,"2"; 12,"12"; 3, "3"]
      |> Map_int.of_list 
      |> Map_int.to_sorted_array in 
      Array.length v =~ 4 ; 
      v =~ [|1,"1"; 2,"2"; 3, "3"; 12,"12"; |]
    end;
    __LOC__ >:: begin fun _ -> 
        test_sorted_strict [||];
        test_sorted_strict [|1,""|];
        test_sorted_strict [|2,""; 1,""|];
        test_sorted_strict [|2,""; 1,""; 3, ""|];
        test_sorted_strict [|2,""; 1,""; 3, ""; 4,""|]
    end;
    __LOC__ >:: begin fun _ ->
      Map_int.cardinal (Map_int.of_array (Array.init 1000 (fun i -> (i,i))))
      =~ 1000
    end;
    __LOC__ >:: begin fun _ -> 
      let count = 1000 in 
      let a = Array.init count (fun x -> x ) in 
      let v = Map_int.empty in
      let u = 
        begin 
          let v = Array.fold_left (fun acc key -> Map_int.adjust acc key (fun v ->  match v with None -> 1 | Some v -> succ v)  ) v a   in 
          Array.fold_left (fun acc key -> Map_int.adjust acc key (fun v -> match v with None ->  1 | Some v -> succ v)   ) v a  
          end
        in  
       Map_int.iter u (fun _ v -> v =~ 2 ) ;
       Map_int.cardinal u =~ count
    end
  ]

end
module Ounit_ordered_hash_set_tests
= struct
#1 "ounit_ordered_hash_set_tests.ml"
let ((>::),
     (>:::)) = OUnit.((>::),(>:::))

let (=~) = OUnit.assert_equal


let suites = 
  __FILE__
  >::: [
    
  ]

end
module Ext_fmt
= struct
#1 "ext_fmt.ml"


let with_file_as_pp filename f = 
  Ext_pervasives.finally (open_out_bin filename) ~clean:close_out
    (fun chan -> 
       let fmt = Format.formatter_of_out_channel chan in
       let v = f  fmt in
       Format.pp_print_flush fmt ();
       v
    ) 



let failwithf ~loc fmt = Format.ksprintf (fun s -> failwith (loc ^ s))
    fmt

let invalid_argf fmt = Format.ksprintf invalid_arg fmt


end
module Ext_sys : sig 
#1 "ext_sys.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)



val is_directory_no_exn : string -> bool


val is_windows_or_cygwin : bool 


end = struct
#1 "ext_sys.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

(** TODO: not exported yet, wait for Windows Fix*)

external is_directory_no_exn : string -> bool = "caml_sys_is_directory_no_exn"



let is_windows_or_cygwin = Sys.win32 || Sys.cygwin



end
module Ext_path : sig 
#1 "ext_path.mli"
(* Copyright (C) 2017 Authors of ReScript
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

type t 


(** Js_output is node style, which means 
    separator is only '/'

    if the path contains 'node_modules', 
    [node_relative_path] will discard its prefix and 
    just treat it as a library instead
*)
val simple_convert_node_path_to_os_path : string -> string



(**
   [combine path1 path2]
   1. add some simplifications when concatenating
   2. when [path2] is absolute, return [path2]
*)  
val combine : 
  string -> 
  string -> 
  string    



(**
   {[
     get_extension "a.txt" = ".txt"
       get_extension "a" = ""
   ]}
*)





val node_rebase_file :
  from:string -> 
  to_:string ->
  string -> 
  string 

(** 
   TODO: could be highly optimized
   if [from] and [to] resolve to the same path, a zero-length string is returned 
   Given that two paths are directory

   A typical use case is 
   {[
     Filename.concat 
       (rel_normalized_absolute_path cwd (Filename.dirname a))
       (Filename.basename a)
   ]}
*)
val rel_normalized_absolute_path : from:string -> string -> string 


val normalize_absolute_path : string -> string 


val absolute_cwd_path : string -> string 

(** [concat dirname filename]
    The same as {!Filename.concat} except a tiny optimization 
    for current directory simplification
*)
val concat : string -> string -> string 

val check_suffix_case : 
  string -> string -> bool



(* It is lazy so that it will not hit errors when in script mode *)
val package_dir : string Lazy.t

end = struct
#1 "ext_path.ml"
(* Copyright (C) 2017 Hongbo Zhang, Authors of ReScript
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

(* [@@@warning "-37"] *)
type t =  
  (* | File of string  *)
  | Dir of string  
[@@unboxed]

let simple_convert_node_path_to_os_path =
  if Sys.unix then fun x -> x 
  else if Sys.win32 || Sys.cygwin then 
    Ext_string.replace_slash_backward 
  else failwith ("Unknown OS : " ^ Sys.os_type)


let cwd = lazy (Sys.getcwd())

let split_by_sep_per_os : string -> string list = 
  if Ext_sys.is_windows_or_cygwin then 
    fun x -> 
      (* on Windows, we can still accept -bs-package-output lib/js *)
      Ext_string.split_by 
        (fun x -> match x with |'/' |'\\' -> true | _ -> false) x
  else 
    fun x -> Ext_string.split x '/'

(** example
    {[
      "/bb/mbigc/mbig2899/bgit/bucklescript/jscomp/stdlib/external/pervasives.cmj"
        "/bb/mbigc/mbig2899/bgit/bucklescript/jscomp/stdlib/ocaml_array.ml"
    ]}

    The other way
    {[

      "/bb/mbigc/mbig2899/bgit/bucklescript/jscomp/stdlib/ocaml_array.ml"
        "/bb/mbigc/mbig2899/bgit/bucklescript/jscomp/stdlib/external/pervasives.cmj"
    ]}
    {[
      "/bb/mbigc/mbig2899/bgit/bucklescript/jscomp/stdlib//ocaml_array.ml"
    ]}
    {[
      /a/b
      /c/d
    ]}
*)
let node_relative_path 
    ~from:(file_or_dir_2 : t )
    (file_or_dir_1 : t) 
  = 
  let relevant_dir1 = 
    match file_or_dir_1 with 
    | Dir x -> x 
    (* | File file1 ->  Filename.dirname file1 *) in
  let relevant_dir2 = 
    match file_or_dir_2 with 
    | Dir x -> x 
    (* | File file2 -> Filename.dirname file2  *) in
  let dir1 = split_by_sep_per_os relevant_dir1 in
  let dir2 = split_by_sep_per_os relevant_dir2 in
  let rec go (dir1 : string list) (dir2 : string list) = 
    match dir1, dir2 with 
    | "." :: xs, ys -> go xs ys 
    | xs , "." :: ys -> go xs ys 
    | x::xs , y :: ys when x = y
      -> go xs ys 
    | _, _ -> 
      Ext_list.map_append  dir2  dir1  (fun _ ->  Literals.node_parent)
  in
  match go dir1 dir2 with
  | (x :: _ ) as ys when x = Literals.node_parent -> 
    String.concat Literals.node_sep ys
  | ys -> 
    String.concat Literals.node_sep  
    @@ Literals.node_current :: ys


let node_concat ~dir base =
  dir ^ Literals.node_sep ^ base 

let node_rebase_file ~from ~to_ file = 

  node_concat
    ~dir:(
      if from = to_ then Literals.node_current
      else node_relative_path ~from:(Dir from) (Dir to_)) 
    file


(***
   {[
     Filename.concat "." "";;
     "./"
   ]}
*)
let combine path1 path2 =  
  if Filename.is_relative path2 then
    if Ext_string.is_empty path2 then 
      path1
    else 
    if path1 = Filename.current_dir_name then 
      path2
    else
    if path2 = Filename.current_dir_name 
    then path1
    else
      Filename.concat path1 path2 
  else
    path2








let (//) x y =
  if x = Filename.current_dir_name then y
  else if y = Filename.current_dir_name then x 
  else Filename.concat x y 

(**
   {[
     split_aux "//ghosg//ghsogh/";;
     - : string * string list = ("/", ["ghosg"; "ghsogh"])
   ]}
   Note that 
   {[
     Filename.dirname "/a/" = "/"
       Filename.dirname "/a/b/" = Filename.dirname "/a/b" = "/a"
   ]}
   Special case:
   {[
     basename "//" = "/"
       basename "///"  = "/"
   ]}
   {[
     basename "" =  "."
       basename "" = "."
       dirname "" = "."
       dirname "" =  "."
   ]}  
*)
let split_aux p =
  let rec go p acc =
    let dir = Filename.dirname p in
    if dir = p then dir, acc
    else
      let new_path = Filename.basename p in 
      if Ext_string.equal new_path Filename.dir_sep then 
        go dir acc 
        (* We could do more path simplification here
           leave to [rel_normalized_absolute_path]
        *)
      else 
        go dir (new_path :: acc)

  in go p []





(** 
   TODO: optimization
   if [from] and [to] resolve to the same path, a zero-length string is returned 

   This function is useed in [es6-global] and 
   [amdjs-global] format and tailored for `rollup`
*)
let rel_normalized_absolute_path ~from to_ =
  let root1, paths1 = split_aux from in 
  let root2, paths2 = split_aux to_ in 
  if root1 <> root2 then root2
  else
    let rec go xss yss =
      match xss, yss with 
      | x::xs, y::ys -> 
        if Ext_string.equal x  y then go xs ys 
        else if x = Filename.current_dir_name then go xs yss 
        else if y = Filename.current_dir_name then go xss ys
        else 
          let start = 
            Ext_list.fold_left xs Ext_string.parent_dir_lit (fun acc  _  -> acc // Ext_string.parent_dir_lit )
          in 
          Ext_list.fold_left yss start (fun acc v -> acc // v)
      | [], [] -> Ext_string.empty
      | [], y::ys -> Ext_list.fold_left ys y (fun acc x -> acc // x) 
      | _::xs, [] ->
        Ext_list.fold_left xs Ext_string.parent_dir_lit (fun acc _ -> acc // Ext_string.parent_dir_lit )
    in
    let v =  go paths1 paths2  in 

    if Ext_string.is_empty v then  Literals.node_current
    else 
    if
      v = "."
      || v = ".."
      || Ext_string.starts_with v "./"  
      || Ext_string.starts_with v "../" 
    then v 
    else "./" ^ v 

(*TODO: could be hgighly optimized later 
  {[
    normalize_absolute_path "/gsho/./..";;

    normalize_absolute_path "/a/b/../c../d/e/f";;

    normalize_absolute_path "/gsho/./..";;

    normalize_absolute_path "/gsho/./../..";;

    normalize_absolute_path "/a/b/c/d";;

    normalize_absolute_path "/a/b/c/d/";;

    normalize_absolute_path "/a/";;

    normalize_absolute_path "/a";;
  ]}
*)
(** See tests in {!Ounit_path_tests} *)
let normalize_absolute_path x =
  let drop_if_exist xs =
    match xs with 
    | [] -> []
    | _ :: xs -> xs in 
  let rec normalize_list acc paths =
    match paths with 
    | [] -> acc 
    | x :: xs -> 
      if Ext_string.equal x Ext_string.current_dir_lit then 
        normalize_list acc xs 
      else if Ext_string.equal x Ext_string.parent_dir_lit then 
        normalize_list (drop_if_exist acc ) xs 
      else   
        normalize_list (x::acc) xs 
  in
  let root, paths = split_aux x in
  let rev_paths =  normalize_list [] paths in 
  let rec go acc rev_paths =
    match rev_paths with 
    | [] -> Filename.concat root acc 
    | last::rest ->  go (Filename.concat last acc ) rest  in 
  match rev_paths with 
  | [] -> root 
  | last :: rest -> go last rest 




let absolute_path cwd s = 
  let process s = 
    let s = 
      if Filename.is_relative s then
        Lazy.force cwd // s 
      else s in
    (* Now simplify . and .. components *)
    let rec aux s =
      let base,dir  = Filename.basename s, Filename.dirname s  in
      if dir = s then dir
      else if base = Filename.current_dir_name then aux dir
      else if base = Filename.parent_dir_name then Filename.dirname (aux dir)
      else aux dir // base
    in aux s  in 
  process s 

let absolute_cwd_path s = 
  absolute_path cwd  s 

(* let absolute cwd s =   
   match s with 
   | File x -> File (absolute_path cwd x )
   | Dir x -> Dir (absolute_path cwd x) *)

let concat dirname filename =
  if filename = Filename.current_dir_name then dirname
  else if dirname = Filename.current_dir_name then filename
  else Filename.concat dirname filename


let check_suffix_case =
  Ext_string.ends_with

(* Input must be absolute directory *)
let rec find_root_filename ~cwd filename   = 
  if Sys.file_exists ( Filename.concat cwd  filename) then cwd
  else 
    let cwd' = Filename.dirname cwd in 
    if String.length cwd' < String.length cwd then  
      find_root_filename ~cwd:cwd'  filename 
    else 
      Ext_fmt.failwithf 
        ~loc:__LOC__
        "%s not found from %s" filename cwd


let find_package_json_dir cwd  = 
  find_root_filename ~cwd  Literals.bsconfig_json

let package_dir = lazy (find_package_json_dir (Lazy.force cwd))

end
module Ounit_path_tests
= struct
#1 "ounit_path_tests.ml"
let ((>::),
     (>:::)) = OUnit.((>::),(>:::))


let normalize = Ext_path.normalize_absolute_path
let (=~) x y = 
  OUnit.assert_equal 
  ~printer:(fun x -> x)
  ~cmp:(fun x y ->   Ext_string.equal x y ) x y

let suites = 
  __FILE__ 
  >:::
  [
    "linux path tests" >:: begin fun _ -> 
      let norm = 
        Array.map normalize
          [|
            "/gsho/./..";
            "/a/b/../c../d/e/f";
            "/a/b/../c/../d/e/f";
            "/gsho/./../..";
            "/a/b/c/d";
            "/a/b/c/d/";
            "/a/";
            "/a";
            "/a.txt/";
            "/a.txt"
          |] in 
      OUnit.assert_equal norm 
        [|
          "/";
          "/a/c../d/e/f";
          "/a/d/e/f";
          "/";
          "/a/b/c/d" ;
          "/a/b/c/d";
          "/a";
          "/a";
          "/a.txt";
          "/a.txt"
        |]
    end;
    __LOC__ >:: begin fun _ ->
      normalize "/./a/.////////j/k//../////..///././b/./c/d/./." =~ "/a/b/c/d"
    end;
    __LOC__ >:: begin fun _ -> 
      normalize "/./a/.////////j/k//../////..///././b/./c/d/././../" =~ "/a/b/c"
    end;

    __LOC__ >:: begin fun _ -> 
      let aux a b result = 

        Ext_path.rel_normalized_absolute_path
          ~from:a b =~ result ; 

        Ext_path.rel_normalized_absolute_path
          ~from:(String.sub a 0 (String.length a - 1)) 
          b  =~ result ;

        Ext_path.rel_normalized_absolute_path
          ~from:a
          (String.sub b 0 (String.length b - 1))  =~ result
        ;


        Ext_path.rel_normalized_absolute_path
          ~from:(String.sub a 0 (String.length a - 1 ))
          (String.sub b 0 (String.length b - 1))
        =~ result  
      in   
      aux
        "/a/b/c/"
        "/a/b/c/d/"  "./d";
      aux
        "/a/b/c/"
        "/a/b/c/d/e/f/" "./d/e/f" ;
      aux
        "/a/b/c/d/"
        "/a/b/c/"  ".."  ;
      aux
        "/a/b/c/d/"
        "/a/b/"  "../.."  ;  
      aux
        "/a/b/c/d/"
        "/a/"  "../../.."  ;  
      aux
        "/a/b/c/d/"
        "//"  "../../../.."  ;  


    end;
    (* This is still correct just not optimal depends 
       on user's perspective *)
    __LOC__ >:: begin fun _ -> 
      Ext_path.rel_normalized_absolute_path 
        ~from:"/a/b/c/d"
        "/x/y" =~ "../../../../x/y"  

    end;

    (* used in module system: [es6-global] and [amdjs-global] *)    
    __LOC__ >:: begin fun _ -> 
      Ext_path.rel_normalized_absolute_path
        ~from:"/usr/local/lib/node_modules/"
        "//" =~ "../../../..";
      Ext_path.rel_normalized_absolute_path
        ~from:"/usr/local/lib/node_modules/"
        "/" =~ "../../../..";
      Ext_path.rel_normalized_absolute_path
        ~from:"./"
        "./node_modules/xx/./xx.js" =~ "./node_modules/xx/xx.js";
      Ext_path.rel_normalized_absolute_path
        ~from:"././"
        "./node_modules/xx/./xx.js" =~ "./node_modules/xx/xx.js"        
    end;

     __LOC__ >:: begin fun _ -> 
      Ext_path.node_rebase_file
        ~to_:( "lib/js/src/a")
        ~from:( "lib/js/src") "b" =~ "./a/b" ;
      Ext_path.node_rebase_file
        ~to_:( "lib/js/src/")
        ~from:( "lib/js/src") "b" =~ "./b" ;          
      Ext_path.node_rebase_file
        ~to_:( "lib/js/src")
        ~from:("lib/js/src/a") "b" =~ "../b";
      Ext_path.node_rebase_file
        ~to_:( "lib/js/src/a")
        ~from:("lib/js/") "b" =~ "./src/a/b" ;
      Ext_path.node_rebase_file
        ~to_:("lib/js/./src/a") 
        ~from:("lib/js/src/a/") "b"
        =~ "./b";

      Ext_path.node_rebase_file
        ~to_:"lib/js/src/a"
        ~from: "lib/js/src/a/" "b"
      =~ "./b";
      Ext_path.node_rebase_file
        ~to_:"lib/js/src/a/"
        ~from:"lib/js/src/a/" "b"
      =~ "./b"
    end     
  ]

end
module Vec : sig 
#1 "vec.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

module Make ( Resize : Vec_gen.ResizeType) : Vec_gen.S with type elt = Resize.t 



end = struct
#1 "vec.ml"
# 1 "ext/vec.cppo.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)
# 25 "ext/vec.cppo.ml"
external unsafe_blit : 
    'a array -> int -> 'a array -> int -> int -> unit = "caml_array_blit"
module Make ( Resize :  Vec_gen.ResizeType) = struct
  type elt = Resize.t 

  let null = Resize.null 
  

# 41 "ext/vec.cppo.ml"
external unsafe_sub : 'a array -> int -> int -> 'a array = "caml_array_sub"

type  t = {
  mutable arr : elt array ;
  mutable len : int ;  
}

let length d = d.len

let compact d =
  let d_arr = d.arr in 
  if d.len <> Array.length d_arr then 
    begin
      let newarr = unsafe_sub d_arr 0 d.len in 
      d.arr <- newarr
    end
let singleton v = 
  {
    len = 1 ; 
    arr = [|v|]
  }

let empty () =
  {
    len = 0;
    arr = [||];
  }

let is_empty d =
  d.len = 0

let reset d = 
  d.len <- 0; 
  d.arr <- [||]


(* For [to_*] operations, we should be careful to call {!Array.*} function 
   in case we operate on the whole array
*)
let to_list d =
  let rec loop (d_arr : elt array) idx accum =
    if idx < 0 then accum else loop d_arr (idx - 1) (Array.unsafe_get d_arr idx :: accum)
  in
  loop d.arr (d.len - 1) []


let of_list lst =
  let arr = Array.of_list lst in 
  { arr ; len = Array.length arr}


let to_array d = 
  unsafe_sub d.arr 0 d.len

let of_array src =
  {
    len = Array.length src;
    arr = Array.copy src;
    (* okay to call {!Array.copy}*)
  }
let of_sub_array arr off len = 
  { 
    len = len ; 
    arr = Array.sub arr off len  
  }  
let unsafe_internal_array v = v.arr  
(* we can not call {!Array.copy} *)
let copy src =
  let len = src.len in
  {
    len ;
    arr = unsafe_sub src.arr 0 len ;
  }

(* FIXME *)
let reverse_in_place src = 
  Ext_array.reverse_range src.arr 0 src.len 




(* {!Array.sub} is not enough for error checking, it 
   may contain some garbage
 *)
let sub (src : t) start len =
  let src_len = src.len in 
  if len < 0 || start > src_len - len then invalid_arg "Vec.sub"
  else 
  { len ; 
    arr = unsafe_sub src.arr start len }

let iter d  f = 
  let arr = d.arr in 
  for i = 0 to d.len - 1 do
    f (Array.unsafe_get arr i)
  done

let iteri d f =
  let arr = d.arr in
  for i = 0 to d.len - 1 do
    f i (Array.unsafe_get arr i)
  done

let iter_range d ~from ~to_ f =
  if from < 0 || to_ >= d.len then invalid_arg "Vec.iter_range"
  else 
    let d_arr = d.arr in 
    for i = from to to_ do 
      f  (Array.unsafe_get d_arr i)
    done

let iteri_range d ~from ~to_ f =
  if from < 0 || to_ >= d.len then invalid_arg "Vec.iteri_range"
  else 
    let d_arr = d.arr in 
    for i = from to to_ do 
      f i (Array.unsafe_get d_arr i)
    done

let map_into_array f src =
  let src_len = src.len in 
  let src_arr = src.arr in 
  if src_len = 0 then [||]
  else 
    let first_one = f (Array.unsafe_get src_arr 0) in 
    let arr = Array.make  src_len  first_one in
    for i = 1 to src_len - 1 do
      Array.unsafe_set arr i (f (Array.unsafe_get src_arr i))
    done;
    arr 
let map_into_list f src = 
  let src_len = src.len in 
  let src_arr = src.arr in 
  if src_len = 0 then []
  else 
    let acc = ref [] in         
    for i =  src_len - 1 downto 0 do
      acc := f (Array.unsafe_get src_arr i) :: !acc
    done;
    !acc

let mapi f src =
  let len = src.len in 
  if len = 0 then { len ; arr = [| |] }
  else 
    let src_arr = src.arr in 
    let arr = Array.make len (Array.unsafe_get src_arr 0) in
    for i = 1 to len - 1 do
      Array.unsafe_set arr i (f i (Array.unsafe_get src_arr i))
    done;
    {
      len ;
      arr ;
    }

let fold_left f x a =
  let rec loop a_len (a_arr : elt array) idx x =
    if idx >= a_len then x else 
      loop a_len a_arr (idx + 1) (f x (Array.unsafe_get a_arr idx))
  in
  loop a.len a.arr 0 x

let fold_right f a x =
  let rec loop (a_arr : elt array) idx x =
    if idx < 0 then x
    else loop a_arr (idx - 1) (f (Array.unsafe_get a_arr idx) x)
  in
  loop a.arr (a.len - 1) x

(**  
   [filter] and [inplace_filter]
*)
let filter f d =
  let new_d = copy d in 
  let new_d_arr = new_d.arr in 
  let d_arr = d.arr in
  let p = ref 0 in
  for i = 0 to d.len  - 1 do
    let x = Array.unsafe_get d_arr i in
    (* TODO: can be optimized for segments blit *)
    if f x  then
      begin
        Array.unsafe_set new_d_arr !p x;
        incr p;
      end;
  done;
  new_d.len <- !p;
  new_d 

let equal eq x y : bool = 
  if x.len <> y.len then false 
  else 
    let rec aux x_arr y_arr i =
      if i < 0 then true else  
      if eq (Array.unsafe_get x_arr i) (Array.unsafe_get y_arr i) then 
        aux x_arr y_arr (i - 1)
      else false in 
    aux x.arr y.arr (x.len - 1)

let get d i = 
  if i < 0 || i >= d.len then invalid_arg "Vec.get"
  else Array.unsafe_get d.arr i
let unsafe_get d i = Array.unsafe_get d.arr i 
let last d = 
  if d.len <= 0 then invalid_arg   "Vec.last"
  else Array.unsafe_get d.arr (d.len - 1)

let capacity d = Array.length d.arr

(* Attention can not use {!Array.exists} since the bound is not the same *)  
let exists p d = 
  let a = d.arr in 
  let n = d.len in   
  let rec loop i =
    if i = n then false
    else if p (Array.unsafe_get a i) then true
    else loop (succ i) in
  loop 0

let map f src =
  let src_len = src.len in 
  if src_len = 0 then { len = 0 ; arr = [||]}
  (* TODO: we may share the empty array 
     but sharing mutable state is very challenging, 
     the tricky part is to avoid mutating the immutable array,
     here it looks fine -- 
     invariant: whenever [.arr] mutated, make sure  it is not an empty array
     Actually no: since starting from an empty array 
     {[
       push v (* the address of v should not be changed *)
     ]}
  *)
  else 
    let src_arr = src.arr in 
    let first = f (Array.unsafe_get src_arr 0 ) in 
    let arr = Array.make  src_len first in
    for i = 1 to src_len - 1 do
      Array.unsafe_set arr i (f (Array.unsafe_get src_arr i))
    done;
    {
      len = src_len;
      arr = arr;
    }

let init len f =
  if len < 0 then invalid_arg  "Vec.init"
  else if len = 0 then { len = 0 ; arr = [||] }
  else 
    let first = f 0 in 
    let arr = Array.make len first in
    for i = 1 to len - 1 do
      Array.unsafe_set arr i (f i)
    done;
    {

      len ;
      arr 
    }



  let make initsize : t =
    if initsize < 0 then invalid_arg  "Vec.make" ;
    {

      len = 0;
      arr = Array.make  initsize null ;
    }



  let reserve (d : t ) s = 
    let d_len = d.len in 
    let d_arr = d.arr in 
    if s < d_len || s < Array.length d_arr then ()
    else 
      let new_capacity = min Sys.max_array_length s in 
      let new_d_arr = Array.make new_capacity null in 
       unsafe_blit d_arr 0 new_d_arr 0 d_len;
      d.arr <- new_d_arr 

  let push (d : t) v  =
    let d_len = d.len in
    let d_arr = d.arr in 
    let d_arr_len = Array.length d_arr in
    if d_arr_len = 0 then
      begin 
        d.len <- 1 ;
        d.arr <- [| v |]
      end
    else  
      begin 
        if d_len = d_arr_len then 
          begin
            if d_len >= Sys.max_array_length then 
              failwith "exceeds max_array_length";
            let new_capacity = min Sys.max_array_length d_len * 2 
            (* [d_len] can not be zero, so [*2] will enlarge   *)
            in
            let new_d_arr = Array.make new_capacity null in 
            d.arr <- new_d_arr;
             unsafe_blit d_arr 0 new_d_arr 0 d_len ;
          end;
        d.len <- d_len + 1;
        Array.unsafe_set d.arr d_len v
      end

(** delete element at offset [idx], will raise exception when have invalid input *)
  let delete (d : t) idx =
    let d_len = d.len in 
    if idx < 0 || idx >= d_len then invalid_arg "Vec.delete" ;
    let arr = d.arr in 
     unsafe_blit arr (idx + 1) arr idx  (d_len - idx - 1);
    let idx = d_len - 1 in 
    d.len <- idx
    
# 358 "ext/vec.cppo.ml"
    ;
    Array.unsafe_set arr idx  null
    
# 362 "ext/vec.cppo.ml"
(** pop the last element, a specialized version of [delete] *)
  let pop (d : t) = 
    let idx  = d.len - 1  in
    if idx < 0 then invalid_arg "Vec.pop";
    d.len <- idx
    
# 369 "ext/vec.cppo.ml"
    ;    
    Array.unsafe_set d.arr idx null
  
# 373 "ext/vec.cppo.ml"
(** pop and return the last element *)  
  let get_last_and_pop (d : t) = 
    let idx  = d.len - 1  in
    if idx < 0 then invalid_arg "Vec.get_last_and_pop";
    let last = Array.unsafe_get d.arr idx in 
    d.len <- idx 
    
# 381 "ext/vec.cppo.ml"
    ;
    Array.unsafe_set d.arr idx null
    
# 384 "ext/vec.cppo.ml"
    ;
    last 

(** delete elements start from [idx] with length [len] *)
  let delete_range (d : t) idx len =
    let d_len = d.len in 
    if len < 0 || idx < 0 || idx + len > d_len then invalid_arg  "Vec.delete_range"  ;
    let arr = d.arr in 
     unsafe_blit arr (idx + len) arr idx (d_len  - idx - len);
    d.len <- d_len - len
    
# 396 "ext/vec.cppo.ml"
    ;
    for i = d_len - len to d_len - 1 do
      Array.unsafe_set arr i null
    done

# 402 "ext/vec.cppo.ml"
(** delete elements from [idx] with length [len] return the deleted elements as a new vec*)
  let get_and_delete_range (d : t) idx len : t = 
    let d_len = d.len in 
    if len < 0 || idx < 0 || idx + len > d_len then invalid_arg  "Vec.get_and_delete_range"  ;
    let arr = d.arr in 
    let value =  unsafe_sub arr idx len in
     unsafe_blit arr (idx + len) arr idx (d_len  - idx - len);
    d.len <- d_len - len; 
    
# 412 "ext/vec.cppo.ml"
    for i = d_len - len to d_len - 1 do
      Array.unsafe_set arr i null
    done;
    
# 416 "ext/vec.cppo.ml"
    {len = len ; arr = value}


  (** Below are simple wrapper around normal Array operations *)  

  let clear (d : t ) =
    
# 424 "ext/vec.cppo.ml"
    for i = 0 to d.len - 1 do 
      Array.unsafe_set d.arr i null
    done;
    
# 428 "ext/vec.cppo.ml"
    d.len <- 0



  let inplace_filter f (d : t) : unit = 
    let d_arr = d.arr in     
    let d_len = d.len in
    let p = ref 0 in
    for i = 0 to d_len - 1 do 
      let x = Array.unsafe_get d_arr i in 
      if f x then 
        begin 
          let curr_p = !p in 
          (if curr_p <> i then 
             Array.unsafe_set d_arr curr_p x) ;
          incr p
        end
    done ;
    let last = !p  in 
    
# 451 "ext/vec.cppo.ml"
    delete_range d last  (d_len - last)

  
# 454 "ext/vec.cppo.ml"
  let inplace_filter_from start f (d : t) : unit = 
    if start < 0 then invalid_arg "Vec.inplace_filter_from"; 
    let d_arr = d.arr in     
    let d_len = d.len in
    let p = ref start in    
    for i = start to d_len - 1 do 
      let x = Array.unsafe_get d_arr i in 
      if f x then 
        begin 
          let curr_p = !p in 
          (if curr_p <> i then 
             Array.unsafe_set d_arr curr_p x) ;
          incr p
        end
    done ;
    let last = !p  in 
    
# 473 "ext/vec.cppo.ml"
    delete_range d last  (d_len - last)


# 477 "ext/vec.cppo.ml"
(** inplace filter the elements and accumulate the non-filtered elements *)
  let inplace_filter_with  f ~cb_no acc (d : t)  = 
    let d_arr = d.arr in     
    let p = ref 0 in
    let d_len = d.len in
    let acc = ref acc in 
    for i = 0 to d_len - 1 do 
      let x = Array.unsafe_get d_arr i in 
      if f x then 
        begin 
          let curr_p = !p in 
          (if curr_p <> i then 
             Array.unsafe_set d_arr curr_p x) ;
          incr p
        end
      else 
        acc := cb_no  x  !acc
    done ;
    let last = !p  in 
    
# 500 "ext/vec.cppo.ml"
    delete_range d last  (d_len - last)
    
# 502 "ext/vec.cppo.ml"
    ; !acc 



# 507 "ext/vec.cppo.ml"
end

end
module Int_vec_vec : sig 
#1 "int_vec_vec.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

include Vec_gen.S with type elt = Vec_int.t

end = struct
#1 "int_vec_vec.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


include Vec.Make(struct type t = Vec_int.t let null = Vec_int.empty () end)

end
module Ext_scc : sig 
#1 "ext_scc.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)




type node = Vec_int.t


(** Assume input is int array with offset from 0 
    Typical input 
    {[
      [|
        [ 1 ; 2 ]; // 0 -> 1,  0 -> 2 
                     [ 1 ];   // 0 -> 1 
          [ 2 ]  // 0 -> 2 
      |]
    ]}
    Note that we can tell how many nodes by calculating 
    [Array.length] of the input 
*)
val graph : Vec_int.t array -> Int_vec_vec.t


(** Used for unit test *)
val graph_check : node array -> int * int list 

end = struct
#1 "ext_scc.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

type node = Vec_int.t 

(** 
   [int] as data for this algorithm
   Pros:
   1. Easy to eoncode algorithm (especially given that the capacity of node is known)
   2. Algorithms itself are much more efficient
   3. Node comparison semantics is clear
   4. Easy to print output
   Cons:
   1. post processing input data  
*)
let min_int (x : int) y = if x < y then x else y  


let graph  e =
  let index = ref 0 in 
  let s = Vec_int.empty () in

  let output = Int_vec_vec.empty () in (* collect output *)
  let node_numes = Array.length e in

  let on_stack_array = Array.make node_numes false in
  let index_array = Array.make node_numes (-1) in 
  let lowlink_array = Array.make node_numes (-1) in

  let rec scc v_data  =
    let new_index = !index + 1 in 
    index := new_index ;
    Vec_int.push s v_data; 

    index_array.(v_data) <- new_index ;  
    lowlink_array.(v_data) <- new_index ; 
    on_stack_array.(v_data) <- true ;    
    let v = e.(v_data) in     
    Vec_int.iter v (fun w_data  ->
        if Array.unsafe_get index_array w_data < 0 then (* not processed *)
          begin  
            scc w_data;
            Array.unsafe_set lowlink_array v_data  
              (min_int (Array.unsafe_get lowlink_array v_data) (Array.unsafe_get lowlink_array w_data))
          end  
        else if Array.unsafe_get on_stack_array w_data then 
          (* successor is in stack and hence in current scc *)
          begin 
            Array.unsafe_set lowlink_array v_data  
              (min_int (Array.unsafe_get lowlink_array v_data) (Array.unsafe_get lowlink_array w_data))
          end
      ) ; 

    if Array.unsafe_get lowlink_array v_data = Array.unsafe_get index_array v_data then
      (* start a new scc *)
      begin
        let s_len = Vec_int.length s in
        let last_index = ref (s_len - 1) in 
        let u = ref (Vec_int.unsafe_get s !last_index) in
        while  !u <> v_data do 
          Array.unsafe_set on_stack_array (!u)  false ; 
          last_index := !last_index - 1;
          u := Vec_int.unsafe_get s !last_index
        done ;
        on_stack_array.(v_data) <- false; (* necessary *)
        Int_vec_vec.push output (Vec_int.get_and_delete_range s !last_index (s_len  - !last_index));
      end   
  in
  for i = 0 to node_numes - 1 do 
    if Array.unsafe_get index_array i < 0 then scc i
  done ;
  output 

let graph_check v = 
  let v = graph v in 
  Int_vec_vec.length v, 
  Int_vec_vec.fold_left (fun acc x -> Vec_int.length x :: acc ) [] v  

end
module Ounit_scc_tests
= struct
#1 "ounit_scc_tests.ml"
let ((>::),
    (>:::)) = OUnit.((>::),(>:::))

let (=~) = OUnit.assert_equal

let tiny_test_cases = {|
13
22
 4  2
 2  3
 3  2
 6  0
 0  1
 2  0
11 12
12  9
 9 10
 9 11
 7  9
10 12
11  4
 4  3
 3  5
 6  8
 8  6
 5  4
 0  5
 6  4
 6  9
 7  6
|}     

let medium_test_cases = {|
50
147
 0  7
 0 34
 1 14
 1 45
 1 21
 1 22
 1 22
 1 49
 2 19
 2 25
 2 33
 3  4
 3 17
 3 27
 3 36
 3 42
 4 17
 4 17
 4 27
 5 43
 6 13
 6 13
 6 28
 6 28
 7 41
 7 44
 8 19
 8 48
 9  9
 9 11
 9 30
 9 46
10  0
10  7
10 28
10 28
10 28
10 29
10 29
10 34
10 41
11 21
11 30
12  9
12 11
12 21
12 21
12 26
13 22
13 23
13 47
14  8
14 21
14 48
15  8
15 34
15 49
16  9
17 20
17 24
17 38
18  6
18 28
18 32
18 42
19 15
19 40
20  3
20 35
20 38
20 46
22  6
23 11
23 21
23 22
24  4
24  5
24 38
24 43
25  2
25 34
26  9
26 12
26 16
27  5
27 24
27 32
27 31
27 42
28 22
28 29
28 39
28 44
29 22
29 49
30 23
30 37
31 18
31 32
32  5
32  6
32 13
32 37
32 47
33  2
33  8
33 19
34  2 
34 19
34 40
35  9
35 37
35 46
36 20
36 42
37  5
37  9
37 35
37 47
37 47
38 35
38 37
38 38
39 18
39 42
40 15
41 28
41 44
42 31
43 37
43 38
44 39
45  8
45 14
45 14
45 15
45 49
46 16
47 23
47 30
48 12
48 21
48 33
48 33
49 34
49 22
49 49
|}
(* 
reference output: 
http://algs4.cs.princeton.edu/42digraph/KosarajuSharirSCC.java.html 
*)

let handle_lines tiny_test_cases = 
  match Ext_string.split  tiny_test_cases '\n' with 
  | nodes :: _edges :: rest -> 
    let nodes_num = int_of_string nodes in 
    let node_array = 
      Array.init nodes_num
        (fun _ -> Vec_int.empty () )
    in 
    begin 
    Ext_list.iter rest (fun x ->
          match Ext_string.split x ' ' with 
          | [ a ; b] -> 
            let a , b = int_of_string a , int_of_string b in 
            Vec_int.push node_array.(a) b  
          | _ -> assert false 
        );
      node_array 
    end
  | _ -> assert false

let read_file file = 
  let in_chan = open_in_bin file in 
  let nodes_sum = int_of_string (input_line in_chan) in 
  let node_array = Array.init nodes_sum (fun _ -> Vec_int.empty () ) in 
  let rec aux () = 
    match input_line in_chan with 
    | exception End_of_file -> ()
    | x -> 
      begin match Ext_string.split x ' ' with 
      | [ a ; b] -> 
        let a , b = int_of_string a , int_of_string b in 
        Vec_int.push node_array.(a) b 
      | _ -> (* assert false  *) ()
      end; 
      aux () in 
  print_endline "read data into memory";
  aux ();
   (fst (Ext_scc.graph_check node_array)) (* 25 *)


let test  (input : (string * string list) list) = 
  (* string -> int mapping 
  *)
  let tbl = Hash_string.create 32 in
  let idx = ref 0 in 
  let add x =
    if not (Hash_string.mem tbl x ) then 
      begin 
        Hash_string.add  tbl x !idx ;
        incr idx 
      end in
  input |> List.iter 
    (fun (x,others) -> List.iter add (x::others));
  let nodes_num = Hash_string.length tbl in
  let node_array = 
      Array.init nodes_num
        (fun _ -> Vec_int.empty () ) in 
  input |> 
  List.iter (fun (x,others) -> 
      let idx = Hash_string.find_exn tbl  x  in 
      others |> 
      List.iter (fun y -> Vec_int.push node_array.(idx) (Hash_string.find_exn tbl y ) )
    ) ; 
  Ext_scc.graph_check node_array 

let test2  (input : (string * string list) list) = 
  (* string -> int mapping 
  *)
  let tbl = Hash_string.create 32 in
  let idx = ref 0 in 
  let add x =
    if not (Hash_string.mem tbl x ) then 
      begin 
        Hash_string.add  tbl x !idx ;
        incr idx 
      end in
  input |> List.iter 
    (fun (x,others) -> List.iter add (x::others));
  let nodes_num = Hash_string.length tbl in
  let other_mapping = Array.make nodes_num "" in 
  Hash_string.iter tbl (fun k v  -> other_mapping.(v) <- k ) ;
  
  let node_array = 
      Array.init nodes_num
        (fun _ -> Vec_int.empty () ) in 
  input |> 
  List.iter (fun (x,others) -> 
      let idx = Hash_string.find_exn tbl  x  in 
      others |> 
      List.iter (fun y -> Vec_int.push node_array.(idx) (Hash_string.find_exn tbl y ) )
    )  ;
  let output = Ext_scc.graph node_array in 
  output |> Int_vec_vec.map_into_array (fun int_vec -> Vec_int.map_into_array (fun i -> other_mapping.(i)) int_vec )


let suites = 
    __FILE__
    >::: [
      __LOC__ >:: begin fun _ -> 
        OUnit.assert_equal (fst @@ Ext_scc.graph_check (handle_lines tiny_test_cases))  5
      end       ;
      __LOC__ >:: begin fun _ -> 
        OUnit.assert_equal (fst @@ Ext_scc.graph_check (handle_lines medium_test_cases))  10
      end       ;
      __LOC__ >:: begin fun _ ->
        OUnit.assert_equal (test [
            "a", ["b" ; "c"];
            "b" , ["c" ; "d"];
            "c", [ "b"];
            "d", [];
          ]) (3 , [1;2;1])
      end ; 
      __LOC__ >:: begin fun _ ->
        OUnit.assert_equal (test [
            "a", ["b" ; "c"];
            "b" , ["c" ; "d"];
            "c", [ "b"];
            "d", [];
            "e", []
          ])  (4, [1;1;2;1])
          (*  {[
              a -> b
              a -> c 
              b -> c 
              b -> d 
              c -> b 
              d 
              e
              ]}
              {[
              [d ; e ; [b;c] [a] ]
              ]}  
          *)
      end ;
      __LOC__ >:: begin fun _ ->
        OUnit.assert_equal (test [
            "a", ["b" ; "c"];
            "b" , ["c" ; "d"];
            "c", [ "b"];
            "d", ["e"];
            "e", []
          ]) (4 , [1;2;1;1])
      end ; 
      __LOC__ >:: begin fun _ ->
        OUnit.assert_equal (test [
            "a", ["b" ; "c"];
            "b" , ["c" ; "d"];
            "c", [ "b"];
            "d", ["e"];
            "e", ["c"]
          ]) (2, [1;4])
      end ;
      __LOC__ >:: begin fun _ ->
        OUnit.assert_equal (test [
            "a", ["b" ; "c"];
            "b" , ["c" ; "d"];
            "c", [ "b"];
            "d", ["e"];
            "e", ["a"]
          ]) (1, [5])
      end ; 
      __LOC__ >:: begin fun _ ->
        OUnit.assert_equal (test [
            "a", ["b"];
            "b" , ["c" ];
            "c", [ ];
            "d", [];
            "e", []
          ]) (5, [1;1;1;1;1])
      end ; 
      __LOC__ >:: begin fun _ ->
        OUnit.assert_equal (test [
            "1", ["0"];
            "0" , ["2" ];
            "2", ["1" ];
            "0", ["3"];
            "3", [ "4"]
          ]) (3, [3;1;1])
      end ; 
      (* http://algs4.cs.princeton.edu/42digraph/largeDG.txt *)
      (* __LOC__ >:: begin fun _ -> *)
      (*   OUnit.assert_equal (read_file "largeDG.txt") 25 *)
      (* end *)
      (* ; *)
      __LOC__ >:: begin fun _ ->
        OUnit.assert_equal (test2 [
            "a", ["b" ; "c"];
            "b" , ["c" ; "d"];
            "c", [ "b"];
            "d", [];
          ]) [|[|"d"|]; [|"b"; "c"|]; [|"a"|]|]
      end ;

      __LOC__ >:: begin fun _ ->
        OUnit.assert_equal (test2 [
            "a", ["b"];
            "b" , ["c" ];
            "c", ["d" ];
            "d", ["e"];
            "e", []
          ]) [|[|"e"|]; [|"d"|]; [|"c"|]; [|"b"|]; [|"a"|]|] 
      end ;

    ]

end
module Ext_digest : sig 
#1 "ext_digest.mli"
(* Copyright (C) 2019- Authors of ReScript
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


val length : int 

val hex_length : int
end = struct
#1 "ext_digest.ml"
(* Copyright (C) 2019- Hongbo Zhang, Authors of ReScript
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


let length = 16

let hex_length = 32
end
module Ext_filename : sig 
#1 "ext_filename.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)





(* TODO:
   Change the module name, this code is not really an extension of the standard 
    library but rather specific to JS Module name convention. 
*)





(** An extension module to calculate relative path follow node/npm style. 
    TODO : this short name will have to change upon renaming the file.
*)

val is_dir_sep : 
  char -> bool 

val maybe_quote:
  string -> 
  string

val chop_extension_maybe:
  string -> 
  string

(* return an empty string if no extension found *)  
val get_extension_maybe:   
  string -> 
  string


val new_extension:  
  string -> 
  string -> 
  string

val chop_all_extensions_maybe:
  string -> 
  string  

(* OCaml specific abstraction*)
val module_name:  
  string ->
  string




type module_info = {
  module_name : string ;
  case : bool;
}   



val as_module:
  basename:string -> 
  module_info option
end = struct
#1 "ext_filename.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)




let is_dir_sep_unix c = c = '/'
let is_dir_sep_win_cygwin c = 
  c = '/' || c = '\\' || c = ':'

let is_dir_sep = 
  if Sys.unix then is_dir_sep_unix else is_dir_sep_win_cygwin

(* reference ninja.cc IsKnownShellSafeCharacter *)
let maybe_quote ( s : string) = 
  let noneed_quote = 
    Ext_string.for_all s (function
        | '0' .. '9' 
        | 'a' .. 'z' 
        | 'A' .. 'Z'
        | '_' | '+' 
        | '-' | '.'
        | '/' 
        | '@' -> true
        | _ -> false
      )  in 
  if noneed_quote then
    s
  else Filename.quote s 


let chop_extension_maybe name =
  let rec search_dot i =
    if i < 0 || is_dir_sep (String.unsafe_get name i) then name
    else if String.unsafe_get name i = '.' then String.sub name 0 i
    else search_dot (i - 1) in
  search_dot (String.length name - 1)

let get_extension_maybe name =   
  let name_len = String.length name in  
  let rec search_dot name i name_len =
    if i < 0 || is_dir_sep (String.unsafe_get name i) then ""
    else if String.unsafe_get name i = '.' then String.sub name i (name_len - i)
    else search_dot name (i - 1) name_len in
  search_dot name (name_len - 1) name_len

let chop_all_extensions_maybe name =
  let rec search_dot i last =
    if i < 0 || is_dir_sep (String.unsafe_get name i) then 
      (match last with 
       | None -> name
       | Some i -> String.sub name 0 i)  
    else if String.unsafe_get name i = '.' then 
      search_dot (i - 1) (Some i)
    else search_dot (i - 1) last in
  search_dot (String.length name - 1) None


let new_extension name (ext : string) = 
  let rec search_dot name i ext =
    if i < 0 || is_dir_sep (String.unsafe_get name i) then 
      name ^ ext 
    else if String.unsafe_get name i = '.' then 
      let ext_len = String.length ext in
      let buf = Bytes.create (i + ext_len) in 
      Bytes.blit_string name 0 buf 0 i;
      Bytes.blit_string ext 0 buf i ext_len;
      Bytes.unsafe_to_string buf
    else search_dot name (i - 1) ext  in
  search_dot name (String.length name - 1) ext



(** TODO: improve efficiency
    given a path, calcuate its module name 
    Note that `ocamlc.opt -c aa.xx.mli` gives `aa.xx.cmi`
    we can not strip all extensions, otherwise
    we can not tell the difference between "x.cpp.ml" 
    and "x.ml"
*)
let module_name name = 
  let rec search_dot i  name =
    if i < 0  then 
      Ext_string.capitalize_ascii name
    else 
    if String.unsafe_get name i = '.' then 
      Ext_string.capitalize_sub name i 
    else 
      search_dot (i - 1) name in  
  let name = Filename.basename  name in 
  let name_len = String.length name in 
  search_dot (name_len - 1)  name 

type module_info = {
  module_name : string ;
  case : bool;
} 



let rec valid_module_name_aux name off len =
  if off >= len then true 
  else 
    let c = String.unsafe_get name off in 
    match c with 
    | 'A'..'Z' | 'a'..'z' | '0'..'9' | '_' | '\'' | '.' | '[' | ']' -> 
      valid_module_name_aux name (off + 1) len 
    | _ -> false

type state = 
  | Invalid
  | Upper
  | Lower

let valid_module_name name len =     
  if len = 0 then Invalid
  else 
    let c = String.unsafe_get name 0 in 
    match c with 
    | 'A' .. 'Z'
      -> 
      if valid_module_name_aux name 1 len then 
        Upper
      else Invalid  
    | 'a' .. 'z' 
    | '0' .. '9'
    | '_'
    | '[' 
    | ']'
      -> 
      if valid_module_name_aux name 1 len then
        Lower
      else Invalid
    | _ -> Invalid


let as_module ~basename =
  let rec search_dot i  name name_len =
    if i < 0  then
      (* Input e.g, [a_b] *)
      match valid_module_name name name_len with 
      | Invalid -> None 
      | Upper ->  Some {module_name = name; case = true }
      | Lower -> Some {module_name = Ext_string.capitalize_ascii name; case = false}
    else 
    if String.unsafe_get name i = '.' then 
      (*Input e.g, [A_b] *)
      match valid_module_name  name i with 
      | Invalid -> None 
      | Upper -> 
        Some {module_name = Ext_string.capitalize_sub name i; case = true}
      | Lower -> 
        Some {module_name = Ext_string.capitalize_sub name i; case = false}
    else 
      search_dot (i - 1) name name_len in  
  let name_len = String.length basename in       
  search_dot (name_len - 1)  basename name_len

end
module Ext_modulename : sig 
#1 "ext_modulename.mli"
(* Copyright (C) 2017 Authors of ReScript
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)




(** Given an JS bundle name, generate a meaningful
    bounded module name
*)
val js_id_name_of_hint_name : string -> string 
end = struct
#1 "ext_modulename.ml"
(* Copyright (C) 2017 Hongbo Zhang, Authors of ReScript
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)








let good_hint_name module_name offset =
  let len = String.length module_name in 
  len > offset && 
  (function | 'a' .. 'z' | 'A' .. 'Z' -> true | _ -> false) 
    (String.unsafe_get module_name offset) &&
  Ext_string.for_all_from module_name (offset + 1) 
    (function 
      | 'a' .. 'z' 
      | 'A' .. 'Z' 
      | '0' .. '9' 
      | '_' 
        -> true
      | _ -> false)

let rec collect_start buf s off len = 
  if off >= len then ()
  else 
    let next = succ off in 
    match String.unsafe_get  s off with     
    | 'a' .. 'z' as c ->
      Ext_buffer.add_char buf (Char.uppercase_ascii c)
      ;
      collect_next buf s next len
    | 'A' .. 'Z' as c -> 
      Ext_buffer.add_char buf c ;
      collect_next buf s next len
    | _ -> collect_start buf s next len
and collect_next buf s off len = 
  if off >= len then ()  
  else 
    let next = off + 1 in 
    match String.unsafe_get s off with 
    | 'a' .. 'z'
    | 'A' .. 'Z'
    | '0' .. '9'
    | '_'
    as c ->
      Ext_buffer.add_char buf c ;
      collect_next buf s next len 
    | '.'
    | '-' -> 
      collect_start buf s next len      
    | _ -> 
      collect_next buf s next len 

(** This is for a js exeternal module, we can change it when printing
    for example
    {[
      var React$1 = require('react');
      React$1.render(..)
    ]}
    Given a name, if duplicated, they should  have the same id
*)
let js_id_name_of_hint_name module_name =       
  let i = Ext_string.rindex_neg module_name '/' in 
  if i >= 0 then
    let offset = succ i in 
    if good_hint_name module_name offset then 
      Ext_string.capitalize_ascii
        (Ext_string.tail_from module_name offset)
    else 
      let str_len = String.length module_name in 
      let buf = Ext_buffer.create str_len in 
      collect_start buf module_name offset str_len ;
      if Ext_buffer.is_empty buf then 
        Ext_string.capitalize_ascii module_name
      else Ext_buffer.contents buf 
  else 
  if good_hint_name module_name 0 then
    Ext_string.capitalize_ascii module_name
  else 
    let str_len = (String.length module_name) in 
    let buf = Ext_buffer.create str_len in 
    collect_start buf module_name 0 str_len ;    
    if Ext_buffer.is_empty buf then module_name
    else  Ext_buffer.contents buf 

end
module Ext_js_suffix
= struct
#1 "ext_js_suffix.ml"
type t = 
  | Js 
  | Bs_js   
  | Mjs
  | Cjs
  | Unknown_extension
let to_string (x : t) =   
  match x with 
  | Js -> Literals.suffix_js
  | Bs_js -> Literals.suffix_bs_js  
  | Mjs -> Literals.suffix_mjs
  | Cjs -> Literals.suffix_cjs
  | Unknown_extension -> assert false


let of_string (x : string) : t =
  match () with 
  | () when x = Literals.suffix_js -> Js 
  | () when x = Literals.suffix_bs_js -> Bs_js       
  | () when x = Literals.suffix_mjs -> Mjs
  | () when x = Literals.suffix_cjs -> Cjs 
  | _ -> Unknown_extension


end
module Ext_js_file_kind
= struct
#1 "ext_js_file_kind.ml"
(* Copyright (C) 2020- Hongbo Zhang, Authors of ReScript
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)
type case = 
  | Upper
  | Little 

type t = {
  case : case; 
  suffix : Ext_js_suffix.t;
}


let any_runtime_kind = {
  case = Little; 
  suffix = Ext_js_suffix.Js
}
end
module Ext_namespace : sig 
#1 "ext_namespace.mli"
(* Copyright (C) 2017- Authors of ReScript
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)



val try_split_module_name :
  string -> (string * string ) option



(* Note  we have to output uncapitalized file Name, 
   or at least be consistent, since by reading cmi file on Case insensitive OS, we don't really know it is `list.cmi` or `List.cmi`, so that `require (./list.js)` or `require(./List.js)`
   relevant issues: #1609, #913  

   #1933 when removing ns suffix, don't pass the bound
   of basename
*)
val change_ext_ns_suffix :  
  string -> 
  string ->
  string



(** [js_name_of_modulename ~little A-Ns]
*)
val js_name_of_modulename : 
  string -> 
  Ext_js_file_kind.case -> 
  Ext_js_suffix.t ->
  string

(* TODO handle cases like 
   '@angular/core'
   its directory structure is like 
   {[
     @angular
     |-------- core
   ]}
*)
val is_valid_npm_package_name : string -> bool 

val namespace_of_package_name : string -> string

end = struct
#1 "ext_namespace.ml"

(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)





let rec rindex_rec s i  =
  if i < 0 then i else
    let char = String.unsafe_get s i in
    if Ext_filename.is_dir_sep char  then -1 
    else if char = Literals.ns_sep_char then i 
    else
      rindex_rec s (i - 1) 

let change_ext_ns_suffix name ext =
  let i = rindex_rec name (String.length name - 1)  in 
  if i < 0 then name ^ ext
  else String.sub name 0 i ^ ext (* FIXME: micro-optimizaiton*)

let try_split_module_name name = 
  let len = String.length name in 
  let i = rindex_rec name (len - 1)  in 
  if i < 0 then None 
  else 
    Some (String.sub name (i+1) (len - i - 1),
          String.sub name 0 i )





let js_name_of_modulename s (case : Ext_js_file_kind.case) suffix : string = 
  let s = match case with 
    | Little -> 
      Ext_string.uncapitalize_ascii s
    | Upper -> s  in 
  change_ext_ns_suffix s  (Ext_js_suffix.to_string suffix)

(* https://docs.npmjs.com/files/package.json 
   Some rules:
   The name must be less than or equal to 214 characters. This includes the scope for scoped packages.
   The name can't start with a dot or an underscore.
   New packages must not have uppercase letters in the name.
   The name ends up being part of a URL, an argument on the command line, and a folder name. Therefore, the name can't contain any non-URL-safe characters.
*)
let is_valid_npm_package_name (s : string) = 
  let len = String.length s in 
  len <= 214 && (* magic number forced by npm *)
  len > 0 &&
  match String.unsafe_get s 0 with 
  | 'a' .. 'z' | '@' -> 
    Ext_string.for_all_from s 1 
      (fun x -> 
         match x with 
         |  'a'..'z' | '0'..'9' | '_' | '-' -> true
         | _ -> false )
  | _ -> false 


let namespace_of_package_name (s : string) : string = 
  let len = String.length s in 
  let buf = Ext_buffer.create len in 
  let add capital ch = 
    Ext_buffer.add_char buf 
      (if capital then 
         (Char.uppercase_ascii ch)
       else ch) in    
  let rec aux capital off len =     
    if off >= len then ()
    else 
      let ch = String.unsafe_get s off in
      match ch with 
      | 'a' .. 'z' 
      | 'A' .. 'Z' 
      | '0' .. '9'
      | '_'
        ->
        add capital ch ; 
        aux false (off + 1) len 
      | '/'
      | '-' -> 
        aux true (off + 1) len 
      | _ -> aux capital (off+1) len
  in 
  aux true 0 len ;
  Ext_buffer.contents buf 

end
module Ounit_data_random
= struct
#1 "ounit_data_random.ml"


let min_int x y = 
    if x < y then x else y

let random_string chars upper = 
    let len = Array.length chars in 
    let string_len = (Random.int (min_int upper len)) in
    String.init string_len (fun _i -> chars.(Random.int len ))
end
module Ounit_string_tests
= struct
#1 "ounit_string_tests.ml"
let ((>::),
     (>:::)) = OUnit.((>::),(>:::))

let (=~) = OUnit.assert_equal  ~printer:Ext_obj.dump  

let printer_string = fun x -> x 

let string_eq = OUnit.assert_equal ~printer:(fun id -> id)

let suites = 
  __FILE__ >::: 
  [
    __LOC__ >:: begin fun _ ->
      OUnit.assert_bool "not found " (Ext_string.rindex_neg "hello" 'x' < 0 )
    end;

    __LOC__ >:: begin fun _ -> 
      Ext_string.rindex_neg "hello" 'h' =~ 0 ;
      Ext_string.rindex_neg "hello" 'e' =~ 1 ;
      Ext_string.rindex_neg "hello" 'l' =~ 3 ;
      Ext_string.rindex_neg "hello" 'l' =~ 3 ;
      Ext_string.rindex_neg "hello" 'o' =~ 4 ;
    end;
    (* __LOC__ >:: begin 
      fun _ -> 
      let nl cur s = Ext_string.extract_until s cur '\n' in 
      nl (ref 0) "hello\n" =~ "hello";
      nl (ref 0) "\nhell" =~ "";
      nl (ref 0) "hello" =~ "hello";
      let cur = ref 0 in 
      let b = "a\nb\nc\nd" in 
      nl cur b =~ "a";
      nl cur b =~ "b";
      nl cur b =~ "c";
      nl cur b =~ "d";
      nl cur b =~ "" ;
      nl cur b =~ "" ;
      cur := 0 ;
      let b = "a\nb\nc\nd\n" in 
      nl cur b =~ "a";
      nl cur b =~ "b";
      nl cur b =~ "c";
      nl cur b =~ "d";
      nl cur b =~ "" ;
      nl cur b =~ "" ;
    end ; *)
    __LOC__ >:: begin fun _ -> 
      let b = "a\nb\nc\nd\n" in
      let a = Ext_string.index_count in 
      a b 0 '\n' 1 =~ 1 ;
      a b 0 '\n' 2 =~ 3;
      a b 0 '\n' 3 =~ 5;
      a b 0 '\n' 4 =~ 7; 
      a b 0 '\n' 5 =~ -1; 
    end ;
    __LOC__ >:: begin fun _ -> 
      OUnit.assert_bool "empty string" (Ext_string.rindex_neg "" 'x' < 0 )
    end;

    __LOC__ >:: begin fun _ -> 
      OUnit.assert_bool __LOC__
        (not (Ext_string.for_all_from "xABc"1
                (function 'A' .. 'Z' -> true | _ -> false)));
      OUnit.assert_bool __LOC__
        ( (Ext_string.for_all_from "xABC" 1
             (function 'A' .. 'Z' -> true | _ -> false)));
      OUnit.assert_bool __LOC__
        ( (Ext_string.for_all_from "xABC" 1_000
             (function 'A' .. 'Z' -> true | _ -> false)));             
    end; 

    (* __LOC__ >:: begin fun _ -> 
      OUnit.assert_bool __LOC__ @@
      List.for_all (fun x -> Ext_string.is_valid_source_name x = Good)
        ["x.ml"; "x.mli"; "x.re"; "x.rei"; 
         "A_x.ml"; "ab.ml"; "a_.ml"; "a__.ml";
         "ax.ml"];
      OUnit.assert_bool __LOC__ @@ not @@
      List.exists (fun x -> Ext_string.is_valid_source_name x = Good)
        [".re"; ".rei";"..re"; "..rei"; "..ml"; ".mll~"; 
         "...ml"; "_.mli"; "_x.ml"; "__.ml"; "__.rei"; 
         ".#hello.ml"; ".#hello.rei"; "a-.ml"; "a-b.ml"; "-a-.ml"
        ; "-.ml"
        ]
    end; *)
    __LOC__ >:: begin fun _ -> 
      Ext_filename.module_name "a/hello.ml" =~ "Hello";
      Ext_filename.as_module ~basename:"a.ml" =~ Some {module_name = "A"; case = false};
      Ext_filename.as_module ~basename:"Aa.ml" =~ Some {module_name = "Aa"; case = true};
      (* Ext_filename.as_module ~basename:"_Aa.ml" =~ None; *)
      Ext_filename.as_module ~basename:"A_a" =~ Some {module_name = "A_a"; case = true};
      Ext_filename.as_module ~basename:"" =~ None;
      Ext_filename.as_module ~basename:"a/hello.ml" =~ 
        None

    end;
    __LOC__ >:: begin fun _ -> 
      OUnit.assert_bool __LOC__ @@
      List.for_all Ext_namespace.is_valid_npm_package_name
        ["x"; "@angualr"; "test"; "hi-x"; "hi-"]
      ;
      OUnit.assert_bool __LOC__ @@
      List.for_all 
        (fun x -> not (Ext_namespace.is_valid_npm_package_name x))
        ["x "; "x'"; "Test"; "hI"]
      ;
    end;
    __LOC__ >:: begin fun _ -> 
      Ext_string.find ~sub:"hello" "xx hello xx" =~ 3 ;
      Ext_string.rfind ~sub:"hello" "xx hello xx" =~ 3 ;
      Ext_string.find ~sub:"hello" "xx hello hello xx" =~ 3 ;
      Ext_string.rfind ~sub:"hello" "xx hello hello xx" =~ 9 ;
    end;
    __LOC__ >:: begin fun _ -> 
      Ext_string.non_overlap_count ~sub:"0" "1000,000" =~ 6;
      Ext_string.non_overlap_count ~sub:"0" "000000" =~ 6;
      Ext_string.non_overlap_count ~sub:"00" "000000" =~ 3;
      Ext_string.non_overlap_count ~sub:"00" "00000" =~ 2
    end;
    __LOC__ >:: begin fun _ -> 
      OUnit.assert_bool __LOC__ (Ext_string.contain_substring "abc" "abc");
      OUnit.assert_bool __LOC__ (Ext_string.contain_substring "abc" "a");
      OUnit.assert_bool __LOC__ (Ext_string.contain_substring "abc" "b");
      OUnit.assert_bool __LOC__ (Ext_string.contain_substring "abc" "c");
      OUnit.assert_bool __LOC__ (Ext_string.contain_substring "abc" "");
      OUnit.assert_bool __LOC__ (not @@ Ext_string.contain_substring "abc" "abcc");
    end;
    __LOC__ >:: begin fun _ -> 
      Ext_string.trim " \t\n" =~ "";
      Ext_string.trim " \t\nb" =~ "b";
      Ext_string.trim "b \t\n" =~ "b";
      Ext_string.trim "\t\n b \t\n" =~ "b";            
    end;
    __LOC__ >:: begin fun _ -> 
      Ext_string.starts_with "ab" "a" =~ true;
      Ext_string.starts_with "ab" "" =~ true;
      Ext_string.starts_with "abb" "abb" =~ true;
      Ext_string.starts_with "abb" "abbc" =~ false;
    end;
    __LOC__ >:: begin fun _ -> 
      let (=~) = OUnit.assert_equal ~printer:(fun x -> string_of_bool x ) in 
      let k = Ext_string.ends_with in 
      k "xx.ml" ".ml" =~ true;
      k "xx.bs.js" ".js" =~ true ;
      k "xx" ".x" =~false;
      k "xx" "" =~true
    end;  
    __LOC__ >:: begin fun _ -> 
      Ext_string.ends_with_then_chop "xx.ml"  ".ml" =~ Some "xx";
      Ext_string.ends_with_then_chop "xx.ml" ".mll" =~ None
    end;
    (* __LOC__ >:: begin fun _ -> 
       Ext_string.starts_with_and_number "js_fn_mk_01" ~offset:0 "js_fn_mk_" =~ 1 ;
       Ext_string.starts_with_and_number "js_fn_run_02" ~offset:0 "js_fn_mk_" =~ -1 ;
       Ext_string.starts_with_and_number "js_fn_mk_03" ~offset:6 "mk_" =~ 3 ;
       Ext_string.starts_with_and_number "js_fn_mk_04" ~offset:6 "run_" =~ -1;
       Ext_string.starts_with_and_number "js_fn_run_04" ~offset:6 "run_" =~ 4;
       Ext_string.(starts_with_and_number "js_fn_run_04" ~offset:6 "run_" = 3) =~ false 
       end; *)
    __LOC__ >:: begin fun _ -> 
      Ext_string.for_all "____" (function '_' -> true | _ -> false)
        =~ true;
      Ext_string.for_all "___-" (function '_' -> true | _ -> false)
        =~ false;
      Ext_string.for_all ""  (function '_' -> true | _ -> false)        
        =~ true
    end;
    __LOC__ >:: begin fun _ -> 
      Ext_string.tail_from "ghsogh" 1 =~ "hsogh";
      Ext_string.tail_from "ghsogh" 0 =~ "ghsogh"
    end;
    (* __LOC__ >:: begin fun _ -> 
       Ext_string.digits_of_str "11_js" ~offset:0 2 =~ 11 
       end; *)
    __LOC__ >:: begin fun _ -> 
      OUnit.assert_bool __LOC__ 
        (Ext_string.replace_backward_slash "a:\\b\\d" = 
         "a:/b/d"
        ) ;
      OUnit.assert_bool __LOC__ 
        (Ext_string.replace_backward_slash "a:\\b\\d\\" = 
         "a:/b/d/"
        ) ;
      OUnit.assert_bool __LOC__ 
        (Ext_string.replace_slash_backward "a:/b/d/"= 
         "a:\\b\\d\\" 
        ) ;  
      OUnit.assert_bool __LOC__ 
        (let old = "a:bd" in 
         Ext_string.replace_backward_slash old == 
         old
        ) ;
      OUnit.assert_bool __LOC__ 
        (let old = "a:bd" in 
         Ext_string.replace_backward_slash old == 
         old
        ) ;

    end;
    __LOC__ >:: begin fun _ -> 
      OUnit.assert_bool __LOC__ 
        (Ext_string.no_slash "ahgoh" );
      OUnit.assert_bool __LOC__ 
        (Ext_string.no_slash "" );            
      OUnit.assert_bool __LOC__ 
        (not (Ext_string.no_slash "ahgoh/" ));
      OUnit.assert_bool __LOC__ 
        (not (Ext_string.no_slash "/ahgoh" ));
      OUnit.assert_bool __LOC__ 
        (not (Ext_string.no_slash "/ahgoh/" ));            
    end;
    __LOC__ >:: begin fun _ -> 
      OUnit.assert_bool __LOC__ (Ext_string.compare "" ""  = 0);
      OUnit.assert_bool __LOC__ (Ext_string.compare "0" "0"  = 0);
      OUnit.assert_bool __LOC__ (Ext_string.compare "" "acd" < 0);
      OUnit.assert_bool __LOC__ (Ext_string.compare  "acd" "" > 0);
      for i = 0 to 256 do 
        let a = String.init i (fun _ -> '0') in 
        let b = String.init i (fun _ -> '0') in 
        OUnit.assert_bool __LOC__ (Ext_string.compare  b a = 0);
        OUnit.assert_bool __LOC__ (Ext_string.compare a b = 0)
      done ;
      for i = 0 to 256 do 
        let a = String.init i (fun _ -> '0') in 
        let b = String.init i (fun _ -> '0') ^ "\000"in 
        OUnit.assert_bool __LOC__ (Ext_string.compare a b < 0);
        OUnit.assert_bool __LOC__ (Ext_string.compare  b a  > 0)
      done ;

    end;
    __LOC__ >:: begin fun _ -> 
      let slow_compare x y  = 
        let x_len = String.length x  in 
        let y_len = String.length y in 
        if x_len = y_len then 
          String.compare x y 
        else 
          Pervasives.compare x_len y_len  in 
      let same_sign x y =
        if x = 0 then y = 0 
        else if x < 0 then y < 0 
        else y > 0 in 
      for _ = 0 to 3000 do
        let chars = [|'a';'b';'c';'d'|] in 
        let x = Ounit_data_random.random_string chars 129 in 
        let y = Ounit_data_random.random_string chars 129 in 
        let a = Ext_string.compare  x y  in 
        let b = slow_compare x y in 
        if same_sign a b then OUnit.assert_bool __LOC__ true 
        else failwith ("incosistent " ^ x ^ " " ^ y ^ " " ^ string_of_int a ^ " " ^ string_of_int b)
      done 
    end ;
    __LOC__ >:: begin fun _ -> 
      OUnit.assert_bool __LOC__ 
        (Ext_string.equal
           (Ext_string.concat3 "a0" "a1" "a2") "a0a1a2"
        );
      OUnit.assert_bool __LOC__ 
        (Ext_string.equal
           (Ext_string.concat3 "a0" "a11" "") "a0a11"
        );

      OUnit.assert_bool __LOC__ 
        (Ext_string.equal
           (Ext_string.concat4 "a0" "a1" "a2" "a3") "a0a1a2a3"
        );
      OUnit.assert_bool __LOC__ 
        (Ext_string.equal
           (Ext_string.concat4 "a0" "a11" "" "a33") "a0a11a33"
        );   
    end;
    __LOC__ >:: begin fun _ -> 
      OUnit.assert_bool __LOC__ 
        (Ext_string.equal
           (Ext_string.inter2 "a0" "a1") "a0 a1"
        );
      OUnit.assert_bool __LOC__ 
        (Ext_string.equal
           (Ext_string.inter3 "a0" "a1" "a2") "a0 a1 a2"
        );
      OUnit.assert_bool __LOC__ 
        (Ext_string.equal
           (Ext_string.inter4 "a0" "a1" "a2" "a3") "a0 a1 a2 a3"
        );
    end;
    __LOC__ >:: begin fun _ -> 
      OUnit.assert_bool __LOC__ 
        (Ext_string.no_slash_idx "" < 0);
      OUnit.assert_bool __LOC__ 
        (Ext_string.no_slash_idx "xxx" < 0);
      OUnit.assert_bool __LOC__ 
        (Ext_string.no_slash_idx "xxx/" = 3);
      OUnit.assert_bool __LOC__ 
        (Ext_string.no_slash_idx "xxx/g/" = 3);
      OUnit.assert_bool __LOC__ 
        (Ext_string.no_slash_idx "/xxx/g/" = 0)
    end;
    __LOC__ >:: begin fun _ -> 
      OUnit.assert_bool __LOC__ 
        (Ext_string.no_slash_idx_from "xxx" 0 < 0);
      OUnit.assert_bool __LOC__ 
        (Ext_string.no_slash_idx_from "xxx/" 1 = 3);
      OUnit.assert_bool __LOC__ 
        (Ext_string.no_slash_idx_from "xxx/g/" 4 = 5);
      OUnit.assert_bool __LOC__ 
        (Ext_string.no_slash_idx_from "xxx/g/" 3 = 3);  
      OUnit.assert_bool __LOC__ 
        (Ext_string.no_slash_idx_from "/xxx/g/" 0 = 0)
    end;
    __LOC__ >:: begin fun _ -> 
      OUnit.assert_bool __LOC__
        (Ext_string.equal 
           (Ext_string.concat_array Ext_string.single_space [||])
           Ext_string.empty
        );
      OUnit.assert_bool __LOC__
        (Ext_string.equal 
           (Ext_string.concat_array Ext_string.single_space [|"a0"|])
           "a0"
        );
      OUnit.assert_bool __LOC__
        (Ext_string.equal 
           (Ext_string.concat_array Ext_string.single_space [|"a0";"a1"|])
           "a0 a1"
        );   
      OUnit.assert_bool __LOC__
        (Ext_string.equal 
           (Ext_string.concat_array Ext_string.single_space [|"a0";"a1"; "a2"|])
           "a0 a1 a2"
        );   
      OUnit.assert_bool __LOC__
        (Ext_string.equal 
           (Ext_string.concat_array Ext_string.single_space [|"a0";"a1"; "a2";"a3"|])
           "a0 a1 a2 a3"
        );    
      OUnit.assert_bool __LOC__
        (Ext_string.equal 
           (Ext_string.concat_array Ext_string.single_space [|"a0";"a1"; "a2";"a3";""; "a4"|])
           "a0 a1 a2 a3  a4"
        );      
      OUnit.assert_bool __LOC__
        (Ext_string.equal 
           (Ext_string.concat_array Ext_string.single_space [|"0";"a1"; "2";"a3";""; "a4"|])
           "0 a1 2 a3  a4"
        );        
      OUnit.assert_bool __LOC__
        (Ext_string.equal 
           (Ext_string.concat_array Ext_string.single_space [|"0";"a1"; "2";"3";"d"; ""; "e"|])
           "0 a1 2 3 d  e"
        );        

    end;

    __LOC__ >:: begin fun _ ->
      Ext_namespace.namespace_of_package_name "bs-json"
      =~ "BsJson"
    end;
    __LOC__ >:: begin fun _ -> 
      Ext_namespace.namespace_of_package_name "xx"
      =~ "Xx"
    end;
    __LOC__ >:: begin fun _ ->
      let (=~) = OUnit.assert_equal ~printer:(fun x -> x) in
      Ext_namespace.namespace_of_package_name
        "reason-react"
      =~ "ReasonReact";
      Ext_namespace.namespace_of_package_name
          "Foo_bar"
        =~ "Foo_bar";
      Ext_namespace.namespace_of_package_name
        "reason"
      =~ "Reason";
      Ext_namespace.namespace_of_package_name 
        "@aa/bb"
        =~"AaBb";
      Ext_namespace.namespace_of_package_name 
        "@A/bb"
        =~"ABb"        
    end;
    __LOC__ >:: begin fun _ -> 
      Ext_namespace.change_ext_ns_suffix  "a-b" Literals.suffix_js
      =~ "a.js";
      Ext_namespace.change_ext_ns_suffix  "a-" Literals.suffix_js
      =~ "a.js";
      Ext_namespace.change_ext_ns_suffix  "a--" Literals.suffix_js
      =~ "a-.js";
      Ext_namespace.change_ext_ns_suffix  "AA-b" Literals.suffix_js
      =~ "AA.js";
      Ext_namespace.js_name_of_modulename 
        "AA-b" Little  Js
      =~ "aA.js";
      Ext_namespace.js_name_of_modulename 
        "AA-b" Upper  Js
      =~ "AA.js";
      Ext_namespace.js_name_of_modulename 
        "AA-b" Upper Bs_js
      =~ "AA.bs.js";
    end;
    __LOC__ >:: begin   fun _ -> 
      let (=~) = OUnit.assert_equal ~printer:(fun x -> 
          match x with 
          | None -> ""
          | Some (a,b) -> a ^","^ b
        ) in  
      Ext_namespace.try_split_module_name "Js-X" =~ Some ("X","Js");
      Ext_namespace.try_split_module_name "Js_X" =~ None
    end;
    __LOC__ >:: begin fun _ ->
      let (=~) = OUnit.assert_equal ~printer:(fun x -> x) in  
      let f = Ext_string.capitalize_ascii in
      f "x" =~ "X";
      f "X" =~ "X";
      f "" =~ "";
      f "abc" =~ "Abc";
      f "_bc" =~ "_bc";
      let v = "bc" in
      f v =~ "Bc";
      v =~ "bc"
    end;
    __LOC__ >:: begin fun _ -> 
      let (=~) = OUnit.assert_equal ~printer:printer_string in 
      Ext_filename.chop_all_extensions_maybe "a.bs.js" =~ "a" ; 
      Ext_filename.chop_all_extensions_maybe "a.js" =~ "a";
      Ext_filename.chop_all_extensions_maybe "a" =~ "a";
      Ext_filename.chop_all_extensions_maybe "a.x.bs.js" =~ "a"
    end;
    (* let (=~) = OUnit.assert_equal ~printer:(fun x -> x) in  *)
    __LOC__ >:: begin fun _ ->
      let k = Ext_modulename.js_id_name_of_hint_name in 
      k "xx" =~ "Xx";
      k "react-dom" =~ "ReactDom";
      k "a/b/react-dom" =~ "ReactDom";
      k "a/b" =~ "B";
      k "a/" =~ "A/" ; (*TODO: warning?*)
      k "#moduleid" =~ "Moduleid";
      k "@bundle" =~ "Bundle";
      k "xx#bc" =~ "Xxbc";
      k "hi@myproj" =~ "Himyproj";
      k "ab/c/xx.b.js" =~ "XxBJs"; (* improve it in the future*)
      k "c/d/a--b"=~ "AB";
      k "c/d/ac--" =~ "Ac"
    end ;
    __LOC__ >:: begin fun _ -> 
      Ext_string.capitalize_sub "ab-Ns.cmi" 2 =~ "Ab";
      Ext_string.capitalize_sub "Ab-Ns.cmi" 2 =~ "Ab";
      Ext_string.capitalize_sub "Ab-Ns.cmi" 3 =~ "Ab-"
    end ;
    __LOC__ >:: begin fun _ ->
      OUnit.assert_equal 
        (String.length (Digest.string "")) 
         Ext_digest.length
    end;

    __LOC__ >:: begin fun _ -> 
      let bench = String.concat 
        ";" (Ext_list.init 11 (fun i -> string_of_int i)) in
      let buf = Ext_buffer.create 10 in 
      OUnit.assert_bool
        __LOC__ (Ext_buffer.not_equal buf bench); 
      for i = 0 to 9 do   
        Ext_buffer.add_string buf (string_of_int i);
        Ext_buffer.add_string buf ";"
      done ;
      OUnit.assert_bool
        __LOC__ (Ext_buffer.not_equal buf bench); 
      Ext_buffer.add_string buf "10"  ;
      (* print_endline (Ext_buffer.contents buf);
      print_endline bench; *)
      OUnit.assert_bool
      __LOC__ (not (Ext_buffer.not_equal buf bench))
    end ;

    __LOC__ >:: begin fun _ -> 
        string_eq (Ext_filename.new_extension "a.c" ".xx")  "a.xx";
        string_eq (Ext_filename.new_extension "abb.c" ".xx")  "abb.xx";
        string_eq (Ext_filename.new_extension ".c" ".xx")  ".xx";
        string_eq (Ext_filename.new_extension "a/b" ".xx")  "a/b.xx";
        string_eq (Ext_filename.new_extension "a/b." ".xx")  "a/b.xx";
        string_eq (Ext_filename.chop_all_extensions_maybe "a.b.x") "a";
        string_eq (Ext_filename.chop_all_extensions_maybe "a.b") "a";
        string_eq (Ext_filename.chop_all_extensions_maybe ".a.b.x") "";
        string_eq (Ext_filename.chop_all_extensions_maybe "abx") "abx";
    end;
    __LOC__ >:: begin fun _ ->
        string_eq 
          (Ext_filename.module_name "a/b/c.d")
          "C";
        string_eq 
          (Ext_filename.module_name "a/b/xc.re")
          "Xc";
        string_eq 
          (Ext_filename.module_name "a/b/xc.ml")
          "Xc"  ;
        string_eq 
          (Ext_filename.module_name "a/b/xc.mli")
          "Xc"  ;
        string_eq 
          (Ext_filename.module_name "a/b/xc.cppo.mli")
          "Xc.cppo";
        string_eq 
          (Ext_filename.module_name "a/b/xc.cppo.")
          "Xc.cppo"  ;
        string_eq 
          (Ext_filename.module_name "a/b/xc..")
          "Xc."  ;
        string_eq 
          (Ext_filename.module_name "a/b/Xc..")
          "Xc."  ;
        string_eq 
          (Ext_filename.module_name "a/b/.")
          ""  ;  
    end;
    __LOC__ >:: begin fun _ -> 
      Ext_string.split "" ':' =~ [];
      Ext_string.split "a:b:" ':' =~ ["a";"b"];
      Ext_string.split "a:b:" ':' ~keep_empty:true =~ ["a";"b";""]
    end;
    __LOC__ >:: begin fun _ ->    
        let cmp0 = Ext_string.compare in 
        let cmp1 = Map_string.compare_key in 
        let f a b = 
          cmp0 a b =~ cmp1 a b ;
          cmp0 b a =~ cmp1 b a
          in
        (* This is needed since deserialization/serialization
          needs to be synced up for .bsbuild decoding
         *)
        f "a" "A";
        f "bcdef" "abcdef";
        f "" "A";
        f "Abcdef" "abcdef";
    end
  ]


end
module Ext_topsort : sig 
#1 "ext_topsort.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


type edges = { id : int ; deps : Vec_int.t }

module Edge_vec : Vec_gen.S with type elt = edges 

type t = Edge_vec.t 

(** the input will be modified ,
*)
val layered_dfs : t -> Set_int.t Queue.t
end = struct
#1 "ext_topsort.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

type edges = { id : int ; deps : Vec_int.t }

module Edge_vec = Vec.Make( struct 
    type t = edges
    let null = { id = 0 ; deps = Vec_int.empty ()}
  end
  )

type t = Edge_vec.t 


(** 
    This graph is different the graph used in [scc] graph, since 
    we need dynamic shrink the graph, so for each vector the first node is it self ,
    it will also change the input.

    TODO: error handling (cycle handling) and defensive bad input (missing edges etc)
*)

let layered_dfs (g : t) =
  let queue = Queue.create () in 
  let rec aux g = 
    let new_entries = 
      Edge_vec.inplace_filter_with 
        (fun (x : edges) -> not (Vec_int.is_empty x.deps) ) 
        ~cb_no:(fun x acc -> Set_int.add acc x.id) Set_int.empty  g in 
    if not (Set_int.is_empty new_entries) 
    then 
      begin 
        Queue.push new_entries queue ; 
        Edge_vec.iter g (fun edges -> Vec_int.inplace_filter  
                            (fun x -> not (Set_int.mem new_entries x)) edges.deps ) ;
        aux g 
      end
  in aux  g ; queue      


end
module Ounit_topsort_tests
= struct
#1 "ounit_topsort_tests.ml"
let ((>::),
     (>:::)) = OUnit.((>::),(>:::))

let handle graph = 
  let len = List.length graph in 
  let result = Ext_topsort.Edge_vec.make len in 
  List.iter (fun (id,deps) -> 
      Ext_topsort.Edge_vec.push result {id ; deps = Vec_int.of_list deps } 
    ) graph; 
  result 


let graph1 = 
  [ 
    0, [1;2];
    1, [2;3];
    2, [4];
    3, [];
    4, []
  ], [[0]; [1]; [2] ; [3;4]]


let graph2 = 
  [ 
    0, [1;2];
    1, [2;3];
    2, [4];
    3, [5];
    4, [5];
    5, []
  ],  
  [[0]; [1]; [2] ; [3;4]; [5]]

let graph3 = 
    [ 0,[1;2;3;4;5];
      1, [6;7;8] ;
      2, [6;7;8];
      3, [6;7;8];
      4, [6;7;8];
      5, [6;7;8];
      6, [];
      7, [] ;
      8, []
     ],
     [[0]; [1;2;3;4;5]; [6; 7; 8]]


let expect loc (graph1, v) = 
  let graph = handle graph1  in 
  let queue = Ext_topsort.layered_dfs graph  in 
  OUnit.assert_bool loc
    (Queue.fold (fun acc x -> Set_int.elements x::acc) [] queue =
     v)





let (=~) = OUnit.assert_equal
let suites = 
  __FILE__
  >:::
  [
    __LOC__ >:: begin fun _ -> 
      expect __LOC__ graph1;
      expect __LOC__ graph2 ;
      expect __LOC__ graph3
    end

  ]
end
module Ext_char : sig 
#1 "ext_char.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)






(** Extension to Standard char module, avoid locale sensitivity *)

val valid_hex : char -> bool
val is_lower_case : char -> bool


end = struct
#1 "ext_char.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)





(** {!Char.escaped} is locale sensitive in 4.02.3, fixed in the trunk,
    backport it here
*)


let valid_hex x = 
  match x with 
  | '0' .. '9'
  | 'a' .. 'f'
  | 'A' .. 'F' -> true
  | _ -> false 



let is_lower_case c =
  (c >= 'a' && c <= 'z')
  || (c >= '\224' && c <= '\246')
  || (c >= '\248' && c <= '\254')    

end
module Ast_utf8_string : sig 
#1 "ast_utf8_string.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


type error 


type exn += Error of int  (* offset *) * error 

val pp_error :  Format.formatter -> error -> unit  



(* module Interp : sig *)
(*   val check_and_transform : int -> string -> int -> cxt -> unit *)
(*   val transform_test : string -> segments *)
(* end *)
val transform_test : string -> string 

val transform : Location.t -> string -> string      


end = struct
#1 "ast_utf8_string.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)



type error = 
  | Invalid_code_point 
  | Unterminated_backslash
  | Invalid_escape_code of char 
  | Invalid_hex_escape
  | Invalid_unicode_escape

let pp_error fmt err = 
  Format.pp_print_string fmt @@  match err with 
  | Invalid_code_point -> "Invalid code point"
  | Unterminated_backslash -> "\\ ended unexpectedly"
  | Invalid_escape_code c -> "Invalid escape code: " ^ String.make 1 c 
  | Invalid_hex_escape -> 
    "Invalid \\x escape"
  | Invalid_unicode_escape -> "Invalid \\u escape"



type exn += Error of int  (* offset *) * error 




let error ~loc error = 
  raise (Error (loc, error))

(** Note the [loc] really should be the utf8-offset, it has nothing to do with our 
    escaping mechanism
*)
(* we can not just print new line in ES5 
   seems we don't need 
   escape "\b" "\f" 
   we need escape "\n" "\r" since 
   ocaml multiple-line allows [\n]
   visual input while es5 string 
   does not*)

let rec check_and_transform (loc : int ) (buf : Buffer.t) (s : string) (byte_offset : int) (s_len : int) =
  if byte_offset = s_len then ()
  else 
    let current_char = s.[byte_offset] in 
    match Ext_utf8.classify current_char with 
    | Single 92 (* '\\' *) -> 
      escape_code (loc + 1) buf s (byte_offset+1) s_len
    | Single 34 ->
      Buffer.add_string buf "\\\"";
      check_and_transform (loc + 1) buf s (byte_offset + 1) s_len
    | Single 10 ->          
      Buffer.add_string buf "\\n";
      check_and_transform (loc + 1) buf s (byte_offset + 1) s_len 
    | Single 13 -> 
      Buffer.add_string buf "\\r";
      check_and_transform (loc + 1) buf s (byte_offset + 1) s_len 
    | Single _ -> 
      Buffer.add_char buf current_char;
      check_and_transform (loc + 1) buf s (byte_offset + 1) s_len 

    | Invalid 
    | Cont _ -> error ~loc Invalid_code_point
    | Leading (n,_) -> 
      let i' = Ext_utf8.next s ~remaining:n  byte_offset in
      if i' < 0 then 
        error ~loc Invalid_code_point
      else 
        begin 
          for k = byte_offset to i' do 
            Buffer.add_char buf s.[k]; 
          done;   
          check_and_transform (loc + 1 ) buf s (i' + 1) s_len 
        end
(* we share the same escape sequence with js *)        
and escape_code loc buf s offset s_len = 
  if offset >= s_len then 
    error ~loc Unterminated_backslash
  else
    Buffer.add_char buf '\\'; 
  let cur_char = s.[offset] in
  match cur_char with 
  | '\\'
  | 'b' 
  | 't' 
  | 'n' 
  | 'v'
  | 'f'
  | 'r' 
  | '0' 
  | '$'
    -> 
    begin 
      Buffer.add_char buf cur_char ;
      check_and_transform (loc + 1) buf s (offset + 1) s_len 
    end 
  | 'u' -> 
    begin 
      Buffer.add_char buf cur_char;
      unicode (loc + 1) buf s (offset + 1) s_len 
    end 
  | 'x' -> begin 
      Buffer.add_char buf cur_char ; 
      two_hex (loc + 1) buf s (offset + 1) s_len 
    end 
  | _ -> error ~loc (Invalid_escape_code cur_char)
and two_hex loc buf s offset s_len = 
  if offset + 1 >= s_len then 
    error ~loc Invalid_hex_escape;
  (*Location.raise_errorf ~loc "\\x need at least two chars";*)
  let a, b = s.[offset], s.[offset + 1] in 
  if Ext_char.valid_hex a && Ext_char.valid_hex b then 
    begin 
      Buffer.add_char buf a ; 
      Buffer.add_char buf b ; 
      check_and_transform (loc + 2) buf s (offset + 2) s_len 
    end
  else
    error ~loc Invalid_hex_escape
(*Location.raise_errorf ~loc "%c%c is not a valid hex code" a b*)

and unicode loc buf s offset s_len = 
  if offset + 3 >= s_len then 
    error ~loc Invalid_unicode_escape
  (*Location.raise_errorf ~loc "\\u need at least four chars"*)
  ;
  let a0,a1,a2,a3 = s.[offset], s.[offset+1], s.[offset+2], s.[offset+3] in
  if 
    Ext_char.valid_hex a0 &&
    Ext_char.valid_hex a1 &&
    Ext_char.valid_hex a2 &&
    Ext_char.valid_hex a3 then 
    begin 
      Buffer.add_char buf a0;
      Buffer.add_char buf a1;
      Buffer.add_char buf a2;
      Buffer.add_char buf a3;  
      check_and_transform (loc + 4) buf s  (offset + 4) s_len 
    end 
  else
    error ~loc Invalid_unicode_escape 
(*Location.raise_errorf ~loc "%c%c%c%c is not a valid unicode point"
  a0 a1 a2 a3 *)
(* http://www.2ality.com/2015/01/es6-strings.html
   console.log('\uD83D\uDE80'); (* ES6*)
   console.log('\u{1F680}');
*)   









let transform_test s =
  let s_len = String.length s in 
  let buf = Buffer.create (s_len * 2) in
  check_and_transform 0 buf s 0 s_len;
  Buffer.contents buf

let transform loc s = 
  let s_len = String.length s in 
  let buf = Buffer.create (s_len * 2) in
  try
    check_and_transform 0 buf s 0 s_len;
    Buffer.contents buf 
  with
    Error (offset, error)
    ->  Location.raise_errorf ~loc "Offset: %d, %a" offset pp_error error



end
module Ast_compatible : sig 
#1 "ast_compatible.mli"
(* Copyright (C) 2018 Authors of ReScript
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)










type loc = Location.t 
type attrs = Parsetree.attribute list 

open Parsetree


val const_exp_string:
  ?loc:Location.t -> 
  ?attrs:attrs ->    
  ?delimiter:string -> 
  string -> 
  expression

val const_exp_int:
  ?loc:Location.t -> 
  ?attrs:attrs -> 
  int -> 
  expression 



val const_exp_int_list_as_array:  
  int list -> 
  expression 




val apply_simple:
  ?loc:Location.t -> 
  ?attrs:attrs -> 
  expression ->   
  expression list -> 
  expression 

val app1:
  ?loc:Location.t -> 
  ?attrs:attrs -> 
  expression ->   
  expression -> 
  expression 

val app2:
  ?loc:Location.t -> 
  ?attrs:attrs -> 
  expression ->   
  expression -> 
  expression -> 
  expression 

val app3:
  ?loc:Location.t -> 
  ?attrs:attrs -> 
  expression ->   
  expression -> 
  expression -> 
  expression ->   
  expression 

(** Note this function would slightly 
    change its semantics depending on compiler versions
    for newer version: it means always label
    for older version: it could be optional (which we should avoid)
*)  
val apply_labels:  
  ?loc:Location.t -> 
  ?attrs:attrs -> 
  expression ->   
  (string * expression) list -> 
  (* [(label,e)] [label] is strictly interpreted as label *)
  expression 

val fun_ :  
  ?loc:Location.t -> 
  ?attrs:attrs -> 
  pattern -> 
  expression -> 
  expression

(* val opt_label : string -> Asttypes.arg_label *)

(* val label_fun :
   ?loc:Location.t ->
   ?attrs:attrs ->
   label:Asttypes.arg_label ->
   pattern ->
   expression ->
   expression *)

val arrow :
  ?loc:Location.t -> 
  ?attrs:attrs -> 
  core_type -> 
  core_type ->
  core_type

val label_arrow :
  ?loc:Location.t -> 
  ?attrs:attrs -> 
  string -> 
  core_type -> 
  core_type ->
  core_type

val opt_arrow:
  ?loc:Location.t -> 
  ?attrs:attrs -> 
  string -> 
  core_type -> 
  core_type ->
  core_type



(* val nonrec_type_str:  
   ?loc:loc -> 
   type_declaration list -> 
   structure_item *)

val rec_type_str:  
  ?loc:loc -> 
  Asttypes.rec_flag -> 
  type_declaration list -> 
  structure_item

(* val nonrec_type_sig:  
   ?loc:loc -> 
   type_declaration list -> 
   signature_item  *)

val rec_type_sig:  
  ?loc:loc -> 
  Asttypes.rec_flag -> 
  type_declaration list -> 
  signature_item

type param_type = 
  {label : Asttypes.arg_label ;
   ty :  Parsetree.core_type ; 
   attr :Parsetree.attributes;
   loc : loc
  }

val mk_fn_type:  
  param_type list -> 
  core_type -> 
  core_type

type object_field = 
  Parsetree.object_field 
val object_field : Asttypes.label Asttypes.loc ->  attributes -> core_type -> object_field



type args  = 
  (Asttypes.arg_label * Parsetree.expression) list 

end = struct
#1 "ast_compatible.ml"
(* Copyright (C) 2018 Hongbo Zhang, Authors of ReScript
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

type loc = Location.t 
type attrs = Parsetree.attribute list 
open Parsetree
let default_loc = Location.none











let arrow ?loc ?attrs a b  =
  Ast_helper.Typ.arrow ?loc ?attrs Nolabel a b  

let apply_simple
    ?(loc = default_loc) 
    ?(attrs = [])
    (fn : expression) 
    (args : expression list) : expression = 
  { pexp_loc = loc; 
    pexp_attributes = attrs;
    pexp_desc = 
      Pexp_apply(
        fn, 
        (Ext_list.map args (fun x -> Asttypes.Nolabel, x) ) ) }

let app1        
    ?(loc = default_loc)
    ?(attrs = [])
    fn arg1 : expression = 
  { pexp_loc = loc; 
    pexp_attributes = attrs;
    pexp_desc = 
      Pexp_apply(
        fn, 
        [Nolabel, arg1]
      ) }

let app2
    ?(loc = default_loc)
    ?(attrs = [])
    fn arg1 arg2 : expression = 
  { pexp_loc = loc; 
    pexp_attributes = attrs;
    pexp_desc = 
      Pexp_apply(
        fn, 
        [
          Nolabel, arg1;
          Nolabel, arg2 ]
      ) }

let app3
    ?(loc = default_loc)
    ?(attrs = [])
    fn arg1 arg2 arg3 : expression = 
  { pexp_loc = loc; 
    pexp_attributes = attrs;
    pexp_desc = 
      Pexp_apply(
        fn, 
        [
          Nolabel, arg1;
          Nolabel, arg2;
          Nolabel, arg3
        ]
      ) }

let fun_         
    ?(loc = default_loc) 
    ?(attrs = [])
    pat
    exp = 
  {
    pexp_loc = loc; 
    pexp_attributes = attrs;
    pexp_desc = Pexp_fun(Nolabel,None, pat, exp)
  }



let const_exp_string 
    ?(loc = default_loc)
    ?(attrs = [])
    ?delimiter
    (s : string) : expression = 
  {
    pexp_loc = loc; 
    pexp_attributes = attrs;
    pexp_desc = Pexp_constant(Pconst_string(s,delimiter))
  }



let const_exp_int 
    ?(loc = default_loc)
    ?(attrs = [])
    (s : int) : expression = 
  {
    pexp_loc = loc; 
    pexp_attributes = attrs;
    pexp_desc = Pexp_constant(Pconst_integer (string_of_int s, None))
  }


let apply_labels
    ?(loc = default_loc) 
    ?(attrs = [])
    fn (args : (string * expression) list) : expression = 
  { pexp_loc = loc; 
    pexp_attributes = attrs;
    pexp_desc = 
      Pexp_apply(
        fn, 
        Ext_list.map args (fun (l,a) -> Asttypes.Labelled l, a)   ) }




let label_arrow ?(loc=default_loc) ?(attrs=[]) s a b : core_type = 
  {
    ptyp_desc = Ptyp_arrow(
        Asttypes.Labelled s

        ,
        a,
        b);
    ptyp_loc = loc;
    ptyp_attributes = attrs
  }

let opt_arrow ?(loc=default_loc) ?(attrs=[]) s a b : core_type = 
  {
    ptyp_desc = Ptyp_arrow( 

        Asttypes.Optional s
        ,
        a,
        b);
    ptyp_loc = loc;
    ptyp_attributes = attrs
  }    

let rec_type_str 
    ?(loc=default_loc) 
    rf tds : structure_item = 
  {
    pstr_loc = loc;
    pstr_desc = Pstr_type ( 
        rf,
        tds)
  }



let rec_type_sig 
    ?(loc=default_loc)
    rf tds : signature_item = 
  {
    psig_loc = loc;
    psig_desc = Psig_type ( 
        rf,
        tds)
  }

(* FIXME: need address migration of `[@nonrec]` attributes in older ocaml *)  
(* let nonrec_type_sig ?(loc=default_loc)  tds : signature_item = 
   {
    psig_loc = loc;
    psig_desc = Psig_type ( 
      Nonrecursive,
      tds)
   }   *)


let const_exp_int_list_as_array xs = 
  Ast_helper.Exp.array 
    (Ext_list.map  xs (fun x -> const_exp_int x ))  

(* let const_exp_string_list_as_array xs =   
   Ast_helper.Exp.array 
   (Ext_list.map xs (fun x -> const_exp_string x ) )   *)

type param_type = 
  {label : Asttypes.arg_label ;
   ty :  Parsetree.core_type ; 
   attr :Parsetree.attributes;
   loc : loc
  }

let mk_fn_type 
    (new_arg_types_ty : param_type list)
    (result : core_type) : core_type = 
  Ext_list.fold_right new_arg_types_ty result (fun {label; ty; attr ; loc} acc -> 
      {
        ptyp_desc = Ptyp_arrow(label,ty,acc);
        ptyp_loc = loc; 
        ptyp_attributes = attr
      }
    )

type object_field = 
  Parsetree.object_field 

let object_field   l attrs ty = 

  Parsetree.Otag 
    (l,attrs,ty)  




type args  = 
  (Asttypes.arg_label * Parsetree.expression) list 

end
module Bs_loc : sig 
#1 "bs_loc.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

type t = Location.t = {
  loc_start : Lexing.position;
  loc_end : Lexing.position ; 
  loc_ghost : bool
} 

(* val is_ghost : t -> bool *)
val merge : t -> t -> t 
(* val none : t  *)


end = struct
#1 "bs_loc.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


type t = Location.t = {
  loc_start : Lexing.position;
  loc_end : Lexing.position ; 
  loc_ghost : bool
} 

let is_ghost x = x.loc_ghost

let merge (l: t) (r : t) = 
  if is_ghost l then r 
  else if is_ghost r then l 
  else match l,r with 
    | {loc_start ; _}, {loc_end; _} (* TODO: improve*)
      -> 
      {loc_start ;loc_end; loc_ghost = false}

(* let none = Location.none *)

end
module Ast_utf8_string_interp : sig 
#1 "ast_utf8_string_interp.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)



type kind =
  | String
  | Var of int * int (* int records its border length *)

type error = private
  | Invalid_code_point
  | Unterminated_backslash
  | Invalid_escape_code of char
  | Invalid_hex_escape
  | Invalid_unicode_escape
  | Unterminated_variable
  | Unmatched_paren
  | Invalid_syntax_of_var of string 

(** Note the position is about code point *)
type pos = { lnum : int ; offset : int ; byte_bol : int }

type segment = {
  start : pos;
  finish : pos ;
  kind : kind;
  content : string ;
} 

type segments = segment list  

type cxt = {
  mutable segment_start : pos ;
  buf : Buffer.t ;
  s_len : int ;
  mutable segments : segments;
  mutable pos_bol : int; (* record the abs position of current beginning line *)
  mutable byte_bol : int ; 
  mutable pos_lnum : int ; (* record the line number *)
}

type exn += Error of pos *  pos * error 

val empty_segment : segment -> bool

val transform_test : string -> segment list



val transform : 
  Parsetree.expression -> 
  string -> 
  string -> 
  Parsetree.expression

val is_unicode_string :   
  string -> 
  bool

val is_unescaped :   
  string -> 
  bool
end = struct
#1 "ast_utf8_string_interp.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

type error =
  | Invalid_code_point
  | Unterminated_backslash
  | Invalid_escape_code of char
  | Invalid_hex_escape
  | Invalid_unicode_escape
  | Unterminated_variable
  | Unmatched_paren
  | Invalid_syntax_of_var of string

type kind =
  | String
  | Var of int * int
  (* [Var (loffset, roffset)]
     For parens it used to be (2,-1)
     for non-parens it used to be (1,0)
  *)

(** Note the position is about code point *)
type pos = {
  lnum : int ;
  offset : int ;
  byte_bol : int (* Note it actually needs to be in sync with OCaml's lexing semantics *)
}


type segment = {
  start : pos;
  finish : pos ;
  kind : kind;
  content : string ;
}

type segments = segment list


type cxt = {
  mutable segment_start : pos ;
  buf : Buffer.t ;
  s_len : int ;
  mutable segments : segments;
  mutable pos_bol : int; (* record the abs position of current beginning line *)
  mutable byte_bol : int ;
  mutable pos_lnum : int ; (* record the line number *)
}


type exn += Error of pos *  pos * error

let pp_error fmt err =
  Format.pp_print_string fmt @@  match err with
  | Invalid_code_point -> "Invalid code point"
  | Unterminated_backslash -> "\\ ended unexpectedly"
  | Invalid_escape_code c -> "Invalid escape code: " ^ String.make 1 c
  | Invalid_hex_escape ->
    "Invalid \\x escape"
  | Invalid_unicode_escape -> "Invalid \\u escape"
  | Unterminated_variable -> "$ unterminated"
  | Unmatched_paren -> "Unmatched paren"
  | Invalid_syntax_of_var s -> "`" ^s ^ "' is not a valid syntax of interpolated identifer"
let valid_lead_identifier_char x =
  match x with
  | 'a'..'z' | '_' -> true
  | _ -> false

let valid_identifier_char x =
  match x with
  | 'a'..'z'
  | 'A'..'Z'
  | '0'..'9'
  | '_' | '\''-> true
  | _ -> false
(** Invariant: [valid_lead_identifier] has to be [valid_identifier] *)

let valid_identifier s =
  let s_len = String.length s in
  if s_len = 0 then false
  else
    valid_lead_identifier_char s.[0] &&
    Ext_string.for_all_from s 1  valid_identifier_char


(* let is_space x =
   match x with
   | ' ' | '\n' | '\t' -> true
   | _ -> false *)



(**
   FIXME: multiple line offset
   if there is no line offset. Note {|{j||} border will never trigger a new line
*)
let update_position border
    ({lnum ; offset;byte_bol } : pos)
    (pos : Lexing.position)=
  if lnum = 0 then
    {pos with pos_cnum = pos.pos_cnum + border + offset  }
    (* When no newline, the column number is [border + offset] *)
  else
    {
      pos with
      pos_lnum = pos.pos_lnum + lnum ;
      pos_bol = pos.pos_cnum + border + byte_bol;
      pos_cnum = pos.pos_cnum + border + byte_bol + offset;
      (* when newline, the column number is [offset] *)
    }
let update border
    (start : pos)
    (finish : pos) (loc : Location.t) : Location.t =
  let start_pos = loc.loc_start in
  { loc  with
    loc_start =
      update_position  border start start_pos;
    loc_end =
      update_position border finish start_pos
  }


(** Note [Var] kind can not be mpty  *)
let empty_segment {content } =
  Ext_string.is_empty content



let update_newline ~byte_bol loc  cxt =
  cxt.pos_lnum <- cxt.pos_lnum + 1 ;
  cxt.pos_bol <- loc;
  cxt.byte_bol <- byte_bol

let pos_error cxt ~loc error =
  raise (Error
           (cxt.segment_start,
            { lnum = cxt.pos_lnum ; offset = loc - cxt.pos_bol ; byte_bol = cxt.byte_bol}, error))

let add_var_segment cxt loc loffset roffset =
  let content =  Buffer.contents cxt.buf in
  Buffer.clear cxt.buf ;
  let next_loc = {
    lnum = cxt.pos_lnum ; offset = loc - cxt.pos_bol ;
    byte_bol = cxt.byte_bol } in
  if valid_identifier content then
    begin
      cxt.segments <-
        { start = cxt.segment_start;
          finish =  next_loc ;
          kind = Var (loffset, roffset);
          content} :: cxt.segments ;
      cxt.segment_start <- next_loc
    end
  else pos_error cxt ~loc (Invalid_syntax_of_var content)

let add_str_segment cxt loc   =
  let content =  Buffer.contents cxt.buf in
  Buffer.clear cxt.buf ;
  let next_loc = {
    lnum = cxt.pos_lnum ; offset = loc - cxt.pos_bol ;
    byte_bol = cxt.byte_bol } in
  cxt.segments <-
    { start = cxt.segment_start;
      finish =  next_loc ;
      kind = String;
      content} :: cxt.segments ;
  cxt.segment_start <- next_loc





let rec check_and_transform (loc : int )  s byte_offset ({s_len; buf} as cxt : cxt) =
  if byte_offset = s_len then
    add_str_segment cxt loc
  else
    let current_char = s.[byte_offset] in
    match Ext_utf8.classify current_char with
    | Single 92 (* '\\' *) ->
      escape_code (loc + 1)  s (byte_offset+1) cxt
    | Single 34 ->
      Buffer.add_string buf "\\\"";
      check_and_transform (loc + 1)  s (byte_offset + 1) cxt
    | Single 10 ->

      Buffer.add_string buf "\\n";
      let loc = loc + 1 in
      let byte_offset = byte_offset + 1 in
      update_newline ~byte_bol:byte_offset loc cxt ; (* Note variable could not have new-line *)
      check_and_transform loc  s byte_offset cxt
    | Single 13 ->
      Buffer.add_string buf "\\r";
      check_and_transform (loc + 1)  s (byte_offset + 1) cxt
    | Single 36 -> (* $ *)
      add_str_segment cxt loc  ;
      let offset = byte_offset + 1 in
      if offset >= s_len then
        pos_error ~loc cxt  Unterminated_variable
      else
        let cur_char = s.[offset] in
        if cur_char = '(' then
          expect_var_paren  (loc + 2)  s (offset + 1) cxt
        else
          expect_simple_var (loc + 1)  s offset cxt
    | Single _ ->
      Buffer.add_char buf current_char;
      check_and_transform (loc + 1)  s (byte_offset + 1) cxt

    | Invalid
    | Cont _ -> pos_error ~loc cxt Invalid_code_point
    | Leading (n,_) ->
      let i' = Ext_utf8.next s ~remaining:n  byte_offset in
      if i' < 0 then
        pos_error cxt ~loc Invalid_code_point
      else
        begin
          for k = byte_offset to i' do
            Buffer.add_char buf s.[k];
          done;
          check_and_transform (loc + 1 )  s (i' + 1) cxt
        end
(* Lets keep identifier simple, so that we could generating a function easier in the future
   for example
   let f = [%fn{| $x + $y = $x_add_y |}]
*)
and expect_simple_var  loc  s offset ({buf; s_len} as cxt) =
  let v = ref offset in
  (* prerr_endline @@ Ext_pervasives.dump (s, has_paren, (is_space s.[!v]), !v); *)
  if not (offset < s_len  && valid_lead_identifier_char s.[offset]) then
    pos_error cxt ~loc (Invalid_syntax_of_var Ext_string.empty)
  else
    begin
      while !v < s_len && valid_identifier_char s.[!v]  do (* TODO*)
        let cur_char = s.[!v] in
        Buffer.add_char buf cur_char;
        incr v ;
      done;
      let added_length = !v - offset in
      let loc = added_length + loc in
      add_var_segment cxt loc 1 0 ;
      check_and_transform loc  s (added_length + offset) cxt
    end
and expect_var_paren  loc  s offset ({buf; s_len} as cxt) =
  let v = ref offset in
  (* prerr_endline @@ Ext_pervasives.dump (s, has_paren, (is_space s.[!v]), !v); *)
  while !v < s_len &&  s.[!v] <> ')' do
    let cur_char = s.[!v] in
    Buffer.add_char buf cur_char;
    incr v ;
  done;
  let added_length = !v - offset in
  let loc = added_length +  1 + loc  in
  if !v < s_len && s.[!v] = ')' then
    begin
      add_var_segment cxt loc 2 (-1) ;
      check_and_transform loc  s (added_length + 1 + offset) cxt
    end
  else
    pos_error cxt ~loc Unmatched_paren





(* we share the same escape sequence with js *)
and escape_code loc  s offset ({ buf; s_len} as cxt) =
  if offset >= s_len then
    pos_error cxt ~loc Unterminated_backslash
  else
    Buffer.add_char buf '\\';
  let cur_char = s.[offset] in
  match cur_char with
  | '\\'
  | 'b'
  | 't'
  | 'n'
  | 'v'
  | 'f'
  | 'r'
  | '0'
  | '$'
    ->
    begin
      Buffer.add_char buf cur_char ;
      check_and_transform (loc + 1)  s (offset + 1) cxt
    end
  | 'u' ->
    begin
      Buffer.add_char buf cur_char;
      unicode (loc + 1) s (offset + 1) cxt
    end
  | 'x' -> begin
      Buffer.add_char buf cur_char ;
      two_hex (loc + 1)  s (offset + 1) cxt
    end
  | _ -> pos_error cxt ~loc (Invalid_escape_code cur_char)
and two_hex loc  s offset ({buf ; s_len} as cxt) =
  if offset + 1 >= s_len then
    pos_error cxt ~loc Invalid_hex_escape;
  let a, b = s.[offset], s.[offset + 1] in
  if Ext_char.valid_hex a && Ext_char.valid_hex b then
    begin
      Buffer.add_char buf a ;
      Buffer.add_char buf b ;
      check_and_transform (loc + 2)  s (offset + 2) cxt
    end
  else
    pos_error cxt ~loc Invalid_hex_escape


and unicode loc  s offset ({buf ; s_len} as cxt) =
  if offset + 3 >= s_len then
    pos_error cxt ~loc Invalid_unicode_escape
  ;
  let a0,a1,a2,a3 = s.[offset], s.[offset+1], s.[offset+2], s.[offset+3] in
  if
    Ext_char.valid_hex a0 &&
    Ext_char.valid_hex a1 &&
    Ext_char.valid_hex a2 &&
    Ext_char.valid_hex a3 then
    begin
      Buffer.add_char buf a0;
      Buffer.add_char buf a1;
      Buffer.add_char buf a2;
      Buffer.add_char buf a3;
      check_and_transform (loc + 4) s  (offset + 4) cxt
    end
  else
    pos_error cxt ~loc Invalid_unicode_escape
let transform_test s =
  let s_len = String.length s in
  let buf = Buffer.create (s_len * 2) in
  let cxt =
    { segment_start = {lnum = 0; offset = 0; byte_bol = 0};
      buf ;
      s_len;
      segments = [];
      pos_lnum = 0;
      byte_bol = 0;
      pos_bol = 0;

    } in
  check_and_transform 0 s 0 cxt;
  List.rev cxt.segments


(** TODO: test empty var $() $ failure,
    Allow identifers x.A.y *)

open Ast_helper

(** Longident.parse "Pervasives.^" *)
let concat_ident  : Longident.t =
  Ldot (Lident "Pervasives", "^") (* FIXME: remove deps on `Pervasives` *)
(* JS string concatMany *)
(* Ldot (Ldot (Lident "Js", "String2"), "concat") *)

(* Longident.parse "Js.String.make"     *)
let to_string_ident : Longident.t =
  Ldot (Ldot (Lident "Js", "String2"), "make")


let escaped_j_delimiter =  "*j" (* not user level syntax allowed *)
let unescaped_j_delimiter = "j"
let unescaped_js_delimiter = "js"

let escaped = Some escaped_j_delimiter


let border = String.length "{j|"

let aux loc (segment : segment) ~to_string_ident : Parsetree.expression =
  match segment with
  | {start ; finish; kind ; content}
    ->
    begin match kind with
      | String ->
        let loc = update border start finish  loc  in
        Ast_compatible.const_exp_string
          content ?delimiter:escaped ~loc
      | Var (soffset, foffset) ->
        let loc = {
          loc with
          loc_start = update_position  (soffset + border) start loc.loc_start ;
          loc_end = update_position (foffset + border) finish loc.loc_start
        } in
        Ast_compatible.apply_simple ~loc
          (Exp.ident ~loc {loc ; txt = to_string_ident })
          [
            Exp.ident ~loc {loc ; txt = Lident content}
          ]
    end

let concat_exp
    a_loc x 
    ~lhs:(lhs : Parsetree.expression) : Parsetree.expression =
  let loc = Bs_loc.merge a_loc lhs.pexp_loc in
  Ast_compatible.apply_simple ~loc
    (Exp.ident { txt =concat_ident; loc})
    [
      lhs;
      aux loc x ~to_string_ident:(Longident.Ldot (Lident"Obj","magic")) ;]

(* Invariant: the [lhs] is always of type string *)
let rec handle_segments loc (rev_segments : segment list)=      
  match rev_segments with
  | [] ->
    Ast_compatible.const_exp_string ~loc ""  ?delimiter:escaped
  | [ segment] ->
    aux loc segment ~to_string_ident(* string literal *)
  | {content="";} :: rest ->
    handle_segments loc rest  
  | a::rest ->
    concat_exp loc a ~lhs:(handle_segments loc rest)  


let transform_interp loc s =
  let s_len = String.length s in
  let buf = Buffer.create (s_len * 2 ) in
  try
    let cxt : cxt =
      { segment_start = {lnum = 0; offset = 0; byte_bol = 0};
        buf ;
        s_len;
        segments = [];
        pos_lnum = 0;
        byte_bol = 0;
        pos_bol = 0;

      } in

    check_and_transform 0 s 0 cxt;
    handle_segments loc cxt.segments
  with
    Error (start,pos, error)
    ->
    Location.raise_errorf ~loc:(update border start pos loc )
      "%a"  pp_error error


let transform (e : Parsetree.expression) s delim : Parsetree.expression =
  if Ext_string.equal delim unescaped_js_delimiter then
    let js_str = Ast_utf8_string.transform e.pexp_loc s in
    { e with pexp_desc =
               Pexp_constant (
                 Pconst_string
                   (js_str, escaped))}
  else if Ext_string.equal delim unescaped_j_delimiter then
    transform_interp e.pexp_loc s
  else e

let is_unicode_string opt = Ext_string.equal opt escaped_j_delimiter

let is_unescaped s =
  Ext_string.equal s unescaped_j_delimiter
  || Ext_string.equal s unescaped_js_delimiter
end
module Ounit_unicode_tests
= struct
#1 "ounit_unicode_tests.ml"
let ((>::),
     (>:::)) = OUnit.((>::),(>:::))

let (=~) a b = 
    OUnit.assert_equal ~cmp:Ext_string.equal a b 

(** Test for single line *)
let (==~) a b =
  OUnit.assert_equal
    (
     Ext_list.map (Ast_utf8_string_interp.transform_test a
     |> List.filter (fun x -> not @@ Ast_utf8_string_interp.empty_segment x))
     (fun 
      ({start = {offset = a}; finish = {offset = b}; kind ; content }
       : Ast_utf8_string_interp.segment) -> 
      a,b,kind,content
      )
    )
    b 

let (==*) a b =
  let segments =     
     Ext_list.map (
       Ast_utf8_string_interp.transform_test a
     |> List.filter (fun x -> not @@ Ast_utf8_string_interp.empty_segment x)
     )(fun 
      ({start = {lnum=la; offset = a}; finish = {lnum = lb; offset = b}; kind ; content } 
        : Ast_utf8_string_interp.segment) -> 
      la,a,lb,b,kind,content
      )
   in 
   OUnit.assert_equal segments b 

let varParen : Ast_utf8_string_interp.kind = Var (2,-1)   
let var : Ast_utf8_string_interp.kind = Var (1,0)
let suites = 
    __FILE__
    >:::
    [
        __LOC__ >:: begin fun _ ->
            Ast_utf8_string.transform_test {|x|} =~ {|x|}
        end;
        __LOC__ >:: begin fun _ ->
            Ast_utf8_string.transform_test "a\nb" =~ {|a\nb|}
        end;
        __LOC__ >:: begin fun _ ->
            Ast_utf8_string.transform_test
            "\\n" =~ "\\n"
        end;
        __LOC__ >:: begin fun _ ->
          Ast_utf8_string.transform_test
            "\\\\\\b\\t\\n\\v\\f\\r\\0\\$" =~
          "\\\\\\b\\t\\n\\v\\f\\r\\0\\$"
        end;

        __LOC__ >:: begin fun _ ->
           match Ast_utf8_string.transform_test
             {|\|} with
           | exception Ast_utf8_string.Error(offset,_) ->
            OUnit.assert_equal offset 1
           | _ -> OUnit.assert_failure __LOC__
        end ;
         __LOC__ >:: begin fun _ ->
           match Ast_utf8_string.transform_test
             {|你\|} with
           | exception Ast_utf8_string.Error(offset,_) ->
            OUnit.assert_equal offset 2
           | _ -> OUnit.assert_failure __LOC__
        end ;
         __LOC__ >:: begin fun _ ->
           match Ast_utf8_string.transform_test
             {|你BuckleScript,好啊\uffff\|} with
           | exception Ast_utf8_string.Error(offset,_) ->
            OUnit.assert_equal offset 23
           | _ -> OUnit.assert_failure __LOC__
        end ;

        __LOC__ >:: begin fun _ ->
          "hie $x hi 你好" ==~
            [
              0,4, String, "hie ";
              4,6, var, "x";
              6,12,String, " hi 你好"
            ]
        end;
        __LOC__ >:: begin fun _ ->
          "x" ==~
          [0,1, String, "x"]
        end;

        __LOC__ >:: begin fun _ ->
          "" ==~
          []
        end;
        __LOC__ >:: begin fun _ ->
          "你好" ==~
          [0,2,String, "你好"]
        end;
        __LOC__ >:: begin fun _ ->
          "你好$x" ==~
          [0,2,String, "你好";
           2,4,var, "x";

          ]
        end
        ;
        __LOC__ >:: begin fun _ ->
          "你好$this" ==~
          [
            0,2,String, "你好";
            2,7,var, "this";
          ]
        end
        ;
        __LOC__ >:: begin fun _ ->
          "你好$(this)" ==~
          [
            0,2,String, "你好";
            2,9,varParen, "this"
          ];

          "你好$this)" ==~
          [
             0,2,String, "你好";
             2,7,var, "this";
             7,8,String,")"
          ];
          {|\xff\xff你好 $x |} ==~
          [
            0,11,String, {|\xff\xff你好 |};
            11,13, var, "x";
            13,14, String, " "
          ];
          {|\xff\xff你好 $x 不吃亏了buckle $y $z = $sum|}
          ==~
          [(0, 11, String,{|\xff\xff你好 |} );
           (11, 13, var, "x");
           (13, 25, String,{| 不吃亏了buckle |} );
           (25, 27, var, "y");
           (27, 28, String, " ");
           (28, 30, var, "z");
           (30, 33, String, " = ");
           (33, 37, var, "sum");
           ]
        end
        ;
        __LOC__ >:: begin fun _ ->
          "你好 $(this_is_a_var)  x" ==~
          [
            0,3,String, "你好 ";
            3,19,varParen, "this_is_a_var";
            19,22, String, "  x"
          ]
        end
        ;

        __LOC__ >:: begin fun _ ->
        "hi\n$x\n" ==*
        [
          0,0,1,0,String, "hi\\n";
          1,0,1,2,var, "x" ;
          1,2,2,0,String,"\\n"
        ];
        "$x" ==*
        [0,0,0,2,var,"x"];
        

        "\n$x\n" ==*
        [
          0,0,1,0,String,"\\n";
          1,0,1,2,var,"x";
          1,2,2,0,String,"\\n"
        ]
        end;

        __LOC__ >:: begin fun _ -> 
        "\n$(x_this_is_cool) " ==*
        [
          0,0,1,0,String, "\\n";
          1,0,1,17,varParen, "x_this_is_cool";
          1,17,1,18,String, " "
        ]
        end;
        __LOC__ >:: begin fun _ -> 
        " $x + $y = $sum " ==*
        [
          0,0,0,1,String , " ";
          0,1,0,3,var, "x";
          0,3,0,6,String, " + ";
          0,6,0,8,var, "y";
          0,8,0,11,String, " = ";
          0,11,0,15,var, "sum";
          0,15,0,16,String, " "
        ]
        end;
        __LOC__ >:: begin fun _ -> 
        "中文 | $a " ==*
        [
          0,0,0,5,String, "中文 | ";
          0,5,0,7,var, "a";
          0,7,0,8,String, " "
        ]
        end
        ;
        __LOC__ >:: begin fun _ ->
          {|Hello \\$world|} ==*
          [
            0,0,0,8,String,"Hello \\\\";
            0,8,0,14,var, "world"
          ]
        end
        ;
        __LOC__ >:: begin fun _ -> 
          {|$x)|} ==*
          [
            0,0,0,2,var,"x";
            0,2,0,3,String,")"
          ]
        end;
        __LOC__ >:: begin fun _ ->
          match Ast_utf8_string_interp.transform_test {j| $( ()) |j}
          with 
          |exception Ast_utf8_string_interp.Error
              ({lnum = 0; offset = 1; byte_bol = 0},
               {lnum = 0; offset = 6; byte_bol = 0}, Invalid_syntax_of_var " (")
            -> OUnit.assert_bool __LOC__ true 
          | _ -> OUnit.assert_bool __LOC__ false 
        end
        ;
        __LOC__ >:: begin fun _ -> 
          match Ast_utf8_string_interp.transform_test {|$()|}
          with 
          | exception Ast_utf8_string_interp.Error ({lnum = 0; offset = 0; byte_bol = 0},
                             {lnum = 0; offset = 3; byte_bol = 0}, Invalid_syntax_of_var "")
            -> OUnit.assert_bool __LOC__ true 
          | _ -> OUnit.assert_bool __LOC__ false
        end
        ;
        __LOC__ >:: begin fun _ ->
          match Ast_utf8_string_interp.transform_test {|$ ()|}
          with 
          | exception Ast_utf8_string_interp.Error 
              ({lnum = 0; offset = 0; byte_bol = 0},
               {lnum = 0; offset = 1; byte_bol = 0}, Invalid_syntax_of_var "")
            -> OUnit.assert_bool __LOC__ true 
          | _ -> OUnit.assert_bool __LOC__ false
        end ;
        __LOC__ >:: begin fun _ -> 
          match Ast_utf8_string_interp.transform_test {|$()|} with 
          | exception Ast_utf8_string_interp.Error 
              ({lnum = 0; offset = 0; byte_bol = 0},
               {lnum = 0; offset = 3; byte_bol = 0}, Invalid_syntax_of_var "")
            -> OUnit.assert_bool __LOC__ true
          | _ -> OUnit.assert_bool __LOC__ false 
        end
        ;
        __LOC__ >:: begin fun _ -> 
          match Ast_utf8_string_interp.transform_test {|$(hello world)|} with 
          | exception Ast_utf8_string_interp.Error 
              ({lnum = 0; offset = 0; byte_bol = 0},
               {lnum = 0; offset = 14; byte_bol = 0}, Invalid_syntax_of_var "hello world")
            -> OUnit.assert_bool __LOC__ true
          | _ -> OUnit.assert_bool __LOC__ false 
        end


        ;
        __LOC__ >:: begin fun _ -> 
          match Ast_utf8_string_interp.transform_test {|$( hi*) |} with 
          | exception Ast_utf8_string_interp.Error 
              ({lnum = 0; offset = 0; byte_bol = 0},
               {lnum = 0; offset = 7; byte_bol = 0}, Invalid_syntax_of_var " hi*")
            -> 
            OUnit.assert_bool __LOC__ true
          | _ -> OUnit.assert_bool __LOC__ false 
        end;
        __LOC__ >:: begin fun _ -> 
          match Ast_utf8_string_interp.transform_test {|xx $|} with 
          | exception Ast_utf8_string_interp.Error 
              ({lnum = 0; offset = 3; byte_bol = 0},
               {lnum = 0; offset = 3; byte_bol = 0}, Unterminated_variable)
            -> 
            OUnit.assert_bool __LOC__ true 
          | _ -> OUnit.assert_bool __LOC__ false
        end ;

        __LOC__ >:: begin fun _ ->
          match Ast_utf8_string_interp.transform_test {|$(world |}; with 
          | exception Ast_utf8_string_interp.Error 
              ({lnum = 0; offset = 0; byte_bol = 0},
               {lnum = 0; offset = 9; byte_bol = 0}, Unmatched_paren)
            -> 
            OUnit.assert_bool __LOC__ true 
          | _ -> OUnit.assert_bool __LOC__ false
        end
    ]

end
module Union_find : sig 
#1 "union_find.mli"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)


type t 

val init : int -> t 



val find : t -> int -> int

val union : t -> int -> int -> unit 

val count : t -> int

end = struct
#1 "union_find.ml"
(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

type t = {
  id : int array;
  sz : int array ;
  mutable components : int  
} 

let init n = 
  let id = Array.make n 0 in 
  for i = 0 to  n - 1 do
    Array.unsafe_set id i i  
  done  ;
  {
    id ; 
    sz = Array.make n 1;
    components = n
  }

let rec find_aux id_store p = 
  let parent = Array.unsafe_get id_store p in 
  if p <> parent then 
    find_aux id_store parent 
  else p       

let find store p = find_aux store.id p 

let union store p q =
  let id_store = store.id in 
  let p_root = find_aux id_store p in 
  let q_root = find_aux id_store q in 
  if p_root <> q_root then 
    begin
      let () = store.components <- store.components - 1 in
      let sz_store = store.sz in
      let sz_p_root = Array.unsafe_get sz_store p_root in 
      let sz_q_root = Array.unsafe_get sz_store q_root in  
      let bigger = sz_p_root + sz_q_root in
      (* Smaller root point to larger to make 
         it more balanced
         it will introduce a cost for small root find,
         but major will not be impacted 
      *) 
      if  sz_p_root < sz_q_root  then
        begin
          Array.unsafe_set id_store p q_root;   
          Array.unsafe_set id_store p_root q_root;
          Array.unsafe_set sz_store q_root bigger;            
          (* little optimization *) 
        end 
      else   
        begin
          Array.unsafe_set id_store q  p_root ;
          Array.unsafe_set id_store q_root p_root;   
          Array.unsafe_set sz_store p_root bigger;          
          (* little optimization *)
        end
    end 

let count store = store.components    


end
module Ounit_union_find_tests
= struct
#1 "ounit_union_find_tests.ml"
let ((>::),
     (>:::)) = OUnit.((>::),(>:::))

let (=~) = OUnit.assert_equal
let tinyUF = {|10
               4 3
               3 8
               6 5
               9 4
               2 1
               8 9
               5 0
               7 2
               6 1
               1 0
               6 7
             |}
let mediumUF = {|625
                 528 503
                 548 523
                 389 414
                 446 421
                 552 553
                 154 155
                 173 174
                 373 348
                 567 542
                 44 43
                 370 345
                 546 547
                 204 229
                 404 429
                 240 215
                 364 389
                 612 611
                 513 512
                 377 376
                 468 443
                 410 435
                 243 218
                 347 322
                 580 581
                 188 163
                 61 36
                 545 546
                 93 68
                 84 83
                 94 69
                 7 8
                 619 618
                 314 339
                 155 156
                 150 175
                 605 580
                 118 93
                 385 360
                 459 458
                 167 168
                 107 108
                 44 69
                 335 334
                 251 276
                 196 197
                 501 502
                 212 187
                 251 250
                 269 270
                 332 331
                 125 150
                 391 416
                 366 367
                 65 40
                 515 540
                 248 273
                 34 9
                 480 479
                 198 173
                 463 488
                 111 86
                 524 499
                 28 27
                 323 324
                 198 199
                 146 147
                 133 158
                 416 415
                 103 102
                 457 482
                 57 82
                 88 113
                 535 560
                 181 180
                 605 606
                 481 456
                 127 102
                 470 445
                 229 254
                 169 170
                 386 385
                 383 384
                 153 152
                 541 542
                 36 37
                 474 473
                 126 125
                 534 509
                 154 129
                 591 592
                 161 186
                 209 234
                 88 87
                 61 60
                 161 136
                 472 447
                 239 240
                 102 101
                 342 343
                 566 565
                 567 568
                 41 42
                 154 153
                 471 496
                 358 383
                 423 448
                 241 242
                 292 293
                 363 364
                 361 362
                 258 283
                 75 100
                 61 86
                 81 106
                 52 27
                 230 255
                 309 334
                 378 379
                 136 111
                 439 464
                 532 533
                 166 191
                 523 522
                 210 211
                 115 140
                 347 346
                 218 217
                 561 560
                 526 501
                 174 149
                 258 259
                 77 52
                 36 11
                 307 306
                 577 552
                 62 61
                 450 425
                 569 570
                 268 293
                 79 78
                 233 208
                 571 570
                 534 535
                 527 552
                 224 199
                 409 408
                 521 520
                 621 622
                 493 518
                 107 106
                 511 510
                 298 299
                 37 62
                 224 249
                 405 380
                 236 237
                 120 121
                 393 418
                 206 231
                 287 288
                 593 568
                 34 59
                 483 484
                 226 227
                 73 74
                 276 277
                 588 587
                 288 313
                 410 385
                 506 505
                 597 598
                 337 312
                 55 56
                 300 325
                 135 134
                 4 29
                 501 500
                 438 437
                 311 312
                 598 599
                 320 345
                 211 236
                 587 562
                 74 99
                 473 498
                 278 279
                 394 369
                 123 148
                 233 232
                 252 277
                 177 202
                 160 185
                 331 356
                 192 191
                 119 118
                 576 601
                 317 316
                 462 487
                 42 43
                 336 311
                 515 490
                 13 14
                 210 235
                 473 448
                 342 341
                 340 315
                 413 388
                 514 515
                 144 143
                 146 145
                 541 566
                 128 103
                 184 159
                 488 489
                 454 455
                 82 83
                 70 45
                 221 222
                 241 240
                 412 411
                 591 590
                 592 593
                 276 301
                 452 453
                 256 255
                 397 372
                 201 200
                 232 207
                 466 465
                 561 586
                 417 442
                 409 434
                 238 239
                 389 390
                 26 1
                 510 485
                 283 282
                 281 306
                 449 474
                 324 349
                 121 146
                 111 112
                 434 435
                 507 508
                 103 104
                 319 294
                 455 480
                 558 557
                 291 292
                 553 578
                 392 391
                 552 551
                 55 80
                 538 539
                 367 392
                 340 365
                 272 297
                 266 265
                 401 376
                 279 280
                 516 515
                 178 177
                 572 571
                 154 179
                 263 262
                 6 31
                 323 348
                 481 506
                 178 179
                 526 527
                 444 469
                 273 274
                 132 133
                 275 300
                 261 236
                 344 369
                 63 38
                 5 30
                 301 300
                 86 87
                 9 10
                 344 319
                 428 427
                 400 375
                 350 375
                 235 236
                 337 336
                 616 615
                 381 380
                 58 59
                 492 493
                 555 556
                 459 434
                 368 369
                 407 382
                 166 141
                 70 95
                 380 355
                 34 35
                 49 24
                 126 127
                 403 378
                 509 484
                 613 588
                 208 207
                 143 168
                 406 431
                 263 238
                 595 596
                 218 193
                 183 182
                 195 220
                 381 406
                 64 65
                 371 372
                 531 506
                 218 219
                 144 145
                 475 450
                 547 548
                 363 362
                 337 362
                 214 239
                 110 111
                 600 575
                 105 106
                 147 148
                 599 574
                 622 623
                 319 320
                 36 35
                 258 233
                 266 267
                 481 480
                 414 439
                 169 168
                 479 478
                 224 223
                 181 182
                 351 326
                 466 441
                 85 60
                 140 165
                 91 90
                 263 264
                 188 187
                 446 447
                 607 606
                 341 316
                 143 142
                 443 442
                 354 353
                 162 137
                 281 256
                 549 574
                 407 408
                 575 550
                 171 170
                 389 388
                 390 391
                 250 225
                 536 537
                 227 228
                 84 59
                 139 140
                 485 484
                 573 598
                 356 381
                 314 315
                 299 324
                 370 395
                 166 165
                 63 62
                 507 506
                 426 425
                 479 454
                 545 570
                 376 375
                 572 597
                 606 581
                 278 277
                 303 302
                 190 165
                 230 205
                 175 200
                 529 528
                 18 17
                 458 457
                 514 513
                 617 616
                 298 323
                 162 161
                 471 472
                 81 56
                 182 207
                 539 564
                 573 572
                 596 621
                 64 39
                 571 546
                 554 555
                 388 363
                 351 376
                 304 329
                 123 122
                 135 160
                 157 132
                 599 624
                 451 426
                 162 187
                 502 477
                 508 483
                 141 140
                 303 328
                 551 576
                 471 446
                 161 160
                 465 490
                 3 2
                 138 113
                 309 284
                 452 451
                 414 413
                 540 565
                 210 185
                 350 325
                 383 382
                 2 1
                 598 623
                 97 72
                 485 460
                 315 316
                 19 20
                 31 32
                 546 521
                 320 321
                 29 54
                 330 331
                 92 67
                 480 505
                 274 249
                 22 47
                 304 279
                 493 468
                 424 423
                 39 40
                 164 165
                 269 268
                 445 446
                 228 203
                 384 409
                 390 365
                 283 308
                 374 399
                 361 386
                 94 119
                 237 262
                 43 68
                 295 270
                 400 425
                 360 335
                 122 121
                 469 468
                 189 188
                 377 352
                 367 342
                 67 42
                 616 591
                 442 467
                 558 533
                 395 394
                 3 28
                 476 477
                 257 258
                 280 281
                 517 542
                 505 504
                 302 301
                 14 15
                 523 498
                 393 368
                 46 71
                 141 142
                 477 452
                 535 510
                 237 238
                 232 231
                 5 6
                 75 50
                 278 253
                 68 69
                 584 559
                 503 504
                 281 282
                 19 44
                 411 410
                 290 265
                 579 554
                 85 84
                 65 66
                 9 8
                 484 459
                 427 402
                 195 196
                 617 618
                 418 443
                 101 126
                 268 243
                 92 117
                 290 315
                 562 561
                 255 280
                 488 487
                 578 603
                 80 79
                 57 58
                 77 78
                 417 418
                 246 271
                 95 96
                 234 233
                 530 555
                 543 568
                 396 397
                 22 23
                 29 28
                 502 527
                 12 13
                 217 216
                 522 547
                 357 332
                 543 518
                 151 176
                 69 70
                 556 557
                 247 248
                 513 538
                 204 205
                 604 605
                 528 527
                 455 456
                 624 623
                 284 285
                 27 26
                 94 95
                 486 511
                 192 167
                 372 347
                 129 104
                 349 374
                 313 314
                 354 329
                 294 293
                 377 378
                 291 290
                 433 408
                 57 56
                 215 190
                 467 492
                 383 408
                 569 594
                 209 208
                 2 27
                 466 491
                 147 122
                 112 113
                 21 46
                 284 259
                 563 538
                 392 417
                 458 433
                 464 465
                 297 298
                 336 361
                 607 582
                 553 554
                 225 200
                 186 211
                 33 34
                 237 212
                 52 51
                 620 595
                 492 517
                 585 610
                 257 282
                 520 545
                 541 540
                 269 244
                 609 584
                 109 84
                 247 246
                 562 537
                 172 197
                 166 167
                 264 265
                 129 130
                 89 114
                 204 179
                 51 76
                 415 390
                 54 53
                 219 244
                 491 490
                 494 493
                 87 62
                 158 183
                 517 518
                 358 359
                 105 104
                 285 260
                 343 318
                 348 347
                 615 614
                 169 144
                 53 78
                 494 495
                 576 577
                 23 24
                 22 21
                 41 40
                 467 466
                 112 87
                 245 220
                 442 441
                 411 436
                 256 257
                 469 494
                 441 416
                 132 107
                 468 467
                 345 344
                 608 609
                 358 333
                 418 419
                 430 429
                 130 131
                 127 128
                 115 90
                 364 365
                 296 271
                 260 235
                 229 228
                 232 257
                 189 190
                 234 235
                 195 170
                 117 118
                 487 486
                 203 204
                 142 117
                 582 583
                 561 536
                 7 32
                 387 388
                 333 334
                 420 421
                 317 292
                 327 352
                 564 563
                 39 14
                 177 152
                 144 119
                 426 401
                 248 223
                 566 567
                 53 28
                 106 131
                 473 472
                 525 526
                 327 302
                 382 381
                 222 197
                 610 609
                 522 521
                 291 316
                 339 338
                 328 329
                 31 56
                 247 222
                 185 186
                 554 529
                 393 392
                 108 83
                 514 489
                 48 23
                 37 12
                 46 45
                 25 0
                 463 462
                 101 76
                 11 10
                 548 573
                 137 112
                 123 124
                 359 360
                 489 490
                 368 367
                 71 96
                 229 230
                 496 495
                 366 365
                 86 85
                 496 497
                 482 481
                 326 301
                 278 303
                 139 114
                 71 70
                 275 276
                 223 198
                 590 565
                 496 521
                 16 41
                 501 476
                 371 370
                 511 536
                 577 602
                 37 38
                 423 422
                 71 72
                 399 424
                 171 146
                 32 33
                 157 182
                 608 583
                 474 499
                 205 206
                 539 514
                 601 600
                 419 420
                 208 183
                 537 538
                 110 85
                 105 130
                 288 289
                 455 430
                 531 532
                 337 338
                 227 202
                 120 145
                 559 534
                 261 262
                 241 216
                 379 354
                 430 405
                 241 266
                 396 421
                 317 318
                 139 164
                 310 285
                 478 477
                 532 557
                 238 213
                 195 194
                 359 384
                 243 242
                 432 457
                 422 447
                 519 518
                 271 272
                 12 11
                 478 453
                 453 428
                 614 613
                 138 139
                 96 97
                 399 398
                 55 54
                 199 174
                 566 591
                 213 188
                 488 513
                 169 194
                 603 602
                 293 318
                 432 431
                 524 523
                 30 31
                 88 63
                 172 173
                 510 509
                 272 273
                 559 558
                 494 519
                 374 373
                 547 572
                 263 288
                 17 16
                 78 103
                 542 543
                 131 132
                 519 544
                 504 529
                 60 59
                 356 355
                 341 340
                 415 414
                 285 286
                 439 438
                 588 563
                 25 50
                 463 438
                 581 556
                 244 245
                 500 475
                 93 92
                 274 299
                 351 350
                 152 127
                 472 497
                 440 415
                 214 215
                 231 230
                 80 81
                 550 525
                 511 512
                 483 458
                 67 68
                 255 254
                 589 588
                 147 172
                 454 453
                 587 612
                 343 368
                 508 509
                 240 265
                 49 48
                 184 183
                 583 558
                 164 189
                 461 436
                 109 134
                 196 171
                 156 181
                 124 99
                 531 530
                 116 91
                 431 430
                 326 325
                 44 45
                 507 482
                 557 582
                 519 520
                 167 142
                 469 470
                 563 562
                 507 532
                 94 93
                 3 4
                 366 391
                 456 431
                 524 549
                 489 464
                 397 398
                 98 97
                 377 402
                 413 412
                 148 149
                 91 66
                 308 333
                 16 15
                 312 287
                 212 211
                 486 461
                 571 596
                 226 251
                 356 357
                 145 170
                 295 294
                 308 309
                 163 138
                 364 339
                 416 417
                 402 401
                 302 277
                 349 348
                 582 581
                 176 175
                 254 279
                 589 614
                 322 297
                 587 586
                 221 246
                 526 551
                 159 158
                 460 461
                 452 427
                 329 330
                 321 322
                 82 107
                 462 461
                 495 520
                 303 304
                 90 65
                 295 320
                 160 159
                 463 464
                 10 35
                 619 594
                 403 402
               |}


let process_str tinyUF = 
  match Ext_string.split tinyUF '\n' with 
  | number :: rest ->
    let n = int_of_string number in
    let store = Union_find.init n in
    List.iter (fun x ->
        match Ext_string.quick_split_by_ws x with 
        | [a;b] ->
          let a,b = int_of_string a , int_of_string b in 
          Union_find.union store a b 
        | _ -> ()) rest;
    Union_find.count store
  | _ -> assert false
;;        

let process_file file = 
  let ichan = open_in_bin file in
  let n = int_of_string (input_line ichan) in
  let store = Union_find.init n in
  let edges = Int_vec_vec.make n in   
  let rec aux i =  
    match input_line ichan with 
    | exception _ -> ()
    | v ->
      begin 
        (* if i = 0 then 
          print_endline "processing 100 nodes start";
    *)
        begin match Ext_string.quick_split_by_ws v with
          | [a;b] ->
            let a,b = int_of_string a , int_of_string b in
            Int_vec_vec.push  edges (Vec_int.of_array [|a;b|]); 
          | _ -> ()
        end;
        aux ((i+1) mod 10000);
      end
  in aux 0;
  (* indeed, [unsafe_internal_array] is necessary for real performnace *)
  let internal = Int_vec_vec.unsafe_internal_array edges in
  for i = 0 to Array.length internal - 1 do
     let i = Vec_int.unsafe_internal_array (Array.unsafe_get internal i) in 
     Union_find.union store (Array.unsafe_get i 0) (Array.unsafe_get i 1) 
  done;  
              (* Union_find.union store a b *)
  Union_find.count store 
;;                
let suites = 
  __FILE__
  >:::
  [
    __LOC__ >:: begin fun _ ->
      OUnit.assert_equal (process_str tinyUF) 2
    end;
    __LOC__ >:: begin fun _ ->
      OUnit.assert_equal (process_str mediumUF) 3
    end;
(*
   __LOC__ >:: begin fun _ ->
      OUnit.assert_equal (process_file "largeUF.txt") 6
    end;
  *)  

  ]
end
module Ounit_utf8_test
= struct
#1 "ounit_utf8_test.ml"


(* https://www.cl.cam.ac.uk/~mgk25/ucs/examples/UTF-8-test.txt
*)

let ((>::),
    (>:::)) = OUnit.((>::),(>:::))

let (=~) = OUnit.assert_equal
let suites = 
    __FILE__
    >:::
    [
        __LOC__ >:: begin fun _ -> 
            Ext_utf8.decode_utf8_string
            "hello 你好，中华民族 hei" =~
            [104; 101; 108; 108; 111; 32; 20320; 22909; 65292; 20013; 21326; 27665; 26063; 32; 104; 101; 105]
        end ;
        __LOC__ >:: begin fun _ -> 
            Ext_utf8.decode_utf8_string
            "" =~ []
        end
    ]
end
module Ounit_util_tests
= struct
#1 "ounit_util_tests.ml"

let ((>::),
     (>:::)) = OUnit.((>::),(>:::))


let (=~) = 
  OUnit.assert_equal
  ~printer:Ext_obj.dump
let suites = 
  __FILE__ >:::
  [
    __LOC__ >:: begin fun _ -> 
      Ext_pervasives.nat_of_string_exn "003" =~ 3;
      (try Ext_pervasives.nat_of_string_exn "0a" |> ignore ; 2 with _ -> -1)  =~ -1;
    end;
    __LOC__ >:: begin fun _ -> 
      let cursor = ref 0 in 
      let v = Ext_pervasives.parse_nat_of_string "123a" cursor in 
      (v, !cursor) =~ (123,3);
      cursor := 0;
      let v = Ext_pervasives.parse_nat_of_string "a" cursor in 
      (v,!cursor) =~ (0,0)
    end;

    (* __LOC__ >:: begin fun _ -> 
      for i = 0 to 0xff do 
        let buf = Ext_buffer.create 0 in 
        Ext_buffer.add_int_1 buf i;
        let s = Ext_buffer.contents buf in 
        s =~ String.make 1 (Char.chr i);
        Ext_string.get_int_1 s 0 =~ i
      done 
    end; *)

    (* __LOC__ >:: begin fun _ -> 
      for i = 0x100 to 0xff_ff do 
        let buf = Ext_buffer.create 0 in 
        Ext_buffer.add_int_2 buf i;
        let s = Ext_buffer.contents buf in         
        Ext_string.get_int_2 s 0 =~ i
      done ;
      let buf = Ext_buffer.create 0 in 
      Ext_buffer.add_int_3 buf 0x1_ff_ff;
      Ext_string.get_int_3 (Ext_buffer.contents buf) 0 =~ 0x1_ff_ff
      ;
      let buf = Ext_buffer.create 0 in 
      Ext_buffer.add_int_4 buf 0x1_ff_ff_ff;
      Ext_string.get_int_4 (Ext_buffer.contents buf) 0 =~ 0x1_ff_ff_ff
    end; *)
    __LOC__ >:: begin fun _ -> 
        let buf = Ext_buffer.create 0 in 
        Ext_buffer.add_string_char buf "hello" 'v';
        Ext_buffer.contents buf =~ "hellov";
        Ext_buffer.length buf =~ 6
    end;
    __LOC__ >:: begin fun _ -> 
        let buf = Ext_buffer.create 0 in 
        Ext_buffer.add_char_string buf 'h' "ellov";
        Ext_buffer.contents buf =~ "hellov";
        Ext_buffer.length buf =~ 6
    end;
    __LOC__ >:: begin fun _ -> 
        String.length 
        (Digest.to_hex(Digest.string "")) =~ 32
    end

  ]
end
module Ounit_vec_test
= struct
#1 "ounit_vec_test.ml"
let ((>::),
     (>:::)) = OUnit.((>::),(>:::))

(* open Ext_json *)

let v = Vec_int.init 10 (fun i -> i);;
let (=~) x y = OUnit.assert_equal ~cmp:(Vec_int.equal  (fun (x: int) y -> x=y)) x y
let (=~~) x y 
  = 
  OUnit.assert_equal ~cmp:(Vec_int.equal  (fun (x: int) y -> x=y)) 
  x (Vec_int.of_array y) 

let suites = 
  __FILE__ 
  >:::
  [
    (* idea 
      [%loc "inplace filter" ] --> __LOC__ ^ "inplace filter" 
      or "inplace filter" [@bs.loc]
    *)
    "inplace_filter " ^ __LOC__ >:: begin fun _ -> 
      v =~~ [|0; 1; 2; 3; 4; 5; 6; 7; 8; 9|];
      
      ignore @@ Vec_int.push v 32;
      let capacity = Vec_int.capacity v  in 
      v =~~ [|0; 1; 2; 3; 4; 5; 6; 7; 8; 9; 32|];
      Vec_int.inplace_filter (fun x -> x mod 2 = 0) v ;
      v =~~ [|0; 2; 4; 6; 8; 32|];
      Vec_int.inplace_filter (fun x -> x mod 3 = 0) v ;
      v =~~ [|0;6|];
      Vec_int.inplace_filter (fun x -> x mod 3 <> 0) v ;
      v =~~ [||];
      OUnit.assert_equal (Vec_int.capacity v ) capacity ;
      Vec_int.compact v ; 
      OUnit.assert_equal (Vec_int.capacity v ) 0 
    end
    ;
    "inplace_filter_from " ^ __LOC__ >:: begin fun _ -> 
      let v = Vec_int.of_array (Array.init 10 (fun i -> i)) in 
      v =~~ [|0; 1; 2; 3; 4; 5; 6; 7; 8; 9|]; 
      Vec_int.push v 96  ;      
      Vec_int.inplace_filter_from 2 (fun x -> x mod 2 = 0) v ;
      v =~~ [|0; 1; 2; 4; 6; 8; 96|];
      Vec_int.inplace_filter_from 2 (fun x -> x mod 3 = 0) v ;
      v =~~ [|0; 1; 6; 96|];
      Vec_int.inplace_filter (fun x -> x mod 3 <> 0) v ;
      v =~~ [|1|];      
      Vec_int.compact v ; 
      OUnit.assert_equal (Vec_int.capacity v ) 1
    end
    ;
    "map " ^ __LOC__ >:: begin fun _ -> 
      let v = Vec_int.of_array (Array.init 1000 (fun i -> i )) in 
      Vec_int.map succ v =~~ (Array.init 1000 succ) ;
      OUnit.assert_bool __LOC__ (Vec_int.exists (fun x -> x >= 999) v );
      OUnit.assert_bool __LOC__ (not (Vec_int.exists (fun x -> x > 1000) v ));
      OUnit.assert_equal (Vec_int.last v ) 999
    end ;  
    __LOC__ >:: begin fun _ -> 
      let count = 1000 in 
      let init_array = (Array.init count (fun i -> i)) in 
      let u = Vec_int.of_array  init_array in 
      let v = Vec_int.inplace_filter_with (fun x -> x mod 2 = 0) ~cb_no:(fun a b -> Set_int.add b a)Set_int.empty u  in
      let (even,odd) = init_array |> Array.to_list |> List.partition (fun x -> x mod 2 = 0) in 
      OUnit.assert_equal 
      (Set_int.elements v) odd ;
      u =~~ Array.of_list even 
    end ;
    "filter" ^ __LOC__ >:: begin fun _ -> 
      let v = Vec_int.of_array [|1;2;3;4;5;6|] in 
      v |> Vec_int.filter (fun x -> x mod 3 = 0) |> (fun x -> x =~~ [|3;6|]);
      v =~~ [|1;2;3;4;5;6|];
      Vec_int.pop v ; 
      v =~~ [|1;2;3;4;5|];
      let count = ref 0 in 
      let len = Vec_int.length v  in 
      while not (Vec_int.is_empty v ) do 
        Vec_int.pop v ;
        incr count
      done;
      OUnit.assert_equal len !count
    end
    ;
    __LOC__ >:: begin fun _ -> 
      let count = 100 in 
      let v = Vec_int.of_array (Array.init count (fun i -> i)) in 
      OUnit.assert_bool __LOC__ 
        (try Vec_int.delete v count; false with _ -> true );
      for i = count - 1 downto 10 do 
        Vec_int.delete v i ;
      done ;
      v =~~ [|0;1;2;3;4;5;6;7;8;9|] 
    end; 
    "sub" ^ __LOC__ >:: begin fun _ -> 
      let v = Vec_int.make 5 in 
      OUnit.assert_bool __LOC__
        (try ignore @@ Vec_int.sub v 0 2 ; false with Invalid_argument _  -> true);
      Vec_int.push v 1;
      OUnit.assert_bool __LOC__
        (try ignore @@ Vec_int.sub v 0 2 ; false with Invalid_argument _  -> true);
      Vec_int.push v 2;  
      ( Vec_int.sub v 0 2 =~~ [|1;2|])
    end;
    "reserve" ^ __LOC__ >:: begin fun _ -> 
      let v = Vec_int.empty () in 
      Vec_int.reserve v  1000 ;
      for i = 0 to 900 do
        Vec_int.push v i
      done ;
      OUnit.assert_equal (Vec_int.length v) 901 ;
      OUnit.assert_equal (Vec_int.capacity v) 1000
    end ; 
    "capacity"  ^ __LOC__ >:: begin fun _ -> 
      let v = Vec_int.of_array [|3|] in 
      Vec_int.reserve v 10 ;
      v =~~ [|3 |];
      Vec_int.push v 1 ;
      Vec_int.push v 2 ;
      Vec_int.push v 5;
      v=~~ [|3;1;2;5|];
      OUnit.assert_equal (Vec_int.capacity v  ) 10 ;
      for i = 0 to 5 do
        Vec_int.push v i
      done;
      v=~~ [|3;1;2;5;0;1;2;3;4;5|];
      Vec_int.push v 100;
      v=~~[|3;1;2;5;0;1;2;3;4;5;100|];
      OUnit.assert_equal (Vec_int.capacity v ) 20
    end
    ;
    __LOC__  >:: begin fun _ -> 
      let empty = Vec_int.empty () in 
      Vec_int.push empty 3;
      empty =~~ [|3|];

    end
    ;
    __LOC__ >:: begin fun _ ->
      let lst = [1;2;3;4] in 
      let v = Vec_int.of_list lst in 
      OUnit.assert_equal 
        (Vec_int.map_into_list (fun x -> x + 1) v)
        (Ext_list.map lst (fun x -> x + 1) )  
    end;
    __LOC__ >:: begin fun _ ->
      let v = Vec_int.make 4 in 
      Vec_int.push v  1 ;
      Vec_int.push v 2;
      Vec_int.reverse_in_place v;
      v =~~ [|2;1|]
    end
    ;
  ]

end
module Ounit_tests_main : sig 
#1 "ounit_tests_main.mli"

end = struct
#1 "ounit_tests_main.ml"


[@@@warning "-32"]

module Int_array = Vec.Make(struct type t = int let null = 0 end);;
let v = Int_array.init 10 (fun i -> i);;

let ((>::),
     (>:::)) = OUnit.((>::),(>:::))


let (=~) x y = OUnit.assert_equal ~cmp:(Int_array.equal  (fun (x: int) y -> x=y)) x y
let (=~~) x y 
  = 
  OUnit.assert_equal ~cmp:(Int_array.equal  (fun (x: int) y -> x=y)) x (Int_array.of_array y) 

let suites = 
  __FILE__ >:::
  [
    Ounit_vec_test.suites;
    Ounit_json_tests.suites;
    Ounit_path_tests.suites;
    Ounit_array_tests.suites;    
    Ounit_scc_tests.suites;
    Ounit_list_test.suites;
    Ounit_hash_set_tests.suites;
    Ounit_union_find_tests.suites;
    Ounit_bal_tree_tests.suites;
    Ounit_hash_stubs_test.suites;
    Ounit_map_tests.suites;
    Ounit_ordered_hash_set_tests.suites;
    Ounit_hashtbl_tests.suites;
    Ounit_string_tests.suites;
    Ounit_topsort_tests.suites;
    (* Ounit_sexp_tests.suites; *)
    Ounit_int_vec_tests.suites;
    Ounit_ident_mask_tests.suites;
    Ounit_cmd_tests.suites;
    Ounit_ffi_error_debug_test.suites;
    Ounit_js_regex_checker_tests.suites;
    Ounit_utf8_test.suites;
    Ounit_unicode_tests.suites;
    Ounit_bsb_regex_tests.suites;
    Ounit_bsb_pkg_tests.suites;
    Ounit_depends_format_test.suites;
    Ounit_util_tests.suites;
  ]
let _ = 
  OUnit.run_test_tt_main suites

end
