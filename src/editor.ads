--  Adamachines: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The track editor, worked from the keyboard: the control points of
--  "My track" are chosen, moved, added and taken away, the road made
--  wider or narrower and the place changed, and the track is kept in
--  ~/.adamachines/custom.trk.

with Cairo;
with Gdk.Types;
with Tracks;

package Editor is

   procedure Load;   --  the saved tracks; slot 1 opened
   procedure Save;   --  the track in the editor, into its slot

   procedure Open (S : Tracks.Custom_Slot);   --  a slot into the editor
   function Current return Tracks.Custom_Slot;

   type Action is (None, Test_Drive, Leave);

   procedure Key (K : Gdk.Types.Gdk_Key_Type; Shift : Boolean; Result : out Action);

   procedure Draw (Cr : Cairo.Cairo_Context; W, H : Natural; Clock : Float);

end Editor;
