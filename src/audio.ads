--  Adamachines: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Synthesised sound, mixed in a task of its own and played through
--  PulseAudio: the buzz of a small engine, the tyres, the gravel, the
--  other cars, and the knocks, splashes and beeps of the race.  Without
--  a sound server the game is silent.  (After the sound of AdaFlip.)

package Audio is

   type Params is record
      Speed    : Float := 0.0;   --  of the car heard, in world units a second
      Throttle : Float := 0.0;
      Boost    : Boolean := False;
      Air      : Boolean := False;   --  wheels off the ground
      Rough    : Float := 0.0;   --  0 .. 1: off the road
      Slip     : Float := 0.0;   --  0 .. 1: sliding
      Other_Speed, Other_Level, Other_Pan : Float := 0.0;   --  the nearest other car
      Voice    : Natural := 0;   --  Tracks.Vehicle_Kind'Pos of the vehicle heard
      Music    : Natural := 0;   --  0 none, 1 the title's tune, 2 the race's
      Music_Level : Float := 0.5;   --  the music's own loudness, apart from Master
      Master   : Float := 0.8;
   end record;

   procedure Start;
   procedure Stop;
   procedure Set (P : Params);

   type Effect is (Thud, Splash, Fall, Jump, Land, Whoosh, Zap, Beep_Low, Beep_High, Lap, Chime, Fanfare,
                   Pickup, Launch, Bang, Shield_Up, Drop, Moan, Jingle);

   procedure Play (E : Effect; Level : Float := 1.0; Pan : Float := 0.0);
   --  Level 0 .. 1, Pan -1 left .. 1 right

end Audio;
