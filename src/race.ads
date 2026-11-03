--  Adamachines: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  A race: the cars, their drivers (people at the keyboard or the AI),
--  laps and places, the camera every player shares, and the duel, where
--  the car left off the screen loses a point to the one in front.
--  What happens is told as events, which the sound, the particles and
--  the HUD read.

with Geom; use Geom;
with Cars;
with Tracks;

package Race is

   Dt : constant := 1.0 / 120.0;

   Max_Cars : constant := 6;
   subtype Car_Index is Positive range 1 .. Max_Cars;

   type Game_Mode is (Single, Double, Duel, Trial);
   --  one player against the AI; two players and the AI; two players head to head;
   --  one player alone against the clock

   type Weapon is (None, Turbo, Shield, Oil, Rocket);
   type Difficulty is (Easy, Normal, Hard);
   type Phase_Kind is (Countdown, Running, Round_Over, Over);

   Duel_Points : constant := 8;   --  a player wins the duel with all of them

   subtype Name_String is String (1 .. 6);

   type Racer is record
      Car       : Cars.Car;
      Human     : Natural := 0;     --  0 for the AI, or the player's number
      Name      : Name_String := "      ";
      Paint     : Natural := 0;
      Index     : Natural := 0;     --  the nearest sample of the road
      Progress  : Integer := 0;     --  samples along the road since the start
      Lap       : Natural := 0;     --  laps done
      Finished  : Boolean := False;
      Finish_T  : Float := 0.0;
      Lap_Start : Float := 0.0;
      Best_Lap  : Float := 0.0;
      Last_Lap  : Float := 0.0;
      Place     : Positive := 1;
      Safe      : Natural := 0;     --  where it is put back after a fall
      Points    : Natural := 0;     --  in a duel
      Holding   : Weapon := None;   --  the pick-up in hand
      Hold_T    : Float := 0.0;     --  how long it has been held
      Shield_T  : Float := 0.0;
      --  The AI
      Lane, Lane_Target : Float := 0.0;
      Lane_T, Stuck_T, Reverse_T, Jam_T : Float := 0.0;
      Pace      : Float := 1.0;
   end record;
   type Racer_Array is array (Car_Index) of Racer;

   type State_Type is record
      Racers   : Racer_Array;
      Count    : Positive := 1;
      Laps     : Positive := 3;
      Mode     : Game_Mode := Single;
      Level    : Difficulty := Normal;
      Phase    : Phase_Kind := Countdown;
      Count_T  : Float := 3.5;      --  seconds left of the countdown
      Time     : Float := 0.0;      --  the race clock
      Clock    : Float := 0.0;      --  seconds since the setup, for the things that move
      Over_T   : Float := 0.0;      --  seconds since the end, or since the round ended
      Attract  : Boolean := False;  --  the race behind the title, all AI
      Items_On : Boolean := True;   --  pick-ups on the track
      Rand     : Seed := 12345;
      Winner   : Natural := 0;      --  of a duel
      Round_Leader : Natural := 0;  --  who won the round just ended
      --  The camera: the middle of the view, and how far the view goes
      Cam, Prev_Cam : Vec;
      View_W, View_H : Float := 1280.0;
   end record;

   State : State_Type;

   type Input is record
      P1, P2 : Cars.Controls;
      Fire1, Fire2 : Boolean := False;   --  use the pick-up, this step
   end record;

   procedure Setup (Id : Tracks.Track_Id; Mode : Game_Mode; Opponents : Natural;
                    Laps : Positive; Level : Difficulty; Attract : Boolean := False;
                    Items : Boolean := True);

   procedure Step (I : Input; Autopilot : Boolean := False);
   --  With the autopilot the AI drives the players' cars too

   function In_Place (K : Positive) return Car_Index;   --  the car in K-th place
   function Player (N : Positive := 1) return Car_Index; --  the player's car
   function Lap_Shown (I : Car_Index) return Positive;   --  the lap it is on
   function Focus return Car_Index;   --  the car the camera follows

   --  The pick-ups: boxes on the road, oil dropped on it, rockets over it
   Max_Boxes : constant := 18;
   type Box is record
      P      : Vec;
      Active : Boolean := False;
      Back_T : Float := 0.0;      --  until it comes back, once taken
   end record;
   Boxes : array (1 .. Max_Boxes) of Box;
   N_Boxes : Natural := 0;

   type Slick is record
      P     : Vec;
      Life  : Float := 0.0;
      Owner : Natural := 0;
   end record;
   Slicks : array (1 .. 16) of Slick;

   type Missile is record
      P             : Vec;
      H             : Float := 0.0;
      Target, Owner : Natural := 0;
      Life, Age     : Float := 0.0;
   end record;
   Rockets : array (1 .. 12) of Missile;

   function Weapon_Name (W : Weapon) return String;

   --  What happened
   type Event_Kind is
     (Bump, Fell, Splash, Jumped, Landed, Boosted, Beep, Go, Lap_Done, Final_Lap,
      Finished, Put_Back, Left_Behind, Point_Won, Duel_Won,
      Picked, Fired, Dropped, Shielded, Exploded, Spun, Scared);
   type Event is record
      Kind : Event_Kind := Beep;
      Car  : Natural := 0;
      P    : Vec;
      Size : Float := 0.0;
   end record;
   Event_Ring : constant := 128;
   type Event_Array is array (0 .. Event_Ring - 1) of Event;
   Events : Event_Array;
   Event_Serial : Natural := 0;   --  events so far; the latest is at (Serial - 1) mod Ring

   function Paint_Count return Positive;

end Race;
