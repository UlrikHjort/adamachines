--  Adamachines: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;

package body Race is

   use Tracks;
   use type Cars.Car;

   AI_Names : constant array (Car_Index) of Name_String :=
     ("ROSIE ", "MAX   ", "JUNO  ", "OTTO  ", "PIP   ", "KAI   ", "LUNA  ", "FINN  ");

   function Paint_Count return Positive is (8);

   function Weapon_Name (W : Weapon) return String is
     (case W is
         when None => "",
         when Turbo => "TURBO",
         when Shield => "SHIELD",
         when Oil =>
           (case Tracks.Theme is
               when Tracks.Alien => "SLIME",
               when Tracks.Bath | Tracks.Fish_Tank => "SOAP",
               when others => "OIL"),
         when Rocket => "ROCKET");

   procedure Add_Event (E : Event) is
   begin
      Events (Event_Serial mod Event_Ring) := E;
      Event_Serial := Event_Serial + 1;
   end Add_Event;

   procedure Tell (K : Event_Kind; Car : Natural := 0; P : Vec := Zero; Size : Float := 0.0) is
   begin
      Events (Event_Serial mod Event_Ring) := (K, Car, P, Size);
      Event_Serial := Event_Serial + 1;
   end Tell;

   function N return Positive is (Tracks.Count);

   function Wrapped (D : Integer) return Integer is
      R : Integer := D mod N;
   begin
      if R > N / 2 then
         R := R - N;
      end if;
      return R;
   end Wrapped;

   function Player (N : Positive := 1) return Car_Index is
   begin
      for I in 1 .. State.Count loop
         if State.Racers (I).Human = N then
            return I;
         end if;
      end loop;
      return 1;
   end Player;

   function Lap_Shown (I : Car_Index) return Positive is
     (Positive'Min (State.Laps, State.Racers (I).Lap + 1));

   function Score (I : Car_Index) return Float is
      R : Racer renames State.Racers (I);
   begin
      if R.Finished then
         return 1.0E9 - R.Finish_T * 100.0;
      end if;
      return Float (R.Progress);
   end Score;

   Order : array (1 .. Max_Cars) of Car_Index := (1, 2, 3, 4, 5, 6, 7, 8);

   function In_Place (K : Positive) return Car_Index is (Order (K));

   procedure Sort_Places is
   begin
      for I in 1 .. State.Count loop
         Order (I) := I;
      end loop;
      for I in 2 .. State.Count loop
         for J in reverse 2 .. I loop
            exit when Score (Order (J - 1)) >= Score (Order (J));
            declare
               T : constant Car_Index := Order (J);
            begin
               Order (J) := Order (J - 1);
               Order (J - 1) := T;
            end;
         end loop;
      end loop;
      for K in 1 .. State.Count loop
         State.Racers (Order (K)).Place := K;
      end loop;
   end Sort_Places;

   --  The human out in front, or the leader of the race
   function Focus return Car_Index is
   begin
      if State.Attract then
         return Order (1);
      end if;
      case State.Mode is
         when Single | Trial =>
            return Player (1);
         when Net =>
            return Player (Local);
         when Double | Duel =>
            declare
               A : constant Car_Index := Player (1);
               B : constant Car_Index := Player (2);
            begin
               return (if Score (B) > Score (A) then B else A);
            end;
      end case;
   end Focus;

   ---------------------------------------------------------------------------
   --  Putting cars on the road
   ---------------------------------------------------------------------------

   function Clear_Sample (K : Integer) return Integer is
      --  A sample at or behind K with road all across, and not just before a ramp
      J : Integer := K;
   begin
      for Tries in 1 .. 80 loop
         declare
            S : constant Sample := Get (J);
            Ok : Boolean := Material_At (S.P) = Road
              and then Material_At (S.P + Perp (S.T) * (0.3 * S.Width)) = Road
              and then Material_At (S.P - Perp (S.T) * (0.3 * S.Width)) = Road;
         begin
            if Ok then
               for A in 1 .. 16 loop
                  if Material_At (Get (J + A).P) in Ramp | Void then
                     Ok := False;
                  end if;
               end loop;
            end if;
            exit when Ok;
         end;
         J := J - 2;
      end loop;
      return J;
   end Clear_Sample;

   procedure Put_At (I : Car_Index; K : Integer; Lat : Float; Speed : Float) is
      R : Racer renames State.Racers (I);
      S : constant Sample := Get (K);
      P : Vec := S.P + Perp (S.T) * (Lat * S.Width * 0.5);
      Old : constant Natural := R.Index;
   begin
      --  Not on top of another car
      for Tries in 1 .. 3 loop
         declare
            Near : Boolean := False;
         begin
            for J in 1 .. State.Count loop
               if J /= I and then Distance (State.Racers (J).Car.P, P) < 20.0 then
                  Near := True;
               end if;
            end loop;
            exit when not Near;
            P := P + Perp (S.T) * (if Lat > 0.0 then -16.0 else 16.0);
         end;
      end loop;
      Cars.Place (R.Car, P, Angle_Of (S.T), Speed);
      R.Car.Ghost_T := 1.5;
      R.Index := K mod N;
      R.Progress := R.Progress + Wrapped (R.Index - Old);
      R.Safe := R.Index;
      R.Stuck_T := 0.0;
      R.Reverse_T := 0.0;
      R.Jam_T := 0.0;
   end Put_At;

   procedure Put_Back (I : Car_Index) is
      R : Racer renames State.Racers (I);
   begin
      Put_At (I, Clear_Sample (R.Safe - 3), 0.0, 60.0);
      Tell (Put_Back, I, R.Car.P);
   end Put_Back;

   ---------------------------------------------------------------------------
   --  Setting up
   ---------------------------------------------------------------------------

   procedure Reset_Camera is
      F : constant Car_Index := Focus;
   begin
      State.Cam := State.Racers (F).Car.P;
      State.Prev_Cam := State.Cam;
   end Reset_Camera;

   --  Three rows of boxes round the lap, each where the road is clear across
   procedure Place_Boxes is
   begin
      N_Boxes := 0;
      if not State.Items_On then
         return;
      end if;
      for Row in 1 .. 3 loop
         declare
            K : Integer := N * (2 * Row - 1) / 6 + N / 12;
            Found : Boolean := False;
         begin
            for Tries in 1 .. 120 loop
               declare
                  S : constant Sample := Get (K);
                  Ok : Boolean := abs S.Turn < 0.004;
               begin
                  for D in -10 .. 10 loop
                     for L in -1 .. 1 loop
                        declare
                           Q : constant Sample := Get (K + D);
                        begin
                           if Material_At (Q.P + Perp (Q.T) * (Float (L) * 0.42 * Q.Width)) /= Road then
                              Ok := False;
                           end if;
                        end;
                     end loop;
                  end loop;
                  if Ok then
                     Found := True;
                     exit;
                  end if;
               end;
               K := K + 3;
            end loop;
            if Found then
               for L in -1 .. 1 loop
                  declare
                     S : constant Sample := Get (K);
                  begin
                     N_Boxes := N_Boxes + 1;
                     Boxes (N_Boxes) := (S.P + Perp (S.T) * (Float (L) * 0.3 * S.Width), True, 0.0);
                  end;
               end loop;
            end if;
         end;
      end loop;
   end Place_Boxes;

   procedure Setup (Id : Tracks.Track_Id; Mode : Game_Mode; Opponents : Natural;
                    Laps : Positive; Level : Difficulty; Attract : Boolean := False;
                    Items : Boolean := True)
   is
      Humans : constant Natural := (if Attract then 0 elsif Mode in Single | Trial then 1 else 2);
      AIs : constant Natural :=
        (if Attract then 5
         elsif Mode in Duel | Trial then 0
         else Natural'Min (Opponents, Max_Cars - Humans));
      Base : constant Float :=
        (case Level is when Easy => 0.83, when Normal => 0.91, when Hard => 0.985);
      View_W : constant Float := State.View_W;
      View_H : constant Float := State.View_H;
   begin
      Tracks.Load (Id);
      State := (Count => Humans + AIs, Laps => (if Attract then 99 elsif Mode = Duel then 99 else Laps),
                Mode => Mode, Level => Level, Attract => Attract,
                View_W => View_W, View_H => View_H,
                Items_On => Items and then Mode /= Trial, others => <>);
      Place_Boxes;
      for S of Slicks loop
         S.Life := 0.0;
      end loop;
      for R of Rockets loop
         R.Life := 0.0;
      end loop;
      for I in 1 .. State.Count loop
         declare
            R : Racer renames State.Racers (I);
            --  The AI in front, the players at the back of the grid
            Slot : constant Positive := I;
            P : Vec;
            H : Float;
         begin
            R := (others => <>);
            if I > AIs then
               R.Human := I - AIs;
               R.Name := (if R.Human = 1 then "P1    " else "P2    ");
               R.Paint := R.Human - 1;
            else
               R.Name := AI_Names (I);
               R.Paint := I + 1;
               R.Pace := Base * (1.0 - 0.018 * Float (I - 1));
               R.Lane := 0.0;
            end if;
            Tracks.Grid_Slot (Slot, P, H);
            Cars.Place (R.Car, P, H);
            R.Car.Top_Factor := (if R.Human > 0 then 1.0 else R.Pace);
            R.Index := Tracks.Nearest (P);
            R.Progress := (if R.Index > N / 2 then R.Index - N else R.Index);
            R.Safe := R.Index;
            if Mode = Duel then
               R.Points := Duel_Points / 2;
            end if;
         end;
      end loop;
      State.Phase := Countdown;
      State.Count_T := (if Attract then 0.01 else 3.5);
      Sort_Places;
      Reset_Camera;
   end Setup;

   procedure Setup_Net (Id : Tracks.Track_Id; Players : Positive; Names : Name_List; AIs : Natural;
                        Laps : Positive; Level : Difficulty; Items : Boolean)
   is
      Count : constant Positive := Positive'Min (Max_Cars, Players + AIs);
      Robots : constant Natural := Count - Players;
   begin
      --  As a race of one player, then the places given to the players and the AI
      Setup (Id, Single, Robots, Laps, Level, Items => Items);
      State.Mode := Net;
      if State.Count /= Count then
         --  more players than a single race has: the grid filled again
         State.Count := Count;
      end if;
      for I in 1 .. Count loop
         declare
            R : Racer renames State.Racers (I);
            P : Vec;
            H : Float;
         begin
            R := (others => <>);
            if I > Robots then
               R.Human := I - Robots;
               R.Name := Names (R.Human);
               R.Paint := (R.Human - 1) mod Paint_Count;
               R.Pace := 1.0;
            else
               R.Name := AI_Names (I);
               R.Paint := (Players + I - 1) mod Paint_Count;
               R.Pace :=
                 (case Level is when Easy => 0.83, when Normal => 0.91, when Hard => 0.985)
                 * (1.0 - 0.018 * Float (I - 1));
            end if;
            Tracks.Grid_Slot (I, P, H);
            Cars.Place (R.Car, P, H);
            R.Car.Top_Factor := (if R.Human > 0 then 1.0 else R.Pace);
            R.Index := Tracks.Nearest (P);
            R.Progress := (if R.Index > N / 2 then R.Index - N else R.Index);
            R.Safe := R.Index;
         end;
      end loop;
      Sort_Places;
      Reset_Camera;
   end Setup_Net;

   ---------------------------------------------------------------------------
   --  The AI
   ---------------------------------------------------------------------------

   function Bad (M : Material) return Float is
     (case M is
         when Void | Solid => 30.0,
         when Floor => 8.0,
         when Sand => 6.0,
         when Water => (if Tracks.Vehicle = Hovercraft then 0.0 else 4.0),
         when Boost => -2.0,
         when Bump => (if Tracks.Vehicle = Monster_Truck then 2.0 else 30.0),
         when Road | Ramp => 0.0);

   procedure Choose_Lane (I : Car_Index) is
      R : Racer renames State.Racers (I);
      Best : Float := Float'Last;
      Lanes : constant array (1 .. 5) of Float := (-0.6, -0.3, 0.0, 0.3, 0.6);
   begin
      for L of Lanes loop
         declare
            Cost : Float := abs (L - R.Lane) * 1.5 + abs L * 0.5;
            Bend : Float := 0.0;
         begin
            for J in 2 .. 12 loop
               declare
                  S : constant Sample := Get (R.Index + J * 3);
               begin
                  Cost := Cost + Bad (Material_At (S.P + Perp (S.T) * (L * S.Width * 0.5)));
                  Bend := Bend + S.Turn;
               end;
            end loop;
            --  The inside of the bend ahead
            Cost := Cost - L * Clamp (Bend * 25.0, -3.0, 3.0);
            --  Out of the way of the things that move across
            for M in 1 .. Tracks.Mover_Count loop
               declare
                  P : Vec;
                  H, Lift : Float;
                  Seen : Boolean;
               begin
                  Tracks.Mover_At (Tracks.Get_Mover (M), State.Clock + 0.5, P, H, Seen, Lift);
                  if Seen then
                     for J in 2 .. 8 loop
                        declare
                           S : constant Sample := Get (R.Index + J * 3);
                        begin
                           if Distance (S.P + Perp (S.T) * (L * S.Width * 0.5), P)
                             < Tracks.Get_Mover (M).Radius + 22.0
                           then
                              Cost := Cost + 12.0;
                           end if;
                        end;
                     end loop;
                  end if;
               end;
            end loop;
            --  Room past the cars ahead
            for J in 1 .. State.Count loop
               if J /= I then
                  declare
                     O : Cars.Car renames State.Racers (J).Car;
                     D : constant Vec := O.P - R.Car.P;
                     Ahead : constant Float := Dot (D, Dir (R.Car.H));
                  begin
                     if Ahead > 0.0 and then Ahead < 110.0 then
                        declare
                           S : constant Sample := Get (R.Index);
                           OL : constant Float := Dot (O.P - S.P, Perp (S.T)) / (S.Width * 0.5);
                        begin
                           if abs (OL - L) < 0.4 then
                              Cost := Cost + 5.0 * (1.0 - Ahead / 110.0) + 1.0;
                           end if;
                        end;
                     end if;
                  end;
               end if;
            end loop;
            if Cost < Best then
               Best := Cost;
               R.Lane_Target := L;
            end if;
         end;
      end loop;
   end Choose_Lane;

   function AI_Drive (I : Car_Index; Pace : Float) return Cars.Controls is
      R : Racer renames State.Racers (I);
      C : Cars.Car renames R.Car;
      Out_C : Cars.Controls;
      V : constant Float := C.Forward;
      Look : constant Integer := 4 + Integer (Float'Max (0.0, V) / 24.0);
      T : constant Sample := Get (R.Index + Look);
      Target : constant Vec := T.P + Perp (T.T) * (R.Lane * T.Width * 0.5);
      Err : constant Float := Wrap (Angle_Of (Target - C.P) - C.H);
      Grip : constant Float := Cars.Road_Grip * 0.8;
      Want : Float := Cars.Top_Speed * Pace;
   begin
      R.Lane_T := R.Lane_T - Dt;
      if R.Lane_T <= 0.0 then
         R.Lane_T := 0.2;
         Choose_Lane (I);
      end if;
      R.Lane := R.Lane + Clamp (R.Lane_Target - R.Lane, -1.3 * Dt, 1.3 * Dt);

      --  As fast as the bends ahead allow, braking in time for them
      for J in 1 .. 44 loop
         declare
            K : constant Float := abs Get (R.Index + J).Turn + 1.0E-4;
            Allowed : constant Float :=
              Float'Min (Sqrt (Grip / K), 3.2 / (K + 0.0032));
            D : constant Float := Float (J) * Tracks.Spacing;
         begin
            Want := Float'Min (Want, Sqrt (Allowed * Allowed + 2.0 * 520.0 * D));
         end;
      end loop;

      Out_C.Steer := Clamp (Err * 3.2, -1.0, 1.0);
      if V > Want + 12.0 then
         Out_C.Brake := Clamp ((V - Want) / 40.0, 0.3, 1.0);
      elsif V > Want then
         Out_C.Throttle := 0.3;
      else
         Out_C.Throttle := 1.0;
      end if;

      --  Stuck against something: back off and try again
      if State.Phase = Running and then abs V < 20.0 then
         R.Stuck_T := R.Stuck_T + Dt;
         R.Jam_T := R.Jam_T + Dt;
      else
         R.Stuck_T := 0.0;
         R.Jam_T := Float'Max (0.0, R.Jam_T - Dt * 0.5);
      end if;
      if R.Stuck_T > 0.8 and then R.Reverse_T <= 0.0 then
         R.Reverse_T := 0.7;
         R.Stuck_T := 0.0;
      end if;
      if R.Reverse_T > 0.0 then
         R.Reverse_T := R.Reverse_T - Dt;
         Out_C := (Steer => (if Err > 0.0 then -1.0 else 1.0), Throttle => 0.0, Brake => 1.0);
      end if;
      return Out_C;
   end AI_Drive;

   ---------------------------------------------------------------------------
   --  The pick-ups
   ---------------------------------------------------------------------------

   function Rnd return Float is (Random (State.Rand));

   function Deal (I : Car_Index) return Weapon is
      --  The further back, the likelier a rocket or a turbo
      F : constant Float :=
        (if State.Count > 1 then Float (State.Racers (I).Place - 1) / Float (State.Count - 1) else 0.5);
      W : constant array (Weapon range Turbo .. Rocket) of Float :=
        (1.0 + F, 1.0, 1.6 - F, 0.4 + 1.6 * F);
      Sum : Float := 0.0;
      X : Float;
   begin
      for V of W loop
         Sum := Sum + V;
      end loop;
      X := Rnd * Sum;
      for K in W'Range loop
         if X < W (K) then
            return K;
         end if;
         X := X - W (K);
      end loop;
      return Rocket;
   end Deal;

   --  The car to aim at: the nearest one in front, in the race and before the nose
   function Aim (I : Car_Index) return Natural is
      C : Cars.Car renames State.Racers (I).Car;
      Best : Natural := 0;
      Best_D : Float := 800.0;
   begin
      for J in 1 .. State.Count loop
         if J /= I and then not Cars.Falling (State.Racers (J).Car) then
            declare
               D : constant Vec := State.Racers (J).Car.P - C.P;
               L : constant Float := Length (D);
            begin
               if L < Best_D and then L > 1.0 and then Dot (D / L, Dir (C.H)) > 0.5 then
                  Best_D := L;
                  Best := J;
               end if;
            end;
         end if;
      end loop;
      return Best;
   end Aim;

   procedure Use_Weapon (I : Car_Index) is
      R : Racer renames State.Racers (I);
      C : Cars.Car renames R.Car;
      F : constant Vec := Dir (C.H);
   begin
      if R.Holding = None or else Cars.Falling (C) or else State.Phase /= Running then
         return;
      end if;
      case R.Holding is
         when None => null;
         when Turbo =>
            C.Boost_T := 1.4;
            Tell (Boosted, I, C.P);
         when Shield =>
            R.Shield_T := 6.0;
            Tell (Shielded, I, C.P);
         when Oil =>
            declare
               Oldest : Positive := 1;
            begin
               for K in Slicks'Range loop
                  if Slicks (K).Life < Slicks (Oldest).Life then
                     Oldest := K;
                  end if;
               end loop;
               Slicks (Oldest) := (C.P - F * 20.0, 25.0, I);
               Tell (Dropped, I, Slicks (Oldest).P);
            end;
         when Rocket =>
            for K in Rockets'Range loop
               if Rockets (K).Life <= 0.0 then
                  Rockets (K) := (C.P + F * 16.0, C.H, Aim (I), I, 2.6, 0.0);
                  Tell (Fired, I, C.P);
                  exit;
               end if;
            end loop;
      end case;
      R.Holding := None;
      R.Hold_T := 0.0;
   end Use_Weapon;

   procedure Knock (J : Car_Index; By : Natural; P : Vec) is
      T : Racer renames State.Racers (J);
   begin
      Tell (Exploded, J, P);
      if T.Shield_T > 0.0 or else Cars.Falling (T.Car) then
         return;
      end if;
      T.Car.Spin_T := 1.0;
      T.Car.V := T.Car.V * 0.35;
      Tell (Spun, J, T.Car.P, Float (By));
   end Knock;

   procedure AI_Items (I : Car_Index) is
      R : Racer renames State.Racers (I);
      C : Cars.Car renames R.Car;
      Go : Boolean := False;
   begin
      if R.Holding = None then
         return;
      end if;
      R.Hold_T := R.Hold_T + Dt;
      if R.Hold_T < 0.6 then
         return;   --  a moment to think
      end if;
      case R.Holding is
         when None => null;
         when Turbo =>
            declare
               Bend : Float := 0.0;
            begin
               for J in 2 .. 40 loop
                  Bend := Float'Max (Bend, abs Get (R.Index + J).Turn);
               end loop;
               Go := Bend < 0.0025;
            end;
         when Shield =>
            Go := R.Hold_T > 7.0;
            for K of Rockets loop
               if K.Life > 0.0 and then K.Target = I and then Distance (K.P, C.P) < 200.0 then
                  Go := True;
               end if;
            end loop;
         when Oil =>
            for J in 1 .. State.Count loop
               if J /= I then
                  declare
                     D : constant Vec := State.Racers (J).Car.P - C.P;
                  begin
                     if Length (D) < 140.0 and then Dot (D, Dir (C.H)) < 0.0 then
                        Go := True;
                     end if;
                  end;
               end if;
            end loop;
            Go := Go or else R.Hold_T > 12.0;
         when Rocket =>
            Go := Aim (I) /= 0 or else R.Hold_T > 15.0;
      end case;
      if Go then
         Use_Weapon (I);
      end if;
   end AI_Items;

   procedure Update_Items is
   begin
      --  Boxes: driven through, they are taken, and come back a little later
      for B of Boxes (1 .. N_Boxes) loop
         if B.Active then
            for I in 1 .. State.Count loop
               declare
                  R : Racer renames State.Racers (I);
               begin
                  if B.Active and then not R.Car.Air and then not Cars.Falling (R.Car)
                    and then Distance (R.Car.P, B.P) < 15.0
                  then
                     B.Active := False;
                     B.Back_T := 4.0;
                     if R.Holding = None then
                        R.Holding := Deal (I);
                        R.Hold_T := 0.0;
                        Tell (Picked, I, B.P, Float (Weapon'Pos (R.Holding)));
                     end if;
                  end if;
               end;
            end loop;
         else
            B.Back_T := B.Back_T - Dt;
            if B.Back_T <= 0.0 then
               B.Active := True;
            end if;
         end if;
      end loop;

      --  Oil
      for S of Slicks loop
         if S.Life > 0.0 then
            S.Life := S.Life - Dt;
            for I in 1 .. State.Count loop
               declare
                  R : Racer renames State.Racers (I);
               begin
                  if Distance (R.Car.P, S.P) < 16.0 and then not R.Car.Air
                    and then R.Car.Slick_T <= 0.0 and then R.Shield_T <= 0.0
                    and then (I /= S.Owner or else S.Life < 24.0)
                  then
                     R.Car.Slick_T := 1.1;
                     Tell (Spun, I, R.Car.P, 0.0);
                  end if;
               end;
            end loop;
         end if;
      end loop;

      --  Rockets: they turn after their target, and burst on whatever they meet
      for M of Rockets loop
         if M.Life > 0.0 then
            M.Life := M.Life - Dt;
            M.Age := M.Age + Dt;
            if M.Target in 1 .. State.Count then
               declare
                  Want : constant Float := Angle_Of (State.Racers (M.Target).Car.P - M.P);
               begin
                  M.H := M.H + Clamp (Wrap (Want - M.H), -4.0 * Dt, 4.0 * Dt);
               end;
            end if;
            M.P := M.P + Dir (M.H) * (520.0 * Dt);
            declare
               Hit : Boolean := False;
            begin
               for J in 1 .. State.Count loop
                  if not Hit and then (J /= M.Owner or else M.Age > 0.4)
                    and then Distance (State.Racers (J).Car.P, M.P) < 14.0
                  then
                     Knock (J, M.Owner, M.P);
                     Hit := True;
                  end if;
               end loop;
               if not Hit and then (Material_At (M.P) = Solid or else M.Life <= 0.0) then
                  Tell (Exploded, 0, M.P);
                  Hit := True;
               end if;
               if Hit then
                  M.Life := 0.0;
               end if;
            end;
         end if;
      end loop;

      for I in 1 .. State.Count loop
         State.Racers (I).Shield_T := Float'Max (0.0, State.Racers (I).Shield_T - Dt);
      end loop;
   end Update_Items;

   ---------------------------------------------------------------------------
   --  The step
   ---------------------------------------------------------------------------

   procedure Follow_Camera (Seconds : Float) is
      F : constant Car_Index := Focus;
      C : Cars.Car renames State.Racers (F).Car;
      Lead : Vec := C.V * 0.32;
      Max_Lead : constant Float := 0.28 * Float'Min (State.View_W, State.View_H);
      Margin_X : constant Float := State.View_W * 0.5 - 70.0;
      Margin_Y : constant Float := State.View_H * 0.5 - 70.0;
      D : Vec;
   begin
      State.Prev_Cam := State.Cam;
      if Length (Lead) > Max_Lead then
         Lead := Normal (Lead) * Max_Lead;
      end if;
      if Cars.Falling (C) then
         return;
      end if;
      State.Cam := State.Cam + (C.P + Lead - State.Cam) * Float'Min (1.0, 3.2 * Seconds);
      D := C.P - State.Cam;
      State.Cam.X := State.Cam.X + (D.X - Clamp (D.X, -Margin_X, Margin_X));
      State.Cam.Y := State.Cam.Y + (D.Y - Clamp (D.Y, -Margin_Y, Margin_Y));
   end Follow_Camera;

   procedure Follow is
   begin
      Follow_Camera (Dt);
   end Follow;

   function Off_Screen (I : Car_Index) return Boolean is
      D : constant Vec := State.Racers (I).Car.P - State.Cam;
   begin
      return abs D.X > State.View_W * 0.5 + 6.0 or else abs D.Y > State.View_H * 0.5 + 6.0;
   end Off_Screen;

   procedure Side_By_Side (K : Integer) is
      A : constant Car_Index := Player (1);
      B : constant Car_Index := Player (2);
      J : constant Integer := Clear_Sample (K);
   begin
      Put_At (A, J, -0.4, 0.0);
      Put_At (B, J, 0.4, 0.0);
      State.Racers (A).Car.Ghost_T := 0.0;
      State.Racers (B).Car.Ghost_T := 0.0;
   end Side_By_Side;

   procedure Check_Behind is
      F : constant Car_Index := Focus;
      O : constant Car_Index := (if F = Player (1) then Player (2) else Player (1));
   begin
      if State.Phase /= Running or else not Off_Screen (O) then
         return;
      end if;
      case State.Mode is
         when Single | Trial | Net => null;
         when Double =>
            if not State.Racers (O).Finished then
               Put_At (O, Clear_Sample (State.Racers (F).Index - 6), 0.4,
                       Float'Min (State.Racers (F).Car.Speed, 120.0));
               Tell (Left_Behind, O, State.Racers (O).Car.P);
            end if;
         when Duel =>
            State.Racers (F).Points := State.Racers (F).Points + 1;
            State.Racers (O).Points := State.Racers (O).Points - 1;
            State.Round_Leader := F;
            Tell (Point_Won, F, State.Racers (F).Car.P);
            State.Over_T := 0.0;
            if State.Racers (O).Points = 0 then
               State.Winner := F;
               State.Phase := Over;
               Tell (Duel_Won, F, State.Racers (F).Car.P);
            else
               State.Phase := Round_Over;
            end if;
      end case;
   end Check_Behind;

   procedure Step (I : Input; Autopilot : Boolean := False) is
      Moving : constant Boolean := State.Phase in Running | Over;
   begin
      --  The lights
      if State.Phase = Countdown then
         declare
            Before : constant Float := State.Count_T;
         begin
            State.Count_T := State.Count_T - Dt;
            if Float'Floor (Before) > Float'Floor (State.Count_T) and then State.Count_T > 0.0
              and then Float'Floor (Before) <= 3.0
            then
               Tell (Beep);
            end if;
            if State.Count_T <= 0.0 then
               State.Phase := Running;
               Tell (Go);
               for K in 1 .. State.Count loop
                  State.Racers (K).Lap_Start := State.Time;
               end loop;
            end if;
         end;
      elsif State.Phase = Running then
         State.Time := State.Time + Dt;
      else
         State.Over_T := State.Over_T + Dt;
         if State.Phase = Over then
            State.Time := State.Time + Dt;
         end if;
         if State.Phase = Round_Over and then State.Over_T > 1.6 then
            Side_By_Side (State.Racers (State.Round_Leader).Index);
            State.Phase := Countdown;
            State.Count_T := 1.99;
         end if;
      end if;

      --  The drivers
      for K in 1 .. State.Count loop
         declare
            R : Racer renames State.Racers (K);
            Ctl : Cars.Controls;
         begin
            if R.Human = 0 or else Autopilot or else R.Finished or else R.Lost
              or else (State.Phase = Over and then State.Mode /= Duel)
            then
               Ctl := AI_Drive (K, (if R.Finished then 0.75
                                    elsif R.Human > 0 then 0.95
                                    else R.Pace));
            elsif State.Mode = Net then
               Ctl := I.Keys (R.Human);
            elsif R.Human = 1 then
               Ctl := I.P1;
            else
               Ctl := I.P2;
            end if;
            if not Moving then
               --  held on the line, or stopped between the rounds of a duel
               Ctl := (Steer => Ctl.Steer, Throttle => 0.0, Brake => 0.0);
               R.Car.Held := True;
               R.Car.V := R.Car.V * (1.0 - Float'Min (1.0, 6.0 * Dt));
            else
               R.Car.Held := False;
            end if;
            Cars.Step (R.Car, Ctl, Dt);
         end;
      end loop;
      for A in 1 .. State.Count loop
         for B in A + 1 .. State.Count loop
            Cars.Collide (State.Racers (A).Car, State.Racers (B).Car);
         end loop;
      end loop;

      --  The things that move across the road knock the cars aside
      State.Clock := State.Clock + Dt;
      for M in 1 .. Tracks.Mover_Count loop
         declare
            Mv : constant Tracks.Mover := Tracks.Get_Mover (M);
            P, P2 : Vec;
            H, H2, Lift : Float;
            Seen, Seen2 : Boolean;
         begin
            Tracks.Mover_At (Mv, State.Clock, P, H, Seen, Lift);
            Tracks.Mover_At (Mv, State.Clock - Dt, P2, H2, Seen2, Lift);
            if Mv.Kind = Tracks.Sleigh and then Seen and then not Seen2 then
               Tell (Bells, 0, P);   --  here comes Santa
            end if;
            if Seen then
               declare
                  Mv_V : constant Vec := (if Seen2 then (P - P2) / Dt else Zero);
               begin
                  for K in 1 .. State.Count loop
                     declare
                        C : Cars.Car renames State.Racers (K).Car;
                        D : constant Vec := C.P - P;
                        N : Vec := Zero;
                        Over : Float := 0.0;
                     begin
                        if C.Air or else Cars.Falling (C) or else C.Ghost_T > 0.0 then
                           null;
                        elsif Mv.Kind = Tracks.Ghost then
                           --  no knock: a fright, that throws the car off its line
                           if Length (D) < 58.0 and then C.Scare_T <= 0.0
                             and then State.Racers (K).Shield_T <= 0.0
                           then
                              C.V := C.V + Normal (D) * 230.0;
                              C.Slick_T := Float'Max (C.Slick_T, 0.8);
                              C.Scare_T := 2.0;
                              Tell (Scared, K, P);
                           end if;
                        elsif Mv.Kind in Tracks.Train | Tracks.Sleigh then
                           declare
                              U : constant Vec := Dir (H);
                              LX : constant Float := Dot (D, U);
                              LY : constant Float := Dot (D, Perp (U));
                              EX : constant Float := Tracks.Train_Length * 0.5 + 8.0 - abs LX;
                              EY : constant Float := Mv.Radius + 8.0 - abs LY;
                           begin
                              if EX > 0.0 and then EY > 0.0 then
                                 if EY < EX then
                                    N := Perp (U) * (if LY < 0.0 then -1.0 else 1.0);
                                    Over := EY;
                                 else
                                    N := U * (if LX < 0.0 then -1.0 else 1.0);
                                    Over := EX;
                                 end if;
                              end if;
                           end;
                        elsif Length (D) < Mv.Radius + 10.0 then
                           N := Normal (D);
                           Over := Mv.Radius + 10.0 - Length (D);
                        end if;
                        if Over > 0.0 and then N /= Zero then
                           C.P := C.P + N * Over;
                           declare
                              Vn : constant Float := Dot (C.V - Mv_V, N);
                           begin
                              if Vn < 0.0 then
                                 C.V := C.V - N * (1.5 * Vn);
                                 if -Vn > 40.0 then
                                    Tell (Bump, K, C.P - N * 10.0, -Vn);
                                 end if;
                              end if;
                           end;
                        end if;
                     end;
                  end loop;
               end;
            end if;
         end;
      end loop;

      --  The pick-ups
      if State.Items_On then
         for K in 1 .. State.Count loop
            declare
               R : Racer renames State.Racers (K);
            begin
               if R.Human = 0 or else Autopilot or else R.Finished or else R.Lost then
                  AI_Items (K);
               elsif (State.Mode = Net and then I.Fires (R.Human))
                 or else (State.Mode /= Net
                          and then ((R.Human = 1 and then I.Fire1) or else (R.Human = 2 and then I.Fire2)))
               then
                  Use_Weapon (K);
               end if;
            end;
         end loop;
         Update_Items;
      end if;

      --  Along the road
      for K in 1 .. State.Count loop
         declare
            R : Racer renames State.Racers (K);
            C : Cars.Car renames R.Car;
            New_Index : constant Natural := Tracks.Nearest (C.P, R.Index);
         begin
            if not Cars.Falling (C) then
               R.Progress := R.Progress + Wrapped (New_Index - R.Index);
               R.Index := New_Index;
               if not C.Air and then C.Under = Road and then Material_At (Get (R.Index).P) = Road then
                  R.Safe := R.Index;
               end if;
            end if;
            if R.Progress >= (R.Lap + 1) * N and then not R.Finished and then State.Phase in Running | Over then
               R.Lap := R.Lap + 1;
               R.Last_Lap := State.Time - R.Lap_Start;
               R.Lap_Start := State.Time;
               if R.Best_Lap = 0.0 or else R.Last_Lap < R.Best_Lap then
                  R.Best_Lap := R.Last_Lap;
               end if;
               if R.Lap >= State.Laps then
                  R.Finished := True;
                  R.Finish_T := State.Time;
                  Tell (Finished, K, C.P);
               else
                  Tell (Lap_Done, K, C.P);
                  if R.Lap = State.Laps - 1 then
                     Tell (Final_Lap, K, C.P);
                  end if;
               end if;
            end if;

            --  What the car did
            if C.Bump > 25.0 then
               Tell (Bump, K, C.Bump_At, C.Bump);
            end if;
            if C.Fell then
               Tell (Fell, K, C.P);
            end if;
            if C.Jumped then
               Tell (Jumped, K, C.P, C.Speed);
            end if;
            if C.Landed then
               Tell (Landed, K, C.P, C.Speed);
            end if;
            if C.Boosted then
               Tell (Boosted, K, C.P);
            end if;
            if C.Splashed and then (Event_Serial mod 7 = 0) then
               Tell (Splash, K, C.P, C.Speed);
            end if;
            if Cars.Fallen (C) or else R.Jam_T > 5.0 then
               Put_Back (K);
            end if;
         end;
      end loop;

      Sort_Places;

      --  The end of a race
      if State.Phase = Running and then State.Mode /= Duel and then not State.Attract then
         declare
            All_In : Boolean := True;
         begin
            for K in 1 .. State.Count loop
               if State.Racers (K).Human > 0 and then not State.Racers (K).Finished then
                  All_In := False;
               end if;
            end loop;
            if All_In then
               State.Phase := Over;
               State.Over_T := 0.0;
            end if;
         end;
      end if;

      Follow;
      if not State.Attract and then State.Mode in Double | Duel then
         Check_Behind;
      end if;
   end Step;

end Race;
