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



type boxed_integer = Lambda.boxed_integer = 
    Pnativeint | Pint32 | Pint64


let eq_boxed_integer (p : boxed_integer) (p1 : boxed_integer ) = 
  match p with 
  | Pnativeint -> p1 = Pnativeint 
  | Pint32 -> p1 = Pint32
  | Pint64 -> p1 = Pint64    

type comparison = Lambda.comparison = 
    Ceq | Cneq | Clt | Cgt | Cle | Cge


let eq_comparison ( p : comparison) (p1:comparison) = 
  match p with 
  | Cge -> p1 =  Cge
  | Cgt -> p1 =  Cgt
  | Cle -> p1 =  Cle
  | Clt -> p1 =  Clt 
  | Ceq -> p1 =  Ceq 
  | Cneq -> p1 =  Cneq 



let cmp_int32 (cmp : comparison) (a : int32) b : bool =
  match cmp with
  | Ceq -> a = b
  | Cneq -> a <> b
  | Cgt -> a > b
  | Cle -> a <= b
  | Clt -> a < b
  | Cge -> a >= b

let cmp_int64 (cmp : comparison) (a : int64) b : bool =
  match cmp with
  | Ceq -> a = b
  | Cneq -> a <> b
  | Cgt -> a > b
  | Cle -> a <= b
  | Clt -> a < b
  | Cge -> a >= b

let cmp_nativeint (cmp : comparison) (a : nativeint) b : bool =
  match cmp with
  | Ceq -> a = b
  | Cneq -> a <> b
  | Cgt -> a > b
  | Cle -> a <= b
  | Clt -> a < b
  | Cge -> a >= b

let cmp_float (cmp : comparison) (a : float) b : bool =
  match cmp with
  | Ceq -> a = b
  | Cneq -> a <> b
  | Cgt -> a > b
  | Cle -> a <= b
  | Clt -> a < b
  | Cge -> a >= b

let cmp_int (cmp : comparison) (a : int) b : bool =
  match cmp with
  | Ceq -> a = b
  | Cneq -> a <> b
  | Cgt -> a > b
  | Cle -> a <= b
  | Clt -> a < b
  | Cge -> a >= b


type compile_time_constant =
  | Big_endian  
  | Ostype_unix
  | Ostype_win32    
  | Ostype
  | Backend_type

(** relies on the fact that [compile_time_constant] is enum type *)
let eq_compile_time_constant ( p : compile_time_constant) (p1 : compile_time_constant) = 
  p = p1

type let_kind = Lambda.let_kind
= Strict
| Alias
| StrictOpt
| Variable


type meth_kind = Lambda.meth_kind
= Self
| Public of string option
| Cached

type field_dbg_info = Lambda.field_dbg_info =
  | Fld_na of string
  | Fld_record of { name : string; mutable_flag : Asttypes.mutable_flag}
  | Fld_module of { name : string }
  | Fld_record_inline of { name : string}
  | Fld_record_extension of {name : string }
  | Fld_tuple
  | Fld_poly_var_tag
  | Fld_poly_var_content
  | Fld_extension
  | Fld_variant
  | Fld_cons
  | Fld_array 

let str_of_field_info (x : field_dbg_info) : string option =  
  match x with 
  | Fld_na  s -> if s = "" then None else Some s
  | Fld_array
  | Fld_extension
  | Fld_variant
  | Fld_cons
  | Fld_poly_var_tag 
  | Fld_poly_var_content
  | Fld_tuple 
    -> None   
  | Fld_record {name ; _} 
  | Fld_module {name ; _}
  | Fld_record_inline {name}
  | Fld_record_extension {name}
    -> 
    Some name

type set_field_dbg_info = Lambda.set_field_dbg_info = 
  | Fld_set_na
  | Fld_record_set of string 
  | Fld_record_inline_set of string  
  | Fld_record_extension_set of string



