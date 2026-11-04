--  Adamachines: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The AI races three laps on every track, every car must finish
--  in good time, and few of them may need putting back on the road.

with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with Cars;
with Net;
with Geom; use Geom;
with Race; use Race;
with Tracks;

procedure Simtest is
   Failed : Boolean := False;
   function Img (X : Float) return String is
      S : constant String := Integer'Image (Integer (X * 10.0));
   begin
      return S (S'First .. S'Last - 1) & "." & S (S'Last);
   end Img;
begin
   for Id in 1 .. Tracks.First_Custom loop
      Setup (Id, Single, 5, 3, Hard);
      declare
         Falls, Backs, Bumps, Jumps, Picks, Shots, Hits, Scares : Natural := 0;
         Seen : Natural := Event_Serial;
         Steps : Natural := 0;
         All_Done : Boolean := False;
      begin
         while Steps < Natural (300.0 / Dt) and then not All_Done loop
            Step ((others => <>), Autopilot => True);
            Steps := Steps + 1;
            for K in Seen .. Event_Serial - 1 loop
               case Events (K mod Event_Ring).Kind is
                  when Fell => Falls := Falls + 1;
                  when Put_Back => Backs := Backs + 1;
                  when Bump => Bumps := Bumps + 1;
                  when Jumped => Jumps := Jumps + 1;
                  when Picked => Picks := Picks + 1;
                  when Fired | Dropped => Shots := Shots + 1;
                  when Spun => Hits := Hits + 1;
                  when Scared => Scares := Scares + 1;
                  when others => null;
               end case;
            end loop;
            Seen := Event_Serial;
            All_Done := True;
            for I in 1 .. State.Count loop
               if not State.Racers (I).Finished then
                  All_Done := False;
               end if;
            end loop;
         end loop;
         Put_Line (Tracks.Name (Id) & ": lap" & Integer (Tracks.Lap_Length)'Image & " units, "
                   & Tracks.Item_Count'Image & " things");
         for K in 1 .. State.Count loop
            declare
               R : Racer renames State.Racers (In_Place (K));
            begin
               Put_Line ("  " & K'Image & " " & R.Name & (if R.Finished then " " & Img (R.Finish_T) & " s, best lap "
                         & Img (R.Best_Lap) else " did not finish, lap" & R.Lap'Image));
               if not R.Finished then
                  Failed := True;
               end if;
            end;
         end loop;
         Put_Line ("   falls" & Falls'Image & ", put back" & Backs'Image & ", knocks" & Bumps'Image
                   & ", jumps" & Jumps'Image & ", pick-ups" & Picks'Image & ", used" & Shots'Image
                   & ", spun" & Hits'Image
                   & (if Scares > 0 then ", scared by ghosts" & Scares'Image else ""));
         if Picks < 6 then
            Put_Line ("   too few pick-ups taken");
            Failed := True;
         end if;
         if Backs > 6 then
            Put_Line ("   too many cars put back");
            Failed := True;
         end if;
      end;
   end loop;

   --  A player at the keyboard: full lock or none, full throttle or the brake
   for Id in 1 .. Tracks.First_Custom loop
      Setup (Id, Single, 1, 2, Easy);
      declare
         Steps : Natural := 0;
         Seen : Natural := Event_Serial;
         Backs : Natural := 0;
         Me : constant Car_Index := Player (1);
      begin
         while Steps < Natural (150.0 / Dt) and then not State.Racers (Me).Finished loop
            declare
               R : Racer renames State.Racers (Me);
               C : Cars.Car renames R.Car;
               T : constant Tracks.Sample := Tracks.Get (R.Index + 6 + Integer (Float'Max (0.0, C.Forward) / 30.0));
               Err : constant Float := Wrap (Angle_Of (T.P - C.P) - C.H);
               Bend : Float := 0.0;
               I : Input;
            begin
               for J in 4 .. 30 loop
                  Bend := Float'Max (Bend, abs Tracks.Get (R.Index + J).Turn);
               end loop;
               I.P1.Steer := (if Err > 0.04 then 1.0 elsif Err < -0.04 then -1.0 else 0.0);
               if C.Forward > 60.0 + 1.6 / (Bend + 0.004) then
                  I.P1.Brake := 1.0;
               else
                  I.P1.Throttle := 1.0;
               end if;
               Step (I);
            end;
            Steps := Steps + 1;
            for K in Seen .. Event_Serial - 1 loop
               if Events (K mod Event_Ring).Kind = Put_Back and then Events (K mod Event_Ring).Car = Me then
                  Backs := Backs + 1;
               end if;
            end loop;
            Seen := Event_Serial;
         end loop;
         Put_Line ("Keyboard driver on " & Tracks.Name (Id) & ": "
                   & (if State.Racers (Me).Finished then "two laps in " & Img (State.Racers (Me).Finish_T) & " s"
                      else "did not finish")
                   & ", put back" & Backs'Image);
         if not State.Racers (Me).Finished then
            Failed := True;
         end if;
      end;
   end loop;

   --  A duel between two AI drivers: points change hands and it comes to an end
   Setup (1, Duel, 0, 3, Normal);
   declare
      Points, Rounds : Natural := 0;
      Seen : Natural := Event_Serial;
   begin
      for K in 1 .. Natural (400.0 / Dt) loop
         Step ((others => <>), Autopilot => True);
         --  one of the drivers is a little slower, so someone gets left behind
         State.Racers (Player (2)).Car.Top_Factor := 0.9;
         for E in Seen .. Event_Serial - 1 loop
            if Events (E mod Event_Ring).Kind = Point_Won then
               Points := Points + 1;
            elsif Events (E mod Event_Ring).Kind = Go then
               Rounds := Rounds + 1;
            end if;
         end loop;
         Seen := Event_Serial;
         exit when State.Phase = Over;
      end loop;
      Put_Line ("Duel:" & Points'Image & " points won," & Rounds'Image & " starts, "
                & (if State.Phase = Over then "won by P" & State.Racers (State.Winner).Human'Image
                   else "not over"));
      if State.Phase /= Over or else Points < 4 then
         Failed := True;
      end if;
   end;

   --  A copy of a built-in track in a slot leaves the original as it was
   declare
      use type Tracks.Theme_Kind;
      Before : Float;
   begin
      Tracks.Load (14);
      Before := Tracks.Lap_Length;
      Tracks.Copy_Track (14);
      Tracks.Custom_Points (1).X := Tracks.Custom_Points (1).X + 300.0;   --  and changed it
      Tracks.Slots (2) := (Tracks.Custom_Points, Tracks.Custom_Count, Tracks.Custom_Theme, True);
      Tracks.Load (Tracks.First_Custom + 1);
      Put_Line ("Copy of " & Tracks.Name (14) & " in " & Tracks.Name (Tracks.First_Custom + 1) & ":"
                & Tracks.Custom_Count'Image & " points, lap" & Integer (Tracks.Lap_Length)'Image);
      Tracks.Load (14);
      if Tracks.Lap_Length /= Before or else Tracks.Custom_Theme /= Tracks.Toy_Town
        or else Tracks.Theme_Of (Tracks.First_Custom + 1) /= Tracks.Toy_Town
      then
         Put_Line ("   the original track changed, or the copy is wrong");
         Failed := True;
      else
         Put_Line ("   the original is unchanged, lap" & Integer (Before)'Image);
      end if;
   end;

   --  The race as the network sends it: packed and unpacked, it is the same race
   Setup (14, Single, 5, 1, Normal);
   for K in 1 .. Natural (20.0 / Dt) loop
      Step ((others => <>), Autopilot => True);
   end loop;
   declare
      Ok : Boolean;
   begin
      Net.Self_Test_Pack (Ok);
      Put_Line ("A race state sent over the network: " & (if Ok then "comes out the same" else "CHANGED"));
      Failed := Failed or else not Ok;
   end;

   if Failed then
      Put_Line ("FAILED");
      Ada.Command_Line.Set_Exit_Status (1);
   else
      Put_Line ("All finished.");
   end if;
end Simtest;
