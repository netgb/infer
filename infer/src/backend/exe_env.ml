(*
 * Copyright (c) 2009-2013, Monoidics ltd.
 * Copyright (c) 2013-present, Facebook, Inc.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

open! IStd

(** Execution environments: basically a cache of where procedures are and what is their CFG and type
   environment *)

module L = Logging

(** per-file data: type environment and cfg *)
type file_data = {source: SourceFile.t; mutable tenv: Tenv.t option; mutable cfg: Cfg.t option}

(** create a new file_data *)
let new_file_data source =
  (* Do not fill in tenv and cfg as they can be quite large. This makes calls to fork() cheaper
     until we start filling out these fields. *)
  { source
  ; tenv= None (* Sil.load_tenv_from_file tenv_file *)
  ; cfg= None (* Cfg.load_cfg_from_file cfg_file *) }


let create_file_data table source =
  match SourceFile.Hash.find table source with
  | file_data ->
      file_data
  | exception Caml.Not_found ->
      let file_data = new_file_data source in
      SourceFile.Hash.add table source file_data ;
      file_data


type t =
  { proc_map: file_data Typ.Procname.Hash.t  (** map from procedure name to file data *)
  ; file_map: file_data SourceFile.Hash.t  (** map from source files to file data *) }

let get_file_data exe_env pname =
  try Some (Typ.Procname.Hash.find exe_env.proc_map pname) with Caml.Not_found ->
    let source_file_opt =
      match Attributes.load pname with
      | None ->
          L.(debug Analysis Medium) "can't find tenv_cfg_object for %a@." Typ.Procname.pp pname ;
          None
      | Some proc_attributes when Config.reactive_capture ->
          let get_captured_file {ProcAttributes.translation_unit} = translation_unit in
          OndemandCapture.try_capture proc_attributes |> Option.map ~f:get_captured_file
      | Some proc_attributes ->
          Some proc_attributes.ProcAttributes.translation_unit
    in
    let get_file_data_for_source source_file =
      let file_data = create_file_data exe_env.file_map source_file in
      Typ.Procname.Hash.replace exe_env.proc_map pname file_data ;
      file_data
    in
    Option.map ~f:get_file_data_for_source source_file_opt


let file_data_to_tenv file_data =
  if is_none file_data.tenv then file_data.tenv <- Tenv.load file_data.source ;
  file_data.tenv


let file_data_to_cfg file_data =
  if is_none file_data.cfg then file_data.cfg <- Cfg.load file_data.source ;
  file_data.cfg


let java_global_tenv =
  lazy
    ( match Tenv.load_global () with
    | None ->
        L.(die InternalError) "Could not load the global tenv"
    | Some tenv ->
        tenv )


(** return the type environment associated to the procedure *)
let get_tenv exe_env proc_name =
  match proc_name with
  | Typ.Procname.Java _ ->
      Lazy.force java_global_tenv
  | _ -> (
    match get_file_data exe_env proc_name with
    | Some file_data -> (
      match file_data_to_tenv file_data with
      | Some tenv ->
          tenv
      | None ->
          let loc = State.get_loc () in
          L.(die InternalError)
            "get_tenv: tenv not found for %a in file '%a' at %a" Typ.Procname.pp proc_name
            SourceFile.pp loc.Location.file Location.pp loc )
    | None ->
        let loc = State.get_loc () in
        L.(die InternalError)
          "get_tenv: file_data not found for %a in file '%a' at %a" Typ.Procname.pp proc_name
          SourceFile.pp loc.Location.file Location.pp loc )


(** return the cfg associated to the procedure *)
let get_cfg exe_env pname =
  match get_file_data exe_env pname with
  | None ->
      None
  | Some file_data ->
      file_data_to_cfg file_data


(** return the proc desc associated to the procedure *)
let get_proc_desc exe_env pname =
  match get_cfg exe_env pname with
  | Some cfg ->
      Typ.Procname.Hash.find_opt cfg pname
  | None ->
      None


let mk () = {proc_map= Typ.Procname.Hash.create 17; file_map= SourceFile.Hash.create 1}
