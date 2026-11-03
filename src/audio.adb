--  Adamachines: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics.Elementary_Functions;
with Interfaces;
with Interfaces.C;
with Interfaces.C.Strings;
with System;

package body Audio is

   use Ada.Numerics.Elementary_Functions;
   use Interfaces;
   use type C.int;
   use type System.Address;

   Two_Pi : constant := 6.28318_53072;
   Rate   : constant := 44_100;
   Frames : constant := 441;      --  ten milliseconds a block
   Dt     : constant Float := 1.0 / Float (Rate);

   type Sample_Spec is record
      Format      : C.int;
      Sample_Rate : Unsigned_32;
      Channels    : Unsigned_8;
   end record
     with Convention => C;

   type Buffer_Attr is record
      Max_Length, T_Length, Pre_Buf, Min_Req, Frag_Size : Unsigned_32;
   end record
     with Convention => C;

   function PA_New
     (Server : C.Strings.chars_ptr; Name : C.Strings.chars_ptr; Dir : C.int;
      Dev : C.Strings.chars_ptr; Stream_Name : C.Strings.chars_ptr;
      Spec : access Sample_Spec; Map : System.Address; Attr : access Buffer_Attr;
      Error : access C.int) return System.Address
     with Import, Convention => C, External_Name => "pa_simple_new";

   function PA_Write (S : System.Address; Data : System.Address; Bytes : C.size_t;
                      Error : access C.int) return C.int
     with Import, Convention => C, External_Name => "pa_simple_write";

   procedure PA_Free (S : System.Address)
     with Import, Convention => C, External_Name => "pa_simple_free";

   type Shot is record
      E : Effect := Thud;
      Level, Pan : Float := 0.0;
   end record;
   type Shot_List is array (1 .. 32) of Shot;

   protected Shared is
      procedure Put (P : Params);
      function Get return Params;
      procedure Queue (S : Shot);
      procedure Take (L : out Shot_List; N : out Natural);
      procedure Halt;
      function Stopping return Boolean;
   private
      Current : Params;
      Q : Shot_List;
      Count : Natural := 0;
      Stop_It : Boolean := False;
   end Shared;

   protected body Shared is
      procedure Put (P : Params) is
      begin
         Current := P;
      end Put;
      function Get return Params is (Current);
      procedure Queue (S : Shot) is
      begin
         if Count < Q'Last then
            Count := Count + 1;
            Q (Count) := S;
         end if;
      end Queue;
      procedure Take (L : out Shot_List; N : out Natural) is
      begin
         L := Q;
         N := Count;
         Count := 0;
      end Take;
      procedure Halt is
      begin
         Stop_It := True;
      end Halt;
      function Stopping return Boolean is (Stop_It);
   end Shared;

   procedure Set (P : Params) is
   begin
      Shared.Put (P);
   end Set;

   procedure Play (E : Effect; Level : Float := 1.0; Pan : Float := 0.0) is
   begin
      Shared.Queue ((E, Level, Pan));
   end Play;

   --  A low pass of one pole
   type Filter is record
      Y : Float := 0.0;
   end record;

   function Low (F : in out Filter; X, Cut : Float) return Float is
      A : constant Float := 1.0 - Exp (-Two_Pi * Float'Min (Cut, 18_000.0) * Dt);
   begin
      F.Y := F.Y + A * (X - F.Y);
      return F.Y;
   end Low;

   type Seed_Type is mod 2**32;

   --  A sound playing
   type Voice is record
      On : Boolean := False;
      E : Effect := Thud;
      Age, Level, Pan : Float := 0.0;
      Ph1, Ph2 : Float := 0.0;
      F1, F2 : Filter;
   end record;
   type Voice_Array is array (1 .. 24) of Voice;

   task Mixer is
      entry Go;
   end Mixer;

   task body Mixer is
      Spec : aliased Sample_Spec := (Format => 3, Sample_Rate => Rate, Channels => 2);  --  S16LE
      Attr : aliased Buffer_Attr :=
        (Max_Length => Unsigned_32'Last, T_Length => Unsigned_32 (Frames * 4 * 3),
         Pre_Buf => Unsigned_32'Last, Min_Req => Unsigned_32'Last, Frag_Size => Unsigned_32'Last);
      Err : aliased C.int := 0;
      Stream : System.Address := System.Null_Address;
      type Sample_Array is array (0 .. 2 * Frames - 1) of Integer_16 with Convention => C;
      Buffer : aliased Sample_Array;
      Name : C.Strings.chars_ptr := C.Strings.New_String ("Adamachines");
      SName : C.Strings.chars_ptr := C.Strings.New_String ("game");
      Seed : Seed_Type := 7;
      function Noise return Float is
      begin
         Seed := Seed * 1664525 + 1013904223;
         return Float (Seed / 65536) / 32768.0 - 1.0;
      end Noise;
      Voices : Voice_Array;
      P : Params;
      Speed_S, Thr_S, Rough_S, Slip_S, Other_S, Other_L, Other_P : Float := 0.0;
      Eng1, Eng2, Whine, Oth : Float := 0.0;
      Eng_F, Wind_F, Rush_F, Scr_F, Scr_F2, Oth_F, Slip_F : Filter;
      Shots : Shot_List;
      --  The music: a sixteen step loop over four chords
      Beat_T : Float := 0.0;
      Step_N : Natural := 0;
      Bass_Ph, Arp_Ph, Lead_Ph : Float := 0.0;
      Kick_T, Hat_T, Note_T : Float := 10.0;
      Bass_F, Arp_F : Float := 110.0;
      Mus_F, Hat_F : Filter;
      Music_Out : Float := 0.0;   --  the music's sample, apart from the master level
      N_Shots : Natural;
   begin
      select
         accept Go;
      or
         terminate;
      end select;
      Stream := PA_New (C.Strings.Null_Ptr, Name, 1, C.Strings.Null_Ptr, SName,
                        Spec'Access, System.Null_Address, Attr'Access, Err'Access);
      C.Strings.Free (Name);
      C.Strings.Free (SName);
      while Stream /= System.Null_Address and then not Shared.Stopping loop
         P := Shared.Get;
         Shared.Take (Shots, N_Shots);
         for K in 1 .. N_Shots loop
            for V of Voices loop
               if not V.On then
                  V := (On => True, E => Shots (K).E, Age => 0.0,
                        Level => Shots (K).Level, Pan => Shots (K).Pan, others => <>);
                  exit;
               end if;
            end loop;
         end loop;
         for I in 0 .. Frames - 1 loop
            declare
               K : constant Float := 0.0015;
               L, R : Float := 0.0;
               Gear_Span : constant Float := 17.0;
               G : Float;
               Rev : Float;
               F : Float;
               S : Float;
            begin
               Speed_S := Speed_S + K * (P.Speed / 4.0 - Speed_S);
               Thr_S := Thr_S + K * (P.Throttle - Thr_S);
               Rough_S := Rough_S + 0.004 * (P.Rough - Rough_S);
               Slip_S := Slip_S + 0.003 * (P.Slip - Slip_S);
               Other_S := Other_S + K * (P.Other_Speed / 4.0 - Other_S);
               Other_L := Other_L + K * (P.Other_Level - Other_L);
               Other_P := Other_P + K * (P.Other_Pan - Other_P);

               --  The engine: a growl that climbs through its gears
               G := Speed_S / (if P.Voice >= 3 then Gear_Span * 0.7 else Gear_Span);
               Rev := 0.42 + 0.58 * (G - Float'Floor (G)) ** 0.8;
               if Speed_S > 4.0 * Gear_Span then
                  Rev := 0.42 + 0.58 * Float'Min (1.4, (Speed_S - 3.0 * Gear_Span) / Gear_Span);
               end if;
               if P.Air then
                  Rev := Rev + 0.2 * Thr_S;
               end if;
               if P.Voice = 2 or else P.Voice = 7 or else P.Voice = 10 then
                  --  a propeller: no gears, a steady drone that climbs with speed
                  Rev := 0.55 + 0.45 * Float'Min (1.2, Speed_S / 80.0) + 0.1 * Thr_S;
               end if;
               F := (case P.Voice is
                        when 1 => 45.0 + 110.0 * Rev,
                        when 2 => 70.0 + 95.0 * Rev,
                        when 3 => 110.0 + 300.0 * Rev,    --  a howling four-stroke
                        when 4 => 85.0 + 230.0 * Rev,     --  a rasping two-stroke
                        when 5 => 100.0 + 260.0 * Rev,    --  a lawnmower of a kart
                        when 6 => 32.0 + 55.0 * Rev,      --  a tank's diesel
                        when 7 => 90.0 + 110.0 * Rev,     --  a hovercraft's fans
                        when 8 => 40.0 + 70.0 * Rev,      --  a submarine's hum
                        when 9 => 36.0 + 120.0 * Rev,     --  a monster truck's big engine
                        when 10 => 170.0 + 220.0 * Rev,   --  a rover's electric whine
                        when 11 => 95.0 + 240.0 * Rev,    --  a snowmobile's two-stroke
                        when others => 75.0 + 170.0 * Rev) * (if P.Boost then 1.15 else 1.0);
               Eng1 := Eng1 + F * Dt;
               Eng1 := Eng1 - Float'Floor (Eng1);
               Eng2 := Eng2 + F * 1.503 * Dt;
               Eng2 := Eng2 - Float'Floor (Eng2);
               Whine := Whine + (300.0 + Speed_S * 16.0) * Dt;
               Whine := Whine - Float'Floor (Whine);
               S := (2.0 * Eng1 - 1.0) * 0.6 + (2.0 * Eng2 - 1.0) * 0.3
                 + Sin (Two_Pi * Eng1 * 0.5) * 0.5;
               S := Low (Eng_F, S, 500.0 + 2200.0 * Thr_S + Speed_S * 15.0)
                 * (0.35 + 0.65 * Thr_S)
                 + Sin (Two_Pi * Whine) * 0.05 * Float'Min (1.0, Speed_S / 40.0);
               L := L + S * (if P.Voice = 20 then 0.03 else 0.32);
               R := R + S * (if P.Voice = 20 then 0.03 else 0.32);

               --  Wind, tyres and scraping
               S := Low (Wind_F, Noise, 300.0 + Speed_S * 30.0) * Float'Min (1.0, (Speed_S / 70.0) ** 2)
                 * (if P.Voice = 20 then 1.5 else 0.5);
               L := L + S;
               R := R + S;
               if P.Voice = 1 then
                  --  the water rushing past the hull
                  S := Low (Rush_F, Noise, 500.0 + Speed_S * 25.0) * Float'Min (1.0, Speed_S / 40.0) * 0.35;
                  L := L + S;
                  R := R + S;
               end if;
               --  gravel and grass under the wheels: a rumble that comes and goes
               S := Low (Scr_F, Noise, 260.0 + Speed_S * 6.0) * Rough_S * 1.1 * Float'Min (1.0, Speed_S / 25.0)
                 * (0.7 + 0.3 * Sin (Two_Pi * Eng1));
               S := Low (Scr_F2, S, 3000.0);
               L := L + S;
               R := R + S;
               S := (Low (Slip_F, Noise, 1800.0) * 0.6 + Sin (Two_Pi * Whine * 3.0) * 0.08) * Slip_S * 0.4
                 * Float'Min (1.0, Speed_S / 15.0);
               L := L + S;
               R := R + S;

               --  The nearest other car
               if Other_L > 0.002 then
                  Oth := Oth + (55.0 + Other_S * 3.0) * Dt;
                  Oth := Oth - Float'Floor (Oth);
                  S := Low (Oth_F, 2.0 * Oth - 1.0, 900.0) * Other_L * 0.25;
                  L := L + S * (1.0 - Other_P) * 0.7;
                  R := R + S * (1.0 + Other_P) * 0.7;
               end if;

               --  What goes bang
               for V of Voices loop
                  if V.On then
                     declare
                        A : constant Float := V.Age;
                        X : Float := 0.0;
                        Len : Float := 1.0;
                     begin
                        case V.E is
                           when Thud =>
                              Len := 0.3;
                              X := Sin (Two_Pi * V.Ph1) * Exp (-A * 20.0)
                                + Low (V.F1, Noise, 900.0) * Exp (-A * 28.0) * 1.4;
                              V.Ph1 := V.Ph1 + 95.0 * Dt;
                           when Splash =>
                              Len := 0.7;
                              X := (Noise - Low (V.F1, Noise, 900.0)) * 0.9 * Exp (-A * 5.0)
                                * Float'Min (1.0, A * 60.0)
                                + Sin (Two_Pi * V.Ph1) * 0.25 * Exp (-A * 12.0);
                              V.Ph1 := V.Ph1 + (300.0 + 500.0 * Exp (-A * 10.0)) * Dt;
                           when Fall =>
                              Len := 0.9;
                              V.Ph1 := V.Ph1 + (900.0 * Exp (-A * 2.2) + 80.0) * Dt;
                              X := Sin (Two_Pi * V.Ph1) * 0.25 * (1.0 - A / Len);
                           when Jump =>
                              Len := 0.35;
                              V.Ph1 := V.Ph1 + (220.0 + 900.0 * A) * Dt;
                              X := Sin (Two_Pi * V.Ph1) * 0.18 * (1.0 - A / Len)
                                + Low (V.F1, Noise, 1500.0) * 0.4 * Exp (-A * 10.0);
                           when Land =>
                              Len := 0.25;
                              X := Sin (Two_Pi * V.Ph1) * Exp (-A * 16.0) * 0.9
                                + Low (V.F1, Noise, 500.0) * Exp (-A * 20.0);
                              V.Ph1 := V.Ph1 + 70.0 * Dt;
                           when Whoosh =>
                              Len := 0.8;
                              X := Low (V.F1, Noise, 300.0 + 3000.0 * A) * 1.1 * Sin (3.1416 * A / Len);
                           when Zap =>
                              Len := 0.4;
                              V.Ph1 := V.Ph1 + (300.0 + 1400.0 * A) * Dt;
                              X := (if V.Ph1 - Float'Floor (V.Ph1) < 0.5 then 0.15 else -0.15) * (1.0 - A / Len);
                           when Beep_Low | Beep_High =>
                              Len := (if V.E = Beep_Low then 0.22 else 0.6);
                              V.Ph1 := V.Ph1 + (if V.E = Beep_Low then 660.0 else 1320.0) * Dt;
                              X := (if V.Ph1 - Float'Floor (V.Ph1) < 0.5 then 0.22 else -0.22)
                                * Float'Min (1.0, (Len - A) * 30.0);
                           when Lap =>
                              Len := 0.45;
                              V.Ph1 := V.Ph1 + (if A < 0.15 then 988.0 else 1319.0) * Dt;
                              X := Sin (Two_Pi * V.Ph1) * 0.3 * Float'Min (1.0, (Len - A) * 10.0);
                           when Chime =>
                              Len := 0.5;
                              V.Ph1 := V.Ph1 + (if A < 0.12 then 1047.0 elsif A < 0.24 then 1319.0 else 1568.0) * Dt;
                              X := Sin (Two_Pi * V.Ph1) * 0.3 * Exp (-(A - 0.12 * Float'Floor (A / 0.12)) * 8.0);
                           when Fanfare =>
                              Len := 1.4;
                              declare
                                 Fq : constant Float :=
                                   (if A < 0.15 then 523.0 elsif A < 0.3 then 659.0 elsif A < 0.45 then 784.0
                                    else 1047.0);
                              begin
                                 V.Ph1 := V.Ph1 + Fq * Dt;
                                 V.Ph2 := V.Ph2 + Fq * 1.5 * Dt;
                                 X := ((if V.Ph1 - Float'Floor (V.Ph1) < 0.5 then 0.16 else -0.16)
                                       + Sin (Two_Pi * V.Ph2) * 0.1)
                                   * Float'Min (1.0, (Len - A) * 3.0);
                              end;
                           when Pickup =>
                              Len := 0.3;
                              declare
                                 Fq : constant Float :=
                                   (if A < 0.07 then 880.0 elsif A < 0.14 then 1175.0 else 1760.0);
                              begin
                                 V.Ph1 := V.Ph1 + Fq * Dt;
                                 X := Sin (Two_Pi * V.Ph1) * 0.35 * Exp (-(A - 0.07 * Float'Floor (A / 0.07)) * 20.0);
                              end;
                           when Launch =>
                              Len := 0.7;
                              X := Low (V.F1, Noise, 400.0 + 3000.0 * A) * 1.4 * Exp (-A * 4.0)
                                * Float'Min (1.0, A * 40.0);
                           when Bang =>
                              Len := 1.4;
                              X := Low (V.F1, Noise, 3000.0 * Exp (-A * 3.0) + 120.0) * 2.0 * Exp (-A * 2.8)
                                + Sin (Two_Pi * V.Ph1) * Exp (-A * 7.0) * 1.1;
                              V.Ph1 := V.Ph1 + (42.0 + 40.0 * Exp (-A * 10.0)) * Dt;
                           when Shield_Up =>
                              Len := 0.8;
                              V.Ph1 := V.Ph1 + 523.0 * Dt;
                              V.Ph2 := V.Ph2 + 784.0 * (1.0 + 0.01 * Sin (A * 40.0)) * Dt;
                              X := (Sin (Two_Pi * V.Ph1) + Sin (Two_Pi * V.Ph2)) * 0.18
                                * Sin (3.1416 * A / Len);
                           when Moan =>
                              --  a ghost's "uhhh": a buzzing voice through an "oo" of a mouth,
                              --  wavering, and sinking as it fades
                              Len := 1.5;
                              declare
                                 Pitch : constant Float :=
                                   (190.0 * Exp (-A * 0.45)) * (1.0 + 0.04 * Sin (Two_Pi * 5.5 * A));
                                 Env : constant Float := Sin (3.1416 * A / Len) ** 2;
                                 Voice_S : Float;
                              begin
                                 V.Ph1 := V.Ph1 + Pitch * Dt;
                                 V.Ph1 := V.Ph1 - Float'Floor (V.Ph1);
                                 Voice_S := 2.0 * V.Ph1 - 1.0;
                                 X := (Low (V.F1, Voice_S, 420.0) * 2.2 + Low (V.F2, Noise, 900.0) * 0.25) * Env;
                              end;
                           when Drop =>
                              Len := 0.35;
                              V.Ph1 := V.Ph1 + 310.0 * Dt;
                              V.Ph2 := V.Ph2 + 477.0 * Dt;
                              X := (Sin (Two_Pi * V.Ph1) + Sin (Two_Pi * V.Ph2)) * 0.3 * Exp (-A * 14.0);
                        end case;
                        X := X * V.Level;
                        L := L + X * (1.0 - V.Pan * 0.6);
                        R := R + X * (1.0 + V.Pan * 0.6);
                        V.Age := V.Age + Dt;
                        if V.Age > Len then
                           V.On := False;
                        end if;
                     end;
                  end if;
               end loop;

               --  The music
               if P.Music > 0 then
                  declare
                     Tempo : constant Float := (if P.Music = 1 then 112.0 else 138.0);
                     Step_Len : constant Float := 60.0 / Tempo / 4.0;
                     type Chord is array (0 .. 2) of Float;
                     Chords : constant array (0 .. 3) of Chord :=
                       ((261.6, 329.6, 392.0), (220.0, 261.6, 329.6), (174.6, 220.0, 261.6), (196.0, 246.9, 293.7));
                     M : Float := 0.0;
                  begin
                     Beat_T := Beat_T + Dt;
                     if Beat_T >= Step_Len then
                        Beat_T := Beat_T - Step_Len;
                        Step_N := (Step_N + 1) mod 64;
                        declare
                           Bar : constant Natural := Step_N / 16;
                           S16 : constant Natural := Step_N mod 16;
                           C : constant Chord := Chords (Bar);
                        begin
                           Bass_F := C (0) / 4.0 * (if S16 mod 8 = 6 then 1.5 else 1.0);
                           Arp_F := C (S16 mod 3) * (if S16 mod 6 < 3 then 2.0 else 1.0);
                           Note_T := 0.0;
                           if S16 mod 4 = 0 then
                              Kick_T := 0.0;
                           end if;
                           if S16 mod 2 = 1 then
                              Hat_T := 0.0;
                           end if;
                        end;
                     end if;
                     Note_T := Note_T + Dt;
                     Kick_T := Kick_T + Dt;
                     Hat_T := Hat_T + Dt;
                     Bass_Ph := Bass_Ph + Bass_F * Dt;
                     Bass_Ph := Bass_Ph - Float'Floor (Bass_Ph);
                     Arp_Ph := Arp_Ph + Arp_F * Dt;
                     Arp_Ph := Arp_Ph - Float'Floor (Arp_Ph);
                     Lead_Ph := Lead_Ph + (50.0 + 80.0 * Exp (-Kick_T * 30.0)) * Dt;
                     M := Low (Mus_F, (2.0 * Bass_Ph - 1.0), 600.0) * 0.5
                       + (if Arp_Ph < 0.5 then 0.12 else -0.12) * Exp (-Note_T * 9.0)
                       + Sin (Two_Pi * Lead_Ph) * 0.6 * Exp (-Kick_T * 14.0)
                       + (Noise - Low (Hat_F, Noise, 6000.0)) * 0.12 * Exp (-Hat_T * 40.0);
                     Music_Out := M * P.Music_Level;
                  end;
               end if;

               L := L * P.Master + Music_Out;
               R := R * P.Master + Music_Out;
               Music_Out := 0.0;
               --  softly limited
               L := L / (1.0 + abs L);
               R := R / (1.0 + abs R);
               Buffer (2 * I) := Integer_16 (L * 30_000.0);
               Buffer (2 * I + 1) := Integer_16 (R * 30_000.0);
            end;
         end loop;
         if PA_Write (Stream, Buffer'Address, C.size_t (Buffer'Size / 8), Err'Access) < 0 then
            exit;
         end if;
      end loop;
      if Stream /= System.Null_Address then
         PA_Free (Stream);
      end if;
   exception
      when others =>
         if Stream /= System.Null_Address then
            PA_Free (Stream);
         end if;
   end Mixer;

   Started : Boolean := False;

   procedure Start is
   begin
      if not Started then
         Started := True;
         Mixer.Go;
      end if;
   end Start;

   procedure Stop is
   begin
      Shared.Halt;
   end Stop;

end Audio;
