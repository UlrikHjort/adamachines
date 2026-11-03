--  Adamachines: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
with Interfaces;
with Cairo; use Cairo;
with Cairo.Image_Surface;
with Cairo.Surface;
with Glib; use Glib;

package body Tracks is

   ---------------------------------------------------------------------------
   --  What the tracks are made of
   ---------------------------------------------------------------------------

   type Point is record
      X, Y, W : Float;
   end record;
   type Point_List is array (Positive range <>) of Point;
   type Point_List_Access is access constant Point_List;

   type Feature_Kind is (F_Ramp, F_Gap, F_Boost, F_Water, F_Sand, F_Hole, F_Solid);
   type Feature is record
      K    : Feature_Kind;
      Seg  : Positive;          --  between control points Seg and Seg + 1
      T    : Float := 0.5;      --  how far along that
      Lat  : Float := 0.0;      --  across the road: -1 left edge .. 1 right edge
      Size : Float := 30.0;
   end record;
   type Feature_List is array (Positive range <>) of Feature;
   type Feature_List_Access is access constant Feature_List;

   type Name_Access is access constant String;

   type Definition is record
      Name     : Name_Access;
      Theme    : Theme_Kind;
      Points   : Point_List_Access;
      Features : Feature_List_Access;
      Clutter  : Natural;       --  how many things are put round the track
      Seed_0   : Seed;
      Hazards  : Natural := 0;  --  how many things move across; 0: as many as the place has
      Walls    : Boolean := False;   --  off the road it is all thick going (a canyon of cloud)
   end record;

   Workbench_Name : aliased constant String := "WORKBENCH RUN";
   Workbench_Points : aliased constant Point_List :=
     ((700.0, 260.0, 120.0), (1150.0, 260.0, 115.0), (1450.0, 420.0, 110.0),
      (1550.0, 700.0, 105.0), (1800.0, 860.0, 110.0), (2100.0, 760.0, 115.0),
      (2250.0, 500.0, 115.0), (2450.0, 420.0, 115.0), (2650.0, 600.0, 115.0),
      (2600.0, 1000.0, 110.0), (2300.0, 1250.0, 110.0), (1800.0, 1300.0, 115.0),
      (1300.0, 1250.0, 115.0), (1000.0, 1050.0, 105.0), (800.0, 1150.0, 105.0),
      (550.0, 1250.0, 110.0), (300.0, 1100.0, 115.0), (220.0, 750.0, 120.0),
      (300.0, 400.0, 120.0));
   Workbench_Features : aliased constant Feature_List :=
     ((F_Boost, 1, 0.55, 0.0, 30.0),
      (F_Water, 3, 0.5, 0.45, 34.0),
      (F_Ramp, 11, 0.55, 0.0, 26.0),
      (F_Sand, 13, 0.5, -0.4, 36.0),
      (F_Boost, 17, 0.5, 0.0, 30.0));

   Garden_Name : aliased constant String := "GARDEN PATH";
   Garden_Points : aliased constant Point_List :=
     ((900.0, 250.0, 110.0), (1300.0, 450.0, 105.0), (1400.0, 800.0, 100.0),
      (1700.0, 950.0, 100.0), (2050.0, 800.0, 105.0), (2150.0, 450.0, 105.0),
      (2450.0, 300.0, 110.0), (2750.0, 450.0, 110.0), (2800.0, 900.0, 105.0),
      (2550.0, 1300.0, 105.0), (2100.0, 1450.0, 110.0), (1500.0, 1500.0, 110.0),
      (1000.0, 1400.0, 105.0), (800.0, 1100.0, 100.0), (550.0, 1000.0, 100.0),
      (300.0, 1150.0, 105.0), (200.0, 700.0, 110.0), (300.0, 300.0, 110.0));
   Garden_Features : aliased constant Feature_List :=
     ((F_Water, 2, 0.5, -0.35, 32.0),
      (F_Sand, 5, 0.5, 0.3, 40.0),
      (F_Boost, 9, 0.35, 0.0, 30.0),
      (F_Ramp, 11, 0.42, 0.0, 26.0),
      (F_Gap, 11, 0.56, 0.0, 46.0),
      (F_Water, 15, 0.6, 0.4, 30.0),
      (F_Boost, 17, 0.4, 0.0, 30.0));

   Ice_Name : aliased constant String := "FROZEN POND";
   Ice_Points : aliased constant Point_List :=
     ((1000.0, 250.0, 130.0), (1600.0, 350.0, 125.0), (2000.0, 650.0, 125.0),
      (2500.0, 600.0, 125.0), (2700.0, 950.0, 125.0), (2400.0, 1350.0, 130.0),
      (1800.0, 1450.0, 130.0), (1400.0, 1150.0, 120.0), (1100.0, 1450.0, 125.0),
      (600.0, 1450.0, 125.0), (300.0, 1100.0, 125.0), (250.0, 700.0, 130.0),
      (400.0, 350.0, 130.0));
   Ice_Features : aliased constant Feature_List :=
     ((F_Boost, 1, 0.4, 0.0, 30.0),
      (F_Hole, 2, 0.6, -0.5, 26.0),
      (F_Sand, 4, 0.5, 0.45, 34.0),
      (F_Ramp, 6, 0.45, 0.0, 26.0),
      (F_Gap, 6, 0.6, 0.0, 44.0),
      (F_Hole, 9, 0.5, 0.45, 24.0),
      (F_Sand, 10, 0.5, -0.4, 34.0),
      (F_Boost, 12, 0.3, 0.0, 30.0));

   Sandpit_Name : aliased constant String := "SANDPIT RALLY";
   Sandpit_Points : aliased constant Point_List :=
     ((800.0, 250.0, 105.0), (1050.0, 500.0, 95.0), (900.0, 800.0, 95.0),
      (1150.0, 1050.0, 100.0), (1550.0, 950.0, 100.0), (1700.0, 600.0, 100.0),
      (1650.0, 300.0, 100.0), (2000.0, 200.0, 105.0), (2400.0, 350.0, 105.0),
      (2500.0, 800.0, 100.0), (2250.0, 1100.0, 100.0), (2300.0, 1400.0, 105.0),
      (1800.0, 1550.0, 105.0), (1200.0, 1500.0, 105.0), (700.0, 1450.0, 100.0),
      (400.0, 1200.0, 100.0), (250.0, 800.0, 105.0), (300.0, 300.0, 105.0));
   Sandpit_Features : aliased constant Feature_List :=
     ((F_Sand, 2, 0.5, 0.0, 44.0),
      (F_Sand, 4, 0.5, -0.35, 38.0),
      (F_Boost, 7, 0.5, 0.0, 30.0),
      (F_Water, 9, 0.5, 0.35, 34.0),
      (F_Sand, 11, 0.5, 0.3, 40.0),
      (F_Ramp, 13, 0.45, 0.0, 26.0),
      (F_Gap, 13, 0.58, 0.0, 44.0),
      (F_Sand, 15, 0.5, -0.3, 40.0),
      (F_Boost, 17, 0.45, 0.0, 30.0));

   Bath_Name : aliased constant String := "BUBBLE BATH";
   Bath_Points : aliased constant Point_List :=
     ((800.0, 250.0, 135.0), (1400.0, 260.0, 135.0), (1900.0, 350.0, 130.0),
      (2200.0, 650.0, 130.0), (2050.0, 950.0, 130.0), (1600.0, 1000.0, 130.0),
      (1300.0, 800.0, 125.0), (950.0, 850.0, 125.0), (700.0, 1150.0, 130.0),
      (350.0, 1100.0, 135.0), (250.0, 700.0, 135.0), (400.0, 350.0, 135.0));
   Bath_Features : aliased constant Feature_List :=
     ((F_Boost, 1, 0.5, 0.0, 30.0),
      (F_Sand, 3, 0.5, 0.35, 40.0),
      (F_Ramp, 6, 0.5, 0.0, 26.0),
      (F_Water, 8, 0.5, -0.3, 36.0),
      (F_Hole, 10, 0.5, -0.62, 26.0),
      (F_Boost, 11, 0.6, 0.0, 30.0));

   Plug_Name : aliased constant String := "PLUGHOLE PANIC";
   Plug_Points : aliased constant Point_List :=
     ((700.0, 250.0, 125.0), (1200.0, 300.0, 120.0), (1350.0, 600.0, 115.0),
      (1150.0, 850.0, 115.0), (1350.0, 1100.0, 120.0), (1800.0, 1150.0, 120.0),
      (2100.0, 900.0, 120.0), (1950.0, 600.0, 115.0), (2150.0, 300.0, 120.0),
      (2500.0, 350.0, 125.0), (2600.0, 800.0, 120.0), (2450.0, 1300.0, 125.0),
      (1800.0, 1450.0, 125.0), (1000.0, 1400.0, 125.0), (500.0, 1300.0, 125.0),
      (250.0, 900.0, 125.0), (300.0, 400.0, 125.0));
   Plug_Features : aliased constant Feature_List :=
     ((F_Boost, 1, 0.45, 0.0, 30.0),
      (F_Hole, 3, 0.5, 0.62, 26.0),
      (F_Sand, 5, 0.5, -0.3, 38.0),
      (F_Hole, 8, 0.5, -0.62, 26.0),
      (F_Water, 11, 0.5, 0.3, 36.0),
      (F_Ramp, 12, 0.5, 0.0, 26.0),
      (F_Boost, 14, 0.5, 0.0, 30.0));

   Bedroom_Name : aliased constant String := "BEDROOM FLYER";
   Bedroom_Points : aliased constant Point_List :=
     ((900.0, 250.0, 150.0), (1600.0, 250.0, 150.0), (2200.0, 450.0, 145.0),
      (2400.0, 900.0, 145.0), (2100.0, 1300.0, 145.0), (1600.0, 1250.0, 140.0),
      (1300.0, 900.0, 140.0), (1000.0, 1200.0, 140.0), (600.0, 1350.0, 145.0),
      (250.0, 1000.0, 145.0), (300.0, 500.0, 150.0));
   Bedroom_Features : aliased constant Feature_List :=
     ((F_Boost, 1, 0.5, 0.0, 30.0),
      (F_Sand, 4, 0.5, 0.3, 46.0),
      (F_Water, 7, 0.5, 0.0, 46.0),
      (F_Boost, 10, 0.5, 0.0, 30.0));

   Sky_Name : aliased constant String := "CLOUD NINE";
   Sky_Points : aliased constant Point_List :=
     ((800.0, 300.0, 150.0), (1500.0, 200.0, 150.0), (2000.0, 500.0, 145.0),
      (1750.0, 850.0, 140.0), (2100.0, 1150.0, 145.0), (2550.0, 1100.0, 145.0),
      (2850.0, 800.0, 145.0), (3200.0, 950.0, 145.0), (3150.0, 1400.0, 150.0),
      (2700.0, 1600.0, 150.0), (1800.0, 1600.0, 150.0), (1000.0, 1450.0, 145.0),
      (500.0, 1100.0, 145.0), (300.0, 600.0, 150.0));
   Sky_Features : aliased constant Feature_List :=
     ((F_Boost, 1, 0.5, 0.0, 30.0),
      (F_Sand, 3, 0.5, -0.3, 50.0),
      (F_Water, 5, 0.5, 0.0, 50.0),
      (F_Boost, 7, 0.5, 0.0, 30.0),
      (F_Sand, 10, 0.5, 0.35, 50.0),
      (F_Boost, 11, 0.5, 0.0, 30.0),
      (F_Water, 13, 0.5, 0.0, 50.0));

   Kitchen_Name : aliased constant String := "KITCHEN GP";
   Kitchen_Points : aliased constant Point_List :=
     ((700.0, 250.0, 110.0), (1300.0, 230.0, 110.0), (1800.0, 300.0, 105.0),
      (2100.0, 550.0, 100.0), (1900.0, 800.0, 100.0), (2150.0, 1050.0, 100.0),
      (2600.0, 1000.0, 105.0), (2800.0, 700.0, 105.0), (3050.0, 950.0, 105.0),
      (2900.0, 1350.0, 110.0), (2400.0, 1550.0, 110.0), (1800.0, 1450.0, 110.0),
      (1300.0, 1550.0, 105.0), (800.0, 1450.0, 105.0), (500.0, 1150.0, 100.0),
      (750.0, 850.0, 100.0), (450.0, 600.0, 105.0), (300.0, 350.0, 110.0));
   Kitchen_Features : aliased constant Feature_List :=
     ((F_Boost, 1, 0.5, 0.0, 30.0),
      (F_Water, 6, 0.5, 0.4, 32.0),
      (F_Sand, 12, 0.5, -0.35, 36.0),
      (F_Boost, 13, 0.5, 0.0, 30.0),
      (F_Water, 16, 0.5, -0.35, 30.0));

   Mud_Name : aliased constant String := "BACKYARD MOTOCROSS";
   Mud_Points : aliased constant Point_List :=
     ((700.0, 250.0, 105.0), (1200.0, 300.0, 100.0), (1400.0, 600.0, 95.0),
      (1200.0, 900.0, 95.0), (1500.0, 1150.0, 100.0), (2000.0, 1100.0, 100.0),
      (2200.0, 750.0, 95.0), (2050.0, 400.0, 95.0), (2400.0, 250.0, 100.0),
      (2700.0, 500.0, 100.0), (2650.0, 1000.0, 100.0), (2400.0, 1400.0, 105.0),
      (1800.0, 1550.0, 105.0), (1100.0, 1500.0, 100.0), (600.0, 1350.0, 100.0),
      (300.0, 1000.0, 100.0), (350.0, 550.0, 100.0));
   Mud_Features : aliased constant Feature_List :=
     ((F_Ramp, 1, 0.35, 0.0, 16.0),
      (F_Ramp, 1, 0.7, 0.0, 16.0),
      (F_Sand, 3, 0.5, 0.3, 38.0),
      (F_Ramp, 5, 0.5, 0.0, 16.0),
      (F_Water, 11, 0.5, -0.3, 30.0),
      (F_Ramp, 13, 0.25, 0.0, 14.0),
      (F_Ramp, 13, 0.33, 0.0, 14.0),
      (F_Ramp, 13, 0.41, 0.0, 14.0),
      (F_Ramp, 13, 0.75, 0.0, 16.0),
      (F_Boost, 14, 0.5, 0.0, 30.0),
      (F_Ramp, 15, 0.5, 0.0, 16.0),
      (F_Sand, 16, 0.5, -0.3, 38.0));

   Pool_Name : aliased constant String := "POOL SHARK";
   Pool_Points : aliased constant Point_List :=
     ((700.0, 250.0, 110.0), (1300.0, 250.0, 105.0), (1750.0, 350.0, 100.0),
      (1850.0, 650.0, 95.0), (1550.0, 850.0, 95.0), (1250.0, 700.0, 95.0),
      (950.0, 850.0, 95.0), (1100.0, 1150.0, 100.0), (1700.0, 1250.0, 100.0),
      (2200.0, 1100.0, 100.0), (2350.0, 700.0, 100.0), (2400.0, 350.0, 105.0),
      (2700.0, 250.0, 105.0), (2900.0, 600.0, 100.0), (2800.0, 1200.0, 105.0),
      (2300.0, 1500.0, 105.0), (1300.0, 1550.0, 105.0), (600.0, 1400.0, 100.0),
      (300.0, 1000.0, 100.0), (350.0, 500.0, 105.0));
   Pool_Features : aliased constant Feature_List :=
     ((F_Boost, 1, 0.5, 0.0, 30.0),
      (F_Water, 8, 0.5, 0.35, 30.0),
      (F_Boost, 16, 0.5, 0.0, 30.0),
      (F_Sand, 18, 0.5, -0.3, 34.0));

   Desk_Name : aliased constant String := "DESK DERBY";
   Desk_Points : aliased constant Point_List :=
     ((800.0, 250.0, 130.0), (1600.0, 250.0, 130.0), (2200.0, 400.0, 125.0),
      (2400.0, 800.0, 125.0), (2100.0, 1150.0, 125.0), (1500.0, 1100.0, 120.0),
      (1100.0, 1300.0, 120.0), (600.0, 1250.0, 125.0), (300.0, 900.0, 125.0),
      (400.0, 450.0, 130.0));
   Desk_Features : aliased constant Feature_List :=
     ((F_Ramp, 1, 0.6, 0.0, 26.0),
      (F_Water, 3, 0.5, 0.35, 34.0),
      (F_Sand, 6, 0.5, -0.3, 40.0),
      (F_Boost, 8, 0.5, 0.0, 30.0));

   Beach_Name : aliased constant String := "BEACH BLAST";
   Beach_Points : aliased constant Point_List :=
     ((700.0, 300.0, 140.0), (1300.0, 200.0, 140.0), (1900.0, 300.0, 135.0),
      (2300.0, 600.0, 135.0), (2200.0, 1000.0, 135.0), (2600.0, 1300.0, 135.0),
      (2300.0, 1650.0, 140.0), (1600.0, 1600.0, 140.0), (1100.0, 1300.0, 135.0),
      (600.0, 1500.0, 135.0), (250.0, 1150.0, 135.0), (300.0, 650.0, 140.0));
   Beach_Features : aliased constant Feature_List :=
     ((F_Water, 2, 0.5, 0.0, 60.0),
      (F_Boost, 3, 0.4, 0.0, 30.0),
      (F_Ramp, 7, 0.5, 0.0, 26.0),
      (F_Water, 9, 0.5, 0.0, 60.0),
      (F_Sand, 11, 0.5, 0.35, 40.0));

   Town_Name : aliased constant String := "TOY TRAIN TOWN";
   Town_Points : aliased constant Point_List :=
     ((600.0, 250.0, 110.0), (1400.0, 220.0, 110.0), (2200.0, 300.0, 105.0),
      (2700.0, 500.0, 105.0), (2750.0, 950.0, 105.0), (2400.0, 1250.0, 100.0),
      (1900.0, 1100.0, 100.0), (1380.0, 1230.0, 100.0), (1900.0, 1480.0, 105.0),
      (1100.0, 1650.0, 105.0), (600.0, 1450.0, 105.0), (300.0, 1050.0, 105.0),
      (400.0, 650.0, 110.0));
   Town_Features : aliased constant Feature_List :=
     ((F_Boost, 1, 0.3, 0.0, 30.0),
      (F_Water, 5, 0.5, 0.35, 30.0),
      (F_Boost, 10, 0.5, 0.0, 30.0));

   Leap_Name : aliased constant String := "WORKBENCH LEAP";
   Leap_Points : aliased constant Point_List :=
     ((600.0, 250.0, 115.0), (1300.0, 250.0, 115.0), (1900.0, 300.0, 110.0), (2300.0, 600.0, 110.0),
      (2200.0, 1000.0, 110.0), (1600.0, 1100.0, 110.0), (1000.0, 1050.0, 110.0), (500.0, 950.0, 115.0),
      (250.0, 600.0, 115.0));
   Leap_Features : aliased constant Feature_List :=
     ((F_Ramp, 1, 0.42, 0.0, 26.0),
      (F_Gap, 1, 0.58, 0.0, 44.0),
      (F_Boost, 3, 0.5, 0.0, 30.0),
      (F_Ramp, 5, 0.35, 0.0, 26.0),
      (F_Gap, 5, 0.52, 0.0, 44.0),
      (F_Water, 7, 0.5, 0.4, 30.0));

   Hockey_Name : aliased constant String := "HOCKEY RINK";
   Hockey_Points : aliased constant Point_List :=
     ((700.0, 300.0, 120.0), (1500.0, 300.0, 120.0), (1900.0, 500.0, 115.0), (1900.0, 850.0, 115.0),
      (1500.0, 1050.0, 120.0), (700.0, 1050.0, 120.0), (300.0, 850.0, 115.0), (300.0, 500.0, 115.0));
   Hockey_Features : aliased constant Feature_List :=
     ((F_Boost, 1, 0.5, 0.0, 30.0),
      (F_Boost, 5, 0.5, 0.0, 30.0));

   Slalom_Name : aliased constant String := "DUCK SLALOM";
   Slalom_Points : aliased constant Point_List :=
     ((700.0, 300.0, 150.0), (1500.0, 300.0, 150.0), (2100.0, 450.0, 145.0), (2300.0, 850.0, 145.0),
      (2000.0, 1250.0, 145.0), (1300.0, 1300.0, 150.0), (700.0, 1250.0, 150.0), (350.0, 900.0, 145.0),
      (350.0, 500.0, 145.0));
   Slalom_Features : aliased constant Feature_List :=
     ((F_Solid, 1, 0.3, 0.45, 20.0),
      (F_Solid, 1, 0.55, -0.45, 20.0),
      (F_Solid, 1, 0.8, 0.45, 20.0),
      (F_Boost, 3, 0.5, 0.0, 30.0),
      (F_Solid, 5, 0.3, -0.45, 20.0),
      (F_Solid, 5, 0.6, 0.45, 20.0),
      (F_Solid, 6, 0.5, -0.45, 20.0),
      (F_Hole, 8, 0.5, 0.62, 24.0));

   Canyon_Name : aliased constant String := "CLOUD CANYON";
   Canyon_Points : aliased constant Point_List :=
     ((700.0, 300.0, 110.0), (1200.0, 250.0, 105.0), (1500.0, 500.0, 100.0), (1300.0, 800.0, 100.0),
      (1600.0, 1050.0, 100.0), (2100.0, 1000.0, 100.0), (2300.0, 700.0, 100.0), (2200.0, 400.0, 105.0),
      (2600.0, 250.0, 105.0), (2900.0, 500.0, 100.0), (2800.0, 1000.0, 100.0), (2400.0, 1350.0, 105.0),
      (1700.0, 1450.0, 105.0), (1000.0, 1400.0, 105.0), (500.0, 1250.0, 100.0), (250.0, 850.0, 105.0),
      (350.0, 450.0, 110.0));
   Canyon_Features : aliased constant Feature_List :=
     ((F_Boost, 1, 0.5, 0.0, 30.0),
      (F_Boost, 12, 0.5, 0.0, 30.0),
      (F_Water, 13, 0.5, 0.0, 45.0));

   Fish_Name : aliased constant String := "FISH TANK";
   Fish_Points : aliased constant Point_List :=
     ((700.0, 300.0, 130.0), (1400.0, 250.0, 130.0), (2000.0, 400.0, 125.0), (2200.0, 800.0, 125.0),
      (1800.0, 1100.0, 120.0), (1300.0, 950.0, 120.0), (900.0, 1200.0, 125.0), (450.0, 1050.0, 125.0),
      (300.0, 650.0, 130.0));
   Fish_Features : aliased constant Feature_List :=
     ((F_Boost, 1, 0.5, 0.0, 30.0),
      (F_Water, 4, 0.5, 0.0, 45.0),
      (F_Sand, 7, 0.5, 0.3, 38.0),
      (F_Boost, 8, 0.5, 0.0, 30.0));

   Attic_Name : aliased constant String := "ATTIC AT NIGHT";
   Attic_Points : aliased constant Point_List :=
     ((600.0, 250.0, 115.0), (1300.0, 230.0, 115.0), (2000.0, 300.0, 110.0), (2500.0, 500.0, 110.0),
      (2600.0, 900.0, 110.0), (2300.0, 1250.0, 110.0), (1800.0, 1350.0, 110.0), (1500.0, 1100.0, 105.0),
      (1200.0, 1300.0, 105.0), (800.0, 1400.0, 110.0), (400.0, 1150.0, 110.0), (300.0, 700.0, 115.0));
   Attic_Features : aliased constant Feature_List :=
     ((F_Boost, 1, 0.5, 0.0, 30.0),
      (F_Ramp, 2, 0.5, 0.0, 26.0),
      (F_Sand, 4, 0.5, 0.35, 36.0),
      (F_Water, 9, 0.5, -0.3, 30.0));

   Party_Name : aliased constant String := "BIRTHDAY PARTY";
   Party_Points : aliased constant Point_List :=
     ((700.0, 300.0, 115.0), (1400.0, 250.0, 115.0), (2000.0, 350.0, 110.0), (2400.0, 700.0, 110.0),
      (2300.0, 1150.0, 110.0), (1800.0, 1400.0, 115.0), (1100.0, 1400.0, 115.0), (600.0, 1200.0, 110.0),
      (400.0, 800.0, 110.0));
   Party_Features : aliased constant Feature_List :=
     ((F_Water, 2, 0.5, 0.35, 32.0),
      (F_Sand, 5, 0.5, -0.3, 36.0),
      (F_Boost, 6, 0.5, 0.0, 30.0),
      (F_Solid, 7, 0.5, 0.45, 18.0));

   Garage_Name : aliased constant String := "GARAGE MONSTERS";
   Garage_Points : aliased constant Point_List :=
     ((700.0, 300.0, 130.0), (1400.0, 250.0, 130.0), (2000.0, 350.0, 125.0), (2400.0, 700.0, 125.0),
      (2300.0, 1100.0, 125.0), (1900.0, 1250.0, 125.0), (1500.0, 1000.0, 125.0), (1100.0, 1250.0, 125.0),
      (600.0, 1250.0, 130.0), (300.0, 900.0, 125.0), (350.0, 500.0, 130.0));
   Garage_Features : aliased constant Feature_List :=
     ((F_Water, 1, 0.5, 0.35, 36.0),
      (F_Boost, 2, 0.5, 0.0, 30.0),
      (F_Water, 6, 0.5, -0.35, 34.0),
      (F_Ramp, 8, 0.5, 0.0, 26.0));

   Xmas_Name : aliased constant String := "CHRISTMAS TREE";
   Xmas_Points : aliased constant Point_List :=
     ((700.0, 250.0, 115.0), (1500.0, 250.0, 115.0), (2100.0, 350.0, 110.0), (2400.0, 750.0, 110.0),
      (2200.0, 1150.0, 110.0), (1500.0, 1300.0, 115.0), (800.0, 1250.0, 115.0), (400.0, 900.0, 110.0),
      (400.0, 500.0, 110.0));
   Xmas_Features : aliased constant Feature_List :=
     ((F_Boost, 1, 0.5, 0.0, 30.0),
      (F_Solid, 2, 0.5, -0.45, 18.0),
      (F_Sand, 4, 0.5, 0.3, 36.0),
      (F_Water, 6, 0.5, -0.3, 30.0));

   Moon_Name : aliased constant String := "MOON BASE";
   Moon_Points : aliased constant Point_List :=
     ((700.0, 300.0, 130.0), (1400.0, 250.0, 130.0), (2000.0, 400.0, 125.0), (2300.0, 800.0, 125.0),
      (2000.0, 1200.0, 125.0), (1400.0, 1150.0, 125.0), (1100.0, 1450.0, 130.0), (500.0, 1400.0, 130.0),
      (250.0, 1000.0, 125.0), (350.0, 600.0, 130.0));
   Moon_Features : aliased constant Feature_List :=
     ((F_Ramp, 1, 0.5, 0.0, 26.0),
      (F_Sand, 3, 0.5, 0.3, 40.0),
      (F_Ramp, 5, 0.5, 0.0, 26.0),
      (F_Ramp, 7, 0.5, 0.0, 26.0),
      (F_Boost, 8, 0.5, 0.0, 30.0));

   Halloween_Name : aliased constant String := "HALLOWEEN NIGHT";
   Halloween_Points : aliased constant Point_List :=
     ((700.0, 300.0, 145.0), (1400.0, 250.0, 145.0), (2000.0, 450.0, 140.0), (2100.0, 850.0, 140.0),
      (1700.0, 1100.0, 135.0), (1200.0, 950.0, 135.0), (800.0, 1150.0, 140.0), (400.0, 1000.0, 140.0),
      (300.0, 600.0, 145.0));
   Halloween_Features : aliased constant Feature_List :=
     ((F_Boost, 1, 0.5, 0.0, 30.0),
      (F_Sand, 3, 0.5, -0.3, 50.0),
      (F_Solid, 5, 0.5, 0.45, 20.0),
      (F_Water, 6, 0.5, 0.0, 46.0),
      (F_Boost, 8, 0.5, 0.0, 30.0));

   Easter_Name : aliased constant String := "EASTER EGG HUNT";
   Easter_Points : aliased constant Point_List :=
     ((700.0, 250.0, 110.0), (1300.0, 250.0, 110.0), (1800.0, 350.0, 105.0), (1900.0, 700.0, 105.0),
      (1600.0, 900.0, 105.0), (1900.0, 1150.0, 105.0), (2400.0, 1150.0, 110.0), (2600.0, 800.0, 110.0),
      (2500.0, 400.0, 110.0), (2900.0, 250.0, 110.0), (3100.0, 700.0, 110.0), (2900.0, 1350.0, 110.0),
      (2000.0, 1500.0, 110.0), (1200.0, 1450.0, 110.0), (600.0, 1300.0, 110.0), (300.0, 900.0, 110.0),
      (350.0, 500.0, 110.0));
   Easter_Features : aliased constant Feature_List :=
     ((F_Boost, 1, 0.5, 0.0, 30.0),
      (F_Solid, 2, 0.5, 0.45, 16.0),
      (F_Sand, 6, 0.5, -0.3, 36.0),
      (F_Ramp, 13, 0.4, 0.0, 26.0),
      (F_Solid, 14, 0.5, -0.45, 16.0),
      (F_Water, 15, 0.5, 0.35, 30.0),
      (F_Boost, 16, 0.5, 0.0, 30.0));

   Chess_Name : aliased constant String := "CHESS BOARD";
   Chess_Points : aliased constant Point_List :=
     ((600.0, 300.0, 120.0), (1400.0, 250.0, 120.0), (2200.0, 300.0, 115.0), (2700.0, 600.0, 115.0),
      (2700.0, 1100.0, 115.0), (2300.0, 1450.0, 115.0), (1700.0, 1450.0, 110.0), (1400.0, 1100.0, 110.0),
      (1100.0, 1450.0, 115.0), (600.0, 1450.0, 115.0), (300.0, 1000.0, 115.0), (300.0, 600.0, 120.0));
   Chess_Features : aliased constant Feature_List :=
     ((F_Boost, 1, 0.5, 0.0, 30.0),
      (F_Solid, 3, 0.5, 0.45, 15.0),
      (F_Water, 5, 0.5, -0.35, 30.0),
      (F_Solid, 9, 0.5, -0.45, 15.0),
      (F_Ramp, 10, 0.5, 0.0, 26.0),
      (F_Boost, 12, 0.5, 0.0, 30.0));

   Alien_Name : aliased constant String := "ALIEN PLANET";
   Alien_Points : aliased constant Point_List :=
     ((700.0, 300.0, 135.0), (1400.0, 250.0, 135.0), (2000.0, 400.0, 130.0), (2200.0, 800.0, 130.0),
      (1900.0, 1150.0, 125.0), (1300.0, 1050.0, 125.0), (900.0, 1300.0, 130.0), (500.0, 1200.0, 130.0),
      (300.0, 800.0, 130.0), (350.0, 450.0, 135.0));
   Alien_Features : aliased constant Feature_List :=
     ((F_Boost, 1, 0.5, 0.0, 30.0),
      (F_Water, 3, 0.5, 0.3, 40.0),
      (F_Sand, 6, 0.5, -0.3, 40.0),
      (F_Ramp, 8, 0.5, 0.0, 26.0),
      (F_Solid, 9, 0.5, 0.45, 16.0));

   Arctic_Name : aliased constant String := "ARCTIC SAFARI";
   Arctic_Points : aliased constant Point_List :=
     ((700.0, 300.0, 125.0), (1400.0, 250.0, 125.0), (2100.0, 350.0, 120.0), (2500.0, 700.0, 120.0),
      (2300.0, 1100.0, 120.0), (1800.0, 1200.0, 115.0), (1500.0, 950.0, 115.0), (1100.0, 1150.0, 120.0),
      (700.0, 1250.0, 120.0), (350.0, 950.0, 120.0), (350.0, 550.0, 125.0));
   Arctic_Features : aliased constant Feature_List :=
     ((F_Boost, 1, 0.5, 0.0, 30.0),
      (F_Water, 3, 0.5, 0.0, 55.0),
      (F_Hole, 6, 0.5, 0.62, 22.0),
      (F_Sand, 8, 0.5, -0.3, 38.0),
      (F_Ramp, 9, 0.5, 0.0, 26.0),
      (F_Solid, 10, 0.5, 0.45, 16.0));

   Defs : constant array (1 .. First_Custom - 1) of Definition :=
     ((Workbench_Name'Access, Workbench, Workbench_Points'Access, Workbench_Features'Access, 70, 11, others => <>),
      (Garden_Name'Access, Garden, Garden_Points'Access, Garden_Features'Access, 90, 23, others => <>),
      (Ice_Name'Access, Ice, Ice_Points'Access, Ice_Features'Access, 70, 37, others => <>),
      (Sandpit_Name'Access, Garden, Sandpit_Points'Access, Sandpit_Features'Access, 90, 41, others => <>),
      (Bath_Name'Access, Bath, Bath_Points'Access, Bath_Features'Access, 60, 53, others => <>),
      (Plug_Name'Access, Bath, Plug_Points'Access, Plug_Features'Access, 70, 59, others => <>),
      (Bedroom_Name'Access, Bedroom, Bedroom_Points'Access, Bedroom_Features'Access, 90, 61, others => <>),
      (Sky_Name'Access, Sky, Sky_Points'Access, Sky_Features'Access, 90, 67, others => <>),
      (Kitchen_Name'Access, Kitchen, Kitchen_Points'Access, Kitchen_Features'Access, 80, 71, others => <>),
      (Mud_Name'Access, Mud, Mud_Points'Access, Mud_Features'Access, 80, 73, others => <>),
      (Pool_Name'Access, Pool, Pool_Points'Access, Pool_Features'Access, 40, 79, others => <>),
      (Desk_Name'Access, Desk, Desk_Points'Access, Desk_Features'Access, 80, 83, others => <>),
      (Beach_Name'Access, Beach, Beach_Points'Access, Beach_Features'Access, 80, 89, others => <>),
      (Town_Name'Access, Toy_Town, Town_Points'Access, Town_Features'Access, 70, 97, others => <>),
      (Leap_Name'Access, Workbench, Leap_Points'Access, Leap_Features'Access, 60, 101, others => <>),
      (Hockey_Name'Access, Ice, Hockey_Points'Access, Hockey_Features'Access, 40, 103, Hazards => 3, others => <>),
      (Slalom_Name'Access, Bath, Slalom_Points'Access, Slalom_Features'Access, 50, 107, others => <>),
      (Canyon_Name'Access, Sky, Canyon_Points'Access, Canyon_Features'Access, 160, 109, Walls => True, others => <>),
      (Fish_Name'Access, Fish_Tank, Fish_Points'Access, Fish_Features'Access, 60, 113, others => <>),
      (Attic_Name'Access, Attic, Attic_Points'Access, Attic_Features'Access, 60, 127, others => <>),
      (Party_Name'Access, Party, Party_Points'Access, Party_Features'Access, 70, 131, others => <>),
      (Garage_Name'Access, Garage, Garage_Points'Access, Garage_Features'Access, 80, 137, others => <>),
      (Xmas_Name'Access, Xmas, Xmas_Points'Access, Xmas_Features'Access, 60, 139, others => <>),
      (Moon_Name'Access, Moon, Moon_Points'Access, Moon_Features'Access, 70, 149, others => <>),
      (Halloween_Name'Access, Halloween, Halloween_Points'Access, Halloween_Features'Access, 70, 151, others => <>),
      (Easter_Name'Access, Easter, Easter_Points'Access, Easter_Features'Access, 90, 157, others => <>),
      (Chess_Name'Access, Chess, Chess_Points'Access, Chess_Features'Access, 50, 163, others => <>),
      (Alien_Name'Access, Alien, Alien_Points'Access, Alien_Features'Access, 80, 167, others => <>),
      (Arctic_Name'Access, Arctic, Arctic_Points'Access, Arctic_Features'Access, 80, 173, others => <>));

   function Name (Id : Track_Id) return String is
     (if Is_Custom (Id) then "MY TRACK" & Integer'Image (Slot_Of (Id)) else Defs (Id).Name.all);
   function Theme_Of (Id : Track_Id) return Theme_Kind is
     (if Is_Custom (Id) then Slots (Slot_Of (Id)).Theme else Defs (Id).Theme);

   procedure Copy_Track (Id : Track_Id) is
   begin
      if Is_Custom (Id) then
         return;
      end if;
      Custom_Count := Natural'Min (Max_Custom, Defs (Id).Points'Length);
      for K in 1 .. Custom_Count loop
         declare
            P : constant Point := Defs (Id).Points (Defs (Id).Points'First + K - 1);
         begin
            Custom_Points (K) := (P.X, P.Y, P.W);
         end;
      end loop;
      Custom_Theme := Defs (Id).Theme;
   end Copy_Track;

   procedure Default_Custom is
      Loop_Points : constant array (1 .. 8) of Control_Point :=
        ((800.0, 300.0, 120.0), (1500.0, 280.0, 120.0), (2100.0, 400.0, 115.0), (2300.0, 800.0, 115.0),
         (2000.0, 1150.0, 115.0), (1300.0, 1200.0, 115.0), (600.0, 1100.0, 115.0), (400.0, 650.0, 120.0));
   begin
      Custom_Count := Loop_Points'Length;
      for K in Loop_Points'Range loop
         Custom_Points (K) := Loop_Points (K);
      end loop;
   end Default_Custom;

   No_Features : aliased constant Feature_List := (1 .. 0 => (F_Boost, 1, 0.5, 0.0, 30.0));
   Custom_Name : aliased constant String := "MY TRACK";

   ---------------------------------------------------------------------------
   --  The track loaded
   ---------------------------------------------------------------------------

   Max_Samples : constant := 4000;
   Samples : array (0 .. Max_Samples - 1) of Sample;
   N_Samples : Positive := 1;
   Lap_Len : Float := 1.0;
   Seg_Start : array (1 .. 64) of Natural := (others => 0);

   Max_Items : constant := 400;
   Items : array (1 .. Max_Items) of Item;
   N_Items : Natural := 0;

   Max_Movers : constant := 6;
   Movers : array (1 .. Max_Movers) of Mover;
   N_Movers : Natural := 0;

   Loaded : Track_Id := 1;
   World_W, World_H : Float := 1000.0;
   Table_X0, Table_Y0, Table_X1, Table_Y1 : Float := 0.0;

   Cell : constant Float := 2.0;
   type Material_Array is array (Natural range <>) of Material;
   type Material_Access is access Material_Array;
   Map : Material_Access;
   Walled : Boolean := False;   --  the track loaded is a canyon
   Map_W, Map_H : Natural := 0;

   function Current return Track_Id is (Loaded);
   function Walls return Boolean is (Walled);
   function Theme return Theme_Kind is (Theme_Of (Loaded));
   function Vehicle return Vehicle_Kind is (Vehicle_Of (Theme_Of (Loaded)));
   function Width return Float is (World_W);
   function Height return Float is (World_H);
   function Count return Positive is (N_Samples);
   function Lap_Length return Float is (Lap_Len);
   function Item_Count return Natural is (N_Items);
   function Mover_Count return Natural is (N_Movers);
   function Get_Mover (I : Positive) return Mover is (Movers (I));

   procedure Mover_At (M : Mover; T : Float; P : out Vec; Heading : out Float;
                       Visible : out Boolean; Lift : out Float)
   is
      U : constant Float := (T + M.Phase) / M.Period - Float'Floor ((T + M.Phase) / M.Period);
      Way : constant Vec := M.B - M.A;
   begin
      Visible := True;
      Lift := 0.0;
      case M.Kind is
         when Circle_Train =>
            declare
               An : constant Float := 2.0 * Pi * U;
            begin
               P := M.A + Dir (An) * M.B.X;
               Heading := An + Pi / 2.0;
            end;
         when Marble | Puck | Drifting_Duck | Tennis_Ball | Pool_Ball | Robot | Crab | Train
            | Fish | Mouse | RC_Car | Rolling_Bauble | Blob | Ghost | Penguin | Polar_Bear =>
            --  there and back, easing at the ends
            declare
               F : constant Float := 0.5 - 0.5 * Cos (2.0 * Pi * U);
            begin
               P := M.A + Way * F;
               Heading := Angle_Of (Way) + (if U > 0.5 then Pi else 0.0);
               if M.Kind = Ghost then
                  Lift := 26.0 + 4.0 * Sin (T * 3.0 + M.Phase);
               end if;
            end;
         when Frog | Chicken | Bouncy_Ball | Astronaut | Bunny | Knight_Hop =>
            --  in hops, there and back
            declare
               Back : constant Boolean := U > 0.5;
               V : constant Float := (if Back then 2.0 - 2.0 * U else 2.0 * U);
               Hops : constant Float := 7.0;
               K : constant Float := Float'Floor (V * Hops);
               Within : constant Float := V * Hops - K;
               Move : constant Float := Float'Min (1.0, Within * 2.5);
            begin
               P := M.A + Way * ((K + Move) / Hops);
               Lift := (if Within < 0.4 then Sin (Pi * Within / 0.4)
                          * (case M.Kind is
                                when Frog => 10.0,
                                when Bouncy_Ball => 18.0,
                                when Astronaut => 14.0,
                                when Bunny => 12.0,
                                when Knight_Hop => 20.0,
                                when others => 4.0)
                        else 0.0);
               Heading := Angle_Of (Way) + (if Back then Pi else 0.0);
            end;
         when Paper_Plane | Bird | Bat =>
            --  one way across, then away for a while
            declare
               Across : constant Float := (if M.Kind = Train then 0.45 else 0.6);
            begin
               if U < Across then
                  P := M.A + Way * (U / Across);
                  Heading := Angle_Of (Way);
               else
                  P := M.A;
                  Heading := 0.0;
                  Visible := False;
               end if;
               if M.Kind /= Train then
                  Lift := 30.0;
               end if;
            end;
      end case;
   end Mover_At;
   function Get_Item (I : Positive) return Item is (Items (I));
   function Has_Table return Boolean is (Theme_Of (Loaded) = Workbench);
   function Table_Left return Float is (Table_X0);
   function Table_Top return Float is (Table_Y0);
   function Table_Right return Float is (Table_X1);
   function Table_Bottom return Float is (Table_Y1);

   function Get (I : Integer) return Sample is (Samples (I mod N_Samples));

   function Material_At (P : Vec) return Material is
      IX : constant Integer := Integer (Float'Floor (P.X / Cell));
      IY : constant Integer := Integer (Float'Floor (P.Y / Cell));
   begin
      if Map = null or else IX < 0 or else IY < 0 or else IX >= Map_W or else IY >= Map_H then
         return (if Has_Table then Void else Solid);
      end if;
      return Map (IY * Map_W + IX);
   end Material_At;

   function Nearest (P : Vec; Hint : Integer := -1) return Natural is
      Best : Natural := 0;
      Best_D : Float := Float'Last;
      procedure Try (I : Integer) is
         J : constant Natural := I mod N_Samples;
         D : constant Vec := Samples (J).P - P;
         D2 : constant Float := D.X * D.X + D.Y * D.Y;
      begin
         if D2 < Best_D then
            Best_D := D2;
            Best := J;
         end if;
      end Try;
   begin
      if Hint < 0 then
         for I in 0 .. N_Samples - 1 loop
            Try (I);
         end loop;
      else
         for I in Hint - 40 .. Hint + 40 loop
            Try (I);
         end loop;
      end if;
      return Best;
   end Nearest;

   procedure Grid_Slot (K : Positive; P : out Vec; Heading : out Float) is
      Row : constant Natural := (K - 1) / 2;
      Col : constant Natural := (K - 1) mod 2;
      S : constant Sample := Get (-(4 + Row * 6 + Col * 3));
   begin
      P := S.P + Perp (S.T) * ((if Col = 0 then -0.22 else 0.22) * S.Width);
      Heading := Angle_Of (S.T);
   end Grid_Slot;

   function Inside (S : Shape; P : Vec; Margin : Float := 0.0) return Boolean is
      D : constant Vec := P - S.C;
      U : constant Vec := Dir (S.A);
      LX : constant Float := Dot (D, U);
      LY : constant Float := Dot (D, Perp (U));
   begin
      case S.Kind is
         when Circle =>
            return Length (D) <= S.RX + Margin;
         when Box =>
            return abs LX <= S.RX + Margin and then abs LY <= S.RY + Margin;
         when Ellipse =>
            return (LX / (S.RX + Margin)) ** 2 + (LY / (S.RY + Margin)) ** 2 <= 1.0;
      end case;
   end Inside;

   function Extent (S : Shape) return Float is
     (case S.Kind is
         when Circle => S.RX,
         when Box | Ellipse => Float'Max (S.RX, S.RY));

   ---------------------------------------------------------------------------
   --  Building it
   ---------------------------------------------------------------------------

   procedure Make_Samples (Pts : Point_List) is
      N : constant Positive := Pts'Length;
      Max_Dense : constant := 40_000;
      Dense : array (0 .. Max_Dense - 1) of Point;
      Dense_Seg : array (1 .. N + 1) of Natural := (others => 0);
      ND : Natural := 0;
      function P (I : Integer) return Point is (Pts (Pts'First + (I mod N)));
   begin
      for I in 0 .. N - 1 loop
         declare
            P0 : constant Point := P (I - 1);
            P1 : constant Point := P (I);
            P2 : constant Point := P (I + 1);
            P3 : constant Point := P (I + 2);
            L : constant Float := Sqrt ((P2.X - P1.X) ** 2 + (P2.Y - P1.Y) ** 2);
            M : constant Positive := Positive'Max (4, Integer (L / 2.0));
         begin
            Dense_Seg (I + 1) := ND;
            for S in 0 .. M - 1 loop
               declare
                  T : constant Float := Float (S) / Float (M);
                  T2 : constant Float := T * T;
                  T3 : constant Float := T2 * T;
                  function F (A, B, C, D : Float) return Float is
                    (0.5 * (2.0 * B + (C - A) * T + (2.0 * A - 5.0 * B + 4.0 * C - D) * T2
                            + (3.0 * B - A - 3.0 * C + D) * T3));
               begin
                  Dense (ND) := (F (P0.X, P1.X, P2.X, P3.X), F (P0.Y, P1.Y, P2.Y, P3.Y),
                                 P1.W + (P2.W - P1.W) * (3.0 * T2 - 2.0 * T3));
                  ND := ND + 1;
               end;
            end loop;
         end;
      end loop;
      Dense_Seg (N + 1) := ND;

      --  Along it at an even spacing
      declare
         Arc : array (0 .. ND) of Float;
         Total : Float;
         Step : Float;
         J : Natural := 0;
      begin
         Arc (0) := 0.0;
         for I in 1 .. ND loop
            declare
               A : constant Point := Dense (I - 1);
               B : constant Point := Dense (I mod ND);
            begin
               Arc (I) := Arc (I - 1) + Sqrt ((B.X - A.X) ** 2 + (B.Y - A.Y) ** 2);
            end;
         end loop;
         Total := Arc (ND);
         N_Samples := Positive'Min (Max_Samples, Integer (Total / Spacing));
         Step := Total / Float (N_Samples);
         Lap_Len := Total;
         for K in 0 .. N_Samples - 1 loop
            declare
               S : constant Float := Float (K) * Step;
            begin
               while J < ND - 1 and then Arc (J + 1) < S loop
                  J := J + 1;
               end loop;
               declare
                  A : constant Point := Dense (J);
                  B : constant Point := Dense ((J + 1) mod ND);
                  F : constant Float := (if Arc (J + 1) > Arc (J) then (S - Arc (J)) / (Arc (J + 1) - Arc (J)) else 0.0);
               begin
                  Samples (K).P := (A.X + (B.X - A.X) * F, A.Y + (B.Y - A.Y) * F);
                  Samples (K).Width := A.W + (B.W - A.W) * F;
               end;
            end;
         end loop;
         for I in 1 .. N loop
            Seg_Start (I) := Natural (Arc (Dense_Seg (I)) / Step) mod N_Samples;
         end loop;
         Seg_Start (N + 1) := N_Samples;
      end;

      for K in 0 .. N_Samples - 1 loop
         Samples (K).T := Normal (Get (K + 1).P - Get (K - 1).P);
      end loop;
      for K in 0 .. N_Samples - 1 loop
         Samples (K).Turn :=
           Wrap (Angle_Of (Get (K + 1).T) - Angle_Of (Get (K - 1).T)) / (2.0 * Spacing);
      end loop;
   end Make_Samples;

   procedure Add (It : Item) is
   begin
      if N_Items < Max_Items then
         N_Items := N_Items + 1;
         Items (N_Items) := It;
      end if;
   end Add;

   function Sample_At (F : Feature) return Natural is
      A : constant Natural := Seg_Start (F.Seg);
      B : Natural := Seg_Start (F.Seg + 1);
   begin
      if B < A then
         B := B + N_Samples;
      end if;
      return Natural (Float (A) + F.T * Float (B - A)) mod N_Samples;
   end Sample_At;

   procedure Add_Features (Def : Definition) is
      R : Seed := Def.Seed_0 * 7 + 3;
   begin
      for F of Def.Features.all loop
         declare
            S : constant Sample := Get (Sample_At (F));
            A : constant Float := Angle_Of (S.T);
            C : constant Vec := S.P + Perp (S.T) * (F.Lat * S.Width * 0.5);
            Tone : constant Float := Random (R);
         begin
            case F.K is
               when F_Ramp =>
                  Add ((Ramp_Piece, (Box, S.P, A, F.Size * 0.5, S.Width * 0.5 + 4.0), Ramp, Tone));
               when F_Gap =>
                  Add ((Stream, (Box, S.P, A, F.Size * 0.5, S.Width * 0.5 + 140.0), Void, Tone));
               when F_Boost =>
                  Add ((Boost_Pad, (Box, C, A, 22.0, S.Width * 0.2), Boost, Tone));
               when F_Water =>
                  Add (((case Def.Theme is
                            when Workbench => Coffee_Spill,
                            when Bath => Soap_Film,
                            when Bedroom | Sky | Halloween => Gust,
                            when Kitchen => Milk_Spill,
                            when Desk => Ink_Blot,
                            when Beach => Tide_Pool,
                            when Pool => Coffee_Spill,
                            when Party => Juice_Spill,
                            when Garage => Oil_Stain,
                            when Chess => Coffee_Spill,
                            when Alien => Goo_Pool,
                            when Arctic => Ice_Patch,
                            when others => Puddle),
                        (Ellipse, C, A + Spread (R) * 0.6, F.Size, F.Size * 0.62), Water, Tone));
               when F_Sand =>
                  Add (((case Def.Theme is
                            when Workbench => Sawdust,
                            when Garden => Sand_Patch,
                            when Ice => Snow_Pile,
                            when Bath => Bubbles,
                            when Bedroom | Sky => Cloud,
                            when Kitchen => Flour,
                            when Mud => Mud_Patch,
                            when Pool => Sawdust,
                            when Desk => Shavings,
                            when Beach | Toy_Town => Sand_Patch,
                            when Fish_Tank => Seaweed,
                            when Attic => Dust_Pile,
                            when Party => Jelly,
                            when Garage => Sawdust,
                            when Xmas => Needles,
                            when Moon => Crater,
                            when Halloween => Fog,
                            when Easter => Nest,
                            when Chess => Sawdust,
                            when Alien => Spores,
                            when Arctic => Snow_Pile),
                        (Ellipse, C, A + Spread (R) * 0.6, F.Size, F.Size * 0.66), Sand, Tone));
               when F_Solid =>
                  Add (((case Def.Theme is
                            when Bath => Rubber_Duck,
                            when Party | Xmas => Present,
                            when Easter => Easter_Egg,
                            when Halloween => Pumpkin,
                            when Chess => Pawn,
                            when Alien => Egg_Pod,
                            when Arctic => Ice_Block,
                            when others => Stone),
                        (Circle, C, A, F.Size, 0.0), Solid, Tone));
               when F_Hole =>
                  Add (((case Def.Theme is
                            when Ice => Ice_Hole,
                            when Bath => Plughole,
                            when Arctic => Fish_Hole,
                            when others => Pond),
                        (Ellipse, C, A + Spread (R) * 0.8, F.Size, F.Size * 0.7), Void, Tone));
            end case;
         end;
      end loop;
   end Add_Features;

   --  The clutter round the track, put where it leaves the road clear
   procedure Add_Clutter (Def : Definition) is
      R : Seed := Def.Seed_0;
      Placed : Natural := 0;
      Tries : Natural := 0;

      type Choice is record
         Kind : Item_Kind;
         Weight : Float;
      end record;
      type Choice_List is array (Positive range <>) of Choice;
      Bench : constant Choice_List :=
        ((Screw, 3.0), (Nut, 2.5), (Pencil, 2.0), (Mug, 1.0), (Tape_Roll, 1.0),
         (Ruler, 1.0), (Battery, 1.5), (Coffee_Spill, 0.8), (Sawdust, 1.2));
      Yard : constant Choice_List :=
        ((Stone, 4.0), (Flower, 4.0), (Pot, 1.0), (Pond, 0.5), (Puddle, 0.8),
         (Leaf, 3.0), (Sand_Patch, 0.8));
      Tub : constant Choice_List :=
        ((Rubber_Duck, 3.0), (Soap, 2.0), (Sponge, 1.5), (Bubbles, 2.5), (Bottle, 1.0),
         (Plughole, 0.4), (Soap_Film, 0.6));
      Room : constant Choice_List :=
        ((Toy_Block, 4.0), (Book, 1.5), (Crayon, 3.0), (Balloon, 2.5));
      Air : constant Choice_List :=
        ((Cloud, 5.0), (Balloon, 2.0), (Hot_Air_Balloon, 0.8));
      Cook : constant Choice_List :=
        ((Fork, 1.5), (Spoon, 1.5), (Bottle_Cap, 3.0), (Salt_Shaker, 1.0), (Milk_Spill, 0.6),
         (Flour, 0.6), (Pea, 3.0));
      Yard_MX : constant Choice_List :=
        ((Hay_Bale, 2.0), (Tyre_Stack, 3.0), (Mud_Patch, 1.5), (Puddle, 1.0), (Stone, 1.5),
         (Plank, 1.0));
      Table_Top : constant Choice_List :=
        ((Snooker_Ball, 3.0), (Chalk_Cube, 1.0), (Cue, 0.4));
      School : constant Choice_List :=
        ((Eraser, 2.0), (Sharpener, 1.0), (Paper_Clip, 2.0), (Coin, 2.0), (Rubber_Band, 1.5),
         (Pencil, 1.5), (Ruler, 0.6), (Ink_Blot, 0.5), (Shavings, 0.6));
      Seaside : constant Choice_List :=
        ((Sandcastle, 1.5), (Bucket, 1.5), (Shell, 3.0), (Starfish, 2.0), (Towel, 0.8),
         (Beach_Ball, 1.0), (Tide_Pool, 1.0));
      Model : constant Choice_List :=
        ((Model_Tree, 4.0), (House, 1.5), (Bush, 2.5), (Pond, 0.3));
      Aquarium : constant Choice_List :=
        ((Castle, 0.6), (Chest, 0.6), (Seaweed, 4.0), (Air_Stone, 0.6), (Shell, 2.0), (Stone, 2.0));
      Loft : constant Choice_List :=
        ((Trunk, 1.5), (Rocking_Horse, 0.5), (Carton, 2.0), (Web, 2.0), (Dust_Pile, 1.0), (Moonbeam, 0.8));
      Birthday : constant Choice_List :=
        ((Cake, 0.4), (Present, 2.0), (Party_Hat, 2.0), (Cupcake, 2.0), (Juice_Spill, 0.6), (Jelly, 0.8),
         (Confetti, 3.0), (Balloon, 1.0));
      Workshop : constant Choice_List :=
        ((Toolbox, 0.8), (Paint_Tin, 2.0), (Spanner, 3.0), (Nut, 2.0), (Screw, 2.0), (Oil_Stain, 1.5),
         (Drain, 0.6), (Tyre_Stack, 1.5));
      Christmas : constant Choice_List :=
        ((Present, 3.0), (Bauble, 3.0), (Candy_Cane, 1.5), (Needles, 3.0));
      Lunar : constant Choice_List :=
        ((Crater, 3.0), (Moon_Rock, 3.0), (Lander, 0.4), (Flag, 0.8), (Dome, 0.6));
      Spooky : constant Choice_List :=
        ((Pumpkin, 3.0), (Gravestone, 2.0), (Cauldron, 0.5), (Candle, 1.5), (Web, 1.0), (Leaf, 3.0));
      Spring : constant Choice_List :=
        ((Easter_Egg, 3.0), (Choc_Bunny, 1.0), (Basket, 0.8), (Daffodil, 3.0), (Flower, 3.0), (Nest, 0.6));
      Board : constant Choice_List :=
        ((Pawn, 4.0), (Rook, 1.0), (Knight_Piece, 1.0), (Bishop, 1.0), (Queen, 0.5), (King, 0.5),
         (Chess_Clock, 0.3));
      Planet : constant Choice_List :=
        ((Crystal, 3.0), (Alien_Plant, 2.5), (Goo_Pool, 1.0), (Egg_Pod, 1.5), (Spire, 1.5), (Spores, 0.8));
      Polar : constant Choice_List :=
        ((Igloo, 1.0), (Ice_Block, 2.0), (Seal, 1.0), (Pine_Tree, 2.0), (Snow_Pile, 2.0), (Snowman, 0.6),
         (Fish_Hole, 0.6), (Ice_Patch, 1.0));
      Frost : constant Choice_List :=
        ((Snowman, 1.0), (Ice_Hole, 0.8), (Snow_Pile, 2.0), (Pine_Cone, 2.5), (Pine_Tree, 1.5),
         (Stone, 1.5));

      function Pick (L : Choice_List) return Item_Kind is
         Sum : Float := 0.0;
         X : Float;
      begin
         for C of L loop
            Sum := Sum + C.Weight;
         end loop;
         X := Random (R) * Sum;
         for C of L loop
            if X < C.Weight then
               return C.Kind;
            end if;
            X := X - C.Weight;
         end loop;
         return L (L'Last).Kind;
      end Pick;

      function Make (K : Item_Kind; C : Vec) return Item is
         A : constant Float := Random (R) * 2.0 * Pi;
         Z : constant Float := Random (R);   --  its size, 0 .. 1
         T : constant Float := Random (R);
      begin
         case K is
            when Screw => return (K, (Circle, C, A, 8.0 + 3.0 * Z, 0.0), (if Def.Theme = Garage then Bump else Solid), T);
            when Nut => return (K, (Circle, C, A, 11.0 + 4.0 * Z, 0.0), (if Def.Theme = Garage then Bump else Solid), T);
            when Pencil => return (K, (Box, C, A, 70.0 + 30.0 * Z, 6.0), Solid, T);
            when Mug => return (K, (Circle, C, A, 46.0 + 8.0 * Z, 0.0), Solid, T);
            when Tape_Roll => return (K, (Circle, C, A, 36.0 + 6.0 * Z, 0.0), Solid, T);
            when Ruler => return (K, (Box, C, A, 110.0 + 40.0 * Z, 14.0), Floor, T);
            when Battery => return (K, (Box, C, A, 26.0 + 6.0 * Z, 9.0), Solid, T);
            when Coffee_Spill => return (K, (Ellipse, C, A, 30.0 + 25.0 * Z, 20.0 + 12.0 * Z), Water, T);
            when Sawdust => return (K, (Ellipse, C, A, 30.0 + 25.0 * Z, 22.0 + 12.0 * Z), Sand, T);
            when Stone => return (K, (Circle, C, A, 12.0 + 18.0 * Z, 0.0), Solid, T);
            when Flower => return (K, (Circle, C, A, 9.0 + 6.0 * Z, 0.0), Floor, T);
            when Pot => return (K, (Circle, C, A, 34.0 + 10.0 * Z, 0.0), Solid, T);
            when Pond => return (K, (Ellipse, C, A, 70.0 + 50.0 * Z, 45.0 + 25.0 * Z), Void, T);
            when Puddle => return (K, (Ellipse, C, A, 26.0 + 20.0 * Z, 16.0 + 10.0 * Z), Water, T);
            when Sand_Patch => return (K, (Ellipse, C, A, 40.0 + 30.0 * Z, 26.0 + 16.0 * Z), Sand, T);
            when Leaf => return (K, (Ellipse, C, A, 12.0 + 6.0 * Z, 6.0 + 2.0 * Z), Floor, T);
            when Snowman => return (K, (Circle, C, A, 22.0 + 6.0 * Z, 0.0), Solid, T);
            when Ice_Hole => return (K, (Ellipse, C, A, 34.0 + 26.0 * Z, 22.0 + 14.0 * Z), Void, T);
            when Snow_Pile => return (K, (Ellipse, C, A, 30.0 + 26.0 * Z, 20.0 + 14.0 * Z), Sand, T);
            when Pine_Cone => return (K, (Ellipse, C, A, 10.0 + 3.0 * Z, 6.5 + 2.0 * Z), Solid, T);
            when Pine_Tree => return (K, (Circle, C, A, 40.0 + 16.0 * Z, 0.0), Solid, T);
            when Rubber_Duck => return (K, (Circle, C, A, 20.0 + 8.0 * Z, 0.0), Solid, T);
            when Soap => return (K, (Box, C, A, 24.0 + 6.0 * Z, 15.0 + 3.0 * Z), Solid, T);
            when Sponge => return (K, (Box, C, A, 32.0 + 8.0 * Z, 20.0 + 4.0 * Z), Solid, T);
            when Bubbles => return (K, (Ellipse, C, A, 34.0 + 30.0 * Z, 24.0 + 16.0 * Z), Sand, T);
            when Plughole => return (K, (Circle, C, A, 20.0 + 4.0 * Z, 0.0), Void, T);
            when Bottle => return (K, (Box, C, A, 34.0 + 8.0 * Z, 18.0 + 4.0 * Z), Solid, T);
            when Soap_Film => return (K, (Ellipse, C, A, 34.0 + 20.0 * Z, 22.0 + 10.0 * Z), Water, T);
            when Toy_Block => return (K, (Box, C, A, 13.0 + 6.0 * Z, 13.0 + 6.0 * Z), Floor, T);
            when Book => return (K, (Box, C, A, 50.0 + 20.0 * Z, 36.0 + 10.0 * Z), Floor, T);
            when Crayon => return (K, (Box, C, A, 26.0 + 6.0 * Z, 4.0), Floor, T);
            when Balloon => return (K, (Circle, C, A, 15.0 + 5.0 * Z, 0.0), Solid, T);
            when Cloud => return (K, (Ellipse, C, A, 70.0 + 80.0 * Z, 40.0 + 30.0 * Z), Floor, T);
            when Hot_Air_Balloon => return (K, (Circle, C, A, 36.0 + 8.0 * Z, 0.0), Solid, T);
            when Fork => return (K, (Box, C, A, 70.0 + 15.0 * Z, 7.0), Solid, T);
            when Spoon => return (K, (Box, C, A, 65.0 + 15.0 * Z, 8.0), Solid, T);
            when Bottle_Cap => return (K, (Circle, C, A, 13.0 + 3.0 * Z, 0.0), Solid, T);
            when Salt_Shaker => return (K, (Circle, C, A, 22.0 + 4.0 * Z, 0.0), Solid, T);
            when Milk_Spill => return (K, (Ellipse, C, A, 30.0 + 25.0 * Z, 20.0 + 12.0 * Z), Water, T);
            when Flour => return (K, (Ellipse, C, A, 30.0 + 25.0 * Z, 22.0 + 12.0 * Z), Sand, T);
            when Pea => return (K, (Circle, C, A, 5.0 + 2.0 * Z, 0.0), Solid, T);
            when Hay_Bale => return (K, (Box, C, A, 28.0 + 6.0 * Z, 16.0 + 3.0 * Z), Solid, T);
            when Tyre_Stack => return (K, (Circle, C, A, 14.0 + 4.0 * Z, 0.0), Solid, T);
            when Mud_Patch => return (K, (Ellipse, C, A, 36.0 + 26.0 * Z, 24.0 + 14.0 * Z), Sand, T);
            when Plank => return (K, (Box, C, A, 60.0 + 20.0 * Z, 9.0), Floor, T);
            when Pocket => return (K, (Circle, C, 0.0, 40.0, 0.0), Void, T);
            when Snooker_Ball => return (K, (Circle, C, A, 13.0, 0.0), Solid, T);
            when Chalk_Cube => return (K, (Box, C, A, 8.0, 8.0), Solid, T);
            when Cue => return (K, (Box, C, A, 260.0 + 40.0 * Z, 5.0), Solid, T);
            when Eraser => return (K, (Box, C, A, 22.0 + 6.0 * Z, 11.0 + 3.0 * Z), Solid, T);
            when Sharpener => return (K, (Box, C, A, 15.0 + 3.0 * Z, 10.0 + 2.0 * Z), Solid, T);
            when Paper_Clip => return (K, (Box, C, A, 22.0 + 6.0 * Z, 6.0), Floor, T);
            when Coin => return (K, (Circle, C, A, 13.0 + 5.0 * Z, 0.0), Solid, T);
            when Ink_Blot => return (K, (Ellipse, C, A, 30.0 + 22.0 * Z, 22.0 + 12.0 * Z), Water, T);
            when Shavings => return (K, (Ellipse, C, A, 30.0 + 20.0 * Z, 22.0 + 10.0 * Z), Sand, T);
            when Rubber_Band => return (K, (Circle, C, A, 16.0 + 6.0 * Z, 0.0), Floor, T);
            when Sandcastle => return (K, (Box, C, A, 30.0 + 8.0 * Z, 30.0 + 8.0 * Z), Solid, T);
            when Bucket => return (K, (Circle, C, A, 22.0 + 5.0 * Z, 0.0), Solid, T);
            when Shell => return (K, (Circle, C, A, 7.0 + 4.0 * Z, 0.0), Floor, T);
            when Starfish => return (K, (Circle, C, A, 11.0 + 5.0 * Z, 0.0), Floor, T);
            when Towel => return (K, (Box, C, A, 70.0 + 20.0 * Z, 36.0 + 6.0 * Z), Floor, T);
            when Beach_Ball => return (K, (Circle, C, A, 20.0 + 5.0 * Z, 0.0), Solid, T);
            when Tide_Pool => return (K, (Ellipse, C, A, 40.0 + 30.0 * Z, 26.0 + 16.0 * Z), Water, T);
            when Model_Tree => return (K, (Circle, C, A, 22.0 + 12.0 * Z, 0.0), Solid, T);
            when House => return (K, (Box, C, A, 34.0 + 10.0 * Z, 26.0 + 6.0 * Z), Solid, T);
            when Bush => return (K, (Circle, C, A, 12.0 + 6.0 * Z, 0.0), Solid, T);
            when Castle => return (K, (Box, C, A, 38.0 + 10.0 * Z, 38.0 + 10.0 * Z), Solid, T);
            when Chest => return (K, (Box, C, A, 30.0 + 6.0 * Z, 20.0 + 4.0 * Z), Solid, T);
            when Seaweed => return (K, (Ellipse, C, A, 34.0 + 20.0 * Z, 24.0 + 10.0 * Z), Sand, T);
            when Air_Stone => return (K, (Circle, C, A, 12.0 + 3.0 * Z, 0.0), Solid, T);
            when Trunk => return (K, (Box, C, A, 50.0 + 12.0 * Z, 30.0 + 6.0 * Z), Solid, T);
            when Rocking_Horse => return (K, (Box, C, A, 44.0 + 8.0 * Z, 18.0 + 4.0 * Z), Solid, T);
            when Carton => return (K, (Box, C, A, 34.0 + 14.0 * Z, 30.0 + 12.0 * Z), Solid, T);
            when Web => return (K, (Circle, C, A, 26.0 + 14.0 * Z, 0.0), Floor, T);
            when Dust_Pile => return (K, (Ellipse, C, A, 30.0 + 20.0 * Z, 22.0 + 12.0 * Z), Sand, T);
            when Moonbeam => return (K, (Box, C, 0.5, 70.0 + 30.0 * Z, 50.0 + 20.0 * Z), Floor, T);
            when Cake => return (K, (Circle, C, A, 60.0 + 15.0 * Z, 0.0), Solid, T);
            when Present => return (K, (Box, C, A, 18.0 + 8.0 * Z, 16.0 + 8.0 * Z), Solid, T);
            when Party_Hat => return (K, (Circle, C, A, 14.0 + 4.0 * Z, 0.0), Solid, T);
            when Cupcake => return (K, (Circle, C, A, 16.0 + 4.0 * Z, 0.0), Solid, T);
            when Juice_Spill => return (K, (Ellipse, C, A, 30.0 + 25.0 * Z, 20.0 + 12.0 * Z), Water, T);
            when Jelly => return (K, (Ellipse, C, A, 30.0 + 18.0 * Z, 24.0 + 10.0 * Z), Sand, T);
            when Confetti => return (K, (Circle, C, A, 22.0 + 12.0 * Z, 0.0), Floor, T);
            when Toolbox => return (K, (Box, C, A, 60.0 + 15.0 * Z, 28.0 + 6.0 * Z), Solid, T);
            when Paint_Tin => return (K, (Circle, C, A, 22.0 + 6.0 * Z, 0.0), Solid, T);
            when Spanner => return (K, (Box, C, A, 34.0 + 10.0 * Z, 5.0), Bump, T);
            when Oil_Stain => return (K, (Ellipse, C, A, 34.0 + 26.0 * Z, 22.0 + 14.0 * Z), Water, T);
            when Drain => return (K, (Box, C, A, 24.0, 24.0), Floor, T);
            when Xmas_Tree => return (K, (Circle, C, A, 120.0, 0.0), Solid, T);
            when Bauble => return (K, (Circle, C, A, 9.0 + 4.0 * Z, 0.0), Solid, T);
            when Candy_Cane => return (K, (Box, C, A, 34.0 + 8.0 * Z, 4.0), Solid, T);
            when Needles => return (K, (Ellipse, C, A, 30.0 + 20.0 * Z, 22.0 + 12.0 * Z), Sand, T);
            when Crater => return (K, (Circle, C, A, 30.0 + 30.0 * Z, 0.0), Sand, T);
            when Moon_Rock => return (K, (Circle, C, A, 12.0 + 16.0 * Z, 0.0), Solid, T);
            when Lander => return (K, (Circle, C, A, 46.0 + 8.0 * Z, 0.0), Solid, T);
            when Flag => return (K, (Circle, C, A, 6.0, 0.0), Solid, T);
            when Dome => return (K, (Circle, C, A, 50.0 + 15.0 * Z, 0.0), Solid, T);
            when Pumpkin => return (K, (Circle, C, A, 18.0 + 10.0 * Z, 0.0), Solid, T);
            when Gravestone => return (K, (Box, C, A, 14.0 + 4.0 * Z, 24.0 + 6.0 * Z), Solid, T);
            when Cauldron => return (K, (Circle, C, A, 34.0 + 6.0 * Z, 0.0), Solid, T);
            when Candle => return (K, (Circle, C, A, 7.0 + 2.0 * Z, 0.0), Solid, T);
            when Fog => return (K, (Ellipse, C, A, 50.0 + 30.0 * Z, 30.0 + 20.0 * Z), Sand, T);
            when Easter_Egg => return (K, (Ellipse, C, A, 16.0 + 5.0 * Z, 11.0 + 3.0 * Z), Solid, T);
            when Choc_Bunny => return (K, (Ellipse, C, A, 22.0 + 4.0 * Z, 15.0 + 3.0 * Z), Solid, T);
            when Basket => return (K, (Circle, C, A, 30.0 + 6.0 * Z, 0.0), Solid, T);
            when Daffodil => return (K, (Circle, C, A, 10.0 + 4.0 * Z, 0.0), Floor, T);
            when Nest => return (K, (Circle, C, A, 30.0 + 14.0 * Z, 0.0), Sand, T);
            when Pawn => return (K, (Circle, C, A, 15.0, 0.0), Solid, T);
            when Rook => return (K, (Circle, C, A, 19.0, 0.0), Solid, T);
            when Knight_Piece => return (K, (Circle, C, A, 19.0, 0.0), Solid, T);
            when Bishop => return (K, (Circle, C, A, 18.0, 0.0), Solid, T);
            when Queen => return (K, (Circle, C, A, 21.0, 0.0), Solid, T);
            when King => return (K, (Circle, C, A, 22.0, 0.0), Solid, T);
            when Chess_Clock => return (K, (Box, C, A, 50.0, 26.0), Solid, T);
            when Crystal => return (K, (Circle, C, A, 14.0 + 10.0 * Z, 0.0), Solid, T);
            when Alien_Plant => return (K, (Circle, C, A, 18.0 + 10.0 * Z, 0.0), Solid, T);
            when Goo_Pool => return (K, (Ellipse, C, A, 34.0 + 26.0 * Z, 24.0 + 14.0 * Z), Water, T);
            when Egg_Pod => return (K, (Ellipse, C, A, 16.0 + 6.0 * Z, 12.0 + 4.0 * Z), Solid, T);
            when Spire => return (K, (Circle, C, A, 20.0 + 12.0 * Z, 0.0), Solid, T);
            when Spores => return (K, (Ellipse, C, A, 34.0 + 20.0 * Z, 24.0 + 12.0 * Z), Sand, T);
            when Igloo => return (K, (Circle, C, A, 44.0 + 10.0 * Z, 0.0), Solid, T);
            when Ice_Block => return (K, (Box, C, A, 14.0 + 6.0 * Z, 12.0 + 4.0 * Z), Solid, T);
            when Seal => return (K, (Ellipse, C, A, 26.0 + 6.0 * Z, 12.0 + 3.0 * Z), Solid, T);
            when Ice_Patch => return (K, (Ellipse, C, A, 50.0 + 30.0 * Z, 32.0 + 16.0 * Z), Water, T);
            when Fish_Hole => return (K, (Circle, C, A, 18.0 + 4.0 * Z, 0.0), Void, T);
            when others => return (K, (Circle, C, A, 10.0, 0.0), Floor, T);
         end case;
      end Make;

      function Clear_Of_Road (It : Item) return Boolean is
         E : constant Float := Extent (It.S);
         Gap : constant Float :=
           (case It.Mat is
               when Solid => 16.0,
               when Void => 34.0,
               when Floor => 2.0,
               when others => 6.0);
         X0, Y0, X1, Y1 : Float;
      begin
         if Has_Table then
            X0 := Table_X0; Y0 := Table_Y0; X1 := Table_X1; Y1 := Table_Y1;
         else
            X0 := 0.0; Y0 := 0.0; X1 := World_W; Y1 := World_H;
         end if;
         if It.S.C.X - E < X0 + 12.0 or else It.S.C.X + E > X1 - 12.0
           or else It.S.C.Y - E < Y0 + 12.0 or else It.S.C.Y + E > Y1 - 12.0
         then
            return False;
         end if;
         if not Below (It.Kind) then
            for J in 0 .. N_Samples - 1 loop
               if Distance (It.S.C, Samples (J).P) < E + Samples (J).Width * 0.5 + Gap then
                  return False;
               end if;
            end loop;
         end if;
         for J in 1 .. N_Items loop
            if Below (It.Kind) = Below (Items (J).Kind)
              and then Distance (It.S.C, Items (J).S.C) < E + Extent (Items (J).S) + 8.0
            then
               return False;
            end if;
         end loop;
         return True;
      end Clear_Of_Road;

   begin
      if Def.Theme = Pool then
         --  the six pockets of the table
         for K in 0 .. 5 loop
            declare
               X : constant Float := (case K mod 3 is when 0 => 70.0, when 1 => World_W * 0.5, when others => World_W - 70.0);
               Y : constant Float := (if K < 3 then 70.0 else World_H - 70.0);
            begin
               Add ((Pocket, (Circle, (X, Y), 0.0, 40.0, 0.0), Void, 0.5));
            end;
         end loop;
      end if;
      if Def.Theme = Xmas then
         --  the tree, in the middle of the room
         declare
            Mid : Vec := Zero;
         begin
            for K in 0 .. N_Samples - 1 loop
               Mid := Mid + Samples (K).P;
            end loop;
            Mid := Mid / Float (N_Samples);
            Add ((Xmas_Tree, (Circle, Mid, 0.0, 120.0, 0.0), Solid, 0.5));
         end;
      end if;
      if Def.Theme = Mud then
         --  stacks of tyres round the outside of the bends
         for K in 0 .. N_Samples - 1 loop
            if K mod 4 = 0 and then abs Samples (K).Turn > 0.0035 then
               declare
                  S : constant Sample := Samples (K);
                  Out_Side : constant Float := (if S.Turn > 0.0 then -1.0 else 1.0);
                  C : constant Vec := S.P + Perp (S.T) * (Out_Side * (S.Width * 0.5 + 24.0));
                  Ok : Boolean := True;
               begin
                  for J in 0 .. N_Samples - 1 loop
                     if Distance (C, Samples (J).P) < Samples (J).Width * 0.5 + 16.0 then
                        Ok := False;
                     end if;
                  end loop;
                  if Ok then
                     Add ((Tyre_Stack, (Circle, C, 0.0, 12.0, 0.0), Solid, Random (R)));
                  end if;
               end;
            end if;
         end loop;
      end if;
      while Placed < Def.Clutter and then Tries < 6000 loop
         Tries := Tries + 1;
         declare
            S : constant Sample := Get (Integer (Random (R) * Float (N_Samples)));
            Side : constant Float := (if Random (R) < 0.5 then -1.0 else 1.0);
            K : constant Item_Kind :=
              Pick ((case Def.Theme is
                        when Workbench => Bench,
                        when Garden => Yard,
                        when Ice => Frost,
                        when Bath => Tub,
                        when Bedroom => Room,
                        when Sky => Air,
                        when Kitchen => Cook,
                        when Mud => Yard_MX,
                        when Fish_Tank => Aquarium,
                        when Attic => Loft,
                        when Party => Birthday,
                        when Garage => Workshop,
                        when Xmas => Christmas,
                        when Moon => Lunar,
                        when Halloween => Spooky,
                        when Easter => Spring,
                        when Chess => Board,
                        when Alien => Planet,
                        when Arctic => Polar,
                        when Pool => Table_Top,
                        when Desk => School,
                        when Beach => Seaside,
                        when Toy_Town => Model));
            Off : constant Float := S.Width * 0.5 + 12.0 + Random (R) ** 1.5 * 380.0
              - (if Below (K) then S.Width * 0.6 else 0.0);
            It : constant Item := Make (K, S.P + Perp (S.T) * (Side * (Off + 20.0)));
         begin
            if Clear_Of_Road (It) then
               Add (It);
               Placed := Placed + 1;
            end if;
         end;
      end loop;
   end Add_Clutter;

   procedure Add_Movers (Def : Definition) is
      R : Seed := Def.Seed_0 * 13 + 1;
      Kind : Mover_Kind;
      Count : Natural;
      Radius, Period : Float;
   begin
      N_Movers := 0;
      case Def.Theme is
         when Workbench => Kind := Marble; Count := 1; Radius := 14.0; Period := 5.0;
         when Garden => Kind := Frog; Count := 2; Radius := 12.0; Period := 9.0;
         when Ice => Kind := Puck; Count := 1; Radius := 11.0; Period := 2.8;
         when Bath => Kind := Drifting_Duck; Count := 1; Radius := 20.0; Period := 11.0;
         when Bedroom => Kind := Paper_Plane; Count := 1; Radius := 16.0; Period := 6.0;
         when Sky => Kind := Bird; Count := 2; Radius := 14.0; Period := 5.0;
         when Kitchen => Kind := Tennis_Ball; Count := 1; Radius := 16.0; Period := 4.5;
         when Mud => Kind := Chicken; Count := 2; Radius := 12.0; Period := 10.0;
         when Pool => Kind := Pool_Ball; Count := 3; Radius := 14.0; Period := 5.0;
         when Desk => Kind := Robot; Count := 1; Radius := 16.0; Period := 14.0;
         when Beach => Kind := Crab; Count := 2; Radius := 12.0; Period := 8.0;
         when Toy_Town => Kind := Train; Count := 1; Radius := 11.0; Period := 10.0;
         when Fish_Tank => Kind := Fish; Count := 2; Radius := 14.0; Period := 7.0;
         when Attic => Kind := Mouse; Count := 1; Radius := 10.0; Period := 3.5;
         when Party => Kind := Bouncy_Ball; Count := 1; Radius := 14.0; Period := 6.0;
         when Garage => Kind := RC_Car; Count := 1; Radius := 13.0; Period := 3.2;
         when Xmas => Kind := Rolling_Bauble; Count := 1; Radius := 13.0; Period := 5.0;
         when Moon => Kind := Astronaut; Count := 1; Radius := 13.0; Period := 14.0;
         when Halloween => Kind := Bat; Count := 2; Radius := 14.0; Period := 5.0;
         when Easter => Kind := Bunny; Count := 2; Radius := 12.0; Period := 9.0;
         when Chess => Kind := Knight_Hop; Count := 1; Radius := 16.0; Period := 8.0;
         when Alien => Kind := Blob; Count := 2; Radius := 16.0; Period := 12.0;
         when Arctic => Kind := Penguin; Count := 3; Radius := 11.0; Period := 8.0;
      end case;
      if Def.Hazards > 0 then
         Count := Def.Hazards;
      end if;
      if Def.Theme = Arctic then
         --  a polar bear, lumbering across on a straight of its own
         declare
            S : constant Sample := Get (N_Samples * 3 / 5);
            Across : constant Vec := Perp (S.T) * (S.Width * 0.5 + 70.0);
         begin
            N_Movers := N_Movers + 1;
            Movers (N_Movers) := (Polar_Bear, S.P - Across, S.P + Across, 18.0, 4.0, 26.0);
         end;
      end if;
      if Def.Theme = Halloween then
         --  two ghosts drifting to and fro over the course, as well as the bats
         for K in 1 .. 2 loop
            declare
               S : constant Sample := Get (N_Samples * (2 * K - 1) / 4 + N_Samples / 10);
               Across : constant Vec := Perp (S.T) * (S.Width * 0.5 + 60.0);
            begin
               N_Movers := N_Movers + 1;
               Movers (N_Movers) := (Ghost, S.P - Across, S.P + Across, 9.0 + 2.0 * Float (K), Float (K) * 3.0, 24.0);
            end;
         end loop;
      end if;
      if Def.Theme = Xmas then
         --  the toy train round the tree, in the middle of the room
         for I in 1 .. N_Items loop
            if Items (I).Kind = Xmas_Tree then
               N_Movers := N_Movers + 1;
               Movers (N_Movers) := (Circle_Train, Items (I).S.C, (Items (I).S.RX + 55.0, 0.0), 16.0, 0.0, 11.0);
            end if;
         end loop;
      end if;
      for K in 1 .. Count loop
         --  across a straight part, away from the start
         declare
            Best : Integer := N_Samples / 2;
            Best_Turn : Float := Float'Last;
         begin
            for Tries in 1 .. 40 loop
               declare
                  J : constant Integer :=
                    Integer ((0.2 + 0.7 * (Float (K - 1) + Random (R)) / Float (Count)) * Float (N_Samples));
                  T : Float := 0.0;
                  Clear : Boolean := True;
               begin
                  for D in -12 .. 12 loop
                     T := T + abs Get (J + D).Turn;
                  end loop;
                  for I in 1 .. N_Items loop
                     if Items (I).Mat in Ramp | Boost | Void
                       and then Distance (Items (I).S.C, Get (J).P) < 160.0
                     then
                        Clear := False;
                     end if;
                  end loop;
                  if Kind = Train then
                     --  its rails must cross the road here and nowhere else
                     declare
                        S : constant Sample := Get (J);
                        Half : constant Float := S.Width * 0.5 + 260.0 + Train_Length * 0.6;
                     begin
                        for Q in 0 .. N_Samples - 1 loop
                           declare
                              Gap : constant Integer := abs (Q - J mod N_Samples);
                              Round : constant Integer := Integer'Min (Gap, N_Samples - Gap);
                              D : constant Vec := Samples (Q).P - S.P;
                              Along : constant Float := Dot (D, Perp (S.T));
                              Off : constant Float := abs Dot (D, S.T);
                           begin
                              if Round > 25 and then abs Along < Half + Samples (Q).Width * 0.5
                                and then Off < Samples (Q).Width * 0.5 + 70.0
                              then
                                 Clear := False;
                              end if;
                           end;
                        end loop;
                     end;
                  end if;
                  if Clear and then T < Best_Turn then
                     Best_Turn := T;
                     Best := J;
                  end if;
               end;
            end loop;
            declare
               S : constant Sample := Get (Best);
               Across : constant Vec := Perp (S.T) * (S.Width * 0.5 + (if Kind = Train then 260.0 else 45.0));
               Beat : constant Float := Period * (0.9 + 0.2 * Random (R));
               Phase : constant Float := Random (R) * Period;
            begin
               N_Movers := N_Movers + 1;
               Movers (N_Movers) := (Kind, S.P - Across, S.P + Across, Beat, Phase, Radius);
            end;
         end;
      end loop;
   end Add_Movers;

   procedure Shape_Path (Cr : Cairo_Context; S : Shape) is
   begin
      Save (Cr);
      Translate (Cr, Gdouble (S.C.X), Gdouble (S.C.Y));
      Rotate (Cr, Gdouble (S.A));
      case S.Kind is
         when Circle =>
            Arc (Cr, 0.0, 0.0, Gdouble (S.RX), 0.0, 2.0 * Pi);
         when Box =>
            Rectangle (Cr, Gdouble (-S.RX), Gdouble (-S.RY), Gdouble (2.0 * S.RX), Gdouble (2.0 * S.RY));
         when Ellipse =>
            Scale (Cr, Gdouble (S.RX), Gdouble (S.RY));
            Arc (Cr, 0.0, 0.0, 1.0, 0.0, 2.0 * Pi);
      end case;
      Restore (Cr);
   end Shape_Path;

   procedure Build_Map is
      use Cairo.Image_Surface;
      Surf : Cairo_Surface;
      Cr : Cairo_Context;
      procedure Use_Material (M : Material) is
      begin
         Set_Source_Rgba (Cr, 0.0, 0.0, 0.0, Gdouble (Material'Pos (M) * 20) / 255.0);
      end Use_Material;
      procedure Items_Of (Solids : Boolean) is
      begin
         for I in 1 .. N_Items loop
            if (Items (I).Mat = Solid) = Solids then
               New_Path (Cr);
               Shape_Path (Cr, Items (I).S);
               Use_Material (Items (I).Mat);
               Fill (Cr);
            end if;
         end loop;
      end Items_Of;
   begin
      Map_W := Natural (Float'Ceiling (World_W / Cell));
      Map_H := Natural (Float'Ceiling (World_H / Cell));
      Surf := Create (Cairo_Format_A8, Gint (Map_W), Gint (Map_H));
      Cr := Create (Surf);
      Set_Antialias (Cr, Cairo_Antialias_None);
      Set_Operator (Cr, Cairo_Operator_Source);
      Scale (Cr, Gdouble (1.0 / Cell), Gdouble (1.0 / Cell));

      if Has_Table then
         Use_Material (Void);
         Paint (Cr);
         Use_Material (Floor);
         Rectangle (Cr, Gdouble (Table_X0), Gdouble (Table_Y0),
                    Gdouble (Table_X1 - Table_X0), Gdouble (Table_Y1 - Table_Y0));
         Fill (Cr);
      else
         Use_Material ((if Walled then Sand else Floor));
         Paint (Cr);
      end if;
      --  The road: a disc at every sample
      Use_Material (Road);
      New_Path (Cr);
      for K in 0 .. N_Samples - 1 loop
         New_Sub_Path (Cr);
         Arc (Cr, Gdouble (Samples (K).P.X), Gdouble (Samples (K).P.Y),
              Gdouble (Samples (K).Width * 0.5), 0.0, 2.0 * Pi);
      end loop;
      Set_Fill_Rule (Cr, Cairo_Fill_Rule_Winding);
      Fill (Cr);
      Items_Of (Solids => False);
      Items_Of (Solids => True);
      if not Has_Table then
         --  the hedge or the snow bank round the edge
         Use_Material (Solid);
         Set_Line_Width (Cr, 52.0);
         Rectangle (Cr, 0.0, 0.0, Gdouble (World_W), Gdouble (World_H));
         Stroke (Cr);
      end if;
      Destroy (Cr);
      Cairo.Surface.Flush (Surf);

      declare
         use Interfaces;
         Stride : constant Natural := Natural (Get_Stride (Surf));
         type Bytes is array (0 .. Stride * Map_H - 1) of Unsigned_8;
         Data : Bytes with Import, Address => Get_Data_Generic (Surf);
      begin
         if Map /= null and then Map'Length /= Map_W * Map_H then
            Map := null;   --  a few megabytes, left to the end of the program
         end if;
         if Map = null then
            Map := new Material_Array (0 .. Map_W * Map_H - 1);
         end if;
         for Y in 0 .. Map_H - 1 loop
            for X in 0 .. Map_W - 1 loop
               declare
                  V : constant Natural := (Natural (Data (Y * Stride + X)) + 10) / 20;
               begin
                  Map (Y * Map_W + X) := (if V <= Material'Pos (Material'Last) then Material'Val (V) else Floor);
               end;
            end loop;
         end loop;
      end;
      Cairo.Surface.Destroy (Surf);
   end Build_Map;

   procedure Load_From (Id : Track_Id; Def : Definition; Pts : Point_List);

   procedure Load (Id : Track_Id) is
   begin
      if Is_Custom (Id) then
         declare
            S : Slot_Data renames Slots (Slot_Of (Id));
         begin
            if S.Count < 4 then
               --  never made: a plain loop
               declare
                  Keep_P : constant Control_List := Custom_Points;
                  Keep_N : constant Natural := Custom_Count;
               begin
                  Default_Custom;
                  S.Points := Custom_Points;
                  S.Count := Custom_Count;
                  Custom_Points := Keep_P;
                  Custom_Count := Keep_N;
               end;
            end if;
            declare
               Custom_List : Point_List (1 .. S.Count);
            begin
               for K in Custom_List'Range loop
                  Custom_List (K) := (S.Points (K).X, S.Points (K).Y, S.Points (K).W);
               end loop;
               Load_From (Id, (Custom_Name'Access, S.Theme, null, No_Features'Access, 70, Seed (101 + Slot_Of (Id)), others => <>),
                          Custom_List);
            end;
         end;
      else
         Load_From (Id, Defs (Id), Defs (Id).Points.all);
      end if;
   end Load;

   procedure Load_From (Id : Track_Id; Def : Definition; Pts : Point_List) is
      Min_X, Min_Y : Float := Float'Last;
      Max_X, Max_Y : Float := Float'First;
      Margin : constant Float := (if Def.Theme = Workbench then 110.0 else 230.0);
      Below : constant Float := 170.0;   --  the floor round the table
      Shift : Vec;
   begin
      Loaded := Id;
      N_Items := 0;
      Walled := Def.Walls;
      Make_Samples (Pts);
      for K in 0 .. N_Samples - 1 loop
         Min_X := Float'Min (Min_X, Samples (K).P.X - Samples (K).Width * 0.5);
         Min_Y := Float'Min (Min_Y, Samples (K).P.Y - Samples (K).Width * 0.5);
         Max_X := Float'Max (Max_X, Samples (K).P.X + Samples (K).Width * 0.5);
         Max_Y := Float'Max (Max_Y, Samples (K).P.Y + Samples (K).Width * 0.5);
      end loop;
      if Def.Theme = Workbench then
         Shift := (Below + Margin - Min_X, Below + Margin - Min_Y);
         World_W := Max_X - Min_X + 2.0 * (Margin + Below);
         World_H := Max_Y - Min_Y + 2.0 * (Margin + Below);
         Table_X0 := Below;
         Table_Y0 := Below;
         Table_X1 := World_W - Below;
         Table_Y1 := World_H - Below;
      else
         Shift := (Margin - Min_X, Margin - Min_Y);
         World_W := Max_X - Min_X + 2.0 * Margin;
         World_H := Max_Y - Min_Y + 2.0 * Margin;
      end if;
      for K in 0 .. N_Samples - 1 loop
         Samples (K).P := Samples (K).P + Shift;
      end loop;
      Add_Features (Def);
      Add_Clutter (Def);
      Add_Movers (Def);
      Build_Map;
   end Load_From;

end Tracks;
