--  Adamachines: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;

package body Cars is

   use Tracks;

   function Gravity return Float is (if Tracks.Vehicle = Rover then 280.0 else 900.0);   --  on the moon, little
   Min_Air_Speed : constant := 110.0;

   type Surface is record
      Grip  : Float;   --  the most the tyres turn the car's slide, units a second squared
      Top   : Float;   --  of the top speed
      Drag  : Float;   --  speed lost a second, as a part of it
   end record;

   function Surface_Of (M : Material) return Surface is
      T : constant Theme_Kind := Tracks.Theme;
   begin
      case Tracks.Vehicle_Of (T) is
         when Boat =>
            --  Boats slide wide; the foam and the bubbles hold them back
            return (case M is
                       when Road | Ramp | Boost | Void | Solid | Bump => (470.0, 0.95, 0.30),
                       when Floor => (400.0, 0.62, 0.90),
                       when Water => (190.0, 0.85, 0.25),
                       when Sand => (380.0, 0.42, 2.20));
         when Plane =>
            --  In the air: the course is calm, off it the air is rough
            return (case M is
                       when Road | Ramp | Boost | Void | Solid | Bump => (1250.0, 1.05, 0.10),
                       when Floor => (1000.0, 0.66, 0.50),
                       when Water => (330.0, 1.0, 0.10),    --  a gust blows you sideways
                       when Sand => (900.0, 0.45, 1.80));   --  into a cloud
         when Road_Bike =>
            --  quick and sure on the tarmac, lost off it
            return (case M is
                       when Road | Ramp | Boost | Void | Solid | Bump => (1080.0, 1.08, 0.12),
                       when Floor => (650.0, 0.52, 1.0),
                       when Water => (210.0, 0.8, 0.35),
                       when Sand => (520.0, 0.38, 2.5));
         when Dirt_Bike =>
            --  at home in the dirt, and not much slower on the grass
            return (case M is
                       when Road | Ramp | Boost | Void | Solid | Bump => (880.0, 1.0, 0.18),
                       when Floor => (760.0, 0.80, 0.45),
                       when Water => (300.0, 0.75, 0.6),
                       when Sand => (620.0, 0.55, 1.5));
         when Kart =>
            --  low and sticky: quick to turn, quick to spin
            return (case M is
                       when Road | Ramp | Boost | Void | Solid | Bump => (1350.0, 0.92, 0.18),
                       when Floor => (900.0, 0.66, 0.7),
                       when Water => (260.0, 0.8, 0.35),
                       when Sand => (650.0, 0.42, 2.2));
         when Tank =>
            --  slow, sure, and hardly troubled by what it drives over
            return (case M is
                       when Road | Ramp | Boost | Void | Solid | Bump => (1700.0, 0.70, 0.30),
                       when Floor => (1500.0, 0.64, 0.40),
                       when Water => (900.0, 0.60, 0.50),
                       when Sand => (1200.0, 0.52, 0.9));
         when Hovercraft =>
            --  on a cushion of air: it slides on everything, and water is no trouble
            return (case M is
                       when Road | Ramp | Boost | Void | Solid | Bump => (330.0, 1.0, 0.12),
                       when Water => (330.0, 1.04, 0.08),
                       when Floor => (300.0, 0.86, 0.30),
                       when Sand => (280.0, 0.70, 0.70));
         when Submarine =>
            --  slow and smooth through the water; weed and currents get hold of it
            return (case M is
                       when Road | Ramp | Boost | Void | Solid | Bump => (620.0, 0.85, 0.30),
                       when Floor => (520.0, 0.62, 0.80),
                       when Water => (240.0, 0.95, 0.20),
                       when Sand => (500.0, 0.40, 2.00));
         when Monster_Truck =>
            --  big wheels: little on the floor slows it, and it rolls over small things
            return (case M is
                       when Road | Ramp | Boost | Void | Solid | Bump => (1100.0, 0.86, 0.22),
                       when Floor => (1000.0, 0.80, 0.35),
                       when Water => (420.0, 0.75, 0.40),
                       when Sand => (900.0, 0.62, 1.00));
         when Rover =>
            --  on dust in low gravity: it floats, and slides a little
            return (case M is
                       when Road | Ramp | Boost | Void | Solid | Bump => (700.0, 0.92, 0.12),
                       when Floor => (560.0, 0.70, 0.50),
                       when Water => (300.0, 0.80, 0.30),
                       when Sand => (520.0, 0.45, 1.80));
         when Snowmobile =>
            --  at home in the snow; on ice its skis slide
            return (case M is
                       when Road | Ramp | Boost | Void | Solid | Bump => (950.0, 1.0, 0.15),
                       when Floor => (820.0, 0.86, 0.40),
                       when Water => (280.0, 1.0, 0.08),
                       when Sand => (700.0, 0.58, 1.20));
         when Tracks.Car =>
            null;
      end case;
      case M is
         when Road | Ramp | Boost =>
            return (case T is
                       when Workbench => (980.0, 1.0, 0.15),
                       when Ice => (430.0, 1.0, 0.08),
                       when others => (860.0, 1.0, 0.18));
         when Floor =>
            return (case T is
                       when Workbench => (760.0, 0.72, 0.6),
                       when Ice => (560.0, 0.5, 1.2),
                       when others => (620.0, 0.58, 0.9));
         when Water => return (230.0, 0.8, 0.35);
         when Sand => return (600.0, 0.4, 2.4);
         when Void | Solid | Bump => return (800.0, 1.0, 0.3);
      end case;
   end Surface_Of;

   function Road_Grip return Float is (Surface_Of (Road).Grip);

   procedure Place (C : in out Car; P : Vec; Heading : Float; Speed : Float := 0.0) is
      F : constant Float := C.Top_Factor;
   begin
      C := (P => P, V => Speed * Dir (Heading), H => Heading, Prev_P => P, Prev_H => Heading,
            Top_Factor => F, Speed => Speed, Forward => Speed, others => <>);
   end Place;

   --  The points round the body that meet what is in the way
   Body_Points : constant array (1 .. 8) of Vec :=
     ((12.0, -6.0), (12.0, 6.0), (-12.0, -6.0), (-12.0, 6.0),
      (12.0, 0.0), (-12.0, 0.0), (0.0, -6.0), (0.0, 6.0));

   function Blocks (M : Material) return Boolean is
     (M = Solid or else (M = Bump and then Tracks.Vehicle /= Monster_Truck));

   procedure Hit_Solids (C : in out Car) is
      F : constant Vec := Dir (C.H);
      R : constant Vec := Perp (F);
   begin
      for B of Body_Points loop
         declare
            Arm : constant Vec := F * B.X + R * B.Y;
            Pt : Vec := C.P + Arm;
         begin
            if Blocks (Material_At (Pt)) then
               --  The way out: towards the free cells round it
               declare
                  Sum : Vec := Zero;
                  N : Vec;
                  Vn : Float;
               begin
                  for K in 0 .. 11 loop
                     declare
                        D : constant Vec := Dir (Float (K) * Pi / 6.0);
                     begin
                        if not Blocks (Material_At (Pt + D * 5.0)) then
                           Sum := Sum + D;
                        end if;
                     end;
                  end loop;
                  N := Normal (Sum);
                  if N = Zero then
                     N := Normal (-Arm);
                  end if;
                  for Tries in 1 .. 12 loop
                     exit when not Blocks (Material_At (Pt));
                     C.P := C.P + N;
                     Pt := Pt + N;
                  end loop;
                  Vn := Dot (C.V, N);
                  if Vn < 0.0 then
                     declare
                        Vt : constant Vec := C.V - Vn * N;
                     begin
                        C.V := Vt * 0.85 - (0.35 * Vn) * N;
                        --  a knock on a corner turns the car a little
                        C.H := C.H + Clamp (Cross (Arm, N) * (-Vn) * 0.00012, -0.25, 0.25);
                        if -Vn > C.Bump then
                           C.Bump := -Vn;
                           C.Bump_At := Pt;
                        end if;
                     end;
                  end if;
               end;
            end if;
         end;
      end loop;
   end Hit_Solids;

   procedure Step (C : in out Car; Given : Controls; Dt : Float) is
      Input : Controls := Given;
      F, R, F0, R0 : Vec;
      Vf, Vr : Float;
      S : Surface;
      Top : Float;
   begin
      C.Prev_P := C.P;
      C.Prev_H := C.H;
      C.Bump := 0.0;
      C.Fell := False;
      C.Jumped := False;
      C.Landed := False;
      C.Boosted := False;
      C.Splashed := False;
      C.Ghost_T := Float'Max (0.0, C.Ghost_T - Dt);
      C.Slick_T := Float'Max (0.0, C.Slick_T - Dt);
      C.Scare_T := Float'Max (0.0, C.Scare_T - Dt);
      if C.Spin_T > 0.0 then
         --  knocked spinning: the controls do nothing till it stops
         C.Spin_T := Float'Max (0.0, C.Spin_T - Dt);
         Input := (others => 0.0);
         C.H := C.H + (4.0 + 10.0 * C.Spin_T) * Dt;
      end if;
      if C.Slick_T > 0.0 and then not C.Air then
         C.H := C.H + (if C.Steer_S < 0.0 then -1.6 else 1.6) * Dt;
      end if;
      C.Boost_T := Float'Max (0.0, C.Boost_T - Dt);

      --  Over the edge: it drops away, and the race puts it back
      if C.Fall_T > 0.0 then
         C.Fall_T := C.Fall_T + Dt;
         C.V := C.V * (1.0 - 2.5 * Dt);
         C.P := C.P + C.V * Dt;
         C.H := C.H + 2.0 * Dt;
         C.Speed := Length (C.V);
         C.Slip := 0.0;
         return;
      end if;

      if C.Air then
         C.Z := C.Z + C.Vz * Dt;
         C.Vz := C.Vz - Gravity * Dt;
         C.P := C.P + C.V * Dt;
         C.Steer_S := C.Steer_S + (Input.Steer - C.Steer_S) * Float'Min (1.0, 6.0 * Dt);
         C.H := C.H + C.Steer_S * 0.6 * Dt;
         C.Speed := Length (C.V);
         C.Slip := 0.0;
         if C.Z <= 0.0 then
            C.Z := 0.0;
            C.Vz := 0.0;
            C.Air := False;
            C.Landed := True;
            --  Landing turns the car's slide along where it points
            F := Dir (C.H);
            C.V := Dot (C.V, F) * F * 0.92 + (C.V - Dot (C.V, F) * F) * 0.5;
         else
            return;
         end if;
      end if;

      C.Under := Material_At (C.P);
      if C.Under = Void and then Tracks.Vehicle = Plane then
         C.Under := Floor;
      elsif C.Under = Ramp and then Tracks.Vehicle = Plane then
         C.Under := Road;
      end if;
      if C.Under = Void then
         C.Fall_T := Dt;
         C.Fell := True;
         return;
      end if;

      S := Surface_Of (C.Under);
      F := Dir (C.H);
      R := Perp (F);
      F0 := F;
      R0 := R;
      Vf := Dot (C.V, F);
      Vr := Dot (C.V, R);
      Top := Top_Speed * S.Top * C.Top_Factor * (if C.Boost_T > 0.0 then 1.35 else 1.0);

      --  The engine and the brakes
      if Input.Brake > 0.05 and then Vf > 8.0 then
         Vf := Float'Max (0.0, Vf - 760.0 * Input.Brake * Dt);
      elsif Input.Brake > 0.05 and then Input.Throttle < 0.05 then
         if Vf > -0.38 * Top then
            Vf := Vf - 320.0 * Input.Brake * Dt;
         end if;
      elsif Input.Throttle > 0.0 then
         if Vf < Top then
            Vf := Vf + (if Vf < 0.0 then 760.0 else 540.0 * (1.0 - 0.75 * Vf / Top))
              * (if Tracks.Vehicle = Tank then 0.65 else 1.0) * Input.Throttle * Dt;
         end if;
      end if;
      if Tracks.Vehicle = Plane and then not C.Held then
         --  a plane keeps flying: the brake only slows it, and never below this
         if Vf < Min_Air_Speed then
            Vf := Vf + (Min_Air_Speed - Vf) * Float'Min (1.0, 3.0 * Dt);
         end if;
      end if;
      if C.Boost_T > 0.0 then
         Vf := Vf + 500.0 * Dt;
      end if;
      --  Above what the surface allows it slows quickly; below, a little
      if Vf > Top then
         Vf := Vf - (Vf - Top) * 2.5 * Dt;
      end if;
      Vf := Vf * (1.0 - S.Drag * Dt * (if Input.Throttle > 0.05 then 0.25 else 1.0));

      --  Steering: it turns with speed, and the other way backwards
      C.Steer_S := C.Steer_S + (Input.Steer - C.Steer_S) * Float'Min (1.0, 9.0 * Dt);
      declare
         Grip_Speed : constant Float :=
           (case Tracks.Vehicle is
               when Tank => 1.0,                                    --  it turns on the spot
               when Hovercraft => Float'Min (1.0, 0.35 + abs Vf / 60.0),
               when Boat => Float'Min (1.0, abs Vf / 45.0),
               when others => Float'Min (1.0, abs Vf / 70.0));
         Rate : constant Float :=
           (case Tracks.Vehicle is
               when Tracks.Car => 3.7,
               when Boat => 3.2,
               when Plane => 3.0,
               when Road_Bike => 3.9,
               when Dirt_Bike => 3.8,
               when Kart => 4.4,
               when Tank => 2.4,
               when Hovercraft => 3.0,
               when Submarine => 2.8,
               when Monster_Truck => 3.2,
               when Rover => 3.4,
               when Snowmobile => 3.5)
           * Grip_Speed * (1.0 - 0.28 * Float'Min (1.0, abs Vf / Top_Speed));
      begin
         C.H := C.H + C.Steer_S * Rate * (if Vf < 0.0 then -1.0 else 1.0) * Dt;
      end;
      F := Dir (C.H);
      R := Perp (F);
      --  The old velocity seen along the new heading: the tyres take out
      --  what slides sideways, as far as their grip goes
      declare
         V : constant Vec := Vf * F0 + Vr * R0;
         Grip_Now : constant Float :=
           S.Grip * (if Input.Brake > 0.05 and then Vf > 40.0 then 0.7 else 1.0)
           * (if C.Slick_T > 0.0 or else C.Spin_T > 0.0 then 0.15 else 1.0) * Dt;
      begin
         Vf := Dot (V, F);
         Vr := Dot (V, R);
         if abs Vr <= Grip_Now then
            Vr := 0.0;
         else
            Vr := Vr - (if Vr > 0.0 then Grip_Now else -Grip_Now);
         end if;
         C.Slip := Clamp ((abs Vr - 6.0) / 70.0, 0.0, 1.0);
         if Input.Brake > 0.05 and then Vf > 60.0 then
            C.Slip := Float'Max (C.Slip, 0.5 * Input.Brake);
         end if;
      end;
      C.V := Vf * F + Vr * R;
      C.P := C.P + C.V * Dt;
      C.Speed := Length (C.V);
      C.Forward := Vf;

      Hit_Solids (C);
      --  a monster truck bounces up over the small things it rolls across
      if Tracks.Vehicle = Monster_Truck and then not C.Air and then C.Speed > 50.0
        and then Material_At (C.P + F * 9.0) = Bump
      then
         C.Air := True;
         C.Vz := 70.0 + 0.12 * C.Speed;
         C.Z := 0.5;
      end if;

      case C.Under is
         when Ramp =>
            if Vf > 40.0 then
               C.Air := True;
               C.Vz := (case Tracks.Vehicle is
                           when Dirt_Bike => 95.0 + 0.32 * Vf,
                           when Rover => 90.0 + 0.22 * Vf,       --  low gravity does the rest
                           when others => 160.0 + 0.5 * Vf);
               C.Z := 0.5;
               C.Jumped := True;
            end if;
         when Boost =>
            if C.Boost_T < 0.3 then
               C.Boosted := C.Boost_T <= 0.0;
               C.Boost_T := 0.8;
            end if;
         when Water =>
            C.Splashed := C.Speed > 50.0 and then Tracks.Vehicle in Tracks.Car | Bike_Kind;
         when others => null;
      end case;
   end Step;

   procedure Collide (A, B : in out Car) is
      Radius : constant Float := 6.6;
   begin
      if A.Air or else B.Air or else A.Fall_T > 0.0 or else B.Fall_T > 0.0
        or else A.Ghost_T > 0.0 or else B.Ghost_T > 0.0
        or else Distance (A.P, B.P) > Car_Length + 2.0
      then
         return;
      end if;
      for I in -1 .. 1 loop
         for J in -1 .. 1 loop
            if I /= 0 and then J /= 0 then
               declare
                  CA : constant Vec := A.P + Dir (A.H) * (Float (I) * 5.5);
                  CB : constant Vec := B.P + Dir (B.H) * (Float (J) * 5.5);
                  D : constant Float := Distance (CA, CB);
               begin
                  if D < 2.0 * Radius and then D > 0.01 then
                     declare
                        N : constant Vec := Normal (CB - CA);
                        Over : constant Float := 2.0 * Radius - D;
                        Rel : constant Float := Dot (B.V - A.V, N);
                     begin
                        A.P := A.P - N * (Over * 0.5);
                        B.P := B.P + N * (Over * 0.5);
                        if Rel < 0.0 then
                           declare
                              Imp : constant Float := -0.75 * Rel;
                           begin
                              A.V := A.V - N * Imp;
                              B.V := B.V + N * Imp;
                              --  and a little spin from where they meet
                              A.H := A.H + Clamp (Cross (CA - A.P, N) * Imp * 0.0004, -0.2, 0.2);
                              B.H := B.H - Clamp (Cross (CB - B.P, N) * Imp * 0.0004, -0.2, 0.2);
                              if -Rel > A.Bump then
                                 A.Bump := -Rel;
                                 A.Bump_At := (CA + CB) * 0.5;
                              end if;
                              if -Rel > B.Bump then
                                 B.Bump := -Rel;
                                 B.Bump_At := (CA + CB) * 0.5;
                              end if;
                           end;
                        end if;
                     end;
                  end if;
               end;
            end if;
         end loop;
      end loop;
   end Collide;

end Cars;
