--  Adamachines: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
with Cairo; use Cairo;
with Glib; use Glib;
with Gtkada.Types;
with Art;
with Geom;
with Race; use Race;
with Scene;
with Tracks;

package body Hud is

   Pi : constant := Geom.Pi;

   Cr : Cairo_Context := Null_Context;
   Scale : Float := 1.0;   --  1 at 1080 lines
   Sw, Sh : Float := 1.0;

   function D (X : Float) return Gdouble is (Gdouble (X * Scale));
   function G (X : Float) return Gdouble is (Gdouble (X));

   ---------------------------------------------------------------------------
   --  Small helpers
   ---------------------------------------------------------------------------

   procedure Color (R, Gr, B : Float; A : Float := 1.0) is
   begin
      Set_Source_Rgba (Cr, G (R), G (Gr), G (B), G (A));
   end Color;

   procedure Color (C : Art.RGB; A : Float := 1.0) is
   begin
      Set_Source_Rgba (Cr, G (C.R), G (C.G), G (C.B), G (A));
   end Color;

   procedure Font (Size : Float; Italic : Boolean := True; Bold : Boolean := True) is
   begin
      Select_Font_Face (Cr, "DejaVu Sans",
                        (if Italic then Cairo_Font_Slant_Oblique else Cairo_Font_Slant_Normal),
                        (if Bold then Cairo_Font_Weight_Bold else Cairo_Font_Weight_Normal));
      Set_Font_Size (Cr, D (Size));
   end Font;

   function Width_Of (S : String) return Float is
      P : Gtkada.Types.Chars_Ptr := Gtkada.Types.New_String (S);
      E : aliased Cairo_Text_Extents;
   begin
      Text_Extents (Cr, P, E'Access);
      Gtkada.Types.Free (P);
      return Float (E.X_Advance);
   end Width_Of;

   --  Text with its base line at Y; Align -1 left, 0 middle, 1 right
   procedure Text (S : String; X, Y : Float; Align : Integer := -1; Shadow : Boolean := True) is
      W : constant Float := Width_Of (S);
      X0 : constant Float := (case Align is when -1 => X, when 0 => X - W / 2.0, when others => X - W);
   begin
      if Shadow then
         Save (Cr);
         Set_Source_Rgba (Cr, 0.0, 0.0, 0.0, 0.6);
         Move_To (Cr, G (X0 + 2.5 * Scale), G (Y + 2.5 * Scale));
         Show_Text (Cr, S);
         Restore (Cr);
      end if;
      Move_To (Cr, G (X0), G (Y));
      Show_Text (Cr, S);
   end Text;

   --  Big letters with a dark edge round them
   procedure Outlined (S : String; X, Y : Float; Align : Integer; Fill_C : Art.RGB; Edge : Float) is
      W : constant Float := Width_Of (S);
      X0 : constant Float := (case Align is when -1 => X, when 0 => X - W / 2.0, when others => X - W);
   begin
      New_Path (Cr);
      Move_To (Cr, G (X0 + 4.0 * Scale), G (Y + 5.0 * Scale));
      Text_Path (Cr, S);
      Color (0.0, 0.0, 0.0, 0.45);
      Fill (Cr);
      New_Path (Cr);
      Move_To (Cr, G (X0), G (Y));
      Text_Path (Cr, S);
      Set_Line_Width (Cr, D (Edge));
      Set_Line_Join (Cr, Cairo_Line_Join_Round);
      Color (0.06, 0.05, 0.10);
      Stroke_Preserve (Cr);
      Color (Fill_C);
      Fill (Cr);
   end Outlined;

   procedure Rounded (X, Y, W, H, R : Float) is
   begin
      New_Path (Cr);
      Arc (Cr, G (X + W - R), G (Y + R), G (R), G (-Pi / 2.0), 0.0);
      Arc (Cr, G (X + W - R), G (Y + H - R), G (R), 0.0, G (Pi / 2.0));
      Arc (Cr, G (X + R), G (Y + H - R), G (R), G (Pi / 2.0), G (Pi));
      Arc (Cr, G (X + R), G (Y + R), G (R), G (Pi), G (3.0 * Pi / 2.0));
      Close_Path (Cr);
   end Rounded;

   procedure Panel (X, Y, W, H : Float; A : Float := 0.55) is
   begin
      Rounded (X, Y, W, H, 12.0 * Scale);
      Color (0.04, 0.04, 0.08, A);
      Fill_Preserve (Cr);
      Set_Line_Width (Cr, D (2.0));
      Color (1.0, 1.0, 1.0, 0.12);
      Stroke (Cr);
   end Panel;

   function Img (N : Integer) return String is
      S : constant String := Integer'Image (N);
   begin
      return (if N >= 0 then S (S'First + 1 .. S'Last) else S);
   end Img;

   function Two (N : Natural) return String is
     (if N < 10 then "0" & Img (N) else Img (N));

   function Time_Of (T : Float) return String is
      Cs : constant Natural := Natural (Float'Max (0.0, T) * 100.0);
   begin
      return Img (Cs / 6000) & ":" & Two ((Cs / 100) mod 60) & "." & Two (Cs mod 100);
   end Time_Of;

   function Ordinal (N : Positive) return String is
     (Img (N) & (case N is
                    when 1 => "ST", when 2 => "ND", when 3 => "RD", when others => "TH"));

   function Trimmed (S : String) return String is
      L : Natural := S'Last;
   begin
      while L >= S'First and then S (L) = ' ' loop
         L := L - 1;
      end loop;
      return S (S'First .. L);
   end Trimmed;

   Yellow : constant Art.RGB := (1.0, 0.84, 0.15);
   White : constant Art.RGB := (1.0, 1.0, 1.0);

   ---------------------------------------------------------------------------
   --  The map
   ---------------------------------------------------------------------------

   Loads : Natural := 0;
   procedure Track_Changed is
   begin
      Loads := Loads + 1;
   end Track_Changed;

   procedure Minimap (X0, Y0, Box_W, Box_H : Float) is
      S : constant Float := Float'Min (Box_W / Tracks.Width, Box_H / Tracks.Height);
      OX : constant Float := X0 + (Box_W - Tracks.Width * S) / 2.0;
      OY : constant Float := Y0 + (Box_H - Tracks.Height * S) / 2.0;
      function MX (X : Float) return Gdouble is (G (OX + X * S));
      function MY (Y : Float) return Gdouble is (G (OY + Y * S));
   begin
      Panel (X0 - 10.0 * Scale, Y0 - 10.0 * Scale, Box_W + 20.0 * Scale, Box_H + 20.0 * Scale, 0.45);
      New_Path (Cr);
      for K in 0 .. Tracks.Count - 1 loop
         if K mod 3 = 0 then
            Line_To (Cr, MX (Tracks.Get (K).P.X), MY (Tracks.Get (K).P.Y));
         end if;
      end loop;
      Close_Path (Cr);
      Set_Line_Join (Cr, Cairo_Line_Join_Round);
      Set_Line_Width (Cr, D (7.0));
      Color (1.0, 1.0, 1.0, 0.25);
      Stroke_Preserve (Cr);
      Set_Line_Width (Cr, D (3.0));
      Color (1.0, 1.0, 1.0, 0.7);
      Stroke (Cr);
      --  the line
      declare
         P : constant Geom.Vec := Tracks.Get (0).P;
      begin
         New_Path (Cr);
         Arc (Cr, MX (P.X), MY (P.Y), D (4.0), 0.0, 2.0 * Pi);
         Color (0.1, 0.1, 0.1);
         Fill (Cr);
      end;
      for K in reverse 1 .. State.Count loop
         declare
            I : constant Car_Index := In_Place (K);
            P : constant Geom.Vec := State.Racers (I).Car.P;
            Big : constant Boolean := State.Racers (I).Human > 0;
         begin
            New_Path (Cr);
            Arc (Cr, MX (P.X), MY (P.Y), D (if Big then 7.0 else 5.0), 0.0, 2.0 * Pi);
            Color (Scene.Paint (State.Racers (I).Paint));
            Fill_Preserve (Cr);
            Set_Line_Width (Cr, D (1.5));
            Color (0.0, 0.0, 0.0, 0.8);
            Stroke (Cr);
         end;
      end loop;
   end Minimap;

   ---------------------------------------------------------------------------
   --  The race
   ---------------------------------------------------------------------------

   procedure Icon (W : Weapon; CX, CY, S : Float) is
   begin
      Set_Line_Width (Cr, D (4.0));
      case W is
         when None => null;
         when Turbo =>
            Color (1.0, 0.6, 0.1);
            for K in 0 .. 1 loop
               declare
                  X : constant Float := CX - S * 0.35 + Float (K) * S * 0.4;
               begin
                  New_Path (Cr);
                  Move_To (Cr, G (X), G (CY - S * 0.4));
                  Line_To (Cr, G (X + S * 0.35), G (CY));
                  Line_To (Cr, G (X), G (CY + S * 0.4));
                  Stroke (Cr);
               end;
            end loop;
         when Rocket =>
            Color (0.92, 0.92, 0.95);
            New_Path (Cr);
            Move_To (Cr, G (CX + S * 0.5), G (CY));
            Line_To (Cr, G (CX + S * 0.15), G (CY - S * 0.16));
            Line_To (Cr, G (CX - S * 0.35), G (CY - S * 0.16));
            Line_To (Cr, G (CX - S * 0.5), G (CY - S * 0.35));
            Line_To (Cr, G (CX - S * 0.5), G (CY + S * 0.35));
            Line_To (Cr, G (CX - S * 0.35), G (CY + S * 0.16));
            Line_To (Cr, G (CX + S * 0.15), G (CY + S * 0.16));
            Close_Path (Cr);
            Fill (Cr);
            Color (1.0, 0.4, 0.1);
            New_Path (Cr);
            Arc (Cr, G (CX - S * 0.6), G (CY), G (S * 0.1), 0.0, G (2.0 * Pi));
            Fill (Cr);
         when Oil =>
            case Tracks.Theme is
               when Tracks.Alien => Color (0.35, 0.95, 0.20);
               when Tracks.Bath | Tracks.Fish_Tank => Color (0.97, 0.98, 1.0);
               when others => Color (0.05, 0.05, 0.07);
            end case;
            New_Path (Cr);
            Move_To (Cr, G (CX), G (CY - S * 0.45));
            Curve_To (Cr, G (CX + S * 0.4), G (CY), G (CX + S * 0.35), G (CY + S * 0.4), G (CX), G (CY + S * 0.4));
            Curve_To (Cr, G (CX - S * 0.35), G (CY + S * 0.4), G (CX - S * 0.4), G (CY), G (CX), G (CY - S * 0.45));
            Fill_Preserve (Cr);
            Set_Line_Width (Cr, D (2.0));
            Color (0.7, 0.6, 1.0);
            Stroke (Cr);
         when Shield =>
            Color (0.3, 0.9, 1.0);
            New_Path (Cr);
            Move_To (Cr, G (CX), G (CY - S * 0.45));
            Line_To (Cr, G (CX + S * 0.38), G (CY - S * 0.3));
            Line_To (Cr, G (CX + S * 0.3), G (CY + S * 0.15));
            Line_To (Cr, G (CX), G (CY + S * 0.45));
            Line_To (Cr, G (CX - S * 0.3), G (CY + S * 0.15));
            Line_To (Cr, G (CX - S * 0.38), G (CY - S * 0.3));
            Close_Path (Cr);
            Stroke (Cr);
      end case;
   end Icon;

   procedure Player_Panel (N : Positive; X, Y : Float; Right : Boolean) is
      I : constant Car_Index := Player (N);
      R : Racer renames State.Racers (I);
      W : constant Float := 330.0 * Scale;
      X0 : constant Float := (if Right then X - W else X);
   begin
      Panel (X0, Y, W, 170.0 * Scale);
      Font (64.0);
      Color (if R.Place = 1 then Yellow else White);
      Text (Ordinal (R.Place), X0 + 22.0 * Scale, Y + 78.0 * Scale);
      Font (26.0, Italic => True, Bold => False);
      Color (0.8, 0.8, 0.85);
      Text ("/" & Img (State.Count), X0 + 22.0 * Scale + Width_Of ("0000") * 2.2, Y + 76.0 * Scale);
      Font (24.0);
      Color (Scene.Paint (R.Paint));
      Text ((if State.Mode = Net then Trimmed (R.Name) else "P" & Img (N)),
            X0 + W - 20.0 * Scale, Y + 42.0 * Scale, Align => 1);
      Color (White);
      Font (26.0);
      Text ("LAP " & Img (Lap_Shown (I)) & "/" & Img (State.Laps), X0 + W - 20.0 * Scale, Y + 78.0 * Scale,
            Align => 1);
      Font (22.0, Bold => False);
      Color (0.9, 0.9, 0.95);
      declare
         Lap_Time : constant Float :=
           (if R.Finished then R.Finish_T
            elsif State.Phase = Countdown then 0.0
            else State.Time - R.Lap_Start);
      begin
         Text ((if R.Finished then "TIME " else "LAP ") & Time_Of (Lap_Time), X0 + 22.0 * Scale, Y + 118.0 * Scale);
      end;
      Text ("BEST " & (if R.Best_Lap > 0.0 then Time_Of (R.Best_Lap) else "-:--.--"),
            X0 + 22.0 * Scale, Y + 150.0 * Scale);
      if R.Holding /= None then
         Rounded (X0 + W - 92.0 * Scale, Y + 96.0 * Scale, 72.0 * Scale, 64.0 * Scale, 10.0 * Scale);
         Color (1.0, 1.0, 1.0, 0.15);
         Fill (Cr);
         Icon (R.Holding, X0 + W - 56.0 * Scale, Y + 128.0 * Scale, 46.0 * Scale);
      elsif R.Car.Boost_T > 0.0 then
         Font (22.0);
         Color (1.0, 0.6, 0.15);
         Text ("BOOST", X0 + W - 20.0 * Scale, Y + 150.0 * Scale, Align => 1);
      end if;
   end Player_Panel;

   procedure Standings (X, Y : Float) is
      Row : constant Float := 44.0 * Scale;
      W : constant Float := 250.0 * Scale;
   begin
      Panel (X - W, Y, W, Row * Float (State.Count) + 16.0 * Scale);
      for K in 1 .. State.Count loop
         declare
            I : constant Car_Index := In_Place (K);
            R : Racer renames State.Racers (I);
            RY : constant Float := Y + 8.0 * Scale + Row * Float (K - 1);
         begin
            if R.Human > 0 then
               Rounded (X - W + 6.0 * Scale, RY + 3.0 * Scale, W - 12.0 * Scale, Row - 6.0 * Scale, 8.0 * Scale);
               Color (Scene.Paint (R.Paint), 0.35);
               Fill (Cr);
            end if;
            Font (24.0);
            Color (if K = 1 then Yellow else White);
            Text (Img (K), X - W + 20.0 * Scale, RY + 31.0 * Scale);
            Scene.Draw_Car (Cr, X - W + 72.0 * Scale, RY + Row / 2.0, 0.0, 1.25 * Scale, R.Paint);
            Font (22.0, Bold => R.Human > 0);
            Color (White);
            Text (Trimmed (R.Name), X - W + 102.0 * Scale, RY + 30.0 * Scale);
            if R.Finished then
               Font (18.0, Bold => False);
               Color (0.85, 0.95, 0.85);
               Text (Time_Of (R.Finish_T), X - 14.0 * Scale, RY + 29.0 * Scale, Align => 1);
            end if;
         end;
      end loop;
   end Standings;

   procedure Lights is
      T : constant Float := State.Count_T;
      Lit : constant Natural :=
        (if State.Phase /= Countdown then 4
         elsif T > 3.0 then 0
         elsif T > 2.0 then 1
         elsif T > 1.0 then 2
         else 3);
      Short : constant Boolean := State.Mode = Duel and then State.Time > 0.0;   --  a round after the first
      R : constant Float := 34.0 * Scale;
      CX : constant Float := Sw / 2.0;
      CY : constant Float := Sh * 0.28;
   begin
      if State.Phase = Countdown or else (State.Phase = Running and then State.Time < 1.0) then
         if not Short then
            Panel (CX - 4.0 * R, CY - 1.4 * R, 8.0 * R, 2.8 * R, 0.75);
            for K in 1 .. 3 loop
               declare
                  X : constant Float := CX + Float (K - 2) * 2.6 * R;
               begin
                  New_Path (Cr);
                  Arc (Cr, G (X), G (CY), G (R), 0.0, 2.0 * Pi);
                  if Lit = 4 then
                     Color (0.2, 1.0, 0.3);
                  elsif K <= Lit then
                     Color (1.0, 0.15, 0.1);
                  else
                     Color (0.22, 0.08, 0.08);
                  end if;
                  Fill (Cr);
               end;
            end loop;
         end if;
         if State.Phase /= Countdown then
            Font (110.0);
            Outlined ("GO!", CX, CY + 2.6 * R + 90.0 * Scale, 0, (0.3, 1.0, 0.4), 10.0);
         elsif T <= 3.0 then
            Font (110.0);
            Outlined (Img (Integer (Float'Ceiling (T))), CX, CY + 2.6 * R + 90.0 * Scale, 0, Yellow, 10.0);
         end if;
      end if;
   end Lights;

   procedure Duel_Points_Bar is
      P1 : constant Natural := State.Racers (Player (1)).Points;
      R : constant Float := 16.0 * Scale;
      Gap : constant Float := 44.0 * Scale;
      X0 : constant Float := Sw / 2.0 - Gap * Float (Duel_Points - 1) / 2.0;
      Y : constant Float := 50.0 * Scale;
   begin
      Panel (X0 - 90.0 * Scale, Y - 34.0 * Scale, Gap * Float (Duel_Points - 1) + 180.0 * Scale, 68.0 * Scale);
      Font (26.0);
      Color (Scene.Paint (0));
      Text ("P1", X0 - 76.0 * Scale, Y + 9.0 * Scale);
      Color (Scene.Paint (1));
      Text ("P2", X0 + Gap * Float (Duel_Points - 1) + 76.0 * Scale, Y + 9.0 * Scale, Align => 1);
      for K in 1 .. Duel_Points loop
         New_Path (Cr);
         Arc (Cr, G (X0 + Gap * Float (K - 1)), G (Y), G (R), 0.0, 2.0 * Pi);
         Color (Scene.Paint (if K <= P1 then 0 else 1));
         Fill_Preserve (Cr);
         Set_Line_Width (Cr, D (2.5));
         Color (1.0, 1.0, 1.0, 0.7);
         Stroke (Cr);
      end loop;
   end Duel_Points_Bar;

   procedure Draw_Race (O : Overlay) is
   begin
      if State.Attract then
         return;
      end if;
      case State.Mode is
         when Single =>
            Player_Panel (1, 24.0 * Scale, 24.0 * Scale, False);
            Standings (Sw - 24.0 * Scale, 24.0 * Scale);
         when Double =>
            Player_Panel (1, 24.0 * Scale, 24.0 * Scale, False);
            Player_Panel (2, 24.0 * Scale, 210.0 * Scale, False);
            Standings (Sw - 24.0 * Scale, 24.0 * Scale);
         when Duel =>
            Duel_Points_Bar;
         when Net =>
            Player_Panel (Local, 24.0 * Scale, 24.0 * Scale, False);
            Standings (Sw - 24.0 * Scale, 24.0 * Scale);
         when Trial =>
            Player_Panel (1, 24.0 * Scale, 24.0 * Scale, False);
            Panel (Sw / 2.0 - 170.0 * Scale, 24.0 * Scale, 340.0 * Scale, 56.0 * Scale);
            Font (24.0);
            Color (1.0, 0.9, 0.5);
            Text ("RECORD " & (if O.Record_Lap > 0.0 then Time_Of (O.Record_Lap) else "-:--.--"),
                  Sw / 2.0, 62.0 * Scale, Align => 0);
      end case;
      if State.Mode /= Duel then
         declare
            Box_W : constant Float := 300.0 * Scale;
            Box_H : constant Float := Box_W * Tracks.Height / Tracks.Width;
         begin
            Minimap (Sw - Box_W - 34.0 * Scale, Sh - Box_H - 34.0 * Scale, Box_W, Box_H);
         end;
      end if;
      Lights;
      if O.Message_T > 0.0 and then Length (O.Message) > 0 then
         Font (64.0);
         Set_Source_Rgba (Cr, 1.0, 1.0, 1.0, G (Float'Min (1.0, O.Message_T * 2.0)));
         Outlined (To_String (O.Message), Sw / 2.0, Sh * 0.42, 0,
                   (1.0, 0.95, 0.7), 8.0);
      end if;
   end Draw_Race;

   ---------------------------------------------------------------------------
   --  The screens
   ---------------------------------------------------------------------------

   procedure Dim (A : Float) is
   begin
      Color (0.02, 0.02, 0.05, A);
      Paint (Cr);
   end Dim;

   procedure Logo (CY : Float; Clock : Float) is
      Word : constant String := "ADAMACHINES";
      Size : constant Float := 118.0;
      Total : Float;
      X : Float;
   begin
      Font (Size);
      Total := Width_Of (Word) + 4.0 * Scale * Float (Word'Length);
      X := Sw / 2.0 - Total / 2.0;
      for K in Word'Range loop
         declare
            Ch : constant String := Word (K .. K);
            Bob : constant Float := 6.0 * Scale * Sin (Clock * 3.0 + Float (K) * 0.55);
            C : constant Art.RGB := Scene.Paint ((K - Word'First) mod 6);
         begin
            Outlined (Ch, X, CY + Bob, -1, C, 12.0);
            X := X + Width_Of (Ch) + 4.0 * Scale;
         end;
      end loop;
      Font (28.0, Italic => True, Bold => False);
      Color (1.0, 1.0, 1.0, 0.9);
      Text ("tiny machines racing round the house", Sw / 2.0, CY + 58.0 * Scale, Align => 0);
   end Logo;

   procedure Menu (O : Overlay; Top : Float) is
      Row : constant Float := 50.0 * Scale;
      W : constant Float := 640.0 * Scale;
      X0 : constant Float := Sw / 2.0 - W / 2.0;
   begin
      Panel (X0, Top, W, Row * Float (O.Item_Count) + 24.0 * Scale, 0.6);
      for K in 1 .. O.Item_Count loop
         declare
            It : Item renames O.Items (K);
            Y : constant Float := Top + 12.0 * Scale + Row * Float (K - 1) - 4.0 * Scale;
            Sel : constant Boolean := K = O.Selected;
         begin
            if Sel then
               Rounded (X0 + 8.0 * Scale, Y + 4.0 * Scale, W - 16.0 * Scale, Row - 8.0 * Scale, 10.0 * Scale);
               Color (1.0, 0.75, 0.1, 0.9);
               Fill (Cr);
            end if;
            Font (30.0);
            if Sel then
               Color (0.08, 0.06, 0.02);
            else
               Color (White);
            end if;
            if Length (It.Value) = 0 then
               Text (To_String (It.Label), Sw / 2.0, Y + 40.0 * Scale, Align => 0, Shadow => not Sel);
            else
               Text (To_String (It.Label), X0 + 34.0 * Scale, Y + 40.0 * Scale, Shadow => not Sel);
               Font (28.0, Bold => True);
               if It.Arrows then
                  Text ("<  " & To_String (It.Value) & "  >", X0 + W - 34.0 * Scale, Y + 40.0 * Scale,
                        Align => 1, Shadow => not Sel);
               else
                  Text (To_String (It.Value), X0 + W - 34.0 * Scale, Y + 40.0 * Scale, Align => 1,
                        Shadow => not Sel);
               end if;
            end if;
         end;
      end loop;
   end Menu;

   procedure Hint_Line (O : Overlay) is
   begin
      Font (21.0, Italic => False, Bold => False);
      Color (1.0, 1.0, 1.0, 0.85);
      if Length (O.Hint2) > 0 then
         Text (To_String (O.Hint2), Sw / 2.0, Sh - 30.0 * Scale, Align => 0);
         if Length (O.Hint) > 0 then
            Text (To_String (O.Hint), Sw / 2.0, Sh - 60.0 * Scale, Align => 0);
         end if;
      elsif Length (O.Hint) > 0 then
         Text (To_String (O.Hint), Sw / 2.0, Sh - 30.0 * Scale, Align => 0);
      end if;
   end Hint_Line;

   --  The championship so far: points, most first
   procedure Champ_Table (O : Overlay; X0, Top : Float) is
      Row : constant Float := 50.0 * Scale;
      W : constant Float := 420.0 * Scale;
      Order : array (1 .. State.Count) of Car_Index;
   begin
      for I in Order'Range loop
         Order (I) := I;
      end loop;
      for I in 2 .. State.Count loop
         for J in reverse 2 .. I loop
            exit when O.Champ_Points (Order (J - 1)) >= O.Champ_Points (Order (J));
            declare
               T : constant Car_Index := Order (J);
            begin
               Order (J) := Order (J - 1);
               Order (J - 1) := T;
            end;
         end loop;
      end loop;
      Panel (X0, Top, W, Row * Float (State.Count + 1) + 20.0 * Scale, 0.6);
      Font (20.0, Bold => False);
      Color (0.8, 0.8, 0.85);
      Text ("CHAMPIONSHIP", X0 + 24.0 * Scale, Top + 36.0 * Scale);
      Text ("POINTS", X0 + W - 24.0 * Scale, Top + 36.0 * Scale, Align => 1);
      for K in 1 .. State.Count loop
         declare
            I : constant Car_Index := Order (K);
            R : Racer renames State.Racers (I);
            Y : constant Float := Top + Row * Float (K) + 10.0 * Scale;
         begin
            if R.Human > 0 then
               Rounded (X0 + 8.0 * Scale, Y, W - 16.0 * Scale, Row - 4.0 * Scale, 8.0 * Scale);
               Color (Scene.Paint (R.Paint), 0.35);
               Fill (Cr);
            end if;
            Font (26.0);
            Color (if K = 1 then Yellow else White);
            Text (Img (K), X0 + 24.0 * Scale, Y + 35.0 * Scale);
            Scene.Draw_Car (Cr, X0 + 84.0 * Scale, Y + Row / 2.0 - 2.0 * Scale, 0.0, 1.3 * Scale, R.Paint);
            Font (24.0, Bold => R.Human > 0);
            Color (White);
            Text (Trimmed (R.Name), X0 + 120.0 * Scale, Y + 35.0 * Scale);
            Font (26.0);
            Text (Img (O.Champ_Points (I)), X0 + W - 24.0 * Scale, Y + 35.0 * Scale, Align => 1);
         end;
      end loop;
   end Champ_Table;

   procedure Results_Table (Top : Float; Left : Float := -1.0) is
      Row : constant Float := 50.0 * Scale;
      W : constant Float := 760.0 * Scale;
      X0 : constant Float := (if Left < 0.0 then Sw / 2.0 - W / 2.0 else Left);
   begin
      Panel (X0, Top, W, Row * Float (State.Count + 1) + 20.0 * Scale, 0.6);
      Font (20.0, Bold => False);
      Color (0.8, 0.8, 0.85);
      Text ("TIME", X0 + W * 0.66, Top + 36.0 * Scale, Align => 1);
      Text ("BEST LAP", X0 + W - 30.0 * Scale, Top + 36.0 * Scale, Align => 1);
      for K in 1 .. State.Count loop
         declare
            I : constant Car_Index := In_Place (K);
            R : Racer renames State.Racers (I);
            Y : constant Float := Top + Row * Float (K) + 10.0 * Scale;
         begin
            if R.Human > 0 then
               Rounded (X0 + 8.0 * Scale, Y, W - 16.0 * Scale, Row - 4.0 * Scale, 8.0 * Scale);
               Color (Scene.Paint (R.Paint), 0.35);
               Fill (Cr);
            end if;
            Font (28.0);
            Color (if K = 1 then Yellow else White);
            Text (Ordinal (K), X0 + 24.0 * Scale, Y + 35.0 * Scale);
            Scene.Draw_Car (Cr, X0 + 130.0 * Scale, Y + Row / 2.0 - 2.0 * Scale, 0.0, 1.4 * Scale, R.Paint);
            Font (26.0, Bold => R.Human > 0);
            Color (White);
            Text (Trimmed (R.Name), X0 + 170.0 * Scale, Y + 35.0 * Scale);
            Font (24.0, Bold => False);
            Text ((if R.Finished then Time_Of (R.Finish_T) else "-"), X0 + W * 0.66, Y + 35.0 * Scale, Align => 1);
            Text ((if R.Best_Lap > 0.0 then Time_Of (R.Best_Lap) else "-"), X0 + W - 30.0 * Scale, Y + 35.0 * Scale,
                  Align => 1);
         end;
      end loop;
   end Results_Table;

   procedure Draw (Cr : Cairo.Cairo_Context; Width, Height : Natural; O : Overlay) is
   begin
      Hud.Cr := Cr;
      Sw := Float (Width);
      Sh := Float (Height);
      Scale := Float'Min (Sh / 1080.0, Sw / 1600.0);
      Save (Cr);
      case O.Mode is
         when Racing =>
            Draw_Race (O);
         when Title =>
            Dim (0.25);
            Logo (Sh * 0.17, O.Clock);
            Menu (O, Sh * 0.25);
            if Length (O.Record_Line) > 0 then
               Font (22.0, Italic => True, Bold => False);
               Color (1.0, 0.9, 0.5);
               Text (To_String (O.Record_Line), Sw / 2.0,
                     Sh * 0.25 + 50.0 * Scale * Float (O.Item_Count) + 58.0 * Scale, Align => 0);
            end if;
            Hint_Line (O);
         when Options =>
            Dim (0.5);
            Font (90.0);
            Outlined ("OPTIONS", Sw / 2.0, Sh * 0.3, 0, Yellow, 10.0);
            Menu (O, Sh * 0.38);
            Hint_Line (O);
         when Editor =>
            null;
         when Net_Menu | Host_Lobby | Browse | Client_Lobby =>
            Dim (0.5);
            Font (70.0);
            Outlined (To_String (O.Heading), Sw / 2.0, Sh * 0.13, 0, Yellow, 9.0);
            Menu (O, Sh * 0.18);
            if O.Info_Count > 0 then
               declare
                  Top : constant Float := Sh * 0.18 + 50.0 * Scale * Float (O.Item_Count) + 50.0 * Scale;
                  Row : constant Float := 30.0 * Scale;
               begin
                  Panel (Sw / 2.0 - 420.0 * Scale, Top, 840.0 * Scale, Row * Float (O.Info_Count) + 24.0 * Scale, 0.6);
                  for K in 1 .. O.Info_Count loop
                     declare
                        L : constant String := To_String (O.Info (K));
                        Head : constant Boolean := L'Length > 0 and then L (L'First) = '*';
                     begin
                        Font (21.0, Italic => False, Bold => Head);
                        if Head then
                           Color (1.0, 0.85, 0.3);
                           Text (L (L'First + 1 .. L'Last), Sw / 2.0, Top + 18.0 * Scale + Row * Float (K), Align => 0);
                        else
                           Color (1.0, 1.0, 1.0, 0.92);
                           Text (L, Sw / 2.0, Top + 18.0 * Scale + Row * Float (K), Align => 0);
                        end if;
                     end;
                  end loop;
               end;
            end if;
            if O.Message_T > 0.0 and then Length (O.Message) > 0 then
               Font (36.0);
               Set_Source_Rgba (Cr, 1.0, 1.0, 1.0, G (Float'Min (1.0, O.Message_T * 2.0)));
               Outlined (To_String (O.Message), Sw / 2.0, Sh * 0.86, 0, (1.0, 0.95, 0.7), 6.0);
            end if;
            Hint_Line (O);
         when Paused =>
            Draw_Race (O);
            Dim (0.5);
            Font (90.0);
            Outlined ("PAUSED", Sw / 2.0, Sh * 0.3, 0, Yellow, 10.0);
            Menu (O, Sh * 0.38);
            Hint_Line (O);
         when Results =>
            Dim (0.45);
            Font (80.0);
            if State.Mode = Duel then
               Outlined ("P" & Img (State.Racers (State.Winner).Human) & " WINS THE DUEL", Sw / 2.0, Sh * 0.34, 0,
                         Scene.Paint (State.Racers (State.Winner).Paint), 10.0);
               Menu (O, Sh * 0.46);
            elsif State.Mode = Trial then
               Outlined ("TIME TRIAL", Sw / 2.0, Sh * 0.18, 0, Yellow, 10.0);
               Font (26.0, Bold => False);
               Color (White);
               Text (Tracks.Name (Tracks.Current), Sw / 2.0, Sh * 0.18 + 48.0 * Scale, Align => 0);
               declare
                  R : Racer renames State.Racers (Player (Local));
               begin
                  Panel (Sw / 2.0 - 380.0 * Scale, Sh * 0.27, 760.0 * Scale, 190.0 * Scale, 0.6);
                  Font (34.0);
                  Color (White);
                  Text ("TIME   " & Time_Of (R.Finish_T), Sw / 2.0, Sh * 0.27 + 60.0 * Scale, Align => 0);
                  Text ("BEST LAP   " & Time_Of (R.Best_Lap), Sw / 2.0, Sh * 0.27 + 110.0 * Scale, Align => 0);
                  Font (28.0);
                  if O.New_Record then
                     Color (1.0, 0.85, 0.2);
                     Text ("NEW LAP RECORD!", Sw / 2.0, Sh * 0.27 + 160.0 * Scale, Align => 0);
                  else
                     Color (0.85, 0.85, 0.9);
                     Text ("RECORD   " & Time_Of (O.Record_Lap), Sw / 2.0, Sh * 0.27 + 160.0 * Scale, Align => 0);
                  end if;
               end;
               Menu (O, Sh * 0.27 + 230.0 * Scale);
            elsif O.Champ then
               declare
                  P : constant Positive := State.Racers (Player (Local)).Place;
                  Left_W : constant Float := 760.0 * Scale;
                  Gap : constant Float := 30.0 * Scale;
                  X0 : constant Float := Sw / 2.0 - (Left_W + Gap + 420.0 * Scale) / 2.0;
               begin
                  if O.Champ_Final then
                     declare
                        Best : Natural := 0;
                        Mine : constant Natural := O.Champ_Points (Player (1));
                        Ahead : Natural := 0;
                     begin
                        for K in 1 .. State.Count loop
                           Best := Natural'Max (Best, O.Champ_Points (K));
                           if O.Champ_Points (K) > Mine then
                              Ahead := Ahead + 1;
                           end if;
                        end loop;
                        Outlined ((if Mine = Best then "CHAMPION!" else "YOU CAME " & Ordinal (Ahead + 1)),
                                  Sw / 2.0, Sh * 0.14, 0, (if Mine = Best then Yellow else White), 10.0);
                     end;
                  else
                     Outlined ((if P = 1 then "YOU WIN!" else "YOU CAME " & Ordinal (P)),
                               Sw / 2.0, Sh * 0.14, 0, (if P = 1 then Yellow else White), 10.0);
                  end if;
                  Font (26.0, Bold => False);
                  Color (White);
                  Text (To_String (O.Cup_Name) & "  -  ROUND " & Img (O.Champ_Round) & " OF " & Img (O.Champ_Rounds)
                        & "  -  " & Tracks.Name (Tracks.Current),
                        Sw / 2.0, Sh * 0.14 + 48.0 * Scale, Align => 0);
                  Results_Table (Sh * 0.21, X0);
                  Champ_Table (O, X0 + Left_W + Gap, Sh * 0.21);
                  Menu (O, Sh * 0.21 + 50.0 * Scale * Float (State.Count + 1) + 50.0 * Scale);
               end;
            else
               declare
                  P : constant Positive := State.Racers (Player (Local)).Place;
               begin
                  Outlined ((if State.Mode = Single then
                               (if P = 1 then "YOU WIN!" else "YOU CAME " & Ordinal (P))
                             else "RESULTS"),
                            Sw / 2.0, Sh * 0.16, 0, (if P = 1 or else State.Mode /= Single then Yellow else White),
                            10.0);
               end;
               Font (26.0, Bold => False);
               Color (White);
               Text (Tracks.Name (Tracks.Current), Sw / 2.0, Sh * 0.16 + 48.0 * Scale, Align => 0);
               Results_Table (Sh * 0.22);
               Menu (O, Sh * 0.22 + 50.0 * Scale * Float (State.Count + 1) + 50.0 * Scale);
            end if;
            Hint_Line (O);
      end case;
      if O.Show_Fps then
         Font (18.0, Italic => False);
         Color (1.0, 1.0, 0.4);
         Text (Img (Integer (O.Fps)) & " fps", 12.0 * Scale, Sh - 12.0 * Scale);
      end if;
      Restore (Cr);
   end Draw;

end Hud;
