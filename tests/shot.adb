--  Adamachines: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  A picture of a race without a window:
--    shot TRACK SECONDS FILE.png [WIDTH HEIGHT [WHOLE]]
--  The AI races for SECONDS, then the frame is written.  With WHOLE
--  the picture is of the whole world, small.

with Ada.Command_Line; use Ada.Command_Line;
with Ada.Environment_Variables;
with Geom;
with Ada.Real_Time; use Ada.Real_Time;
with Ada.Text_IO;
with Cairo; use Cairo;
with Cairo.Image_Surface;
with Cairo.Png;
with Cairo.Surface;
with Glib; use Glib;
with Art;
with Hud;
with Race;
with Scene;
with Tracks;

procedure Shot is
   Id : constant Tracks.Track_Id := Tracks.Track_Id'Value (Argument (1));
   Seconds : constant Float := Float'Value (Argument (2));
   W : constant Natural := (if Argument_Count >= 4 then Natural'Value (Argument (4)) else 1280);
   H : constant Natural := (if Argument_Count >= 5 then Natural'Value (Argument (5)) else 720);
   Whole : constant Boolean := Argument_Count >= 6;
   Surf : Cairo_Surface;
   Cr : Cairo_Context;
   Seen : Natural;
   St : Cairo_Status;
begin
   Race.State.View_H := 520.0;
   Race.State.View_W := 520.0 * Float (W) / Float (H);
   Race.Setup (Id, Race.Single, 5, 3, Race.Normal);
   declare
      T0 : constant Time := Clock;
   begin
      Scene.New_Track;
      Ada.Text_IO.Put_Line ("Painted in" & Duration'Image (To_Duration (Clock - T0)));
   end;
   Seen := Race.Event_Serial;
   Surf := Cairo.Image_Surface.Create (Cairo.Image_Surface.Cairo_Format_ARGB32, Gint (W), Gint (H));
   Cr := Create (Surf);
   for K in 1 .. Natural (Seconds / Race.Dt) loop
      Race.Step ((others => <>), Autopilot => True);
      for E in Seen .. Race.Event_Serial - 1 loop
         Scene.Hear (Race.Events (E mod Race.Event_Ring));
      end loop;
      Seen := Race.Event_Serial;
      if K mod 2 = 0 then
         Scene.Draw (Cr, W, H, 1.0, 2.0 * Race.Dt);   --  the skids and smoke, as in the game
      end if;
   end loop;
   if Ada.Environment_Variables.Exists ("SHOT_SLICK") then
      --  a slick laid where the camera looks, to see how it is drawn
      declare
         use type Geom.Vec;
      begin
         Race.Slicks (1) := (Race.State.Cam + (-40.0, 0.0), 20.0, 0);
         Race.Slicks (2) := (Race.State.Cam + (40.0, 30.0), 20.0, 0);
      end;
   end if;
   if Ada.Environment_Variables.Exists ("SHOT_MOVER") and then Tracks.Mover_Count > 0 then
      --  the camera on the first thing that moves
      declare
         P : Geom.Vec;
         H, L : Float;
         Seen : Boolean;
      begin
         Tracks.Mover_At (Tracks.Get_Mover (1), Race.State.Clock, P, H, Seen, L);
         Race.State.Cam := P;
         Race.State.Prev_Cam := P;
      end;
   end if;
   if Whole then
      declare
         S : constant Float := Float'Min (Float (W) / Tracks.Width, Float (H) / Tracks.Height) / Art.Scale;
      begin
         Set_Source_Rgb (Cr, 0.0, 0.0, 0.0);
         Paint (Cr);
         Scale (Cr, Gdouble (S), Gdouble (S));
         Set_Source_Surface (Cr, Art.World, 0.0, 0.0);
         Paint (Cr);
      end;
   elsif Ada.Environment_Variables.Exists ("SHOT_FRAMES") then
      --  a run of frames, thirty a second, with the HUD, for animations:
      --  FILE is then the start of each frame's name
      declare
         Frames : constant Positive := Positive'Value (Ada.Environment_Variables.Value ("SHOT_FRAMES"));
         O : Hud.Overlay;
      begin
         O.Mode := Hud.Racing;
         for F in 1 .. Frames loop
            for K in 1 .. 4 loop
               Race.Step ((others => <>), Autopilot => True);
               for E in Seen .. Race.Event_Serial - 1 loop
                  Scene.Hear (Race.Events (E mod Race.Event_Ring));
               end loop;
               Seen := Race.Event_Serial;
            end loop;
            O.Clock := Float (F) / 30.0;
            Scene.Draw (Cr, W, H, 1.0, 4.0 * Race.Dt);
            Hud.Draw (Cr, W, H, O);
            Cairo.Surface.Flush (Surf);
            declare
               N : constant String := Natural'Image (10_000 + F);
            begin
               St := Cairo.Png.Write_To_Png (Surf, Argument (3) & N (N'First + 2 .. N'Last) & ".png");
            end;
         end loop;
      end;
   else
      declare
         T0 : constant Time := Clock;
      begin
         for K in 1 .. 20 loop
            Scene.Draw (Cr, W, H, 1.0, Race.Dt);
         end loop;
         Ada.Text_IO.Put_Line ("A frame in" & Duration'Image (To_Duration (Clock - T0) / 20));
      end;
   end if;
   Cairo.Surface.Flush (Surf);
   St := Cairo.Png.Write_To_Png (Surf, Argument (3));
   Ada.Text_IO.Put_Line ("Wrote " & Argument (3) & " " & St'Image);
end Shot;
