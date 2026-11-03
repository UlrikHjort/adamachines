--  Adamachines: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The picture of the race, drawn every frame with cairo: the world
--  where the camera looks, the skid marks the cars leave on it, their
--  shadows, the cars themselves, and the smoke, dust, spray and sparks.

with Cairo;
with Art;
with Geom;
with Race;

package Scene is

   Shake : Float := 0.0;   --  the camera shaken, in world units

   --  The ghost of the best lap, in a time trial
   Ghost_On : Boolean := False;
   Ghost_P  : Geom.Vec;
   Ghost_H  : Float := 0.0;

   procedure New_Track;
   --  The world was set up again: paint its picture, forget the old smoke

   procedure Hear (E : Race.Event);
   --  Something happened: sparks, splashes and the like

   procedure Draw (Cr : Cairo.Cairo_Context; W, H : Natural; Alpha, Dt : Float);
   --  Alpha 0 .. 1: how far the race is between its last step and the next

   function Paint (N : Natural) return Art.RGB;   --  the colour of car paint N

   procedure Draw_Car (Cr : Cairo.Cairo_Context; X, Y, Heading, Size : Float; Paint_N : Natural);
   --  A car on its own, for the HUD and the menus; Size 1 is the car in the world

end Scene;
