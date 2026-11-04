--  Adamachines: tiny machines racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics.Discrete_Random;
with Ada.Streams; use Ada.Streams;
with Ada.Unchecked_Conversion;
with GNAT.Sockets; use GNAT.Sockets;
with Interfaces; use Interfaces;
with Geom; use Geom;

package body Net is

   use type Race.Phase_Kind;
   use type Tracks.Material;

   Version : constant := 2;

   --  Every game hosted has a number of its own, so a game that answers on two
   --  addresses (its own network's and this machine's) is listed once
   package Random_Ids is new Ada.Numerics.Discrete_Random (Unsigned_32);
   Ids : Random_Ids.Generator;
   Ids_Ready : Boolean := False;
   Game_Id : Unsigned_32 := 0;
   Racing : Natural := 0;   --  as the host: how many players are in the race on now
   Found_Ids : array (1 .. Max_Found) of Unsigned_32 := (others => 0);   --  of the games found

   type Message is (M_Look, M_Here, M_Ask, M_Welcome, M_Refuse, M_Lobby, M_Keys, M_State, M_Bye);

   Socket : Socket_Type := No_Socket;
   Quiet : Request_Type := (Non_Blocking_IO, True);   --  receiving never waits
   My_Role : Role_Kind := Off;
   function Role return Role_Kind is (My_Role);

   ---------------------------------------------------------------------------
   --  Packing: little-endian, whatever the machine
   ---------------------------------------------------------------------------

   subtype Packet is Stream_Element_Array (1 .. 1400);

   type Writer is record
      Data : Packet := (others => 0);
      Last : Stream_Element_Offset := 0;
   end record;

   type Reader is record
      Data : Packet := (others => 0);
      Last : Stream_Element_Offset := 0;
      Pos  : Stream_Element_Offset := 1;
   end record;

   Short : exception;   --  a packet that ends too soon

   procedure Put_U8 (W : in out Writer; V : Unsigned_8) is
   begin
      W.Last := W.Last + 1;
      W.Data (W.Last) := Stream_Element (V);
   end Put_U8;

   procedure Put_U16 (W : in out Writer; V : Unsigned_16) is
   begin
      Put_U8 (W, Unsigned_8 (V and 16#FF#));
      Put_U8 (W, Unsigned_8 (Shift_Right (V, 8)));
   end Put_U16;

   procedure Put_U32 (W : in out Writer; V : Unsigned_32) is
   begin
      Put_U16 (W, Unsigned_16 (V and 16#FFFF#));
      Put_U16 (W, Unsigned_16 (Shift_Right (V, 16)));
   end Put_U32;

   function To_Bits is new Ada.Unchecked_Conversion (Float, Unsigned_32);
   function To_Float is new Ada.Unchecked_Conversion (Unsigned_32, Float);

   procedure Put_F (W : in out Writer; V : Float) is
   begin
      Put_U32 (W, To_Bits (V));
   end Put_F;

   procedure Put_I32 (W : in out Writer; V : Integer) is
   begin
      Put_U32 (W, (if V >= 0 then Unsigned_32 (V) else not Unsigned_32 (-V - 1)));
   end Put_I32;

   procedure Put_Name (W : in out Writer; N : Race.Name_String) is
   begin
      for C of N loop
         Put_U8 (W, Character'Pos (C));
      end loop;
   end Put_Name;

   procedure Put_Header (W : in out Writer; M : Message) is
   begin
      W.Last := 0;
      Put_U8 (W, Character'Pos ('A'));
      Put_U8 (W, Character'Pos ('M'));
      Put_U8 (W, Version);
      Put_U8 (W, Message'Pos (M));
   end Put_Header;

   function Get_U8 (R : in out Reader) return Unsigned_8 is
   begin
      if R.Pos > R.Last then
         raise Short;
      end if;
      R.Pos := R.Pos + 1;
      return Unsigned_8 (R.Data (R.Pos - 1));
   end Get_U8;

   function Get_U16 (R : in out Reader) return Unsigned_16 is
      Lo : constant Unsigned_8 := Get_U8 (R);
      Hi : constant Unsigned_8 := Get_U8 (R);
   begin
      return Unsigned_16 (Lo) or Shift_Left (Unsigned_16 (Hi), 8);
   end Get_U16;

   function Get_U32 (R : in out Reader) return Unsigned_32 is
      Lo : constant Unsigned_16 := Get_U16 (R);
      Hi : constant Unsigned_16 := Get_U16 (R);
   begin
      return Unsigned_32 (Lo) or Shift_Left (Unsigned_32 (Hi), 16);
   end Get_U32;

   function Get_F (R : in out Reader) return Float is
      V : constant Float := To_Float (Get_U32 (R));
   begin
      return (if V'Valid then V else 0.0);
   end Get_F;

   function Get_I32 (R : in out Reader) return Integer is
      U : constant Unsigned_32 := Get_U32 (R);
   begin
      return (if U < 16#8000_0000# then Integer (U) else -Integer (not U) - 1);
   end Get_I32;

   function Get_Name (R : in out Reader) return Race.Name_String is
      N : Race.Name_String;
   begin
      for C of N loop
         declare
            B : constant Unsigned_8 := Get_U8 (R);
         begin
            C := (if B in 32 .. 126 then Character'Val (B) else ' ');
         end;
      end loop;
      return N;
   end Get_Name;

   --  A little float into one byte, 0 .. Top
   function Byte (V, Top : Float) return Unsigned_8 is
     (Unsigned_8 (Clamp (V / Top, 0.0, 1.0) * 255.0));
   function Unbyte (B : Unsigned_8; Top : Float) return Float is (Float (B) / 255.0 * Top);

   ---------------------------------------------------------------------------
   --  Sending
   ---------------------------------------------------------------------------

   procedure Send (W : Writer; To : Sock_Addr_Type) is
      Last : Stream_Element_Offset;
      pragma Warnings (Off, Last);
   begin
      Send_Socket (Socket, W.Data (1 .. W.Last), Last, To);
   exception
      when others => null;   --  a lost packet is nothing new to UDP
   end Send;

   function Address_Of (Text : String) return Sock_Addr_Type is
      Host_Part : Natural := Text'Last;
      Port_Num : Port_Type := Port;
      Addr : Inet_Addr_Type;
   begin
      for I in Text'Range loop
         if Text (I) = ':' then
            Host_Part := I - 1;
            Port_Num := Port_Type'Value (Text (I + 1 .. Text'Last));
         end if;
      end loop;
      declare
         H : constant String := Text (Text'First .. Host_Part);
      begin
         begin
            Addr := Inet_Addr (H);
         exception
            when others =>
               Addr := Addresses (Get_Host_By_Name (H), 1);
         end;
      end;
      return (Family_Inet, Addr, Port_Num);
   end Address_Of;

   ---------------------------------------------------------------------------
   --  The host's side
   ---------------------------------------------------------------------------

   type Peer is record
      Active    : Boolean := False;
      Addr      : Sock_Addr_Type;
      Heard     : Float := 0.0;      --  seconds since it was last heard
      Keys      : Cars.Controls;
      Fires     : Unsigned_16 := 0;  --  the fire key presses it has counted
      Fire_Now  : Boolean := False;  --  a press not yet used
      Lost      : Boolean := False;
   end record;
   Peers : array (Race.Car_Index) of Peer;   --  by player number; 1 is the host
   Lobby_T : Float := 0.0;
   Tick : Unsigned_32 := 0;

   function Host (Name : Race.Name_String) return Boolean is
   begin
      Stop;
      if not Ids_Ready then
         Random_Ids.Reset (Ids);
         Ids_Ready := True;
      end if;
      Game_Id := Random_Ids.Random (Ids);
      Create_Socket (Socket, Family_Inet, Socket_Datagram);
      --  not shared: a second game hosted on this machine is told the port is taken
      Bind_Socket (Socket, (Family_Inet, Any_Inet_Addr, Port));
      Control_Socket (Socket, Quiet);
      My_Role := Hosting;
      Lobby.Players := 1;
      Lobby.Names := (others => "      ");
      Lobby.Names (1) := Name;
      Lobby.In_Race := False;
      Peers := (others => <>);
      return True;
   exception
      when others =>
         if Socket /= No_Socket then
            Close_Socket (Socket);
            Socket := No_Socket;
         end if;
         My_Role := Off;
         return False;
   end Host;

   procedure Write_Lobby (W : in out Writer) is
   begin
      Put_Header (W, M_Lobby);
      Put_U8 (W, Unsigned_8 (Lobby.Track));
      Put_U8 (W, Unsigned_8 (Lobby.Laps));
      Put_U8 (W, Race.Difficulty'Pos (Lobby.Level));
      Put_U8 (W, (if Lobby.Items then 1 else 0));
      Put_U8 (W, Unsigned_8 (Lobby.AIs));
      Put_U8 (W, Unsigned_8 (Lobby.Players));
      Put_U8 (W, (if Lobby.In_Race then 1 else 0));
      Put_U16 (W, Unsigned_16 (Lobby.Serial mod 65536));
      for K in 1 .. Lobby.Players loop
         Put_Name (W, Lobby.Names (K));
      end loop;
   end Write_Lobby;

   procedure Tell_Everyone is
      W : Writer;
   begin
      Write_Lobby (W);
      for K in 2 .. Lobby.Players loop
         if Peers (K).Active then
            Send (W, Peers (K).Addr);
         end if;
      end loop;
      Lobby_T := 0.0;
   end Tell_Everyone;

   procedure Changed is
   begin
      if My_Role = Hosting then
         Tell_Everyone;
      end if;
   end Changed;

   procedure Welcome (K : Positive) is
      W : Writer;
   begin
      Put_Header (W, M_Welcome);
      Put_U8 (W, Unsigned_8 (K));
      Send (W, Peers (K).Addr);
   end Welcome;

   --  In the lobby a player who leaves leaves no gap: those after move up
   procedure Remove (K : Positive) is
   begin
      for J in K .. Lobby.Players - 1 loop
         Peers (J) := Peers (J + 1);
         Lobby.Names (J) := Lobby.Names (J + 1);
         if Peers (J).Active then
            Welcome (J);
         end if;
      end loop;
      Peers (Lobby.Players) := (others => <>);
      Lobby.Names (Lobby.Players) := "      ";
      Lobby.Players := Lobby.Players - 1;
      Tell_Everyone;
   end Remove;

   procedure Host_Start is
   begin
      Racing := Lobby.Players;
      Lobby.In_Race := True;
      Lobby.Serial := Lobby.Serial + 1;
      for K in 2 .. Lobby.Players loop
         Peers (K).Fire_Now := False;
         Peers (K).Keys := (others => 0.0);
      end loop;
      Tell_Everyone;
   end Host_Start;

   procedure Host_Lobby is
   begin
      Lobby.In_Race := False;
      Racing := 0;
      --  those who left during the race are gone for good now
      for K in reverse 2 .. Lobby.Players loop
         if Peers (K).Lost then
            Remove (K);
         end if;
      end loop;
      Tell_Everyone;
   end Host_Lobby;

   procedure Host_Inputs (I : in out Race.Input) is
      use Race;
   begin
      for K in 2 .. Lobby.Players loop
         declare
            P : Peer renames Peers (K);
         begin
            I.Keys (K) := P.Keys;
            I.Fires (K) := P.Fire_Now;
            P.Fire_Now := False;
            if P.Lost then
               for C in 1 .. State.Count loop
                  if State.Racers (C).Human = K then
                     State.Racers (C).Lost := True;
                  end if;
               end loop;
            end if;
         end;
      end loop;
   end Host_Inputs;

   ---------------------------------------------------------------------------
   --  The race, packed
   ---------------------------------------------------------------------------

   Max_Events_Sent : constant := 12;

   procedure Write_State (W : in out Writer) is
      use Race;
   begin
      Tick := Tick + 1;
      Put_Header (W, M_State);
      Put_U32 (W, Tick);
      Put_U8 (W, Phase_Kind'Pos (State.Phase));
      Put_F (W, State.Count_T);
      Put_F (W, State.Time);
      Put_F (W, State.Clock);
      Put_F (W, State.Over_T);
      Put_U8 (W, Unsigned_8 (State.Count));
      for K in 1 .. State.Count loop
         declare
            R : Racer renames State.Racers (K);
            C : Cars.Car renames R.Car;
            Flags : Unsigned_8 := 0;
         begin
            if C.Air then Flags := Flags or 1; end if;
            if R.Finished then Flags := Flags or 2; end if;
            if R.Lost then Flags := Flags or 4; end if;
            if C.Held then Flags := Flags or 8; end if;
            Put_F (W, C.P.X);
            Put_F (W, C.P.Y);
            Put_F (W, C.V.X);
            Put_F (W, C.V.Y);
            Put_F (W, C.H);
            Put_F (W, C.Z);
            Put_F (W, C.Forward);
            Put_U8 (W, Unsigned_8 (Integer (Clamp (C.Steer_S, -1.0, 1.0) * 100.0) + 100));
            Put_U8 (W, Flags);
            Put_U8 (W, Byte (C.Fall_T, 1.0));
            Put_U8 (W, Byte (C.Ghost_T, 2.0));
            Put_U8 (W, Byte (C.Boost_T, 2.0));
            Put_U8 (W, Byte (C.Slick_T, 2.0));
            Put_U8 (W, Byte (C.Spin_T, 2.0));
            Put_U8 (W, Byte (C.Slip, 1.0));
            Put_U8 (W, Tracks.Material'Pos (C.Under));
            Put_U8 (W, Unsigned_8 (R.Lap));
            Put_I32 (W, R.Progress);
            Put_U8 (W, Unsigned_8 (R.Place));
            Put_F (W, R.Finish_T);
            Put_F (W, R.Best_Lap);
            Put_F (W, R.Last_Lap);
            Put_F (W, R.Lap_Start);
            Put_U8 (W, Weapon'Pos (R.Holding));
            Put_U8 (W, Byte (R.Shield_T, 8.0));
         end;
      end loop;
      --  the boxes, one bit each
      declare
         Bits : Unsigned_32 := 0;
      begin
         for K in 1 .. N_Boxes loop
            if Boxes (K).Active then
               Bits := Bits or Shift_Left (1, K - 1);
            end if;
         end loop;
         Put_U32 (W, Bits);
      end;
      --  the oil, and the rockets in flight
      declare
         N : Natural := 0;
      begin
         for S of Slicks loop
            if S.Life > 0.0 then
               N := N + 1;
            end if;
         end loop;
         Put_U8 (W, Unsigned_8 (N));
         for S of Slicks loop
            if S.Life > 0.0 then
               Put_F (W, S.P.X);
               Put_F (W, S.P.Y);
               Put_U8 (W, Byte (S.Life, 30.0));
            end if;
         end loop;
         N := 0;
         for M of Rockets loop
            if M.Life > 0.0 then
               N := N + 1;
            end if;
         end loop;
         Put_U8 (W, Unsigned_8 (N));
         for M of Rockets loop
            if M.Life > 0.0 then
               Put_F (W, M.P.X);
               Put_F (W, M.P.Y);
               Put_F (W, M.H);
            end if;
         end loop;
      end;
      --  the latest events, so that one lost packet loses no bang
      declare
         First : constant Natural :=
           (if Event_Serial > Max_Events_Sent then Event_Serial - Max_Events_Sent else 0);
      begin
         Put_U32 (W, Unsigned_32 (Event_Serial));
         Put_U8 (W, Unsigned_8 (Event_Serial - First));
         for S in First .. Event_Serial - 1 loop
            declare
               E : constant Event := Events (S mod Event_Ring);
            begin
               Put_U8 (W, Event_Kind'Pos (E.Kind));
               Put_U8 (W, Unsigned_8 (E.Car mod 256));
               Put_F (W, E.P.X);
               Put_F (W, E.P.Y);
               Put_F (W, E.Size);
            end;
         end loop;
      end;
   end Write_State;

   Last_Tick : Unsigned_32 := 0;
   Last_Event : Natural := Natural'Last;   --  of the host's: none seen yet

   procedure Read_State (R : in out Reader) is
      use Race;
      T : constant Unsigned_32 := Get_U32 (R);
   begin
      if T <= Last_Tick and then Last_Tick - T < 1_000_000 then
         return;   --  older than what we have
      end if;
      Last_Tick := T;
      State.Phase := Phase_Kind'Val (Integer (Get_U8 (R)) mod 4);
      State.Count_T := Get_F (R);
      State.Time := Get_F (R);
      State.Clock := Get_F (R);
      State.Over_T := Get_F (R);
      declare
         Count : constant Natural := Natural (Get_U8 (R));
      begin
         if Count /= State.Count then
            return;   --  not this race
         end if;
         for K in 1 .. Count loop
            declare
               Rc : Racer renames State.Racers (K);
               C : Cars.Car renames Rc.Car;
               Flags : Unsigned_8;
               New_P : Vec;
               New_H : Float;
            begin
               New_P.X := Get_F (R);
               New_P.Y := Get_F (R);
               C.V.X := Get_F (R);
               C.V.Y := Get_F (R);
               New_H := Get_F (R);
               --  the last place it was, to draw the way between
               C.Prev_P := C.P;
               C.Prev_H := C.H;
               C.P := New_P;
               C.H := New_H;
               C.Z := Get_F (R);
               C.Forward := Get_F (R);
               C.Speed := Length (C.V);
               C.Steer_S := (Float (Get_U8 (R)) - 100.0) / 100.0;
               Flags := Get_U8 (R);
               C.Air := (Flags and 1) /= 0;
               Rc.Finished := (Flags and 2) /= 0;
               Rc.Lost := (Flags and 4) /= 0;
               C.Held := (Flags and 8) /= 0;
               C.Fall_T := Unbyte (Get_U8 (R), 1.0);
               C.Ghost_T := Unbyte (Get_U8 (R), 2.0);
               C.Boost_T := Unbyte (Get_U8 (R), 2.0);
               C.Slick_T := Unbyte (Get_U8 (R), 2.0);
               C.Spin_T := Unbyte (Get_U8 (R), 2.0);
               C.Slip := Unbyte (Get_U8 (R), 1.0);
               C.Under := Tracks.Material'Val (Integer (Get_U8 (R)) mod (Tracks.Material'Pos (Tracks.Material'Last) + 1));
               Rc.Lap := Natural (Get_U8 (R));
               Rc.Progress := Get_I32 (R);
               Rc.Place := Positive'Max (1, Natural (Get_U8 (R)));
               Rc.Finish_T := Get_F (R);
               Rc.Best_Lap := Get_F (R);
               Rc.Last_Lap := Get_F (R);
               Rc.Lap_Start := Get_F (R);
               Rc.Holding := Weapon'Val (Integer (Get_U8 (R)) mod (Weapon'Pos (Weapon'Last) + 1));
               Rc.Shield_T := Unbyte (Get_U8 (R), 8.0);
               if Cars.Falling (C) or else Distance (C.Prev_P, C.P) > 60.0 then
                  C.Prev_P := C.P;   --  put back on the road: no sliding there
                  C.Prev_H := C.H;
               end if;
            end;
         end loop;
      end;
      declare
         Bits : constant Unsigned_32 := Get_U32 (R);
      begin
         for K in 1 .. N_Boxes loop
            Boxes (K).Active := (Bits and Shift_Left (1, K - 1)) /= 0;
         end loop;
      end;
      declare
         N : constant Natural := Natural (Get_U8 (R));
      begin
         for S of Slicks loop
            S.Life := 0.0;
         end loop;
         for K in 1 .. Natural'Min (N, Slicks'Length) loop
            Slicks (K).P.X := Get_F (R);
            Slicks (K).P.Y := Get_F (R);
            Slicks (K).Life := Unbyte (Get_U8 (R), 30.0) + 0.01;
         end loop;
      end;
      declare
         N : constant Natural := Natural (Get_U8 (R));
      begin
         for M of Rockets loop
            M.Life := 0.0;
         end loop;
         for K in 1 .. Natural'Min (N, Rockets'Length) loop
            Rockets (K).P.X := Get_F (R);
            Rockets (K).P.Y := Get_F (R);
            Rockets (K).H := Get_F (R);
            Rockets (K).Life := 1.0;
         end loop;
      end;
      declare
         Serial : constant Natural := Natural (Get_U32 (R));
         N : constant Natural := Natural (Get_U8 (R));
      begin
         if Last_Event = Natural'Last or else Serial < Last_Event then
            Last_Event := Serial;   --  the first state of a race: what went before is old news
         end if;
         for K in 1 .. N loop
            declare
               S : constant Natural := Serial - N + K - 1;
               E : Event;
            begin
               E.Kind := Event_Kind'Val (Integer (Get_U8 (R)) mod (Event_Kind'Pos (Event_Kind'Last) + 1));
               E.Car := Natural (Get_U8 (R));
               E.P.X := Get_F (R);
               E.P.Y := Get_F (R);
               E.Size := Get_F (R);
               if S >= Last_Event then
                  Add_Event (E);
                  Last_Event := S + 1;
               end if;
            end;
         end loop;
      end;
      Since_State := 0.0;
   end Read_State;

   procedure Host_Send_State is
      W : Writer;
   begin
      if My_Role /= Hosting then
         return;
      end if;
      Write_State (W);
      for K in 2 .. Natural'Min (Racing, Lobby.Players) loop   --  not those waiting for the next race
         if Peers (K).Active and then not Peers (K).Lost then
            Send (W, Peers (K).Addr);
         end if;
      end loop;
   end Host_Send_State;

   ---------------------------------------------------------------------------
   --  The joining side
   ---------------------------------------------------------------------------

   Host_Addr : Sock_Addr_Type;
   State_Now : Join_State := Idle;
   My_Name : Race.Name_String := "      ";
   Ask_T, Look_T, Host_Heard : Float := 0.0;
   Begun, Back : Boolean := False;
   Fire_Count : Unsigned_16 := 0;
   Seen_Serial : Natural := 0;
   Was_In_Race : Boolean := False;
   First_Lobby : Boolean := True;   --  none heard yet since joining
   Waiting : Boolean := False;

   function Waiting_For_Next return Boolean is (Waiting);

   function Joining return Join_State is (State_Now);

   function Race_Begun return Boolean is
      B : constant Boolean := Begun;
   begin
      Begun := False;
      return B;
   end Race_Begun;

   function Back_In_Lobby return Boolean is
      B : constant Boolean := Back;
   begin
      Back := False;
      return B;
   end Back_In_Lobby;

   procedure Open_Client is
   begin
      if Socket = No_Socket then
         Create_Socket (Socket, Family_Inet, Socket_Datagram);
         Set_Socket_Option (Socket, Socket_Level, (Broadcast, True));
         Bind_Socket (Socket, (Family_Inet, Any_Inet_Addr, 0));
         Control_Socket (Socket, Quiet);
      end if;
   end Open_Client;

   procedure Browse is
   begin
      if My_Role = Hosting then
         Stop;
      end if;
      Open_Client;
      N_Found := 0;
      Look_T := 10.0;   --  look at once
   end Browse;

   procedure Ask is
      W : Writer;
   begin
      Put_Header (W, M_Ask);
      Put_Name (W, My_Name);
      Send (W, Host_Addr);
      Ask_T := 0.0;
   end Ask;

   procedure Join (Address : String; Name : Race.Name_String) is
   begin
      if My_Role = Hosting then
         Stop;
      end if;
      Open_Client;
      My_Name := Name;
      Refusal := Null_Unbounded_String;
      begin
         Host_Addr := Address_Of (Address);
      exception
         when others =>
            State_Now := Refused;
            Refusal := To_Unbounded_String ("NO SUCH ADDRESS: " & Address);
            return;
      end;
      State_Now := Asking;
      Host_Heard := 0.0;
      Me := 0;
      Last_Tick := 0;
      Seen_Serial := 0;
      Was_In_Race := False;
      First_Lobby := True;
      Waiting := False;
      Ask;
   end Join;

   procedure Send_Keys (C : Cars.Controls; Fire : Boolean) is
      W : Writer;
   begin
      if My_Role /= Joined then
         return;
      end if;
      if Fire then
         Fire_Count := Fire_Count + 1;
      end if;
      Put_Header (W, M_Keys);
      Put_U8 (W, Unsigned_8 (Integer (Clamp (C.Steer, -1.0, 1.0) * 100.0) + 100));
      Put_U8 (W, Byte (C.Throttle, 1.0));
      Put_U8 (W, Byte (C.Brake, 1.0));
      Put_U16 (W, Fire_Count);
      Send (W, Host_Addr);
   end Send_Keys;

   function Local_Address return String is
      S : Socket_Type;
      A : Sock_Addr_Type;
   begin
      --  a datagram socket "connected" outward sends nothing, but knows its own address
      Create_Socket (S, Family_Inet, Socket_Datagram);
      Connect_Socket (S, (Family_Inet, Inet_Addr ("8.8.8.8"), 53));
      A := Get_Socket_Name (S);
      Close_Socket (S);
      return Image (A.Addr);
   exception
      when others =>
         return "this machine's address";
   end Local_Address;

   ---------------------------------------------------------------------------
   --  What comes in
   ---------------------------------------------------------------------------

   procedure Handle (R : in out Reader; From : Sock_Addr_Type) is
      M : Message;
   begin
      if Get_U8 (R) /= Character'Pos ('A') or else Get_U8 (R) /= Character'Pos ('M')
        or else Get_U8 (R) /= Version
      then
         return;
      end if;
      declare
         K : constant Natural := Natural (Get_U8 (R));
      begin
         if K > Message'Pos (Message'Last) then
            return;
         end if;
         M := Message'Val (K);
      end;

      if My_Role = Hosting then
         --  Which player sent it, if any
         declare
            Who : Natural := 0;
         begin
            for K in 2 .. Lobby.Players loop
               if Peers (K).Active and then Peers (K).Addr = From then
                  Who := K;
               end if;
            end loop;
            case M is
               when M_Look =>
                  declare
                     W : Writer;
                  begin
                     Put_Header (W, M_Here);
                     Put_U32 (W, Game_Id);
                     Put_Name (W, Lobby.Names (1));
                     Put_U8 (W, Unsigned_8 (Lobby.Track));
                     Put_U8 (W, Unsigned_8 (Lobby.Players));
                     Put_U8 (W, (if Lobby.In_Race then 1 else 0));
                     Send (W, From);
                  end;
               when M_Ask =>
                  declare
                     Name : constant Race.Name_String := Get_Name (R);
                     W : Writer;
                  begin
                     if Who > 0 then
                        Welcome (Who);   --  it asked again: our welcome was lost
                        Tell_Everyone;
                     elsif Lobby.Players >= Race.Max_Cars then
                        --  during a race a player joins the lobby, for the next one
                        Put_Header (W, M_Refuse);
                        Put_U8 (W, 2);
                        Send (W, From);
                     else
                        Lobby.Players := Lobby.Players + 1;
                        Peers (Lobby.Players) := (Active => True, Addr => From, others => <>);
                        Lobby.Names (Lobby.Players) := Name;
                        if Lobby.AIs + Lobby.Players > Race.Max_Cars then
                           Lobby.AIs := Race.Max_Cars - Lobby.Players;
                        end if;
                        Welcome (Lobby.Players);
                        Tell_Everyone;
                     end if;
                  end;
               when M_Keys =>
                  if Who > 0 then
                     declare
                        P : Peer renames Peers (Who);
                        Steer : constant Float := (Float (Get_U8 (R)) - 100.0) / 100.0;
                        Throttle : constant Float := Unbyte (Get_U8 (R), 1.0);
                        Brake : constant Float := Unbyte (Get_U8 (R), 1.0);
                        Fires : constant Unsigned_16 := Get_U16 (R);
                     begin
                        P.Keys := (Steer, Throttle, Brake);
                        if Fires /= P.Fires then
                           P.Fires := Fires;
                           P.Fire_Now := True;
                        end if;
                        P.Heard := 0.0;
                        P.Lost := False;
                     end;
                  end if;
               when M_Bye =>
                  if Who > 0 then
                     if Lobby.In_Race then
                        Peers (Who).Lost := True;
                     else
                        Remove (Who);
                     end if;
                  end if;
               when others => null;
            end case;
         end;

      elsif My_Role = Joined or else Socket /= No_Socket then
         case M is
            when M_Here =>
               declare
                  Id : constant Unsigned_32 := Get_U32 (R);
                  Name : constant Race.Name_String := Get_Name (R);
                  Track : constant Natural := Natural (Get_U8 (R));
                  Players : constant Natural := Natural (Get_U8 (R));
                  In_Race : constant Boolean := Get_U8 (R) = 1;
                  A : constant String := Image (From.Addr);
                  Slot : Natural := 0;
               begin
                  for K in 1 .. N_Found loop
                     if Found_Ids (K) = Id then
                        Slot := K;
                     end if;
                  end loop;
                  if Slot = 0 and then N_Found < Max_Found then
                     N_Found := N_Found + 1;
                     Slot := N_Found;
                     Found (Slot).Address := To_Unbounded_String (A);   --  the first address it answered on
                  end if;
                  if Slot > 0 then
                     Found_Ids (Slot) := Id;
                     Found (Slot) := (Found (Slot).Address, Name,
                                      (if Track in Tracks.Track_Id then Track else 1), Players, In_Race, 0.0);
                  end if;
               end;
            when M_Welcome =>
               if State_Now in Asking | In_Lobby and then From = Host_Addr then
                  Me := Natural (Get_U8 (R));
                  State_Now := In_Lobby;
                  My_Role := Joined;
                  Host_Heard := 0.0;
               end if;
            when M_Refuse =>
               if State_Now = Asking and then From = Host_Addr then
                  State_Now := Refused;
                  Refusal := To_Unbounded_String
                    ((if Get_U8 (R) = 1 then "A RACE IS ON THERE. TRY AGAIN SOON" else "THAT GAME IS FULL"));
               end if;
            when M_Lobby =>
               if My_Role = Joined and then From = Host_Addr then
                  Host_Heard := 0.0;
                  Lobby.Track := Tracks.Track_Id'Max (1, Tracks.Track_Id'Min (Tracks.Track_Count, Natural (Get_U8 (R))));
                  Lobby.Laps := Positive'Max (1, Natural (Get_U8 (R)));
                  Lobby.Level := Race.Difficulty'Val (Integer (Get_U8 (R)) mod 3);
                  Lobby.Items := Get_U8 (R) = 1;
                  Lobby.AIs := Natural (Get_U8 (R));
                  Lobby.Players := Natural'Min (Race.Max_Cars, Natural (Get_U8 (R)));
                  Lobby.In_Race := Get_U8 (R) = 1;
                  Lobby.Serial := Natural (Get_U16 (R));
                  for K in 1 .. Lobby.Players loop
                     Lobby.Names (K) := Get_Name (R);
                  end loop;
                  if First_Lobby then
                     First_Lobby := False;
                     if Lobby.In_Race then
                        --  a race already on: not ours, the next one is
                        Seen_Serial := Lobby.Serial;
                        Waiting := True;
                     end if;
                  end if;
                  if Lobby.In_Race and then Lobby.Serial /= Seen_Serial then
                     Seen_Serial := Lobby.Serial;
                     Begun := True;
                     Last_Tick := 0;
                     Last_Event := Natural'Last;
                  elsif not Lobby.In_Race and then Was_In_Race then
                     Back := not Waiting;   --  only those who raced come back to it
                     Waiting := False;
                  end if;
                  Was_In_Race := Lobby.In_Race;
               end if;
            when M_State =>
               if My_Role = Joined and then From = Host_Addr and then Lobby.In_Race and then not Waiting then
                  Host_Heard := 0.0;
                  Read_State (R);
               end if;
            when M_Bye =>
               if My_Role = Joined and then From = Host_Addr then
                  State_Now := Gone;
                  Refusal := To_Unbounded_String ("THE HOST HAS CLOSED THE GAME");
               end if;
            when others => null;
         end case;
      end if;
   exception
      when others => null;   --  a packet that makes no sense is dropped
   end Handle;

   procedure Poll (Dt : Float) is
   begin
      if Socket = No_Socket then
         return;
      end if;
      Since_State := Since_State + Dt;
      --  everything waiting
      for Count in 1 .. 200 loop
         declare
            R : Reader;
            From : Sock_Addr_Type;
         begin
            Receive_Socket (Socket, R.Data, R.Last, From);
            R.Pos := 1;
            Handle (R, From);
         exception
            when others => exit;   --  nothing more (or an error the network told us of)
         end;
      end loop;

      case My_Role is
         when Hosting =>
            Lobby_T := Lobby_T + Dt;
            if Lobby_T > 0.5 then
               Tell_Everyone;
            end if;
            for K in reverse 2 .. Lobby.Players loop
               declare
                  P : Peer renames Peers (K);
               begin
                  P.Heard := P.Heard + Dt;
                  if P.Heard > 4.0 then
                     if Lobby.In_Race then
                        P.Lost := True;
                     else
                        Remove (K);
                     end if;
                  end if;
               end;
            end loop;
         when Joined | Off =>
            --  looking for games
            if State_Now in Idle | Refused then
               Look_T := Look_T + Dt;
               if Look_T > 1.0 then
                  Look_T := 0.0;
                  declare
                     W : Writer;
                  begin
                     Put_Header (W, M_Look);
                     Send (W, (Family_Inet, Broadcast_Inet_Addr, Port));
                     Send (W, (Family_Inet, Inet_Addr ("127.0.0.1"), Port));   --  a game on this machine
                  end;
               end if;
               for K in reverse 1 .. N_Found loop
                  Found (K).Age := Found (K).Age + Dt;
                  if Found (K).Age > 3.5 then
                     Found (K .. N_Found - 1) := Found (K + 1 .. N_Found);
                     Found_Ids (K .. N_Found - 1) := Found_Ids (K + 1 .. N_Found);
                     N_Found := N_Found - 1;
                  end if;
               end loop;
            end if;
            if State_Now = Asking then
               Ask_T := Ask_T + Dt;
               Host_Heard := Host_Heard + Dt;
               if Ask_T > 0.5 then
                  Ask;
               end if;
               if Host_Heard > 5.0 then
                  State_Now := Refused;
                  Refusal := To_Unbounded_String ("NO ANSWER FROM THERE");
               end if;
            elsif State_Now = In_Lobby then
               Host_Heard := Host_Heard + Dt;
               if Host_Heard > 6.0 then
                  State_Now := Gone;
                  Refusal := To_Unbounded_String ("THE HOST HAS GONE");
               end if;
               if not Lobby.In_Race or else Waiting then
                  Send_Keys ((others => 0.0), False);   --  to say we are still here
               end if;
            end if;
      end case;
   end Poll;

   procedure Stop is
      W : Writer;
   begin
      if Socket /= No_Socket then
         Put_Header (W, M_Bye);
         if My_Role = Hosting then
            for K in 2 .. Lobby.Players loop
               if Peers (K).Active then
                  Send (W, Peers (K).Addr);
               end if;
            end loop;
         elsif My_Role = Joined then
            Send (W, Host_Addr);
         end if;
         Close_Socket (Socket);
         Socket := No_Socket;
      end if;
      My_Role := Off;
      State_Now := Idle;
      N_Found := 0;
      Me := 0;
   end Stop;

   procedure Self_Test_Pack (Ok : out Boolean) is
      use Race;
      W : Writer;
      R : Reader;
      Before : constant State_Type := State;
      Event_Before : constant Natural := Event_Serial;
   begin
      Write_State (W);
      R.Data := W.Data;
      R.Last := W.Last;
      R.Pos := 5;   --  past the header
      Last_Tick := 0;
      Last_Event := Natural'Last;
      Read_State (R);
      Ok := W.Last <= Packet'Last and then R.Pos = R.Last + 1 and then State.Count = Before.Count;
      for K in 1 .. State.Count loop
         if State.Racers (K).Car.P /= Before.Racers (K).Car.P
           or else State.Racers (K).Car.H /= Before.Racers (K).Car.H
           or else State.Racers (K).Progress /= Before.Racers (K).Progress
           or else State.Racers (K).Place /= Before.Racers (K).Place
           or else State.Racers (K).Finished /= Before.Racers (K).Finished
         then
            Ok := False;
         end if;
      end loop;
      Ok := Ok and then Event_Serial = Event_Before;   --  the events were old news, and not taken again
   end Self_Test_Pack;

end Net;
