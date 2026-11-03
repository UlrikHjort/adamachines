--  Adamachines: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Directories;
with GNAT.OS_Lib;

package body Speech is

   Checked : Boolean := False;
   Found : Boolean := False;

   function Available return Boolean is
   begin
      if not Checked then
         Checked := True;
         Found := Ada.Directories.Exists ("/usr/bin/espeak-ng") and then Ada.Directories.Exists ("/bin/sh");
      end if;
      return Found;
   end Available;

   procedure Say (Text : String) is
      use GNAT.OS_Lib;
      Clean : String := Text;
      Ok : Boolean;
   begin
      if not Enabled or else not Available or else Loudness = 0 then
         return;
      end if;
      --  Only letters, digits and spaces reach the shell
      for C of Clean loop
         if not (C in 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | ' ' | '!' | '.' | ',') then
            C := ' ';
         end if;
      end loop;
      declare
         Args : Argument_List_Access := new Argument_List'
           (new String'("-c"),
            new String'("espeak-ng "
                        & (case Voice is
                              when Woman => "-v en-us+f3 -s 160 -p 60",
                              when Man => "-v en -s 165 -p 55")
                        & " -a" & Natural'Image (Loudness) & " '" & Clean & "' >/dev/null 2>&1 &"));
      begin
         Spawn ("/bin/sh", Args.all, Ok);
         for A of Args.all loop
            Free (A);
         end loop;
         Free (Args);
      end;
   end Say;

end Speech;
