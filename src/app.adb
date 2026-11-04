--  Adamachines: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Real_Time;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;

with Cairo;
with Cairo.Image_Surface;
with Cairo.Png;
with Cairo.Surface;
with Gdk.Event;
with Gdk.Frame_Clock;
with Gdk.Types;
with Gdk.Types.Keysyms;
with Glib; use Glib;
with Gtk.Drawing_Area;
with Gtk.Main;
with Gtk.Widget;
with Gtk.Window;

with Audio;
with Cars;
with Editor;
with Records;
with Speech;
with Geom; use Geom;
with Hud;
with Net;
with Race;
with Scene;
with Tracks;

package body App is

   use type Gdk.Types.Gdk_Key_Type;
   use type Hud.Screen;
   use type Speech.Voice_Kind;
   use type Race.Event_Kind;
   use type Race.Game_Mode;
   use type Race.Phase_Kind;
   use type Tracks.Material;
   use type Tracks.Theme_Kind;
   use type Net.Role_Kind;
   use type Net.Join_State;

   Window : Gtk.Window.Gtk_Window;
   Area : Gtk.Drawing_Area.Gtk_Drawing_Area;
   Is_Fullscreen : Boolean := False;

   Mode : Hud.Screen := Hud.Title;
   Selected : Positive := 1;
   Overlay : Hud.Overlay;

   --  The ways to play
   type Play_Mode is (Race_1P, Race_2P, Duel_2P, Champ, Trial_1P, Net_Game);
   type Cup_Kind is (Car_Cup, House_Cup, Speed_Cup, Water_Air_Cup, Holiday_Cup, Strange_Cup, Frozen_Cup,
                     Grand_Tour);
   type Track_List is array (Positive range <>) of Tracks.Track_Id;
   Car_Tracks : constant Track_List := (1, 2, 3, 4, 14, 15);
   House_Tracks : constant Track_List := (11, 16, 20, 15);
   Frozen_Tracks : constant Track_List := (3, 16, 29, 23);
   Holiday_Tracks : constant Track_List := (21, 25, 23, 26);
   Odd_Tracks : constant Track_List := (27, 28, 24, 20);
   Speed_Tracks : constant Track_List := (9, 10, 12, 13, 22, 24);
   Water_Air_Tracks : constant Track_List := (5, 6, 17, 19, 7, 8, 18);
   All_Tracks : constant Track_List :=
     (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26,
      27, 28, 29);

   function Cup_Tracks (C : Cup_Kind) return Track_List is
     (case C is
         when Car_Cup => Car_Tracks,
         when House_Cup => House_Tracks,
         when Holiday_Cup => Holiday_Tracks,
         when Strange_Cup => Odd_Tracks,
         when Frozen_Cup => Frozen_Tracks,
         when Speed_Cup => Speed_Tracks,
         when Water_Air_Cup => Water_Air_Tracks,
         when Grand_Tour => All_Tracks);

   function Cup_Name (C : Cup_Kind) return String is
     (case C is
         when Car_Cup => "CAR CUP",
         when House_Cup => "HOUSE CUP",
         when Holiday_Cup => "HOLIDAY CUP",
         when Strange_Cup => "STRANGE WORLDS CUP",
         when Frozen_Cup => "SNOW AND ICE CUP",
         when Speed_Cup => "SPEED CUP",
         when Water_Air_Cup => "WATER AND AIR CUP",
         when Grand_Tour => "GRAND TOUR");

   Champ_Points_Table : constant array (1 .. 6) of Natural := (10, 7, 5, 3, 2, 1);

   --  The choices in the menu
   Track_Sel : Tracks.Track_Id := 14;   --  Toy Train Town
   Play : Play_Mode := Race_1P;
   Cup : Cup_Kind := Car_Cup;
   Opponents : Natural := 5;
   Laps : Positive := 3;
   Level : Race.Difficulty := Race.Normal;
   Items_On : Boolean := True;
   Muted : Boolean := False;          --  M: everything quiet for a while, not kept
   Sound_Volume : Natural := 8;       --  0 .. 10, the engines, the knocks and the announcer
   Music_Volume : Natural := 6;       --  0 .. 10
   Voice_On : Boolean := True;
   Voice : Speech.Voice_Kind := Speech.Woman;
   Customs_First : Boolean := False;   --  your own tracks at the start of the list, not the end

   --  A championship under way
   Champ_Round : Natural := 0;
   Champ_Points : Hud.Points_Array := (others => 0);
   Champ_Opponents : Natural := 5;
   Champ_Scored : Boolean := False;

   --  Time trials and records
   New_Record : Boolean := False;
   Seen_Lap : Natural := 0;
   Was_Running : Boolean := False;
   Ghost_Step : Natural := 0;

   --  The network game
   Player_Name : Race.Name_String := "PLAYER";
   Join_Address : Unbounded_String;
   type Edit_Kind is (Not_Editing, Editing_Name, Editing_Address);
   Editing : Edit_Kind := Not_Editing;
   Edit_Text : Unbounded_String;
   My_Address : Unbounded_String;      --  as the host: where others join
   Net_Steps : Natural := 0;
   Auto_Host_T : Float := 0.0;         --  for the automatic runs: seconds in the lobby
   Alone_Asked : Boolean := False;     --  the host was asked to start again, nobody having joined
   Players_Seen : Natural := 0;        --  as the host: to tell when someone joins
   Held_Key : Gdk.Types.Gdk_Key_Type := 0;   --  Enter, Space or Esc held down: repeats are not presses

   function Hosting return Boolean is (Net.Role = Net.Hosting);
   function Client return Boolean is (Net.Role = Net.Joined);
   function In_Net_Race return Boolean is (Race.State.Mode = Race.Net and then not Race.State.Attract);

   function Trim_Name (N : String) return String is
      L : Natural := N'Last;
   begin
      while L >= N'First and then N (L) = ' ' loop
         L := L - 1;
      end loop;
      return N (N'First .. L);
   end Trim_Name;

   function As_Name (S : String) return Race.Name_String is
      R : Race.Name_String := (others => ' ');
   begin
      for I in 1 .. Natural'Min (6, S'Length) loop
         R (I) := (if S (S'First + I - 1) in 'a' .. 'z'
                   then Character'Val (Character'Pos (S (S'First + I - 1)) - 32)
                   else S (S'First + I - 1));
      end loop;
      return R;
   end As_Name;

   --  The feel of it
   Shake : Float := 0.0;
   Slow_T : Float := 0.0;    --  real seconds of slow motion left
   Return_To : Hud.Screen := Hud.Title;   --  where the options go back to

   function Game return Race.Game_Mode is
     (case Play is
         when Race_1P | Champ => Race.Single,
         when Race_2P => Race.Double,
         when Duel_2P => Race.Duel,
         when Trial_1P => Race.Trial,
         when Net_Game => Race.Net);

   --  The keys held
   type Pad is record
      Left, Right, Up, Down : Boolean := False;
   end record;
   Arrows, Letters : Pad;
   Fire1_Pending, Fire2_Pending : Boolean := False;
   Shift_Held : Boolean := False;

   Accum : Float := 0.0;
   Last_Time : Ada.Real_Time.Time := Ada.Real_Time.Clock;
   Events_Read : Natural := 0;
   Fps : Float := 60.0;
   Show_Fps : Boolean := False;
   New_World : Boolean := False;

   --  For pictures made without a person at the keys
   Autopilot : Boolean := False;
   Shot_File : Unbounded_String;
   Shot_Frame : Natural := 0;
   Frame_Count : Natural := 0;

   function Env (N : String) return String is
     (if Ada.Environment_Variables.Exists (N) then Ada.Environment_Variables.Value (N) else "");

   procedure Say (S : String; Seconds : Float := 1.6) is
   begin
      Overlay.Message := To_Unbounded_String (S);
      Overlay.Message_T := Seconds;
   end Say;

   procedure Announce (S : String) is
   begin
      if Voice_On and then not Muted and then Sound_Volume > 0
        and then not Race.State.Attract and then Shot_Frame = 0
      then
         Speech.Voice := Voice;
         Speech.Loudness := 30 + 17 * Sound_Volume;
         Speech.Say (S);
      end if;
   end Announce;

   function Img (N : Integer) return String is
      S : constant String := Integer'Image (N);
   begin
      return (if N >= 0 then S (S'First + 1 .. S'Last) else S);
   end Img;

   function Spoken_Place (N : Positive) return String is
     (case N is
         when 1 => "first", when 2 => "second", when 3 => "third",
         when 4 => "fourth", when 5 => "fifth", when others => "sixth");

   ---------------------------------------------------------------------------
   --  Remembered choices, in ~/.adamachinesrc
   ---------------------------------------------------------------------------

   function Rc_File return String is (Env ("HOME") & "/.adamachinesrc");

   procedure Save_Choices is
      use Ada.Text_IO;
      F : File_Type;
      function B (X : Boolean) return String is (if X then "1" else "0");
   begin
      Create (F, Out_File, Rc_File);
      Put_Line (F, "track_name " & Tracks.Name (Track_Sel));   --  by name, so new tracks change nothing
      Put_Line (F, "play " & Img (Play_Mode'Pos (Play)));
      Put_Line (F, "cup " & Img (Cup_Kind'Pos (Cup)));
      Put_Line (F, "opponents " & Img (Opponents));
      Put_Line (F, "laps " & Img (Laps));
      Put_Line (F, "level " & Img (Race.Difficulty'Pos (Level)));
      Put_Line (F, "items " & B (Items_On));
      Put_Line (F, "sound_volume " & Img (Sound_Volume));
      Put_Line (F, "music_volume " & Img (Music_Volume));
      Put_Line (F, "customs_first " & B (Customs_First));
      Put_Line (F, "name " & Trim_Name (Player_Name));
      Put_Line (F, "address " & To_String (Join_Address));
      Put_Line (F, "voice " & (if not Voice_On then "0" elsif Voice = Speech.Woman then "1" else "2"));
      Close (F);
   exception
      when others => null;
   end Save_Choices;

   procedure Load_Choices is
      use Ada.Text_IO;
      F : File_Type;
      Numbering : Natural := 0;
   begin
      if not Ada.Directories.Exists (Rc_File) then
         return;
      end if;
      Open (F, In_File, Rc_File);
      while not End_Of_File (F) loop
         declare
            L : constant String := Get_Line (F);
         begin
            if L'Length > 5 and then L (L'First .. L'First + 4) = "name " then
               Player_Name := As_Name (L (L'First + 5 .. L'Last));
            elsif L'Length > 8 and then L (L'First .. L'First + 7) = "address " then
               Join_Address := To_Unbounded_String (L (L'First + 8 .. L'Last));
            end if;
            if L'Length > 11 and then L (L'First .. L'First + 10) = "track_name " then
               for Id in Tracks.Track_Id loop
                  if Tracks.Name (Id) = L (L'First + 11 .. L'Last) then
                     Track_Sel := Id;
                  end if;
               end loop;
            end if;
            for I in L'Range loop
               if L (I) = ' ' and then (L'Length <= 11 or else L (L'First .. L'First + 10) /= "track_name ")
                 and then (L'Length <= 5 or else L (L'First .. L'First + 4) /= "name ")
                 and then (L'Length <= 8 or else L (L'First .. L'First + 7) /= "address ")
               then
                  declare
                     K : constant String := L (L'First .. I - 1);
                     V : constant Integer := Integer'Value (L (I + 1 .. L'Last));
                  begin
                     if K = "tracks" then
                        Numbering := V;
                     elsif K = "track" and then V in Tracks.Track_Id then
                        --  from before the tracks went by name: yours were 15 .. 19, then 25 .. 29
                        Track_Sel :=
                          (if Numbering < 2 and then V in 15 .. 19 then Tracks.First_Custom + V - 15
                           elsif Numbering = 2 and then V in 25 .. 29 then Tracks.First_Custom + V - 25
                           else V);
                     elsif K = "play" and then V in 0 .. Play_Mode'Pos (Play_Mode'Last) then
                        Play := Play_Mode'Val (V);
                     elsif K = "cup" and then V in 0 .. Cup_Kind'Pos (Cup_Kind'Last) then
                        Cup := Cup_Kind'Val (V);
                     elsif K = "opponents" and then V in 0 .. 5 then
                        Opponents := V;
                     elsif K = "laps" and then V in 1 .. 9 then
                        Laps := V;
                     elsif K = "level" and then V in 0 .. 2 then
                        Level := Race.Difficulty'Val (V);
                     elsif K = "items" then
                        Items_On := V = 1;
                     elsif K = "sound_volume" and then V in 0 .. 10 then
                        Sound_Volume := V;
                     elsif K = "music_volume" and then V in 0 .. 10 then
                        Music_Volume := V;
                     elsif K = "customs_first" then
                        Customs_First := V = 1;
                     elsif K = "muted" then
                        --  from before there were volumes
                        if V = 1 then
                           Sound_Volume := 0;
                        end if;
                     elsif K = "music" then
                        if V = 0 then
                           Music_Volume := 0;
                        end if;
                     elsif K = "voice" then
                        Voice_On := V /= 0;
                        Voice := (if V = 2 then Speech.Man else Speech.Woman);
                     end if;
                  end;
                  exit;
               end if;
            end loop;
         exception
            when others => null;
         end;
      end loop;
      Close (F);
   exception
      when others => null;
   end Load_Choices;

   ---------------------------------------------------------------------------
   --  The screens
   ---------------------------------------------------------------------------

   function Mode_Name (M : Play_Mode) return String is
     (case M is
         when Race_1P => "1 PLAYER RACE",
         when Race_2P => "2 PLAYER RACE",
         when Duel_2P => "2 PLAYER DUEL",
         when Champ => "CHAMPIONSHIP",
         when Trial_1P => "TIME TRIAL",
         when Net_Game => "NETWORK GAME");

   function Max_Opponents return Natural is
     (case Play is
         when Race_1P | Champ => 5,
         when Race_2P => 4,
         when Duel_2P | Trial_1P | Net_Game => 0);

   function On_Off (B : Boolean) return String is (if B then "ON" else "OFF");

   --  Ten blocks, filled as far as the volume goes
   function Volume_Bar (V : Natural) return String is
      Full : constant String := Character'Val (16#E2#) & Character'Val (16#96#) & Character'Val (16#AE#);
      Empty : constant String := Character'Val (16#E2#) & Character'Val (16#96#) & Character'Val (16#AF#);
      R : Unbounded_String;
   begin
      if V = 0 then
         return "OFF";
      end if;
      for K in 1 .. 10 loop
         Append (R, (if K <= V then Full else Empty));
      end loop;
      return To_String (R);
   end Volume_Bar;

   Keys_Hint : constant String := "up, down: choose     left, right: change     enter: select     esc: back";
   Play_Hint : constant String :=
     "P1: arrow keys, right Ctrl to use a pick-up      P2: W A S D, left Ctrl      esc: pause";

   procedure Fill_Items is
      procedure Put (K : Positive; L : String; V : String := ""; Arrows : Boolean := False) is
      begin
         Overlay.Items (K) := (To_Unbounded_String (L), To_Unbounded_String (V), Arrows);
      end Put;
      procedure Info (L : String) is
      begin
         if Overlay.Info_Count < Overlay.Info'Last then
            Overlay.Info_Count := Overlay.Info_Count + 1;
            Overlay.Info (Overlay.Info_Count) := To_Unbounded_String (L);
         end if;
      end Info;
      --  what is being typed, with a blinking cursor
      function Typing (Kind : Edit_Kind; Shown : String) return String is
        (if Editing = Kind
         then To_String (Edit_Text) & (if Integer (Overlay.Clock * 3.0) mod 2 = 0 then "_" else " ")
         else Shown);
      procedure Players_Info is
      begin
         Info ("*PLAYERS:" & Natural'Image (Net.Lobby.Players) & " OF" & Natural'Image (Race.Max_Cars)
               & ",  AND" & Natural'Image (Net.Lobby.AIs) & " AI DRIVERS");
         for K in 1 .. Net.Lobby.Players loop
            Info (Img (K) & ".  " & Trim_Name (Net.Lobby.Names (K))
                  & (if K = 1 then "  (THE HOST)" else "")
                  & (if Client and then K = Net.Me then "  (YOU)" else ""));
         end loop;
      end Players_Info;
      Champ_Over : constant Boolean := Champ_Round >= Cup_Tracks (Cup)'Length;
   begin
      Overlay.Hint := Null_Unbounded_String;
      Overlay.Hint2 := Null_Unbounded_String;
      Overlay.Record_Line := Null_Unbounded_String;
      Overlay.Info_Count := 0;
      case Mode is
         when Hud.Title =>
            Put (1, (case Play is
                        when Duel_2P => "START DUEL",
                        when Champ => "START CHAMPIONSHIP",
                        when Trial_1P => "START TIME TRIAL",
                        when Net_Game => "HOST OR JOIN A GAME",
                        when others => "START RACE"));
            Put (2, "MODE", Mode_Name (Play), True);
            if Play = Champ then
               Put (3, "CUP", Cup_Name (Cup) & " (" & Img (Cup_Tracks (Cup)'Length) & ")", True);
            elsif Play = Net_Game then
               Put (3, "TRACK", "THE HOST CHOOSES");
            else
               Put (3, "TRACK", Tracks.Name (Track_Sel), True);
            end if;
            if Max_Opponents = 0 then
               Put (4, "OPPONENTS", "NONE");
            else
               Put (4, "OPPONENTS", Img (Natural'Min (Opponents, Max_Opponents)), True);
            end if;
            if Play in Duel_2P | Net_Game then
               Put (5, "LAPS", "-");
            else
               Put (5, "LAPS", Img (Laps), True);
            end if;
            Put (6, "DIFFICULTY", Race.Difficulty'Image (Level), True);
            if Play = Trial_1P then
               Put (7, "PICK-UPS", "OFF");
            elsif Play = Net_Game then
               Put (7, "PICK-UPS", "-");
            else
               Put (7, "PICK-UPS", On_Off (Items_On), True);
            end if;
            Put (8, "TRACK EDITOR");
            Put (9, "OPTIONS");
            Put (10, "QUIT");
            Overlay.Item_Count := 10;
            Overlay.Hint := To_Unbounded_String (Play_Hint);
            Overlay.Hint2 := To_Unbounded_String (Keys_Hint & "     F11: full screen");
            if Play /= Champ and then Records.Best_Lap (Track_Sel) > 0.0 then
               Overlay.Record_Line := To_Unbounded_String
                 ("LAP RECORD  " & Hud.Time_Of (Records.Best_Lap (Track_Sel)));
            end if;
         when Hud.Options =>
            Put (1, "SOUND", Volume_Bar (Sound_Volume), True);
            Put (2, "MUSIC", Volume_Bar (Music_Volume), True);
            Put (3, "ANNOUNCER VOICE",
                 (if not Speech.Available then "NOT FOUND"
                  elsif not Voice_On then "OFF"
                  elsif Voice = Speech.Woman then "FEMALE"
                  else "MALE"), True);
            Put (4, "MY TRACKS", (if Customs_First then "FIRST" else "LAST"), True);
            Put (5, "BACK");
            Overlay.Item_Count := 5;
            Overlay.Hint := To_Unbounded_String (Keys_Hint);
         when Hud.Paused =>
            if In_Net_Race then
               --  the race goes on meanwhile
               Put (1, "BACK TO THE RACE");
               Put (2, "OPTIONS");
               Put (3, (if Hosting then "CLOSE THE GAME" else "LEAVE THE GAME"));
               Overlay.Item_Count := 3;
               Overlay.Hint := To_Unbounded_String ("The race goes on for the others while you are here.");
               goto Done;
            end if;
            Put (1, "RESUME");
            Put (2, "RESTART");
            Put (3, "OPTIONS");
            Put (4, (if Play = Champ then "QUIT CHAMPIONSHIP" else "QUIT TO MENU"));
            Overlay.Item_Count := 4;
            Overlay.Hint := To_Unbounded_String (Keys_Hint);
         when Hud.Results =>
            if In_Net_Race then
               if Hosting then
                  Put (1, "BACK TO THE LOBBY");
                  Put (2, "CLOSE THE GAME");
                  Overlay.Item_Count := 2;
               else
                  Put (1, "LEAVE THE GAME");
                  Overlay.Item_Count := 1;
                  Overlay.Hint := To_Unbounded_String ("Waiting for the host to go back to the lobby");
               end if;
            elsif Play = Champ then
               if Champ_Over then
                  Put (1, "MENU");
                  Overlay.Item_Count := 1;
               else
                  Put (1, "NEXT RACE");
                  Put (2, "QUIT CHAMPIONSHIP");
                  Overlay.Item_Count := 2;
               end if;
            else
               Put (1, (case Play is
                           when Duel_2P => "DUEL AGAIN",
                           when Trial_1P => "TRY AGAIN",
                           when others => "RACE AGAIN"));
               Put (2, "NEXT TRACK");
               Put (3, "MENU");
               Overlay.Item_Count := 3;
            end if;
         when Hud.Racing | Hud.Editor =>
            Overlay.Item_Count := 0;
         when Hud.Net_Menu =>
            Overlay.Heading := To_Unbounded_String ("NETWORK GAME");
            Put (1, "HOST A GAME");
            Put (2, "JOIN A GAME");
            Put (3, "YOUR NAME", Typing (Editing_Name, Trim_Name (Player_Name)));
            Put (4, "BACK");
            Overlay.Item_Count := 4;
            Info ("*RACE AGAINST PLAYERS ON OTHER MACHINES");
            Info ("One of you hosts the game: the host chooses the track");
            Info ("and how many AI drivers race too. Up to 8 cars in all.");
            Info ("Games on this network are found by themselves; others");
            Info ("are joined by their address. Everyone uses the arrow");
            Info ("keys (or W A S D) and Ctrl, Shift or Enter to fire.");
            Overlay.Hint := To_Unbounded_String
              ((if Editing = Editing_Name then "type your name, then enter" else Keys_Hint));
         when Hud.Host_Lobby =>
            Overlay.Heading := To_Unbounded_String ("YOUR GAME");
            Put (1, "START THE RACE");
            Put (2, "TRACK", Tracks.Name (Net.Lobby.Track), True);
            Put (3, "LAPS", Img (Net.Lobby.Laps), True);
            Put (4, "AI DRIVERS", Img (Net.Lobby.AIs), True);
            Put (5, "DIFFICULTY", Race.Difficulty'Image (Net.Lobby.Level), True);
            Put (6, "PICK-UPS", On_Off (Net.Lobby.Items), True);
            Put (7, "CLOSE THE GAME");
            Overlay.Item_Count := 7;
            Players_Info;
            Info ("*HOW THE OTHERS JOIN");
            Info ("On this network the game shows up by itself under JOIN A GAME.");
            Info ("This machine is " & To_String (My_Address) & " here. Over the internet: your");
            Info ("router's own address, with UDP port" & Natural'Image (Net.Port) & " sent on to this machine.");
            Overlay.Hint := To_Unbounded_String (Keys_Hint);
         when Hud.Browse =>
            Overlay.Heading := To_Unbounded_String ("JOIN A GAME");
            for K in 1 .. Net.N_Found loop
               Put (K, Trim_Name (Net.Found (K).Host_Name) & "'S GAME",
                    (if Net.Found (K).In_Race then "RACING: JOIN FOR THE NEXT" else Tracks.Name (Net.Found (K).Track))
                    & "   " & Img (Net.Found (K).Players) & "/" & Img (Race.Max_Cars));
            end loop;
            Put (Net.N_Found + 1, "JOIN BY ADDRESS",
                 Typing (Editing_Address,
                         (if Length (Join_Address) = 0 then "TYPE IT" else To_String (Join_Address))));
            Put (Net.N_Found + 2, "BACK");
            Overlay.Item_Count := Net.N_Found + 2;
            if Net.Joining = Net.Asking then
               Info ("*ASKING TO JOIN...");
            elsif Net.N_Found = 0 then
               Info ("*LOOKING FOR GAMES ON THIS NETWORK...");
               Info ("None yet. A game hosted here or nearby shows up in a moment.");
            else
               Info ("*GAMES ON THIS NETWORK");
               Info ("Choose one to join it.");
            end if;
            if Net.Joining in Net.Refused | Net.Gone and then Length (Net.Refusal) > 0 then
               Info (To_String (Net.Refusal));
            end if;
            Info ("A game further away is joined by its address, like 81.12.3.4 or host:27272.");
            Overlay.Hint := To_Unbounded_String
              ((if Editing = Editing_Address then "type the address, then enter" else Keys_Hint));
         when Hud.Client_Lobby =>
            Overlay.Heading := To_Unbounded_String (Trim_Name (Net.Lobby.Names (1)) & "'S GAME");
            Put (1, "LEAVE THE GAME");
            Overlay.Item_Count := 1;
            Info ("*" & Tracks.Name (Net.Lobby.Track));
            Info (Img (Net.Lobby.Laps) & " LAPS,  " & Race.Difficulty'Image (Net.Lobby.Level)
                  & ",  PICK-UPS " & On_Off (Net.Lobby.Items));
            Players_Info;
            if Net.Waiting_For_Next then
               Info ("*A RACE IS ON. YOU ARE IN THE NEXT ONE");
            else
               Info ("Waiting for " & Trim_Name (Net.Lobby.Names (1)) & " to start the race...");
            end if;
            Overlay.Hint := To_Unbounded_String (Keys_Hint);
      end case;
      <<Done>>
      Overlay.Champ := Play = Champ and then Mode = Hud.Results;
      Overlay.Champ_Round := Champ_Round;
      Overlay.Champ_Rounds := Cup_Tracks (Cup)'Length;
      Overlay.Champ_Final := Champ_Over;
      Overlay.Cup_Name := To_Unbounded_String (Cup_Name (Cup));
      Overlay.Champ_Points := Champ_Points;
      Overlay.New_Record := New_Record;
      Overlay.Record_Lap := Records.Best_Lap (Tracks.Current);
      Selected := Positive'Min (Selected, Positive'Max (1, Overlay.Item_Count));
      Overlay.Selected := Selected;
      Overlay.Mode := Mode;
   end Fill_Items;

   procedure New_Race_World is
   begin
      Scene.New_Track;
      Hud.Track_Changed;
      Events_Read := Race.Event_Serial;
      Accum := 0.0;
      Last_Time := Ada.Real_Time.Clock;
   end New_Race_World;

   procedure Start_Attract is
   begin
      Race.Setup (Track_Sel, Race.Single, 5, 3, Race.Normal, Attract => True);
      --  Some way in, so the cars are spread out and racing
      for K in 1 .. Natural (4.0 / Race.Dt) loop
         Race.Step ((others => <>), Autopilot => True);
      end loop;
      Scene.Ghost_On := False;
      New_World := True;
   end Start_Attract;

   procedure Start_Race is
      Id : constant Tracks.Track_Id :=
        (if Play = Champ then Cup_Tracks (Cup) (Cup_Tracks (Cup)'First + Champ_Round) else Track_Sel);
   begin
      Race.Local := 1;
      Race.Setup (Id, Game, (if Play = Champ then Champ_Opponents else Natural'Min (Opponents, Max_Opponents)),
                  Laps, Level, Items => Items_On);
      New_World := True;
      Mode := Hud.Racing;
      Overlay.Message_T := 0.0;
      New_Record := False;
      Champ_Scored := False;
      Seen_Lap := 0;
      Was_Running := False;
      Slow_T := 0.0;
      Scene.Ghost_On := False;
      if Play = Trial_1P then
         Records.Load_Ghost (Id);
      end if;
      Fill_Items;
      Save_Choices;
      Announce ((if Play = Champ and then Champ_Round = 0 then Cup_Name (Cup) & ". " else "")
                & Tracks.Name (Id) & ". Get ready!");
   end Start_Race;

   --  A network race: everyone sets it up the same, from the lobby
   procedure Start_Net_Race is
      L : Net.Lobby_Info renames Net.Lobby;
   begin
      Race.Local := (if Hosting then 1 else Natural'Max (1, Net.Me));
      Race.Setup_Net (L.Track, Natural'Max (1, L.Players), L.Names, L.AIs, L.Laps, L.Level, L.Items);
      New_World := True;
      Mode := Hud.Racing;
      Overlay.Message_T := 0.0;
      New_Record := False;
      Seen_Lap := 0;
      Was_Running := False;
      Slow_T := 0.0;
      Net_Steps := 0;
      Editing := Not_Editing;
      Scene.Ghost_On := False;
      Fill_Items;
      Announce (Tracks.Name (L.Track) & ". Get ready!");
   end Start_Net_Race;

   --  The race behind the lobby: on the track chosen there
   procedure Lobby_Attract is
   begin
      if Track_Sel /= Net.Lobby.Track or else not Race.State.Attract then
         Track_Sel := Net.Lobby.Track;
         Start_Attract;
      end if;
   end Lobby_Attract;

   procedure Start_Championship is
   begin
      Champ_Round := 0;
      Champ_Points := (others => 0);
      Champ_Opponents := Natural'Max (1, Natural'Min (Opponents, 5));
      Start_Race;
   end Start_Championship;

   procedure To_Title is
   begin
      if Net.Role /= Net.Off then
         Net.Stop;
      end if;
      Editing := Not_Editing;
      Mode := Hud.Title;
      Selected := 1;
      Start_Attract;
      Fill_Items;
   end To_Title;

   function Turn (V, Dir, Lo, Hi : Integer) return Integer is
     (if V + Dir > Hi then Lo elsif V + Dir < Lo then Hi else V + Dir);

   --  The next track in the list: your own ones only once they are made
   --  in the order chosen: the built-in tracks then yours, or yours first
   function Next_Track (T : Tracks.Track_Id; Dir : Integer) return Tracks.Track_Id is
      N : constant Positive := Tracks.Track_Count;
      function Place_Of (Id : Tracks.Track_Id) return Positive is
        (if not Customs_First then Id
         elsif Tracks.Is_Custom (Id) then Id - Tracks.First_Custom + 1
         else Id + Tracks.Custom_Slots);
      function Id_At (P : Positive) return Tracks.Track_Id is
        (if not Customs_First then P
         elsif P <= Tracks.Custom_Slots then Tracks.First_Custom + P - 1
         else P - Tracks.Custom_Slots);
      P : Positive := Place_Of (T);
      R : Tracks.Track_Id := T;
   begin
      for Tries in 1 .. N loop
         P := Turn (P, Dir, 1, N);
         R := Id_At (P);
         exit when not Tracks.Is_Custom (R) or else Tracks.Slots (Tracks.Slot_Of (R)).Saved;
      end loop;
      return R;
   end Next_Track;

   procedure Change (Dir : Integer) is
   begin
      if Mode = Hud.Title then
         case Selected is
            when 2 =>
               Play := Play_Mode'Val (Turn (Play_Mode'Pos (Play), Dir, 0, Play_Mode'Pos (Play_Mode'Last)));
               if Max_Opponents > 0 then
                  Opponents := Natural'Max ((if Play = Race_2P then 0 else 1), Natural'Min (Opponents, Max_Opponents));
               end if;
            when 3 =>
               if Play = Net_Game then
                  null;
               elsif Play = Champ then
                  Cup := Cup_Kind'Val (Turn (Cup_Kind'Pos (Cup), Dir, 0, Cup_Kind'Pos (Cup_Kind'Last)));
               else
                  Track_Sel := Next_Track (Track_Sel, Dir);
                  Start_Attract;
               end if;
            when 4 =>
               if Max_Opponents > 0 then
                  Opponents := Natural (Turn (Opponents, Dir, (if Play = Race_2P then 0 else 1), Max_Opponents));
               end if;
            when 5 =>
               if Play not in Duel_2P | Net_Game then
                  Laps := Turn (Laps, Dir, 1, 9);
               end if;
            when 6 =>
               Level := Race.Difficulty'Val (Turn (Race.Difficulty'Pos (Level), Dir, 0, 2));
            when 7 =>
               if Play not in Trial_1P | Net_Game then
                  Items_On := not Items_On;
               end if;
            when others => null;
         end case;
      elsif Mode = Hud.Options then
         case Selected is
            when 1 =>
               Sound_Volume := Natural (Clamp (Float (Sound_Volume + Dir), 0.0, 10.0));
               Audio.Play (Audio.Beep_Low, 0.8);   --  to hear how loud
            when 2 =>
               Music_Volume := Natural (Clamp (Float (Music_Volume + Dir), 0.0, 10.0));
            when 3 =>
               --  woman, man, off, and round again
               if not Voice_On then
                  Voice_On := True;
                  Voice := Speech.Woman;
               elsif Voice = Speech.Woman then
                  Voice := Speech.Man;
               else
                  Voice_On := False;
               end if;
               if Voice_On and then not Muted and then Sound_Volume > 0 then
                  Speech.Voice := Voice;
                  Speech.Loudness := 30 + 17 * Sound_Volume;
                  Speech.Say ("Ready to race!");
               end if;
            when 4 =>
               Customs_First := not Customs_First;
            when others => null;
         end case;
         Save_Choices;
      elsif Mode = Hud.Host_Lobby then
         declare
            L : Net.Lobby_Info renames Net.Lobby;
         begin
            case Selected is
               when 2 =>
                  --  the built-in tracks only: the others would not have yours
                  L.Track := Turn (L.Track, Dir, 1, Tracks.First_Custom - 1);
                  Track_Sel := L.Track;
                  Start_Attract;
               when 3 => L.Laps := Turn (L.Laps, Dir, 1, 9);
               when 4 =>
                  L.AIs := Turn (L.AIs, Dir, (if L.Players <= 1 then 1 else 0),
                                 Race.Max_Cars - Natural'Max (1, L.Players));
               when 5 => L.Level := Race.Difficulty'Val (Turn (Race.Difficulty'Pos (L.Level), Dir, 0, 2));
               when 6 => L.Items := not L.Items;
               when others => null;
            end case;
            Net.Changed;
         end;
      end if;
      Fill_Items;
   end Change;

   procedure Open_Options is
   begin
      Return_To := Mode;
      Mode := Hud.Options;
      Selected := 1;
   end Open_Options;

   --  Hosting a game, with what was last chosen
   procedure Begin_Hosting is
      L : Net.Lobby_Info renames Net.Lobby;
   begin
      if not Net.Host (Player_Name) then
         Say ("A GAME IS HOSTED ON THIS MACHINE ALREADY", 3.0);
         return;
      end if;
      L.Track := (if Tracks.Is_Custom (Track_Sel) then 14 else Track_Sel);
      L.Laps := Laps;
      L.Level := Level;
      L.Items := Items_On;
      L.AIs := Natural'Min (3, Race.Max_Cars - 1);
      Alone_Asked := False;
      Players_Seen := 1;
      My_Address := To_Unbounded_String (Net.Local_Address);
      Net.Changed;
      Mode := Hud.Host_Lobby;
      Selected := 1;
      Lobby_Attract;
   end Begin_Hosting;

   --  Out of the game, to the network menu
   procedure Leave_Net is
   begin
      Net.Stop;
      Editing := Not_Editing;
      Mode := Hud.Net_Menu;
      Selected := 1;
      if not Race.State.Attract then
         Start_Attract;
      end if;
   end Leave_Net;

   procedure Join_Game (Address : String) is
   begin
      Net.Join (Address, Player_Name);
   end Join_Game;

   procedure Choose is
   begin
      case Mode is
         when Hud.Title =>
            case Selected is
               when 1 =>
                  if Play = Net_Game then
                     Mode := Hud.Net_Menu;
                     Selected := 1;
                  elsif Play = Champ then
                     Start_Championship;
                  else
                     Start_Race;
                  end if;
               when 8 =>
                  --  the track chosen, if it is one of yours; else the one edited last
                  if Tracks.Is_Custom (Track_Sel) then
                     Editor.Open (Tracks.Slot_Of (Track_Sel));
                  else
                     Editor.Open (Editor.Current);
                  end if;
                  Mode := Hud.Editor;
               when 9 =>
                  Open_Options;
               when 10 => Gtk.Main.Main_Quit;
               when others => Change (1);
            end case;
         when Hud.Options =>
            if Selected = 5 then
               Mode := Return_To;
               Selected := 1;
            else
               Change (1);
            end if;
         when Hud.Paused =>
            if In_Net_Race then
               case Selected is
                  when 1 => Mode := Hud.Racing;
                  when 2 => Open_Options;
                  when others => Leave_Net;
               end case;
               Fill_Items;
               return;
            end if;
            case Selected is
               when 1 => Mode := Hud.Racing;
               when 2 => Start_Race;
               when 3 => Open_Options;
               when others => To_Title;
            end case;
         when Hud.Results =>
            if In_Net_Race then
               if Hosting and then Selected = 1 then
                  Net.Host_Lobby;
                  Mode := Hud.Host_Lobby;
                  Selected := 1;
                  Start_Attract;
               else
                  Leave_Net;
               end if;
            elsif Play = Champ then
               if Selected = 1 and then Champ_Round < Cup_Tracks (Cup)'Length then
                  Start_Race;
               else
                  To_Title;
               end if;
            else
               case Selected is
                  when 1 => Start_Race;
                  when 2 =>
                     Track_Sel := Next_Track (Track_Sel, 1);
                     Start_Race;
                  when others => To_Title;
               end case;
            end if;
         when Hud.Racing | Hud.Editor => null;
         when Hud.Net_Menu =>
            case Selected is
               when 1 => Begin_Hosting;
               when 2 =>
                  Net.Browse;
                  Mode := Hud.Browse;
                  Selected := 1;
               when 3 =>
                  Editing := Editing_Name;
                  Edit_Text := To_Unbounded_String (Trim_Name (Player_Name));
               when others =>
                  Mode := Hud.Title;
                  Selected := 1;
            end case;
         when Hud.Host_Lobby =>
            case Selected is
               when 1 =>
                  if Net.Lobby.Players <= 1 and then not Alone_Asked then
                     Alone_Asked := True;
                     Say ("NOBODY HAS JOINED YET. ENTER AGAIN TO RACE ALONE", 3.0);
                  else
                     Alone_Asked := False;
                     Net.Host_Start;
                     Start_Net_Race;
                  end if;
               when 7 => Leave_Net;
               when others => Change (1);
            end case;
         when Hud.Browse =>
            if Selected <= Net.N_Found then
               Join_Game (To_String (Net.Found (Selected).Address));
            elsif Selected = Net.N_Found + 1 then
               Editing := Editing_Address;
               Edit_Text := Join_Address;
            else
               Leave_Net;
            end if;
         when Hud.Client_Lobby =>
            Leave_Net;
      end case;
      Fill_Items;
   end Choose;

   --  A name or an address being typed
   procedure Edit_Key (K : Gdk.Types.Gdk_Key_Type) is
      use Gdk.Types.Keysyms;
      Code : constant Natural := Natural (K);
      Most : constant Positive := (if Editing = Editing_Name then 6 else 40);
   begin
      if K = GDK_Return or else K = GDK_KP_Enter then
         if Editing = Editing_Name then
            if Length (Edit_Text) > 0 then
               Player_Name := As_Name (To_String (Edit_Text));
            end if;
            Editing := Not_Editing;
         else
            Editing := Not_Editing;
            Join_Address := Edit_Text;
            if Length (Join_Address) > 0 then
               Join_Game (To_String (Join_Address));
            end if;
         end if;
         Save_Choices;
      elsif K = GDK_Escape then
         Editing := Not_Editing;
      elsif K = GDK_BackSpace then
         if Length (Edit_Text) > 0 then
            Delete (Edit_Text, Length (Edit_Text), Length (Edit_Text));
         end if;
      elsif Code in 32 .. 126 and then Length (Edit_Text) < Most then
         declare
            C : constant Character := Character'Val (Code);
         begin
            if Editing = Editing_Name then
               if C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | ' ' | '-' | '!' then
                  Append (Edit_Text, (if C in 'a' .. 'z' then Character'Val (Code - 32) else C));
               end if;
            elsif C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '.' | ':' | '-' then
               Append (Edit_Text, C);
            end if;
         end;
      end if;
      Fill_Items;
   end Edit_Key;

   procedure Menu_Move (Dir : Integer) is
   begin
      Alone_Asked := False;
      if Overlay.Item_Count > 0 then
         Selected := Turn (Selected, Dir, 1, Overlay.Item_Count);
         Fill_Items;
      end if;
   end Menu_Move;

   procedure Toggle_Pause is
   begin
      if Mode = Hud.Racing then
         Mode := Hud.Paused;
         Selected := 1;
      elsif Mode = Hud.Paused then
         Mode := Hud.Racing;
      end if;
      Fill_Items;
   end Toggle_Pause;

   --  The race is over: points for the championship, then the results
   procedure Race_Over is
   begin
      if Play = Champ and then not Champ_Scored then
         Champ_Scored := True;
         for K in 1 .. Race.State.Count loop
            Champ_Points (K) := Champ_Points (K) + Champ_Points_Table (Race.State.Racers (K).Place);
         end loop;
         Champ_Round := Champ_Round + 1;
         if Champ_Round >= Cup_Tracks (Cup)'Length then
            declare
               Mine : constant Natural := Champ_Points (Race.Player (1));
               Ahead : Natural := 0;
            begin
               for K in 1 .. Race.State.Count loop
                  if Champ_Points (K) > Mine then
                     Ahead := Ahead + 1;
                  end if;
               end loop;
               Announce ((if Ahead = 0 then "You are the champion!"
                          else "You finished " & Spoken_Place (Ahead + 1) & " in the championship"));
            end;
         end if;
      end if;
      Mode := Hud.Results;
      Selected := 1;
      Fill_Items;
   end Race_Over;

   ---------------------------------------------------------------------------
   --  The keyboard
   ---------------------------------------------------------------------------

   procedure Set_Key (K : Gdk.Types.Gdk_Key_Type; Down : Boolean; Known : out Boolean) is
      use Gdk.Types.Keysyms;
   begin
      Known := True;
      if K = GDK_Left then Arrows.Left := Down;
      elsif K = GDK_Right then Arrows.Right := Down;
      elsif K = GDK_Up then Arrows.Up := Down;
      elsif K = GDK_Down then Arrows.Down := Down;
      elsif K = GDK_LC_a or else K = GDK_A then Letters.Left := Down;
      elsif K = GDK_LC_d or else K = GDK_D then Letters.Right := Down;
      elsif K = GDK_LC_w or else K = GDK_W then Letters.Up := Down;
      elsif K = GDK_LC_s or else K = GDK_S then Letters.Down := Down;
      else
         Known := False;
      end if;
   end Set_Key;

   function Key_Press (Self : access Gtk.Widget.Gtk_Widget_Record'Class;
                       Event : Gdk.Event.Gdk_Event_Key) return Boolean
   is
      pragma Unreferenced (Self);
      use Gdk.Types.Keysyms;
      K : constant Gdk.Types.Gdk_Key_Type := Event.Keyval;
      Known : Boolean;
   begin
      if K = GDK_F11 then
         Is_Fullscreen := not Is_Fullscreen;
         if Is_Fullscreen then
            Window.Fullscreen;
         else
            Window.Unfullscreen;
         end if;
         return True;
      elsif K = GDK_F3 then
         Show_Fps := not Show_Fps;
         return True;
      end if;
      if K = GDK_Shift_L or else K = GDK_Shift_R then
         Shift_Held := True;
      end if;
      --  A key held down repeats: for Enter, Space and Esc only the first press counts,
      --  or one long press would go through several menus at once
      if K = GDK_Return or else K = GDK_KP_Enter or else K = GDK_space or else K = GDK_Escape then
         if K = Held_Key then
            return True;
         end if;
         Held_Key := K;
      end if;
      if Editing /= Not_Editing then
         Edit_Key (K);
         return True;
      end if;
      if Mode = Hud.Editor then
         declare
            Result : Editor.Action;
         begin
            Editor.Key (K, Shift_Held, Result);
            case Result is
               when Editor.None => null;
               when Editor.Test_Drive =>
                  Track_Sel := Tracks.First_Custom + Editor.Current - 1;
                  if Play in Champ | Duel_2P then
                     Play := Race_1P;
                  end if;
                  Start_Race;
               when Editor.Leave =>
                  Track_Sel := Tracks.First_Custom + Editor.Current - 1;
                  To_Title;
                  Selected := 3;
                  Fill_Items;
            end case;
         end;
         return True;
      end if;
      Set_Key (K, True, Known);
      if Mode /= Hud.Racing then
         if K = GDK_Up or else K = GDK_LC_w then Menu_Move (-1);
         elsif K = GDK_Down or else K = GDK_LC_s then Menu_Move (1);
         elsif K = GDK_Left or else K = GDK_LC_a then Change (-1);
         elsif K = GDK_Right or else K = GDK_LC_d then Change (1);
         elsif K = GDK_Return or else K = GDK_KP_Enter or else K = GDK_space then Choose;
         elsif K = GDK_Escape then
            case Mode is
               when Hud.Title => Gtk.Main.Main_Quit;
               when Hud.Paused => Toggle_Pause;
               when Hud.Options =>
                  Mode := Return_To;
                  Selected := 1;
                  Fill_Items;
               when Hud.Net_Menu =>
                  Mode := Hud.Title;
                  Selected := 1;
                  Fill_Items;
               when Hud.Host_Lobby | Hud.Browse | Hud.Client_Lobby =>
                  Leave_Net;
                  Fill_Items;
               when Hud.Results =>
                  if In_Net_Race then
                     Selected := 2;
                     Choose;   --  out of the game
                  else
                     To_Title;
                  end if;
               when others => To_Title;
            end case;
         else
            return Known;
         end if;
         return True;
      end if;
      --  Fire: the right Ctrl, Shift or Enter for P1; the left Ctrl, Shift, Space or Q for P2.
      --  Alone, a player may use any of them.
      if K = GDK_Control_R or else K = GDK_Shift_R or else K = GDK_Return or else K = GDK_KP_Enter then
         Fire1_Pending := True;
         return True;
      elsif K = GDK_Control_L or else K = GDK_Shift_L or else K = GDK_space or else K = GDK_LC_q then
         if Play in Race_1P | Champ | Trial_1P | Net_Game then
            Fire1_Pending := True;
         else
            Fire2_Pending := True;
         end if;
         return True;
      end if;
      if K = GDK_Escape or else K = GDK_LC_p or else K = GDK_P then
         Toggle_Pause;
         return True;
      elsif K = GDK_LC_m then
         Muted := not Muted;
         Say ((if Muted then "SOUND OFF" else "SOUND ON"), 1.0);
         return True;
      end if;
      return Known;
   end Key_Press;

   function Key_Release (Self : access Gtk.Widget.Gtk_Widget_Record'Class;
                         Event : Gdk.Event.Gdk_Event_Key) return Boolean
   is
      pragma Unreferenced (Self);
      use Gdk.Types.Keysyms;
      Known : Boolean;
   begin
      if Event.Keyval = GDK_Shift_L or else Event.Keyval = GDK_Shift_R then
         Shift_Held := False;
      end if;
      if Event.Keyval = Held_Key then
         Held_Key := 0;
      end if;
      Set_Key (Event.Keyval, False, Known);
      return Known;
   end Key_Release;

   function Controls_Of (P : Pad) return Cars.Controls is
     ((Steer => (if P.Left then -1.0 else 0.0) + (if P.Right then 1.0 else 0.0),
       Throttle => (if P.Up then 1.0 else 0.0),
       Brake => (if P.Down then 1.0 else 0.0)));

   function Player_Input return Race.Input is
      I : Race.Input;
   begin
      if Play in Race_1P | Champ | Trial_1P | Net_Game then
         --  one player may use either set of keys
         I.P1 := Controls_Of ((Arrows.Left or else Letters.Left, Arrows.Right or else Letters.Right,
                               Arrows.Up or else Letters.Up, Arrows.Down or else Letters.Down));
      else
         I.P1 := Controls_Of (Arrows);
         I.P2 := Controls_Of (Letters);
      end if;
      return I;
   end Player_Input;

   ---------------------------------------------------------------------------
   --  What happened: sound and words
   ---------------------------------------------------------------------------

   function Pan_Of (P : Vec) return Float is
     (Clamp ((P.X - Race.State.Cam.X) / (Race.State.View_W * 0.5), -1.0, 1.0));

   function Near_Level (P : Vec) return Float is
      D : constant Float := Distance (P, Race.State.Cam);
   begin
      return Clamp (1.3 - D / (Race.State.View_W * 0.8), 0.0, 1.0);
   end Near_Level;

   function Who (Car : Natural) return String is
     (if Car in 1 .. Race.State.Count then "P" & Img (Race.State.Racers (Car).Human) else "");

   function Hud_Name (I : Race.Car_Index) return String is
      N : constant String := Race.State.Racers (I).Name;
      L : Natural := N'Last;
   begin
      while L > N'First and then N (L) = ' ' loop
         L := L - 1;
      end loop;
      return N (N'First .. L);
   end Hud_Name;

   procedure Hear_Events is
      use Race;
      From : Natural := Events_Read;
      Racing : constant Boolean := not State.Attract;
   begin
      if Event_Serial - From > Event_Ring then
         From := Event_Serial - Event_Ring;
      end if;
      for K in From .. Event_Serial - 1 loop
         declare
            E : constant Event := Events (K mod Event_Ring);
            Human : constant Boolean :=
              Racing and then E.Car in 1 .. State.Count
              and then (if State.Mode = Race.Net then State.Racers (E.Car).Human = Local
                        else State.Racers (E.Car).Human > 0);
            Lv : constant Float := Near_Level (E.P);
            Pn : constant Float := Pan_Of (E.P);
         begin
            Scene.Hear (E);
            case E.Kind is
               when Bump =>
                  Audio.Play (Audio.Thud, Lv * Float'Min (1.0, E.Size / 180.0), Pn);
                  if Human and then E.Car = Focus then
                     Shake := Float'Max (Shake, Float'Min (7.0, E.Size / 35.0));
                  end if;
               when Fell =>
                  if Tracks.Theme in Tracks.Workbench | Tracks.Bath then
                     Audio.Play (Audio.Fall, Lv * 0.8, Pn);
                  else
                     Audio.Play (Audio.Splash, Lv, Pn);
                  end if;
               when Splash => Audio.Play (Audio.Splash, Lv * 0.35, Pn);
               when Jumped => Audio.Play (Audio.Jump, Lv * 0.7, Pn);
               when Boosted => Audio.Play (Audio.Whoosh, Lv * 0.8, Pn);
               when Put_Back => Audio.Play (Audio.Zap, Lv * 0.5, Pn);
               when Beep =>
                  if Racing then
                     Audio.Play (Audio.Beep_Low, 0.8);
                  end if;
               when Go =>
                  if Racing then
                     Audio.Play (Audio.Beep_High, 0.9);
                  end if;
               when Landed =>
                  Audio.Play (Audio.Land, Lv * 0.8, Pn);
                  if Human and then E.Car = Focus then
                     Shake := Float'Max (Shake, 2.5);
                  end if;
               when Lap_Done | Finished =>
                  if Human and then Records.Offer_Lap (Tracks.Current, State.Racers (E.Car).Last_Lap) then
                     New_Record := True;
                     Say ("NEW LAP RECORD!", 2.0);
                     Announce ("New lap record!");
                  end if;
                  if E.Kind = Lap_Done and then Human then
                     Audio.Play (Audio.Lap, 0.8);
                     Say ((if State.Mode = Double then Who (E.Car) & " " else "")
                          & "LAP " & Img (Lap_Shown (E.Car)));
                  end if;
               when Final_Lap =>
                  if Human then
                     Say ((if State.Mode = Double then Who (E.Car) & " " else "") & "FINAL LAP", 2.0);
                     Announce ("Final lap!");
                  end if;
                  if E.Kind = Finished and then Human then
                     Audio.Play (Audio.Fanfare, 0.8);
                     if State.Mode = Trial then
                        Say ("FINISHED", 3.0);
                     else
                        Say ((if State.Mode = Double then Who (E.Car) & " " else "")
                             & "FINISHED " & Hud.Ordinal (State.Racers (E.Car).Place), 3.0);
                        if State.Mode in Single | Race.Net then
                           Announce ((if State.Racers (E.Car).Place = 1 then "You win!"
                                      else "You came " & Spoken_Place (State.Racers (E.Car).Place)));
                        end if;
                     end if;
                     if State.Mode /= Race.Net then
                        Slow_T := 1.3;   --  not in a network race: it goes on for the others
                     end if;
                  end if;
               when Left_Behind =>
                  if Racing then
                     Audio.Play (Audio.Zap, 0.6);
                     Say (Who (E.Car) & " LEFT BEHIND", 1.5);
                  end if;
               when Point_Won =>
                  Audio.Play (Audio.Chime, 0.9);
                  Say (Who (E.Car) & " TAKES A POINT", 1.6);
               when Picked =>
                  if Human then
                     Audio.Play (Audio.Pickup, 0.8);
                     Say (Weapon_Name (Weapon'Val (Integer (E.Size))), 1.0);
                  else
                     Audio.Play (Audio.Pickup, Lv * 0.35, Pn);
                  end if;
               when Fired => Audio.Play (Audio.Launch, Lv, Pn);
               when Dropped => Audio.Play (Audio.Drop, Lv, Pn);
               when Shielded => Audio.Play (Audio.Shield_Up, Lv, Pn);
               when Exploded =>
                  Audio.Play (Audio.Bang, Lv, Pn);
                  if Racing then
                     Shake := Float'Max (Shake, 8.0 * Lv);
                  end if;
               when Spun =>
                  if Human then
                     Say ((if E.Size > 0.0 and then Integer (E.Size) in 1 .. State.Count
                           then "HIT BY " & Hud_Name (Integer (E.Size))
                           else "SPIN!"), 1.2);
                  end if;
               when Scared =>
                  Audio.Play (Audio.Moan, Float'Max (Lv, (if Human then 1.0 else 0.0)), Pn);
                  if Human then
                     Say ("BOO!", 1.2);
                  end if;
               when Bells =>
                  Audio.Play (Audio.Jingle, Float'Max (0.5, Lv), Pn);
                  if Voice_On and then not Muted and then Sound_Volume > 0 and then Racing and then Shot_Frame = 0 then
                     --  in Santa's own deep voice, whatever the announcer's
                     Speech.Voice := Speech.Man;
                     Speech.Loudness := 30 + 17 * Sound_Volume;
                     Speech.Say ("Ho ho ho!");
                     Speech.Voice := Voice;
                  end if;
               when Duel_Won =>
                  Audio.Play (Audio.Fanfare, 0.9);
                  Say (Who (E.Car) & " WINS!", 3.0);
                  Announce ("Player " & (if State.Racers (E.Car).Human = 1 then "one" else "two") & " wins the duel!");
                  Slow_T := 1.3;
            end case;
         end;
      end loop;
      Events_Read := Event_Serial;
   end Hear_Events;

   procedure Update_Sound is
      use Race;
      F : constant Car_Index := Focus;
      C : Cars.Car renames State.Racers (F).Car;
      P : Audio.Params;
      Best : Float := Float'Last;
      In_Race : constant Boolean := Mode = Hud.Racing or else Mode = Hud.Results
        or else (Mode = Hud.Paused and then In_Net_Race);
      I : constant Race.Input := Player_Input;
   begin
      P.Speed := C.Speed;
      P.Voice := (if Tracks.Theme = Tracks.Halloween then 20   --  a broomstick: only the wind
                  else Tracks.Vehicle_Kind'Pos (Tracks.Vehicle));
      P.Throttle :=
        (if State.Racers (F).Human = 0 or else Autopilot or else not In_Race then 0.8
         elsif State.Racers (F).Human = 2 and then State.Mode /= Race.Net then I.P2.Throttle
         else I.P1.Throttle);
      P.Boost := C.Boost_T > 0.0;
      P.Air := C.Air;
      P.Rough := (if not C.Air and then C.Under in Tracks.Floor | Tracks.Sand then 1.0 else 0.0);
      P.Slip := C.Slip;
      for K in 1 .. State.Count loop
         if K /= F then
            declare
               D : constant Float := Distance (State.Racers (K).Car.P, C.P);
            begin
               if D < Best then
                  Best := D;
                  P.Other_Speed := State.Racers (K).Car.Speed;
                  P.Other_Level := 1.0 / (1.0 + D / 60.0);
                  P.Other_Pan := Pan_Of (State.Racers (K).Car.P);
               end if;
            end;
         end if;
      end loop;
      P.Music := (if Music_Volume = 0 or else Muted or else Shot_Frame > 0 or else Mode = Hud.Editor then 0
                  elsif Mode in Hud.Title | Hud.Options | Hud.Net_Menu | Hud.Host_Lobby
                       | Hud.Browse | Hud.Client_Lobby then 1
                  else 2);
      P.Music_Level := Float (Music_Volume) / 10.0 * (if Mode = Hud.Racing then 0.5 else 0.8);
      P.Master := Float (Sound_Volume) / 10.0
        * (if Muted or else Mode = Hud.Editor then 0.0   --  the editor is a quiet place
           elsif Mode = Hud.Paused then 0.25
           elsif Mode in Hud.Title | Hud.Options | Hud.Net_Menu | Hud.Host_Lobby
                | Hud.Browse | Hud.Client_Lobby then 0.55 else 1.0);
      Audio.Set (P);
   end Update_Sound;

   ---------------------------------------------------------------------------
   --  The frame
   ---------------------------------------------------------------------------

   --  A time trial: the lap is kept for a ghost, and the ghost is shown
   procedure Trial_Step is
      use Race;
      R : Racer renames State.Racers (Player (1));
      Going : constant Boolean := State.Phase = Running;
   begin
      if Going and then not Was_Running then
         Records.Begin_Lap;
         Ghost_Step := 0;
      end if;
      Was_Running := Going;
      if R.Lap > Seen_Lap then
         Seen_Lap := R.Lap;
         Records.End_Lap (Tracks.Current, R.Last_Lap);
         Records.Begin_Lap;
         Ghost_Step := 0;
      end if;
      if Going and then not R.Finished then
         if Ghost_Step mod 4 = 0 then
            Records.Record_Frame (R.Car.P, R.Car.H);
         end if;
         Ghost_Step := Ghost_Step + 1;
         declare
            P : Vec;
            H : Float;
            Ok : Boolean;
         begin
            Records.Ghost_At (State.Time - R.Lap_Start, P, H, Ok);
            Scene.Ghost_On := Ok;
            Scene.Ghost_P := P;
            Scene.Ghost_H := H;
         end;
      else
         Scene.Ghost_On := False;
      end if;
   end Trial_Step;

   procedure Step_World (Dt : Float) is
      Steps : Natural := 0;
      Net_Race : constant Boolean := In_Net_Race;
   begin
      if Net_Race and then Client then
         return;   --  the host runs the race
      end if;
      if not Net_Race and then (Mode = Hud.Paused or else (Mode = Hud.Options and then Return_To = Hud.Paused)) then
         return;
      end if;
      Accum := Accum + Dt;
      while Accum >= Race.Dt and then Steps < 30 loop
         declare
            I : Race.Input := (if Mode = Hud.Racing then Player_Input else (others => <>));
         begin
            if Mode = Hud.Racing then
               I.Fire1 := Fire1_Pending;
               I.Fire2 := Fire2_Pending;
            end if;
            Fire1_Pending := False;
            Fire2_Pending := False;
            if Net_Race then
               I.Keys (1) := I.P1;
               I.Fires (1) := I.Fire1;
               Net.Host_Inputs (I);
            end if;
            Race.Step (I, Autopilot => Race.State.Attract or else Autopilot);
            if Net_Race then
               Net_Steps := Net_Steps + 1;
               if Net_Steps mod 4 = 0 then
                  Net.Host_Send_State;
               end if;
            end if;
         end;
         if Play = Trial_1P and then Mode = Hud.Racing and then not Race.State.Attract then
            Trial_Step;
         end if;
         Accum := Accum - Race.Dt;
         Steps := Steps + 1;
      end loop;
      if Steps = 30 then
         Accum := 0.0;
      end if;
   end Step_World;

   procedure Set_View (W, H : Natural) is
      View_H : constant Float :=
        (if Race.State.Attract or else Race.State.Mode in Race.Single | Race.Net then 520.0 else 600.0);
   begin
      Race.State.View_H := View_H;
      Race.State.View_W := View_H * Float (Natural'Max (1, W)) / Float (Natural'Max (1, H));
   end Set_View;

   --  The network, every frame: what came, what to send, where to go
   procedure Net_Frame (Dt : Float) is
   begin
      Net.Poll (Dt);   --  nothing, when no game is hosted or joined
      if Hosting then
         declare
            L : Net.Lobby_Info renames Net.Lobby;
         begin
            if L.Players > Players_Seen then
               Say (Trim_Name (L.Names (L.Players))
                    & (if L.In_Race then " JOINS, FOR THE NEXT RACE" else " JOINS"), 2.5);
               Audio.Play (Audio.Chime, 0.6);
               Alone_Asked := False;
            end if;
            Players_Seen := L.Players;
            if Mode = Hud.Host_Lobby then
               --  room for everyone who joined
               if L.Players + L.AIs > Race.Max_Cars then
                  L.AIs := Race.Max_Cars - L.Players;
                  Net.Changed;
               end if;
               if Env ("ADAMACHINES_NET_HOST") /= "" then
                  Auto_Host_T := Auto_Host_T + Dt;
                  if L.Players >= Natural'Value (Env ("ADAMACHINES_NET_HOST")) and then Auto_Host_T > 2.0 then
                     Auto_Host_T := -1000.0;
                     Net.Host_Start;
                     Start_Net_Race;
                  end if;
               end if;
            end if;
         end;
      elsif Client then
         if Net.Joining = Net.Gone then
            declare
               Why : constant String := To_String (Net.Refusal);
            begin
               Leave_Net;
               Fill_Items;
               Say ((if Why = "" then "THE HOST HAS GONE" else Why), 3.0);
            end;
            return;
         end if;
         if Mode = Hud.Browse and then Net.Joining = Net.In_Lobby then
            Mode := Hud.Client_Lobby;
            Selected := 1;
            Editing := Not_Editing;
         end if;
         if Net.Race_Begun then
            Start_Net_Race;
         elsif Net.Back_In_Lobby then
            Mode := Hud.Client_Lobby;
            Selected := 1;
            Start_Attract;
         end if;
         if Mode = Hud.Client_Lobby then
            Lobby_Attract;
         end if;
         if In_Net_Race then
            declare
               I : constant Race.Input := (if Mode = Hud.Racing then Player_Input else (others => <>));
            begin
               Net.Send_Keys (I.P1, Mode = Hud.Racing and then Fire1_Pending);
               Fire1_Pending := False;
               Fire2_Pending := False;
            end;
         end if;
      end if;
      if Mode in Hud.Net_Menu | Hud.Host_Lobby | Hud.Browse | Hud.Client_Lobby then
         Fill_Items;
         if Selected > Natural'Max (1, Overlay.Item_Count) then
            Selected := Natural'Max (1, Overlay.Item_Count);
            Fill_Items;
         end if;
      end if;
   end Net_Frame;

   procedure Paint_Frame (Cr : Cairo.Cairo_Context; W, H : Natural; Dt : Float) is
   begin
      Scene.Draw (Cr, W, H,
                  (if In_Net_Race and then Client then 1.0   --  put in place already
                   else Clamp (Accum / Race.Dt, 0.0, 1.0)), Dt);
      Hud.Draw (Cr, W, H, Overlay);
   end Paint_Frame;

   Clock_T : Float := 0.0;

   function Draw (Self : access Gtk.Widget.Gtk_Widget_Record'Class;
                  Cr : Cairo.Cairo_Context) return Boolean
   is
      use Ada.Real_Time;
      Now : constant Time := Clock;
      Dt : constant Float := Float'Min (0.1, Float (To_Duration (Now - Last_Time)));
      W : constant Natural := Natural (Self.Get_Allocated_Width);
      H : constant Natural := Natural (Self.Get_Allocated_Height);
   begin
      Last_Time := Now;
      if Dt > 0.0 then
         Fps := Fps + (1.0 / Dt - Fps) * 0.05;
      end if;
      Frame_Count := Frame_Count + 1;
      Clock_T := Clock_T + Dt;
      if New_World then
         New_World := False;
         New_Race_World;
      end if;
      if Mode = Hud.Editor then
         Editor.Draw (Cr, W, H, Clock_T);
         Update_Sound;
         if Shot_Frame > 0 and then Frame_Count = Shot_Frame then
            declare
               use Cairo.Image_Surface;
               Surf : constant Cairo.Cairo_Surface := Create (Cairo_Format_ARGB32, Gint (W), Gint (H));
               C2 : constant Cairo.Cairo_Context := Cairo.Create (Surf);
               St : Cairo.Cairo_Status;
            begin
               Editor.Draw (C2, W, H, Clock_T);
               Cairo.Destroy (C2);
               Cairo.Surface.Flush (Surf);
               St := Cairo.Png.Write_To_Png (Surf, To_String (Shot_File));
               Ada.Text_IO.Put_Line ("Wrote " & To_String (Shot_File) & " " & St'Image);
               Cairo.Surface.Destroy (Surf);
               Gtk.Main.Main_Quit;
            end;
         end if;
         return True;
      end if;
      Net_Frame (Dt);
      Set_View (W, H);
      Step_World (if Slow_T > 0.0 then Dt * 0.3 else Dt);
      if In_Net_Race and then Client then
         --  the cars where they are to be drawn, and the camera after them smoothly
         Net.Smooth (Dt);
         Race.Follow_Camera (Dt);
         Race.State.Prev_Cam := Race.State.Cam;
      end if;
      Slow_T := Float'Max (0.0, Slow_T - Dt);
      Shake := Float'Max (0.0, Shake - Dt * 14.0);
      Scene.Shake := Shake;

      if Mode = Hud.Racing and then Race.State.Phase = Race.Over
        and then Race.State.Over_T > (if Race.State.Mode = Race.Duel then 2.5 else 3.5)
      then
         Race_Over;
      end if;

      Hear_Events;
      Update_Sound;
      Overlay.Message_T := Float'Max (0.0, Overlay.Message_T - Dt);
      Overlay.Fps := Fps;
      Overlay.Show_Fps := Show_Fps;
      Overlay.Mode := Mode;
      Overlay.Clock := Clock_T;
      Overlay.Record_Lap := Records.Best_Lap (Tracks.Current);
      Paint_Frame (Cr, W, H, Dt);

      if Shot_Frame > 0 and then Frame_Count = Shot_Frame then
         declare
            use Cairo.Image_Surface;
            Surf : constant Cairo.Cairo_Surface := Create (Cairo_Format_ARGB32, Gint (W), Gint (H));
            C2 : constant Cairo.Cairo_Context := Cairo.Create (Surf);
            St : Cairo.Cairo_Status;
         begin
            Paint_Frame (C2, W, H, 0.0);
            Cairo.Destroy (C2);
            Cairo.Surface.Flush (Surf);
            St := Cairo.Png.Write_To_Png (Surf, To_String (Shot_File));
            Ada.Text_IO.Put_Line ("Wrote " & To_String (Shot_File) & " " & St'Image);
            Cairo.Surface.Destroy (Surf);
            Gtk.Main.Main_Quit;
         end;
      end if;
      return True;
   exception
      when E : others =>
         Ada.Text_IO.Put_Line ("Frame failed: " & Ada.Exceptions.Exception_Information (E));
         Gtk.Main.Main_Quit;
         return True;
   end Draw;

   function Tick (Widget : not null access Gtk.Widget.Gtk_Widget_Record'Class;
                  Frame_Clock : not null access Gdk.Frame_Clock.Gdk_Frame_Clock_Record'Class)
                  return Boolean
   is
      pragma Unreferenced (Frame_Clock);
   begin
      Widget.Queue_Draw;
      return True;
   end Tick;

   procedure On_Destroy (Self : access Gtk.Widget.Gtk_Widget_Record'Class) is
      pragma Unreferenced (Self);
   begin
      Gtk.Main.Main_Quit;
   end On_Destroy;

   procedure Run is
      Id : Guint;
   begin
      Gtk.Main.Init;
      Load_Choices;
      Records.Load;
      Editor.Load;
      if Tracks.Is_Custom (Track_Sel) and then not Tracks.Slots (Tracks.Slot_Of (Track_Sel)).Saved then
         Track_Sel := 14;
      end if;
      if Env ("ADAMACHINES_TRACK") /= "" then
         Track_Sel := Tracks.Track_Id'Value (Env ("ADAMACHINES_TRACK"));
      end if;
      if Env ("ADAMACHINES_MODE") /= "" then
         Play := Play_Mode'Value (Env ("ADAMACHINES_MODE"));
      end if;
      Autopilot := Env ("ADAMACHINES_AUTOPILOT") /= "";
      Shot_File := To_Unbounded_String (Env ("ADAMACHINES_SHOT"));
      if Env ("ADAMACHINES_SHOT_FRAME") /= "" then
         Shot_Frame := Natural'Value (Env ("ADAMACHINES_SHOT_FRAME"));
      end if;

      Gtk.Window.Gtk_New (Window);
      Window.Set_Title ("Adamachines");
      Window.Set_Default_Size (1600, 900);
      Window.On_Destroy (On_Destroy'Access);
      Window.On_Key_Press_Event (Key_Press'Access, False);
      Window.On_Key_Release_Event (Key_Release'Access, False);

      Gtk.Drawing_Area.Gtk_New (Area);
      Area.On_Draw (Draw'Access);
      Area.Set_Can_Focus (True);
      Window.Add (Area);
      Window.Show_All;
      if Env ("ADAMACHINES_FULLSCREEN") /= "" then
         Window.Fullscreen;
         Is_Fullscreen := True;
      end if;

      Audio.Start;
      if Env ("ADAMACHINES_EDITOR") /= "" then
         Mode := Hud.Editor;
      elsif Env ("ADAMACHINES_AUTOSTART") /= "" then
         if Play = Champ then
            Start_Championship;
         else
            Start_Race;
         end if;
      elsif Env ("ADAMACHINES_NET_HOST") /= "" then
         Play := Net_Game;
         To_Title;
         Begin_Hosting;
         Fill_Items;
      elsif Env ("ADAMACHINES_NET_JOIN") /= "" then
         Play := Net_Game;
         To_Title;
         Net.Browse;
         Mode := Hud.Browse;
         Join_Game (Env ("ADAMACHINES_NET_JOIN"));
         Fill_Items;
      else
         To_Title;
         if Env ("ADAMACHINES_OPTIONS") /= "" then
            Open_Options;
            Fill_Items;
         end if;
      end if;
      Id := Area.Add_Tick_Callback (Tick'Access);
      pragma Unreferenced (Id);
      Gtk.Main.Main;
      Audio.Stop;
   end Run;

end App;
