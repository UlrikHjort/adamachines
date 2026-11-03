--  Adamachines: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The announcer: a few words spoken by espeak-ng, when it is there.
--  The speech runs in a process of its own, so the game never waits.

package Speech is

   Enabled : Boolean := True;

   type Voice_Kind is (Woman, Man);
   Voice : Voice_Kind := Woman;
   Loudness : Natural := 140;   --  espeak-ng's amplitude, 0 .. 200

   function Available return Boolean;
   procedure Say (Text : String);

end Speech;
