--  Adamachines: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
with Interfaces; use Interfaces;
with Cairo; use Cairo;
with Cairo.Image_Surface;
with Cairo.Pattern;
with Cairo.Surface;
with Glib; use Glib;

package body Art is

   pragma Warnings (Off, "value may be affected by call");

   use Tracks;

   Picture : Cairo_Surface := Null_Surface;
   Marks : Cairo_Context := Null_Context;   --  drawing on the picture, for the skids

   function World return Cairo_Surface is (Picture);

   function G (X : Float) return Gdouble is (Gdouble (X));

   ---------------------------------------------------------------------------
   --  Noise, that repeats every Period, so tiles meet without a seam
   ---------------------------------------------------------------------------

   function Hash (X, Y, S : Integer) return Float is
      H : Unsigned_32 := Unsigned_32 (X mod 65536) * 374_761_393
        + Unsigned_32 (Y mod 65536) * 668_265_263 + Unsigned_32 (S mod 65536) * 2_246_822_519;
   begin
      H := (H xor Shift_Right (H, 13)) * 1_274_126_177;
      H := H xor Shift_Right (H, 16);
      return Float (H and 16#FF_FFFF#) / 16_777_215.0;
   end Hash;

   function Smooth (T : Float) return Float is (T * T * (3.0 - 2.0 * T));

   function Value_Noise (X, Y : Float; PX, PY : Positive; S : Integer) return Float is
      IX : constant Integer := Integer (Float'Floor (X));
      IY : constant Integer := Integer (Float'Floor (Y));
      FX : constant Float := Smooth (X - Float (IX));
      FY : constant Float := Smooth (Y - Float (IY));
      X0 : constant Integer := IX mod PX;
      Y0 : constant Integer := IY mod PY;
      X1 : constant Integer := (IX + 1) mod PX;
      Y1 : constant Integer := (IY + 1) mod PY;
      A : constant Float := Hash (X0, Y0, S);
      B : constant Float := Hash (X1, Y0, S);
      C : constant Float := Hash (X0, Y1, S);
      D : constant Float := Hash (X1, Y1, S);
   begin
      return Mix (Mix (A, B, FX), Mix (C, D, FX), FY);
   end Value_Noise;

   --  U, V: 0 .. 1 over the tile; PX, PY: the cells across it at the first octave
   function Fbm (U, V : Float; PX, PY : Positive; S : Integer; Octaves : Positive := 4) return Float is
      Sum : Float := 0.0;
      Amp : Float := 0.5;
      Total : Float := 0.0;
      KX : Positive := PX;
      KY : Positive := PY;
   begin
      for O in 1 .. Octaves loop
         Sum := Sum + Amp * Value_Noise (U * Float (KX), V * Float (KY), KX, KY, S + O * 101);
         Total := Total + Amp;
         Amp := Amp * 0.5;
         KX := KX * 2;
         KY := KY * 2;
      end loop;
      return Sum / Total;
   end Fbm;

   ---------------------------------------------------------------------------
   --  The tiles
   ---------------------------------------------------------------------------

   type Tile_Kind is (Wood, Tarmac, Dirt, Grass, Ice_Sheet, Snow, Sand_Grains, Floor_Below,
                      Bath_Water, Carpet, Sky_Blue, Kitchen_Tiles, Mud_Ground, Felt, Birch, Model_Grass,
                      Gravel, Old_Boards, Gingham, Concrete, Tartan, Regolith, Chessboard, Alien_Soil);

   Tile_Size : constant := 256;
   Tiles : array (Tile_Kind) of Cairo_Surface := (others => Null_Surface);
   Patterns : array (Tile_Kind) of Cairo_Pattern := (others => Cairo.Null_Pattern);

   function Mix (A, B : RGB; T : Float) return RGB is
     ((Mix (A.R, B.R, T), Mix (A.G, B.G, T), Mix (A.B, B.B, T)));
   function Shade (A : RGB; F : Float) return RGB is
     ((Float'Min (1.0, A.R * F), Float'Min (1.0, A.G * F), Float'Min (1.0, A.B * F)));

   function Pixel_Of (K : Tile_Kind; X, Y : Natural) return RGB is
      U : constant Float := Float (X) / Float (Tile_Size);
      V : constant Float := Float (Y) / Float (Tile_Size);
   begin
      case K is
         when Wood =>
            declare
               Warp : constant Float := Fbm (U, V, 2, 2, 1, 2);
               Ring_At : constant Float := V * 10.0 + 1.4 * Warp;
               Ring : constant Float := Ring_At - Float'Floor (Ring_At);
               Line : constant Float := Float'Max (0.0, 1.0 - abs (Ring - 0.5) * 9.0);
               Streak : constant Float := Fbm (U, V, 2, 64, 2, 2);
               Fine : constant Float := Fbm (U, V, 4, 160, 3, 1);
               T : constant Float := 0.25 + 0.45 * Streak + 0.2 * Fine + 0.35 * Line - 0.25;
            begin
               return Mix ((0.84, 0.63, 0.41), (0.58, 0.38, 0.21), Clamp (T, 0.0, 1.0));
            end;
         when Tarmac =>
            declare
               N : constant Float := Fbm (U, V, 16, 16, 3, 3);
               Fleck : constant Float := Hash (X, Y, 9);
               C : RGB := Shade ((0.34, 0.35, 0.38), 0.88 + 0.24 * N);
            begin
               if Fleck > 0.97 then
                  C := Shade (C, 1.25);
               elsif Fleck < 0.03 then
                  C := Shade (C, 0.75);
               end if;
               return C;
            end;
         when Dirt =>
            declare
               N : constant Float := Fbm (U, V, 6, 6, 4, 4);
               Peb : constant Float := Fbm (U, V, 40, 40, 5, 2);
               C : RGB := Shade ((0.58, 0.44, 0.29), 0.82 + 0.36 * N);
            begin
               if Peb > 0.7 then
                  C := Mix (C, (0.72, 0.68, 0.62), Float'Min (1.0, (Peb - 0.7) * 8.0));
               elsif Peb < 0.27 then
                  C := Shade (C, 0.85);
               end if;
               if Hash (X, Y, 6) > 0.985 then
                  C := Shade (C, 0.7);
               end if;
               return C;
            end;
         when Grass =>
            declare
               Patch : constant Float := Fbm (U, V, 4, 4, 7, 3);
               Blade : constant Float := Fbm (U, V, 128, 24, 8, 2);
               C : RGB := Mix ((0.25, 0.47, 0.17), (0.38, 0.60, 0.22), Patch);
            begin
               C := Shade (C, 0.78 + 0.42 * Blade);
               return C;
            end;
         when Ice_Sheet =>
            declare
               N : constant Float := Fbm (U, V, 3, 3, 10, 4);
               Streak : constant Float := Fbm (U + V * 0.5, V, 24, 2, 11, 2);
               C : RGB := Mix ((0.70, 0.83, 0.93), (0.86, 0.93, 0.98), N);
            begin
               C := Mix (C, (0.97, 0.99, 1.0), Float'Max (0.0, Streak - 0.6) * 1.6);
               return C;
            end;
         when Snow =>
            declare
               N : constant Float := Fbm (U, V, 5, 5, 12, 4);
               C : RGB := Mix ((0.84, 0.88, 0.96), (0.98, 0.99, 1.0), N);
            begin
               if Hash (X, Y, 13) > 0.993 then
                  C := (1.0, 1.0, 1.0);
               end if;
               return C;
            end;
         when Sand_Grains =>
            declare
               Ripple_At : constant Float := U * 12.0 + 2.0 * Fbm (U, V, 3, 3, 14, 3);
               Ripple : constant Float := 0.5 + 0.5 * Sin (2.0 * Pi * Ripple_At);
               C : RGB := Shade ((0.88, 0.76, 0.52), 0.9 + 0.1 * Ripple);
            begin
               C := Shade (C, 0.92 + 0.16 * Hash (X, Y, 15));
               return C;
            end;
         when Bath_Water =>
            declare
               N : constant Float := Fbm (U, V, 4, 4, 20, 3);
               W1 : constant Float := Fbm (U, V, 6, 6, 21, 2);
               W2 : constant Float := Fbm (U, V, 5, 7, 22, 2);
               Line : constant Float :=
                 Float'Max (0.0, 1.0 - abs (W1 - 0.5) * 14.0) + Float'Max (0.0, 1.0 - abs (W2 - 0.5) * 16.0);
               C : constant RGB := Mix ((0.50, 0.76, 0.86), (0.62, 0.86, 0.93), N);
            begin
               return Mix (C, (0.92, 0.98, 1.0), Clamp (Line * 0.45, 0.0, 0.6));
            end;
         when Carpet =>
            declare
               N : constant Float := Fbm (U, V, 8, 8, 23, 3);
               C : constant RGB := Mix ((0.30, 0.38, 0.55), (0.38, 0.46, 0.64), N);
            begin
               return Shade (C, 0.9 + 0.2 * Hash (X, Y, 24));
            end;
         when Sky_Blue =>
            declare
               N : constant Float := Fbm (U, V, 3, 3, 25, 4);
            begin
               return Mix ((0.42, 0.64, 0.90), (0.62, 0.80, 0.97), N);
            end;
         when Kitchen_Tiles =>
            declare
               Cell_U : constant Float := U * 4.0 - Float'Floor (U * 4.0);
               Cell_V : constant Float := V * 4.0 - Float'Floor (V * 4.0);
               Grout : constant Boolean := Cell_U < 0.03 or else Cell_V < 0.03;
               Odd : constant Boolean := (Integer (Float'Floor (U * 4.0)) + Integer (Float'Floor (V * 4.0))) mod 2 = 1;
               N : constant Float := Fbm (U, V, 8, 8, 26, 3);
               C : constant RGB := (if Odd then (0.80, 0.42, 0.28) else (0.93, 0.88, 0.78));
            begin
               if Grout then
                  return (0.62, 0.60, 0.56);
               end if;
               return Shade (C, 0.92 + 0.14 * N);
            end;
         when Mud_Ground =>
            declare
               N : constant Float := Fbm (U, V, 5, 5, 27, 4);
               Grass_Tuft : constant Float := Fbm (U, V, 12, 12, 28, 2);
               C : RGB := Mix ((0.30, 0.22, 0.13), (0.45, 0.34, 0.21), N);
            begin
               if Grass_Tuft > 0.62 then
                  C := Mix (C, (0.32, 0.48, 0.18), Float'Min (1.0, (Grass_Tuft - 0.62) * 6.0));
               end if;
               return Shade (C, 0.9 + 0.2 * Hash (X, Y, 29));
            end;
         when Felt =>
            declare
               N : constant Float := Fbm (U, V, 16, 16, 30, 3);
            begin
               return Shade ((0.10, 0.48, 0.25), 0.9 + 0.15 * N + 0.06 * Hash (X, Y, 31));
            end;
         when Birch =>
            declare
               Warp : constant Float := Fbm (U, V, 2, 2, 32, 2);
               Ring_At : constant Float := V * 8.0 + 1.2 * Warp;
               Ring : constant Float := Ring_At - Float'Floor (Ring_At);
               Streak : constant Float := Fbm (U, V, 2, 64, 33, 2);
               T : constant Float := 0.35 * Streak + 0.3 * Float'Max (0.0, 1.0 - abs (Ring - 0.5) * 8.0);
            begin
               return Mix ((0.92, 0.82, 0.64), (0.78, 0.64, 0.44), Clamp (T, 0.0, 1.0));
            end;
         when Model_Grass =>
            declare
               N : constant Float := Fbm (U, V, 6, 6, 34, 3);
            begin
               return Shade (Mix ((0.30, 0.55, 0.22), (0.40, 0.65, 0.28), N), 0.88 + 0.24 * Hash (X, Y, 35));
            end;
         when Gravel =>
            declare
               Cell : constant Float := Hash (X / 3, Y / 3, 40);
               C : constant RGB :=
                 (if Cell < 0.25 then (0.55, 0.45, 0.70) elsif Cell < 0.5 then (0.35, 0.55, 0.75)
                  elsif Cell < 0.75 then (0.80, 0.75, 0.62) else (0.45, 0.65, 0.55));
            begin
               return Shade (Mix (C, (0.25, 0.45, 0.55), 0.45), 0.8 + 0.3 * Hash (X, Y, 41));
            end;
         when Old_Boards =>
            declare
               Plank : constant Integer := Y / 32;
               Streak : constant Float := Fbm (U, V, 2, 48, 42 + Plank, 2);
               Seam : constant Boolean := Y mod 32 = 0;
               C : constant RGB := Shade ((0.42, 0.30, 0.20), 0.8 + 0.3 * Streak + 0.1 * Hash (Plank, 0, 43));
            begin
               return (if Seam then (0.12, 0.08, 0.05) else C);
            end;
         when Gingham =>
            declare
               A : constant Boolean := (X / 32) mod 2 = 0;
               B : constant Boolean := (Y / 32) mod 2 = 0;
               C : constant RGB :=
                 (if A and B then (0.98, 0.70, 0.78) elsif A or B then (0.99, 0.86, 0.90) else (1.0, 0.98, 0.98));
            begin
               return Shade (C, 0.95 + 0.06 * Hash (X, Y, 44));
            end;
         when Concrete =>
            declare
               N : constant Float := Fbm (U, V, 6, 6, 45, 4);
            begin
               return Shade ((0.60, 0.60, 0.58), 0.85 + 0.25 * N + 0.06 * Hash (X, Y, 46));
            end;
         when Tartan =>
            declare
               SX : constant Integer := X mod 64;
               SY : constant Integer := Y mod 64;
               C : RGB := (0.55, 0.08, 0.10);
            begin
               if SX in 20 .. 28 or else SY in 20 .. 28 then
                  C := (0.10, 0.32, 0.15);
               end if;
               if SX in 44 .. 45 or else SY in 44 .. 45 then
                  C := (0.85, 0.75, 0.30);
               end if;
               return Shade (C, 0.9 + 0.15 * Hash (X, Y, 47));
            end;
         when Regolith =>
            declare
               N : constant Float := Fbm (U, V, 6, 6, 48, 4);
               Pit : constant Float := Fbm (U, V, 20, 20, 49, 2);
               C : RGB := Shade ((0.60, 0.60, 0.62), 0.8 + 0.35 * N);
            begin
               if Pit < 0.3 then
                  C := Shade (C, 0.85);
               end if;
               return Shade (C, 0.95 + 0.1 * Hash (X, Y, 50));
            end;
         when Chessboard =>
            declare
               Black : constant Boolean := (X / 128 + Y / 128) mod 2 = 1;
               Grain : constant Float := Fbm (U, V, 2, 32, 51, 2);
            begin
               return Shade ((if Black then (0.28, 0.17, 0.10) else (0.90, 0.80, 0.62)), 0.9 + 0.15 * Grain);
            end;
         when Alien_Soil =>
            declare
               N : constant Float := Fbm (U, V, 5, 5, 52, 4);
               Glow : constant Float := Fbm (U, V, 24, 24, 53, 2);
               C : RGB := Mix ((0.22, 0.10, 0.28), (0.38, 0.18, 0.42), N);
            begin
               if Glow > 0.72 then
                  C := Mix (C, (0.4, 1.0, 0.6), Float'Min (0.6, (Glow - 0.72) * 4.0));
               end if;
               return Shade (C, 0.9 + 0.15 * Hash (X, Y, 54));
            end;
         when Floor_Below =>
            declare
               --  Tiles on the floor far below the table, dim and out of focus
               TX : constant Integer := X / 64;
               TY : constant Integer := Y / 64;
               N : constant Float := Fbm (U, V, 4, 4, 16, 3);
               C : constant RGB :=
                 (if (TX + TY) mod 2 = 0 then (0.20, 0.19, 0.22) else (0.15, 0.14, 0.17));
            begin
               return Shade (C, 0.85 + 0.3 * N);
            end;
      end case;
   end Pixel_Of;

   procedure Make_Tiles is
      use Cairo.Image_Surface;
   begin
      if Tiles (Wood) /= Null_Surface then
         return;
      end if;
      for K in Tile_Kind loop
         Tiles (K) := Create (Cairo_Format_ARGB32, Tile_Size, Tile_Size);
         Cairo.Surface.Flush (Tiles (K));
         declare
            Stride : constant Natural := Natural (Get_Stride (Tiles (K))) / 4;
            type Pixels is array (0 .. Stride * Tile_Size - 1) of Unsigned_32;
            Data : Pixels with Import, Address => Get_Data_Generic (Tiles (K));
            function Byte (X : Float) return Unsigned_32 is
              (Unsigned_32 (Clamp (X, 0.0, 1.0) * 255.0));
         begin
            for Y in 0 .. Tile_Size - 1 loop
               for X in 0 .. Tile_Size - 1 loop
                  declare
                     C : constant RGB := Pixel_Of (K, X, Y);
                  begin
                     Data (Y * Stride + X) := 16#FF00_0000# or Shift_Left (Byte (C.R), 16)
                       or Shift_Left (Byte (C.G), 8) or Byte (C.B);
                  end;
               end loop;
            end loop;
         end;
         Cairo.Surface.Mark_Dirty (Tiles (K));
         Patterns (K) := Cairo.Pattern.Create_For_Surface (Tiles (K));
         Cairo.Pattern.Set_Extend (Patterns (K), Cairo.Pattern.Cairo_Extend_Repeat);
         Cairo.Pattern.Set_Filter (Patterns (K), Cairo.Pattern.Cairo_Filter_Good);
      end loop;
   end Make_Tiles;

   ---------------------------------------------------------------------------
   --  Painting helpers, in world units
   ---------------------------------------------------------------------------

   Cr : Cairo_Context := Null_Context;
   Rand : Seed := 1;

   procedure Color (C : RGB; A : Float := 1.0) is
   begin
      Set_Source_Rgba (Cr, G (C.R), G (C.G), G (C.B), G (A));
   end Color;

   procedure Color (R, Gr, B : Float; A : Float := 1.0) is
   begin
      Set_Source_Rgba (Cr, G (R), G (Gr), G (B), G (A));
   end Color;

   procedure Fill_Tile (K : Tile_Kind; Preserve : Boolean := False) is
   begin
      Save (Cr);
      Identity_Matrix (Cr);
      Set_Source (Cr, Patterns (K));
      if Preserve then
         Fill_Preserve (Cr);
      else
         Fill (Cr);
      end if;
      Restore (Cr);
   end Fill_Tile;

   procedure Disc (X, Y, R : Float) is
   begin
      New_Sub_Path (Cr);
      Arc (Cr, G (X), G (Y), G (R), 0.0, 2.0 * Pi);
   end Disc;

   procedure Oval (RX, RY : Float) is
   begin
      Save (Cr);
      Cairo.Scale (Cr, G (RX), G (RY));
      New_Sub_Path (Cr);
      Arc (Cr, 0.0, 0.0, 1.0, 0.0, 2.0 * Pi);
      Restore (Cr);
   end Oval;

   procedure Round_Box (X, Y, W, H, R : Float) is
   begin
      New_Sub_Path (Cr);
      Arc (Cr, G (X + W - R), G (Y + R), G (R), G (-Pi / 2.0), 0.0);
      Arc (Cr, G (X + W - R), G (Y + H - R), G (R), 0.0, G (Pi / 2.0));
      Arc (Cr, G (X + R), G (Y + H - R), G (R), G (Pi / 2.0), G (Pi));
      Arc (Cr, G (X + R), G (Y + R), G (R), G (Pi), G (1.5 * Pi));
      Close_Path (Cr);
   end Round_Box;

   --  A blob: a circle with a ragged edge
   procedure Blob (RX, RY : Float; Rag : Float; S : Integer) is
      N : constant := 28;
   begin
      New_Sub_Path (Cr);
      for K in 0 .. N - 1 loop
         declare
            A : constant Float := Float (K) * 2.0 * Pi / Float (N);
            F : constant Float := 1.0 + Rag * (Value_Noise (Float (K) * 0.6, 0.0, 17, 1, S) - 0.5);
         begin
            Line_To (Cr, G (RX * F * Cos (A)), G (RY * F * Sin (A)));
         end;
      end loop;
      Close_Path (Cr);
   end Blob;

   procedure Radial (CX, CY, R : Float; Inner, Outer : RGB; A_In : Float := 1.0; A_Out : Float := 1.0) is
      P : constant Cairo_Pattern := Cairo.Pattern.Create_Radial
        (G (CX - R * 0.3), G (CY - R * 0.3), G (R * 0.1), G (CX), G (CY), G (R));
   begin
      Cairo.Pattern.Add_Color_Stop_Rgba (P, 0.0, G (Inner.R), G (Inner.G), G (Inner.B), G (A_In));
      Cairo.Pattern.Add_Color_Stop_Rgba (P, 1.0, G (Outer.R), G (Outer.G), G (Outer.B), G (A_Out));
      Set_Source (Cr, P);
      Cairo.Pattern.Destroy (P);
   end Radial;

   procedure Linear (X0, Y0, X1, Y1 : Float; A, B : RGB) is
      P : constant Cairo_Pattern := Cairo.Pattern.Create_Linear (G (X0), G (Y0), G (X1), G (Y1));
   begin
      Cairo.Pattern.Add_Color_Stop_Rgb (P, 0.0, G (A.R), G (A.G), G (A.B));
      Cairo.Pattern.Add_Color_Stop_Rgb (P, 1.0, G (B.R), G (B.G), G (B.B));
      Set_Source (Cr, P);
      Cairo.Pattern.Destroy (P);
   end Linear;

   procedure Shape_Path (S : Shape; Grow : Float := 0.0) is
   begin
      Save (Cr);
      Translate (Cr, G (S.C.X), G (S.C.Y));
      Rotate (Cr, G (S.A));
      case S.Kind is
         when Circle =>
            Disc (0.0, 0.0, S.RX + Grow);
         when Box =>
            New_Sub_Path (Cr);
            Rectangle (Cr, G (-S.RX - Grow), G (-S.RY - Grow), G (2.0 * (S.RX + Grow)), G (2.0 * (S.RY + Grow)));
         when Ellipse =>
            Oval (S.RX + Grow, S.RY + Grow);
      end case;
      Restore (Cr);
   end Shape_Path;

   procedure Shadow (S : Shape; Height : Float) is
      Off : constant Vec := (0.55 * Height, 0.75 * Height);
   begin
      for K in 1 .. 3 loop
         New_Path (Cr);
         Shape_Path ((S.Kind, S.C + Off, S.A, S.RX, S.RY), Float (4 - K) * 1.6);
         Color (0.0, 0.0, 0.0, (if Tracks.Theme = Sky then 0.04 else 0.11));
         Fill (Cr);
      end loop;
   end Shadow;

   ---------------------------------------------------------------------------
   --  The things
   ---------------------------------------------------------------------------

   Toys : constant array (0 .. 7) of RGB :=
     ((0.88, 0.15, 0.12), (0.15, 0.40, 0.90), (0.98, 0.78, 0.10), (0.15, 0.70, 0.30),
      (0.62, 0.28, 0.85), (0.98, 0.52, 0.10), (0.95, 0.95, 0.95), (0.10, 0.75, 0.80));
   function Toy_Color (N : Natural) return RGB is (Toys (N mod Toys'Length));

   Steel : constant RGB := (0.78, 0.80, 0.84);
   Steel_Dark : constant RGB := (0.38, 0.40, 0.45);

   procedure Draw_Item (It : Item) is
      S : Shape renames It.S;
      T : constant Float := It.Tone;
      R : constant Float := S.RX;
   begin
      case It.Kind is
         when Screw | Nut | Pencil | Mug | Tape_Roll | Battery | Stone | Pot | Snowman | Pine_Cone | Pine_Tree
            | Rubber_Duck | Soap | Sponge | Bottle | Balloon | Hot_Air_Balloon
            | Fork | Spoon | Bottle_Cap | Salt_Shaker | Pea | Hay_Bale | Tyre_Stack
            | Snooker_Ball | Chalk_Cube | Cue | Eraser | Sharpener | Coin | Sandcastle | Bucket
            | Beach_Ball | Model_Tree | House | Bush
            | Castle | Chest | Air_Stone | Trunk | Rocking_Horse | Carton | Cake | Present | Party_Hat
            | Cupcake | Toolbox | Paint_Tin | Spanner | Xmas_Tree | Bauble | Candy_Cane | Moon_Rock
            | Lander | Dome | Pumpkin | Gravestone | Cauldron | Candle | Easter_Egg | Choc_Bunny | Basket
            | Pawn | Rook | Knight_Piece | Bishop | Queen | King | Chess_Clock | Alien_Plant | Egg_Pod | Spire
            | Igloo | Ice_Block | Seal =>
            Shadow (S, (case It.Kind is
                           when Mug => 13.0, when Pot => 11.0, when Pine_Tree => 16.0,
                           when Snowman => 12.0, when Tape_Roll => 7.0, when Pencil => 5.0,
                           when Battery => 7.0, when Stone => 3.0 + R * 0.15,
                           when Rubber_Duck => 6.0, when Soap | Sponge => 4.0, when Bottle => 7.0,
                           when Balloon => 46.0, when Hot_Air_Balloon => 60.0,
                           when Salt_Shaker => 14.0, when Hay_Bale => 8.0, when Tyre_Stack => 6.0,
                           when Fork | Spoon => 3.0, when Bottle_Cap => 3.0, when Pea => 2.0,
                           when Snooker_Ball => 6.0, when Sandcastle => 12.0, when Bucket => 10.0,
                           when Beach_Ball => 9.0, when Model_Tree => 16.0, when House => 12.0,
                           when Bush => 6.0, when Coin => 1.5, when Eraser | Sharpener => 4.0,
                           when Castle => 14.0, when Chest => 7.0, when Trunk => 10.0, when Carton => 12.0,
                           when Rocking_Horse => 12.0, when Cake => 16.0, when Present => 8.0,
                           when Party_Hat | Cupcake => 9.0, when Toolbox => 10.0, when Paint_Tin => 9.0,
                           when Spanner => 2.0, when Xmas_Tree => 26.0, when Bauble => 4.0,
                           when Candy_Cane => 3.0, when Lander => 14.0, when Dome => 12.0,
                           when Pumpkin => 8.0, when Gravestone => 10.0, when Cauldron => 9.0, when Candle => 5.0,
                           when Easter_Egg => 5.0, when Choc_Bunny => 8.0, when Basket => 9.0,
                           when Pawn => 10.0, when Rook | Bishop => 13.0, when Knight_Piece => 14.0,
                           when Queen => 16.0, when King => 18.0, when Chess_Clock => 9.0,
                           when Alien_Plant => 6.0, when Egg_Pod => 5.0, when Spire => 14.0,
                           when Igloo => 14.0, when Ice_Block => 7.0, when Seal => 4.0,
                           when others => 3.0));
         when others => null;
      end case;
      Save (Cr);
      Translate (Cr, G (S.C.X), G (S.C.Y));
      Rotate (Cr, G (S.A));
      case It.Kind is
         when Screw =>
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            Radial (0.0, 0.0, R, (0.95, 0.95, 0.97), Steel_Dark);
            Fill (Cr);
            Set_Line_Width (Cr, G (R * 0.28));
            Color (0.15, 0.15, 0.18);
            Move_To (Cr, G (-R * 0.7), 0.0);
            Line_To (Cr, G (R * 0.7), 0.0);
            if T > 0.5 then
               Move_To (Cr, 0.0, G (-R * 0.7));
               Line_To (Cr, 0.0, G (R * 0.7));
            end if;
            Stroke (Cr);
         when Nut =>
            New_Path (Cr);
            for K in 0 .. 5 loop
               Line_To (Cr, G (R * Cos (Float (K) * Pi / 3.0)), G (R * Sin (Float (K) * Pi / 3.0)));
            end loop;
            Close_Path (Cr);
            Radial (0.0, 0.0, R, Steel, Steel_Dark);
            Fill_Preserve (Cr);
            Set_Line_Width (Cr, 1.0);
            Color (0.25, 0.25, 0.3);
            Stroke (Cr);
            New_Path (Cr);
            Disc (0.0, 0.0, R * 0.48);
            Color (0.45, 0.30, 0.17);
            Fill_Preserve (Cr);
            Color (0.2, 0.2, 0.22);
            Set_Line_Width (Cr, G (R * 0.12));
            Stroke (Cr);
         when Pencil =>
            declare
               Body_Col : constant RGB :=
                 (if T < 0.33 then (0.95, 0.75, 0.10) elsif T < 0.66 then (0.20, 0.45, 0.85) else (0.85, 0.18, 0.18));
               L : constant Float := R;
               W : constant Float := S.RY;
            begin
               --  the painted body, in three faces
               New_Path (Cr);
               Rectangle (Cr, G (-L + 10.0), G (-W), G (2.0 * L - 26.0), G (2.0 * W));
               Linear (0.0, -W, 0.0, W, Shade (Body_Col, 1.15), Shade (Body_Col, 0.7));
               Fill (Cr);
               Color (1.0, 1.0, 1.0, 0.25);
               Rectangle (Cr, G (-L + 10.0), G (-W * 0.35), G (2.0 * L - 26.0), G (W * 0.3));
               Fill (Cr);
               --  the sharpened end
               New_Path (Cr);
               Move_To (Cr, G (L - 16.0), G (-W));
               Line_To (Cr, G (L), 0.0);
               Line_To (Cr, G (L - 16.0), G (W));
               Close_Path (Cr);
               Color (0.92, 0.78, 0.58);
               Fill (Cr);
               New_Path (Cr);
               Move_To (Cr, G (L - 5.0), G (-W * 0.32));
               Line_To (Cr, G (L), 0.0);
               Line_To (Cr, G (L - 5.0), G (W * 0.32));
               Close_Path (Cr);
               Color (0.2, 0.2, 0.22);
               Fill (Cr);
               --  the band and the rubber
               New_Path (Cr);
               Rectangle (Cr, G (-L + 4.0), G (-W), 6.0, G (2.0 * W));
               Linear (0.0, -W, 0.0, W, (0.9, 0.9, 0.85), (0.55, 0.55, 0.5));
               Fill (Cr);
               New_Path (Cr);
               Round_Box (-L, -W, 6.0, 2.0 * W, 2.0);
               Color (0.93, 0.55, 0.6);
               Fill (Cr);
            end;
         when Mug =>
            declare
               Col : constant RGB := (if T < 0.5 then (0.92, 0.92, 0.9) else (0.25, 0.45, 0.75));
            begin
               --  the handle
               New_Path (Cr);
               Round_Box (R * 0.75, -R * 0.2, R * 0.6, R * 0.4, R * 0.18);
               Color (Shade (Col, 0.85));
               Fill (Cr);
               New_Path (Cr);
               Disc (0.0, 0.0, R);
               Radial (0.0, 0.0, R, Col, Shade (Col, 0.7));
               Fill (Cr);
               New_Path (Cr);
               Disc (0.0, 0.0, R * 0.84);
               Color (0.30, 0.17, 0.08);
               Fill (Cr);
               New_Path (Cr);
               Disc (-R * 0.25, -R * 0.25, R * 0.25);
               Color (1.0, 1.0, 1.0, 0.12);
               Fill (Cr);
            end;
         when Tape_Roll =>
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            Disc (0.0, 0.0, R * 0.62);
            Set_Fill_Rule (Cr, Cairo_Fill_Rule_Even_Odd);
            Radial (0.0, 0.0, R, (0.95, 0.88, 0.70), (0.72, 0.62, 0.42));
            Fill (Cr);
            Set_Fill_Rule (Cr, Cairo_Fill_Rule_Winding);
            Set_Line_Width (Cr, 0.8);
            Color (0.6, 0.5, 0.35, 0.6);
            for K in 1 .. 4 loop
               New_Path (Cr);
               Arc (Cr, 0.0, 0.0, G (R * (0.66 + 0.08 * Float (K))), 0.0, 2.0 * Pi);
               Stroke (Cr);
            end loop;
            New_Path (Cr);
            Disc (0.0, 0.0, R * 0.62);
            Disc (0.0, 0.0, R * 0.52);
            Set_Fill_Rule (Cr, Cairo_Fill_Rule_Even_Odd);
            Color (0.62, 0.48, 0.30);
            Fill (Cr);
            Set_Fill_Rule (Cr, Cairo_Fill_Rule_Winding);
         when Ruler =>
            New_Path (Cr);
            Rectangle (Cr, G (-R), G (-S.RY), G (2.0 * R), G (2.0 * S.RY));
            Color (0.0, 0.0, 0.0, 0.2);
            Fill (Cr);
            New_Path (Cr);
            Rectangle (Cr, G (-R), G (-S.RY), G (2.0 * R - 1.0), G (2.0 * S.RY - 1.0));
            Color ((if T < 0.5 then (0.86, 0.88, 0.90) else (0.95, 0.85, 0.45)));
            Fill (Cr);
            Set_Line_Width (Cr, 0.8);
            Color (0.15, 0.15, 0.15);
            declare
               X : Float := -R + 4.0;
               K : Natural := 0;
            begin
               while X < R - 2.0 loop
                  Move_To (Cr, G (X), G (-S.RY));
                  Line_To (Cr, G (X), G (-S.RY + (if K mod 10 = 0 then 9.0 elsif K mod 5 = 0 then 6.0 else 3.5)));
                  X := X + 4.0;
                  K := K + 1;
               end loop;
               Stroke (Cr);
            end;
         when Battery =>
            declare
               L : constant Float := R;
               W : constant Float := S.RY;
            begin
               New_Path (Cr);
               Round_Box (-L, -W, 2.0 * L * 0.7, 2.0 * W, 2.0);
               Linear (0.0, -W, 0.0, W, (0.35, 0.35, 0.38), (0.08, 0.08, 0.1));
               Fill (Cr);
               New_Path (Cr);
               Round_Box (-L + 1.4 * L, -W, 0.6 * L, 2.0 * W, 2.0);
               Linear (0.0, -W, 0.0, W, (0.95, 0.65, 0.25), (0.6, 0.35, 0.1));
               Fill (Cr);
               New_Path (Cr);
               Rectangle (Cr, G (L), G (-W * 0.35), 3.0, G (W * 0.7));
               Color (Steel);
               Fill (Cr);
            end;
         when Coffee_Spill =>
            New_Path (Cr);
            Blob (R, S.RY, 0.35, Integer (T * 100.0));
            Color (0.30, 0.17, 0.07, 0.75);
            Fill_Preserve (Cr);
            Set_Line_Width (Cr, 2.0);
            Color (0.22, 0.11, 0.04, 0.8);
            Stroke (Cr);
            New_Path (Cr);
            Oval (R * 0.4, S.RY * 0.25);
            Color (1.0, 1.0, 1.0, 0.12);
            Fill (Cr);
         when Sawdust | Sand_Patch | Snow_Pile =>
            New_Path (Cr);
            Blob (R, S.RY, 0.4, Integer (T * 100.0));
            if It.Kind = Snow_Pile then
               Radial (0.0, 0.0, Float'Max (R, S.RY), (1.0, 1.0, 1.0), (0.66, 0.74, 0.88));
               Fill_Preserve (Cr);
               Set_Line_Width (Cr, 2.0);
               Color (0.58, 0.66, 0.82, 0.8);
               Stroke (Cr);
            elsif It.Kind = Sand_Patch then
               Fill_Tile (Sand_Grains, Preserve => True);
               Set_Line_Width (Cr, 3.0);
               Color (0.70, 0.58, 0.36, 0.5);
               Stroke (Cr);
            else
               Color (0.92, 0.80, 0.55, 0.9);
               Fill (Cr);
               for K in 1 .. 40 loop
                  declare
                     A : constant Float := Random (Rand) * 2.0 * Pi;
                     D : constant Float := Sqrt (Random (Rand)) * 0.9;
                  begin
                     New_Path (Cr);
                     Disc (R * D * Cos (A), S.RY * D * Sin (A), 0.8 + Random (Rand) * 1.4);
                     Color (0.78, 0.62, 0.38, 0.8);
                     Fill (Cr);
                  end;
               end loop;
            end if;
         when Stone =>
            New_Path (Cr);
            Blob (R, R * (0.75 + 0.2 * T), 0.3, Integer (T * 300.0));
            Radial (0.0, 0.0, R, (0.72, 0.70, 0.66), (0.38, 0.36, 0.34));
            Fill (Cr);
         when Flower =>
            declare
               Petal : constant RGB :=
                 (if T < 0.25 then (0.95, 0.30, 0.35) elsif T < 0.5 then (0.98, 0.85, 0.25)
                  elsif T < 0.75 then (0.70, 0.45, 0.95) else (1.0, 1.0, 1.0));
            begin
               for K in 0 .. 1 loop
                  Save (Cr);
                  Rotate (Cr, G (Float (K) * 2.5 + 0.4));
                  Translate (Cr, G (R * 0.9), 0.0);
                  New_Path (Cr);
                  Oval (R * 0.6, R * 0.25);
                  Color (0.20, 0.50, 0.15);
                  Fill (Cr);
                  Restore (Cr);
               end loop;
               for K in 0 .. 4 loop
                  Save (Cr);
                  Rotate (Cr, G (Float (K) * 2.0 * Pi / 5.0));
                  Translate (Cr, G (R * 0.45), 0.0);
                  New_Path (Cr);
                  Oval (R * 0.45, R * 0.28);
                  Color (Petal);
                  Fill (Cr);
                  Restore (Cr);
               end loop;
               New_Path (Cr);
               Disc (0.0, 0.0, R * 0.25);
               Color (0.95, 0.75, 0.15);
               Fill (Cr);
            end;
         when Pot =>
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            Radial (0.0, 0.0, R, (0.85, 0.48, 0.30), (0.55, 0.27, 0.15));
            Fill (Cr);
            New_Path (Cr);
            Disc (0.0, 0.0, R * 0.8);
            Color (0.30, 0.20, 0.12);
            Fill (Cr);
            for K in 0 .. 6 loop
               Save (Cr);
               Rotate (Cr, G (Float (K) * 2.0 * Pi / 7.0 + T));
               Translate (Cr, G (R * 0.35), 0.0);
               New_Path (Cr);
               Oval (R * 0.42, R * 0.16);
               Color (0.22 + 0.05 * Float (K mod 2), 0.55, 0.18);
               Fill (Cr);
               Restore (Cr);
            end loop;
         when Pond | Ice_Hole | Puddle =>
            declare
               Deep : constant RGB :=
                 (case It.Kind is
                     when Pond => (0.10, 0.25, 0.32),
                     when Ice_Hole => (0.03, 0.10, 0.18),
                     when others => (0.40, 0.50, 0.58));
               Rim : constant RGB :=
                 (case It.Kind is
                     when Pond => (0.45, 0.42, 0.38),
                     when Ice_Hole => (0.95, 0.98, 1.0),
                     when others => (0.35, 0.30, 0.22));
            begin
               New_Path (Cr);
               Blob (R + 5.0, S.RY + 5.0, 0.18, Integer (T * 50.0));
               Color (Rim, (if It.Kind = Puddle then 0.4 else 1.0));
               Fill (Cr);
               New_Path (Cr);
               Blob (R, S.RY, 0.12, Integer (T * 50.0) + 3);
               Radial (0.0, 0.0, Float'Max (R, S.RY), Shade (Deep, 1.4), Deep,
                       (if It.Kind = Puddle then 0.7 else 1.0), (if It.Kind = Puddle then 0.8 else 1.0));
               Fill (Cr);
               --  light on the water
               Set_Line_Width (Cr, 1.5);
               Color (1.0, 1.0, 1.0, (if It.Kind = Ice_Hole then 0.0 else 0.25));
               for K in 1 .. 3 loop
                  New_Path (Cr);
                  Arc (Cr, G (-R * 0.2), G (-S.RY * 0.2), G (Float (K) * R * 0.18), G (-2.4), G (-1.6));
                  Stroke (Cr);
               end loop;
               if It.Kind = Pond then
                  for K in 1 .. 3 loop
                     Save (Cr);
                     Translate (Cr, G (R * 0.5 * Cos (Float (K) * 2.1)), G (S.RY * 0.5 * Sin (Float (K) * 2.1)));
                     New_Path (Cr);
                     Arc (Cr, 0.0, 0.0, 9.0, 0.5, G (2.0 * Pi));
                     Line_To (Cr, 0.0, 0.0);
                     Close_Path (Cr);
                     Color (0.25, 0.55, 0.2);
                     Fill (Cr);
                     Restore (Cr);
                  end loop;
               elsif It.Kind = Ice_Hole then
                  for K in 1 .. 5 loop
                     New_Path (Cr);
                     Disc (R * (0.25 + 0.5 * Hash (K, 1, Integer (T * 997.0))) * Cos (Float (K) * 2.3 + T * 6.0),
                           S.RY * (0.25 + 0.5 * Hash (K, 2, Integer (T * 997.0))) * Sin (Float (K) * 2.3 + T * 6.0),
                           1.5 + 3.0 * Hash (K, 3, 5));
                     Color (0.85, 0.92, 0.98, 0.9);
                     Fill (Cr);
                  end loop;
               end if;
            end;
         when Leaf =>
            New_Path (Cr);
            Oval (R, S.RY);
            Color ((if T < 0.5 then (0.75, 0.45, 0.12) else (0.55, 0.35, 0.12)));
            Fill (Cr);
            Set_Line_Width (Cr, 0.8);
            Color (0.35, 0.22, 0.08);
            Move_To (Cr, G (-R * 1.2), 0.0);
            Line_To (Cr, G (R * 0.9), 0.0);
            Stroke (Cr);
         when Stream =>
            declare
               L : constant Float := R;
               W : constant Float := S.RY;
            begin
               --  across the road: the banks, then the water or the dark gap
               if Tracks.Theme = Workbench then
                  --  a gap between the planks, the floor far below
                  New_Path (Cr);
                  Rectangle (Cr, G (-L - 3.0), G (-W), G (2.0 * L + 6.0), G (2.0 * W));
                  Color (0.25, 0.15, 0.08);
                  Fill (Cr);
                  New_Path (Cr);
                  Rectangle (Cr, G (-L), G (-W), G (2.0 * L), G (2.0 * W));
                  Fill_Tile (Floor_Below);
                  New_Path (Cr);
                  Rectangle (Cr, G (-L), G (-W), G (2.0 * L), G (2.0 * W));
                  Color (0.0, 0.0, 0.0, 0.45);
                  Fill (Cr);
                  Restore (Cr);
                  return;
               end if;
               New_Path (Cr);
               Rectangle (Cr, G (-L - 5.0), G (-W), G (2.0 * L + 10.0), G (2.0 * W));
               Color ((case Tracks.Theme is
                          when Garden => (0.40, 0.32, 0.22),
                          when Ice => (0.96, 0.98, 1.0),
                          when Workbench => (0.25, 0.18, 0.12),
                          when others => (0.90, 0.92, 0.94)));
               Fill (Cr);
               New_Path (Cr);
               Rectangle (Cr, G (-L), G (-W), G (2.0 * L), G (2.0 * W));
               Linear (-L, 0.0, L, 0.0,
                       (if Tracks.Theme = Ice then (0.02, 0.08, 0.15) else (0.12, 0.30, 0.42)),
                       (if Tracks.Theme = Ice then (0.05, 0.15, 0.25) else (0.20, 0.42, 0.55)));
               Fill (Cr);
               Set_Line_Width (Cr, 1.6);
               Color (1.0, 1.0, 1.0, 0.3);
               declare
                  Y : Float := -W + 8.0;
               begin
                  while Y < W - 8.0 loop
                     declare
                        X : constant Float := (Random (Rand) - 0.5) * L;
                     begin
                        Move_To (Cr, G (X - 5.0), G (Y));
                        Curve_To (Cr, G (X - 2.0), G (Y + 3.0), G (X + 2.0), G (Y - 3.0), G (X + 6.0), G (Y));
                        Y := Y + 7.0 + Random (Rand) * 8.0;
                     end;
                  end loop;
                  Stroke (Cr);
               end;
            end;
         when Snowman =>
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            Radial (0.0, 0.0, R, (1.0, 1.0, 1.0), (0.78, 0.84, 0.94));
            Fill (Cr);
            New_Path (Cr);
            Disc (-R * 0.25, -R * 0.2, R * 0.62);
            Radial (-R * 0.25, -R * 0.2, R * 0.62, (1.0, 1.0, 1.0), (0.82, 0.87, 0.95));
            Fill (Cr);
            New_Path (Cr);
            Disc (-R * 0.35, -R * 0.3, R * 0.36);
            Color (0.12, 0.12, 0.14);
            Fill (Cr);
            New_Path (Cr);
            Move_To (Cr, G (-R * 0.05), G (-R * 0.1));
            Line_To (Cr, G (R * 0.4), G (R * 0.05));
            Line_To (Cr, G (-R * 0.05), G (R * 0.06));
            Close_Path (Cr);
            Color (0.95, 0.5, 0.1);
            Fill (Cr);
         when Pine_Cone =>
            New_Path (Cr);
            Oval (R, S.RY);
            Radial (0.0, 0.0, R, (0.60, 0.40, 0.22), (0.32, 0.20, 0.10));
            Fill (Cr);
            Set_Line_Width (Cr, 0.8);
            Color (0.25, 0.15, 0.07);
            for K in -2 .. 2 loop
               Move_To (Cr, G (Float (K) * R * 0.3), G (-S.RY * 0.8));
               Line_To (Cr, G (Float (K) * R * 0.3 + 2.0), G (S.RY * 0.8));
            end loop;
            Stroke (Cr);
         when Pine_Tree =>
            for Layer in 0 .. 3 loop
               declare
                  RL : constant Float := R * (1.0 - 0.22 * Float (Layer));
                  Spikes : constant := 9;
               begin
                  New_Path (Cr);
                  for K in 0 .. 2 * Spikes - 1 loop
                     declare
                        A : constant Float := Float (K) * Pi / Float (Spikes) + Float (Layer) * 0.35;
                        RR : constant Float := (if K mod 2 = 0 then RL else RL * 0.7);
                     begin
                        Line_To (Cr, G (RR * Cos (A)), G (RR * Sin (A)));
                     end;
                  end loop;
                  Close_Path (Cr);
                  Color (0.10 + 0.04 * Float (Layer), 0.30 + 0.06 * Float (Layer), 0.18 + 0.03 * Float (Layer));
                  Fill (Cr);
               end;
            end loop;
            for K in 1 .. 14 loop
               New_Path (Cr);
               Disc ((Random (Rand) - 0.5) * R * 1.3, (Random (Rand) - 0.5) * R * 1.3, 2.0 + Random (Rand) * 3.0);
               Color (1.0, 1.0, 1.0, 0.85);
               Fill (Cr);
            end loop;
         when Rubber_Duck =>
            New_Path (Cr);
            Oval (R, R * 0.78);
            Radial (0.0, 0.0, R, (1.0, 0.92, 0.35), (0.92, 0.70, 0.05));
            Fill (Cr);
            New_Path (Cr);
            Save (Cr);
            Translate (Cr, G (-R * 0.15), 0.0);
            Oval (R * 0.45, R * 0.3);
            Restore (Cr);
            Color (0.98, 0.80, 0.15);
            Fill (Cr);
            New_Path (Cr);
            Disc (R * 0.5, 0.0, R * 0.45);
            Radial (R * 0.5, 0.0, R * 0.45, (1.0, 0.95, 0.45), (0.95, 0.75, 0.1));
            Fill (Cr);
            New_Path (Cr);
            Move_To (Cr, G (R * 0.85), G (-R * 0.15));
            Line_To (Cr, G (R * 1.25), 0.0);
            Line_To (Cr, G (R * 0.85), G (R * 0.15));
            Close_Path (Cr);
            Color (1.0, 0.45, 0.08);
            Fill (Cr);
            for K in -1 .. 1 loop
               if K /= 0 then
                  New_Path (Cr);
                  Disc (R * 0.62, Float (K) * R * 0.2, R * 0.07);
                  Color (0.05, 0.05, 0.05);
                  Fill (Cr);
               end if;
            end loop;
         when Soap =>
            New_Path (Cr);
            Round_Box (-R, -S.RY, 2.0 * R, 2.0 * S.RY, S.RY * 0.7);
            Radial (0.0, 0.0, R, (1.0, 0.88, 0.92), (0.88, 0.62, 0.72));
            Fill (Cr);
            New_Path (Cr);
            Oval (R * 0.55, S.RY * 0.45);
            Set_Line_Width (Cr, 1.2);
            Color (1.0, 1.0, 1.0, 0.6);
            Stroke (Cr);
         when Sponge =>
            New_Path (Cr);
            Round_Box (-R, -S.RY, 2.0 * R, 2.0 * S.RY, 4.0);
            Color (0.98, 0.84, 0.30);
            Fill (Cr);
            New_Path (Cr);
            Round_Box (-R, -S.RY, 2.0 * R, S.RY * 0.7, 4.0);
            Color (0.25, 0.55, 0.30);
            Fill (Cr);
            for K in 1 .. 18 loop
               New_Path (Cr);
               Disc ((Random (Rand) - 0.5) * 1.8 * R, (0.0 + Random (Rand) * 0.9) * S.RY, 1.0 + Random (Rand) * 1.5);
               Color (0.80, 0.62, 0.15, 0.8);
               Fill (Cr);
            end loop;
         when Bubbles =>
            for K in 1 .. 34 loop
               declare
                  A : constant Float := Random (Rand) * 2.0 * Pi;
                  D : constant Float := Sqrt (Random (Rand)) * 0.85;
                  BR : constant Float := 3.0 + Random (Rand) * 8.0;
                  X : constant Float := R * D * Cos (A);
                  Y : constant Float := S.RY * D * Sin (A);
               begin
                  New_Path (Cr);
                  Disc (X, Y, BR);
                  Radial (X, Y, BR, (1.0, 1.0, 1.0), (0.82, 0.90, 0.96), 0.95, 0.9);
                  Fill_Preserve (Cr);
                  Set_Line_Width (Cr, 0.6);
                  Color (0.6, 0.75, 0.85, 0.7);
                  Stroke (Cr);
                  New_Path (Cr);
                  Disc (X - BR * 0.35, Y - BR * 0.35, BR * 0.25);
                  Color (1.0, 1.0, 1.0);
                  Fill (Cr);
               end;
            end loop;
         when Plughole =>
            Set_Line_Width (Cr, 1.2);
            Color (0.30, 0.50, 0.62, 0.6);
            for K in 1 .. 4 loop
               New_Path (Cr);
               Arc (Cr, 0.0, 0.0, G (R * (1.1 + 0.35 * Float (K))), G (Float (K) * 1.3), G (Float (K) * 1.3 + 3.6));
               Stroke (Cr);
            end loop;
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            Radial (0.0, 0.0, R, (0.95, 0.96, 0.98), (0.55, 0.58, 0.62));
            Fill (Cr);
            New_Path (Cr);
            Disc (0.0, 0.0, R * 0.78);
            Color (0.06, 0.07, 0.09);
            Fill (Cr);
            Set_Line_Width (Cr, G (R * 0.12));
            Color (0.75, 0.77, 0.80);
            Move_To (Cr, G (-R * 0.78), 0.0);
            Line_To (Cr, G (R * 0.78), 0.0);
            Move_To (Cr, 0.0, G (-R * 0.78));
            Line_To (Cr, 0.0, G (R * 0.78));
            Stroke (Cr);
         when Bottle =>
            declare
               Col : constant RGB :=
                 (if T < 0.33 then (0.20, 0.60, 0.85) elsif T < 0.66 then (0.85, 0.30, 0.55) else (0.40, 0.75, 0.35));
            begin
               New_Path (Cr);
               Round_Box (-R, -S.RY, 2.0 * R - 8.0, 2.0 * S.RY, S.RY * 0.6);
               Linear (0.0, -S.RY, 0.0, S.RY, Shade (Col, 1.3), Shade (Col, 0.7));
               Fill (Cr);
               New_Path (Cr);
               Round_Box (R - 10.0, -S.RY * 0.55, 10.0, S.RY * 1.1, 3.0);
               Color (0.95, 0.95, 0.95);
               Fill (Cr);
               New_Path (Cr);
               Rectangle (Cr, G (-R * 0.6), G (-S.RY * 0.5), G (R * 0.9), G (S.RY));
               Color (1.0, 1.0, 1.0, 0.7);
               Fill (Cr);
            end;
         when Soap_Film =>
            New_Path (Cr);
            Blob (R, S.RY, 0.25, Integer (T * 80.0));
            Radial (0.0, 0.0, Float'Max (R, S.RY), (1.0, 0.75, 0.95), (0.55, 0.95, 0.95), 0.55, 0.35);
            Fill (Cr);
            Set_Line_Width (Cr, 1.2);
            Color (1.0, 1.0, 1.0, 0.5);
            for K in 1 .. 3 loop
               New_Path (Cr);
               Save (Cr);
               Cairo.Scale (Cr, G (R * (0.3 + 0.2 * Float (K))), G (S.RY * (0.3 + 0.2 * Float (K))));
               Arc (Cr, 0.0, 0.0, 1.0, G (Float (K)), G (Float (K) + 2.0));
               Restore (Cr);
               Stroke (Cr);
            end loop;
         when Toy_Block =>
            declare
               Col : constant RGB :=
                 (if T < 0.25 then (0.85, 0.20, 0.20) elsif T < 0.5 then (0.20, 0.45, 0.85)
                  elsif T < 0.75 then (0.95, 0.75, 0.15) else (0.25, 0.65, 0.30));
            begin
               New_Path (Cr);
               Rectangle (Cr, G (-R + 4.0), G (-R + 6.0), G (2.0 * R), G (2.0 * R));
               Color (0.0, 0.0, 0.0, 0.25);
               Fill (Cr);
               New_Path (Cr);
               Rectangle (Cr, G (-R), G (-R), G (2.0 * R), G (2.0 * R));
               Color (Col);
               Fill (Cr);
               New_Path (Cr);
               Rectangle (Cr, G (-R * 0.6), G (-R * 0.6), G (1.2 * R), G (1.2 * R));
               Color (Shade (Col, 1.25));
               Fill (Cr);
            end;
         when Book =>
            declare
               Col : constant RGB :=
                 (if T < 0.33 then (0.55, 0.15, 0.15) elsif T < 0.66 then (0.15, 0.30, 0.50) else (0.20, 0.45, 0.30));
            begin
               New_Path (Cr);
               Rectangle (Cr, G (-R + 5.0), G (-S.RY + 7.0), G (2.0 * R), G (2.0 * S.RY));
               Color (0.0, 0.0, 0.0, 0.25);
               Fill (Cr);
               New_Path (Cr);
               Rectangle (Cr, G (-R), G (-S.RY), G (2.0 * R), G (2.0 * S.RY));
               Color (0.95, 0.93, 0.85);
               Fill (Cr);
               New_Path (Cr);
               Rectangle (Cr, G (-R), G (-S.RY), G (2.0 * R - 3.0), G (2.0 * S.RY - 3.0));
               Color (Col);
               Fill (Cr);
               New_Path (Cr);
               Rectangle (Cr, G (-R), G (-S.RY), 8.0, G (2.0 * S.RY - 3.0));
               Color (Shade (Col, 0.7));
               Fill (Cr);
               New_Path (Cr);
               Rectangle (Cr, G (-R * 0.4), G (-S.RY * 0.5), G (R), G (S.RY * 0.3));
               Color (0.95, 0.85, 0.4, 0.8);
               Fill (Cr);
            end;
         when Crayon =>
            declare
               Col : constant RGB := Shade (Toy_Color (Natural (T * 7.9)), 1.0);
            begin
               New_Path (Cr);
               Rectangle (Cr, G (-R), G (-S.RY), G (2.0 * R - 6.0), G (2.0 * S.RY));
               Color (Col);
               Fill (Cr);
               New_Path (Cr);
               Move_To (Cr, G (R - 6.0), G (-S.RY));
               Line_To (Cr, G (R), 0.0);
               Line_To (Cr, G (R - 6.0), G (S.RY));
               Close_Path (Cr);
               Color (Shade (Col, 0.75));
               Fill (Cr);
            end;
         when Balloon =>
            declare
               Col : constant RGB := Toy_Color (Natural (T * 7.9));
            begin
               Set_Line_Width (Cr, 0.8);
               Color (0.9, 0.9, 0.9, 0.8);
               Move_To (Cr, 0.0, G (R));
               Curve_To (Cr, 4.0, G (R + 8.0), -4.0, G (R + 14.0), 2.0, G (R + 22.0));
               Stroke (Cr);
               New_Path (Cr);
               Oval (R, R * 1.08);
               Radial (0.0, 0.0, R, Shade (Col, 1.45), Shade (Col, 0.75));
               Fill (Cr);
               New_Path (Cr);
               Disc (-R * 0.35, -R * 0.4, R * 0.22);
               Color (1.0, 1.0, 1.0, 0.6);
               Fill (Cr);
            end;
         when Cloud =>
            declare
               Fade : constant Float := (if It.Mat = Floor then 0.75 else 0.92);
            begin
               for K in 1 .. 9 loop
                  declare
                     A : constant Float := Float (K) * 2.0 * Pi / 9.0 + T * 3.0;
                     D : constant Float := 0.45 + 0.2 * Hash (K, 7, Integer (T * 500.0));
                     X : constant Float := R * D * Cos (A);
                     Y : constant Float := S.RY * D * Sin (A);
                     BR : constant Float := Float'Min (R, S.RY) * (0.55 + 0.3 * Hash (K, 8, 3));
                  begin
                     New_Path (Cr);
                     Disc (X, Y, BR);
                     Radial (X, Y, BR, (1.0, 1.0, 1.0), (0.85, 0.89, 0.96), Fade, Fade * 0.9);
                     Fill (Cr);
                  end;
               end loop;
               New_Path (Cr);
               Oval (R * 0.6, S.RY * 0.6);
               Color (1.0, 1.0, 1.0, Fade);
               Fill (Cr);
            end;
         when Hot_Air_Balloon =>
            declare
               A : constant RGB := Toy_Color (Natural (T * 7.9));
               B : constant RGB := Toy_Color (Natural (T * 7.9) + 3);
            begin
               for K in 0 .. 11 loop
                  New_Path (Cr);
                  Move_To (Cr, 0.0, 0.0);
                  Arc (Cr, 0.0, 0.0, G (R), G (Float (K) * Pi / 6.0), G (Float (K + 1) * Pi / 6.0));
                  Close_Path (Cr);
                  Color ((if K mod 2 = 0 then A else B));
                  Fill (Cr);
               end loop;
               New_Path (Cr);
               Disc (0.0, 0.0, R);
               Radial (0.0, 0.0, R, (1.0, 1.0, 1.0), (0.0, 0.0, 0.0), 0.3, 0.3);
               Fill (Cr);
               New_Path (Cr);
               Rectangle (Cr, -5.0, -5.0, 10.0, 10.0);
               Color (0.55, 0.38, 0.2);
               Fill (Cr);
            end;
         when Gust =>
            Set_Line_Width (Cr, 2.0);
            for K in 0 .. 5 loop
               declare
                  Y : constant Float := (Float (K) / 5.0 - 0.5) * 1.6 * S.RY;
                  X : constant Float := (Hash (K, 1, 9) - 0.5) * R;
               begin
                  New_Path (Cr);
                  Move_To (Cr, G (X - R * 0.6), G (Y));
                  Curve_To (Cr, G (X - R * 0.2), G (Y - 6.0), G (X + R * 0.2), G (Y + 6.0), G (X + R * 0.5), G (Y));
                  Arc (Cr, G (X + R * 0.5), G (Y - 5.0), 5.0, G (Pi / 2.0), G (2.0 * Pi));
                  Color (1.0, 1.0, 1.0, 0.7);
                  Stroke (Cr);
               end;
            end loop;
         when Fork | Spoon =>
            declare
               L : constant Float := R;
            begin
               New_Path (Cr);
               Round_Box (-L, -3.0, L * 1.2, 6.0, 3.0);
               Linear (0.0, -3.0, 0.0, 3.0, (0.95, 0.96, 0.98), (0.55, 0.57, 0.62));
               Fill (Cr);
               if It.Kind = Spoon then
                  New_Path (Cr);
                  Save (Cr);
                  Translate (Cr, G (L * 0.55), 0.0);
                  Oval (L * 0.38, S.RY + 4.0);
                  Restore (Cr);
                  Radial (L * 0.5, 0.0, L * 0.4, (1.0, 1.0, 1.0), (0.6, 0.62, 0.68));
                  Fill (Cr);
               else
                  New_Path (Cr);
                  Round_Box (L * 0.1, -S.RY - 2.0, L * 0.35, 2.0 * S.RY + 4.0, 3.0);
                  Linear (0.0, -S.RY, 0.0, S.RY, (0.95, 0.96, 0.98), (0.55, 0.57, 0.62));
                  Fill (Cr);
                  for K in -2 .. 1 loop
                     New_Path (Cr);
                     Rectangle (Cr, G (L * 0.4), G (Float (K) * 2.6 + 0.3), G (L * 0.55), 1.6);
                     Color (0.80, 0.82, 0.86);
                     Fill (Cr);
                  end loop;
               end if;
            end;
         when Bottle_Cap =>
            New_Path (Cr);
            for K in 0 .. 41 loop
               declare
                  A : constant Float := Float (K) * 2.0 * Pi / 42.0;
                  RR : constant Float := (if K mod 2 = 0 then R else R * 0.9);
               begin
                  Line_To (Cr, G (RR * Cos (A)), G (RR * Sin (A)));
               end;
            end loop;
            Close_Path (Cr);
            Radial (0.0, 0.0, R, Shade (Toy_Color (Natural (T * 7.9)), 1.3), Shade (Toy_Color (Natural (T * 7.9)), 0.7));
            Fill (Cr);
            New_Path (Cr);
            Disc (0.0, 0.0, R * 0.6);
            Set_Line_Width (Cr, 1.0);
            Color (1.0, 1.0, 1.0, 0.4);
            Stroke (Cr);
         when Salt_Shaker =>
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            Radial (0.0, 0.0, R, (1.0, 1.0, 1.0), (0.72, 0.74, 0.78));
            Fill (Cr);
            New_Path (Cr);
            Disc (0.0, 0.0, R * 0.7);
            Radial (0.0, 0.0, R * 0.7, (0.95, 0.96, 0.98), (0.60, 0.62, 0.66));
            Fill (Cr);
            for K in 0 .. 5 loop
               New_Path (Cr);
               Disc (R * 0.35 * Cos (Float (K) * Pi / 3.0), R * 0.35 * Sin (Float (K) * Pi / 3.0), 1.3);
               Color (0.2, 0.2, 0.22);
               Fill (Cr);
            end loop;
         when Milk_Spill =>
            New_Path (Cr);
            Blob (R, S.RY, 0.35, Integer (T * 100.0));
            Color (0.98, 0.98, 0.96, 0.92);
            Fill_Preserve (Cr);
            Set_Line_Width (Cr, 1.5);
            Color (0.80, 0.82, 0.84, 0.8);
            Stroke (Cr);
            New_Path (Cr);
            Oval (R * 0.35, S.RY * 0.25);
            Color (1.0, 1.0, 1.0);
            Fill (Cr);
         when Flour =>
            New_Path (Cr);
            Blob (R, S.RY, 0.45, Integer (T * 100.0));
            Radial (0.0, 0.0, Float'Max (R, S.RY), (1.0, 0.99, 0.96), (0.90, 0.88, 0.82), 0.95, 0.7);
            Fill (Cr);
         when Pea =>
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            Radial (0.0, 0.0, R, (0.55, 0.85, 0.30), (0.20, 0.50, 0.10));
            Fill (Cr);
         when Hay_Bale =>
            New_Path (Cr);
            Round_Box (-R, -S.RY, 2.0 * R, 2.0 * S.RY, 3.0);
            Linear (0.0, -S.RY, 0.0, S.RY, (0.95, 0.85, 0.45), (0.75, 0.60, 0.25));
            Fill (Cr);
            Set_Line_Width (Cr, 0.7);
            Color (0.65, 0.50, 0.20, 0.8);
            for K in 1 .. 14 loop
               declare
                  Y : constant Float := (Random (Rand) - 0.5) * 1.8 * S.RY;
                  X : constant Float := (Random (Rand) - 0.5) * 1.6 * R;
               begin
                  Move_To (Cr, G (X - 6.0), G (Y));
                  Line_To (Cr, G (X + 6.0), G (Y + Spread (Rand)));
               end;
            end loop;
            Stroke (Cr);
            Set_Line_Width (Cr, 1.6);
            Color (0.45, 0.30, 0.15);
            for K in -1 .. 1 loop
               if K /= 0 then
                  Move_To (Cr, G (Float (K) * R * 0.5), G (-S.RY));
                  Line_To (Cr, G (Float (K) * R * 0.5), G (S.RY));
               end if;
            end loop;
            Stroke (Cr);
         when Tyre_Stack =>
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            Disc (0.0, 0.0, R * 0.45);
            Set_Fill_Rule (Cr, Cairo_Fill_Rule_Even_Odd);
            Radial (0.0, 0.0, R, (0.30, 0.30, 0.32), (0.06, 0.06, 0.07));
            Fill (Cr);
            Set_Fill_Rule (Cr, Cairo_Fill_Rule_Winding);
            New_Path (Cr);
            Disc (0.0, 0.0, R * 0.45);
            Color (0.03, 0.03, 0.03);
            Fill (Cr);
            New_Path (Cr);
            Arc (Cr, 0.0, 0.0, G (R * 0.75), 0.0, 2.0 * Pi);
            Set_Line_Width (Cr, 1.0);
            Color ((if T < 0.5 then (0.9, 0.9, 0.9) else (0.85, 0.15, 0.1)), 0.7);
            Stroke (Cr);
         when Mud_Patch =>
            New_Path (Cr);
            Blob (R, S.RY, 0.4, Integer (T * 100.0));
            Radial (0.0, 0.0, Float'Max (R, S.RY), (0.38, 0.27, 0.15), (0.25, 0.17, 0.09), 1.0, 0.95);
            Fill (Cr);
            Set_Line_Width (Cr, 1.2);
            Color (0.55, 0.42, 0.28, 0.5);
            for K in 1 .. 3 loop
               New_Path (Cr);
               Arc (Cr, G (-R * 0.2), G (-S.RY * 0.1), G (Float (K) * R * 0.2), G (-2.5), G (-1.2));
               Stroke (Cr);
            end loop;
         when Plank =>
            New_Path (Cr);
            Rectangle (Cr, G (-R + 3.0), G (-S.RY + 4.0), G (2.0 * R), G (2.0 * S.RY));
            Color (0.0, 0.0, 0.0, 0.25);
            Fill (Cr);
            New_Path (Cr);
            Rectangle (Cr, G (-R), G (-S.RY), G (2.0 * R), G (2.0 * S.RY));
            Linear (0.0, -S.RY, 0.0, S.RY, (0.72, 0.55, 0.35), (0.52, 0.38, 0.22));
            Fill (Cr);
            New_Path (Cr);
            Disc (-R + 5.0, 0.0, 1.5);
            Disc (R - 5.0, 0.0, 1.5);
            Color (0.25, 0.25, 0.28);
            Fill (Cr);
         when Pocket =>
            New_Path (Cr);
            Disc (0.0, 0.0, R + 8.0);
            Radial (0.0, 0.0, R + 8.0, (0.45, 0.30, 0.18), (0.25, 0.15, 0.08));
            Fill (Cr);
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            Radial (0.0, 0.0, R, (0.0, 0.0, 0.0), (0.08, 0.08, 0.08));
            Fill (Cr);
         when Snooker_Ball =>
            declare
               Col : constant RGB := Toy_Color (Natural (T * 7.9));
            begin
               New_Path (Cr);
               Disc (0.0, 0.0, R);
               Radial (0.0, 0.0, R, Shade (Col, 1.5), Shade (Col, 0.6));
               Fill (Cr);
               New_Path (Cr);
               Disc (R * 0.1, R * 0.1, R * 0.4);
               Color (1.0, 1.0, 1.0);
               Fill (Cr);
               New_Path (Cr);
               Disc (-R * 0.4, -R * 0.4, R * 0.2);
               Color (1.0, 1.0, 1.0, 0.6);
               Fill (Cr);
            end;
         when Chalk_Cube =>
            New_Path (Cr);
            Rectangle (Cr, G (-R), G (-R), G (2.0 * R), G (2.0 * R));
            Color (0.20, 0.45, 0.80);
            Fill (Cr);
            New_Path (Cr);
            Disc (0.0, 0.0, R * 0.55);
            Color (0.55, 0.75, 0.95);
            Fill (Cr);
         when Cue =>
            New_Path (Cr);
            Move_To (Cr, G (-R), G (-S.RY));
            Line_To (Cr, G (R), G (-S.RY * 0.45));
            Line_To (Cr, G (R), G (S.RY * 0.45));
            Line_To (Cr, G (-R), G (S.RY));
            Close_Path (Cr);
            Linear (-R, 0.0, R, 0.0, (0.25, 0.12, 0.05), (0.90, 0.75, 0.50));
            Fill (Cr);
            New_Path (Cr);
            Rectangle (Cr, G (R - 6.0), G (-S.RY * 0.45), 6.0, G (S.RY * 0.9));
            Color (0.25, 0.45, 0.85);
            Fill (Cr);
         when Eraser =>
            New_Path (Cr);
            Round_Box (-R, -S.RY, 2.0 * R, 2.0 * S.RY, 3.0);
            Color (0.95, 0.60, 0.65);
            Fill (Cr);
            New_Path (Cr);
            Round_Box (-R * 0.3, -S.RY, R * 1.3, 2.0 * S.RY, 2.0);
            Color (0.30, 0.45, 0.85);
            Fill (Cr);
         when Sharpener =>
            New_Path (Cr);
            Round_Box (-R, -S.RY, 2.0 * R, 2.0 * S.RY, 2.0);
            Linear (0.0, -S.RY, 0.0, S.RY, (0.90, 0.92, 0.95), (0.50, 0.52, 0.58));
            Fill (Cr);
            New_Path (Cr);
            Disc (R * 0.2, 0.0, S.RY * 0.55);
            Color (0.15, 0.15, 0.17);
            Fill (Cr);
         when Paper_Clip =>
            Set_Line_Width (Cr, 1.4);
            Color (0.75, 0.78, 0.82);
            New_Path (Cr);
            Round_Box (-R, -S.RY, 2.0 * R, 2.0 * S.RY, S.RY);
            Stroke (Cr);
            New_Path (Cr);
            Round_Box (-R * 0.7, -S.RY * 0.5, 1.5 * R, S.RY, S.RY * 0.5);
            Stroke (Cr);
         when Coin =>
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            Radial (0.0, 0.0, R, (1.0, 0.90, 0.50), (0.70, 0.52, 0.15));
            Fill (Cr);
            New_Path (Cr);
            Arc (Cr, 0.0, 0.0, G (R * 0.8), 0.0, 2.0 * Pi);
            Set_Line_Width (Cr, 1.0);
            Color (0.6, 0.45, 0.1, 0.8);
            Stroke (Cr);
         when Ink_Blot =>
            New_Path (Cr);
            Blob (R, S.RY, 0.5, Integer (T * 100.0));
            Color (0.10, 0.12, 0.45, 0.85);
            Fill (Cr);
            for K in 1 .. 5 loop
               New_Path (Cr);
               Disc (R * 1.2 * Cos (Float (K) * 1.3), S.RY * 1.2 * Sin (Float (K) * 1.3), 2.0 + Float (K mod 3));
               Color (0.10, 0.12, 0.45, 0.85);
               Fill (Cr);
            end loop;
         when Shavings =>
            for K in 1 .. 16 loop
               declare
                  A : constant Float := Random (Rand) * 2.0 * Pi;
                  D : constant Float := Sqrt (Random (Rand)) * 0.8;
                  X : constant Float := R * D * Cos (A);
                  Y : constant Float := S.RY * D * Sin (A);
               begin
                  Save (Cr);
                  Translate (Cr, G (X), G (Y));
                  Rotate (Cr, G (A));
                  New_Path (Cr);
                  Arc (Cr, 0.0, 0.0, 7.0, 0.0, G (Pi * 1.3));
                  Line_To (Cr, 0.0, 0.0);
                  Close_Path (Cr);
                  Color (0.92, 0.80, 0.60);
                  Fill_Preserve (Cr);
                  Set_Line_Width (Cr, 1.2);
                  Color (Toy_Color (K), 0.9);
                  Stroke (Cr);
                  Restore (Cr);
               end;
            end loop;
         when Rubber_Band =>
            New_Path (Cr);
            Oval (R, R * 0.7);
            Set_Line_Width (Cr, 2.0);
            Color (Toy_Color (Natural (T * 7.9)), 0.9);
            Stroke (Cr);
         when Sandcastle =>
            New_Path (Cr);
            Rectangle (Cr, G (-R), G (-R), G (2.0 * R), G (2.0 * R));
            Radial (0.0, 0.0, R * 1.4, (0.95, 0.85, 0.60), (0.75, 0.62, 0.38));
            Fill (Cr);
            for K in 0 .. 3 loop
               declare
                  X : constant Float := (if K mod 2 = 0 then -R else R);
                  Y : constant Float := (if K < 2 then -R else R);
               begin
                  New_Path (Cr);
                  Disc (X, Y, R * 0.42);
                  Radial (X, Y, R * 0.42, (1.0, 0.92, 0.68), (0.72, 0.60, 0.36));
                  Fill (Cr);
               end;
            end loop;
            New_Path (Cr);
            Disc (0.0, 0.0, R * 0.35);
            Radial (0.0, 0.0, R * 0.35, (1.0, 0.92, 0.68), (0.72, 0.60, 0.36));
            Fill (Cr);
            Set_Line_Width (Cr, 1.0);
            Color (0.3, 0.3, 0.3);
            Move_To (Cr, 0.0, 0.0);
            Line_To (Cr, 0.0, G (-R * 0.9));
            Stroke (Cr);
            New_Path (Cr);
            Move_To (Cr, 0.0, G (-R * 0.9));
            Line_To (Cr, G (R * 0.4), G (-R * 0.75));
            Line_To (Cr, 0.0, G (-R * 0.6));
            Close_Path (Cr);
            Color (0.9, 0.15, 0.1);
            Fill (Cr);
         when Bucket =>
            declare
               Col : constant RGB := Toy_Color (Natural (T * 7.9));
            begin
               New_Path (Cr);
               Disc (0.0, 0.0, R);
               Radial (0.0, 0.0, R, Shade (Col, 1.3), Shade (Col, 0.7));
               Fill (Cr);
               New_Path (Cr);
               Disc (0.0, 0.0, R * 0.78);
               Color (0.85, 0.75, 0.52);
               Fill (Cr);
               Set_Line_Width (Cr, 1.6);
               Color (Shade (Col, 0.6));
               New_Path (Cr);
               Arc (Cr, 0.0, 0.0, G (R * 1.1), G (-1.2), G (1.2));
               Stroke (Cr);
            end;
         when Shell =>
            New_Path (Cr);
            Move_To (Cr, 0.0, G (R));
            for K in 0 .. 8 loop
               declare
                  A : constant Float := Pi + Float (K) * Pi / 8.0;
               begin
                  Line_To (Cr, G (R * Cos (A)), G (R * Sin (A) * 1.1 + R * 0.2));
               end;
            end loop;
            Close_Path (Cr);
            Radial (0.0, 0.0, R, (1.0, 0.90, 0.85), (0.85, 0.60, 0.55));
            Fill (Cr);
            Set_Line_Width (Cr, 0.6);
            Color (0.6, 0.4, 0.35, 0.8);
            for K in 1 .. 7 loop
               declare
                  A : constant Float := Pi + Float (K) * Pi / 8.0;
               begin
                  Move_To (Cr, 0.0, G (R));
                  Line_To (Cr, G (R * Cos (A)), G (R * Sin (A) * 1.1 + R * 0.2));
               end;
            end loop;
            Stroke (Cr);
         when Starfish =>
            New_Path (Cr);
            for K in 0 .. 9 loop
               declare
                  A : constant Float := Float (K) * Pi / 5.0;
                  RR : constant Float := (if K mod 2 = 0 then R else R * 0.4);
               begin
                  Line_To (Cr, G (RR * Cos (A)), G (RR * Sin (A)));
               end;
            end loop;
            Close_Path (Cr);
            Color (0.95, 0.50, 0.25);
            Fill (Cr);
         when Towel =>
            New_Path (Cr);
            Rectangle (Cr, G (-R), G (-S.RY), G (2.0 * R), G (2.0 * S.RY));
            Color (0.95, 0.95, 0.92);
            Fill (Cr);
            for K in 0 .. 5 loop
               if K mod 2 = 0 then
                  New_Path (Cr);
                  Rectangle (Cr, G (-R + Float (K) * R / 3.0), G (-S.RY), G (R / 3.0), G (2.0 * S.RY));
                  Color (Toy_Color (Natural (T * 7.9)));
                  Fill (Cr);
               end if;
            end loop;
         when Beach_Ball =>
            for K in 0 .. 5 loop
               New_Path (Cr);
               Move_To (Cr, 0.0, 0.0);
               Arc (Cr, 0.0, 0.0, G (R), G (Float (K) * Pi / 3.0), G (Float (K + 1) * Pi / 3.0));
               Close_Path (Cr);
               Color ((if K mod 2 = 0 then Toy_Color (K / 2) else (0.97, 0.97, 0.97)));
               Fill (Cr);
            end loop;
            New_Path (Cr);
            Disc (-R * 0.35, -R * 0.35, R * 0.3);
            Color (1.0, 1.0, 1.0, 0.4);
            Fill (Cr);
         when Tide_Pool =>
            New_Path (Cr);
            Blob (R + 6.0, S.RY + 6.0, 0.2, Integer (T * 50.0));
            Color (0.75, 0.65, 0.45, 0.8);
            Fill (Cr);
            New_Path (Cr);
            Blob (R, S.RY, 0.15, Integer (T * 50.0) + 3);
            Radial (0.0, 0.0, Float'Max (R, S.RY), (0.45, 0.85, 0.88), (0.15, 0.55, 0.65), 0.9, 0.95);
            Fill (Cr);
            Set_Line_Width (Cr, 1.4);
            Color (1.0, 1.0, 1.0, 0.4);
            for K in 1 .. 3 loop
               New_Path (Cr);
               Arc (Cr, G (-R * 0.2), G (-S.RY * 0.2), G (Float (K) * R * 0.2), G (-2.4), G (-1.6));
               Stroke (Cr);
            end loop;
         when Model_Tree =>
            New_Path (Cr);
            Blob (R, R, 0.25, Integer (T * 90.0));
            Radial (0.0, 0.0, R, (0.40, 0.70, 0.30), (0.12, 0.35, 0.12));
            Fill (Cr);
            for K in 1 .. 6 loop
               New_Path (Cr);
               Disc (R * 0.5 * Cos (Float (K) * 1.1), R * 0.5 * Sin (Float (K) * 1.1), R * 0.3);
               Color (0.35, 0.62, 0.25, 0.6);
               Fill (Cr);
            end loop;
         when House =>
            declare
               Roof : constant RGB := (if T < 0.5 then (0.75, 0.25, 0.15) else (0.30, 0.35, 0.45));
            begin
               New_Path (Cr);
               Rectangle (Cr, G (-R), G (-S.RY), G (2.0 * R), G (S.RY));
               Color (Shade (Roof, 1.2));
               Fill (Cr);
               New_Path (Cr);
               Rectangle (Cr, G (-R), 0.0, G (2.0 * R), G (S.RY));
               Color (Shade (Roof, 0.75));
               Fill (Cr);
               Set_Line_Width (Cr, 0.8);
               Color (0.0, 0.0, 0.0, 0.3);
               Move_To (Cr, G (-R), 0.0);
               Line_To (Cr, G (R), 0.0);
               Stroke (Cr);
               New_Path (Cr);
               Rectangle (Cr, G (R * 0.4), G (-S.RY * 0.75), 6.0, 6.0);
               Color (0.55, 0.30, 0.20);
               Fill (Cr);
            end;
         when Bush =>
            New_Path (Cr);
            Blob (R, R, 0.35, Integer (T * 70.0));
            Radial (0.0, 0.0, R, (0.45, 0.72, 0.30), (0.18, 0.42, 0.14));
            Fill (Cr);
         when Castle =>
            New_Path (Cr);
            Rectangle (Cr, G (-R), G (-S.RY), G (2.0 * R), G (2.0 * S.RY));
            Linear (0.0, -S.RY, 0.0, S.RY, (0.85, 0.75, 0.60), (0.55, 0.45, 0.35));
            Fill (Cr);
            for K in 0 .. 3 loop
               declare
                  X : constant Float := (if K mod 2 = 0 then -R else R);
                  Y : constant Float := (if K < 2 then -S.RY else S.RY);
               begin
                  New_Path (Cr);
                  Disc (X, Y, R * 0.38);
                  Radial (X, Y, R * 0.38, (0.90, 0.80, 0.65), (0.55, 0.45, 0.35));
                  Fill (Cr);
                  New_Path (Cr);
                  Move_To (Cr, G (X), G (Y - R * 0.3));
                  Line_To (Cr, G (X + R * 0.26), G (Y + R * 0.15));
                  Line_To (Cr, G (X - R * 0.26), G (Y + R * 0.15));
                  Close_Path (Cr);
                  Color (0.75, 0.25, 0.25);
                  Fill (Cr);
               end;
            end loop;
            New_Path (Cr);
            Rectangle (Cr, G (-R * 0.25), G (-S.RY * 0.25), G (R * 0.5), G (S.RY * 0.5));
            Color (0.15, 0.12, 0.10);
            Fill (Cr);
         when Chest =>
            New_Path (Cr);
            Round_Box (-R, -S.RY, 2.0 * R, 2.0 * S.RY, 4.0);
            Linear (0.0, -S.RY, 0.0, S.RY, (0.60, 0.38, 0.18), (0.35, 0.20, 0.08));
            Fill (Cr);
            Set_Line_Width (Cr, 2.0);
            Color (0.85, 0.70, 0.20);
            for K in -1 .. 1 loop
               Move_To (Cr, G (Float (K) * R * 0.6), G (-S.RY));
               Line_To (Cr, G (Float (K) * R * 0.6), G (S.RY));
            end loop;
            Stroke (Cr);
            for K in 1 .. 6 loop
               New_Path (Cr);
               Disc ((Random (Rand) - 0.5) * R, (Random (Rand) - 0.5) * S.RY, 2.5);
               Color (1.0, 0.85, 0.2);
               Fill (Cr);
            end loop;
         when Seaweed =>
            Set_Line_Width (Cr, 3.0);
            for K in 1 .. 9 loop
               declare
                  X : constant Float := (Random (Rand) - 0.5) * 1.6 * R;
                  Y : constant Float := (Random (Rand) - 0.5) * 1.6 * S.RY;
                  A : constant Float := Random (Rand) * 2.0 * Pi;
                  L : constant Float := 18.0 + Random (Rand) * 22.0;
               begin
                  New_Path (Cr);
                  Move_To (Cr, G (X), G (Y));
                  Curve_To (Cr, G (X + Cos (A) * L * 0.4 + 6.0), G (Y + Sin (A) * L * 0.4),
                            G (X + Cos (A) * L * 0.7 - 6.0), G (Y + Sin (A) * L * 0.7),
                            G (X + Cos (A) * L), G (Y + Sin (A) * L));
                  Color (0.15 + 0.1 * Random (Rand), 0.50 + 0.2 * Random (Rand), 0.20, 0.9);
                  Stroke (Cr);
               end;
            end loop;
         when Air_Stone =>
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            Radial (0.0, 0.0, R, (0.6, 0.65, 0.75), (0.30, 0.32, 0.40));
            Fill (Cr);
            for K in 1 .. 8 loop
               New_Path (Cr);
               Disc ((Random (Rand) - 0.5) * R * 2.0, (Random (Rand) - 0.5) * R * 2.0, 1.5 + Random (Rand) * 3.0);
               Set_Line_Width (Cr, 0.8);
               Color (1.0, 1.0, 1.0, 0.7);
               Stroke (Cr);
            end loop;
         when Trunk =>
            New_Path (Cr);
            Round_Box (-R, -S.RY, 2.0 * R, 2.0 * S.RY, 3.0);
            Linear (0.0, -S.RY, 0.0, S.RY, (0.45, 0.28, 0.15), (0.25, 0.14, 0.07));
            Fill (Cr);
            Set_Line_Width (Cr, 3.0);
            Color (0.20, 0.15, 0.10);
            for K in -1 .. 1 loop
               if K /= 0 then
                  Move_To (Cr, G (Float (K) * R * 0.55), G (-S.RY));
                  Line_To (Cr, G (Float (K) * R * 0.55), G (S.RY));
               end if;
            end loop;
            Stroke (Cr);
            New_Path (Cr);
            Rectangle (Cr, -4.0, G (S.RY - 6.0), 8.0, 6.0);
            Color (0.8, 0.7, 0.3);
            Fill (Cr);
         when Rocking_Horse =>
            Set_Line_Width (Cr, 3.0);
            Color (0.55, 0.30, 0.15);
            for K in -1 .. 1 loop
               if K /= 0 then
                  New_Path (Cr);
                  Move_To (Cr, G (-R), G (Float (K) * S.RY));
                  Curve_To (Cr, G (-R * 0.3), G (Float (K) * S.RY * 1.2), G (R * 0.3), G (Float (K) * S.RY * 1.2),
                            G (R), G (Float (K) * S.RY));
                  Stroke (Cr);
               end if;
            end loop;
            New_Path (Cr);
            Round_Box (-R * 0.6, -S.RY * 0.5, R * 1.2, S.RY, S.RY * 0.4);
            Color (0.92, 0.90, 0.85);
            Fill (Cr);
            New_Path (Cr);
            Disc (R * 0.7, 0.0, S.RY * 0.45);
            Color (0.92, 0.90, 0.85);
            Fill (Cr);
            New_Path (Cr);
            Rectangle (Cr, G (-R * 0.2), G (-S.RY * 0.5), G (R * 0.4), G (S.RY));
            Color (0.75, 0.15, 0.12);
            Fill (Cr);
         when Carton =>
            New_Path (Cr);
            Rectangle (Cr, G (-R), G (-S.RY), G (2.0 * R), G (2.0 * S.RY));
            Color (0.72, 0.56, 0.36);
            Fill (Cr);
            Set_Line_Width (Cr, 1.0);
            Color (0.45, 0.33, 0.20);
            Move_To (Cr, G (-R), 0.0);
            Line_To (Cr, G (R), 0.0);
            Stroke (Cr);
            New_Path (Cr);
            Rectangle (Cr, G (-R * 0.15), G (-S.RY), G (R * 0.3), G (2.0 * S.RY));
            Color (0.85, 0.78, 0.55, 0.9);
            Fill (Cr);
         when Web =>
            Set_Line_Width (Cr, 0.6);
            Color (0.92, 0.92, 0.95, 0.6);
            for K in 0 .. 7 loop
               Move_To (Cr, 0.0, 0.0);
               Line_To (Cr, G (R * Cos (Float (K) * Pi / 4.0)), G (R * Sin (Float (K) * Pi / 4.0)));
            end loop;
            Stroke (Cr);
            for Ring in 1 .. 4 loop
               New_Path (Cr);
               for K in 0 .. 8 loop
                  Line_To (Cr, G (R * Float (Ring) / 4.5 * Cos (Float (K) * Pi / 4.0)),
                           G (R * Float (Ring) / 4.5 * Sin (Float (K) * Pi / 4.0)));
               end loop;
               Stroke (Cr);
            end loop;
         when Dust_Pile =>
            New_Path (Cr);
            Blob (R, S.RY, 0.4, Integer (T * 100.0));
            Radial (0.0, 0.0, Float'Max (R, S.RY), (0.62, 0.58, 0.52), (0.40, 0.36, 0.32), 0.95, 0.8);
            Fill (Cr);
         when Moonbeam =>
            --  the moonlight through the skylight, lying on the boards
            New_Path (Cr);
            Rectangle (Cr, G (-R), G (-S.RY), G (2.0 * R), G (2.0 * S.RY));
            Color (0.75, 0.82, 1.0, 0.18);
            Fill (Cr);
            Set_Line_Width (Cr, 2.0);
            Color (0.75, 0.82, 1.0, 0.12);
            Move_To (Cr, 0.0, G (-S.RY));
            Line_To (Cr, 0.0, G (S.RY));
            Move_To (Cr, G (-R), 0.0);
            Line_To (Cr, G (R), 0.0);
            Stroke (Cr);
         when Cake =>
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            Radial (0.0, 0.0, R, (1.0, 0.85, 0.90), (0.85, 0.55, 0.65));
            Fill (Cr);
            Set_Line_Width (Cr, 4.0);
            Color (1.0, 1.0, 1.0, 0.9);
            New_Path (Cr);
            for K in 0 .. 24 loop
               declare
                  A : constant Float := Float (K) * 2.0 * Pi / 24.0;
                  RR : constant Float := R * (0.88 + 0.06 * Sin (Float (K) * 3.0));
               begin
                  Line_To (Cr, G (RR * Cos (A)), G (RR * Sin (A)));
               end;
            end loop;
            Stroke (Cr);
            for K in 0 .. 6 loop
               declare
                  A : constant Float := Float (K) * 2.0 * Pi / 7.0;
                  X : constant Float := R * 0.55 * Cos (A);
                  Y : constant Float := R * 0.55 * Sin (A);
               begin
                  New_Path (Cr);
                  Rectangle (Cr, G (X - 2.5), G (Y - 2.5), 5.0, 5.0);
                  Color (Toy_Color (K));
                  Fill (Cr);
                  New_Path (Cr);
                  Disc (X, Y - 1.0, 3.0);
                  Radial (X, Y - 1.0, 3.0, (1.0, 1.0, 0.7), (1.0, 0.55, 0.1));
                  Fill (Cr);
               end;
            end loop;
         when Present =>
            declare
               Col : constant RGB := Toy_Color (Natural (T * 7.9));
            begin
               New_Path (Cr);
               Rectangle (Cr, G (-R), G (-S.RY), G (2.0 * R), G (2.0 * S.RY));
               Linear (-R, -S.RY, R, S.RY, Shade (Col, 1.2), Shade (Col, 0.75));
               Fill (Cr);
               New_Path (Cr);
               Rectangle (Cr, G (-R), -2.5, G (2.0 * R), 5.0);
               Rectangle (Cr, -2.5, G (-S.RY), 5.0, G (2.0 * S.RY));
               Color (1.0, 0.92, 0.3);
               Fill (Cr);
               New_Path (Cr);
               Oval (6.0, 3.5);
               Color (1.0, 0.85, 0.2);
               Fill (Cr);
            end;
         when Party_Hat =>
            declare
               Col : constant RGB := Toy_Color (Natural (T * 7.9));
            begin
               for K in 0 .. 7 loop
                  New_Path (Cr);
                  Move_To (Cr, 0.0, 0.0);
                  Arc (Cr, 0.0, 0.0, G (R), G (Float (K) * Pi / 4.0), G (Float (K + 1) * Pi / 4.0));
                  Close_Path (Cr);
                  Color ((if K mod 2 = 0 then Col else (1.0, 1.0, 1.0)));
                  Fill (Cr);
               end loop;
               New_Path (Cr);
               Disc (0.0, 0.0, R * 0.25);
               Color (1.0, 0.85, 0.2);
               Fill (Cr);
            end;
         when Cupcake =>
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            Color (0.85, 0.65, 0.40);
            Fill (Cr);
            New_Path (Cr);
            Blob (R * 0.85, R * 0.85, 0.25, Integer (T * 90.0));
            Radial (0.0, 0.0, R, (1.0, 0.92, 0.96), Shade (Toy_Color (Natural (T * 7.9)), 1.2));
            Fill (Cr);
            New_Path (Cr);
            Disc (0.0, 0.0, R * 0.22);
            Color (0.85, 0.05, 0.1);
            Fill (Cr);
         when Juice_Spill =>
            New_Path (Cr);
            Blob (R, S.RY, 0.35, Integer (T * 100.0));
            Color (1.0, 0.60, 0.10, 0.70);
            Fill (Cr);
         when Jelly =>
            New_Path (Cr);
            Blob (R, S.RY, 0.3, Integer (T * 100.0));
            Radial (0.0, 0.0, Float'Max (R, S.RY), (0.55, 1.0, 0.45), (0.15, 0.65, 0.20), 0.85, 0.9);
            Fill (Cr);
            New_Path (Cr);
            Oval (R * 0.4, S.RY * 0.25);
            Color (1.0, 1.0, 1.0, 0.35);
            Fill (Cr);
         when Confetti =>
            for K in 1 .. 16 loop
               declare
                  A : constant Float := Random (Rand) * 2.0 * Pi;
                  D : constant Float := Sqrt (Random (Rand)) * R;
               begin
                  Save (Cr);
                  Translate (Cr, G (D * Cos (A)), G (D * Sin (A)));
                  Rotate (Cr, G (A * 3.0));
                  New_Path (Cr);
                  Rectangle (Cr, -2.5, -1.2, 5.0, 2.4);
                  Color (Toy_Color (K));
                  Fill (Cr);
                  Restore (Cr);
               end;
            end loop;
         when Toolbox =>
            New_Path (Cr);
            Round_Box (-R, -S.RY, 2.0 * R, 2.0 * S.RY, 3.0);
            Linear (0.0, -S.RY, 0.0, S.RY, (0.90, 0.20, 0.15), (0.55, 0.08, 0.05));
            Fill (Cr);
            New_Path (Cr);
            Round_Box (-R * 0.4, -4.0, R * 0.8, 8.0, 3.0);
            Color (0.15, 0.15, 0.15);
            Fill (Cr);
            Set_Line_Width (Cr, 1.0);
            Color (0.3, 0.05, 0.03);
            Move_To (Cr, G (-R), 0.0);
            Line_To (Cr, G (R), 0.0);
            Stroke (Cr);
         when Paint_Tin =>
            declare
               Col : constant RGB := Toy_Color (Natural (T * 7.9));
            begin
               New_Path (Cr);
               Disc (0.0, 0.0, R);
               Radial (0.0, 0.0, R, (0.85, 0.86, 0.90), (0.45, 0.47, 0.52));
               Fill (Cr);
               New_Path (Cr);
               Disc (0.0, 0.0, R * 0.78);
               Color (Col);
               Fill (Cr);
               New_Path (Cr);
               Blob (R * 0.5, R * 0.3, 0.5, Integer (T * 60.0));
               Color (Shade (Col, 1.25));
               Fill (Cr);
            end;
         when Spanner =>
            New_Path (Cr);
            Rectangle (Cr, G (-R * 0.7), G (-S.RY * 0.6), G (R * 1.4), G (S.RY * 1.2));
            Linear (0.0, -S.RY, 0.0, S.RY, (0.85, 0.87, 0.92), (0.45, 0.47, 0.52));
            Fill (Cr);
            for E in -1 .. 1 loop
               if E /= 0 then
                  New_Path (Cr);
                  Disc (Float (E) * R * 0.8, 0.0, S.RY * 1.6);
                  Linear (0.0, -S.RY, 0.0, S.RY, (0.85, 0.87, 0.92), (0.45, 0.47, 0.52));
                  Fill (Cr);
                  New_Path (Cr);
                  Disc (Float (E) * R, 0.0, S.RY * 0.8);
                  Color (0.38, 0.38, 0.40);
                  Fill (Cr);
               end if;
            end loop;
         when Oil_Stain =>
            New_Path (Cr);
            Blob (R, S.RY, 0.45, Integer (T * 100.0));
            Color (0.05, 0.05, 0.06, 0.75);
            Fill (Cr);
            New_Path (Cr);
            Oval (R * 0.4, S.RY * 0.3);
            Color (0.5, 0.4, 0.8, 0.2);
            Fill (Cr);
         when Drain =>
            New_Path (Cr);
            Rectangle (Cr, G (-R), G (-S.RY), G (2.0 * R), G (2.0 * S.RY));
            Color (0.20, 0.20, 0.22);
            Fill (Cr);
            Set_Line_Width (Cr, 2.0);
            Color (0.45, 0.45, 0.48);
            for K in -3 .. 3 loop
               Move_To (Cr, G (Float (K) * R / 4.0), G (-S.RY));
               Line_To (Cr, G (Float (K) * R / 4.0), G (S.RY));
            end loop;
            Stroke (Cr);
         when Xmas_Tree =>
            for Layer in 0 .. 4 loop
               declare
                  RL : constant Float := R * (1.0 - 0.18 * Float (Layer));
                  Spikes : constant := 11;
               begin
                  New_Path (Cr);
                  for K in 0 .. 2 * Spikes - 1 loop
                     declare
                        A : constant Float := Float (K) * Pi / Float (Spikes) + Float (Layer) * 0.3;
                        RR : constant Float := (if K mod 2 = 0 then RL else RL * 0.75);
                     begin
                        Line_To (Cr, G (RR * Cos (A)), G (RR * Sin (A)));
                     end;
                  end loop;
                  Close_Path (Cr);
                  Color (0.08 + 0.04 * Float (Layer), 0.32 + 0.07 * Float (Layer), 0.15 + 0.03 * Float (Layer));
                  Fill (Cr);
               end;
            end loop;
            --  baubles and lights on it, and the star on top
            for K in 1 .. 26 loop
               declare
                  A : constant Float := Random (Rand) * 2.0 * Pi;
                  D : constant Float := (0.2 + 0.75 * Random (Rand)) * R;
               begin
                  New_Path (Cr);
                  Disc (D * Cos (A), D * Sin (A), (if K mod 3 = 0 then 5.0 else 2.2));
                  Color ((if K mod 3 = 0 then Toy_Color (K) else (1.0, 0.95, 0.6)));
                  Fill (Cr);
               end;
            end loop;
            New_Path (Cr);
            for K in 0 .. 9 loop
               declare
                  A : constant Float := Float (K) * Pi / 5.0 - Pi / 2.0;
                  RR : constant Float := (if K mod 2 = 0 then 16.0 else 7.0);
               begin
                  Line_To (Cr, G (RR * Cos (A)), G (RR * Sin (A)));
               end;
            end loop;
            Close_Path (Cr);
            Color (1.0, 0.85, 0.15);
            Fill (Cr);
         when Bauble =>
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            Radial (0.0, 0.0, R, Shade (Toy_Color (Natural (T * 7.9)), 1.6), Shade (Toy_Color (Natural (T * 7.9)), 0.6));
            Fill (Cr);
            New_Path (Cr);
            Rectangle (Cr, -2.0, G (-R - 3.0), 4.0, 3.5);
            Color (0.85, 0.75, 0.3);
            Fill (Cr);
         when Candy_Cane =>
            New_Path (Cr);
            Round_Box (-R, -S.RY, 2.0 * R, 2.0 * S.RY, S.RY);
            Color (1.0, 1.0, 1.0);
            Fill (Cr);
            declare
               X : Float := -R;
            begin
               while X < R loop
                  New_Path (Cr);
                  Move_To (Cr, G (X), G (-S.RY));
                  Line_To (Cr, G (X + 4.0), G (-S.RY));
                  Line_To (Cr, G (X + 7.0), G (S.RY));
                  Line_To (Cr, G (X + 3.0), G (S.RY));
                  Close_Path (Cr);
                  Color (0.9, 0.1, 0.1);
                  Fill (Cr);
                  X := X + 9.0;
               end loop;
            end;
            New_Path (Cr);
            Arc (Cr, G (R), G (-S.RY * 2.0), G (S.RY * 2.2), G (-Pi / 2.0), G (Pi / 2.0));
            Set_Line_Width (Cr, G (S.RY * 2.0));
            Color (0.9, 0.1, 0.1);
            Stroke (Cr);
         when Needles =>
            Set_Line_Width (Cr, 1.0);
            for K in 1 .. 40 loop
               declare
                  A : constant Float := Random (Rand) * 2.0 * Pi;
                  D : constant Float := Sqrt (Random (Rand));
                  X : constant Float := R * D * Cos (A);
                  Y : constant Float := S.RY * D * Sin (A);
                  B : constant Float := Random (Rand) * Pi;
               begin
                  Move_To (Cr, G (X), G (Y));
                  Line_To (Cr, G (X + 6.0 * Cos (B)), G (Y + 6.0 * Sin (B)));
               end;
            end loop;
            Color (0.15, 0.40, 0.15, 0.9);
            Stroke (Cr);
         when Crater =>
            New_Path (Cr);
            Disc (0.0, 0.0, R * 1.12);
            Color (0.75, 0.75, 0.77, 0.8);
            Fill (Cr);
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            Radial (R * 0.2, R * 0.2, R, (0.30, 0.30, 0.32), (0.55, 0.55, 0.57));
            Fill (Cr);
         when Moon_Rock =>
            New_Path (Cr);
            Blob (R, R * 0.8, 0.35, Integer (T * 300.0));
            Radial (0.0, 0.0, R, (0.78, 0.78, 0.80), (0.38, 0.38, 0.40));
            Fill (Cr);
         when Lander =>
            Set_Line_Width (Cr, 2.5);
            Color (0.75, 0.75, 0.78);
            for K in 0 .. 3 loop
               Move_To (Cr, 0.0, 0.0);
               Line_To (Cr, G (R * Cos (Float (K) * Pi / 2.0 + 0.78)), G (R * Sin (Float (K) * Pi / 2.0 + 0.78)));
            end loop;
            Stroke (Cr);
            New_Path (Cr);
            for K in 0 .. 7 loop
               Line_To (Cr, G (R * 0.55 * Cos (Float (K) * Pi / 4.0)), G (R * 0.55 * Sin (Float (K) * Pi / 4.0)));
            end loop;
            Close_Path (Cr);
            Color (0.85, 0.70, 0.20);
            Fill (Cr);
            New_Path (Cr);
            Disc (0.0, 0.0, R * 0.3);
            Color (0.85, 0.86, 0.90);
            Fill (Cr);
         when Flag =>
            Set_Line_Width (Cr, 1.5);
            Color (0.8, 0.8, 0.8);
            Move_To (Cr, 0.0, 0.0);
            Line_To (Cr, 0.0, -30.0);
            Stroke (Cr);
            New_Path (Cr);
            Rectangle (Cr, 0.0, -30.0, 20.0, 12.0);
            Color (Toy_Color (Natural (T * 7.9)));
            Fill (Cr);
         when Dome =>
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            Radial (-R * 0.2, -R * 0.2, R, (0.95, 0.97, 1.0), (0.55, 0.60, 0.70));
            Fill (Cr);
            Set_Line_Width (Cr, 1.0);
            Color (0.4, 0.45, 0.55, 0.7);
            for K in 1 .. 3 loop
               New_Path (Cr);
               Arc (Cr, 0.0, 0.0, G (R * Float (K) / 3.5), 0.0, 2.0 * Pi);
               Stroke (Cr);
            end loop;
            for K in 0 .. 5 loop
               Move_To (Cr, 0.0, 0.0);
               Line_To (Cr, G (R * Cos (Float (K) * Pi / 3.0)), G (R * Sin (Float (K) * Pi / 3.0)));
            end loop;
            Stroke (Cr);
         when Pumpkin =>
            for K in 0 .. 5 loop
               New_Path (Cr);
               Save (Cr);
               Rotate (Cr, G (Float (K) * Pi / 6.0));
               Oval (R, R * 0.55);
               Restore (Cr);
               Color (0.95 - 0.05 * Float (K mod 2), 0.48, 0.08);
               Fill (Cr);
            end loop;
            New_Path (Cr);
            Disc (0.0, 0.0, R * 0.85);
            Radial (0.0, 0.0, R * 0.85, (1.0, 0.65, 0.15), (0.85, 0.38, 0.05));
            Fill (Cr);
            --  a carved face, lit from inside
            Color (1.0, 0.92, 0.35);
            for S in -1 .. 1 loop
               if S /= 0 then
                  New_Path (Cr);
                  Move_To (Cr, G (Float (S) * R * 0.35), G (-R * 0.35));
                  Line_To (Cr, G (Float (S) * R * 0.15), G (-R * 0.05));
                  Line_To (Cr, G (Float (S) * R * 0.55), G (-R * 0.05));
                  Close_Path (Cr);
                  Fill (Cr);
               end if;
            end loop;
            New_Path (Cr);
            Move_To (Cr, G (-R * 0.5), G (R * 0.2));
            Line_To (Cr, G (-R * 0.25), G (R * 0.45));
            Line_To (Cr, 0.0, G (R * 0.25));
            Line_To (Cr, G (R * 0.25), G (R * 0.45));
            Line_To (Cr, G (R * 0.5), G (R * 0.2));
            Close_Path (Cr);
            Fill (Cr);
            New_Path (Cr);
            Rectangle (Cr, -2.0, G (-R - 4.0), 4.0, 6.0);
            Color (0.25, 0.40, 0.12);
            Fill (Cr);
         when Gravestone =>
            New_Path (Cr);
            Move_To (Cr, G (-R), G (S.RY));
            Line_To (Cr, G (-R), G (-S.RY + R));
            Arc (Cr, 0.0, G (-S.RY + R), G (R), G (Pi), 0.0);
            Line_To (Cr, G (R), G (S.RY));
            Close_Path (Cr);
            Linear (-R, 0.0, R, 0.0, (0.62, 0.62, 0.66), (0.35, 0.35, 0.40));
            Fill (Cr);
            Set_Line_Width (Cr, 1.4);
            Color (0.25, 0.25, 0.28);
            Move_To (Cr, 0.0, G (-S.RY + R * 0.5));
            Line_To (Cr, 0.0, G (-S.RY + R * 1.8));
            Move_To (Cr, G (-R * 0.4), G (-S.RY + R));
            Line_To (Cr, G (R * 0.4), G (-S.RY + R));
            Stroke (Cr);
         when Cauldron =>
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            Radial (0.0, 0.0, R, (0.25, 0.25, 0.28), (0.05, 0.05, 0.06));
            Fill (Cr);
            New_Path (Cr);
            Disc (0.0, 0.0, R * 0.78);
            Radial (0.0, 0.0, R * 0.78, (0.55, 1.0, 0.35), (0.15, 0.55, 0.10));
            Fill (Cr);
            for K in 1 .. 7 loop
               New_Path (Cr);
               Disc ((Random (Rand) - 0.5) * R, (Random (Rand) - 0.5) * R, 2.0 + Random (Rand) * 4.0);
               Set_Line_Width (Cr, 1.2);
               Color (0.75, 1.0, 0.6, 0.9);
               Stroke (Cr);
            end loop;
         when Candle =>
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            Color (0.95, 0.92, 0.85);
            Fill (Cr);
            New_Path (Cr);
            Disc (0.0, 0.0, R * 0.45);
            Radial (0.0, 0.0, R * 0.45, (1.0, 1.0, 0.7), (1.0, 0.6, 0.1));
            Fill (Cr);
         when Fog =>
            for K in 1 .. 7 loop
               declare
                  A : constant Float := Float (K) * 2.0 * Pi / 7.0 + T * 3.0;
                  X : constant Float := R * 0.5 * Cos (A);
                  Y : constant Float := S.RY * 0.5 * Sin (A);
                  BR : constant Float := Float'Min (R, S.RY) * 0.7;
               begin
                  New_Path (Cr);
                  Disc (X, Y, BR);
                  Radial (X, Y, BR, (0.80, 0.80, 0.90), (0.55, 0.55, 0.70), 0.45, 0.0);
                  Fill (Cr);
               end;
            end loop;
         when Easter_Egg =>
            declare
               Col : constant RGB := Mix (Toy_Color (Natural (T * 7.9)), (1.0, 1.0, 1.0), 0.45);
            begin
               New_Path (Cr);
               Move_To (Cr, G (R), 0.0);
               Curve_To (Cr, G (R), G (-S.RY * 1.1), G (-R), G (-S.RY * 1.3), G (-R), 0.0);
               Curve_To (Cr, G (-R), G (S.RY * 1.3), G (R), G (S.RY * 1.1), G (R), 0.0);
               Close_Path (Cr);
               Radial (0.0, 0.0, R, Shade (Col, 1.2), Shade (Col, 0.8));
               Fill (Cr);
               --  a zigzag band, and dots
               Set_Line_Width (Cr, 2.0);
               Color (1.0, 1.0, 1.0, 0.9);
               New_Path (Cr);
               for K in 0 .. 6 loop
                  Line_To (Cr, G (-R * 0.15 + (if K mod 2 = 0 then -3.0 else 3.0)), G (-S.RY + Float (K) * S.RY / 3.0));
               end loop;
               Stroke (Cr);
               for K in 0 .. 2 loop
                  New_Path (Cr);
                  Disc (R * 0.45, (Float (K) - 1.0) * S.RY * 0.55, 1.6);
                  Color (Shade (Toy_Color (Natural (T * 7.9) + 3), 1.0));
                  Fill (Cr);
               end loop;
            end;
         when Choc_Bunny =>
            New_Path (Cr);
            Oval (R, S.RY);
            Radial (0.0, 0.0, R, (0.60, 0.38, 0.22), (0.32, 0.18, 0.08));
            Fill (Cr);
            New_Path (Cr);
            Disc (R * 0.7, 0.0, S.RY * 0.6);
            Radial (R * 0.7, 0.0, S.RY * 0.6, (0.62, 0.40, 0.24), (0.35, 0.20, 0.10));
            Fill (Cr);
            for E in -1 .. 1 loop
               if E /= 0 then
                  Save (Cr);
                  Translate (Cr, G (R * 1.1), G (Float (E) * S.RY * 0.35));
                  Rotate (Cr, G (Float (E) * 0.3));
                  New_Path (Cr);
                  Oval (R * 0.45, S.RY * 0.18);
                  Color (0.45, 0.27, 0.12);
                  Fill (Cr);
                  Restore (Cr);
               end if;
            end loop;
            New_Path (Cr);
            Disc (-R * 0.2, 0.0, S.RY * 0.35);
            Color (0.9, 0.2, 0.3);
            Fill (Cr);
         when Basket =>
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            Radial (0.0, 0.0, R, (0.85, 0.65, 0.35), (0.55, 0.38, 0.18));
            Fill (Cr);
            Set_Line_Width (Cr, 0.8);
            Color (0.45, 0.30, 0.12, 0.8);
            for K in 1 .. 4 loop
               New_Path (Cr);
               Arc (Cr, 0.0, 0.0, G (R * Float (K) / 4.5), 0.0, 2.0 * Pi);
               Stroke (Cr);
            end loop;
            for K in 0 .. 4 loop
               declare
                  A : constant Float := Float (K) * 2.0 * Pi / 5.0;
               begin
                  New_Path (Cr);
                  Save (Cr);
                  Translate (Cr, G (R * 0.45 * Cos (A)), G (R * 0.45 * Sin (A)));
                  Rotate (Cr, G (A));
                  Oval (R * 0.32, R * 0.22);
                  Restore (Cr);
                  Color (Mix (Toy_Color (K), (1.0, 1.0, 1.0), 0.4));
                  Fill (Cr);
               end;
            end loop;
            Set_Line_Width (Cr, 3.0);
            Color (0.65, 0.45, 0.22);
            New_Path (Cr);
            Move_To (Cr, G (-R), 0.0);
            Curve_To (Cr, G (-R * 0.5), G (-R * 0.3), G (R * 0.5), G (-R * 0.3), G (R), 0.0);
            Stroke (Cr);
         when Daffodil =>
            for K in 0 .. 5 loop
               Save (Cr);
               Rotate (Cr, G (Float (K) * Pi / 3.0));
               Translate (Cr, G (R * 0.5), 0.0);
               New_Path (Cr);
               Oval (R * 0.5, R * 0.3);
               Color (1.0, 0.95, 0.45);
               Fill (Cr);
               Restore (Cr);
            end loop;
            New_Path (Cr);
            Disc (0.0, 0.0, R * 0.35);
            Color (1.0, 0.62, 0.10);
            Fill (Cr);
         when Nest =>
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            Color (0.80, 0.68, 0.35);
            Fill (Cr);
            Set_Line_Width (Cr, 1.0);
            for K in 1 .. 40 loop
               declare
                  A : constant Float := Random (Rand) * 2.0 * Pi;
                  D : constant Float := Sqrt (Random (Rand)) * R;
                  B : constant Float := Random (Rand) * Pi;
               begin
                  Move_To (Cr, G (D * Cos (A)), G (D * Sin (A)));
                  Line_To (Cr, G (D * Cos (A) + 9.0 * Cos (B)), G (D * Sin (A) + 9.0 * Sin (B)));
               end;
            end loop;
            Color (0.60, 0.48, 0.20, 0.9);
            Stroke (Cr);
         when Pawn | Rook | Knight_Piece | Bishop | Queen | King =>
            declare
               White : constant Boolean := T < 0.5;
               Light : constant RGB := (if White then (1.0, 0.97, 0.88) else (0.32, 0.30, 0.30));
               Dark : constant RGB := (if White then (0.72, 0.66, 0.55) else (0.06, 0.05, 0.05));
               Top : constant RGB := (if White then (0.95, 0.90, 0.80) else (0.18, 0.17, 0.17));
            begin
               --  the base, then the piece's own top
               New_Path (Cr);
               Disc (0.0, 0.0, R);
               Radial (0.0, 0.0, R, Light, Dark);
               Fill (Cr);
               New_Path (Cr);
               Arc (Cr, 0.0, 0.0, G (R * 0.78), 0.0, 2.0 * Pi);
               Set_Line_Width (Cr, 1.0);
               Color (Dark);
               Stroke (Cr);
               case It.Kind is
                  when Pawn =>
                     New_Path (Cr);
                     Disc (0.0, 0.0, R * 0.48);
                     Radial (0.0, 0.0, R * 0.48, Light, Top);
                     Fill (Cr);
                  when Rook =>
                     New_Path (Cr);
                     Rectangle (Cr, G (-R * 0.55), G (-R * 0.55), G (R * 1.1), G (R * 1.1));
                     Color (Top);
                     Fill (Cr);
                     New_Path (Cr);
                     Rectangle (Cr, G (-R * 0.3), G (-R * 0.3), G (R * 0.6), G (R * 0.6));
                     Color (Dark);
                     Fill (Cr);
                     for K in 0 .. 3 loop
                        New_Path (Cr);
                        Rectangle (Cr, G ((if K mod 2 = 0 then -1.0 else 1.0) * R * 0.55 - 2.0),
                                   G ((if K < 2 then -1.0 else 1.0) * R * 0.55 - 2.0), 4.0, 4.0);
                        Color (Light);
                        Fill (Cr);
                     end loop;
                  when Knight_Piece =>
                     --  the horse's head, looking along its turn
                     New_Path (Cr);
                     Move_To (Cr, G (-R * 0.4), G (-R * 0.45));
                     Curve_To (Cr, G (R * 0.2), G (-R * 0.7), G (R * 0.9), G (-R * 0.3), G (R * 0.75), G (R * 0.15));
                     Line_To (Cr, G (R * 0.2), G (R * 0.2));
                     Line_To (Cr, G (-R * 0.2), G (R * 0.5));
                     Close_Path (Cr);
                     Color (Top);
                     Fill (Cr);
                     New_Path (Cr);
                     Disc (R * 0.35, -R * 0.2, 1.6);
                     Color (Dark);
                     Fill (Cr);
                  when Bishop =>
                     New_Path (Cr);
                     Oval (R * 0.5, R * 0.42);
                     Color (Top);
                     Fill (Cr);
                     Set_Line_Width (Cr, 2.0);
                     Color (Dark);
                     Move_To (Cr, G (-R * 0.3), G (-R * 0.25));
                     Line_To (Cr, G (R * 0.3), G (R * 0.25));
                     Stroke (Cr);
                     New_Path (Cr);
                     Disc (0.0, 0.0, 2.0);
                     Color (Light);
                     Fill (Cr);
                  when Queen | King =>
                     New_Path (Cr);
                     for K in 0 .. 15 loop
                        declare
                           A : constant Float := Float (K) * Pi / 8.0;
                           RR : constant Float := (if K mod 2 = 0 then R * 0.65 else R * 0.45);
                        begin
                           Line_To (Cr, G (RR * Cos (A)), G (RR * Sin (A)));
                        end;
                     end loop;
                     Close_Path (Cr);
                     Color (Top);
                     Fill (Cr);
                     if It.Kind = King then
                        New_Path (Cr);
                        Rectangle (Cr, -2.0, G (-R * 0.35), 4.0, G (R * 0.7));
                        Rectangle (Cr, G (-R * 0.35), -2.0, G (R * 0.7), 4.0);
                        Color (0.85, 0.70, 0.20);
                        Fill (Cr);
                     else
                        New_Path (Cr);
                        Disc (0.0, 0.0, R * 0.2);
                        Color (0.85, 0.70, 0.20);
                        Fill (Cr);
                     end if;
                  when others => null;
               end case;
            end;
         when Chess_Clock =>
            New_Path (Cr);
            Round_Box (-R, -S.RY, 2.0 * R, 2.0 * S.RY, 4.0);
            Linear (0.0, -S.RY, 0.0, S.RY, (0.55, 0.35, 0.18), (0.30, 0.18, 0.08));
            Fill (Cr);
            for E in -1 .. 1 loop
               if E /= 0 then
                  New_Path (Cr);
                  Disc (Float (E) * R * 0.5, 0.0, S.RY * 0.75);
                  Color (0.96, 0.95, 0.90);
                  Fill (Cr);
                  Set_Line_Width (Cr, 1.2);
                  Color (0.1, 0.1, 0.1);
                  Move_To (Cr, G (Float (E) * R * 0.5), 0.0);
                  Line_To (Cr, G (Float (E) * R * 0.5 + 5.0), G (-S.RY * 0.5));
                  Stroke (Cr);
                  New_Path (Cr);
                  Rectangle (Cr, G (Float (E) * R * 0.5 - 3.0), G (-S.RY - 4.0), 6.0, 4.0);
                  Color (0.85, 0.15, 0.1);
                  Fill (Cr);
               end if;
            end loop;
         when Crystal =>
            declare
               Col : constant RGB := (if T < 0.5 then (0.35, 1.0, 0.55) else (0.75, 0.45, 1.0));
            begin
               New_Path (Cr);
               Disc (0.0, 0.0, R * 1.4);
               Radial (0.0, 0.0, R * 1.4, Col, Col, 0.35, 0.0);
               Fill (Cr);
               for K in 0 .. 4 loop
                  Save (Cr);
                  Rotate (Cr, G (Float (K) * 2.0 * Pi / 5.0 + T));
                  New_Path (Cr);
                  Move_To (Cr, 0.0, G (-R * 0.25));
                  Line_To (Cr, G (R * (0.8 + 0.2 * Float (K mod 2))), 0.0);
                  Line_To (Cr, 0.0, G (R * 0.25));
                  Close_Path (Cr);
                  Linear (0.0, 0.0, R, 0.0, Shade (Col, 0.6), Mix (Col, (1.0, 1.0, 1.0), 0.6));
                  Fill (Cr);
                  Restore (Cr);
               end loop;
            end;
         when Alien_Plant =>
            Set_Line_Width (Cr, 4.0);
            for K in 0 .. 6 loop
               declare
                  A : constant Float := Float (K) * 2.0 * Pi / 7.0 + T * 2.0;
               begin
                  New_Path (Cr);
                  Move_To (Cr, 0.0, 0.0);
                  Curve_To (Cr, G (R * 0.5 * Cos (A)), G (R * 0.5 * Sin (A)),
                            G (R * 0.8 * Cos (A + 0.5)), G (R * 0.8 * Sin (A + 0.5)),
                            G (R * Cos (A + 0.3)), G (R * Sin (A + 0.3)));
                  Color (0.55, 0.20, 0.65);
                  Stroke (Cr);
                  New_Path (Cr);
                  Disc (R * Cos (A + 0.3), R * Sin (A + 0.3), 3.0);
                  Color (0.40, 1.0, 0.50);
                  Fill (Cr);
               end;
            end loop;
            New_Path (Cr);
            Disc (0.0, 0.0, R * 0.3);
            Radial (0.0, 0.0, R * 0.3, (0.95, 0.55, 1.0), (0.45, 0.10, 0.55));
            Fill (Cr);
         when Goo_Pool =>
            New_Path (Cr);
            Blob (R, S.RY, 0.35, Integer (T * 100.0));
            Radial (0.0, 0.0, Float'Max (R, S.RY), (0.70, 1.0, 0.30), (0.20, 0.70, 0.10), 0.95, 0.9);
            Fill (Cr);
            for K in 1 .. 5 loop
               New_Path (Cr);
               Disc ((Random (Rand) - 0.5) * R, (Random (Rand) - 0.5) * S.RY, 2.0 + Random (Rand) * 3.0);
               Set_Line_Width (Cr, 1.2);
               Color (0.90, 1.0, 0.70, 0.8);
               Stroke (Cr);
            end loop;
         when Egg_Pod =>
            New_Path (Cr);
            Oval (R, S.RY);
            Radial (0.0, 0.0, R, (0.85, 0.75, 0.55), (0.45, 0.35, 0.25));
            Fill (Cr);
            Set_Line_Width (Cr, 0.8);
            Color (0.55, 0.15, 0.25, 0.8);
            for K in -1 .. 1 loop
               Move_To (Cr, G (-R * 0.8), G (Float (K) * S.RY * 0.4));
               Curve_To (Cr, G (-R * 0.2), G (Float (K) * S.RY * 0.7), G (R * 0.2), G (Float (K) * S.RY * 0.1),
                         G (R * 0.8), G (Float (K) * S.RY * 0.4));
            end loop;
            Stroke (Cr);
         when Spire =>
            New_Path (Cr);
            for K in 0 .. 13 loop
               declare
                  A : constant Float := Float (K) * Pi / 7.0;
                  RR : constant Float := (if K mod 2 = 0 then R else R * 0.6);
               begin
                  Line_To (Cr, G (RR * Cos (A)), G (RR * Sin (A)));
               end;
            end loop;
            Close_Path (Cr);
            Radial (0.0, 0.0, R, (0.60, 0.45, 0.75), (0.25, 0.15, 0.35));
            Fill (Cr);
         when Spores =>
            for K in 1 .. 30 loop
               declare
                  A : constant Float := Random (Rand) * 2.0 * Pi;
                  D : constant Float := Sqrt (Random (Rand));
               begin
                  New_Path (Cr);
                  Disc (R * D * Cos (A), S.RY * D * Sin (A), 2.0 + Random (Rand) * 3.0);
                  Color (0.85, 0.45, 1.0, 0.55);
                  Fill (Cr);
               end;
            end loop;
         when Igloo =>
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            Radial (-R * 0.2, -R * 0.2, R, (1.0, 1.0, 1.0), (0.72, 0.80, 0.92));
            Fill (Cr);
            Set_Line_Width (Cr, 1.0);
            Color (0.60, 0.70, 0.85, 0.8);
            for Ring in 1 .. 3 loop
               New_Path (Cr);
               Arc (Cr, 0.0, 0.0, G (R * Float (Ring) / 3.5), 0.0, 2.0 * Pi);
               Stroke (Cr);
               for K in 0 .. 5 + Ring * 2 loop
                  declare
                     A : constant Float := Float (K) * 2.0 * Pi / Float (6 + Ring * 2) + Float (Ring) * 0.3;
                     R0 : constant Float := R * Float (Ring) / 3.5;
                     R1 : constant Float := R * Float'Min (1.0, Float (Ring + 1) / 3.5);
                  begin
                     Move_To (Cr, G (R0 * Cos (A)), G (R0 * Sin (A)));
                     Line_To (Cr, G (R1 * Cos (A)), G (R1 * Sin (A)));
                  end;
               end loop;
               Stroke (Cr);
            end loop;
            --  the way in
            New_Path (Cr);
            Round_Box (R * 0.8, -R * 0.28, R * 0.55, R * 0.56, R * 0.2);
            Color (0.85, 0.90, 0.98);
            Fill (Cr);
            New_Path (Cr);
            Round_Box (R * 0.95, -R * 0.16, R * 0.4, R * 0.32, R * 0.1);
            Color (0.15, 0.20, 0.30);
            Fill (Cr);
         when Ice_Block =>
            New_Path (Cr);
            Rectangle (Cr, G (-R), G (-S.RY), G (2.0 * R), G (2.0 * S.RY));
            Linear (-R, -S.RY, R, S.RY, (0.85, 0.95, 1.0), (0.50, 0.70, 0.88));
            Fill (Cr);
            Set_Line_Width (Cr, 1.5);
            Color (1.0, 1.0, 1.0, 0.7);
            Move_To (Cr, G (-R * 0.7), G (-S.RY * 0.6));
            Line_To (Cr, G (R * 0.2), G (-S.RY * 0.6));
            Stroke (Cr);
         when Seal =>
            New_Path (Cr);
            Oval (R, S.RY);
            Radial (0.0, 0.0, R, (0.65, 0.65, 0.70), (0.35, 0.35, 0.40));
            Fill (Cr);
            for E in -1 .. 1 loop
               if E /= 0 then
                  New_Path (Cr);
                  Save (Cr);
                  Translate (Cr, G (R * 0.2), G (Float (E) * S.RY));
                  Oval (R * 0.25, S.RY * 0.35);
                  Restore (Cr);
                  Color (0.35, 0.35, 0.40);
                  Fill (Cr);
               end if;
            end loop;
            New_Path (Cr);
            Move_To (Cr, G (-R), 0.0);
            Line_To (Cr, G (-R * 1.4), G (-S.RY * 0.6));
            Line_To (Cr, G (-R * 1.4), G (S.RY * 0.6));
            Close_Path (Cr);
            Color (0.35, 0.35, 0.40);
            Fill (Cr);
            New_Path (Cr);
            Disc (R * 0.8, 0.0, S.RY * 0.55);
            Color (0.60, 0.60, 0.66);
            Fill (Cr);
            for E in -1 .. 1 loop
               if E /= 0 then
                  New_Path (Cr);
                  Disc (R * 0.95, Float (E) * S.RY * 0.25, 1.4);
                  Color (0.05, 0.05, 0.05);
                  Fill (Cr);
               end if;
            end loop;
         when Ice_Patch =>
            New_Path (Cr);
            Blob (R, S.RY, 0.2, Integer (T * 100.0));
            Radial (0.0, 0.0, Float'Max (R, S.RY), (0.82, 0.92, 1.0), (0.55, 0.75, 0.92), 0.95, 0.95);
            Fill (Cr);
            Set_Line_Width (Cr, 0.8);
            Color (1.0, 1.0, 1.0, 0.7);
            for K in 1 .. 4 loop
               declare
                  A : Float := Random (Rand) * 2.0 * Pi;
                  PX : constant Float := (Random (Rand) - 0.5) * R;
                  PY : constant Float := (Random (Rand) - 0.5) * S.RY;
                  P : Vec := (PX, PY);
               begin
                  New_Path (Cr);
                  Move_To (Cr, G (P.X), G (P.Y));
                  for Seg in 1 .. 4 loop
                     A := A + Spread (Rand) * 0.8;
                     P := P + Dir (A) * 8.0;
                     Line_To (Cr, G (P.X), G (P.Y));
                  end loop;
                  Stroke (Cr);
               end;
            end loop;
         when Fish_Hole =>
            New_Path (Cr);
            Disc (0.0, 0.0, R + 6.0);
            Color (0.90, 0.95, 1.0);
            Fill (Cr);
            New_Path (Cr);
            Disc (0.0, 0.0, R);
            Radial (0.0, 0.0, R, (0.10, 0.25, 0.40), (0.02, 0.08, 0.15));
            Fill (Cr);
            Set_Line_Width (Cr, 0.7);
            Color (0.9, 0.9, 0.9, 0.8);
            Move_To (Cr, 0.0, 0.0);
            Line_To (Cr, G (R + 14.0), G (-R - 6.0));
            Stroke (Cr);
            New_Path (Cr);
            Rectangle (Cr, G (R + 12.0), G (-R - 10.0), 5.0, 5.0);
            Color (0.85, 0.15, 0.1);
            Fill (Cr);
         when Ramp_Piece =>
            if Tracks.Theme in Mud | Arctic then
               --  a mound of packed earth across the track: up the face, over the lip,
               --  and its shadow down the back
               declare
                  P : constant Cairo_Pattern := Cairo.Pattern.Create_Linear (G (-R - 14.0), 0.0, G (R + 16.0), 0.0);
               begin
                  if Tracks.Theme = Arctic then
                     --  a kicker of packed snow
                     Cairo.Pattern.Add_Color_Stop_Rgba (P, 0.0, 0.80, 0.86, 0.95, 0.0);
                     Cairo.Pattern.Add_Color_Stop_Rgb (P, 0.25, 0.82, 0.88, 0.96);
                     Cairo.Pattern.Add_Color_Stop_Rgb (P, 0.62, 1.0, 1.0, 1.0);
                     Cairo.Pattern.Add_Color_Stop_Rgb (P, 0.70, 0.55, 0.65, 0.80);
                  else
                     Cairo.Pattern.Add_Color_Stop_Rgba (P, 0.0, 0.45, 0.33, 0.20, 0.0);
                     Cairo.Pattern.Add_Color_Stop_Rgb (P, 0.25, 0.55, 0.41, 0.25);
                     Cairo.Pattern.Add_Color_Stop_Rgb (P, 0.62, 0.86, 0.70, 0.48);
                     Cairo.Pattern.Add_Color_Stop_Rgb (P, 0.70, 0.30, 0.21, 0.11);
                  end if;
                  Cairo.Pattern.Add_Color_Stop_Rgba (P, 1.0, 0.25, 0.17, 0.09, 0.0);
                  New_Path (Cr);
                  Round_Box (-R - 14.0, -S.RY, 2.0 * R + 30.0, 2.0 * S.RY, 6.0);
                  Set_Source (Cr, P);
                  Fill (Cr);
                  Cairo.Pattern.Destroy (P);
               end;
               Set_Line_Width (Cr, 1.0);
               Color (0.30, 0.20, 0.10, 0.4);
               for K in -3 .. 3 loop
                  Move_To (Cr, G (-R - 8.0), G (Float (K) * S.RY * 0.28));
                  Line_To (Cr, G (R + 2.0), G (Float (K) * S.RY * 0.28));
               end loop;
               Stroke (Cr);
               Restore (Cr);
               return;
            end if;
            declare
               L : constant Float := R;
               W : constant Float := S.RY;
               Stripe : Float := -W;
               N : Natural := 0;
            begin
               New_Path (Cr);
               Rectangle (Cr, G (-L), G (-W), G (2.0 * L), G (2.0 * W));
               Linear (-L, 0.0, L, 0.0, (0.45, 0.30, 0.18), (0.92, 0.75, 0.50));
               Fill (Cr);
               --  the stripes on its lip
               while Stripe < W loop
                  New_Path (Cr);
                  Rectangle (Cr, G (L - 5.0), G (Stripe), 5.0, 6.0);
                  if N mod 2 = 0 then
                     Color (0.98, 0.82, 0.1);
                  else
                     Color (0.1, 0.1, 0.1);
                  end if;
                  Fill (Cr);
                  Stripe := Stripe + 6.0;
                  N := N + 1;
               end loop;
               Set_Line_Width (Cr, 1.0);
               Color (0.3, 0.2, 0.1, 0.6);
               for K in 1 .. 3 loop
                  Move_To (Cr, G (-L + Float (K) * L * 0.5), G (-W));
                  Line_To (Cr, G (-L + Float (K) * L * 0.5), G (W));
               end loop;
               Stroke (Cr);
            end;
         when Boost_Pad =>
            declare
               L : constant Float := R;
               W : constant Float := S.RY;
            begin
               New_Path (Cr);
               Round_Box (-L, -W, 2.0 * L, 2.0 * W, 3.0);
               Color (0.12, 0.12, 0.14);
               Fill (Cr);
               for K in 0 .. 2 loop
                  declare
                     X : constant Float := -L + 6.0 + Float (K) * (2.0 * L - 10.0) / 3.0;
                  begin
                     New_Path (Cr);
                     Move_To (Cr, G (X), G (-W + 3.0));
                     Line_To (Cr, G (X + 9.0), 0.0);
                     Line_To (Cr, G (X), G (W - 3.0));
                     Line_To (Cr, G (X + 4.0), G (W - 3.0));
                     Line_To (Cr, G (X + 13.0), 0.0);
                     Line_To (Cr, G (X + 4.0), G (-W + 3.0));
                     Close_Path (Cr);
                     Color (1.0, 0.55 + 0.15 * Float (K), 0.1);
                     Fill (Cr);
                  end;
               end loop;
            end;
      end case;
      Restore (Cr);
   end Draw_Item;

   ---------------------------------------------------------------------------
   --  The road
   ---------------------------------------------------------------------------

   function Edge (K : Integer; Side, Inset : Float) return Vec is
      S : constant Sample := Get (K);
   begin
      return S.P + Perp (S.T) * (Side * (S.Width * 0.5 - Inset));
   end Edge;

   procedure Edge_Path (Side, Inset : Float) is
   begin
      New_Path (Cr);
      for K in 0 .. Tracks.Count - 1 loop
         declare
            E : constant Vec := Edge (K, Side, Inset);
         begin
            Line_To (Cr, G (E.X), G (E.Y));
         end;
      end loop;
      Close_Path (Cr);
   end Edge_Path;

   procedure Road_Path (Grow : Float := 0.0; Offset : Vec := Zero) is
   begin
      New_Path (Cr);
      for K in 0 .. Tracks.Count - 1 loop
         declare
            S : constant Sample := Get (K);
         begin
            Disc (S.P.X + Offset.X, S.P.Y + Offset.Y, S.Width * 0.5 + Grow);
         end;
      end loop;
   end Road_Path;

   procedure Kerbs (Red, White : RGB) is
      --  Striped on the outside and inside of the bends
   begin
      for K in 0 .. Tracks.Count - 1 loop
         if abs Get (K).Turn > 0.0028 or else abs Get (K + 3).Turn > 0.0028
           or else abs Get (K - 3).Turn > 0.0028
         then
            for Side in -1 .. 1 loop
               if Side /= 0 then
                  declare
                     A : constant Vec := Edge (K, Float (Side), 0.0);
                     B : constant Vec := Edge (K + 1, Float (Side), 0.0);
                     C : constant Vec := Edge (K + 1, Float (Side), 7.0);
                     D : constant Vec := Edge (K, Float (Side), 7.0);
                  begin
                     New_Path (Cr);
                     Move_To (Cr, G (A.X), G (A.Y));
                     Line_To (Cr, G (B.X), G (B.Y));
                     Line_To (Cr, G (C.X), G (C.Y));
                     Line_To (Cr, G (D.X), G (D.Y));
                     Close_Path (Cr);
                     Color ((if (K / 2) mod 2 = 0 then Red else White));
                     Fill (Cr);
                  end;
               end if;
            end loop;
         end if;
      end loop;
   end Kerbs;

   procedure Start_Line is
      S : constant Sample := Get (0);
      Sq : constant Float := 5.0;
      N : constant Integer := Integer (S.Width / Sq);
   begin
      Save (Cr);
      Translate (Cr, G (S.P.X), G (S.P.Y));
      Rotate (Cr, G (Angle_Of (S.T)));
      for Row in 0 .. 1 loop
         for I in 0 .. N - 1 loop
            New_Path (Cr);
            Rectangle (Cr, G (Float (Row) * Sq - Sq), G (-S.Width * 0.5 + Float (I) * Sq), G (Sq), G (Sq));
            if (Row + I) mod 2 = 0 then
               Color (0.05, 0.05, 0.05);
            else
               Color (0.97, 0.97, 0.97);
            end if;
            Fill (Cr);
         end loop;
      end loop;
      Restore (Cr);
      --  The boxes of the grid
      for K in 1 .. 6 loop
         declare
            P : Vec;
            H : Float;
         begin
            Tracks.Grid_Slot (K, P, H);
            Save (Cr);
            Translate (Cr, G (P.X), G (P.Y));
            Rotate (Cr, G (H));
            Set_Line_Width (Cr, 1.6);
            Color (1.0, 1.0, 1.0, 0.65);
            New_Path (Cr);
            Move_To (Cr, -6.0, -9.0);
            Line_To (Cr, 16.0, -9.0);
            Line_To (Cr, 16.0, 9.0);
            Line_To (Cr, -6.0, 9.0);
            Stroke (Cr);
            Restore (Cr);
         end;
      end loop;
   end Start_Line;

   --  The rails of the toy train, where it shuttles across the road
   procedure Paint_Rails is
   begin
      for M in 1 .. Tracks.Mover_Count loop
         declare
            Mv : constant Mover := Tracks.Get_Mover (M);
         begin
            if Mv.Kind = Circle_Train then
               --  a ring of track round the tree
               for K in 0 .. 89 loop
                  declare
                     A : constant Float := Float (K) * 2.0 * Pi / 90.0;
                     P : constant Vec := Mv.A + Dir (A) * Mv.B.X;
                     Q : constant Vec := Dir (A) * 12.0;
                  begin
                     Set_Line_Width (Cr, 4.0);
                     Color (0.40, 0.28, 0.18);
                     Move_To (Cr, G (P.X - Q.X), G (P.Y - Q.Y));
                     Line_To (Cr, G (P.X + Q.X), G (P.Y + Q.Y));
                     Stroke (Cr);
                  end;
               end loop;
               Set_Line_Width (Cr, 2.2);
               Color (0.72, 0.74, 0.78);
               for Side in -1 .. 1 loop
                  if Side /= 0 then
                     New_Path (Cr);
                     Arc (Cr, G (Mv.A.X), G (Mv.A.Y), G (Mv.B.X + 8.0 * Float (Side)), 0.0, 2.0 * Pi);
                     Stroke (Cr);
                  end if;
               end loop;
            elsif Mv.Kind = Train then
               declare
                  U : constant Vec := Normal (Mv.B - Mv.A);
                  A : constant Vec := Mv.A - U * (Train_Length * 0.6);
                  B : constant Vec := Mv.B + U * (Train_Length * 0.6);
                  L : constant Float := Distance (A, B);
                  S : Float := 0.0;
               begin
                  --  the sleepers, then the two rails, then a buffer at each end
                  while S < L loop
                     declare
                        P : constant Vec := A + U * S;
                        Q : constant Vec := Perp (U) * 13.0;
                     begin
                        Set_Line_Width (Cr, 4.0);
                        Color (0.40, 0.28, 0.18);
                        Move_To (Cr, G (P.X - Q.X), G (P.Y - Q.Y));
                        Line_To (Cr, G (P.X + Q.X), G (P.Y + Q.Y));
                        Stroke (Cr);
                     end;
                     S := S + 9.0;
                  end loop;
                  for Side in -1 .. 1 loop
                     if Side /= 0 then
                        declare
                           Q : constant Vec := Perp (U) * (8.0 * Float (Side));
                        begin
                           Set_Line_Width (Cr, 2.2);
                           Color (0.72, 0.74, 0.78);
                           Move_To (Cr, G (A.X + Q.X), G (A.Y + Q.Y));
                           Line_To (Cr, G (B.X + Q.X), G (B.Y + Q.Y));
                           Stroke (Cr);
                        end;
                     end if;
                  end loop;
                  for E in 0 .. 1 loop
                     declare
                        P : constant Vec := (if E = 0 then A else B);
                     begin
                        Save (Cr);
                        Translate (Cr, G (P.X), G (P.Y));
                        Rotate (Cr, G (Angle_Of (U)));
                        New_Path (Cr);
                        Rectangle (Cr, -3.0, -14.0, 6.0, 28.0);
                        Color (0.8, 0.15, 0.1);
                        Fill (Cr);
                        Restore (Cr);
                     end;
                  end loop;
               end;
            end if;
         end;
      end loop;
   end Paint_Rails;

   procedure Paint_Road is
   begin
      case Tracks.Theme is
         when Workbench =>
            --  A toy track laid on the bench: it stands a little proud
            Road_Path (1.0, (2.5, 3.5));
            Color (0.0, 0.0, 0.0, 0.35);
            Set_Fill_Rule (Cr, Cairo_Fill_Rule_Winding);
            Fill (Cr);
            Road_Path;
            Fill_Tile (Tarmac);
            Kerbs ((0.85, 0.12, 0.10), (0.95, 0.95, 0.95));
            Set_Line_Width (Cr, 2.0);
            Color (0.95, 0.95, 0.92, 0.9);
            Edge_Path (-1.0, 9.5);
            Stroke (Cr);
            Edge_Path (1.0, 9.5);
            Stroke (Cr);
            Set_Dash (Cr, (12.0, 14.0), 0.0);
            Set_Line_Width (Cr, 1.6);
            Color (0.95, 0.85, 0.3, 0.55);
            New_Path (Cr);
            for K in 0 .. Tracks.Count - 1 loop
               Line_To (Cr, G (Get (K).P.X), G (Get (K).P.Y));
            end loop;
            Close_Path (Cr);
            Stroke (Cr);
            Set_Dash (Cr, Cairo.No_Dashes, 0.0);
         when Garden =>
            --  A path trodden through the grass
            Road_Path (5.0);
            Color (0.28, 0.24, 0.12, 0.45);
            Fill (Cr);
            Road_Path;
            Fill_Tile (Dirt);
            Set_Line_Width (Cr, 4.0);
            Color (0.35, 0.26, 0.15, 0.5);
            Edge_Path (-1.0, 1.0);
            Stroke (Cr);
            Edge_Path (1.0, 1.0);
            Stroke (Cr);
            --  tufts of grass over the edges
            for K in 0 .. Tracks.Count - 1 loop
               if K mod 2 = 0 then
                  declare
                     Side : constant Float := (if Random (Rand) < 0.5 then -1.0 else 1.0);
                     E : constant Vec := Edge (K, Side, Random (Rand) * 4.0 - 1.0);
                  begin
                     Set_Line_Width (Cr, 1.3);
                     Color (0.22 + Random (Rand) * 0.1, 0.48 + Random (Rand) * 0.1, 0.16);
                     for B in 1 .. 4 loop
                        Move_To (Cr, G (E.X), G (E.Y));
                        Line_To (Cr, G (E.X + Spread (Rand) * 5.0), G (E.Y + Spread (Rand) * 5.0));
                     end loop;
                     Stroke (Cr);
                  end;
               end if;
            end loop;
            --  pebbles along them
            for K in 0 .. Tracks.Count - 1 loop
               if Random (Rand) < 0.35 then
                  declare
                     Side : constant Float := (if Random (Rand) < 0.5 then -1.0 else 1.0);
                     E : constant Vec := Edge (K, Side, 2.0 + Random (Rand) * 5.0);
                  begin
                     New_Path (Cr);
                     Disc (E.X, E.Y, 1.2 + Random (Rand) * 1.8);
                     Color (0.62 + Random (Rand) * 0.2, 0.6, 0.55);
                     Fill (Cr);
                  end;
               end if;
            end loop;
         when Ice =>
            --  Swept ice, with the snow pushed up along it
            Road_Path (9.0);
            Color (0.80, 0.86, 0.94);
            Fill (Cr);
            Road_Path;
            Fill_Tile (Ice_Sheet);
            Set_Line_Width (Cr, 7.0);
            Color (1.0, 1.0, 1.0, 0.75);
            Edge_Path (-1.0, -2.0);
            Stroke (Cr);
            Edge_Path (1.0, -2.0);
            Stroke (Cr);
            Set_Line_Width (Cr, 3.0);
            Color (0.70, 0.80, 0.92, 0.6);
            Edge_Path (-1.0, 2.5);
            Stroke (Cr);
            Edge_Path (1.0, 2.5);
            Stroke (Cr);
            Kerbs ((0.25, 0.45, 0.85), (0.96, 0.97, 1.0));
            --  cracks in the ice
            Set_Line_Width (Cr, 0.8);
            Color (1.0, 1.0, 1.0, 0.55);
            for K in 0 .. Tracks.Count - 1 loop
               if Random (Rand) < 0.06 then
                  declare
                     P : Vec := Edge (K, Spread (Rand), Get (K).Width * 0.5);
                     A : Float := Random (Rand) * 2.0 * Pi;
                  begin
                     P := Get (K).P + Perp (Get (K).T) * (Spread (Rand) * Get (K).Width * 0.35);
                     Move_To (Cr, G (P.X), G (P.Y));
                     for Seg in 1 .. 5 loop
                        A := A + Spread (Rand) * 0.8;
                        P := P + Dir (A) * (4.0 + Random (Rand) * 7.0);
                        Line_To (Cr, G (P.X), G (P.Y));
                     end loop;
                     Stroke (Cr);
                  end;
               end if;
            end loop;
         when Pool =>
            --  The cloth worn lighter where the karts go, lined in chalk
            Road_Path;
            Color (1.0, 1.0, 0.9, 0.12);
            Fill (Cr);
            Set_Line_Width (Cr, 2.0);
            Set_Dash (Cr, (8.0, 6.0), 0.0);
            Color (0.95, 0.97, 1.0, 0.75);
            Edge_Path (-1.0, 2.0);
            Stroke (Cr);
            Edge_Path (1.0, 2.0);
            Stroke (Cr);
            Set_Dash (Cr, Cairo.No_Dashes, 0.0);
         when Desk =>
            --  A road of squared paper, cut from an exercise book
            Road_Path (1.5, (2.0, 3.0));
            Color (0.0, 0.0, 0.0, 0.2);
            Fill (Cr);
            Road_Path;
            Color (0.98, 0.98, 0.96);
            Fill_Preserve (Cr);
            Save (Cr);
            Clip (Cr);
            Set_Line_Width (Cr, 0.7);
            Color (0.45, 0.62, 0.90, 0.55);
            declare
               X : Float := 0.0;
            begin
               while X < Tracks.Width loop
                  Move_To (Cr, G (X), 0.0);
                  Line_To (Cr, G (X), G (Tracks.Height));
                  X := X + 12.0;
               end loop;
               X := 0.0;
               while X < Tracks.Height loop
                  Move_To (Cr, 0.0, G (X));
                  Line_To (Cr, G (Tracks.Width), G (X));
                  X := X + 12.0;
               end loop;
               Stroke (Cr);
            end;
            Set_Line_Width (Cr, 1.6);
            Color (0.90, 0.25, 0.25, 0.7);
            Edge_Path (-1.0, 12.0);
            Stroke (Cr);
            Restore (Cr);
         when Beach =>
            --  Wet, packed sand, ridged by the tide
            Road_Path (4.0);
            Color (0.72, 0.60, 0.40, 0.5);
            Fill (Cr);
            Road_Path;
            Fill_Tile (Sand_Grains);
            Road_Path;
            Color (0.45, 0.35, 0.20, 0.30);
            Fill (Cr);
         when Fish_Tank =>
            --  A channel of clean sand through the gravel
            Road_Path (6.0);
            Color (0.25, 0.35, 0.40, 0.4);
            Fill (Cr);
            Road_Path;
            Fill_Tile (Sand_Grains);
            Road_Path;
            Color (0.30, 0.55, 0.65, 0.25);
            Fill (Cr);
         when Attic =>
            --  Masking tape on the floorboards marks out the course
            Road_Path;
            Color (0.75, 0.65, 0.50, 0.18);
            Fill (Cr);
            Set_Line_Width (Cr, 4.0);
            Color (0.92, 0.88, 0.70, 0.95);
            Edge_Path (-1.0, 3.0);
            Stroke (Cr);
            Edge_Path (1.0, 3.0);
            Stroke (Cr);
         when Party =>
            --  A ribbon of a road, with white edges and dots
            Road_Path (2.0, (2.0, 3.0));
            Color (0.0, 0.0, 0.0, 0.2);
            Fill (Cr);
            Road_Path;
            Color (0.55, 0.75, 0.95);
            Fill (Cr);
            Set_Line_Width (Cr, 3.0);
            Color (1.0, 1.0, 1.0);
            Edge_Path (-1.0, 3.0);
            Stroke (Cr);
            Edge_Path (1.0, 3.0);
            Stroke (Cr);
            for K in 0 .. Tracks.Count - 1 loop
               if K mod 4 = 0 then
                  declare
                     E : constant Vec := Edge (K, (if K mod 8 = 0 then 0.5 else -0.5), Get (K).Width * 0.25);
                  begin
                     New_Path (Cr);
                     Disc (E.X, E.Y, 3.0);
                     Color (1.0, 1.0, 1.0, 0.6);
                     Fill (Cr);
                  end;
               end if;
            end loop;
         when Garage =>
            --  Painted lanes on the concrete
            Road_Path;
            Color (0.30, 0.30, 0.32, 0.55);
            Fill (Cr);
            Set_Line_Width (Cr, 4.0);
            Set_Dash (Cr, (20.0, 10.0), 0.0);
            Color (0.95, 0.80, 0.10, 0.9);
            Edge_Path (-1.0, 3.0);
            Stroke (Cr);
            Edge_Path (1.0, 3.0);
            Stroke (Cr);
            Set_Dash (Cr, Cairo.No_Dashes, 0.0);
         when Xmas =>
            --  A cream rug runner, edged with tinsel
            Road_Path (2.0, (2.0, 3.0));
            Color (0.0, 0.0, 0.0, 0.25);
            Fill (Cr);
            Road_Path;
            Color (0.94, 0.90, 0.80);
            Fill (Cr);
            for Side in -1 .. 1 loop
               if Side /= 0 then
                  Set_Line_Width (Cr, 5.0);
                  Color (0.85, 0.72, 0.25, 0.9);
                  Edge_Path (Float (Side), 2.0);
                  Stroke (Cr);
                  Set_Line_Width (Cr, 1.5);
                  Set_Dash (Cr, (2.0, 3.0), 0.0);
                  Color (1.0, 0.95, 0.6);
                  Edge_Path (Float (Side), 2.0);
                  Stroke (Cr);
                  Set_Dash (Cr, Cairo.No_Dashes, 0.0);
               end if;
            end loop;
            Paint_Rails;
         when Arctic =>
            --  A trail of packed snow, grooved by skis, staked with orange poles
            Road_Path (5.0);
            Color (0.70, 0.78, 0.90, 0.6);
            Fill (Cr);
            Road_Path;
            Color (0.90, 0.93, 0.98);
            Fill (Cr);
            Set_Line_Width (Cr, 2.0);
            Color (0.70, 0.78, 0.90, 0.7);
            for Lane in -2 .. 2 loop
               if Lane /= 0 then
                  Edge_Path (1.0, Get (0).Width * 0.5 + Float (Lane) * 12.0);
                  Stroke (Cr);
               end if;
            end loop;
            for K in 0 .. Tracks.Count - 1 loop
               if K mod 14 = 0 then
                  for Side in -1 .. 1 loop
                     if Side /= 0 then
                        declare
                           E : constant Vec := Edge (K, Float (Side), -6.0);
                        begin
                           New_Path (Cr);
                           Disc (E.X + 2.0, E.Y + 3.0, 3.0);
                           Color (0.0, 0.0, 0.0, 0.2);
                           Fill (Cr);
                           New_Path (Cr);
                           Disc (E.X, E.Y, 3.0);
                           Color (1.0, 0.45, 0.05);
                           Fill (Cr);
                        end;
                     end if;
                  end loop;
               end if;
            end loop;
         when Chess =>
            --  A strip of green baize across the board, edged in gold
            Road_Path (2.0, (2.0, 3.0));
            Color (0.0, 0.0, 0.0, 0.3);
            Fill (Cr);
            Road_Path;
            Fill_Tile (Felt);
            Set_Line_Width (Cr, 3.0);
            Color (0.90, 0.75, 0.30);
            Edge_Path (-1.0, 2.0);
            Stroke (Cr);
            Edge_Path (1.0, 2.0);
            Stroke (Cr);
         when Alien =>
            --  Smooth dark rock, its edges glowing green
            Road_Path (3.0);
            Color (0.30, 1.0, 0.50, 0.25);
            Fill (Cr);
            Road_Path;
            Color (0.14, 0.10, 0.18);
            Fill (Cr);
            Set_Line_Width (Cr, 2.5);
            Color (0.40, 1.0, 0.55, 0.85);
            Edge_Path (-1.0, 3.0);
            Stroke (Cr);
            Edge_Path (1.0, 3.0);
            Stroke (Cr);
         when Halloween =>
            --  A ribbon of purple in the night air, edged in orange
            Road_Path;
            Color (0.55, 0.30, 0.75, 0.22);
            Fill (Cr);
            Set_Line_Width (Cr, 3.0);
            Set_Dash (Cr, (14.0, 10.0), 0.0);
            Color (1.0, 0.55, 0.10, 0.9);
            Edge_Path (-1.0, 1.5);
            Stroke (Cr);
            Edge_Path (1.0, 1.5);
            Stroke (Cr);
            Set_Dash (Cr, Cairo.No_Dashes, 0.0);
         when Easter =>
            --  A pastel path, with dots of every colour along it
            Road_Path (3.0, (2.0, 3.0));
            Color (0.0, 0.0, 0.0, 0.15);
            Fill (Cr);
            Road_Path;
            Color (1.0, 0.95, 0.75);
            Fill (Cr);
            Set_Line_Width (Cr, 4.0);
            Color (0.98, 0.70, 0.80);
            Edge_Path (-1.0, 2.0);
            Stroke (Cr);
            Color (0.70, 0.80, 1.0);
            Edge_Path (1.0, 2.0);
            Stroke (Cr);
            for K in 0 .. Tracks.Count - 1 loop
               if K mod 5 = 0 then
                  declare
                     E : constant Vec := Edge (K, Spread (Rand), Get (K).Width * 0.5);
                  begin
                     New_Path (Cr);
                     Disc (E.X, E.Y, 2.2);
                     Color (Mix (Toy_Color (K), (1.0, 1.0, 1.0), 0.35), 0.8);
                     Fill (Cr);
                  end;
               end if;
            end loop;
         when Moon =>
            --  A graded track across the dust, its edges marked with lights
            Road_Path;
            Color (0.42, 0.42, 0.45, 0.55);
            Fill (Cr);
            for K in 0 .. Tracks.Count - 1 loop
               if K mod 6 = 0 then
                  for Side in -1 .. 1 loop
                     if Side /= 0 then
                        declare
                           E : constant Vec := Edge (K, Float (Side), 2.0);
                        begin
                           New_Path (Cr);
                           Disc (E.X, E.Y, 2.5);
                           Color ((if Side < 0 then (1.0, 0.3, 0.2) else (0.3, 0.6, 1.0)));
                           Fill (Cr);
                        end;
                     end if;
                  end loop;
               end if;
            end loop;
         when Toy_Town =>
            --  A model road: grey, with a dashed line down the middle
            Road_Path (1.0, (1.5, 2.0));
            Color (0.0, 0.0, 0.0, 0.25);
            Fill (Cr);
            Road_Path;
            Fill_Tile (Tarmac);
            Set_Line_Width (Cr, 1.8);
            Color (0.95, 0.95, 0.92, 0.85);
            Edge_Path (-1.0, 5.0);
            Stroke (Cr);
            Edge_Path (1.0, 5.0);
            Stroke (Cr);
            Set_Dash (Cr, (10.0, 10.0), 0.0);
            New_Path (Cr);
            for K in 0 .. Tracks.Count - 1 loop
               Line_To (Cr, G (Get (K).P.X), G (Get (K).P.Y));
            end loop;
            Close_Path (Cr);
            Stroke (Cr);
            Set_Dash (Cr, Cairo.No_Dashes, 0.0);
            Paint_Rails;
         when Kitchen =>
            --  A circuit laid on the floor tiles, kerbs on every bend
            Road_Path (1.0, (2.0, 3.0));
            Color (0.0, 0.0, 0.0, 0.3);
            Fill (Cr);
            Road_Path;
            Fill_Tile (Tarmac);
            Kerbs ((0.85, 0.12, 0.10), (0.95, 0.95, 0.95));
            Set_Line_Width (Cr, 2.0);
            Color (0.95, 0.95, 0.92, 0.9);
            Edge_Path (-1.0, 9.5);
            Stroke (Cr);
            Edge_Path (1.0, 9.5);
            Stroke (Cr);
         when Mud =>
            --  Packed earth, ridged by the wheels, with churned edges
            Road_Path (6.0);
            Color (0.22, 0.15, 0.08, 0.5);
            Fill (Cr);
            Road_Path;
            Fill_Tile (Dirt);
            Set_Line_Width (Cr, 1.4);
            for Line in -2 .. 2 loop
               Color (0.35, 0.25, 0.14, 0.35);
               Edge_Path (1.0, Get (0).Width * 0.5 + Float (Line) * 9.0);
               Stroke (Cr);
            end loop;
            Set_Line_Width (Cr, 5.0);
            Color (0.30, 0.21, 0.12, 0.6);
            Edge_Path (-1.0, 0.0);
            Stroke (Cr);
            Edge_Path (1.0, 0.0);
            Stroke (Cr);
         when Bath =>
            --  A lane through the bathwater, roped off with floats
            Road_Path;
            Color (1.0, 1.0, 1.0, 0.13);
            Fill (Cr);
            for Side in -1 .. 1 loop
               if Side /= 0 then
                  for K in 0 .. Tracks.Count - 1 loop
                     if K mod 3 = 0 then
                        declare
                           E : constant Vec := Edge (K, Float (Side), -2.0);
                        begin
                           New_Path (Cr);
                           Disc (E.X + 1.5, E.Y + 2.0, 4.2);
                           Color (0.0, 0.2, 0.3, 0.25);
                           Fill (Cr);
                           New_Path (Cr);
                           Disc (E.X, E.Y, 4.0);
                           if (K / 3) mod 2 = 0 then
                              Radial (E.X, E.Y, 4.0, (1.0, 0.45, 0.4), (0.75, 0.08, 0.05));
                           else
                              Radial (E.X, E.Y, 4.0, (1.0, 1.0, 1.0), (0.75, 0.78, 0.82));
                           end if;
                           Fill (Cr);
                        end;
                     end if;
                  end loop;
               end if;
            end loop;
         when Bedroom | Sky =>
            --  A ribbon in the air, with arrows along it
            if Tracks.Walls then
               --  the clear way through the cloud, its walls shaded
               Road_Path (14.0);
               Color (0.70, 0.76, 0.88, 0.8);
               Fill (Cr);
               Road_Path;
               Fill_Tile (Sky_Blue);
            end if;
            Road_Path;
            Color (1.0, 1.0, 1.0, (if Tracks.Theme = Sky then 0.16 else 0.12));
            Fill (Cr);
            Set_Line_Width (Cr, 3.0);
            Set_Dash (Cr, (16.0, 12.0), 0.0);
            Color (1.0, 0.85, 0.2, 0.85);
            Edge_Path (-1.0, 1.5);
            Stroke (Cr);
            Edge_Path (1.0, 1.5);
            Stroke (Cr);
            Set_Dash (Cr, Cairo.No_Dashes, 0.0);
            for K in 0 .. Tracks.Count - 1 loop
               if K mod 16 = 8 then
                  declare
                     S : constant Sample := Get (K);
                  begin
                     Save (Cr);
                     Translate (Cr, G (S.P.X), G (S.P.Y));
                     Rotate (Cr, G (Angle_Of (S.T)));
                     New_Path (Cr);
                     Move_To (Cr, -6.0, -14.0);
                     Line_To (Cr, 6.0, 0.0);
                     Line_To (Cr, -6.0, 14.0);
                     Set_Line_Width (Cr, 4.0);
                     Color (1.0, 1.0, 1.0, 0.35);
                     Stroke (Cr);
                     Restore (Cr);
                  end;
               end if;
            end loop;
      end case;
      Start_Line;
   end Paint_Road;

   ---------------------------------------------------------------------------
   --  The ground
   ---------------------------------------------------------------------------

   function Ground_Color return RGB is
     (case Tracks.Theme is
         when Workbench => (0.12, 0.11, 0.13),
         when Garden => (0.12, 0.22, 0.10),
         when Ice => (0.72, 0.78, 0.86),
         when Bath => (0.88, 0.90, 0.92),
         when Bedroom => (0.30, 0.20, 0.14),
         when Sky => (0.40, 0.60, 0.86),
         when Kitchen => (0.92, 0.92, 0.90),
         when Mud => (0.35, 0.25, 0.15),
         when Pool => (0.30, 0.18, 0.10),
         when Desk => (0.55, 0.42, 0.28),
         when Beach => (0.25, 0.55, 0.70),
         when Toy_Town => (0.20, 0.35, 0.15),
         when Fish_Tank => (0.10, 0.25, 0.32),
         when Attic => (0.05, 0.04, 0.04),
         when Party => (0.95, 0.85, 0.88),
         when Garage => (0.35, 0.35, 0.34),
         when Xmas => (0.30, 0.06, 0.07),
         when Moon => (0.02, 0.02, 0.05),
         when Halloween => (0.06, 0.04, 0.08),
         when Easter => (0.30, 0.50, 0.20),
         when Chess => (0.30, 0.18, 0.10),
         when Alien => (0.10, 0.04, 0.14),
         when Arctic => (0.78, 0.84, 0.92));

   function Somewhere (X0, Y0, X1, Y1 : Float) return Vec is
      X : constant Float := X0 + Random (Rand) * (X1 - X0);
      Y : constant Float := Y0 + Random (Rand) * (Y1 - Y0);
   begin
      return (X, Y);
   end Somewhere;

   procedure Paint_Ground is
      W : constant Float := Tracks.Width;
      H : constant Float := Tracks.Height;
   begin
      case Tracks.Theme is
         when Bath =>
            New_Path (Cr);
            Rectangle (Cr, 0.0, 0.0, G (W), G (H));
            Fill_Tile (Bath_Water);
         when Bedroom =>
            New_Path (Cr);
            Rectangle (Cr, 0.0, 0.0, G (W), G (H));
            Fill_Tile (Carpet);
            --  a round rug in the middle of the room
            Save (Cr);
            Translate (Cr, G (W * 0.5), G (H * 0.5));
            for K in 0 .. 5 loop
               New_Path (Cr);
               Oval (W * 0.32 - Float (K) * 40.0, H * 0.32 - Float (K) * 30.0);
               if K mod 2 = 0 then
                  Color (0.80, 0.35, 0.25, 0.9);
               else
                  Color (0.95, 0.80, 0.45, 0.9);
               end if;
               Fill (Cr);
            end loop;
            Restore (Cr);
         when Sky =>
            New_Path (Cr);
            Rectangle (Cr, 0.0, 0.0, G (W), G (H));
            Fill_Tile (Sky_Blue);
            if Tracks.Walls then
               --  a bank of cloud everywhere: the course is a canyon through it
               declare
                  Y : Float := 0.0;
               begin
                  while Y < H + 60.0 loop
                     declare
                        X : Float := 0.0;
                     begin
                        while X < W + 60.0 loop
                           declare
                              JX : constant Float := X + Spread (Rand) * 30.0;
                              JY : constant Float := Y + Spread (Rand) * 30.0;
                              R : constant Float := 55.0 + Random (Rand) * 35.0;
                           begin
                              New_Path (Cr);
                              Disc (JX, JY, R);
                              Radial (JX, JY, R, (1.0, 1.0, 1.0), (0.80, 0.85, 0.94), 1.0, 0.95);
                              Fill (Cr);
                           end;
                           X := X + 70.0;
                        end loop;
                     end;
                     Y := Y + 70.0;
                  end loop;
               end;
            end if;
         when Kitchen =>
            New_Path (Cr);
            Rectangle (Cr, 0.0, 0.0, G (W), G (H));
            Fill_Tile (Kitchen_Tiles);
         when Pool =>
            New_Path (Cr);
            Rectangle (Cr, 0.0, 0.0, G (W), G (H));
            Fill_Tile (Felt);
            New_Path (Cr);
            Disc (W * 0.72, H * 0.5, 4.0);
            Color (1.0, 1.0, 1.0, 0.6);
            Fill (Cr);
         when Desk =>
            New_Path (Cr);
            Rectangle (Cr, 0.0, 0.0, G (W), G (H));
            Fill_Tile (Birch);
            --  doodles and scratches in the desk top
            Set_Line_Width (Cr, 1.5);
            for K in 1 .. 12 loop
               declare
                  P : constant Vec := Somewhere (0.0, 0.0, W, H);
               begin
                  New_Path (Cr);
                  Arc (Cr, G (P.X), G (P.Y), G (10.0 + Random (Rand) * 20.0), 0.0, G (Pi * (1.0 + Random (Rand))));
                  Color (0.35, 0.25, 0.15, 0.25);
                  Stroke (Cr);
               end;
            end loop;
         when Beach =>
            New_Path (Cr);
            Rectangle (Cr, 0.0, 0.0, G (W), G (H));
            Fill_Tile (Sand_Grains);
            New_Path (Cr);
            Rectangle (Cr, 0.0, 0.0, G (W), G (H));
            Color (1.0, 0.95, 0.80, 0.15);
            Fill (Cr);
         when Toy_Town =>
            New_Path (Cr);
            Rectangle (Cr, 0.0, 0.0, G (W), G (H));
            Fill_Tile (Model_Grass);
         when Fish_Tank =>
            New_Path (Cr);
            Rectangle (Cr, 0.0, 0.0, G (W), G (H));
            Fill_Tile (Gravel);
         when Attic =>
            New_Path (Cr);
            Rectangle (Cr, 0.0, 0.0, G (W), G (H));
            Fill_Tile (Old_Boards);
         when Party =>
            New_Path (Cr);
            Rectangle (Cr, 0.0, 0.0, G (W), G (H));
            Fill_Tile (Gingham);
         when Garage =>
            New_Path (Cr);
            Rectangle (Cr, 0.0, 0.0, G (W), G (H));
            Fill_Tile (Concrete);
            Set_Line_Width (Cr, 1.2);
            Color (0.30, 0.30, 0.30, 0.5);
            for K in 1 .. 25 loop
               declare
                  P : Vec := Somewhere (0.0, 0.0, W, H);
                  A : Float := Random (Rand) * 2.0 * Pi;
               begin
                  New_Path (Cr);
                  Move_To (Cr, G (P.X), G (P.Y));
                  for Seg in 1 .. 6 loop
                     A := A + Spread (Rand) * 0.9;
                     P := P + Dir (A) * (10.0 + Random (Rand) * 20.0);
                     Line_To (Cr, G (P.X), G (P.Y));
                  end loop;
                  Stroke (Cr);
               end;
            end loop;
         when Xmas =>
            New_Path (Cr);
            Rectangle (Cr, 0.0, 0.0, G (W), G (H));
            Fill_Tile (Tartan);
         when Moon =>
            New_Path (Cr);
            Rectangle (Cr, 0.0, 0.0, G (W), G (H));
            Fill_Tile (Regolith);
         when Chess =>
            New_Path (Cr);
            Rectangle (Cr, 0.0, 0.0, G (W), G (H));
            Fill_Tile (Chessboard);
         when Arctic =>
            New_Path (Cr);
            Rectangle (Cr, 0.0, 0.0, G (W), G (H));
            Fill_Tile (Snow);
            for K in 1 .. 50 loop
               declare
                  C : constant Vec := Somewhere (0.0, 0.0, W, H);
               begin
                  Save (Cr);
                  Translate (Cr, G (C.X), G (C.Y));
                  Rotate (Cr, G (0.4 + Spread (Rand) * 0.2));   --  the drifts all lie with the wind
                  New_Path (Cr);
                  Oval (70.0 + Random (Rand) * 90.0, 12.0 + Random (Rand) * 12.0);
                  Color (0.68, 0.76, 0.90, 0.28);
                  Fill (Cr);
                  Restore (Cr);
               end;
            end loop;
         when Alien =>
            New_Path (Cr);
            Rectangle (Cr, 0.0, 0.0, G (W), G (H));
            Fill_Tile (Alien_Soil);
         when Halloween =>
            --  the pumpkin patch by night
            New_Path (Cr);
            Rectangle (Cr, 0.0, 0.0, G (W), G (H));
            Fill_Tile (Grass);
            New_Path (Cr);
            Rectangle (Cr, 0.0, 0.0, G (W), G (H));
            Color (0.12, 0.06, 0.18, 0.55);
            Fill (Cr);
         when Easter =>
            --  a spring lawn, full of flowers
            New_Path (Cr);
            Rectangle (Cr, 0.0, 0.0, G (W), G (H));
            Fill_Tile (Grass);
            New_Path (Cr);
            Rectangle (Cr, 0.0, 0.0, G (W), G (H));
            Color (0.85, 1.0, 0.6, 0.12);
            Fill (Cr);
            for K in 1 .. 400 loop
               declare
                  C : constant Vec := Somewhere (0.0, 0.0, W, H);
               begin
                  New_Path (Cr);
                  Disc (C.X, C.Y, 1.5 + Random (Rand) * 2.0);
                  Color (Mix (Toy_Color (K), (1.0, 1.0, 1.0), 0.5), 0.9);
                  Fill (Cr);
               end;
            end loop;
         when Mud =>
            New_Path (Cr);
            Rectangle (Cr, 0.0, 0.0, G (W), G (H));
            Fill_Tile (Mud_Ground);
            --  old wheel ruts over the ground
            Set_Line_Width (Cr, 3.0);
            for K in 1 .. 30 loop
               declare
                  P : Vec := Somewhere (0.0, 0.0, W, H);
                  A : Float := Random (Rand) * 2.0 * Pi;
               begin
                  New_Path (Cr);
                  Move_To (Cr, G (P.X), G (P.Y));
                  for Seg in 1 .. 8 loop
                     A := A + Spread (Rand) * 0.3;
                     P := P + Dir (A) * 30.0;
                     Line_To (Cr, G (P.X), G (P.Y));
                  end loop;
                  Color (0.22, 0.15, 0.08, 0.25);
                  Stroke (Cr);
               end;
            end loop;
         when Workbench =>
            New_Path (Cr);
            Rectangle (Cr, 0.0, 0.0, G (W), G (H));
            Fill_Tile (Floor_Below);
            declare
               X0 : constant Float := Table_Left;
               Y0 : constant Float := Table_Top;
               X1 : constant Float := Table_Right;
               Y1 : constant Float := Table_Bottom;
            begin
               --  its shadow on the floor
               for K in 1 .. 6 loop
                  New_Path (Cr);
                  Rectangle (Cr, G (X0 + 20.0 - Float (K) * 3.0), G (Y0 + 30.0 - Float (K) * 3.0),
                             G (X1 - X0 + Float (K) * 6.0), G (Y1 - Y0 + Float (K) * 6.0));
                  Color (0.0, 0.0, 0.0, 0.12);
                  Fill (Cr);
               end loop;
               --  the side of the top, seen past its edge
               New_Path (Cr);
               Rectangle (Cr, G (X0), G (Y0), G (X1 - X0), G (Y1 - Y0 + 16.0));
               Color (0.36, 0.22, 0.12);
               Fill (Cr);
               New_Path (Cr);
               Rectangle (Cr, G (X0), G (Y0), G (X1 - X0), G (Y1 - Y0));
               Fill_Tile (Wood);
               --  the planks
               Set_Line_Width (Cr, 1.5);
               Color (0.30, 0.18, 0.09, 0.7);
               declare
                  Y : Float := Y0 + 150.0;
                  Row : Natural := 0;
               begin
                  while Y < Y1 - 20.0 loop
                     Move_To (Cr, G (X0), G (Y));
                     Line_To (Cr, G (X1), G (Y));
                     Stroke (Cr);
                     --  a joint in the plank, and its nails
                     declare
                        JX : constant Float := X0 + (0.2 + 0.6 * Hash (Row, 1, 3)) * (X1 - X0);
                     begin
                        Move_To (Cr, G (JX), G (Y - 150.0));
                        Line_To (Cr, G (JX), G (Y));
                        Stroke (Cr);
                        for NY in 0 .. 1 loop
                           New_Path (Cr);
                           Disc (JX - 8.0, Y - 150.0 + 30.0 + Float (NY) * 90.0, 2.5);
                           Disc (JX + 8.0, Y - 150.0 + 30.0 + Float (NY) * 90.0, 2.5);
                           Color (0.25, 0.25, 0.28);
                           Fill (Cr);
                        end loop;
                        Color (0.30, 0.18, 0.09, 0.7);
                     end;
                     Y := Y + 150.0;
                     Row := Row + 1;
                  end loop;
               end;
               --  the worn edge of the top
               Set_Line_Width (Cr, 4.0);
               Color (0.95, 0.80, 0.60, 0.35);
               New_Path (Cr);
               Rectangle (Cr, G (X0 + 2.0), G (Y0 + 2.0), G (X1 - X0 - 4.0), G (Y1 - Y0 - 4.0));
               Stroke (Cr);
               --  rings left by cups
               for K in 1 .. 5 loop
                  declare
                     C : constant Vec := Somewhere (X0, Y0, X1, Y1);
                  begin
                     Set_Line_Width (Cr, 3.0);
                     Color (0.35, 0.20, 0.08, 0.18);
                     New_Path (Cr);
                     Arc (Cr, G (C.X), G (C.Y), G (40.0 + Random (Rand) * 10.0), 0.0, G (1.6 * Pi));
                     Stroke (Cr);
                  end;
               end loop;
            end;
         when Garden =>
            New_Path (Cr);
            Rectangle (Cr, 0.0, 0.0, G (W), G (H));
            Fill_Tile (Grass);
            --  darker patches and clover
            for K in 1 .. 220 loop
               declare
                  C : constant Vec := Somewhere (0.0, 0.0, W, H);
               begin
                  New_Path (Cr);
                  Disc (C.X, C.Y, 2.0 + Random (Rand) * 3.0);
                  Color (0.18, 0.40, 0.12, 0.5);
                  Fill (Cr);
               end;
            end loop;
         when Ice =>
            New_Path (Cr);
            Rectangle (Cr, 0.0, 0.0, G (W), G (H));
            Fill_Tile (Snow);
            --  drifts
            for K in 1 .. 40 loop
               declare
                  C : constant Vec := Somewhere (0.0, 0.0, W, H);
               begin
                  Save (Cr);
                  Translate (Cr, G (C.X), G (C.Y));
                  Rotate (Cr, G (Random (Rand) * Pi));
                  New_Path (Cr);
                  Oval (60.0 + Random (Rand) * 80.0, 10.0 + Random (Rand) * 12.0);
                  Color (0.70, 0.78, 0.90, 0.25);
                  Fill (Cr);
                  Restore (Cr);
               end;
            end loop;
      end case;
   end Paint_Ground;

   procedure Paint_Border is
      --  A hedge round the garden, a bank of snow round the pond
      W : constant Float := Tracks.Width;
      H : constant Float := Tracks.Height;
      procedure Bump_Along (X0, Y0, X1, Y1 : Float) is
         L : constant Float := Distance ((X0, Y0), (X1, Y1));
         N : constant Natural := Natural (L / 14.0);
      begin
         for K in 0 .. N loop
            declare
               F : constant Float := Float (K) / Float (Natural'Max (1, N));
               P : constant Vec := ((X0 + (X1 - X0) * F), (Y0 + (Y1 - Y0) * F));
               R : constant Float := 22.0 + Random (Rand) * 12.0;
            begin
               New_Path (Cr);
               Disc (P.X + 6.0, P.Y + 8.0, R);
               Color (0.0, 0.0, 0.0, 0.18);
               Fill (Cr);
               New_Path (Cr);
               Disc (P.X, P.Y, R);
               if Tracks.Theme = Alien then
                  Radial (P.X, P.Y, R, (0.50, 0.30, 0.60), (0.15, 0.06, 0.20));
               elsif Tracks.Theme in Garden | Easter then
                  Radial (P.X, P.Y, R, (0.25, 0.50, 0.18), (0.08, 0.25, 0.08));
               elsif Tracks.Theme = Sky then
                  Radial (P.X, P.Y, R, (1.0, 1.0, 1.0), (0.86, 0.90, 0.97));
               else
                  Radial (P.X, P.Y, R, (1.0, 1.0, 1.0), (0.78, 0.84, 0.94));
               end if;
               Fill (Cr);
            end;
         end loop;
      end Bump_Along;
   begin
      if Tracks.Has_Table then
         return;
      elsif Tracks.Theme = Mud then
         --  a wooden fence round the yard
         New_Path (Cr);
         Rectangle (Cr, 8.0, 8.0, G (W - 16.0), G (H - 16.0));
         Set_Line_Width (Cr, 16.0);
         Color (0.55, 0.40, 0.24);
         Stroke (Cr);
         declare
            X : Float := 0.0;
         begin
            while X < W loop
               New_Path (Cr);
               Disc (X, 8.0, 7.0);
               Disc (X, H - 8.0, 7.0);
               Color (0.38, 0.26, 0.14);
               Fill (Cr);
               X := X + 60.0;
            end loop;
            X := 0.0;
            while X < H loop
               New_Path (Cr);
               Disc (8.0, X, 7.0);
               Disc (W - 8.0, X, 7.0);
               Color (0.38, 0.26, 0.14);
               Fill (Cr);
               X := X + 60.0;
            end loop;
         end;
         return;
      elsif Tracks.Theme = Pool then
         --  the cushions, then the wooden rail with its diamonds
         New_Path (Cr);
         Rectangle (Cr, 13.0, 13.0, G (W - 26.0), G (H - 26.0));
         Set_Line_Width (Cr, 26.0);
         Color (0.05, 0.32, 0.15);
         Stroke (Cr);
         New_Path (Cr);
         Rectangle (Cr, 4.0, 4.0, G (W - 8.0), G (H - 8.0));
         Set_Line_Width (Cr, 10.0);
         Color (0.40, 0.22, 0.10);
         Stroke (Cr);
         for K in 1 .. 7 loop
            New_Path (Cr);
            Disc (W * Float (K) / 8.0, 4.0, 2.5);
            Disc (W * Float (K) / 8.0, H - 4.0, 2.5);
            Color (0.95, 0.92, 0.80);
            Fill (Cr);
         end loop;
         for I in 1 .. Item_Count loop
            if Get_Item (I).Kind = Pocket then
               Draw_Item (Get_Item (I));
            end if;
         end loop;
         return;
      elsif Tracks.Theme in Beach | Toy_Town | Desk | Party | Xmas | Halloween then
         return;
      elsif Tracks.Theme = Chess then
         --  the board's wooden frame, letters and numbers along it
         New_Path (Cr);
         Rectangle (Cr, 14.0, 14.0, G (W - 28.0), G (H - 28.0));
         Set_Line_Width (Cr, 28.0);
         Color (0.40, 0.24, 0.12);
         Stroke (Cr);
         Select_Font_Face (Cr, "DejaVu Sans", Cairo_Font_Slant_Normal, Cairo_Font_Weight_Bold);
         Set_Font_Size (Cr, 16.0);
         Color (0.90, 0.80, 0.55);
         for K in 0 .. Natural (W / 64.0) - 1 loop
            Move_To (Cr, G (Float (K) * 64.0 + 28.0), 22.0);
            Show_Text (Cr, (1 => Character'Val (Character'Pos ('a') + K mod 26)));
         end loop;
         return;
      elsif Tracks.Theme = Fish_Tank then
         --  the glass of the tank
         for K in 0 .. 3 loop
            New_Path (Cr);
            Rectangle (Cr, G (6.0 + Float (K) * 4.0), G (6.0 + Float (K) * 4.0),
                       G (W - 12.0 - Float (K) * 8.0), G (H - 12.0 - Float (K) * 8.0));
            Set_Line_Width (Cr, 6.0);
            Color (0.75, 0.92, 0.95, 0.5 - 0.1 * Float (K));
            Stroke (Cr);
         end loop;
         return;
      elsif Tracks.Theme in Attic | Garage then
         --  the walls
         New_Path (Cr);
         Rectangle (Cr, 12.0, 12.0, G (W - 24.0), G (H - 24.0));
         Set_Line_Width (Cr, 24.0);
         if Tracks.Theme = Attic then
            Color (0.25, 0.16, 0.10);
         else
            Color (0.50, 0.50, 0.55);
         end if;
         Stroke (Cr);
         return;
      elsif Tracks.Theme = Moon then
         --  a ridge of rock round the base
         for K in 0 .. Natural ((W + H) / 15.0) loop
            declare
               F : constant Float := Float (K) * 30.0;
               P : constant Vec :=
                 (if F < W then (F, 0.0) elsif F < W + H then (W, F - W)
                  elsif F < 2.0 * W + H then (2.0 * W + H - F, H) else (0.0, 2.0 * (W + H) - F));
               R : constant Float := 18.0 + Random (Rand) * 14.0;
            begin
               New_Path (Cr);
               Disc (P.X, P.Y, R);
               Radial (P.X, P.Y, R, (0.65, 0.65, 0.68), (0.30, 0.30, 0.32));
               Fill (Cr);
            end;
         end loop;
         return;
      elsif Tracks.Theme in Bath | Bedroom | Kitchen then
         --  the side of the tub, or the skirting board round the room
         for K in 0 .. 5 loop
            New_Path (Cr);
            Rectangle (Cr, G (Float (K) * 5.0), G (Float (K) * 5.0),
                       G (W - Float (K) * 10.0), G (H - Float (K) * 10.0));
            Set_Line_Width (Cr, 10.0);
            if Tracks.Theme in Bath | Kitchen then
               Color (0.97 - 0.03 * Float (K), 0.98 - 0.03 * Float (K), 1.0 - 0.02 * Float (K));
            else
               Color (0.55 - 0.04 * Float (K), 0.36 - 0.03 * Float (K), 0.22 - 0.02 * Float (K));
            end if;
            Stroke (Cr);
         end loop;
         New_Path (Cr);
         Rectangle (Cr, 30.0, 30.0, G (W - 60.0), G (H - 60.0));
         Set_Line_Width (Cr, 6.0);
         Color (0.0, 0.0, 0.0, 0.15);
         Stroke (Cr);
         return;
      end if;
      Bump_Along (0.0, 0.0, W, 0.0);
      Bump_Along (0.0, H, W, H);
      Bump_Along (0.0, 0.0, 0.0, H);
      Bump_Along (W, 0.0, W, H);
   end Paint_Border;

   function Touches_Road (It : Item) return Boolean is
      K : constant Natural := Tracks.Nearest (It.S.C);
      E : constant Float := (case It.S.Kind is
                                when Circle => It.S.RX,
                                when others => Float'Max (It.S.RX, It.S.RY));
   begin
      return Distance (It.S.C, Get (K).P) < E + Get (K).Width * 0.5;
   end Touches_Road;

   procedure Build is
      use Cairo.Image_Surface;
      PW : constant Gint := Gint (Tracks.Width * Scale);
      PH : constant Gint := Gint (Tracks.Height * Scale);
   begin
      Make_Tiles;
      Rand := Seed (Tracks.Current) * 977 + 5;
      if Marks /= Null_Context then
         Destroy (Marks);
         Marks := Null_Context;
      end if;
      if Picture /= Null_Surface then
         Cairo.Surface.Destroy (Picture);
      end if;
      Picture := Create (Cairo_Format_RGB24, PW, PH);
      Cr := Create (Picture);
      Cairo.Scale (Cr, Scale, Scale);
      Set_Line_Cap (Cr, Cairo_Line_Cap_Round);
      Set_Line_Join (Cr, Cairo_Line_Join_Round);

      Paint_Ground;
      for I in 1 .. Item_Count loop
         if Is_Below (Get_Item (I)) then
            Draw_Item (Get_Item (I));
         end if;
      end loop;
      if Tracks.Vehicle = Plane then
         --  the ground is far below: a haze over it
         New_Path (Cr);
         Rectangle (Cr, 0.0, 0.0, G (Tracks.Width), G (Tracks.Height));
         if Tracks.Theme = Halloween then
            Color (0.35, 0.25, 0.45, 0.25);   --  a mist over it
         else
            Color (0.85, 0.92, 1.0, (if Tracks.Theme = Sky then 0.12 else 0.22));
         end if;
         Fill (Cr);
      end if;
      for I in 1 .. Item_Count loop
         if Get_Item (I).Mat /= Solid and then not Is_Below (Get_Item (I))
           and then not Touches_Road (Get_Item (I))
         then
            Draw_Item (Get_Item (I));
         end if;
      end loop;
      Paint_Road;
      for I in 1 .. Item_Count loop
         if Get_Item (I).Mat /= Solid and then not Is_Below (Get_Item (I)) and then Touches_Road (Get_Item (I)) then
            Draw_Item (Get_Item (I));
         end if;
      end loop;
      for I in 1 .. Item_Count loop
         if Get_Item (I).Mat = Solid then
            Draw_Item (Get_Item (I));
         end if;
      end loop;
      Paint_Border;
      if Tracks.Theme = Fish_Tank then
         --  under water: a blue-green cast, and the light rippling over it all
         New_Path (Cr);
         Rectangle (Cr, 0.0, 0.0, G (Tracks.Width), G (Tracks.Height));
         Color (0.15, 0.45, 0.55, 0.22);
         Fill (Cr);
         Set_Line_Width (Cr, 2.5);
         for K in 1 .. 160 loop
            declare
               P : Vec := Somewhere (0.0, 0.0, Tracks.Width, Tracks.Height);
               A : Float := Random (Rand) * 2.0 * Pi;
            begin
               New_Path (Cr);
               Move_To (Cr, G (P.X), G (P.Y));
               for Seg in 1 .. 4 loop
                  A := A + Spread (Rand) * 1.2;
                  P := P + Dir (A) * (14.0 + Random (Rand) * 16.0);
                  Line_To (Cr, G (P.X), G (P.Y));
               end loop;
               Color (0.85, 1.0, 1.0, 0.14);
               Stroke (Cr);
            end;
         end loop;
      end if;
      Destroy (Cr);
      Cr := Null_Context;
      Cairo.Surface.Flush (Picture);

      Marks := Create (Picture);
      Cairo.Scale (Marks, Scale, Scale);
      Set_Line_Cap (Marks, Cairo_Line_Cap_Round);
   end Build;

   procedure Skid (A, B : Vec; Strength : Float; Under : Tracks.Material) is
      C : RGB;
      Alpha : Float := Clamp (Strength, 0.0, 1.0);
      W : Float := 2.4;
   begin
      if Marks = Null_Context or else Distance (A, B) > 30.0
        or else Tracks.Vehicle in Boat | Plane | Hovercraft | Submarine
      then
         return;
      end if;
      case Under is
         when Road | Boost =>
            case Tracks.Theme is
               when Workbench | Kitchen | Toy_Town | Garage | Xmas | Party | Attic =>
                  C := (0.05, 0.05, 0.06); Alpha := Alpha * 0.30;
               when Moon => C := (0.30, 0.30, 0.33); Alpha := Alpha * 0.55; W := 3.0;
               when Arctic => C := (0.62, 0.70, 0.84); Alpha := Alpha * 0.5; W := 3.0;
               when Pool => C := (0.02, 0.2, 0.08); Alpha := Alpha * 0.35;
               when Desk => C := (0.3, 0.3, 0.35); Alpha := Alpha * 0.35;
               when Beach => C := (0.45, 0.35, 0.2); Alpha := Alpha * 0.4; W := 3.0;
               when Mud => C := (0.25, 0.17, 0.09); Alpha := Alpha * 0.45; W := 2.0;
               when Garden => C := (0.32, 0.22, 0.12); Alpha := Alpha * 0.35;
               when Ice => C := (1.0, 1.0, 1.0); Alpha := Alpha * 0.40; W := 1.6;
               when others => return;
            end case;
         when Floor =>
            case Tracks.Theme is
               when Workbench => C := (0.25, 0.14, 0.06); Alpha := Alpha * 0.18;
               when Kitchen => C := (0.3, 0.25, 0.2); Alpha := Alpha * 0.15;
               when Pool => C := (0.02, 0.2, 0.08); Alpha := Alpha * 0.35;
               when Desk => C := (0.35, 0.25, 0.15); Alpha := Alpha * 0.2;
               when Beach => C := (0.55, 0.45, 0.28); Alpha := Alpha * 0.5; W := 3.4;
               when Toy_Town => C := (0.15, 0.30, 0.10); Alpha := Alpha * 0.4;
               when Moon => C := (0.35, 0.35, 0.38); Alpha := Alpha * 0.6; W := 3.0;
               when Arctic => C := (0.60, 0.68, 0.82); Alpha := Alpha * 0.55; W := 3.5;
               when Garage | Attic => C := (0.15, 0.15, 0.15); Alpha := Alpha * 0.3;
               when Mud => C := (0.18, 0.12, 0.06); Alpha := Alpha * 0.5; W := 2.4;
               when Garden => C := (0.15, 0.28, 0.08); Alpha := Alpha * 0.45; W := 3.0;
               when Ice => C := (0.62, 0.70, 0.82); Alpha := Alpha * 0.55; W := 3.2;
               when others => return;
            end case;
         when Sand =>
            C := (0.45, 0.35, 0.20); Alpha := Alpha * 0.35; W := 3.4;
         when others =>
            return;
      end case;
      Set_Source_Rgba (Marks, G (C.R), G (C.G), G (C.B), G (Alpha));
      Set_Line_Width (Marks, G (W));
      Move_To (Marks, G (A.X), G (A.Y));
      Line_To (Marks, G (B.X), G (B.Y));
      Stroke (Marks);
   end Skid;

end Art;
