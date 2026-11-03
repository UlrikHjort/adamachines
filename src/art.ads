--  Adamachines: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The picture of the world: the ground, the road and every thing on
--  it, painted once with cairo when a track is set up.  The textures
--  are made here too, from noise.  The cars leave their skid marks on
--  this picture, so they stay for the rest of the race.

with Cairo;
with Geom; use Geom;
with Tracks;

package Art is

   Scale : constant := 2.0;   --  pixels of the picture to a unit of the world

   procedure Build;
   --  Paints the world of the track loaded

   function World return Cairo.Cairo_Surface;

   procedure Skid (A, B : Vec; Strength : Float; Under : Tracks.Material);
   --  A mark on the ground from A to B, Strength 0 .. 1

   type RGB is record
      R, G, B : Float;
   end record;

   function Ground_Color return RGB;   --  round the world, past its edge

end Art;
