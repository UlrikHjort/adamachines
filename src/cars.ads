--  Adamachines: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  A car seen from above: where it is, where it points, how it slides.
--  The grip and drag come from what is under it, so the same car grips
--  a road on the workbench and skates on the frozen pond.

with Geom; use Geom;
with Tracks;

package Cars is

   Car_Length : constant := 24.0;
   Car_Width  : constant := 12.0;
   Top_Speed  : constant := 320.0;      --  units a second, on the road

   type Controls is record
      Steer    : Float := 0.0;          --  -1 left .. 1 right
      Throttle : Float := 0.0;          --  0 .. 1
      Brake    : Float := 0.0;          --  0 .. 1, and reverse when stopped
   end record;

   type Car is record
      P, V      : Vec;
      H         : Float := 0.0;         --  heading
      Prev_P    : Vec;                  --  a step ago, to draw between steps
      Prev_H    : Float := 0.0;
      Steer_S   : Float := 0.0;         --  the wheels' turn, eased towards the input
      Speed     : Float := 0.0;
      Forward   : Float := 0.0;         --  speed along the heading
      Z, Vz     : Float := 0.0;         --  height, in the air
      Air       : Boolean := False;
      Fall_T    : Float := 0.0;         --  over the edge: seconds falling
      Ghost_T   : Float := 0.0;         --  just put back: no knocks for a while
      Boost_T   : Float := 0.0;
      Slip      : Float := 0.0;         --  0 .. 1: how much it slides
      Under     : Tracks.Material := Tracks.Road;
      Top_Factor : Float := 1.0;        --  the AI's pace
      Held      : Boolean := False;     --  on the line, waiting for the lights
      Slick_T   : Float := 0.0;         --  on oil: no grip for a while
      Spin_T    : Float := 0.0;         --  hit: spinning, out of control
      Scare_T   : Float := 0.0;         --  just scared by a ghost: not again for a moment
      --  What happened in the last step
      Bump      : Float := 0.0;         --  the hardest knock, in units a second
      Bump_At   : Vec;
      Fell, Jumped, Landed, Boosted, Splashed : Boolean := False;
   end record;

   procedure Place (C : in out Car; P : Vec; Heading : Float; Speed : Float := 0.0);

   procedure Step (C : in out Car; Given : Controls; Dt : Float);

   procedure Collide (A, B : in out Car);
   --  Two cars pushed apart when they touch

   function Falling (C : Car) return Boolean is (C.Fall_T > 0.0);
   function Fallen (C : Car) return Boolean is (C.Fall_T > 0.9);

   --  The surface's grip on the road of the track loaded, for the AI
   function Road_Grip return Float;

end Cars;
