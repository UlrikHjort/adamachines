--  Adamachines: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Two dimensional vectors.  The world is seen from above: X runs to the
--  right and Y down the screen, so a heading A points along (cos A, sin A)
--  and a positive turn is clockwise on the screen.

package Geom is

   Pi : constant := 3.14159_26535_89793;

   type Vec is record
      X, Y : Float := 0.0;
   end record;

   Zero : constant Vec := (0.0, 0.0);

   function "+" (A, B : Vec) return Vec is ((A.X + B.X, A.Y + B.Y));
   function "-" (A, B : Vec) return Vec is ((A.X - B.X, A.Y - B.Y));
   function "-" (A : Vec) return Vec is ((-A.X, -A.Y));
   function "*" (S : Float; A : Vec) return Vec is ((S * A.X, S * A.Y));
   function "*" (A : Vec; S : Float) return Vec is ((S * A.X, S * A.Y));
   function "/" (A : Vec; S : Float) return Vec is ((A.X / S, A.Y / S));

   function Dot (A, B : Vec) return Float is (A.X * B.X + A.Y * B.Y);
   function Cross (A, B : Vec) return Float is (A.X * B.Y - A.Y * B.X);
   function Length (A : Vec) return Float;
   function Normal (A : Vec) return Vec;        --  unit length, or zero
   function Perp (A : Vec) return Vec is ((-A.Y, A.X));   --  a quarter turn clockwise
   function Dir (A : Float) return Vec;         --  the unit vector at heading A
   function Angle_Of (A : Vec) return Float;
   function Lerp (A, B : Vec; T : Float) return Vec is (A + T * (B - A));
   function Distance (A, B : Vec) return Float is (Length (A - B));

   function Clamp (X, Lo, Hi : Float) return Float is
     (if X < Lo then Lo elsif X > Hi then Hi else X);
   function Wrap (A : Float) return Float;      --  an angle in -Pi .. Pi
   function Mix (A, B, T : Float) return Float is (A + (B - A) * T);

   --  A small deterministic random generator, so every race looks the same
   type Seed is mod 2**32;
   function Random (S : in out Seed) return Float;   --  0 .. 1
   function Spread (S : in out Seed) return Float;   --  -1 .. 1

end Geom;
