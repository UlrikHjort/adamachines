--  Adamachines: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Everything written over the race: places, laps and times, the
--  lights at the start, the standings, the map, the points of a duel,
--  and the title, pause and results screens.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Cairo;

package Hud is

   type Screen is (Title, Racing, Paused, Results, Options, Editor);

   type Item is record
      Label, Value : Unbounded_String;
      Arrows       : Boolean := False;   --  a choice changed with left and right
   end record;
   type Item_List is array (1 .. 12) of Item;
   type Points_Array is array (1 .. 6) of Natural;

   type Overlay is record
      Mode       : Screen := Title;
      Items      : Item_List;
      Item_Count : Natural := 0;
      Selected   : Positive := 1;
      Message    : Unbounded_String;
      Message_T  : Float := 0.0;      --  seconds it stays
      Hint       : Unbounded_String;  --  the keys, at the foot of a screen
      Hint2      : Unbounded_String;
      Record_Line : Unbounded_String; --  under the title's menu
      Record_Lap : Float := 0.0;      --  of the track raced
      New_Record : Boolean := False;
      --  A championship
      Champ       : Boolean := False;
      Champ_Round, Champ_Rounds : Natural := 0;
      Champ_Final : Boolean := False;
      Cup_Name    : Unbounded_String;
      Champ_Points : Points_Array := (others => 0);
      Fps        : Float := 0.0;
      Show_Fps   : Boolean := False;
      Clock      : Float := 0.0;      --  seconds since the start, for things that move
   end record;

   procedure Draw (Cr : Cairo.Cairo_Context; Width, Height : Natural; O : Overlay);

   procedure Track_Changed;
   --  A race was set up: the map is drawn again

   function Time_Of (T : Float) return String;   --  0:00.00
   function Ordinal (N : Positive) return String;

end Hud;
