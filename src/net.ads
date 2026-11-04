--  Adamachines: tiny machines racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Races over the network.  One player hosts: the race runs on the host's
--  machine, the others send it their keys and draw what it sends back, the
--  state of every car thirty times a second.  Games on the same network
--  are found by asking all of it; others are joined by their address.
--  All of it is UDP, on one port.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Cars;
with Race;
with Tracks;

package Net is

   Port : constant := 27272;

   type Role_Kind is (Off, Hosting, Joined);
   function Role return Role_Kind;

   --  What the host has chosen, as everyone in the game sees it
   type Lobby_Info is record
      Track   : Tracks.Track_Id := 14;
      Laps    : Positive := 3;
      Level   : Race.Difficulty := Race.Normal;
      Items   : Boolean := True;
      AIs     : Natural := 2;
      Players : Natural := 0;           --  the host is player 1
      Names   : Race.Name_List := (others => "      ");
      In_Race : Boolean := False;
      Serial  : Natural := 0;           --  races started so far
   end record;
   Lobby : Lobby_Info;

   ---------------------------------------------------------------------------
   --  Hosting
   ---------------------------------------------------------------------------

   function Host (Name : Race.Name_String) return Boolean;
   --  False when the port is taken (another game is hosted on this machine)

   procedure Changed;      --  the host changed something in the lobby: everyone is told now
   procedure Host_Start;   --  the race begins: everyone is told to set it up
   procedure Host_Lobby;   --  back to the lobby after a race

   procedure Host_Inputs (I : in out Race.Input);
   --  The keys of the players on the network, into I (the host's own are the caller's)
   procedure Host_Send_State;
   --  The race as it is now, to everyone

   function Local_Address return String;   --  this machine's address on its network

   ---------------------------------------------------------------------------
   --  Finding a game and joining it
   ---------------------------------------------------------------------------

   type Found_Game is record
      Address   : Unbounded_String;
      Host_Name : Race.Name_String := "      ";
      Track     : Tracks.Track_Id := 1;
      Players   : Natural := 0;
      In_Race   : Boolean := False;
      Age       : Float := 0.0;
   end record;
   Max_Found : constant := 8;
   Found : array (1 .. Max_Found) of Found_Game;
   N_Found : Natural := 0;

   procedure Browse;   --  look for games on this network
   procedure Join (Address : String; Name : Race.Name_String);   --  "host" or "host:port"

   type Join_State is (Idle, Asking, In_Lobby, Refused, Gone);
   function Joining return Join_State;
   Refusal : Unbounded_String;   --  why, when refused or gone
   Me : Natural := 0;            --  this player's number, given by the host

   function Race_Begun return Boolean;     --  a race was started (true once)
   function Back_In_Lobby return Boolean;  --  the host went back to the lobby (true once)

   procedure Send_Keys (C : Cars.Controls; Fire : Boolean);
   Since_State : Float := 0.0;   --  seconds since the last state came, to draw between

   ---------------------------------------------------------------------------

   procedure Poll (Dt : Float);
   --  Everything that has arrived, handled; called every frame
   procedure Stop;   --  leave the game, or close it

   --  For the checks: a race state packed and unpacked again, as it is sent
   procedure Self_Test_Pack (Ok : out Boolean);

end Net;
