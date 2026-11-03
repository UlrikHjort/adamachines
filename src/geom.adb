--  Adamachines: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;

package body Geom is

   function Length (A : Vec) return Float is (Sqrt (A.X * A.X + A.Y * A.Y));

   function Normal (A : Vec) return Vec is
      L : constant Float := Length (A);
   begin
      return (if L > 1.0E-6 then A / L else Zero);
   end Normal;

   function Dir (A : Float) return Vec is ((Cos (A), Sin (A)));

   function Angle_Of (A : Vec) return Float is
     (if A.X = 0.0 and then A.Y = 0.0 then 0.0 else Arctan (A.Y, A.X));

   function Wrap (A : Float) return Float is
      R : Float := A;
   begin
      while R > Pi loop
         R := R - 2.0 * Pi;
      end loop;
      while R < -Pi loop
         R := R + 2.0 * Pi;
      end loop;
      return R;
   end Wrap;

   function Random (S : in out Seed) return Float is
   begin
      S := S * 1664525 + 1013904223;
      return Float (S / 256) / 16777216.0;
   end Random;

   function Spread (S : in out Seed) return Float is (2.0 * Random (S) - 1.0);

end Geom;
