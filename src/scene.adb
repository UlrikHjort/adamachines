--  Adamachines: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
with Cairo; use Cairo;
with Cairo.Pattern;
with Glib; use Glib;
with Cars;
with Geom; use Geom;
with Tracks;

package body Scene is

   subtype RGB is Art.RGB;
   use type Race.Event_Kind;
   use type Race.Game_Mode;
   use type Race.Phase_Kind;
   use type Tracks.Material;
   use type Tracks.Theme_Kind;
   use type Tracks.Vehicle_Kind;
   use type Tracks.Mover_Kind;
   use type Tracks.Item_Kind;

   function G (X : Float) return Gdouble is (Gdouble (X));

   Paints : constant array (0 .. 7) of RGB :=
     ((0.88, 0.12, 0.10),    --  red, the first player
      (0.12, 0.38, 0.92),    --  blue, the second
      (0.98, 0.78, 0.08),    --  yellow
      (0.10, 0.70, 0.30),    --  green
      (0.62, 0.25, 0.85),    --  purple
      (0.98, 0.50, 0.08),    --  orange
      (0.94, 0.94, 0.94),    --  white
      (0.10, 0.75, 0.80));   --  teal

   function Paint (N : Natural) return RGB is (Paints (N mod Paints'Length));

   Cr : Cairo_Context := Null_Context;
   Rand : Seed := 99;

   procedure Color (C : RGB; A : Float := 1.0) is
   begin
      Set_Source_Rgba (Cr, G (C.R), G (C.G), G (C.B), G (A));
   end Color;

   procedure Color (R, Gr, B : Float; A : Float := 1.0) is
   begin
      Set_Source_Rgba (Cr, G (R), G (Gr), G (B), G (A));
   end Color;

   function Shade (A : RGB; F : Float) return RGB is
     ((Float'Min (1.0, A.R * F), Float'Min (1.0, A.G * F), Float'Min (1.0, A.B * F)));

   procedure Round_Box (X, Y, W, H, R : Float) is
   begin
      New_Sub_Path (Cr);
      Arc (Cr, G (X + W - R), G (Y + R), G (R), G (-Pi / 2.0), 0.0);
      Arc (Cr, G (X + W - R), G (Y + H - R), G (R), 0.0, G (Pi / 2.0));
      Arc (Cr, G (X + R), G (Y + H - R), G (R), G (Pi / 2.0), G (Pi));
      Arc (Cr, G (X + R), G (Y + R), G (R), G (Pi), G (1.5 * Pi));
      Close_Path (Cr);
   end Round_Box;

   function Mix (A, B : RGB; T : Float) return RGB is
     ((A.R + (B.R - A.R) * T, A.G + (B.G - A.G) * T, A.B + (B.B - A.B) * T));

   procedure Oval (RX, RY : Float) is
   begin
      Save (Cr);
      Cairo.Scale (Cr, G (RX), G (RY));
      New_Sub_Path (Cr);
      Arc (Cr, 0.0, 0.0, 1.0, 0.0, 2.0 * Pi);
      Restore (Cr);
   end Oval;

   procedure Disc (X, Y, R : Float) is
   begin
      New_Sub_Path (Cr);
      Arc (Cr, G (X), G (Y), G (R), 0.0, 2.0 * Pi);
   end Disc;

   ---------------------------------------------------------------------------
   --  Particles
   ---------------------------------------------------------------------------

   type Particle_Kind is (Smoke, Dust, Spray, Spark, Flame, Ring, Confetti);
   type Particle is record
      Kind : Particle_Kind := Smoke;
      P, V : Vec;
      Life, Max_Life : Float := 0.0;
      Size, Grow : Float := 1.0;
      C : RGB := (1.0, 1.0, 1.0);
      A : Float := 1.0;
      Spin : Float := 0.0;
   end record;
   Max_Particles : constant := 1600;
   Parts : array (1 .. Max_Particles) of Particle;
   Next_Part : Positive := 1;

   procedure Spawn (K : Particle_Kind; P, V : Vec; Life, Size, Grow : Float; C : RGB; A : Float := 1.0) is
   begin
      Parts (Next_Part) := (K, P, V, Life, Life, Size, Grow, C, A, Spread (Rand) * 8.0);
      Next_Part := (if Next_Part = Max_Particles then 1 else Next_Part + 1);
   end Spawn;

   function Dust_Color (M : Tracks.Material) return RGB is
   begin
      case M is
         when Tracks.Sand =>
            return (case Tracks.Theme is
                       when Tracks.Ice => (0.95, 0.97, 1.0),
                       when others => (0.85, 0.72, 0.48));
         when Tracks.Water => return (0.80, 0.90, 1.0);
         when others =>
            return (case Tracks.Theme is
                       when Tracks.Workbench => (0.78, 0.62, 0.42),
                       when Tracks.Garden => (0.45, 0.62, 0.25),
                       when Tracks.Ice | Tracks.Sky | Tracks.Bedroom => (0.95, 0.97, 1.0),
                       when Tracks.Bath => (0.90, 0.96, 1.0),
                       when Tracks.Kitchen => (0.85, 0.82, 0.78),
                       when Tracks.Mud => (0.48, 0.36, 0.22),
                       when Tracks.Pool => (0.55, 0.80, 0.60),
                       when Tracks.Desk => (0.85, 0.80, 0.75),
                       when Tracks.Beach => (0.90, 0.80, 0.58),
                       when Tracks.Toy_Town => (0.50, 0.65, 0.35),
                       when Tracks.Fish_Tank => (0.75, 0.70, 0.55),
                       when Tracks.Attic => (0.50, 0.45, 0.40),
                       when Tracks.Party => (1.0, 0.85, 0.90),
                       when Tracks.Garage => (0.55, 0.55, 0.52),
                       when Tracks.Xmas => (0.95, 0.95, 1.0),
                       when Tracks.Moon => (0.70, 0.70, 0.72),
                       when Tracks.Halloween => (0.45, 0.35, 0.55),
                       when Tracks.Easter => (0.55, 0.75, 0.35),
                       when Tracks.Chess => (0.85, 0.80, 0.70),
                       when Tracks.Alien => (0.55, 0.35, 0.65),
                       when Tracks.Arctic => (0.97, 0.98, 1.0));
      end case;
   end Dust_Color;

   procedure Hear (E : Race.Event) is
   begin
      case E.Kind is
         when Race.Bump =>
            for K in 1 .. Integer (Float'Min (12.0, E.Size / 12.0)) loop
               Spawn (Spark, E.P, Dir (Random (Rand) * 2.0 * Pi) * (60.0 + Random (Rand) * 120.0),
                      0.25 + Random (Rand) * 0.2, 1.1, 0.0, (1.0, 0.85, 0.4));
            end loop;
         when Race.Fell =>
            if Tracks.Theme /= Tracks.Workbench then
               for K in 1 .. 24 loop
                  Spawn (Spray, E.P, Dir (Random (Rand) * 2.0 * Pi) * (40.0 + Random (Rand) * 70.0),
                         0.5 + Random (Rand) * 0.3, 2.5, 3.0, (0.85, 0.93, 1.0), 0.9);
               end loop;
               Spawn (Ring, E.P, Zero, 0.8, 6.0, 50.0, (1.0, 1.0, 1.0), 0.8);
            end if;
         when Race.Landed =>
            if Tracks.Vehicle = Tracks.Boat then
               for K in 1 .. 20 loop
                  Spawn (Spray, E.P, Dir (Random (Rand) * 2.0 * Pi) * (40.0 + Random (Rand) * 60.0),
                         0.5, 2.2, 3.0, (0.92, 0.97, 1.0), 0.9);
               end loop;
               Spawn (Ring, E.P, Zero, 0.7, 6.0, 40.0, (1.0, 1.0, 1.0), 0.7);
            end if;
            for K in 1 .. (if Tracks.Vehicle = Tracks.Boat then 0 else 10) loop
               Spawn (Dust, E.P + Dir (Random (Rand) * 2.0 * Pi) * 8.0,
                      Dir (Random (Rand) * 2.0 * Pi) * (20.0 + Random (Rand) * 40.0),
                      0.6, 4.0, 10.0, Dust_Color (Tracks.Material_At (E.P)), 0.5);
            end loop;
         when Race.Put_Back =>
            Spawn (Ring, E.P, Zero, 0.6, 4.0, 60.0, (1.0, 1.0, 0.8), 0.9);
         when Race.Finished | Race.Duel_Won =>
            if E.Car in 1 .. Race.State.Count and then Race.State.Racers (E.Car).Human > 0 then
               for K in 1 .. 70 loop
                  Spawn (Confetti, E.P, Dir (Random (Rand) * 2.0 * Pi) * (40.0 + Random (Rand) * 160.0),
                         1.2 + Random (Rand) * 0.8, 2.2, 0.0, Paint (Natural (Random (Rand) * 8.0)));
               end loop;
            end if;
         when Race.Exploded =>
            for K in 1 .. 18 loop
               Spawn (Flame, E.P, Dir (Random (Rand) * 2.0 * Pi) * (30.0 + Random (Rand) * 90.0),
                      0.35 + Random (Rand) * 0.3, 4.0, 6.0, (1.0, 0.6, 0.1));
            end loop;
            for K in 1 .. 10 loop
               Spawn (Smoke, E.P, Dir (Random (Rand) * 2.0 * Pi) * (20.0 + Random (Rand) * 40.0),
                      1.0, 5.0, 14.0, (0.35, 0.33, 0.32), 0.6);
            end loop;
            for K in 1 .. 10 loop
               Spawn (Spark, E.P, Dir (Random (Rand) * 2.0 * Pi) * (100.0 + Random (Rand) * 150.0),
                      0.3, 1.2, 0.0, (1.0, 0.9, 0.5));
            end loop;
            Spawn (Ring, E.P, Zero, 0.4, 8.0, 90.0, (1.0, 0.8, 0.4), 0.9);
         when Race.Picked =>
            Spawn (Ring, E.P, Zero, 0.4, 6.0, 50.0, (1.0, 1.0, 1.0), 0.9);
            for K in 1 .. 10 loop
               Spawn (Confetti, E.P, Dir (Random (Rand) * 2.0 * Pi) * (40.0 + Random (Rand) * 60.0),
                      0.5, 1.6, 0.0, Paint (Natural (Random (Rand) * 8.0)));
            end loop;
         when Race.Shielded =>
            Spawn (Ring, E.P, Zero, 0.5, 10.0, 60.0, (0.4, 0.9, 1.0), 0.9);
         when Race.Boosted =>
            Spawn (Ring, E.P, Zero, 0.35, 6.0, 40.0, (1.0, 0.7, 0.2), 0.7);
         when others => null;
      end case;
   end Hear;

   procedure Move_Particles (Dt : Float) is
   begin
      for P of Parts loop
         if P.Life > 0.0 then
            P.Life := P.Life - Dt;
            P.P := P.P + P.V * Dt;
            P.Size := P.Size + P.Grow * Dt;
            case P.Kind is
               when Smoke | Dust => P.V := P.V * (1.0 - 2.5 * Dt);
               when Spray => P.V := P.V * (1.0 - 3.0 * Dt);
               when Spark => P.V := P.V * (1.0 - 4.0 * Dt);
               when Flame => P.V := P.V * (1.0 - 5.0 * Dt);
               when Confetti => P.V := P.V * (1.0 - 2.0 * Dt);
               when Ring => null;
            end case;
         end if;
      end loop;
   end Move_Particles;

   procedure Draw_Particles (Above : Boolean) is
   begin
      for P of Parts loop
         if P.Life > 0.0 and then (P.Kind in Spark | Confetti | Ring | Flame) = Above then
            declare
               F : constant Float := P.Life / P.Max_Life;
            begin
               case P.Kind is
                  when Smoke | Dust | Spray =>
                     New_Path (Cr);
                     Disc (P.P.X, P.P.Y, P.Size);
                     Color (P.C, P.A * F * F);
                     Fill (Cr);
                  when Spark =>
                     Set_Line_Width (Cr, G (P.Size));
                     Color (P.C, F);
                     Move_To (Cr, G (P.P.X), G (P.P.Y));
                     Line_To (Cr, G (P.P.X - P.V.X * 0.03), G (P.P.Y - P.V.Y * 0.03));
                     Stroke (Cr);
                  when Flame =>
                     New_Path (Cr);
                     Disc (P.P.X, P.P.Y, P.Size * (0.5 + F));
                     Color (1.0, 0.35 + 0.6 * F, 0.1 * F, 0.8 * F);
                     Fill (Cr);
                  when Ring =>
                     New_Path (Cr);
                     Arc (Cr, G (P.P.X), G (P.P.Y), G (P.Size), 0.0, 2.0 * Pi);
                     Set_Line_Width (Cr, 2.0);
                     Color (P.C, P.A * F);
                     Stroke (Cr);
                  when Confetti =>
                     Save (Cr);
                     Translate (Cr, G (P.P.X), G (P.P.Y));
                     Rotate (Cr, G (P.Spin * P.Life));
                     New_Path (Cr);
                     Rectangle (Cr, G (-P.Size), G (-P.Size * 0.5), G (P.Size * 2.0), G (P.Size));
                     Color (P.C, Float'Min (1.0, 2.0 * F));
                     Fill (Cr);
                     Restore (Cr);
               end case;
            end;
         end if;
      end loop;
   end Draw_Particles;

   ---------------------------------------------------------------------------
   --  The cars
   ---------------------------------------------------------------------------

   type Car_Look is (Racer_Look, Buggy_Look, Rally_Look, Boat_Look, Plane_Look, Sport_Look, Cross_Look,
                     Kart_Look, Tank_Look, Hover_Look, Sub_Look, Monster_Look, Rover_Look, Broom_Look, Egg_Look,
                     Saucer_Look, Snowmobile_Look);

   function Look return Car_Look is
     (case Tracks.Theme is
         when Tracks.Workbench => Racer_Look,
         when Tracks.Garden => Buggy_Look,
         when Tracks.Ice => Rally_Look,
         when Tracks.Bath => Boat_Look,
         when Tracks.Bedroom | Tracks.Sky => Plane_Look,
         when Tracks.Kitchen => Sport_Look,
         when Tracks.Mud => Cross_Look,
         when Tracks.Pool => Kart_Look,
         when Tracks.Desk => Tank_Look,
         when Tracks.Beach => Hover_Look,
         when Tracks.Toy_Town | Tracks.Attic => Rally_Look,
         when Tracks.Party => Racer_Look,
         when Tracks.Xmas => Buggy_Look,
         when Tracks.Fish_Tank => Sub_Look,
         when Tracks.Garage => Monster_Look,
         when Tracks.Moon => Rover_Look,
         when Tracks.Halloween => Broom_Look,
         when Tracks.Easter => Egg_Look,
         when Tracks.Chess => Racer_Look,
         when Tracks.Alien => Saucer_Look,
         when Tracks.Arctic => Snowmobile_Look);

   Clock : Float := 0.0;   --  for the propellers and the bobbing

   procedure Body_Gradient (Paint_C : RGB; Half : Float) is
      P : constant Cairo_Pattern := Cairo.Pattern.Create_Linear (0.0, G (-Half), 0.0, G (Half));
      Dark : constant RGB := Shade (Paint_C, 0.6);
      Light : constant RGB := Shade (Paint_C, 1.35);
   begin
      Cairo.Pattern.Add_Color_Stop_Rgb (P, 0.0, G (Dark.R), G (Dark.G), G (Dark.B));
      Cairo.Pattern.Add_Color_Stop_Rgb (P, 0.45, G (Light.R), G (Light.G), G (Light.B));
      Cairo.Pattern.Add_Color_Stop_Rgb (P, 1.0, G (Dark.R * 0.8), G (Dark.G * 0.8), G (Dark.B * 0.8));
      Set_Source (Cr, P);
      Cairo.Pattern.Destroy (P);
   end Body_Gradient;

   --  A speedboat: white hull, a painted deck, an outboard at the back
   procedure Boat_Body (Paint_C : RGB; Steer : Float; Boosting : Boolean) is
   begin
      --  the motor, turned with the rudder
      Save (Cr);
      Translate (Cr, -11.0, 0.0);
      Rotate (Cr, G (-Steer * 0.5));
      New_Path (Cr);
      Round_Box (-4.5, -2.6, 5.0, 5.2, 1.2);
      Color (0.12, 0.12, 0.14);
      Fill (Cr);
      Restore (Cr);
      New_Path (Cr);
      Move_To (Cr, 14.0, 0.0);
      Curve_To (Cr, 10.0, -5.5, 4.0, -6.5, -2.0, -6.5);
      Line_To (Cr, -11.0, -6.0);
      Line_To (Cr, -11.0, 6.0);
      Line_To (Cr, -2.0, 6.5);
      Curve_To (Cr, 4.0, 6.5, 10.0, 5.5, 14.0, 0.0);
      Close_Path (Cr);
      Body_Gradient ((0.95, 0.95, 0.97), 6.5);
      Fill_Preserve (Cr);
      Set_Line_Width (Cr, 0.7);
      Color (0.0, 0.0, 0.0, 0.5);
      Stroke (Cr);
      --  the deck
      New_Path (Cr);
      Move_To (Cr, 11.0, 0.0);
      Curve_To (Cr, 8.0, -4.0, 3.0, -4.8, -2.0, -4.8);
      Line_To (Cr, -9.5, -4.5);
      Line_To (Cr, -9.5, 4.5);
      Line_To (Cr, -2.0, 4.8);
      Curve_To (Cr, 3.0, 4.8, 8.0, 4.0, 11.0, 0.0);
      Close_Path (Cr);
      Body_Gradient (Paint_C, 4.8);
      Fill (Cr);
      --  the windscreen and the seat
      New_Path (Cr);
      Move_To (Cr, 3.5, -4.0);
      Curve_To (Cr, 5.5, -2.0, 5.5, 2.0, 3.5, 4.0);
      Line_To (Cr, 1.8, 3.6);
      Curve_To (Cr, 3.4, 1.5, 3.4, -1.5, 1.8, -3.6);
      Close_Path (Cr);
      Color (0.25, 0.45, 0.6, 0.85);
      Fill (Cr);
      New_Path (Cr);
      Round_Box (-5.5, -3.0, 5.0, 6.0, 1.5);
      Color (0.15, 0.15, 0.18);
      Fill (Cr);
      New_Path (Cr);
      Disc (-2.5, 0.0, 2.0);
      Color (Shade (Paint_C, 1.25));
      Fill (Cr);
      if Boosting then
         New_Path (Cr);
         Move_To (Cr, -15.0, -2.5);
         Line_To (Cr, -21.0, 0.0);
         Line_To (Cr, -15.0, 2.5);
         Close_Path (Cr);
         Color (1.0, 0.65, 0.15, 0.85);
         Fill (Cr);
      end if;
   end Boat_Body;

   procedure Radial (CX, CY, R : Float; Inner, Outer : RGB) is
      P : constant Cairo_Pattern := Cairo.Pattern.Create_Radial
        (G (CX - R * 0.3), G (CY - R * 0.3), G (R * 0.1), G (CX), G (CY), G (R));
   begin
      Cairo.Pattern.Add_Color_Stop_Rgb (P, 0.0, G (Inner.R), G (Inner.G), G (Inner.B));
      Cairo.Pattern.Add_Color_Stop_Rgb (P, 1.0, G (Outer.R), G (Outer.G), G (Outer.B));
      Set_Source (Cr, P);
      Cairo.Pattern.Destroy (P);
   end Radial;

   --  A go-kart: four fat wheels, a frame, a driver in a helmet
   procedure Kart_Body (Paint_C : RGB; Steer : Float) is
   begin
      for Front in Boolean loop
         for Side in -1 .. 1 loop
            if Side /= 0 then
               Save (Cr);
               Translate (Cr, G (if Front then 7.5 else -7.0), G (Float (Side) * 7.0));
               if Front then
                  Rotate (Cr, G (Steer * 0.5));
               end if;
               New_Path (Cr);
               Round_Box (-3.2, -2.3, 6.4, 4.6, 1.4);
               Color (0.06, 0.06, 0.07);
               Fill (Cr);
               Restore (Cr);
            end if;
         end loop;
      end loop;
      New_Path (Cr);
      Round_Box (-9.0, -4.5, 18.0, 9.0, 2.5);
      Color (0.12, 0.12, 0.14);
      Fill (Cr);
      New_Path (Cr);
      Move_To (Cr, 12.0, 0.0);
      Line_To (Cr, 7.0, -4.0);
      Line_To (Cr, 7.0, 4.0);
      Close_Path (Cr);
      Body_Gradient (Paint_C, 4.0);
      Fill (Cr);
      for Side in -1 .. 1 loop
         if Side /= 0 then
            New_Path (Cr);
            Round_Box (-3.0, Float (Side) * 4.8 - 1.6, 8.0, 3.2, 1.4);
            Body_Gradient (Paint_C, 4.0);
            Fill (Cr);
         end if;
      end loop;
      New_Path (Cr);
      Round_Box (-11.0, -3.5, 3.5, 7.0, 1.2);
      Color (0.35, 0.35, 0.38);
      Fill (Cr);
      New_Path (Cr);
      Disc (-2.5, 0.0, 3.0);
      Radial (-2.5, 0.0, 3.0, Shade (Paint_C, 1.5), Shade (Paint_C, 0.7));
      Fill (Cr);
      New_Path (Cr);
      Rectangle (Cr, -1.2, -1.8, 1.5, 3.6);
      Color (0.05, 0.05, 0.08);
      Fill (Cr);
   end Kart_Body;

   --  A tank: two tracks, a hull, a turret and its gun
   procedure Tank_Body (Paint_C : RGB; Steer : Float) is
      Hull : constant RGB := Shade (Paint_C, 0.75);
      Roll : constant Float := Clock * 30.0 - Float'Floor (Clock * 30.0 / 4.0) * 4.0;
   begin
      for Side in -1 .. 1 loop
         if Side /= 0 then
            New_Path (Cr);
            Round_Box (-13.0, Float (Side) * 6.5 - 3.0, 26.0, 6.0, 2.5);
            Color (0.10, 0.10, 0.10);
            Fill (Cr);
            Set_Line_Width (Cr, 0.8);
            Color (0.30, 0.30, 0.30);
            declare
               X : Float := -12.0 + Roll;
            begin
               while X < 12.0 loop
                  Move_To (Cr, G (X), G (Float (Side) * 6.5 - 2.8));
                  Line_To (Cr, G (X), G (Float (Side) * 6.5 + 2.8));
                  X := X + 4.0;
               end loop;
            end;
            Stroke (Cr);
         end if;
      end loop;
      New_Path (Cr);
      Round_Box (-11.5, -4.5, 23.0, 9.0, 2.0);
      Body_Gradient (Hull, 4.5);
      Fill (Cr);
      Save (Cr);
      Rotate (Cr, G (Steer * 0.25));
      New_Path (Cr);
      Rectangle (Cr, 2.0, -1.0, 16.0, 2.0);
      Color (0.15, 0.15, 0.15);
      Fill (Cr);
      New_Path (Cr);
      Disc (-1.0, 0.0, 5.2);
      Radial (-1.0, 0.0, 5.2, Shade (Paint_C, 1.3), Shade (Paint_C, 0.6));
      Fill (Cr);
      New_Path (Cr);
      Disc (-2.5, -1.5, 1.4);
      Color (0.1, 0.1, 0.1);
      Fill (Cr);
      Restore (Cr);
   end Tank_Body;

   --  A hovercraft: a black skirt full of air, a deck, two fans at the back
   procedure Hover_Body (Paint_C : RGB; Steer : Float) is
   begin
      New_Path (Cr);
      Round_Box (-13.0, -8.0, 26.0, 16.0, 7.0);
      Color (0.10, 0.10, 0.12);
      Fill (Cr);
      New_Path (Cr);
      Round_Box (-10.5, -6.0, 21.0, 12.0, 5.0);
      Body_Gradient (Paint_C, 6.0);
      Fill (Cr);
      New_Path (Cr);
      Round_Box (1.0, -4.0, 7.0, 8.0, 3.0);
      Color (0.20, 0.32, 0.45, 0.9);
      Fill (Cr);
      for Side in -1 .. 1 loop
         if Side /= 0 then
            New_Path (Cr);
            Disc (-9.0, Float (Side) * 4.0, 3.6);
            Color (0.85, 0.85, 0.88);
            Fill (Cr);
            Set_Line_Width (Cr, 1.0);
            Color (0.2, 0.2, 0.22);
            declare
               A : constant Float := Clock * 40.0 + Float (Side);
            begin
               Move_To (Cr, G (-9.0 + 3.0 * Cos (A)), G (Float (Side) * 4.0 + 3.0 * Sin (A)));
               Line_To (Cr, G (-9.0 - 3.0 * Cos (A)), G (Float (Side) * 4.0 - 3.0 * Sin (A)));
            end;
            Stroke (Cr);
            Save (Cr);
            Translate (Cr, -13.0, G (Float (Side) * 4.0));
            Rotate (Cr, G (-Steer * 0.5));
            New_Path (Cr);
            Rectangle (Cr, -3.0, -0.6, 3.0, 1.2);
            Color (0.15, 0.15, 0.15);
            Fill (Cr);
            Restore (Cr);
         end if;
      end loop;
   end Hover_Body;

   --  A snowmobile: two skis in front that steer, a tracked belt behind, a rider in a helmet
   procedure Snowmobile_Body (Paint_C : RGB; Steer : Float) is
   begin
      --  the belt
      New_Path (Cr);
      Round_Box (-13.0, -4.0, 13.0, 8.0, 2.0);
      Color (0.10, 0.10, 0.11);
      Fill (Cr);
      Set_Line_Width (Cr, 0.8);
      Color (0.30, 0.30, 0.32);
      declare
         X : Float := -12.5 + (Clock * 25.0 - Float'Floor (Clock * 25.0 / 3.0) * 3.0);
      begin
         while X < -0.5 loop
            Move_To (Cr, G (X), -3.8);
            Line_To (Cr, G (X), 3.8);
            X := X + 3.0;
         end loop;
      end;
      Stroke (Cr);
      --  the skis
      for Side in -1 .. 1 loop
         if Side /= 0 then
            Save (Cr);
            Translate (Cr, 8.0, G (Float (Side) * 6.5));
            Rotate (Cr, G (Steer * 0.4));
            New_Path (Cr);
            Round_Box (-5.0, -1.2, 11.0, 2.4, 1.2);
            Color (0.15, 0.15, 0.17);
            Fill (Cr);
            Restore (Cr);
            Set_Line_Width (Cr, 1.0);
            Color (0.25, 0.25, 0.28);
            Move_To (Cr, 3.0, G (Float (Side) * 2.5));
            Line_To (Cr, 8.0, G (Float (Side) * 6.5));
            Stroke (Cr);
         end if;
      end loop;
      --  the body and the windscreen
      New_Path (Cr);
      Move_To (Cr, 9.5, 0.0);
      Curve_To (Cr, 9.5, -4.0, 4.0, -5.0, -2.0, -4.5);
      Line_To (Cr, -10.0, -3.5);
      Line_To (Cr, -10.0, 3.5);
      Line_To (Cr, -2.0, 4.5);
      Curve_To (Cr, 4.0, 5.0, 9.5, 4.0, 9.5, 0.0);
      Close_Path (Cr);
      Body_Gradient (Paint_C, 4.5);
      Fill_Preserve (Cr);
      Set_Line_Width (Cr, 0.6);
      Color (0.0, 0.0, 0.0, 0.5);
      Stroke (Cr);
      New_Path (Cr);
      Move_To (Cr, 4.5, -3.5);
      Curve_To (Cr, 6.5, -1.5, 6.5, 1.5, 4.5, 3.5);
      Line_To (Cr, 3.0, 3.0);
      Line_To (Cr, 3.0, -3.0);
      Close_Path (Cr);
      Color (0.35, 0.55, 0.70, 0.85);
      Fill (Cr);
      New_Path (Cr);
      Round_Box (-8.0, -2.5, 7.0, 5.0, 1.5);
      Color (0.12, 0.12, 0.14);
      Fill (Cr);
      --  the rider
      New_Path (Cr);
      Disc (-2.0, Steer * 1.5, 3.0);
      Radial (-2.0, Steer * 1.5, 3.0, Shade (Paint_C, 1.5), Shade (Paint_C, 0.7));
      Fill (Cr);
      New_Path (Cr);
      Rectangle (Cr, -0.6, G (-1.6 + Steer * 1.5), 1.6, 3.2);
      Color (0.05, 0.05, 0.08);
      Fill (Cr);
   end Snowmobile_Body;

   --  A flying saucer: a disc, a glass dome, and a ring of lights going round
   procedure Saucer_Body (Paint_C : RGB; Steer : Float) is
      pragma Unreferenced (Steer);
   begin
      New_Path (Cr);
      Disc (0.0, 0.0, 12.5);
      Radial (0.0, 0.0, 12.5, (0.92, 0.93, 0.96), (0.45, 0.47, 0.52));
      Fill (Cr);
      New_Path (Cr);
      Arc (Cr, 0.0, 0.0, 9.5, 0.0, 2.0 * Pi);
      Set_Line_Width (Cr, 0.8);
      Color (0.3, 0.3, 0.35);
      Stroke (Cr);
      for K in 0 .. 7 loop
         declare
            A : constant Float := Float (K) * Pi / 4.0 + Clock * 3.0;
            On : constant Boolean := (K + Integer (Clock * 8.0)) mod 3 = 0;
         begin
            New_Path (Cr);
            Disc (11.0 * Cos (A), 11.0 * Sin (A), 1.3);
            if On then
               Color (1.0, 1.0, 0.5);
            else
               Color (Shade (Paint_C, 1.2));
            end if;
            Fill (Cr);
         end;
      end loop;
      New_Path (Cr);
      Disc (0.0, 0.0, 6.0);
      Radial (0.0, 0.0, 6.0, (0.85, 1.0, 0.95), Shade (Paint_C, 0.8));
      Fill (Cr);
      New_Path (Cr);
      Disc (1.0, 0.0, 2.2);
      Color (0.40, 0.85, 0.40);
      Fill (Cr);
      for S in -1 .. 1 loop
         if S /= 0 then
            New_Path (Cr);
            Disc (2.2, Float (S) * 0.9, 0.6);
            Color (0.05, 0.05, 0.05);
            Fill (Cr);
         end if;
      end loop;
   end Saucer_Body;

   --  A witch on a broomstick: the bristles behind, a hat and a cape
   procedure Broom_Body (Paint_C : RGB; Steer : Float) is
   begin
      Set_Line_Width (Cr, 2.0);
      Color (0.55, 0.35, 0.18);
      Move_To (Cr, 14.0, 0.0);
      Line_To (Cr, -8.0, 0.0);
      Stroke (Cr);
      New_Path (Cr);
      Move_To (Cr, -7.0, -1.5);
      Line_To (Cr, -17.0, -5.5);
      Line_To (Cr, -18.5, 0.0);
      Line_To (Cr, -17.0, 5.5);
      Line_To (Cr, -7.0, 1.5);
      Close_Path (Cr);
      Color (0.85, 0.70, 0.35);
      Fill (Cr);
      Set_Line_Width (Cr, 0.6);
      Color (0.55, 0.42, 0.15);
      for K in -2 .. 2 loop
         Move_To (Cr, -8.0, G (Float (K) * 0.6));
         Line_To (Cr, -17.5, G (Float (K) * 2.0));
      end loop;
      Stroke (Cr);
      --  the cape flying out to the side she leans to
      New_Path (Cr);
      Move_To (Cr, 1.0, -4.0);
      Line_To (Cr, G (-9.0), G (-7.0 + Steer * 3.0));
      Line_To (Cr, G (-9.0), G (7.0 + Steer * 3.0));
      Line_To (Cr, 1.0, 4.0);
      Close_Path (Cr);
      Body_Gradient (Paint_C, 6.0);
      Fill (Cr);
      New_Path (Cr);
      Disc (0.0, 0.0, 5.0);
      Color (0.10, 0.08, 0.12);
      Fill (Cr);
      New_Path (Cr);
      Disc (0.5, 0.0, 2.6);
      Color (0.20, 0.15, 0.25);
      Fill (Cr);
      New_Path (Cr);
      Disc (0.8, 0.0, 1.0);
      Color (Shade (Paint_C, 1.3));
      Fill (Cr);
   end Broom_Body;

   --  An Easter egg on wheels, painted in bands
   procedure Egg_Body (Paint_C : RGB; Steer : Float) is
      Pale : constant RGB := Mix (Paint_C, (1.0, 1.0, 1.0), 0.45);
   begin
      for Front in Boolean loop
         for Side in -1 .. 1 loop
            if Side /= 0 then
               Save (Cr);
               Translate (Cr, G (if Front then 6.5 else -6.5), G (Float (Side) * 6.5));
               if Front then
                  Rotate (Cr, G (Steer * 0.45));
               end if;
               New_Path (Cr);
               Round_Box (-3.0, -1.8, 6.0, 3.6, 1.2);
               Color (0.08, 0.08, 0.09);
               Fill (Cr);
               Restore (Cr);
            end if;
         end loop;
      end loop;
      New_Path (Cr);
      Move_To (Cr, 12.5, 0.0);
      Curve_To (Cr, 12.5, -6.0, -12.0, -8.0, -12.0, 0.0);
      Curve_To (Cr, -12.0, 8.0, 12.5, 6.0, 12.5, 0.0);
      Close_Path (Cr);
      Body_Gradient (Pale, 6.5);
      Fill_Preserve (Cr);
      Set_Line_Width (Cr, 0.6);
      Color (0.0, 0.0, 0.0, 0.4);
      Stroke (Cr);
      Set_Line_Width (Cr, 1.6);
      Color (Paint_C);
      New_Path (Cr);
      for K in 0 .. 6 loop
         Line_To (Cr, G (-4.0 + (if K mod 2 = 0 then -2.0 else 2.0)), G (-6.0 + Float (K) * 2.0));
      end loop;
      Stroke (Cr);
      for K in -1 .. 1 loop
         New_Path (Cr);
         Disc (-9.0, Float (K) * 3.0, 1.1);
         Color (1.0, 1.0, 1.0);
         Fill (Cr);
      end loop;
      New_Path (Cr);
      Round_Box (2.0, -3.5, 5.0, 7.0, 2.0);
      Color (0.20, 0.30, 0.40, 0.85);
      Fill (Cr);
   end Egg_Body;

   --  A submarine: a rounded hull, a conning tower, a propeller turning
   procedure Sub_Body (Paint_C : RGB; Steer : Float) is
   begin
      for Side in -1 .. 1 loop
         if Side /= 0 then
            New_Path (Cr);
            Move_To (Cr, -8.0, G (Float (Side) * 5.0));
            Line_To (Cr, -12.0, G (Float (Side) * 8.5));
            Line_To (Cr, -13.0, G (Float (Side) * 5.0));
            Close_Path (Cr);
            Color (Shade (Paint_C, 0.6));
            Fill (Cr);
         end if;
      end loop;
      New_Path (Cr);
      Round_Box (-12.0, -5.5, 25.0, 11.0, 5.5);
      Body_Gradient (Paint_C, 5.5);
      Fill_Preserve (Cr);
      Set_Line_Width (Cr, 0.6);
      Color (0.0, 0.0, 0.0, 0.5);
      Stroke (Cr);
      New_Path (Cr);
      Round_Box (-3.0, -3.0, 9.0, 6.0, 3.0);
      Color (Shade (Paint_C, 1.2));
      Fill (Cr);
      for K in 0 .. 2 loop
         New_Path (Cr);
         Disc (-7.0 + Float (K) * 5.5, 0.0, 1.2);
         Color (0.3, 0.6, 0.8);
         Fill (Cr);
      end loop;
      New_Path (Cr);
      Disc (2.0, 0.0, 1.0);
      Color (0.15, 0.15, 0.15);
      Fill (Cr);
      Save (Cr);
      Translate (Cr, -13.5, 0.0);
      Rotate (Cr, G (-Steer * 0.4));
      New_Path (Cr);
      Save (Cr);
      Cairo.Scale (Cr, 1.0, 4.5);
      Arc (Cr, 0.0, 0.0, 1.0, 0.0, 2.0 * Pi);
      Restore (Cr);
      Color (0.85, 0.85, 0.85, 0.45);
      Fill (Cr);
      Restore (Cr);
   end Sub_Body;

   --  A monster truck: wheels as big as the body, and the body high on them
   procedure Monster_Body (Paint_C : RGB; Steer : Float) is
   begin
      for Front in Boolean loop
         for Side in -1 .. 1 loop
            if Side /= 0 then
               Save (Cr);
               Translate (Cr, G (if Front then 8.0 else -8.0), G (Float (Side) * 8.5));
               if Front then
                  Rotate (Cr, G (Steer * 0.4));
               end if;
               New_Path (Cr);
               Round_Box (-5.5, -3.6, 11.0, 7.2, 2.5);
               Color (0.06, 0.06, 0.06);
               Fill (Cr);
               Set_Line_Width (Cr, 0.8);
               Color (0.30, 0.30, 0.30);
               for K in -2 .. 2 loop
                  Move_To (Cr, G (Float (K) * 2.0), -3.6);
                  Line_To (Cr, G (Float (K) * 2.0), 3.6);
               end loop;
               Stroke (Cr);
               Restore (Cr);
            end if;
         end loop;
      end loop;
      New_Path (Cr);
      Round_Box (-11.0, -6.0, 22.0, 12.0, 3.0);
      Body_Gradient (Paint_C, 6.0);
      Fill_Preserve (Cr);
      Set_Line_Width (Cr, 0.7);
      Color (0.0, 0.0, 0.0, 0.5);
      Stroke (Cr);
      New_Path (Cr);
      Round_Box (-4.0, -4.5, 8.0, 9.0, 2.0);
      Color (0.12, 0.14, 0.18);
      Fill (Cr);
      --  flames down the bonnet
      for Side in -1 .. 1 loop
         if Side /= 0 then
            New_Path (Cr);
            Move_To (Cr, 10.0, G (Float (Side) * 2.0));
            Line_To (Cr, 5.0, G (Float (Side) * 4.5));
            Line_To (Cr, 7.0, G (Float (Side) * 2.5));
            Line_To (Cr, 4.0, G (Float (Side) * 1.0));
            Close_Path (Cr);
            Color (1.0, 0.65, 0.1);
            Fill (Cr);
         end if;
      end loop;
   end Monster_Body;

   --  A lunar rover: six wheels, a flat deck, a dish and a panel of cells
   procedure Rover_Body (Paint_C : RGB; Steer : Float) is
   begin
      for Axle in -1 .. 1 loop
         for Side in -1 .. 1 loop
            if Side /= 0 then
               Save (Cr);
               Translate (Cr, G (Float (Axle) * 8.0), G (Float (Side) * 6.8));
               if Axle = 1 then
                  Rotate (Cr, G (Steer * 0.45));
               end if;
               New_Path (Cr);
               Round_Box (-3.0, -2.0, 6.0, 4.0, 1.5);
               Color (0.18, 0.18, 0.20);
               Fill (Cr);
               Restore (Cr);
            end if;
         end loop;
      end loop;
      New_Path (Cr);
      Round_Box (-11.5, -5.0, 23.0, 10.0, 2.0);
      Color (0.85, 0.86, 0.88);
      Fill (Cr);
      New_Path (Cr);
      Rectangle (Cr, -11.0, -4.5, 9.0, 9.0);
      Color (Shade (Paint_C, 0.7));
      Fill (Cr);
      Set_Line_Width (Cr, 0.5);
      Color (0.9, 0.9, 1.0, 0.6);
      for K in 1 .. 2 loop
         Move_To (Cr, G (-11.0 + Float (K) * 3.0), -4.5);
         Line_To (Cr, G (-11.0 + Float (K) * 3.0), 4.5);
         Move_To (Cr, -11.0, G (-4.5 + Float (K) * 3.0));
         Line_To (Cr, -2.0, G (-4.5 + Float (K) * 3.0));
      end loop;
      Stroke (Cr);
      New_Path (Cr);
      Disc (3.0, 0.0, 2.8);
      Radial (3.0, 0.0, 2.8, (1.0, 1.0, 1.0), Paint_C);
      Fill (Cr);
      New_Path (Cr);
      Rectangle (Cr, 3.8, -1.4, 1.4, 2.8);
      Color (0.85, 0.70, 0.2);
      Fill (Cr);
      New_Path (Cr);
      Disc (9.0, -2.5, 2.0);
      Set_Line_Width (Cr, 0.8);
      Color (0.95, 0.95, 0.95);
      Stroke (Cr);
   end Rover_Body;

   --  A motorcycle from above, its rider leaning into the turn
   procedure Bike_Body (Paint_C : RGB; Steer : Float; Braking, Boosting : Boolean; Cross : Boolean) is
      Lean : constant Float := Clamp (Steer, -1.0, 1.0) * 2.4;
      Tyre_W : constant Float := (if Cross then 3.4 else 3.0);
   begin
      --  the back wheel
      New_Path (Cr);
      Round_Box (-11.0, -Tyre_W / 2.0, 7.0, Tyre_W, 1.4);
      Color (0.06, 0.06, 0.07);
      Fill (Cr);
      --  the front wheel and the bars turn with the steering
      Save (Cr);
      Translate (Cr, 6.5, 0.0);
      Rotate (Cr, G (Steer * 0.45));
      New_Path (Cr);
      Round_Box (-1.0, -Tyre_W / 2.0, 7.0, Tyre_W, 1.4);
      Color (0.06, 0.06, 0.07);
      Fill (Cr);
      if Cross then
         Set_Line_Width (Cr, 0.6);
         Color (0.35, 0.35, 0.37);
         for K in 0 .. 3 loop
            Move_To (Cr, G (Float (K) * 1.6), G (-Tyre_W / 2.0));
            Line_To (Cr, G (Float (K) * 1.6), G (Tyre_W / 2.0));
         end loop;
         Stroke (Cr);
         --  the high front mudguard
         New_Path (Cr);
         Round_Box (0.0, -2.0, 7.5, 4.0, 1.8);
         Color (Shade (Paint_C, 1.2));
         Fill (Cr);
      end if;
      New_Path (Cr);
      Set_Line_Width (Cr, 1.3);
      Color (0.15, 0.15, 0.17);
      Move_To (Cr, -1.5, -5.0);
      Line_To (Cr, -1.0, 5.0);
      Stroke (Cr);
      Restore (Cr);
      --  the bike
      New_Path (Cr);
      if Cross then
         Round_Box (-8.0, -2.6, 14.0, 5.2, 2.2);
      else
         Move_To (Cr, 7.5, 0.0);
         Curve_To (Cr, 7.5, -3.6, 2.0, -3.6, -2.0, -3.4);
         Line_To (Cr, -9.5, -2.2);
         Line_To (Cr, -9.5, 2.2);
         Line_To (Cr, -2.0, 3.4);
         Curve_To (Cr, 2.0, 3.6, 7.5, 3.6, 7.5, 0.0);
         Close_Path (Cr);
      end if;
      Body_Gradient (Paint_C, 3.6);
      Fill_Preserve (Cr);
      Set_Line_Width (Cr, 0.6);
      Color (0.0, 0.0, 0.0, 0.5);
      Stroke (Cr);
      if Cross then
         --  the number board
         New_Path (Cr);
         Save (Cr);
         Translate (Cr, 5.5, 0.0);
         Cairo.Scale (Cr, 1.2, 2.6);
         Arc (Cr, 0.0, 0.0, 1.0, 0.0, 2.0 * Pi);
         Restore (Cr);
         Color (0.97, 0.97, 0.95);
         Fill (Cr);
      else
         New_Path (Cr);
         Move_To (Cr, 6.0, -2.4);
         Curve_To (Cr, 7.4, -1.0, 7.4, 1.0, 6.0, 2.4);
         Line_To (Cr, 4.6, 1.8);
         Line_To (Cr, 4.6, -1.8);
         Close_Path (Cr);
         Color (0.20, 0.30, 0.40, 0.9);
         Fill (Cr);
      end if;
      --  the rider, over to the inside of the turn
      Save (Cr);
      Translate (Cr, 0.0, G (Lean));
      New_Path (Cr);
      Save (Cr);
      Translate (Cr, (if Cross then -1.5 else -3.0), 0.0);
      Cairo.Scale (Cr, 4.2, 3.4);
      Arc (Cr, 0.0, 0.0, 1.0, 0.0, 2.0 * Pi);
      Restore (Cr);
      Color (0.12, 0.12, 0.14);
      Fill (Cr);
      --  arms to the bars
      Set_Line_Width (Cr, 1.4);
      Color (0.15, 0.15, 0.17);
      New_Path (Cr);
      Move_To (Cr, -1.0, -2.6);
      Line_To (Cr, 5.0, G (-4.5 - Lean * 0.3));
      Move_To (Cr, -1.0, 2.6);
      Line_To (Cr, 5.0, G (4.5 - Lean * 0.3));
      Stroke (Cr);
      --  the helmet
      New_Path (Cr);
      Disc ((if Cross then 1.0 else 0.0), 0.0, 2.8);
      Radial ((if Cross then 1.0 else 0.0), 0.0, 2.8, Shade (Paint_C, 1.5), Shade (Paint_C, 0.8));
      Fill (Cr);
      New_Path (Cr);
      Rectangle (Cr, (if Cross then 2.4 else 1.4), -1.6, 1.4, 3.2);
      Color (0.05, 0.05, 0.08);
      Fill (Cr);
      if Cross then
         New_Path (Cr);
         Round_Box (2.8, -2.0, 2.2, 4.0, 0.8);
         Color (Shade (Paint_C, 0.8));
         Fill (Cr);
      end if;
      Restore (Cr);
      --  the tail light
      New_Path (Cr);
      Rectangle (Cr, -10.0, -1.0, 1.0, 2.0);
      if Braking then
         Color (1.0, 0.15, 0.1);
      else
         Color (0.5, 0.05, 0.05);
      end if;
      Fill (Cr);
      if Boosting then
         New_Path (Cr);
         Move_To (Cr, -11.0, -1.8);
         Line_To (Cr, -17.0, 0.0);
         Line_To (Cr, -11.0, 1.8);
         Close_Path (Cr);
         Color (1.0, 0.65, 0.15, 0.85);
         Fill (Cr);
      end if;
   end Bike_Body;

   --  A biplane from above: the top wing over the bottom one, a spinning propeller
   procedure Plane_Body (Paint_C : RGB; Steer : Float; Boosting : Boolean) is
      Bank : constant Float := 1.0 - 0.18 * abs Steer;   --  the wings seen tilted
      Span : constant Float := 14.0 * Bank;
   begin
      --  the lower wing, a little behind
      New_Path (Cr);
      Round_Box (-1.5, -Span * 0.95, 5.5, 2.0 * Span * 0.95, 1.8);
      Color (Shade (Paint_C, 0.65));
      Fill (Cr);
      --  the tail
      New_Path (Cr);
      Round_Box (-12.0, -5.5, 3.5, 11.0, 1.2);
      Color (Shade (Paint_C, 0.85));
      Fill (Cr);
      New_Path (Cr);
      Rectangle (Cr, -12.5, -0.6, 4.5, 1.2);
      Color (0.15, 0.15, 0.15);
      Fill (Cr);
      --  the body
      New_Path (Cr);
      Move_To (Cr, 10.5, 0.0);
      Curve_To (Cr, 10.5, -3.2, 6.0, -3.0, 0.0, -2.6);
      Line_To (Cr, -11.0, -1.0);
      Line_To (Cr, -11.0, 1.0);
      Line_To (Cr, 0.0, 2.6);
      Curve_To (Cr, 6.0, 3.0, 10.5, 3.2, 10.5, 0.0);
      Close_Path (Cr);
      Body_Gradient (Paint_C, 3.0);
      Fill_Preserve (Cr);
      Set_Line_Width (Cr, 0.6);
      Color (0.0, 0.0, 0.0, 0.5);
      Stroke (Cr);
      --  the upper wing, with its struts and roundels
      New_Path (Cr);
      Round_Box (0.5, -Span, 6.0, 2.0 * Span, 2.0);
      Body_Gradient (Shade (Paint_C, 1.1), Span);
      Fill_Preserve (Cr);
      Color (0.0, 0.0, 0.0, 0.45);
      Stroke (Cr);
      for Side in -1 .. 1 loop
         if Side /= 0 then
            New_Path (Cr);
            Disc (3.5, Float (Side) * Span * 0.7, 2.2);
            Color (1.0, 1.0, 1.0);
            Fill (Cr);
            New_Path (Cr);
            Disc (3.5, Float (Side) * Span * 0.7, 1.1);
            Color (Shade (Paint_C, 0.5));
            Fill (Cr);
         end if;
      end loop;
      --  the pilot
      New_Path (Cr);
      Disc (-2.5, 0.0, 1.9);
      Color (0.35, 0.22, 0.12);
      Fill (Cr);
      --  the propeller, a blur
      New_Path (Cr);
      Save (Cr);
      Translate (Cr, 11.3, 0.0);
      Cairo.Scale (Cr, 1.0, 6.0);
      Arc (Cr, 0.0, 0.0, 1.0, 0.0, 2.0 * Pi);
      Restore (Cr);
      Color (0.9, 0.9, 0.9, 0.35);
      Fill (Cr);
      declare
         A : constant Float := Clock * 60.0;
      begin
         Set_Line_Width (Cr, 1.3);
         Color (0.15, 0.12, 0.1, 0.8);
         Move_To (Cr, 11.3, G (6.0 * Sin (A)));
         Line_To (Cr, 11.3, G (-6.0 * Sin (A)));
         Stroke (Cr);
      end;
      if Boosting then
         New_Path (Cr);
         Move_To (Cr, -11.0, -1.5);
         Line_To (Cr, -17.0, 0.0);
         Line_To (Cr, -11.0, 1.5);
         Close_Path (Cr);
         Color (1.0, 0.65, 0.15, 0.85);
         Fill (Cr);
      end if;
   end Plane_Body;

   --  A car at the origin pointing along X, in world units
   procedure Car_Body (Paint_C : RGB; Steer : Float; Braking, Boosting : Boolean; L : Car_Look) is
      Wheel_L : constant Float := (if L = Buggy_Look then 7.0 else 6.0);
      Wheel_W : constant Float := (if L = Buggy_Look then 4.2 else 3.2);
      Track_W : constant Float := (if L = Buggy_Look then 6.8 else 5.9);
      Body_W : constant Float := (if L = Buggy_Look then 10.0 else 11.0);
      Dark : constant RGB := Shade (Paint_C, 0.6);
   begin
      if L = Boat_Look then
         Boat_Body (Paint_C, Steer, Boosting);
         return;
      elsif L = Plane_Look then
         Plane_Body (Paint_C, Steer, Boosting);
         return;
      elsif L in Sport_Look | Cross_Look then
         Bike_Body (Paint_C, Steer, Braking, Boosting, L = Cross_Look);
         return;
      elsif L = Kart_Look then
         Kart_Body (Paint_C, Steer);
         return;
      elsif L = Tank_Look then
         Tank_Body (Paint_C, Steer);
         return;
      elsif L = Hover_Look then
         Hover_Body (Paint_C, Steer);
         return;
      elsif L = Sub_Look then
         Sub_Body (Paint_C, Steer);
         return;
      elsif L = Monster_Look then
         Monster_Body (Paint_C, Steer);
         return;
      elsif L = Rover_Look then
         Rover_Body (Paint_C, Steer);
         return;
      elsif L = Broom_Look then
         Broom_Body (Paint_C, Steer);
         return;
      elsif L = Egg_Look then
         Egg_Body (Paint_C, Steer);
         return;
      elsif L = Saucer_Look then
         Saucer_Body (Paint_C, Steer);
         return;
      elsif L = Snowmobile_Look then
         Snowmobile_Body (Paint_C, Steer);
         return;
      end if;
      --  The wheels
      for Front in Boolean loop
         for Side in -1 .. 1 loop
            if Side /= 0 then
               Save (Cr);
               Translate (Cr, G (if Front then 7.0 else -7.0), G (Float (Side) * Track_W));
               if Front then
                  Rotate (Cr, G (Steer * 0.45));
               end if;
               New_Path (Cr);
               Round_Box (-Wheel_L / 2.0, -Wheel_W / 2.0, Wheel_L, Wheel_W, 1.0);
               Color (0.07, 0.07, 0.08);
               Fill (Cr);
               Restore (Cr);
            end if;
         end loop;
      end loop;

      --  The body, lit from above
      declare
         P : constant Cairo_Pattern := Cairo.Pattern.Create_Linear (0.0, G (-Body_W / 2.0), 0.0, G (Body_W / 2.0));
         Light : constant RGB := Shade (Paint_C, 1.35);
      begin
         Cairo.Pattern.Add_Color_Stop_Rgb (P, 0.0, G (Dark.R), G (Dark.G), G (Dark.B));
         Cairo.Pattern.Add_Color_Stop_Rgb (P, 0.45, G (Light.R), G (Light.G), G (Light.B));
         Cairo.Pattern.Add_Color_Stop_Rgb (P, 1.0, G (Dark.R * 0.8), G (Dark.G * 0.8), G (Dark.B * 0.8));
         New_Path (Cr);
         case L is
            when Racer_Look =>
               --  low and long, a nose to a point
               Move_To (Cr, 12.5, 0.0);
               Curve_To (Cr, 12.5, -3.0, 10.0, G (-Body_W / 2.0), 6.0, G (-Body_W / 2.0));
               Line_To (Cr, -10.5, G (-Body_W / 2.0));
               Curve_To (Cr, -12.0, G (-Body_W / 2.0), -12.0, G (-Body_W / 2.0), -12.0, -3.0);
               Line_To (Cr, -12.0, 3.0);
               Curve_To (Cr, -12.0, G (Body_W / 2.0), -12.0, G (Body_W / 2.0), -10.5, G (Body_W / 2.0));
               Line_To (Cr, 6.0, G (Body_W / 2.0));
               Curve_To (Cr, 10.0, G (Body_W / 2.0), 12.5, 3.0, 12.5, 0.0);
               Close_Path (Cr);
            when others =>
               Round_Box (-11.5, -Body_W / 2.0, 23.0, Body_W, 3.2);
         end case;
         Set_Source (Cr, P);
         Fill_Preserve (Cr);
         Cairo.Pattern.Destroy (P);
         Set_Line_Width (Cr, 0.7);
         Color (0.0, 0.0, 0.0, 0.5);
         Stroke (Cr);
      end;

      case L is
         when Racer_Look =>
            --  stripes over the bonnet and roof
            New_Path (Cr);
            Rectangle (Cr, -11.0, -1.6, 23.0, 1.1);
            Rectangle (Cr, -11.0, 0.5, 23.0, 1.1);
            Color (1.0, 1.0, 1.0, 0.85);
            Fill (Cr);
            --  the cockpit
            New_Path (Cr);
            Move_To (Cr, 4.5, -3.6);
            Line_To (Cr, 1.0, -4.4);
            Line_To (Cr, -6.0, -4.2);
            Line_To (Cr, -6.0, 4.2);
            Line_To (Cr, 1.0, 4.4);
            Line_To (Cr, 4.5, 3.6);
            Close_Path (Cr);
            Color (0.10, 0.12, 0.16);
            Fill (Cr);
            New_Path (Cr);
            Round_Box (-4.5, -3.4, 4.8, 6.8, 1.5);
            Color (Shade (Paint_C, 1.1));
            Fill (Cr);
            --  the wing at the back
            New_Path (Cr);
            Rectangle (Cr, -12.5, -6.2, 2.4, 12.4);
            Color (0.08, 0.08, 0.1);
            Fill (Cr);
         when Buggy_Look =>
            --  open seat in a cage
            New_Path (Cr);
            Round_Box (-5.5, -3.6, 9.0, 7.2, 1.5);
            Color (0.12, 0.12, 0.13);
            Fill (Cr);
            Set_Line_Width (Cr, 1.1);
            Color (0.85, 0.85, 0.88);
            New_Path (Cr);
            Rectangle (Cr, -5.0, -4.2, 8.0, 8.4);
            Move_To (Cr, -5.0, -4.2);
            Line_To (Cr, 3.0, 4.2);
            Stroke (Cr);
            New_Path (Cr);
            Disc (-1.5, 0.0, 2.0);
            Color (Shade (Paint_C, 1.2));
            Fill (Cr);
            --  the bonnet's vents
            Set_Line_Width (Cr, 0.7);
            Color (0.0, 0.0, 0.0, 0.5);
            for K in 0 .. 2 loop
               Move_To (Cr, G (6.0 + Float (K) * 1.6), -2.5);
               Line_To (Cr, G (6.0 + Float (K) * 1.6), 2.5);
            end loop;
            Stroke (Cr);
         when Rally_Look =>
            --  a hatchback: glass all round, a roof with lamps on it
            New_Path (Cr);
            Round_Box (-7.5, -4.6, 13.0, 9.2, 2.2);
            Color (0.12, 0.14, 0.18);
            Fill (Cr);
            New_Path (Cr);
            Round_Box (-6.0, -3.9, 8.5, 7.8, 1.6);
            Color (Shade (Paint_C, 1.15));
            Fill (Cr);
            New_Path (Cr);
            Rectangle (Cr, -5.0, -1.0, 6.5, 2.0);
            Color (1.0, 1.0, 1.0, 0.9);
            Fill (Cr);
            for K in -1 .. 1 loop
               if K /= 0 then
                  New_Path (Cr);
                  Disc (3.2, Float (K) * 2.3, 1.0);
                  Color (1.0, 0.95, 0.6);
                  Fill (Cr);
               end if;
            end loop;
         when Boat_Look | Plane_Look | Sport_Look | Cross_Look | Kart_Look | Tank_Look | Hover_Look
            | Sub_Look | Monster_Look | Rover_Look | Broom_Look | Egg_Look | Saucer_Look
            | Snowmobile_Look => null;
      end case;

      --  Lamps
      for Side in -1 .. 1 loop
         if Side /= 0 then
            New_Path (Cr);
            Disc (11.0, Float (Side) * 3.4, 1.1);
            Color (1.0, 0.97, 0.75);
            Fill (Cr);
            New_Path (Cr);
            Rectangle (Cr, -12.2, G (Float (Side) * 3.6 - 1.0), 1.2, 2.0);
            if Braking then
               Color (1.0, 0.15, 0.1);
            else
               Color (0.5, 0.05, 0.05);
            end if;
            Fill (Cr);
         end if;
      end loop;
      if Boosting then
         New_Path (Cr);
         Move_To (Cr, -12.5, -2.5);
         Line_To (Cr, -19.0, 0.0);
         Line_To (Cr, -12.5, 2.5);
         Close_Path (Cr);
         Color (1.0, 0.65, 0.15, 0.85);
         Fill (Cr);
      end if;
   end Car_Body;

   procedure Car_Shadow (L : Car_Look) is
   begin
      New_Path (Cr);
      case L is
         when Plane_Look =>
            Round_Box (-11.0, -3.0, 22.0, 6.0, 2.5);
            Round_Box (-1.0, -14.0, 7.0, 28.0, 2.0);
            Round_Box (-12.0, -5.5, 3.5, 11.0, 1.0);
            Color (0.0, 0.0, 0.0, (if Tracks.Theme = Tracks.Sky then 0.12 else 0.22));
         when Sport_Look | Cross_Look =>
            Round_Box (-12.0, -4.0, 24.0, 8.0, 3.5);
            Color (0.0, 0.0, 0.0, 0.3);
         when Hover_Look =>
            Round_Box (-13.0, -8.0, 26.0, 16.0, 7.0);
            Color (0.0, 0.0, 0.0, 0.22);
         when Sub_Look =>
            Round_Box (-12.0, -5.5, 25.0, 11.0, 5.5);
            Color (0.0, 0.1, 0.15, 0.18);
         when Monster_Look =>
            Round_Box (-14.0, -12.5, 28.0, 25.0, 5.0);
            Color (0.0, 0.0, 0.0, 0.35);
         when Boat_Look =>
            Round_Box (-12.0, -7.0, 27.0, 14.0, 6.0);
            Color (0.0, 0.15, 0.25, 0.18);
         when others =>
            Round_Box (-13.0, -7.5, 26.0, 15.0, 4.0);
            Color (0.0, 0.0, 0.0, 0.32);
      end case;
      Fill (Cr);
   end Car_Shadow;

   procedure Draw_Car (Cr : Cairo.Cairo_Context; X, Y, Heading, Size : Float; Paint_N : Natural) is
      Keep : constant Cairo_Context := Scene.Cr;
   begin
      Scene.Cr := Cr;
      Save (Cr);
      Translate (Cr, G (X), G (Y));
      Scale (Cr, G (Size), G (Size));
      Save (Cr);
      Translate (Cr, 1.5, 2.5);
      Rotate (Cr, G (Heading));
      Car_Shadow (Look);
      Restore (Cr);
      Rotate (Cr, G (Heading));
      Car_Body (Paint (Paint_N), 0.0, False, False, Look);
      Restore (Cr);
      Scene.Cr := Keep;
   end Draw_Car;

   ---------------------------------------------------------------------------
   --  The frame
   ---------------------------------------------------------------------------

   type Wheel_Marks is array (1 .. 2) of Vec;
   Last_Wheels : array (Race.Car_Index) of Wheel_Marks;
   Had_Wheels : array (Race.Car_Index) of Boolean := (others => False);

   procedure New_Track is
   begin
      Art.Build;
      for P of Parts loop
         P.Life := 0.0;
      end loop;
      Had_Wheels := (others => False);
   end New_Track;

   procedure Leave_Marks (Dt : Float) is
      use Race;
   begin
      for I in 1 .. State.Count loop
         declare
            C : Cars.Car renames State.Racers (I).Car;
            F : constant Vec := Dir (C.H);
            R : constant Vec := Perp (F);
            Now : constant Wheel_Marks :=
              (if Tracks.Vehicle in Tracks.Bike_Kind then (C.P - F * 8.0, C.P - F * 8.0)
               else (C.P - F * 7.0 - R * 6.0, C.P - F * 7.0 + R * 6.0));
            On_Ground : constant Boolean := not C.Air and then not Cars.Falling (C);
            Rough : constant Boolean := C.Under in Tracks.Floor | Tracks.Sand;
            Strength : constant Float :=
              (if not On_Ground then 0.0
               elsif Rough and then Tracks.Theme /= Tracks.Workbench then
                  Float'Max (C.Slip, Float'Min (0.7, C.Speed / 300.0))
               elsif C.Slip > 0.12 then C.Slip
               else 0.0);
         begin
            if Had_Wheels (I) and then Strength > 0.0 then
               for K in 1 .. (if Tracks.Vehicle in Tracks.Bike_Kind then 1 else 2) loop
                  Art.Skid (Last_Wheels (I) (K), Now (K), Strength, C.Under);
               end loop;
            end if;
            Last_Wheels (I) := Now;
            if C.Boost_T > 0.0 and then Dt > 0.0 and then not Cars.Falling (C) then
               Spawn (Flame, C.P - F * 14.0, -F * 60.0 + R * (Spread (Rand) * 20.0),
                      0.18, 2.6, 0.0, (1.0, 0.6, 0.1));
            end if;
            Had_Wheels (I) := True;

            --  A boat's wake
            if Tracks.Vehicle = Tracks.Boat and then On_Ground and then Dt > 0.0 and then C.Speed > 25.0 then
               if Random (Rand) < 0.75 then
                  declare
                     Side : constant Float := (if Random (Rand) < 0.5 then -1.0 else 1.0);
                  begin
                     Spawn (Spray, C.P - F * 11.0 + R * (Side * 4.0),
                            R * (Side * (15.0 + C.Speed * 0.08)) - F * 10.0,
                            1.3, 1.8, 5.5, (0.96, 0.99, 1.0), 0.55 * Float'Min (1.0, C.Speed / 150.0));
                  end;
               end if;
               if C.Slip > 0.3 and then Random (Rand) < C.Slip then
                  Spawn (Spray, C.P + R * (if Random (Rand) < 0.5 then -7.0 else 7.0), -C.V * 0.1,
                         0.6, 2.0, 6.0, (0.96, 0.99, 1.0), 0.6);
               end if;
            end if;
            --  Smoke, dust and spray from the back wheels
            --  a submarine leaves a trail of bubbles
            if Tracks.Vehicle = Tracks.Submarine and then Dt > 0.0 and then C.Speed > 25.0
              and then Random (Rand) < 0.5
            then
               Spawn (Ring, C.P - F * 14.0 + R * (Spread (Rand) * 3.0), -F * 20.0 + R * (Spread (Rand) * 15.0),
                      0.9, 1.0 + Random (Rand) * 1.5, 2.0, (0.9, 1.0, 1.0), 0.7);
            end if;
            --  a rover and a monster truck throw up the dust
            if Tracks.Vehicle in Tracks.Rover | Tracks.Monster_Truck | Tracks.Snowmobile
              and then On_Ground and then Dt > 0.0
              and then C.Speed > 60.0 and then Random (Rand) < 0.5
            then
               Spawn (Dust, C.P - F * 12.0 + R * (Spread (Rand) * 6.0),
                      -F * (30.0 + Random (Rand) * 30.0) + R * (Spread (Rand) * 20.0),
                      (if Tracks.Vehicle = Tracks.Rover then 1.4 else 0.6), 2.0, 7.0,
                      Dust_Color (C.Under), 0.45);
            end if;
            --  a hovercraft blows up spray or sand round its skirt
            if Tracks.Vehicle = Tracks.Hovercraft and then Dt > 0.0 and then C.Speed > 30.0
              and then Random (Rand) < 0.6
            then
               Spawn ((if C.Under = Tracks.Water then Spray else Dust),
                      C.P - F * 12.0 + R * (Spread (Rand) * 8.0), -F * 30.0 + R * (Spread (Rand) * 40.0),
                      0.6, 2.0, 7.0,
                      (if C.Under = Tracks.Water then (0.92, 0.97, 1.0) else Dust_Color (C.Under)), 0.5);
            end if;
            --  a dirt bike throws the earth up behind it
            if Tracks.Vehicle = Tracks.Dirt_Bike and then On_Ground and then Dt > 0.0
              and then C.Speed > 60.0 and then C.Under /= Tracks.Water and then Random (Rand) < 0.5
            then
               Spawn (Dust, C.P - F * 10.0, -F * (40.0 + Random (Rand) * 50.0) + R * (Spread (Rand) * 25.0),
                      0.55, 1.6, 6.0, Dust_Color (C.Under), 0.55);
            end if;
            if On_Ground and then Dt > 0.0
              and then Tracks.Vehicle in Tracks.Car | Tracks.Bike_Kind | Tracks.Kart | Tracks.Tank
                | Tracks.Monster_Truck | Tracks.Rover | Tracks.Snowmobile
            then
               declare
                  K : constant Positive := (if Random (Rand) < 0.5 then 1 else 2);
                  Back : constant Vec := -C.V * 0.15 + Dir (Random (Rand) * 2.0 * Pi) * 12.0;
               begin
                  if C.Under = Tracks.Water and then C.Speed > 50.0 then
                     for N in 1 .. 2 loop
                        Spawn (Spray, Now (N), R * (Float (2 * N - 3) * (40.0 + Random (Rand) * 50.0)) - C.V * 0.2,
                               0.45, 1.8, 4.0, (0.85, 0.93, 1.0), 0.8);
                     end loop;
                  elsif Rough and then C.Speed > 70.0 and then Random (Rand) < 0.7 then
                     Spawn (Dust, Now (K), Back, 0.7, 2.5, 9.0, Dust_Color (C.Under), 0.45);
                  elsif C.Slip > 0.3 and then C.Speed > 40.0 and then Random (Rand) < C.Slip then
                     Spawn (Smoke, Now (K), Back,
                            0.8, 2.5, 10.0,
                            (if Tracks.Theme = Tracks.Ice then (0.95, 0.97, 1.0) else (0.85, 0.85, 0.88)),
                            0.35 * C.Slip);
                  end if;
                  if C.Boost_T > 0.0 and then False then
                     Spawn (Flame, C.P - F * 14.0, -F * 60.0 + R * (Spread (Rand) * 20.0),
                            0.18, 2.6, 0.0, (1.0, 0.6, 0.1));
                  end if;
               end;
            end if;
         end;
      end loop;
   end Leave_Marks;

   --  The things moving across the road
   procedure Draw_Mover (M : Tracks.Mover; P : Vec; Hd, Lift : Float) is
      use Tracks;
      R : constant Float := M.Radius;
      Sh : constant Vec := (3.0 + Lift * 0.5, 4.0 + Lift * 0.7);
      procedure Shadow_Disc (RX, RY : Float) is
      begin
         Save (Cr);
         Translate (Cr, G (P.X + Sh.X), G (P.Y + Sh.Y));
         Rotate (Cr, G (Hd));
         Cairo.Scale (Cr, G (RX), G (RY));
         New_Path (Cr);
         Arc (Cr, 0.0, 0.0, 1.0, 0.0, 2.0 * Pi);
         Restore (Cr);
         Color (0.0, 0.0, 0.0, 0.28);
         Fill (Cr);
      end Shadow_Disc;
      Spin : constant Float := Clock * 6.0;
   begin
      case M.Kind is
         when Train | Circle_Train =>
            null;
         when Paper_Plane | Bird | Bat =>
            Shadow_Disc (R, R * 0.5);
         when Ghost =>
            null;   --  a ghost casts no shadow
         when Sleigh =>
            Shadow_Disc (92.0, 19.0);
         when others =>
            Shadow_Disc (R, R);
      end case;
      Save (Cr);
      Translate (Cr, G (P.X), G (P.Y));
      Rotate (Cr, G (Hd));
      if M.Kind in Frog | Chicken | Bouncy_Ball | Astronaut | Bunny | Knight_Hop then
         Cairo.Scale (Cr, G (1.0 + Lift / 30.0), G (1.0 + Lift / 30.0));
      end if;
      case M.Kind is
         when Marble =>
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            Radial (0.0, 0.0, R, (0.75, 0.90, 1.0), (0.15, 0.35, 0.65));
            Fill (Cr);
            Set_Line_Width (Cr, 2.5);
            Color (0.95, 0.4, 0.2, 0.8);
            New_Path (Cr);
            Arc (Cr, 0.0, 0.0, G (R * 0.55), G (Spin), G (Spin + 2.2));
            Stroke (Cr);
            New_Path (Cr);
            Disc (-R * 0.35, -R * 0.35, R * 0.25);
            Color (1.0, 1.0, 1.0, 0.7);
            Fill (Cr);
         when Tennis_Ball | Pool_Ball =>
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            if M.Kind = Tennis_Ball then
               Radial (0.0, 0.0, R, (0.92, 1.0, 0.45), (0.60, 0.75, 0.10));
               Fill (Cr);
               Set_Line_Width (Cr, 1.6);
               Color (1.0, 1.0, 1.0, 0.9);
               New_Path (Cr);
               Arc (Cr, G (R * 0.9 * Cos (Spin)), 0.0, G (R * 0.7), G (Pi * 0.6), G (Pi * 1.4));
               Stroke (Cr);
            else
               Radial (0.0, 0.0, R, Shade (Paint (Natural (M.Phase * 3.0)), 1.4),
                       Shade (Paint (Natural (M.Phase * 3.0)), 0.6));
               Fill (Cr);
               New_Path (Cr);
               Disc (R * 0.3 * Cos (Spin), R * 0.3 * Sin (Spin * 0.7), R * 0.38);
               Color (1.0, 1.0, 1.0);
               Fill (Cr);
            end if;
            New_Path (Cr);
            Disc (-R * 0.4, -R * 0.4, R * 0.2);
            Color (1.0, 1.0, 1.0, 0.55);
            Fill (Cr);
         when Puck =>
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            Color (0.06, 0.06, 0.07);
            Fill (Cr);
            New_Path (Cr);
            Arc (Cr, 0.0, 0.0, G (R * 0.8), 0.0, 2.0 * Pi);
            Set_Line_Width (Cr, 1.0);
            Color (0.35, 0.35, 0.38);
            Stroke (Cr);
         when Frog =>
            for S in -1 .. 1 loop
               if S /= 0 then
                  New_Path (Cr);
                  Save (Cr);
                  Translate (Cr, G (-R * 0.6), G (Float (S) * R * 0.75));
                  Cairo.Scale (Cr, G (R * 0.6), G (R * 0.3));
                  Arc (Cr, 0.0, 0.0, 1.0, 0.0, 2.0 * Pi);
                  Restore (Cr);
                  Color (0.25, 0.55, 0.15);
                  Fill (Cr);
               end if;
            end loop;
            New_Path (Cr);
            Save (Cr);
            Cairo.Scale (Cr, G (R), G (R * 0.8));
            Arc (Cr, 0.0, 0.0, 1.0, 0.0, 2.0 * Pi);
            Restore (Cr);
            Radial (0.0, 0.0, R, (0.55, 0.85, 0.30), (0.20, 0.50, 0.12));
            Fill (Cr);
            for S in -1 .. 1 loop
               if S /= 0 then
                  New_Path (Cr);
                  Disc (R * 0.55, Float (S) * R * 0.4, R * 0.25);
                  Color (1.0, 1.0, 0.85);
                  Fill (Cr);
                  New_Path (Cr);
                  Disc (R * 0.62, Float (S) * R * 0.4, R * 0.12);
                  Color (0.05, 0.05, 0.05);
                  Fill (Cr);
               end if;
            end loop;
         when Chicken =>
            New_Path (Cr);
            Save (Cr);
            Cairo.Scale (Cr, G (R), G (R * 0.75));
            Arc (Cr, 0.0, 0.0, 1.0, 0.0, 2.0 * Pi);
            Restore (Cr);
            Radial (0.0, 0.0, R, (1.0, 1.0, 0.98), (0.80, 0.78, 0.72));
            Fill (Cr);
            New_Path (Cr);
            Disc (R * 0.75, 0.0, R * 0.45);
            Color (0.97, 0.97, 0.95);
            Fill (Cr);
            New_Path (Cr);
            Move_To (Cr, G (R * 1.1), G (-R * 0.15));
            Line_To (Cr, G (R * 1.5), 0.0);
            Line_To (Cr, G (R * 1.1), G (R * 0.15));
            Close_Path (Cr);
            Color (1.0, 0.6, 0.1);
            Fill (Cr);
            New_Path (Cr);
            Round_Box (R * 0.55, -R * 0.12, R * 0.4, R * 0.24, R * 0.1);
            Color (0.9, 0.1, 0.1);
            Fill (Cr);
            New_Path (Cr);
            Move_To (Cr, G (-R), 0.0);
            Line_To (Cr, G (-R * 1.4), G (-R * 0.35));
            Line_To (Cr, G (-R * 1.4), G (R * 0.35));
            Close_Path (Cr);
            Color (0.85, 0.83, 0.78);
            Fill (Cr);
         when Drifting_Duck =>
            New_Path (Cr);
            Save (Cr);
            Cairo.Scale (Cr, G (R), G (R * 0.78));
            Arc (Cr, 0.0, 0.0, 1.0, 0.0, 2.0 * Pi);
            Restore (Cr);
            Radial (0.0, 0.0, R, (1.0, 0.92, 0.35), (0.92, 0.70, 0.05));
            Fill (Cr);
            New_Path (Cr);
            Disc (R * 0.5, 0.0, R * 0.45);
            Radial (R * 0.5, 0.0, R * 0.45, (1.0, 0.95, 0.45), (0.95, 0.75, 0.1));
            Fill (Cr);
            New_Path (Cr);
            Move_To (Cr, G (R * 0.85), G (-R * 0.15));
            Line_To (Cr, G (R * 1.25), 0.0);
            Line_To (Cr, G (R * 0.85), G (R * 0.15));
            Close_Path (Cr);
            Color (1.0, 0.45, 0.08);
            Fill (Cr);
         when Paper_Plane =>
            New_Path (Cr);
            Move_To (Cr, G (R * 1.3), 0.0);
            Line_To (Cr, G (-R), G (-R));
            Line_To (Cr, G (-R * 0.6), 0.0);
            Close_Path (Cr);
            Color (1.0, 1.0, 1.0);
            Fill (Cr);
            New_Path (Cr);
            Move_To (Cr, G (R * 1.3), 0.0);
            Line_To (Cr, G (-R), G (R));
            Line_To (Cr, G (-R * 0.6), 0.0);
            Close_Path (Cr);
            Color (0.85, 0.87, 0.92);
            Fill (Cr);
         when Bird =>
            declare
               Flap : constant Float := 0.6 + 0.4 * Sin (Clock * 12.0 + M.Phase);
            begin
               New_Path (Cr);
               Move_To (Cr, G (R * 0.2), 0.0);
               Curve_To (Cr, 0.0, G (-R * 1.2 * Flap), G (-R * 0.5), G (-R * 2.0 * Flap), G (-R * 0.8), G (-R * 2.2 * Flap));
               Line_To (Cr, G (-R * 0.4), 0.0);
               Curve_To (Cr, G (-R * 0.5), G (R * 2.0 * Flap), 0.0, G (R * 1.2 * Flap), G (R * 0.2), 0.0);
               Color (0.55, 0.58, 0.62);
               Fill (Cr);
               New_Path (Cr);
               Save (Cr);
               Cairo.Scale (Cr, G (R), G (R * 0.35));
               Arc (Cr, 0.0, 0.0, 1.0, 0.0, 2.0 * Pi);
               Restore (Cr);
               Color (0.97, 0.97, 0.97);
               Fill (Cr);
               New_Path (Cr);
               Disc (R * 1.0, 0.0, R * 0.12);
               Color (1.0, 0.7, 0.1);
               Fill (Cr);
            end;
         when Robot =>
            New_Path (Cr);
            Round_Box (-R, -R * 0.8, 2.0 * R, 1.6 * R, 3.0);
            Radial (0.0, 0.0, R, (0.85, 0.87, 0.92), (0.45, 0.48, 0.55));
            Fill (Cr);
            for S in -1 .. 1 loop
               if S /= 0 then
                  New_Path (Cr);
                  Disc (R * 0.6, Float (S) * R * 0.35, R * 0.18);
                  Color (1.0, 0.3, 0.2);
                  Fill (Cr);
               end if;
            end loop;
            Save (Cr);
            Translate (Cr, G (-R * 1.1), 0.0);
            Rotate (Cr, G (Spin));
            Set_Line_Width (Cr, 2.0);
            Color (0.8, 0.65, 0.2);
            New_Path (Cr);
            Move_To (Cr, 0.0, G (-R * 0.5));
            Line_To (Cr, 0.0, G (R * 0.5));
            Stroke (Cr);
            Restore (Cr);
         when Crab =>
            Set_Line_Width (Cr, 1.6);
            Color (0.75, 0.25, 0.10);
            for S in -1 .. 1 loop
               if S /= 0 then
                  for L in 0 .. 2 loop
                     New_Path (Cr);
                     Move_To (Cr, G (-R * 0.4 + Float (L) * R * 0.4), G (Float (S) * R * 0.5));
                     Line_To (Cr, G (-R * 0.6 + Float (L) * R * 0.4 + Sin (Spin + Float (L)) * 2.0),
                              G (Float (S) * R * 1.3));
                     Stroke (Cr);
                  end loop;
                  New_Path (Cr);
                  Disc (R * 0.9, Float (S) * R * 0.9, R * 0.35);
                  Fill (Cr);
               end if;
            end loop;
            New_Path (Cr);
            Save (Cr);
            Cairo.Scale (Cr, G (R * 0.8), G (R));
            Arc (Cr, 0.0, 0.0, 1.0, 0.0, 2.0 * Pi);
            Restore (Cr);
            Radial (0.0, 0.0, R, (1.0, 0.55, 0.30), (0.75, 0.25, 0.10));
            Fill (Cr);
         when Fish =>
            declare
               Wag : constant Float := 0.5 * Sin (Clock * 10.0 + M.Phase);
            begin
               Save (Cr);
               Translate (Cr, G (-R * 0.9), 0.0);
               Rotate (Cr, G (Wag));
               New_Path (Cr);
               Move_To (Cr, 0.0, 0.0);
               Line_To (Cr, G (-R * 0.8), G (-R * 0.6));
               Line_To (Cr, G (-R * 0.6), 0.0);
               Line_To (Cr, G (-R * 0.8), G (R * 0.6));
               Close_Path (Cr);
               Color (1.0, 0.55, 0.15, 0.9);
               Fill (Cr);
               Restore (Cr);
               New_Path (Cr);
               Save (Cr);
               Cairo.Scale (Cr, G (R), G (R * 0.55));
               Arc (Cr, 0.0, 0.0, 1.0, 0.0, 2.0 * Pi);
               Restore (Cr);
               Radial (0.0, 0.0, R, (1.0, 0.75, 0.25), (0.95, 0.40, 0.05));
               Fill (Cr);
               New_Path (Cr);
               Disc (R * 0.55, -R * 0.2, R * 0.12);
               Color (0.05, 0.05, 0.05);
               Fill (Cr);
            end;
         when Mouse =>
            Set_Line_Width (Cr, 1.2);
            Color (0.55, 0.50, 0.50);
            New_Path (Cr);
            Move_To (Cr, G (-R), 0.0);
            Curve_To (Cr, G (-R * 1.6), G (R * 0.6), G (-R * 2.0), G (-R * 0.6), G (-R * 2.6), G (Sin (Clock * 8.0) * R * 0.4));
            Stroke (Cr);
            New_Path (Cr);
            Move_To (Cr, G (R * 1.1), 0.0);
            Curve_To (Cr, G (R * 0.6), G (-R * 0.7), G (-R), G (-R * 0.7), G (-R), 0.0);
            Curve_To (Cr, G (-R), G (R * 0.7), G (R * 0.6), G (R * 0.7), G (R * 1.1), 0.0);
            Radial (0.0, 0.0, R, (0.72, 0.70, 0.70), (0.42, 0.40, 0.40));
            Fill (Cr);
            for S in -1 .. 1 loop
               if S /= 0 then
                  New_Path (Cr);
                  Disc (R * 0.3, Float (S) * R * 0.45, R * 0.3);
                  Color (0.95, 0.70, 0.75);
                  Fill (Cr);
               end if;
            end loop;
         when Bouncy_Ball =>
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            Radial (0.0, 0.0, R, (1.0, 0.55, 0.85), (0.65, 0.10, 0.45));
            Fill (Cr);
            Set_Line_Width (Cr, 2.5);
            Color (1.0, 0.95, 0.3);
            New_Path (Cr);
            Arc (Cr, 0.0, 0.0, G (R * 0.65), G (Spin), G (Spin + Pi));
            Stroke (Cr);
         when RC_Car =>
            Save (Cr);
            Cairo.Scale (Cr, G (R / 12.0), G (R / 12.0));
            Car_Body ((0.90, 0.15, 0.10), 0.0, False, False, Racer_Look);
            Set_Line_Width (Cr, 0.8);
            Color (0.1, 0.1, 0.1);
            Move_To (Cr, -8.0, 4.0);
            Line_To (Cr, -16.0, 9.0);
            Stroke (Cr);
            Restore (Cr);
         when Rolling_Bauble =>
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            Radial (0.0, 0.0, R, (1.0, 0.55, 0.55), (0.60, 0.02, 0.05));
            Fill (Cr);
            New_Path (Cr);
            Rectangle (Cr, -3.0, G (-R - 3.0), 6.0, 4.0);
            Color (0.85, 0.75, 0.3);
            Fill (Cr);
            New_Path (Cr);
            Disc (-R * 0.4, -R * 0.4, R * 0.25);
            Color (1.0, 1.0, 1.0, 0.7);
            Fill (Cr);
         when Astronaut =>
            New_Path (Cr);
            Round_Box (-R * 0.9, -R * 0.7, R * 0.6, R * 1.4, 2.0);
            Color (0.85, 0.86, 0.90);
            Fill (Cr);
            New_Path (Cr);
            Disc (0.0, 0.0, R * 0.75);
            Radial (0.0, 0.0, R * 0.75, (1.0, 1.0, 1.0), (0.75, 0.76, 0.80));
            Fill (Cr);
            New_Path (Cr);
            Disc (R * 0.3, 0.0, R * 0.42);
            Radial (R * 0.3, 0.0, R * 0.42, (1.0, 0.85, 0.4), (0.70, 0.50, 0.10));
            Fill (Cr);
         when Bat =>
            declare
               Flap : constant Float := 0.5 + 0.5 * Sin (Clock * 16.0 + M.Phase);
            begin
               for S in -1 .. 1 loop
                  if S /= 0 then
                     New_Path (Cr);
                     Move_To (Cr, 0.0, 0.0);
                     Line_To (Cr, G (R * 0.6), G (Float (S) * R * 1.6 * Flap));
                     Line_To (Cr, G (R * 0.1), G (Float (S) * R * 1.1 * Flap));
                     Line_To (Cr, G (-R * 0.2), G (Float (S) * R * 1.6 * Flap));
                     Line_To (Cr, G (-R * 0.5), G (Float (S) * R * 0.9 * Flap));
                     Close_Path (Cr);
                     Color (0.10, 0.06, 0.12);
                     Fill (Cr);
                  end if;
               end loop;
               New_Path (Cr);
               Oval (R * 0.55, R * 0.3);
               Color (0.18, 0.10, 0.20);
               Fill (Cr);
               for S in -1 .. 1 loop
                  if S /= 0 then
                     New_Path (Cr);
                     Disc (R * 0.4, Float (S) * R * 0.12, 1.2);
                     Color (1.0, 0.2, 0.1);
                     Fill (Cr);
                  end if;
               end loop;
            end;
         when Bunny =>
            New_Path (Cr);
            Oval (R, R * 0.75);
            Radial (0.0, 0.0, R, (1.0, 1.0, 1.0), (0.80, 0.78, 0.76));
            Fill (Cr);
            New_Path (Cr);
            Disc (-R * 0.95, 0.0, R * 0.3);
            Color (1.0, 1.0, 1.0);
            Fill (Cr);
            New_Path (Cr);
            Disc (R * 0.75, 0.0, R * 0.45);
            Color (0.96, 0.95, 0.94);
            Fill (Cr);
            for S in -1 .. 1 loop
               if S /= 0 then
                  Save (Cr);
                  Translate (Cr, G (R * 0.35), G (Float (S) * R * 0.3));
                  Rotate (Cr, G (Float (S) * 0.35 + Pi));
                  New_Path (Cr);
                  Oval (R * 0.7, R * 0.16);
                  Color (0.98, 0.80, 0.85);
                  Fill (Cr);
                  Restore (Cr);
               end if;
            end loop;
         when Knight_Hop =>
            --  a white knight, leaping
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            Radial (0.0, 0.0, R, (1.0, 0.97, 0.88), (0.72, 0.66, 0.55));
            Fill (Cr);
            New_Path (Cr);
            Move_To (Cr, G (-R * 0.4), G (-R * 0.45));
            Curve_To (Cr, G (R * 0.2), G (-R * 0.7), G (R * 0.9), G (-R * 0.3), G (R * 0.75), G (R * 0.15));
            Line_To (Cr, G (R * 0.2), G (R * 0.2));
            Line_To (Cr, G (-R * 0.2), G (R * 0.5));
            Close_Path (Cr);
            Color (0.95, 0.90, 0.80);
            Fill_Preserve (Cr);
            Set_Line_Width (Cr, 1.0);
            Color (0.55, 0.50, 0.42);
            Stroke (Cr);
         when Blob =>
            declare
               Wob : constant Float := Sin (Clock * 5.0 + M.Phase);
            begin
               New_Path (Cr);
               for K in 0 .. 19 loop
                  declare
                     A : constant Float := Float (K) * Pi / 10.0;
                     RR : constant Float := R * (1.0 + 0.12 * Sin (A * 3.0 + Clock * 4.0) + 0.05 * Wob);
                  begin
                     Line_To (Cr, G (RR * Cos (A)), G (RR * Sin (A) * (1.0 - 0.1 * Wob)));
                  end;
               end loop;
               Close_Path (Cr);
               Radial (0.0, 0.0, R, (0.70, 1.0, 0.40), (0.20, 0.65, 0.10));
               Fill (Cr);
               for S in -1 .. 1 loop
                  if S /= 0 then
                     New_Path (Cr);
                     Disc (R * 0.4, Float (S) * R * 0.3, R * 0.18);
                     Color (1.0, 1.0, 1.0);
                     Fill (Cr);
                     New_Path (Cr);
                     Disc (R * 0.47, Float (S) * R * 0.3, R * 0.08);
                     Color (0.0, 0.0, 0.0);
                     Fill (Cr);
                  end if;
               end loop;
            end;
         when Ghost =>
            --  a sheet with a wavy hem trailing behind, see-through and flickering
            declare
               Fade : constant Float := 0.72 + 0.12 * Sin (Clock * 7.0 + M.Phase);
               Flap : constant Float := Clock * 6.0 + M.Phase;
            begin
               Push_Group (Cr);
               New_Path (Cr);
               Move_To (Cr, G (R * 0.9), 0.0);
               Curve_To (Cr, G (R * 0.9), G (-R * 1.1), G (-R * 0.3), G (-R * 1.1), G (-R * 0.5), G (-R * 0.9));
               for K in 0 .. 6 loop
                  declare
                     Y : constant Float := -R * 0.9 + Float (K) * R * 0.3;
                     X : constant Float := -R * 1.6 - (if K mod 2 = 0 then 0.0 else R * 0.35)
                       + R * 0.15 * Sin (Flap + Float (K));
                  begin
                     Line_To (Cr, G (X), G (Y));
                  end;
               end loop;
               Line_To (Cr, G (-R * 0.5), G (R * 0.9));
               Curve_To (Cr, G (-R * 0.3), G (R * 1.1), G (R * 0.9), G (R * 1.1), G (R * 0.9), 0.0);
               Close_Path (Cr);
               Radial (R * 0.3, 0.0, R * 1.6, (1.0, 1.0, 1.0), (0.78, 0.80, 0.92));
               Fill (Cr);
               for S in -1 .. 1 loop
                  if S /= 0 then
                     New_Path (Cr);
                     Save (Cr);
                     Translate (Cr, G (R * 0.45), G (Float (S) * R * 0.35));
                     Oval (R * 0.14, R * 0.2);
                     Restore (Cr);
                     Color (0.08, 0.05, 0.12);
                     Fill (Cr);
                  end if;
               end loop;
               New_Path (Cr);
               Save (Cr);
               Translate (Cr, G (R * 0.05), 0.0);
               Oval (R * 0.18, R * 0.24);
               Restore (Cr);
               Color (0.08, 0.05, 0.12);
               Fill (Cr);
               Pop_Group_To_Source (Cr);
               Paint_With_Alpha (Cr, G (Fade));
            end;
         when Penguin =>
            --  waddling, now and then down on its belly
            declare
               Waddle : constant Float := 0.25 * Sin (Clock * 12.0 + M.Phase);
            begin
               Rotate (Cr, G (Waddle));
               for S in -1 .. 1 loop
                  if S /= 0 then
                     New_Path (Cr);
                     Save (Cr);
                     Translate (Cr, G (-R * 0.1), G (Float (S) * R * 0.75));
                     Oval (R * 0.5, R * 0.18);
                     Restore (Cr);
                     Color (0.08, 0.08, 0.10);
                     Fill (Cr);
                  end if;
               end loop;
               New_Path (Cr);
               Oval (R * 0.95, R * 0.72);
               Color (0.08, 0.08, 0.10);
               Fill (Cr);
               New_Path (Cr);
               Save (Cr);
               Translate (Cr, G (R * 0.1), 0.0);
               Oval (R * 0.6, R * 0.45);
               Restore (Cr);
               Color (0.97, 0.97, 0.97);
               Fill (Cr);
               New_Path (Cr);
               Disc (R * 0.6, 0.0, R * 0.42);
               Color (0.08, 0.08, 0.10);
               Fill (Cr);
               New_Path (Cr);
               Move_To (Cr, G (R * 0.9), G (-R * 0.12));
               Line_To (Cr, G (R * 1.25), 0.0);
               Line_To (Cr, G (R * 0.9), G (R * 0.12));
               Close_Path (Cr);
               Color (1.0, 0.60, 0.10);
               Fill (Cr);
               for S in -1 .. 1 loop
                  if S /= 0 then
                     New_Path (Cr);
                     Disc (R * 0.7, Float (S) * R * 0.18, 1.3);
                     Color (1.0, 1.0, 1.0);
                     Fill (Cr);
                  end if;
               end loop;
            end;
         when Polar_Bear =>
            --  big, white and slow, its legs going
            declare
               Step : constant Float := Sin (Clock * 4.0 + M.Phase);
            begin
               for Leg in 0 .. 3 loop
                  declare
                     X : constant Float := (if Leg < 2 then R * 0.45 else -R * 0.5)
                       + (if Leg mod 2 = 0 then Step else -Step) * R * 0.15;
                     Y : constant Float := (if Leg mod 2 = 0 then -R * 0.5 else R * 0.5);
                  begin
                     New_Path (Cr);
                     Disc (X, Y, R * 0.2);
                     Color (0.85, 0.85, 0.80);
                     Fill (Cr);
                  end;
               end loop;
               New_Path (Cr);
               Oval (R * 0.85, R * 0.52);
               Radial (0.0, 0.0, R, (1.0, 1.0, 0.98), (0.80, 0.80, 0.74));
               Fill (Cr);
               New_Path (Cr);
               Disc (R * 0.95, 0.0, R * 0.32);
               Radial (R * 0.95, 0.0, R * 0.32, (1.0, 1.0, 0.98), (0.82, 0.82, 0.76));
               Fill (Cr);
               for S in -1 .. 1 loop
                  if S /= 0 then
                     New_Path (Cr);
                     Disc (R * 0.85, Float (S) * R * 0.25, R * 0.08);
                     Color (0.85, 0.85, 0.80);
                     Fill (Cr);
                  end if;
               end loop;
               New_Path (Cr);
               Disc (R * 1.25, 0.0, R * 0.07);
               Color (0.05, 0.05, 0.05);
               Fill (Cr);
            end;
         when Sleigh =>
            --  four reindeer in front, Rudolph leading, then Santa in his sleigh
            declare
               Gallop : constant Float := Sin (Clock * 14.0);
               procedure Reindeer (X, Y : Float; Rudolph : Boolean) is
               begin
                  New_Path (Cr);
                  Save (Cr);
                  Translate (Cr, G (X), G (Y));
                  Oval (11.0, 4.5);
                  Restore (Cr);
                  Color (0.50, 0.32, 0.18);
                  Fill (Cr);
                  New_Path (Cr);
                  Disc (X + 12.0, Y, 3.5);
                  Color (0.55, 0.36, 0.20);
                  Fill (Cr);
                  Set_Line_Width (Cr, 1.2);
                  Color (0.40, 0.28, 0.15);
                  for S in -1 .. 1 loop
                     if S /= 0 then
                        Move_To (Cr, G (X + 11.0), G (Y + Float (S) * 2.0));
                        Line_To (Cr, G (X + 8.0), G (Y + Float (S) * 7.0));
                        Line_To (Cr, G (X + 10.0), G (Y + Float (S) * 9.0));
                        Move_To (Cr, G (X + 8.5), G (Y + Float (S) * 6.0));
                        Line_To (Cr, G (X + 5.0), G (Y + Float (S) * 7.5));
                     end if;
                  end loop;
                  Stroke (Cr);
                  for Leg in -1 .. 1 loop
                     if Leg /= 0 then
                        New_Path (Cr);
                        Disc (X + Float (Leg) * 6.0 + Gallop * Float (Leg) * 2.0, Y + 4.5, 1.6);
                        Disc (X + Float (Leg) * 6.0 - Gallop * Float (Leg) * 2.0, Y - 4.5, 1.6);
                        Color (0.30, 0.20, 0.10);
                        Fill (Cr);
                     end if;
                  end loop;
                  New_Path (Cr);
                  Disc (X + 15.5, Y, (if Rudolph then 2.2 else 1.2));
                  if Rudolph then
                     Color (1.0, 0.10, 0.08);
                  else
                     Color (0.15, 0.10, 0.08);
                  end if;
                  Fill (Cr);
               end Reindeer;
            begin
               Cairo.Scale (Cr, 1.35, 1.35);
               --  the reins
               Set_Line_Width (Cr, 0.8);
               Color (0.85, 0.70, 0.25);
               for S in -1 .. 1 loop
                  if S /= 0 then
                     Move_To (Cr, -22.0, G (Float (S) * 5.0));
                     Line_To (Cr, 52.0, G (Float (S) * 7.0));
                  end if;
               end loop;
               Stroke (Cr);
               Reindeer (0.0, -7.0, False);
               Reindeer (0.0, 7.0, False);
               Reindeer (30.0, -7.0, False);
               Reindeer (30.0, 7.0, False);
               Reindeer (58.0, 0.0, True);
               --  the sleigh, its runners curling up at the front
               Set_Line_Width (Cr, 2.0);
               Color (0.85, 0.70, 0.25);
               for S in -1 .. 1 loop
                  if S /= 0 then
                     New_Path (Cr);
                     Move_To (Cr, -62.0, G (Float (S) * 13.0));
                     Line_To (Cr, -20.0, G (Float (S) * 13.0));
                     Curve_To (Cr, -14.0, G (Float (S) * 13.0), -14.0, G (Float (S) * 8.0), -18.0, G (Float (S) * 8.0));
                     Stroke (Cr);
                  end if;
               end loop;
               New_Path (Cr);
               Round_Box (-60.0, -11.0, 40.0, 22.0, 6.0);
               Body_Gradient ((0.85, 0.08, 0.08), 11.0);
               Fill_Preserve (Cr);
               Set_Line_Width (Cr, 1.5);
               Color (0.95, 0.80, 0.30);
               Stroke (Cr);
               --  the sack, full of presents
               New_Path (Cr);
               Disc (-52.0, 0.0, 9.0);
               Color (0.55, 0.38, 0.20);
               Fill (Cr);
               for K in 0 .. 2 loop
                  New_Path (Cr);
                  Rectangle (Cr, G (-56.0 + Float (K) * 3.0), G (-5.0 + Float (K) * 3.0), 4.0, 4.0);
                  Color (Paint (K + 2));
                  Fill (Cr);
               end loop;
               --  Santa: a red coat, a white beard, his hat with its bobble
               New_Path (Cr);
               Disc (-34.0, 0.0, 8.0);
               Radial (-34.0, 0.0, 8.0, (1.0, 0.25, 0.20), (0.70, 0.05, 0.05));
               Fill (Cr);
               New_Path (Cr);
               Disc (-30.0, 0.0, 4.5);
               Color (1.0, 1.0, 1.0);
               Fill (Cr);
               New_Path (Cr);
               Disc (-34.0, 0.0, 3.5);
               Color (0.85, 0.08, 0.08);
               Fill (Cr);
               New_Path (Cr);
               Disc (-37.0, 0.0, 1.8);
               Color (1.0, 1.0, 1.0);
               Fill (Cr);
            end;
         when Train | Circle_Train =>
            --  an engine and two carriages, end to end along its way
            for Part in 0 .. 2 loop
               declare
                  L : constant Float := Train_Length / 3.0;
                  X0 : constant Float := Train_Length * 0.5 - Float (Part + 1) * L + 2.0;
                  Col : constant RGB := (if Part = 0 then (0.80, 0.12, 0.10) else (0.15, 0.45, 0.25));
               begin
                  New_Path (Cr);
                  Round_Box (X0 + 4.0, -R + 5.0, L - 4.0, 2.0 * R, 3.0);
                  Color (0.0, 0.0, 0.0, 0.3);
                  Fill (Cr);
                  New_Path (Cr);
                  Round_Box (X0, -R, L - 4.0, 2.0 * R, 3.0);
                  Body_Gradient (Col, R);
                  Fill (Cr);
                  if Part = 0 then
                     New_Path (Cr);
                     Disc (X0 + L * 0.7, 0.0, R * 0.45);
                     Color (0.15, 0.15, 0.15);
                     Fill (Cr);
                     New_Path (Cr);
                     Rectangle (Cr, G (X0 + 3.0), G (-R * 0.7), G (L * 0.35), G (R * 1.4));
                     Color (0.2, 0.2, 0.25);
                     Fill (Cr);
                  else
                     for W in 0 .. 2 loop
                        New_Path (Cr);
                        Rectangle (Cr, G (X0 + 6.0 + Float (W) * (L - 14.0) / 3.0), G (-R * 0.5),
                                   G ((L - 20.0) / 3.0), G (R));
                        Color (0.95, 0.9, 0.6, 0.9);
                        Fill (Cr);
                     end loop;
                  end if;
               end;
            end loop;
      end case;
      Restore (Cr);
   end Draw_Mover;

   procedure Draw_Movers (High : Boolean; Dt : Float) is
   begin
      for K in 1 .. Tracks.Mover_Count loop
         declare
            M : constant Tracks.Mover := Tracks.Get_Mover (K);
            P : Vec;
            H, Lift : Float;
            Seen : Boolean;
         begin
            Tracks.Mover_At (M, Race.State.Clock, P, H, Seen, Lift);
            if Seen and then (Lift > 20.0) = High then
               if M.Kind = Tracks.Train then
                  --  the lights at the crossing flash while the train is near
                  declare
                     U : constant Vec := Normal (M.B - M.A);
                     Mid : constant Vec := (M.A + M.B) * 0.5;
                     Half : constant Float := Distance (M.A, M.B) * 0.5 - 260.0 + 14.0;
                     Near : constant Boolean := Distance (P, Mid) < Tracks.Train_Length * 0.5 + Half + 60.0;
                  begin
                     for E in -1 .. 1 loop
                        if E /= 0 then
                           for S in -1 .. 1 loop
                              if S /= 0 then
                                 declare
                                    Q : constant Vec := Mid + U * (Float (E) * Half) + Perp (U) * (Float (S) * 20.0);
                                    On : constant Boolean :=
                                      Near and then (Integer (Clock * 4.0) mod 2 = 0) = (S > 0);
                                 begin
                                    New_Path (Cr);
                                    Disc (Q.X, Q.Y, 4.5);
                                    Color (0.1, 0.1, 0.1);
                                    Fill (Cr);
                                    New_Path (Cr);
                                    Disc (Q.X, Q.Y, 3.0);
                                    if On then
                                       Color (1.0, 0.15, 0.1);
                                    else
                                       Color (0.35, 0.08, 0.06);
                                    end if;
                                    Fill (Cr);
                                 end;
                              end if;
                           end loop;
                        end if;
                     end loop;
                  end;
               end if;
               Draw_Mover (M, P, H, Lift);
               if M.Kind = Tracks.Sleigh and then Dt > 0.0 then
                  --  a trail of golden sparkles
                  Spawn (Confetti, P - Dir (H) * 62.0 + Perp (Dir (H)) * (Spread (Rand) * 12.0),
                         -Dir (H) * 30.0 + Dir (Random (Rand) * 2.0 * Pi) * 20.0,
                         0.9, 1.4, 0.0, (1.0, 0.85, 0.30));
               end if;
               if M.Kind in Tracks.Train | Tracks.Circle_Train and then Dt > 0.0 and then Random (Rand) < 0.5 then
                  Spawn (Smoke, P + Dir (H) * (Tracks.Train_Length * 0.5 - 15.0), Dir (Random (Rand) * 2.0 * Pi) * 15.0,
                         1.4, 4.0, 12.0, (0.92, 0.92, 0.95), 0.5);
               end if;
            end if;
         end;
      end loop;
   end Draw_Movers;

   --  The boxes, and the oil on the road
   procedure Draw_Pickups is
      use Race;
   begin
      for S of Slicks loop
         if S.Life > 0.0 then
            declare
               A : constant Float := Float'Min (1.0, S.Life / 2.0);
            begin
               Save (Cr);
               Translate (Cr, G (S.P.X), G (S.P.Y));
               New_Path (Cr);
               for K in 0 .. 11 loop
                  declare
                     An : constant Float := Float (K) * Pi / 6.0;
                     RR : constant Float := 14.0 + 3.0 * Sin (Float (K) * 2.7 + S.P.X);
                  begin
                     Line_To (Cr, G (RR * Cos (An)), G (RR * 0.8 * Sin (An)));
                  end;
               end loop;
               Close_Path (Cr);
               case Tracks.Theme is
                  when Tracks.Alien =>
                     --  green slime, glowing
                     Color (0.35, 0.95, 0.20, 0.85 * A);
                     Fill (Cr);
                     for K in 0 .. 3 loop
                        New_Path (Cr);
                        Disc (Float (K - 2) * 4.0, Float (K mod 2) * 4.0 - 2.0, 2.0 + Float (K mod 3));
                        Color (0.75, 1.0, 0.55, 0.7 * A);
                        Fill (Cr);
                     end loop;
                  when Tracks.Bath | Tracks.Fish_Tank =>
                     --  soap: foam, bubbles, and a sheen of colour
                     Color (0.97, 0.98, 1.0, 0.85 * A);
                     Fill (Cr);
                     for K in 0 .. 6 loop
                        New_Path (Cr);
                        Disc (8.0 * Cos (Float (K) * 0.9), 6.0 * Sin (Float (K) * 1.3), 2.0 + Float (K mod 3));
                        Set_Line_Width (Cr, 0.8);
                        Color (0.6, 0.75, 0.9, 0.8 * A);
                        Stroke (Cr);
                     end loop;
                     New_Path (Cr);
                     Disc (-3.0, -2.0, 4.0);
                     Color (1.0, 0.7, 0.95, 0.3 * A);
                     Fill (Cr);
                  when others =>
                     if Tracks.Vehicle = Tracks.Plane then
                        Color (0.25, 0.25, 0.28, 0.6 * A);   --  a cloud of black smoke in the air
                     else
                        Color (0.04, 0.04, 0.06, 0.85 * A);
                     end if;
                     Fill (Cr);
                     New_Path (Cr);
                     Disc (-4.0, -3.0, 4.0);
                     Color (0.6, 0.4, 0.9, 0.35 * A);
                     Fill (Cr);
                     New_Path (Cr);
                     Disc (3.0, 2.0, 3.0);
                     Color (0.3, 0.8, 0.7, 0.3 * A);
                     Fill (Cr);
               end case;
               Restore (Cr);
            end;
         end if;
      end loop;
      for K in 1 .. N_Boxes loop
         declare
            B : Box renames Boxes (K);
         begin
            if B.Active then
               Save (Cr);
               Translate (Cr, G (B.P.X + 3.0), G (B.P.Y + 4.0));
               Rotate (Cr, G (Clock * 1.5 + Float (K)));
               New_Path (Cr);
               Round_Box (-7.5, -7.5, 15.0, 15.0, 3.0);
               Color (0.0, 0.0, 0.0, 0.3);
               Fill (Cr);
               Restore (Cr);
               Save (Cr);
               Translate (Cr, G (B.P.X), G (B.P.Y + 1.5 * Sin (Clock * 4.0 + Float (K))));
               Rotate (Cr, G (Clock * 1.5 + Float (K)));
               New_Path (Cr);
               Round_Box (-7.5, -7.5, 15.0, 15.0, 3.0);
               declare
                  C1 : constant RGB := Paint (Natural (Clock * 2.0) + K);
               begin
                  Radial (0.0, 0.0, 10.0, Shade (C1, 1.5), Shade (C1, 0.8));
               end;
               Fill_Preserve (Cr);
               Set_Line_Width (Cr, 1.2);
               Color (1.0, 1.0, 1.0, 0.9);
               Stroke (Cr);
               Rotate (Cr, G (-(Clock * 1.5 + Float (K))));
               Select_Font_Face (Cr, "DejaVu Sans", Cairo_Font_Slant_Normal, Cairo_Font_Weight_Bold);
               Set_Font_Size (Cr, 12.0);
               Move_To (Cr, -3.6, 4.4);
               Color (1.0, 1.0, 1.0);
               Show_Text (Cr, "?");
               Restore (Cr);
            end if;
         end;
      end loop;
   end Draw_Pickups;

   procedure Draw_Rockets (Dt : Float) is
      use Race;
   begin
      for M of Rockets loop
         if M.Life > 0.0 then
            if Dt > 0.0 then
               Spawn (Smoke, M.P - Dir (M.H) * 6.0, Dir (M.H + Pi + Spread (Rand) * 0.3) * 30.0,
                      0.6, 2.0, 8.0, (0.85, 0.85, 0.88), 0.4);
            end if;
            Save (Cr);
            Translate (Cr, G (M.P.X), G (M.P.Y));
            Rotate (Cr, G (M.H));
            New_Path (Cr);
            Move_To (Cr, -6.0, -3.5);
            Line_To (Cr, -10.0, 0.0);
            Line_To (Cr, -6.0, 3.5);
            Close_Path (Cr);
            Color (1.0, 0.6 + 0.3 * Sin (Clock * 40.0), 0.1, 0.9);
            Fill (Cr);
            New_Path (Cr);
            Round_Box (-6.0, -1.8, 12.0, 3.6, 1.8);
            Color (0.92, 0.92, 0.95);
            Fill (Cr);
            New_Path (Cr);
            Rectangle (Cr, -6.0, -3.0, 2.5, 6.0);
            Color (0.85, 0.15, 0.1);
            Fill (Cr);
            Restore (Cr);
         end if;
      end loop;
   end Draw_Rockets;

   --  Night in the attic: dark everywhere, but for the headlights, the moonlight,
   --  and the glow of the boxes and the rockets
   procedure Draw_Night (Alpha : Float) is
      use Race;
      Spooky : constant Boolean := Tracks.Theme = Tracks.Halloween;
      procedure Glow (P : Vec; R, A : Float) is
         Pat : constant Cairo_Pattern := Cairo.Pattern.Create_Radial (G (P.X), G (P.Y), 0.0, G (P.X), G (P.Y), G (R));
      begin
         Cairo.Pattern.Add_Color_Stop_Rgba (Pat, 0.0, 0.0, 0.0, 0.0, G (A));
         Cairo.Pattern.Add_Color_Stop_Rgba (Pat, 1.0, 0.0, 0.0, 0.0, 0.0);
         Set_Source (Cr, Pat);
         New_Path (Cr);
         Disc (P.X, P.Y, R);
         Fill (Cr);
         Cairo.Pattern.Destroy (Pat);
      end Glow;
   begin
      Push_Group (Cr);
      if Spooky then
         Set_Source_Rgba (Cr, 0.04, 0.0, 0.08, 0.72);
      else
         Set_Source_Rgba (Cr, 0.0, 0.0, 0.03, 0.88);
      end if;
      Paint (Cr);
      Set_Operator (Cr, Cairo_Operator_Dest_Out);
      for I in 1 .. Tracks.Item_Count loop
         declare
            It : constant Tracks.Item := Tracks.Get_Item (I);
         begin
            if It.Kind = Tracks.Moonbeam then
               Glow (It.S.C, Float'Max (It.S.RX, It.S.RY) * 1.6, 0.8);
            elsif It.Kind in Tracks.Pumpkin | Tracks.Candle | Tracks.Cauldron then
               Glow (It.S.C, It.S.RX * 4.0, 0.85);
            end if;
         end;
      end loop;
      for I in 1 .. State.Count loop
         declare
            C : Cars.Car renames State.Racers (I).Car;
            P : constant Vec := Lerp (C.Prev_P, C.P, Alpha);
            F : constant Vec := Dir (C.H);
            R : constant Vec := Perp (F);
            Front : constant Vec := P + F * 11.0;
            Pat : constant Cairo_Pattern := Cairo.Pattern.Create_Radial
              (G (Front.X), G (Front.Y), 0.0, G (Front.X), G (Front.Y), 190.0);
         begin
            if Spooky then
               --  a broomstick has no lamps, but the witch is lit by the moon
               Glow (P, 55.0, 0.85);
            elsif not Cars.Falling (C) then
               --  the beams, wide and fading ahead of the car
               Cairo.Pattern.Add_Color_Stop_Rgba (Pat, 0.0, 0.0, 0.0, 0.0, 0.95);
               Cairo.Pattern.Add_Color_Stop_Rgba (Pat, 0.6, 0.0, 0.0, 0.0, 0.6);
               Cairo.Pattern.Add_Color_Stop_Rgba (Pat, 1.0, 0.0, 0.0, 0.0, 0.0);
               Set_Source (Cr, Pat);
               New_Path (Cr);
               declare
                  A : constant Vec := Front - R * 5.0;
                  B : constant Vec := Front + F * 190.0 - R * 85.0;
                  D : constant Vec := Front + F * 190.0 + R * 85.0;
                  E : constant Vec := Front + R * 5.0;
               begin
                  Move_To (Cr, G (A.X), G (A.Y));
                  Line_To (Cr, G (B.X), G (B.Y));
                  Line_To (Cr, G (D.X), G (D.Y));
                  Line_To (Cr, G (E.X), G (E.Y));
                  Close_Path (Cr);
               end;
               Fill (Cr);
               Glow (P, 38.0, 0.75);
            end if;
            Cairo.Pattern.Destroy (Pat);
         end;
      end loop;
      for K in 1 .. N_Boxes loop
         if Boxes (K).Active then
            Glow (Boxes (K).P, 24.0, 0.8);
         end if;
      end loop;
      for M of Rockets loop
         if M.Life > 0.0 then
            Glow (M.P, 50.0, 0.9);
         end if;
      end loop;
      for M in 1 .. Tracks.Mover_Count loop
         declare
            P : Vec;
            H, Lift : Float;
            Seen : Boolean;
         begin
            Tracks.Mover_At (Tracks.Get_Mover (M), State.Clock, P, H, Seen, Lift);
            if Seen then
               Glow (P, (if Tracks.Get_Mover (M).Kind = Tracks.Ghost then 60.0 else 28.0),
                     (if Tracks.Get_Mover (M).Kind = Tracks.Ghost then 0.8 else 0.45));
            end if;
         end;
      end loop;
      Pop_Group_To_Source (Cr);
      Paint (Cr);
      --  little reflectors on the tape, so the way can be seen
      for K in 0 .. (if Spooky then -1 else Tracks.Count - 1) loop
         if K mod 10 = 0 then
            for Side in -1 .. 1 loop
               if Side /= 0 then
                  declare
                     S : constant Tracks.Sample := Tracks.Get (K);
                     E : constant Vec := S.P + Perp (S.T) * (Float (Side) * (S.Width * 0.5 - 3.0));
                  begin
                     New_Path (Cr);
                     Disc (E.X, E.Y, 1.8);
                     Color (1.0, 0.85, 0.4, 0.55);
                     Fill (Cr);
                  end;
               end if;
            end loop;
         end if;
      end loop;
   end Draw_Night;

   procedure Draw (Cr : Cairo.Cairo_Context; W, H : Natural; Alpha, Dt : Float) is
      use Race;
      Z : constant Float := Float (H) / State.View_H;
      Jolt_X : constant Float := (if Shake > 0.0 then Spread (Rand) * Shake else 0.0);
      Jolt_Y : constant Float := (if Shake > 0.0 then Spread (Rand) * Shake else 0.0);
      Cam : constant Vec := Lerp (State.Prev_Cam, State.Cam, Alpha) + (Jolt_X, Jolt_Y);
      Ground : constant RGB := Art.Ground_Color;
      L : constant Car_Look := Look;

      type Order_Array is array (1 .. Max_Cars) of Car_Index;
      By_Height : Order_Array := (1, 2, 3, 4, 5, 6, 7, 8);
   begin
      Scene.Cr := Cr;
      Clock := Clock + Dt;
      Move_Particles (Dt);
      Leave_Marks (Dt);

      Set_Source_Rgb (Cr, G (Ground.R), G (Ground.G), G (Ground.B));
      Paint (Cr);

      Save (Cr);
      Translate (Cr, G (Float (W) / 2.0), G (Float (H) / 2.0));
      Scale (Cr, G (Z), G (Z));
      Translate (Cr, G (-Cam.X), G (-Cam.Y));

      --  The world
      Save (Cr);
      Scale (Cr, G (1.0 / Art.Scale), G (1.0 / Art.Scale));
      Set_Source_Surface (Cr, Art.World, 0.0, 0.0);
      Cairo.Pattern.Set_Filter
        (Get_Source (Cr),
         (if abs (Z / Art.Scale - 1.0) < 0.02 then Cairo.Pattern.Cairo_Filter_Fast
          else Cairo.Pattern.Cairo_Filter_Good));
      Paint (Cr);
      Restore (Cr);

      Draw_Particles (Above => False);
      Draw_Pickups;
      Draw_Movers (High => False, Dt => Dt);

      --  Lowest first: the cars falling, those on the ground, then those in the air
      for I in 2 .. State.Count loop
         for J in reverse 2 .. I loop
            declare
               A : Cars.Car renames State.Racers (By_Height (J - 1)).Car;
               B : Cars.Car renames State.Racers (By_Height (J)).Car;
               HA : constant Float := (if Cars.Falling (A) then -1.0 else A.Z);
               HB : constant Float := (if Cars.Falling (B) then -1.0 else B.Z);
            begin
               exit when HA <= HB;
               By_Height (J - 1 .. J) := (By_Height (J), By_Height (J - 1));
            end;
         end loop;
      end loop;

      if Ghost_On then
         Save (Cr);
         Translate (Cr, G (Ghost_P.X), G (Ghost_P.Y));
         Rotate (Cr, G (Ghost_H));
         Push_Group (Cr);
         Car_Body ((0.85, 0.92, 1.0), 0.0, False, False, L);
         Pop_Group_To_Source (Cr);
         Paint_With_Alpha (Cr, 0.4);
         Restore (Cr);
      end if;

      for N in 1 .. State.Count loop
         declare
            I : constant Car_Index := By_Height (N);
            R : Racer renames State.Racers (I);
            C : Cars.Car renames R.Car;
            P : constant Vec := Lerp (C.Prev_P, C.P, Alpha);
            Hd : constant Float := C.Prev_H + Wrap (C.H - C.Prev_H) * Alpha;
            Plane : constant Boolean := Tracks.Vehicle = Tracks.Plane;
            Lift : constant Float := C.Z + (if Plane then 46.0 else 0.0);
            Fall : constant Float := Clamp (C.Fall_T / 0.9, 0.0, 1.0);
            Size : constant Float :=
              (if Cars.Falling (C) then
                 (if Tracks.Theme = Tracks.Workbench then 1.0 - 0.75 * Fall else 1.0 - 0.45 * Fall)
               else (case L is
                        when Plane_Look => 1.15,
                        when Sport_Look | Cross_Look => 1.3,
                        when others => 1.0) + C.Z / 110.0);
            Ghost : constant Boolean := C.Ghost_T > 0.0 and then Integer (C.Ghost_T * 12.0) mod 2 = 0;
            Braking : constant Boolean := C.Forward > 20.0 and then C.Slip > 0.2;
         begin
            --  The shadow, further off the higher the car is
            if not Cars.Falling (C) then
               Save (Cr);
               Translate (Cr, G (P.X + 2.0 + Lift * 0.35), G (P.Y + 3.0 + Lift * 0.5));
               Rotate (Cr, G (Hd));
               Scale (Cr, G (1.0 - Lift / 400.0), G (1.0 - Lift / 400.0));
               Car_Shadow (L);
               Restore (Cr);
            end if;
            Save (Cr);
            Translate (Cr, G (P.X), G (P.Y));
            Rotate (Cr, G (Hd));
            Scale (Cr, G (Size), G (Size));
            if L = Boat_Look and then not Cars.Falling (C) then
               --  bobbing on the water
               Rotate (Cr, G (0.04 * Sin (Clock * 7.0 + Float (I))));
               Scale (Cr, G (1.0 + 0.02 * Sin (Clock * 9.0 + Float (I) * 2.0)), 1.0);
            end if;
            if Ghost or else Cars.Falling (C) then
               Push_Group (Cr);
            end if;
            Car_Body (Paint (R.Paint), C.Steer_S, Braking, C.Boost_T > 0.0, L);
            if R.Shield_T > 0.0 and then (R.Shield_T > 1.5 or else Integer (R.Shield_T * 10.0) mod 2 = 0) then
               New_Path (Cr);
               Disc (0.0, 0.0, 18.0 + 1.5 * Sin (Clock * 8.0));
               Set_Source_Rgba (Cr, 0.4, 0.85, 1.0, 0.22);
               Fill_Preserve (Cr);
               Set_Line_Width (Cr, 1.5);
               Set_Source_Rgba (Cr, 0.7, 0.95, 1.0, 0.8);
               Stroke (Cr);
            end if;
            if C.Spin_T > 0.0 then
               for K in 0 .. 2 loop
                  New_Path (Cr);
                  Disc (13.0 * Cos (Clock * 9.0 + Float (K) * 2.1), 13.0 * Sin (Clock * 9.0 + Float (K) * 2.1), 2.0);
                  Set_Source_Rgba (Cr, 1.0, 0.95, 0.3, 0.9);
                  Fill (Cr);
               end loop;
            end if;
            if Cars.Falling (C) then
               --  down into the dark, or under the water
               Pop_Group_To_Source (Cr);
               Paint_With_Alpha (Cr, G (1.0 - Fall * 0.9));
            elsif Ghost then
               Pop_Group_To_Source (Cr);
               Paint_With_Alpha (Cr, 0.45);
            end if;
            Restore (Cr);
         end;
      end loop;

      Draw_Rockets (Dt);
      Draw_Movers (High => True, Dt => Dt);
      Draw_Particles (Above => True);
      if Tracks.Theme in Tracks.Attic | Tracks.Halloween then
         Draw_Night (Alpha);
      end if;
      if Tracks.Theme = Tracks.Fish_Tank and then Dt > 0.0 then
         --  bubbles rising from the air stones
         for I in 1 .. Tracks.Item_Count loop
            if Tracks.Get_Item (I).Kind = Tracks.Air_Stone and then Random (Rand) < 0.6 then
               Spawn (Ring, Tracks.Get_Item (I).S.C + Dir (Random (Rand) * 2.0 * Pi) * (Random (Rand) * 14.0),
                      Dir (Random (Rand) * 2.0 * Pi) * 10.0, 1.2, 1.5 + Random (Rand) * 2.0, 3.0,
                      (0.9, 1.0, 1.0), 0.8);
            end if;
         end loop;
      end if;

      --  Which car is whose, when two share the screen or the race is about to start
      for I in 1 .. State.Count loop
         declare
            R : Racer renames State.Racers (I);
         begin
            if R.Human > 0 and then not State.Attract
              and then (State.Mode in Double | Duel | Net or else State.Phase = Countdown)
            then
               declare
                  P : constant Vec := Lerp (R.Car.Prev_P, R.Car.P, Alpha) - (0.0, 22.0 + R.Car.Z * 0.6);
               begin
                  New_Path (Cr);
                  Move_To (Cr, G (P.X), G (P.Y + 7.0));
                  Line_To (Cr, G (P.X - 5.0), G (P.Y));
                  Line_To (Cr, G (P.X + 5.0), G (P.Y));
                  Close_Path (Cr);
                  Color (Paint (R.Paint));
                  Fill_Preserve (Cr);
                  Set_Line_Width (Cr, 1.0);
                  Color (1.0, 1.0, 1.0);
                  Stroke (Cr);
                  Select_Font_Face (Cr, "DejaVu Sans", Cairo_Font_Slant_Oblique, Cairo_Font_Weight_Bold);
                  Set_Font_Size (Cr, 9.0);
                  Move_To (Cr, G (P.X - 6.0), G (P.Y - 2.0));
                  Color (1.0, 1.0, 1.0);
                  if State.Mode = Net then
                     declare
                        N : constant String := R.Name;
                        L : Natural := N'Last;
                     begin
                        while L > N'First and then N (L) = ' ' loop
                           L := L - 1;
                        end loop;
                        Move_To (Cr, G (P.X - 3.0 * Float (L - N'First + 1)), G (P.Y - 2.0));
                        Show_Text (Cr, N (N'First .. L));
                     end;
                  else
                     Show_Text (Cr, (if R.Human = 1 then "P1" else "P2"));
                  end if;
               end;
            end if;
         end;
      end loop;

      Restore (Cr);
   end Draw;

end Scene;
