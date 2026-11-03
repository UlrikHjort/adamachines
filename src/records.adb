--  Adamachines: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;

package body Records is

   function Home return String is
     (if Ada.Environment_Variables.Exists ("HOME") then Ada.Environment_Variables.Value ("HOME") else ".");

   function Dir return String is (Home & "/.adamachines");

   function Img (N : Integer) return String is
      S : constant String := Integer'Image (N);
   begin
      return S (S'First + 1 .. S'Last);
   end Img;

   Laps : array (Tracks.Track_Id) of Float := (others => 0.0);

   --  The tracks were once numbered 1 .. 14 and yours 15 .. 19; old files say so
   function From_Old_Number (N : Integer) return Natural is
     (if N in 1 .. 14 then N
      elsif N in 15 .. 19 then Tracks.First_Custom + N - 15
      else 0);

   --  A file name made from the track's name: TOY TRAIN TOWN gives toy-train-town
   function Key (Id : Tracks.Track_Id) return String is
      N : constant String := Tracks.Name (Id);
      R : String := N;
   begin
      for I in R'Range loop
         if R (I) in 'A' .. 'Z' then
            R (I) := Character'Val (Character'Pos (R (I)) + 32);
         elsif R (I) not in 'a' .. 'z' | '0' .. '9' then
            R (I) := '-';
         end if;
      end loop;
      return R;
   end Key;

   function By_Name (Name : String) return Natural is
   begin
      for Id in Tracks.Track_Id loop
         if Tracks.Name (Id) = Name then
            return Id;
         end if;
      end loop;
      return 0;
   end By_Name;

   procedure Ensure_Dir is
   begin
      if not Ada.Directories.Exists (Dir) then
         Ada.Directories.Create_Path (Dir);
      end if;
   exception
      when others => null;
   end Ensure_Dir;

   procedure Save is
      use Ada.Text_IO;
      F : File_Type;
   begin
      Ensure_Dir;
      Create (F, Out_File, Dir & "/records");
      for Id in Laps'Range loop
         if Laps (Id) > 0.0 then
            Put_Line (F, Tracks.Name (Id) & "|" & Img (Integer (Laps (Id) * 1000.0)));
         end if;
      end loop;
      Close (F);
   exception
      when others => null;
   end Save;

   procedure Load is
      use Ada.Text_IO;
      F : File_Type;
   begin
      if not Ada.Directories.Exists (Dir & "/records") then
         return;
      end if;
      Open (F, In_File, Dir & "/records");
      while not End_Of_File (F) loop
         declare
            L : constant String := Get_Line (F);
         begin
            for I in L'Range loop
               if L (I) = '|' or else L (I) = ' ' then
                  declare
                     Id : constant Natural :=
                       (if L (I) = '|' then By_Name (L (L'First .. I - 1))
                        else From_Old_Number (Integer'Value (L (L'First .. I - 1))));
                     Ms : constant Integer := Integer'Value (L (I + 1 .. L'Last));
                  begin
                     if Id in Tracks.Track_Id and then Ms > 0 then
                        Laps (Id) := Float (Ms) / 1000.0;
                     end if;
                  end;
                  exit;
               end if;
            end loop;
         exception
            when others => null;
         end;
      end loop;
      Close (F);
   exception
      when others => null;
   end Load;

   function Best_Lap (Id : Tracks.Track_Id) return Float is (Laps (Id));

   function Offer_Lap (Id : Tracks.Track_Id; T : Float) return Boolean is
   begin
      if T > 1.0 and then (Laps (Id) = 0.0 or else T < Laps (Id)) then
         Laps (Id) := T;
         Save;
         return True;
      end if;
      return False;
   end Offer_Lap;

   ---------------------------------------------------------------------------
   --  The ghost
   ---------------------------------------------------------------------------

   Max_Frames : constant := 30 * 180;
   type Frame is record
      X, Y, H : Float := 0.0;
   end record;
   type Frame_Array is array (1 .. Max_Frames) of Frame;

   Now_Lap : Frame_Array;          --  the lap being driven
   Now_Count : Natural := 0;
   Best : Frame_Array;             --  the ghost
   Best_Count : Natural := 0;
   Best_T : Float := 0.0;
   Best_Track : Natural := 0;

   procedure Begin_Lap is
   begin
      Now_Count := 0;
   end Begin_Lap;

   procedure Record_Frame (P : Vec; H : Float) is
   begin
      if Now_Count < Max_Frames then
         Now_Count := Now_Count + 1;
         Now_Lap (Now_Count) := (P.X, P.Y, H);
      end if;
   end Record_Frame;

   function Ghost_File (Id : Tracks.Track_Id) return String is (Dir & "/ghost-" & Key (Id));

   --  Where the ghost of a track was kept when the tracks went by number
   function Old_Ghost_File (Id : Tracks.Track_Id) return String is
     (if Id <= 14 then Dir & "/ghost-" & Img (Id)
      elsif Tracks.Is_Custom (Id) then Dir & "/ghost-" & Img (15 + Tracks.Slot_Of (Id) - 1)
      else "");

   procedure End_Lap (Id : Tracks.Track_Id; T : Float) is
      use Ada.Streams.Stream_IO;
      F : File_Type;
   begin
      if Now_Count < 10 or else Now_Count = Max_Frames then
         return;
      end if;
      if Best_Track = Id and then Best_Count > 0 and then T >= Best_T then
         return;
      end if;
      Best := Now_Lap;
      Best_Count := Now_Count;
      Best_T := T;
      Best_Track := Id;
      Ensure_Dir;
      Create (F, Out_File, Ghost_File (Id));
      Float'Write (Stream (F), T);
      Natural'Write (Stream (F), Best_Count);
      for K in 1 .. Best_Count loop
         Frame'Write (Stream (F), Best (K));
      end loop;
      Close (F);
   exception
      when others => null;
   end End_Lap;

   procedure Load_Ghost (Id : Tracks.Track_Id) is
      use Ada.Streams.Stream_IO;
      F : File_Type;
      N : Natural;
   begin
      Best_Track := Id;
      Best_Count := 0;
      Best_T := 0.0;
      if not Ada.Directories.Exists (Ghost_File (Id)) then
         if Old_Ghost_File (Id) /= "" and then Ada.Directories.Exists (Old_Ghost_File (Id)) then
            Ada.Directories.Rename (Old_Ghost_File (Id), Ghost_File (Id));
         else
            return;
         end if;
      end if;
      Open (F, In_File, Ghost_File (Id));
      Float'Read (Stream (F), Best_T);
      Natural'Read (Stream (F), N);
      N := Natural'Min (N, Max_Frames);
      for K in 1 .. N loop
         Frame'Read (Stream (F), Best (K));
      end loop;
      Best_Count := N;
      Close (F);
   exception
      when others =>
         Best_Count := 0;
   end Load_Ghost;

   function Has_Ghost return Boolean is (Best_Count > 0);
   function Ghost_Time return Float is (Best_T);

   procedure Ghost_At (T : Float; P : out Vec; H : out Float; Valid : out Boolean) is
      F : constant Float := T * Ghost_Rate;
      K : constant Integer := Integer (Float'Floor (F)) + 1;
   begin
      P := Zero;
      H := 0.0;
      Valid := Best_Count > 1 and then K >= 1 and then K < Best_Count;
      if Valid then
         declare
            A : constant Frame := Best (K);
            B : constant Frame := Best (K + 1);
            U : constant Float := F - Float'Floor (F);
         begin
            P := ((A.X + (B.X - A.X) * U), (A.Y + (B.Y - A.Y) * U));
            H := A.H + Wrap (B.H - A.H) * U;
         end;
      end if;
   end Ghost_At;

end Records;
