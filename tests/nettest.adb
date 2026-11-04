--  Adamachines: tiny machines racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  A race over the network, between two processes on this machine:
--    nettest host            hosts a game, waits for a player, races a lap of the Hockey Rink
--    nettest join ADDRESS    joins it and drives, from the race state the host sends
--    nettest join find       the same, but finds the game on the network first, as the
--                            JOIN A GAME screen does, and joins the one it found
--    nettest second          while a game is hosted here: hosting another must be refused
--    nettest late ADDRESS    joins while the race is on: it waits in the lobby, is not in
--                            that race, and is in the lobby when the host comes back to it
--    nettest host late       hosts as above, and checks the late player is in the lobby after
--  Both drive like a player at the keyboard.  The race must end with the
--  joined player's car home, driven by the keys it sent.

with Ada.Command_Line; use Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO; use Ada.Text_IO;
with Cars;
with Geom; use Geom;
with Net;
with Race; use Race;
with Tracks;

procedure Nettest is

   use type Net.Join_State;

   --  Steering like a player: full lock or none, full throttle or the brake
   function Drive (Me : Car_Index) return Cars.Controls is
      R : Racer renames State.Racers (Me);
      C : Cars.Car renames R.Car;
      Index : constant Natural := Tracks.Nearest (C.P);
      T : constant Tracks.Sample := Tracks.Get (Index + 6 + Integer (Float'Max (0.0, C.Forward) / 30.0));
      Err : constant Float := Wrap (Angle_Of (T.P - C.P) - C.H);
      Bend : Float := 0.0;
      Out_C : Cars.Controls;
   begin
      for J in 4 .. 30 loop
         Bend := Float'Max (Bend, abs Tracks.Get (Index + J).Turn);
      end loop;
      Out_C.Steer := (if Err > 0.04 then 1.0 elsif Err < -0.04 then -1.0 else 0.0);
      if C.Forward > 60.0 + 1.6 / (Bend + 0.004) then
         Out_C.Brake := 1.0;
      else
         Out_C.Throttle := 1.0;
      end if;
      return Out_C;
   end Drive;

   procedure Fail (Why : String) is
   begin
      Put_Line ("nettest " & Argument (1) & ": FAILED: " & Why);
      Net.Stop;
      Set_Exit_Status (Failure);
   end Fail;

   Step_Time : constant := 0.002;   --  a quarter of the real time a step takes: the race runs fast

begin
   if Argument_Count >= 1 and then Argument (1) = "host" then
      if not Net.Host ("HOST  ") then
         Fail ("the port is taken");
         return;
      end if;
      Net.Lobby.Track := 16;
      Net.Lobby.Laps := 1;
      Net.Lobby.AIs := 2;
      Net.Changed;
      for Wait in 1 .. 1000 loop
         Net.Poll (0.01);
         exit when Net.Lobby.Players >= 2;
         delay 0.01;
      end loop;
      if Net.Lobby.Players < 2 then
         Fail ("nobody joined");
         return;
      end if;
      Put_Line ("nettest host: " & Net.Lobby.Names (2) & " joined");
      Net.Host_Start;
      Setup_Net (Net.Lobby.Track, Net.Lobby.Players, Net.Lobby.Names, Net.Lobby.AIs,
                 Net.Lobby.Laps, Net.Lobby.Level, Net.Lobby.Items);
      Local := 1;
      for Frame in 1 .. 30 * 90 loop
         Net.Poll (4.0 * Dt);
         for K in 1 .. 4 loop
            declare
               I : Input;
            begin
               I.Keys (1) := Drive (Player (1));
               Net.Host_Inputs (I);
               Step (I);
            end;
         end loop;
         Net.Host_Send_State;
         delay 4.0 * Step_Time;
         exit when State.Phase = Over and then State.Over_T > 1.0;
      end loop;
      declare
         R : Racer renames State.Racers (Player (2));
      begin
         if not R.Finished then
            Fail ("the joined player did not finish");
         elsif R.Lost then
            Fail ("the joined player was lost on the way");
         else
            Put_Line ("nettest host: GUEST finished " & Integer'Image (R.Place) & " of"
                      & Integer'Image (State.Count) & ", lap" & Integer'Image (Integer (R.Best_Lap * 10.0)) & " tenths");
         end if;
      end;
      if Argument_Count >= 2 and then Argument (2) = "late" then
         if Net.Lobby.Players /= 3 then
            Fail ("the player who joined during the race is not in the lobby after it");
            return;
         end if;
         Put_Line ("nettest host: " & Net.Lobby.Names (3) & " joined during the race, for the next one");
      end if;
      Net.Host_Lobby;
      for K in 1 .. 50 loop
         Net.Poll (0.01);
         delay 0.01;
      end loop;
      Net.Stop;

   elsif Argument_Count >= 1 and then Argument (1) = "second" then
      if Net.Host ("SECOND") then
         Fail ("a second game was hosted on the port already taken");
      else
         Put_Line ("nettest second: a second game on this machine is refused");
      end if;

   elsif Argument_Count >= 2 and then Argument (1) = "late" then
      Net.Join (Argument (2), "LATE  ");
      for Wait in 1 .. 1000 loop
         Net.Poll (0.01);
         exit when Net.Joining /= Net.Asking and then Net.Lobby.Players > 0;
         delay 0.01;
      end loop;
      if Net.Joining /= Net.In_Lobby then
         Fail ("could not join during the race: " & To_String (Net.Refusal));
         return;
      elsif not Net.Lobby.In_Race then
         Fail ("the race was not on yet: started too soon");
         return;
      elsif not Net.Waiting_For_Next then
         Fail ("joined during the race but not told to wait for the next one");
         return;
      end if;
      Put_Line ("nettest late: in the lobby as player" & Natural'Image (Net.Me) & " during the race");
      declare
         Back : Boolean := False;
      begin
         for Wait in 1 .. 3000 loop
            Net.Poll (0.01);
            if Net.Race_Begun then
               Fail ("was put into the race already on");
               return;
            end if;
            if not Net.Lobby.In_Race then
               Back := True;
               exit;
            end if;
            exit when Net.Joining = Net.Gone;
            delay 0.01;
         end loop;
         if not Back then
            Fail ("never saw the host back in the lobby: " & To_String (Net.Refusal));
            return;
         elsif Net.Back_In_Lobby or else Net.Waiting_For_Next then
            Fail ("treated as back from a race it was not in");
            return;
         end if;
      end;
      Put_Line ("nettest late: the race is over and it is in the lobby, ready for the next");
      Net.Stop;

   elsif Argument_Count >= 2 and then Argument (1) = "join" then
      if Argument (2) = "find" then
         --  asked of the whole network: the game must turn up, once
         Net.Browse;
         for Wait in 1 .. 300 loop
            Net.Poll (0.01);
            exit when Net.N_Found > 0 and then Wait > 250;   --  time for every answer to come
            delay 0.01;
         end loop;
         if Net.N_Found = 0 then
            Fail ("no game was found on the network");
            return;
         elsif Net.N_Found > 1 then
            Fail ("the game was found" & Natural'Image (Net.N_Found) & " times");
            for K in 1 .. Net.N_Found loop
               Put_Line ("   at " & To_String (Net.Found (K).Address));
            end loop;
            return;
         elsif Net.Found (1).Host_Name /= "HOST  " or else Net.Found (1).Track /= 16
           or else Net.Found (1).Players /= 1 or else Net.Found (1).In_Race
         then
            Fail ("the game found is not the one hosted");
            return;
         end if;
         Put_Line ("nettest join: found " & Net.Found (1).Host_Name & "'s game at "
                   & To_String (Net.Found (1).Address));
         Net.Join (To_String (Net.Found (1).Address), "GUEST ");
      else
         Net.Join (Argument (2), "GUEST ");
      end if;
      for Wait in 1 .. 1000 loop
         Net.Poll (0.01);
         exit when Net.Joining /= Net.Asking;
         delay 0.01;
      end loop;
      if Net.Joining /= Net.In_Lobby then
         Fail ("could not join: " & To_String (Net.Refusal));
         return;
      end if;
      Put_Line ("nettest join: in the lobby as player" & Natural'Image (Net.Me));
      for Wait in 1 .. 1000 loop
         Net.Poll (0.01);
         exit when Net.Race_Begun;
         delay 0.01;
      end loop;
      Setup_Net (Net.Lobby.Track, Net.Lobby.Players, Net.Lobby.Names, Net.Lobby.AIs,
                 Net.Lobby.Laps, Net.Lobby.Level, Net.Lobby.Items);
      Local := Net.Me;
      declare
         States : Natural := 0;
         Done : Boolean := False;
      begin
         for Frame in 1 .. 60 * 120 loop
            Net.Poll (Step_Time * 2.0);
            if Net.Since_State = 0.0 then
               States := States + 1;
            end if;
            Net.Send_Keys (Drive (Player (Net.Me)), False);
            delay Step_Time * 2.0;
            if Net.Back_In_Lobby then
               Done := True;
               exit;
            end if;
            exit when Net.Joining = Net.Gone;
         end loop;
         if not Done then
            Fail ("the race did not end with the host back in the lobby");
         elsif not State.Racers (Player (Net.Me)).Finished then
            Fail ("this player's car is not home in the state the host sent");
         else
            Put_Line ("nettest join: home, from" & Natural'Image (States) & " states the host sent");
         end if;
      end;
      Net.Stop;
   else
      Put_Line ("nettest host | nettest join ADDRESS | nettest join find | nettest second");
      Set_Exit_Status (Failure);
   end if;
end Nettest;
