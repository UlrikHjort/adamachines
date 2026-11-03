--  Adamachines: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with Cairo; use Cairo;
with Gdk.Types.Keysyms; use Gdk.Types.Keysyms;
with Glib; use Glib;
with Gtkada.Types;
with Art;
with Geom; use Geom;
with Tracks; use Tracks;

package body Editor is

   use type Gdk.Types.Gdk_Key_Type;

   Selected : Positive := 1;

   function Home return String is
     (if Ada.Environment_Variables.Exists ("HOME") then Ada.Environment_Variables.Value ("HOME") else ".");
   function Dir return String is (Home & "/.adamachines");
   function File_Name (S : Custom_Slot) return String is
     (Dir & "/custom-" & Character'Val (Character'Pos ('0') + S) & ".trk");
   function Old_File return String is (Dir & "/custom.trk");   --  from when there was one

   Slot : Custom_Slot := 1;
   Modified : Boolean := False;
   Copy_Next : Natural := 0;        --  the built-in track C copies next
   Note : Unbounded_String;         --  a word on what was just done
   Note_T : Float := 0.0;

   function Img (N : Integer) return String is
      S : constant String := Integer'Image (N);
   begin
      return (if N >= 0 then S (S'First + 1 .. S'Last) else S);
   end Img;

   function Current return Custom_Slot is (Slot);

   procedure Tell (S : String) is
   begin
      Note := To_Unbounded_String (S);
      Note_T := 2.5;
   end Tell;

   --  The track in the editor into its slot, and to its file
   procedure Save is
      use Ada.Text_IO;
      F : File_Type;
   begin
      Slots (Slot) := (Custom_Points, Custom_Count, Custom_Theme, True);
      Modified := False;
      if not Ada.Directories.Exists (Dir) then
         Ada.Directories.Create_Path (Dir);
      end if;
      Create (F, Out_File, File_Name (Slot));
      Put_Line (F, "theme " & Theme_Kind'Image (Custom_Theme));
      for K in 1 .. Custom_Count loop
         Put_Line (F, Img (Integer (Custom_Points (K).X)) & " " & Img (Integer (Custom_Points (K).Y)) & " "
                   & Img (Integer (Custom_Points (K).W)));
      end loop;
      Close (F);
   exception
      when others => null;
   end Save;

   --  A slot's file into the editor's track; False when there is none to read
   function Read (Name : String) return Boolean is
      use Ada.Text_IO;
      F : File_Type;
      N : Natural := 0;
   begin
      if not Ada.Directories.Exists (Name) then
         return False;
      end if;
      Open (F, In_File, Name);
      while not End_Of_File (F) loop
         declare
            L : constant String := Get_Line (F);
         begin
            if L'Length > 6 and then L (L'First .. L'First + 5) = "theme " then
               Custom_Theme := Theme_Kind'Value (L (L'First + 6 .. L'Last));
            elsif N < Max_Custom then
               declare
                  V : array (1 .. 3) of Integer := (others => 0);
                  K : Natural := 0;
                  From : Positive := L'First;
               begin
                  for I in L'First .. L'Last + 1 loop
                     if I > L'Last or else L (I) = ' ' then
                        if I > From and then K < 3 then
                           K := K + 1;
                           V (K) := Integer'Value (L (From .. I - 1));
                        end if;
                        From := I + 1;
                     end if;
                  end loop;
                  if K = 3 then
                     N := N + 1;
                     Custom_Points (N) := (Float (V (1)), Float (V (2)), Float (V (3)));
                  end if;
               end;
            end if;
         exception
            when others => null;
         end;
      end loop;
      Close (F);
      Custom_Count := N;
      return N >= 4;
   exception
      when others =>
         return False;
   end Read;

   procedure Load is
   begin
      for S in Custom_Slot loop
         Custom_Theme := Workbench;
         if Read (File_Name (S)) or else (S = 1 and then Read (Old_File)) then
            Slots (S) := (Custom_Points, Custom_Count, Custom_Theme, True);
         else
            Default_Custom;
            Slots (S) := (Custom_Points, Custom_Count, Workbench, False);
         end if;
      end loop;
      Open (1);
   end Load;

   procedure Open (S : Custom_Slot) is
   begin
      Slot := S;
      Custom_Points := Slots (S).Points;
      Custom_Count := Slots (S).Count;
      Custom_Theme := Slots (S).Theme;
      Modified := False;
      Selected := 1;
      if Custom_Count < 4 then
         Default_Custom;
      end if;
   end Open;

   ---------------------------------------------------------------------------
   --  The spline, as the track will be built from it
   ---------------------------------------------------------------------------

   function P (I : Integer) return Control_Point is
     (Custom_Points (1 + (I mod Custom_Count)));

   function Curve (I : Integer; T : Float) return Control_Point is
      P0 : constant Control_Point := P (I - 1);
      P1 : constant Control_Point := P (I);
      P2 : constant Control_Point := P (I + 1);
      P3 : constant Control_Point := P (I + 2);
      T2 : constant Float := T * T;
      T3 : constant Float := T2 * T;
      function F (A, B, C, D : Float) return Float is
        (0.5 * (2.0 * B + (C - A) * T + (2.0 * A - 5.0 * B + 4.0 * C - D) * T2
                + (3.0 * B - A - 3.0 * C + D) * T3));
   begin
      return (F (P0.X, P1.X, P2.X, P3.X), F (P0.Y, P1.Y, P2.Y, P3.Y),
              P1.W + (P2.W - P1.W) * (3.0 * T2 - 2.0 * T3));
   end Curve;

   Steps : constant := 16;
   Max_Dense : constant := Max_Custom * Steps;
   type Dense_Array is array (0 .. Max_Dense - 1) of Control_Point;

   procedure Densify (D : out Dense_Array; N : out Natural) is
   begin
      N := 0;
      for I in 0 .. Custom_Count - 1 loop
         for S in 0 .. Steps - 1 loop
            D (N) := Curve (I, Float (S) / Float (Steps));
            N := N + 1;
         end loop;
      end loop;
   end Densify;

   --  Where the road comes too near itself, if anywhere
   function Crossing return Boolean is
      D : Dense_Array;
      N : Natural;
   begin
      Densify (D, N);
      for I in 0 .. N - 1 loop
         for J in I + 1 .. N - 1 loop
            declare
               Gap : constant Natural := Natural'Min (J - I, N - (J - I));
            begin
               if Gap > Steps * 2
                 and then Sqrt ((D (I).X - D (J).X) ** 2 + (D (I).Y - D (J).Y) ** 2)
                   < (D (I).W + D (J).W) * 0.5 + 15.0
               then
                  return True;
               end if;
            end;
         end loop;
      end loop;
      return False;
   end Crossing;

   function Lap_Length return Float is
      D : Dense_Array;
      N : Natural;
      L : Float := 0.0;
   begin
      Densify (D, N);
      for I in 0 .. N - 1 loop
         L := L + Sqrt ((D ((I + 1) mod N).X - D (I).X) ** 2 + (D ((I + 1) mod N).Y - D (I).Y) ** 2);
      end loop;
      return L;
   end Lap_Length;

   ---------------------------------------------------------------------------
   --  The keys
   ---------------------------------------------------------------------------

   Min_X : constant := 100.0;
   Max_X : constant := 3600.0;
   Min_Y : constant := 100.0;
   Max_Y : constant := 2400.0;

   procedure Key (K : Gdk.Types.Gdk_Key_Type; Shift : Boolean; Result : out Action) is
      Step : constant Float := (if Shift then 4.0 else 20.0);
      C : Control_Point renames Custom_Points (Selected);
      Edited : Boolean := True;
   begin
      Result := None;
      if K in GDK_1 .. GDK_5 then
         --  another slot: this one is kept first, if it was changed or is in the list
         if Modified or else Slots (Slot).Saved then
            Save;
         end if;
         Open (Custom_Slot (K - GDK_1 + 1));
         Tell ("MY TRACK " & Img (Slot) & (if Slots (Slot).Saved then "" else " (NEW)"));
         return;
      elsif K = GDK_LC_c or else K = GDK_C then
         Copy_Next := (if Copy_Next >= Built_In_Count then 1 else Copy_Next + 1);
         Copy_Track (Copy_Next);
         Selected := 1;
         Modified := True;
         Tell ("A COPY OF " & Tracks.Name (Copy_Next) & " - THE ORIGINAL STAYS AS IT IS");
         return;
      end if;
      if K = GDK_Left then
         C.X := Float'Max (Min_X, C.X - Step);
      elsif K = GDK_Right then
         C.X := Float'Min (Max_X, C.X + Step);
      elsif K = GDK_Up then
         C.Y := Float'Max (Min_Y, C.Y - Step);
      elsif K = GDK_Down then
         C.Y := Float'Min (Max_Y, C.Y + Step);
      elsif K = GDK_Tab or else K = GDK_bracketright or else K = GDK_period then
         Selected := (if Selected >= Custom_Count then 1 else Selected + 1);
      elsif K = GDK_ISO_Left_Tab or else K = GDK_bracketleft or else K = GDK_comma then
         Selected := (if Selected = 1 then Custom_Count else Selected - 1);
      elsif K = GDK_Insert or else K = GDK_LC_n or else K = GDK_N then
         if Custom_Count < Max_Custom then
            --  a new point half way to the next one, on the curve
            declare
               Mid : constant Control_Point := Curve (Selected - 1, 0.5);
            begin
               for J in reverse Selected + 1 .. Custom_Count loop
                  Custom_Points (J + 1) := Custom_Points (J);
               end loop;
               Custom_Count := Custom_Count + 1;
               Selected := Selected + 1;
               Custom_Points (Selected) := Mid;
            end;
         end if;
      elsif K = GDK_Delete or else K = GDK_LC_x or else K = GDK_X then
         if Custom_Count > 4 then
            for J in Selected .. Custom_Count - 1 loop
               Custom_Points (J) := Custom_Points (J + 1);
            end loop;
            Custom_Count := Custom_Count - 1;
            Selected := Positive'Min (Selected, Custom_Count);
         end if;
      elsif K = GDK_Page_Up or else K = GDK_plus or else K = GDK_equal or else K = GDK_KP_Add then
         C.W := Float'Min (180.0, C.W + 5.0);
      elsif K = GDK_Page_Down or else K = GDK_minus or else K = GDK_KP_Subtract then
         C.W := Float'Max (70.0, C.W - 5.0);
      elsif K = GDK_LC_t or else K = GDK_T then
         Custom_Theme := (if Custom_Theme = Theme_Kind'Last then Theme_Kind'First else Theme_Kind'Succ (Custom_Theme));
      elsif K = GDK_LC_r or else K = GDK_R then
         Default_Custom;
         Selected := 1;
      elsif K = GDK_Return or else K = GDK_KP_Enter or else K = GDK_F5 then
         Save;
         Result := Test_Drive;
         Edited := False;
      elsif K = GDK_Escape then
         Save;
         Result := Leave;
         Edited := False;
      elsif K = GDK_Tab or else K = GDK_bracketright or else K = GDK_period
        or else K = GDK_ISO_Left_Tab or else K = GDK_bracketleft or else K = GDK_comma
      then
         Edited := False;
      else
         Edited := K in GDK_Left | GDK_Right | GDK_Up | GDK_Down | GDK_Insert | GDK_LC_n | GDK_N
           | GDK_Delete | GDK_LC_x | GDK_X | GDK_Page_Up | GDK_Page_Down | GDK_plus | GDK_equal
           | GDK_KP_Add | GDK_minus | GDK_KP_Subtract | GDK_LC_t | GDK_T | GDK_LC_r | GDK_R;
      end if;
      if Edited then
         Modified := True;
      end if;
   end Key;

   ---------------------------------------------------------------------------
   --  The picture
   ---------------------------------------------------------------------------

   function Theme_Name (T : Theme_Kind) return String is
     (case T is
         when Workbench => "WORKBENCH (CARS)",
         when Garden => "GARDEN (BUGGIES)",
         when Ice => "FROZEN POND (RALLY CARS)",
         when Bath => "BATH (SPEEDBOATS)",
         when Bedroom => "BEDROOM (BIPLANES)",
         when Sky => "SKY (BIPLANES)",
         when Kitchen => "KITCHEN (ROAD BIKES)",
         when Mud => "BACKYARD (DIRT BIKES)",
         when Pool => "POOL TABLE (GO-KARTS)",
         when Desk => "SCHOOL DESK (TANKS)",
         when Beach => "BEACH (HOVERCRAFT)",
         when Toy_Town => "TOY TOWN (CARS)",
         when Fish_Tank => "FISH TANK (SUBMARINES)",
         when Attic => "ATTIC AT NIGHT (RALLY CARS)",
         when Party => "BIRTHDAY PARTY (CARS)",
         when Garage => "GARAGE (MONSTER TRUCKS)",
         when Xmas => "CHRISTMAS (BUGGIES)",
         when Moon => "MOON BASE (ROVERS)",
         when Halloween => "HALLOWEEN (BROOMSTICKS)",
         when Easter => "EASTER (EGG CARS)",
         when Chess => "CHESS BOARD (CARS)",
         when Alien => "ALIEN PLANET (FLYING SAUCERS)",
         when Arctic => "ARCTIC (SNOWMOBILES)");

   procedure Draw (Cr : Cairo.Cairo_Context; W, H : Natural; Clock : Float) is
      Sw : constant Float := Float (W);
      Sh : constant Float := Float (H);
      Sc : constant Float := Float'Min (Sh / 1080.0, Sw / 1600.0);
      Margin : constant Float := 60.0 * Sc;
      Z : constant Float := Float'Min ((Sw - 2.0 * Margin) / (Max_X + 100.0), (Sh - 230.0 * Sc) / (Max_Y + 100.0));
      OX : constant Float := (Sw - (Max_X + 100.0) * Z) / 2.0;
      OY : constant Float := 70.0 * Sc;
      function SX (X : Float) return Gdouble is (Gdouble (OX + X * Z));
      function SY (Y : Float) return Gdouble is (Gdouble (OY + Y * Z));
      function SX_F (X : Float) return Float is (OX + X * Z);
      function SY_F (Y : Float) return Float is (OY + Y * Z);
      G : constant Art.RGB := Art.Ground_Color;
      D : Dense_Array;
      N : Natural;
      Bad : constant Boolean := Crossing;
      procedure Text (S : String; X, Y : Float; Size : Float; Center : Boolean := False) is
         E : aliased Cairo_Text_Extents;
         P : Gtkada.Types.Chars_Ptr;
      begin
         Select_Font_Face (Cr, "DejaVu Sans", Cairo_Font_Slant_Oblique, Cairo_Font_Weight_Bold);
         Set_Font_Size (Cr, Gdouble (Size * Sc));
         if Center then
            P := Gtkada.Types.New_String (S);
            Text_Extents (Cr, P, E'Access);
            Gtkada.Types.Free (P);
            Move_To (Cr, Gdouble (X - Float (E.X_Advance) / 2.0), Gdouble (Y));
         else
            Move_To (Cr, Gdouble (X), Gdouble (Y));
         end if;
         Show_Text (Cr, S);
      end Text;
      pragma Unreferenced (G);
   begin
      Set_Source_Rgb (Cr, 0.08, 0.09, 0.12);
      Paint (Cr);
      --  the area a track may use, and a grid on it
      Rectangle (Cr, SX (0.0), SY (0.0), Gdouble ((Max_X + 100.0) * Z), Gdouble ((Max_Y + 100.0) * Z));
      Set_Source_Rgb (Cr, 0.16, 0.20, 0.17);
      Fill (Cr);
      Set_Line_Width (Cr, 1.0);
      Set_Source_Rgba (Cr, 1.0, 1.0, 1.0, 0.06);
      declare
         X : Float := 0.0;
      begin
         while X <= Max_X + 100.0 loop
            Move_To (Cr, SX (X), SY (0.0));
            Line_To (Cr, SX (X), SY (Max_Y + 100.0));
            X := X + 100.0;
         end loop;
         X := 0.0;
         while X <= Max_Y + 100.0 loop
            Move_To (Cr, SX (0.0), SY (X));
            Line_To (Cr, SX (Max_X + 100.0), SY (X));
            X := X + 100.0;
         end loop;
         Stroke (Cr);
      end;

      --  the road
      Densify (D, N);
      New_Path (Cr);
      for I in 0 .. N - 1 loop
         New_Sub_Path (Cr);
         Arc (Cr, SX (D (I).X), SY (D (I).Y), Gdouble (D (I).W * 0.5 * Z), 0.0, 2.0 * Pi);
      end loop;
      if Bad then
         Set_Source_Rgb (Cr, 0.55, 0.30, 0.30);
      else
         Set_Source_Rgb (Cr, 0.45, 0.46, 0.50);
      end if;
      Fill (Cr);
      Set_Line_Width (Cr, 1.5);
      Set_Source_Rgba (Cr, 1.0, 1.0, 1.0, 0.6);
      Set_Dash (Cr, (6.0, 6.0), 0.0);
      New_Path (Cr);
      for I in 0 .. N - 1 loop
         Line_To (Cr, SX (D (I).X), SY (D (I).Y));
      end loop;
      Close_Path (Cr);
      Stroke (Cr);
      Set_Dash (Cr, No_Dashes, 0.0);

      --  the way round, from the start
      declare
         A : constant Control_Point := D (0);
         B : constant Control_Point := D (3);
         Ang : constant Float := Angle_Of ((B.X - A.X, B.Y - A.Y));
      begin
         Save (Cr);
         Translate (Cr, SX (A.X), SY (A.Y));
         Rotate (Cr, Gdouble (Ang));
         New_Path (Cr);
         Move_To (Cr, Gdouble (22.0 * Sc), 0.0);
         Line_To (Cr, 0.0, Gdouble (-10.0 * Sc));
         Line_To (Cr, 0.0, Gdouble (10.0 * Sc));
         Close_Path (Cr);
         Set_Source_Rgb (Cr, 1.0, 1.0, 1.0);
         Fill (Cr);
         Restore (Cr);
      end;

      --  the control points
      for K in 1 .. Custom_Count loop
         declare
            C : constant Control_Point := Custom_Points (K);
            Sel : constant Boolean := K = Selected;
            R : constant Float := (if Sel then 13.0 + 2.0 * Sin (Clock * 6.0) else 10.0) * Sc;
         begin
            New_Path (Cr);
            Arc (Cr, SX (C.X), SY (C.Y), Gdouble (R), 0.0, 2.0 * Pi);
            if Sel then
               Set_Source_Rgb (Cr, 1.0, 0.8, 0.1);
            elsif K = 1 then
               Set_Source_Rgb (Cr, 0.3, 0.9, 0.4);
            else
               Set_Source_Rgb (Cr, 0.9, 0.92, 0.95);
            end if;
            Fill_Preserve (Cr);
            Set_Source_Rgb (Cr, 0.05, 0.05, 0.08);
            Set_Line_Width (Cr, 1.5);
            Stroke (Cr);
            Set_Source_Rgb (Cr, 0.05, 0.05, 0.08);
            Text (Img (K), SX_F (C.X) - 5.0 * Sc * Float (Img (K)'Length), SY_F (C.Y) + 5.0 * Sc, 14.0);
         end;
      end loop;

      --  what is what
      Set_Source_Rgb (Cr, 1.0, 0.84, 0.15);
      Text ("TRACK EDITOR  -  MY TRACK " & Img (Slot) & (if Slots (Slot).Saved then "" else " (NEW)")
            & (if Modified then " *" else ""), Sw / 2.0, 46.0 * Sc, 36.0, Center => True);
      --  the five slots, the one open lit
      for S in Custom_Slot loop
         declare
            X : constant Float := Sw - 40.0 * Sc * Float (Custom_Slots - S + 1) - 20.0 * Sc;
         begin
            New_Path (Cr);
            Rectangle (Cr, Gdouble (X), Gdouble (16.0 * Sc), Gdouble (32.0 * Sc), Gdouble (32.0 * Sc));
            if S = Slot then
               Set_Source_Rgb (Cr, 1.0, 0.8, 0.1);
            elsif Slots (S).Saved then
               Set_Source_Rgb (Cr, 0.55, 0.6, 0.7);
            else
               Set_Source_Rgb (Cr, 0.25, 0.27, 0.32);
            end if;
            Fill (Cr);
            Set_Source_Rgb (Cr, 0.05, 0.05, 0.08);
            Text (Img (S), X + 9.0 * Sc, 41.0 * Sc, 22.0);
         end;
      end loop
      ;
      if Note_T > 0.0 then
         Note_T := Note_T - 1.0 / 60.0;
         Set_Source_Rgb (Cr, 0.6, 0.95, 0.6);
         Text (To_String (Note), Sw / 2.0, Sh - 152.0 * Sc, 22.0, Center => True);
      end if;
      declare
         Info : constant String :=
           Theme_Name (Custom_Theme) & "     " & Img (Custom_Count) & " POINTS     LAP "
           & Img (Integer (Lap_Length)) & "     POINT " & Img (Selected) & " WIDTH "
           & Img (Integer (Custom_Points (Selected).W));
      begin
         Set_Source_Rgb (Cr, 1.0, 1.0, 1.0);
         Text (Info, Sw / 2.0, Sh - 120.0 * Sc, 24.0, Center => True);
      end;
      if Bad then
         Set_Source_Rgb (Cr, 1.0, 0.35, 0.3);
         Text ("THE ROAD RUNS INTO ITSELF - MOVE THE POINTS APART", Sw / 2.0, Sh - 86.0 * Sc, 22.0, Center => True);
      end if;
      Set_Source_Rgba (Cr, 1.0, 1.0, 1.0, 0.85);
      Text ("arrows: move (shift: finely)    tab, [ ]: next point    N: add    X: delete    + -: width"
            & "    T: place    R: start again", Sw / 2.0, Sh - 52.0 * Sc, 19.0, Center => True);
      Text ("1 - 5: another of your tracks    C: start from a copy of a built-in track    enter: drive it"
            & "    esc: keep it and go back", Sw / 2.0, Sh - 24.0 * Sc, 19.0, Center => True);
   end Draw;

end Editor;
