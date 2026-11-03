--  Adamachines: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The best lap of every track, and the ghost of it: the way the car
--  went, thirty times a second, to race against in a time trial.
--  Kept in ~/.adamachines.

with Geom; use Geom;
with Tracks;

package Records is

   procedure Load;

   function Best_Lap (Id : Tracks.Track_Id) return Float;   --  0 when there is none
   function Offer_Lap (Id : Tracks.Track_Id; T : Float) return Boolean;
   --  A lap was driven: True when it is a new record (then it is saved)

   --  The ghost
   Ghost_Rate : constant := 30.0;           --  frames a second

   procedure Begin_Lap;                     --  the line was crossed: a new lap is recorded
   procedure Record_Frame (P : Vec; H : Float);
   procedure End_Lap (Id : Tracks.Track_Id; T : Float);
   --  The lap just driven took T seconds: it becomes the ghost if it is the fastest

   procedure Load_Ghost (Id : Tracks.Track_Id);
   function Has_Ghost return Boolean;
   function Ghost_Time return Float;
   procedure Ghost_At (T : Float; P : out Vec; H : out Float; Valid : out Boolean);
   --  Where the ghost is T seconds into its lap

end Records;
